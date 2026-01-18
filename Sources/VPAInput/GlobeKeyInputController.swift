import Foundation
import VPACore
import Cocoa
import ApplicationServices

public final class GlobeKeyInputController: InputController {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?
    private var isPTTDown: Bool = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init() {}

    public func start(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> Bool {
        self.onPress = onPress
        self.onRelease = onRelease

        if !ensureAccessibilityPermission() {
            return false
        }

        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = UnsafeMutablePointer<CFMachPort>(OpaquePointer(refcon)) {
                    CGEvent.tapEnable(tap: tap.pointee, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            guard type == .flagsChanged || type == .keyDown || type == .keyUp else {
                return Unmanaged.passUnretained(event)
            }
            let controller = Unmanaged<GlobeKeyInputController>.fromOpaque(refcon!).takeUnretainedValue()
            controller.handleCGEvent(type: type, event: event, source: "cgeventtap")
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        )

        guard let eventTap else {
            return false
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)

        // NSEvent monitors as a fallback for Fn/Globe modifiers
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            self?.handleNSEvent(event, source: "nsevent-global")
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            self?.handleNSEvent(event, source: "nsevent-local")
            return event
        }

        return true
    }

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        runLoopSource = nil
        eventTap = nil
        globalMonitor = nil
        localMonitor = nil
        onPress = nil
        onRelease = nil
        isPTTDown = false
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent, source: String) {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if keycode == 63 {
            if type == .keyDown && !isPTTDown {
                isPTTDown = true
                if DebugFlags.input { print("vpa input: press (\(source), keyDown keycode=63)") }
                onPress?()
                return
            }
            if type == .keyUp && isPTTDown {
                isPTTDown = false
                if DebugFlags.input { print("vpa input: release (\(source), keyUp keycode=63)") }
                onRelease?()
                return
            }
        }

        if type == .flagsChanged {
            let functionDown = flags.contains(.maskSecondaryFn)
            if functionDown && !isPTTDown {
                isPTTDown = true
                if DebugFlags.input { print("vpa input: press (\(source), flagsChanged fn=down)") }
                onPress?()
            } else if !functionDown && isPTTDown {
                isPTTDown = false
                if DebugFlags.input { print("vpa input: release (\(source), flagsChanged fn=up)") }
                onRelease?()
            }
        }
    }

    private func handleNSEvent(_ event: NSEvent, source: String) {
        if event.type == .keyDown && event.keyCode == 63 && !isPTTDown {
            isPTTDown = true
            if DebugFlags.input { print("vpa input: press (\(source), keyDown keycode=63)") }
            onPress?()
            return
        }
        if event.type == .keyUp && event.keyCode == 63 && isPTTDown {
            isPTTDown = false
            if DebugFlags.input { print("vpa input: release (\(source), keyUp keycode=63)") }
            onRelease?()
            return
        }
        if event.type == .flagsChanged {
            let functionDown = event.modifierFlags.contains(.function)
            if functionDown && !isPTTDown {
                isPTTDown = true
                if DebugFlags.input { print("vpa input: press (\(source), flagsChanged fn=down)") }
                onPress?()
            } else if !functionDown && isPTTDown {
                isPTTDown = false
                if DebugFlags.input { print("vpa input: release (\(source), flagsChanged fn=up)") }
                onRelease?()
            }
        }
    }

    private func ensureAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        return AXIsProcessTrustedWithOptions(options)
    }
}
