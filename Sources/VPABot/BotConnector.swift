import Foundation
import VPACore
import VPAConfig

public protocol BotClient {
    func join(room: String, seat: Int)
    func createRoom(room: String)
    func fetchRules()
    func play(draw: String, meld: Bool, discard: String)
}

public final class BotConnector: BotClient {
    private let url: URL
    private let rulesURL: URL?
    private var task: URLSessionWebSocketTask?
    public var onRoomCreated: ((String, Int) -> Void)?
    public var onRules: ((String) -> Void)?
    public var onYourTurn: (([String: Any]) -> Void)?

    public init(url: URL, rulesURL: URL? = nil) {
        self.url = url
        self.rulesURL = rulesURL
    }

    public func join(room: String, seat: Int) {
        ensureConnected()
        let payload: [String: Any] = [
            "action": "join",
            "room": room,
            "seat": seat
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        if DebugFlags.input {
            print("vpa bot: send \(text)")
        }
        task?.send(.string(text)) { _ in }
    }

    public func createRoom(room: String) {
        ensureConnected()
        let payload: [String: Any] = [
            "action": "join",
            "room": room,
            "create": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        if DebugFlags.input {
            print("vpa bot: send \(text)")
        }
        task?.send(.string(text)) { _ in }
    }

    public func fetchRules() {
        guard let rulesURL else { return }
        let task = URLSession.shared.dataTask(with: rulesURL) { [weak self] data, _, _ in
            guard let self else { return }
            let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
            if DebugFlags.input, !text.isEmpty {
                print("vpa bot: rules \(text.prefix(200))")
            }
            self.onRules?(text)
        }
        task.resume()
    }

    public func play(draw: String, meld: Bool, discard: String) {
        ensureConnected()
        let payload: [String: Any] = [
            "action": "play",
            "draw": draw,
            "meld": meld,
            "discard": discard
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        if DebugFlags.input {
            print("vpa bot: send \(text)")
        }
        task?.send(.string(text)) { _ in }
    }

    private func ensureConnected() {
        if let task, task.state == .running { return }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop()
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
            case .failure:
                break
            }
            self.receiveLoop()
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard let type = json["type"] as? String else { return }
        if DebugFlags.input {
            let preview = text.count > 800 ? String(text.prefix(800)) + "…" : text
            print("vpa bot: recv \(preview)")
        }
        if type == "room_created" {
            let room = json["room"] as? String ?? ""
            let playerIndex = json["playerIndex"] as? Int ?? 0
            onRoomCreated?(room, playerIndex)
        }
        if type == "your_turn" {
            onYourTurn?(json)
        }
        if type == "your_turn" || type == "state" {
            let phase = (json["phase"] as? String) ?? ""
            if DebugFlags.input {
                let expected = expectedNextPhase(for: phase)
                print("vpa bot: phase=\(phase) expected_next=\(expected)")
            }
        }
    }

    private func expectedNextPhase(for phase: String) -> String {
        switch phase {
        case "await_draw":
            return "await_discard"
        case "await_discard":
            return "action_accepted or next_turn"
        default:
            return "unknown"
        }
    }
}

public enum BotConnectorFactory {
    public static func from(config: VPAConfig?, onRoomCreated: ((String, Int) -> Void)? = nil, onRules: ((String) -> Void)? = nil, onYourTurn: (([String: Any]) -> Void)? = nil) -> BotClient? {
        guard let bot = config?.bot else { return nil }
        guard let url = URL(string: bot.wsURL) else { return nil }
        let rulesURL = bot.rulesURL.flatMap { URL(string: $0) }
        let connector = BotConnector(url: url, rulesURL: rulesURL)
        connector.onRoomCreated = onRoomCreated
        connector.onRules = onRules
        connector.onYourTurn = onYourTurn
        return connector
    }
}
