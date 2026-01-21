import Foundation
import VPACore
import VPAConfig

public protocol BotClient {
    func join(room: String, seat: Int)
    func createRoom(room: String)
    func fetchRules()
    func requestCandidates(state: [String: Any], completion: @escaping ([[String: Any]]?) -> Void)
    func requestMove(state: [String: Any], candidates: [[String: Any]]?, advice: [String: Any], completion: @escaping (BotMove?) -> Void)
    func play(draw: String, meld: Bool, discard: String)
}

public struct BotMove {
    public let draw: String
    public let meld: Bool
    public let discard: String

    public init(draw: String, meld: Bool, discard: String) {
        self.draw = draw
        self.meld = meld
        self.discard = discard
    }
}

public final class BotConnector: BotClient {
    private let url: URL
    private let rulesURL: URL?
    private var task: URLSessionWebSocketTask?
    private var pendingCandidates: (([[String: Any]]?) -> Void)?
    private var pendingEngineMove: ((BotMove?) -> Void)?
    private var currentSeat: Int?
    private var lastTurnKey: String?
    private var pendingCandidatesKey: String?
    private var candidatesHashes: [String: String] = [:]
    private var candidatesProcessed: [String: Bool] = [:]
    private var strategySent: [String: Bool] = [:]
    public var onRoomCreated: ((String, Int) -> Void)?
    public var onRules: ((String) -> Void)?
    public var onYourTurn: (([String: Any]) -> Void)?
    public var onStrategyInvalid: ((String) -> Void)?

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

    public func requestCandidates(state: [String: Any], completion: @escaping ([[String: Any]]?) -> Void) {
        ensureConnected()
        pendingCandidates = completion
        let key = turnKey(from: state)
        pendingCandidatesKey = key
        if let key {
            candidatesHashes[key] = nil
            candidatesProcessed[key] = false
            strategySent[key] = false
        }
        let payload: [String: Any] = [
            "action": "candidates",
            "state": state
        ]
        send(payload: payload)
    }

    public func requestMove(state: [String: Any], candidates: [[String: Any]]?, advice: [String: Any], completion: @escaping (BotMove?) -> Void) {
        ensureConnected()
        let key = turnKey(from: state)
        guard let key, let hash = candidatesHashes[key] else {
            if DebugFlags.input {
                print("vpa bot: missing candidates_hash; re-requesting candidates")
            }
            onStrategyInvalid?("missing candidates_hash")
            completion(nil)
            return
        }
        strategySent[key] = true
        pendingEngineMove = completion
        var payload: [String: Any] = [
            "action": "strategy",
            "state": state,
            "advice": advice,
            "candidates_hash": hash
        ]
        if let candidates {
            payload["candidates"] = candidates
        }
        send(payload: payload)
    }

    public func play(draw: String, meld: Bool, discard: String) {
        ensureConnected()
        let payload: [String: Any] = [
            "action": "play",
            "draw": draw,
            "meld": meld,
            "discard": discard
        ]
        send(payload: payload)
    }

    private func send(payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        if DebugFlags.input {
            if let action = payload["action"] as? String, action == "candidates" || action == "strategy" {
                let hash = payload["candidates_hash"] as? String ?? ""
                let count = (payload["candidates"] as? [Any])?.count ?? 0
                let note = hash.isEmpty ? "" : " hash=\(hash)"
                print("vpa bot: send action=\(action)\(note) candidates=\(count)")
            } else {
                print("vpa bot: send \(text)")
            }
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
            if type == "candidates" {
                let hash = json["candidates_hash"] as? String ?? ""
                let count = (json["candidates"] as? [Any])?.count ?? 0
                print("vpa bot: recv candidates hash=\(hash) count=\(count)")
            } else if type == "your_turn" || type == "state" {
                let room = json["room"] as? String ?? ""
                let phase = json["phase"] as? String ?? ""
                print("vpa bot: recv type=\(type) room=\(room) phase=\(phase)")
            } else if type == "error" {
                let message = json["message"] as? String ?? ""
                print("vpa bot: recv error \(message)")
            } else {
                let preview = text.count > 800 ? String(text.prefix(800)) + "…" : text
                print("vpa bot: recv \(preview)")
            }
        }
        if type == "room_created" {
            let room = json["room"] as? String ?? ""
            let playerIndex = json["playerIndex"] as? Int ?? 0
            onRoomCreated?(room, playerIndex)
        }
        if type == "joined" {
            if let seat = json["seat"] as? Int {
                currentSeat = seat
            }
        }
        if type == "your_turn" {
            lastTurnKey = turnKey(from: json)
            if let key = lastTurnKey {
                candidatesHashes[key] = nil
                candidatesProcessed[key] = false
                strategySent[key] = false
            }
            onYourTurn?(json)
        }
        if type == "candidates" {
            let candidates = json["candidates"] as? [[String: Any]]
            let hash = json["candidates_hash"] as? String ?? ""
            let key = pendingCandidatesKey ?? lastTurnKey
            if let key, !hash.isEmpty {
                if let current = candidatesHashes[key],
                   current == hash,
                   candidatesProcessed[key] == true || strategySent[key] == true {
                    if DebugFlags.input {
                        print("vpa bot: duplicate candidates hash=\(hash); ignoring")
                    }
                    return
                }
                candidatesHashes[key] = hash
            }
            pendingCandidatesKey = nil
            let handler = pendingCandidates
            pendingCandidates = nil
            if let key {
                candidatesProcessed[key] = true
            }
            handler?(candidates)
        }
        if type == "engine_move" {
            let movePayload = (json["move"] as? [String: Any]) ?? json
            let draw = movePayload["draw"] as? String ?? "deck"
            let meld = movePayload["meld"] as? Bool ?? false
            let discard = movePayload["discard"] as? String ?? ""
            let move = discard.isEmpty ? nil : BotMove(draw: draw, meld: meld, discard: discard)
            let handler = pendingEngineMove
            pendingEngineMove = nil
            handler?(move)
        }
        if type == "your_turn" || type == "state" {
            let phase = (json["phase"] as? String) ?? ""
            if DebugFlags.input {
                let expected = expectedNextPhase(for: phase)
                print("vpa bot: phase=\(phase) expected_next=\(expected)")
            }
        }
        if type == "state" {
            let current = json["currentPlayerIndex"] as? Int ?? json["current_player_index"] as? Int
            if let seat = currentSeat, current == seat {
                lastTurnKey = turnKey(from: json)
                if let key = lastTurnKey {
                    candidatesHashes[key] = nil
                    candidatesProcessed[key] = false
                    strategySent[key] = false
                }
                onYourTurn?(json)
            }
        }
        if type == "error" {
            let message = (json["message"] as? String) ?? ""
            let lower = message.lowercased()
            if lower.contains("hash") || lower.contains("stale") || lower.contains("strategy") {
                if let key = lastTurnKey {
                    candidatesHashes[key] = nil
                    candidatesProcessed[key] = false
                    strategySent[key] = false
                }
                onStrategyInvalid?(message)
            }
        }
    }

    private func turnKey(from state: [String: Any]) -> String? {
        let room = (state["room"] as? String) ?? ""
        let round = (state["round_number"] as? Int) ?? (state["roundNumber"] as? Int)
        let phase = (state["phase"] as? String) ?? ""
        let seat = (state["seat"] as? Int) ?? currentSeat
        if room.isEmpty || seat == nil { return nil }
        let roundLabel = round == nil ? "?" : "\(round!)"
        return "\(room)|\(seat!)|\(roundLabel)|\(phase)"
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
    public static func from(config: VPAConfig?, onRoomCreated: ((String, Int) -> Void)? = nil, onRules: ((String) -> Void)? = nil, onYourTurn: (([String: Any]) -> Void)? = nil, onStrategyInvalid: ((String) -> Void)? = nil) -> BotClient? {
        guard let bot = config?.bot else { return nil }
        guard let url = URL(string: bot.wsURL) else { return nil }
        let rulesURL = bot.rulesURL.flatMap { URL(string: $0) }
        let connector = BotConnector(url: url, rulesURL: rulesURL)
        connector.onRoomCreated = onRoomCreated
        connector.onRules = onRules
        connector.onYourTurn = onYourTurn
        connector.onStrategyInvalid = onStrategyInvalid
        return connector
    }
}
