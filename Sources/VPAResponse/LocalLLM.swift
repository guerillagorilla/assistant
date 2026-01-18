import Foundation
import VPACore
import VPAConfig

public final class LocalLLMClarifier {
    private let engine: LocalLLMEngine
    private let intentThreshold: Double

    public init(engine: LocalLLMEngine, intentThreshold: Double) {
        self.engine = engine
        self.intentThreshold = intentThreshold
    }

    public func maybeClarify(base: Response, transcript: Transcript, intentConfidence: Double, allowClarify: Bool = true) -> Response {
        if intentConfidence >= intentThreshold { return base }
        if !allowClarify { return base }
        switch base.type {
        case .failure, .clarification:
            return base
        case .success, .confirmation:
            break
        }

        if DebugFlags.llm {
            let conf = String(format: "%.2f", intentConfidence)
            print("vpa llm: clarifier invoked (intentConf=\(conf), threshold=\(intentThreshold))")
        }
        let prompt = buildPrompt(transcript: transcript, base: base)
        let output = engine.complete(prompt: prompt)
        if DebugFlags.llm {
            let preview = output.trimmingCharacters(in: .whitespacesAndNewlines)
            print("vpa llm: raw output: \(preview.prefix(200))")
        }
        return interpret(output: output, fallback: base)
    }

    private func buildPrompt(transcript: Transcript, base: Response) -> String {
        let rules = """
You are a clarification-only assistant. Output exactly one line using one of:
- CLARIFY: <short question to clarify intent, max 8 words>
- FAILURE: <short reprompt in-character, max 6 words>
- NONE

Rules:
- Do NOT answer questions.
- Do NOT confirm or execute actions.
- Do NOT be polite. No "please", no apologies.
- If the transcript is a greeting or simple statement, output NONE.
- If the question is clear, output NONE.
- Only clarify if a command is ambiguous or missing an object.
"""
        return """
\(rules)

TRANSCRIPT: "\(transcript.text)"
CONFIDENCE: \(String(format: "%.2f", transcript.confidence))
BASE_TYPE: \(base.type)
BASE_TEXT: "\(base.text)"
"""
    }

    private func interpret(output: String, fallback: Response) -> Response {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()
        if upper.hasPrefix("CLARIFY:") {
            let text = trimmed.dropFirst("CLARIFY:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return fallback }
            return Response(text: text, type: .clarification)
        }
        if upper.hasPrefix("FAILURE:") {
            let text = trimmed.dropFirst("FAILURE:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return fallback }
            return Response(text: text, type: .failure)
        }
        return fallback
    }
}

public final class LlamaCLILocalLLMEngine: LocalLLMEngine {
    private let config: VPAConfig.LLM

    public init(config: VPAConfig.LLM) {
        self.config = config
    }

    public func complete(prompt: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.cliPath)

        var args = config.args ?? []
        if let modelPath = config.modelPath, !modelPath.isEmpty {
            args.append(contentsOf: ["-m", modelPath])
        }
        if let maxTokens = config.maxTokens {
            args.append(contentsOf: ["-n", String(maxTokens)])
        }
        if let temperature = config.temperature {
            args.append(contentsOf: ["--temp", String(temperature)])
        }

        let useStdin = config.useStdin ?? false
        if !useStdin {
            args.append(contentsOf: ["-p", prompt])
        }
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        if useStdin {
            let stdin = Pipe()
            process.standardInput = stdin
            let payload = (prompt + "\n").data(using: .utf8) ?? Data()
            stdin.fileHandleForWriting.write(payload)
            stdin.fileHandleForWriting.closeFile()
        }

        do {
            try process.run()
        } catch {
            return ""
        }
        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outText = String(data: outData, encoding: .utf8) ?? ""
        if DebugFlags.llm, outText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let errText = String(data: errData, encoding: .utf8) ?? ""
            if !errText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("vpa llm: stderr: \(errText.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        return outText
    }
}

public final class OllamaCLILocalLLMEngine: LocalLLMEngine {
    private let config: VPAConfig.LLM

    public init(config: VPAConfig.LLM) {
        self.config = config
    }

    public func complete(prompt: String) -> String {
        let useStdinPreferred = config.useStdin ?? false
        let first = run(prompt: prompt, useStdin: useStdinPreferred)
        if !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || useStdinPreferred {
            return first
        }
        if DebugFlags.llm {
            print("vpa llm: empty stdout; retrying with stdin")
        }
        return run(prompt: prompt, useStdin: true)
    }

    private func run(prompt: String, useStdin: Bool) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.cliPath)

        let model = config.modelName ?? config.modelPath ?? "llama3.2:latest"
        var args = ["run", model]
        if let temperature = config.temperature {
            args.append(contentsOf: ["--temperature", String(temperature)])
        }
        if let maxTokens = config.maxTokens {
            args.append(contentsOf: ["--num-predict", String(maxTokens)])
        }
        if let extraArgs = config.args {
            args.append(contentsOf: extraArgs)
        }
        if !useStdin {
            args.append("--prompt")
            args.append(prompt)
        }
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        if useStdin {
            let stdin = Pipe()
            process.standardInput = stdin
            stdin.fileHandleForWriting.write(prompt.data(using: .utf8) ?? Data())
            stdin.fileHandleForWriting.closeFile()
        }

        if DebugFlags.llm {
            let promptLen = prompt.count
            print("vpa llm: ollama run model=\(model) stdin=\(useStdin) promptLen=\(promptLen)")
        }
        do {
            try process.run()
        } catch {
            return ""
        }
        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outText = String(data: outData, encoding: .utf8) ?? ""
        if DebugFlags.llm {
            let status = process.terminationStatus
            print("vpa llm: exit status \(status)")
        }
        if DebugFlags.llm, outText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let errText = String(data: errData, encoding: .utf8) ?? ""
            if !errText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("vpa llm: stderr: \(errText.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        return outText
    }
}

public final class OllamaHTTPLocalLLMEngine: LocalLLMEngine {
    private let config: VPAConfig.LLM

    public init(config: VPAConfig.LLM) {
        self.config = config
    }

    public func complete(prompt: String) -> String {
        let base = config.apiURL ?? "http://localhost:11434"
        guard let url = URL(string: base + "/api/generate") else {
            return ""
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let model = config.modelName ?? config.modelPath ?? "llama3.2:latest"
        var payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]
        var options: [String: Any] = [:]
        if let temperature = config.temperature {
            options["temperature"] = temperature
        }
        if let maxTokens = config.maxTokens {
            options["num_predict"] = maxTokens
        }
        if !options.isEmpty {
            payload["options"] = options
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            return ""
        }

        if DebugFlags.llm {
            print("vpa llm: http POST \(url.absoluteString) model=\(model)")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result = ""
        var statusCode: Int?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let http = response as? HTTPURLResponse {
                statusCode = http.statusCode
            }
            if let error {
                if DebugFlags.llm {
                    print("vpa llm: http error: \(error.localizedDescription)")
                }
                return
            }
            guard let data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["response"] as? String {
                result = text
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10)

        if DebugFlags.llm, let statusCode {
            print("vpa llm: http status \(statusCode)")
        }
        return result
    }
}
