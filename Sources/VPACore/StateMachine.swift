import Foundation

public enum AssistantState {
    case idle
    case listening
    case processing
    case speaking
    case interrupted
}

public protocol StateMachineObserver: AnyObject {
    func stateDidChange(_ newState: AssistantState)
}

public final class AssistantStateMachine {
    private(set) public var state: AssistantState = .idle {
        didSet { notify() }
    }

    private var observers: [WeakObserver] = []

    public init() {}

    public func addObserver(_ observer: StateMachineObserver) {
        observers.append(WeakObserver(observer))
    }

    public func transition(to newState: AssistantState) {
        state = newState
        observers = observers.filter { $0.observer != nil }
    }

    private func notify() {
        for wrapper in observers {
            wrapper.observer?.stateDidChange(state)
        }
    }
}

private struct WeakObserver {
    weak var observer: StateMachineObserver?
    init(_ observer: StateMachineObserver) { self.observer = observer }
}
