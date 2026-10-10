import AppKit
import Foundation
import Observation

@MainActor protocol SecurityClock { var now: TimeInterval { get } }
@MainActor struct UptimeClock: SecurityClock {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

@MainActor protocol SecretPasteboard {
    /// Returns ownership of this write without retaining or reading back the secret.
    func write(_ value: String) -> Int?
    func clear(ifOwnedBy changeCount: Int)
}

@MainActor final class SystemSecretPasteboard: SecretPasteboard {
    private let pasteboard: NSPasteboard
    init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    func write(_ value: String) -> Int? {
        let item = NSPasteboardItem()
        item.setString(value, forType: .string)
        // Community hints, not an enforcement boundary against clipboard history tools.
        item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        item.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
        let owner = pasteboard.clearContents()
        guard pasteboard.writeObjects([item]), pasteboard.changeCount == owner else { return nil }
        return owner
    }
    func clear(ifOwnedBy changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
    }
}

public enum AutomaticLockReason: Sendable { case inactivity, sleep, sessionChange }

/// A deterministic state machine; AppKit supplies events, and tests supply time/pasteboard.
@MainActor @Observable public final class SessionSecurity {
    public static let inactivityOptions = [0, 60, 300, 900, 1800]
    public static let clipboardOptions = [0, 15, 30, 60, 120]
    public var inactivitySeconds: Int {
        didSet {
            if !Self.inactivityOptions.contains(inactivitySeconds) { inactivitySeconds = 300 }
            defaults?.set(inactivitySeconds, forKey: "inactivitySeconds")
            tick()
        }
    }
    public var clipboardSeconds: Int {
        didSet {
            if !Self.clipboardOptions.contains(clipboardSeconds) { clipboardSeconds = 30 }
            defaults?.set(clipboardSeconds, forKey: "clipboardSeconds")
            tick()
        }
    }
    public private(set) var sessionActive = false
    @ObservationIgnored var onAutomaticLock: ((AutomaticLockReason) -> Void)?
    @ObservationIgnored private let clock: any SecurityClock
    @ObservationIgnored private let pasteboard: any SecretPasteboard
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var lastActivity: TimeInterval = 0
    @ObservationIgnored private var clipboardOwner: Int?
    @ObservationIgnored private var copiedAt: TimeInterval = 0

    public convenience init() {
        self.init(clock: UptimeClock(), pasteboard: SystemSecretPasteboard(), defaults: .standard)
    }
    init(clock: any SecurityClock, pasteboard: any SecretPasteboard, defaults: UserDefaults? = nil) {
        self.clock = clock; self.pasteboard = pasteboard; self.defaults = defaults
        let idle = defaults?.object(forKey: "inactivitySeconds") as? Int ?? 300
        let clipboard = defaults?.object(forKey: "clipboardSeconds") as? Int ?? 30
        inactivitySeconds = Self.inactivityOptions.contains(idle) ? idle : 300
        clipboardSeconds = Self.clipboardOptions.contains(clipboard) ? clipboard : 30
    }
    func beginSession() { sessionActive = true; lastActivity = clock.now }
    func endSession() { sessionActive = false; clearClipboard() }

    /// Check expiry before allowing an arriving event to renew the session.
    @discardableResult func recordActivity() -> Bool {
        let wasActive = sessionActive
        tick()
        if wasActive && !sessionActive { return false }
        if sessionActive { lastActivity = clock.now }
        return true
    }
    func tick() {
        if clipboardOwner != nil, clipboardSeconds > 0, clock.now - copiedAt >= Double(clipboardSeconds) {
            clearClipboard()
        }
        if sessionActive, inactivitySeconds > 0, clock.now - lastActivity >= Double(inactivitySeconds) {
            endSession()
            onAutomaticLock?(.inactivity)
        }
    }
    func systemWillSleep() { endSession(); onAutomaticLock?(.sleep) }
    func sessionDidResignActive() { endSession(); onAutomaticLock?(.sessionChange) }
    @discardableResult func copy(_ value: String) -> Bool {
        tick()
        guard sessionActive else { return false }
        guard let owner = pasteboard.write(value) else { return false }
        clipboardOwner = owner; copiedAt = clock.now
        return true
    }
    func clearClipboard() {
        if let owner = clipboardOwner { pasteboard.clear(ifOwnedBy: owner) }
        clipboardOwner = nil
    }
}

@MainActor final class AppSecurityMonitor {
    private let security: SessionSecurity
    private var timer: Timer?
    private var eventMonitor: Any?
    private var sleepObserver: NSObjectProtocol?
    private var sessionObserver: NSObjectProtocol?
    init(security: SessionSecurity) { self.security = security }
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.security.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            let allow = MainActor.assumeIsolated {
                guard event.window != nil else { return true }
                return self?.security.recordActivity() ?? true
            }
            return allow ? event : nil
        }
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.security.systemWillSleep() }
        }
        sessionObserver = center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.security.sessionDidResignActive() }
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }; eventMonitor = nil
        let center = NSWorkspace.shared.notificationCenter
        if let sleepObserver { center.removeObserver(sleepObserver) }; sleepObserver = nil
        if let sessionObserver { center.removeObserver(sessionObserver) }; sessionObserver = nil
        security.endSession()
    }
}
