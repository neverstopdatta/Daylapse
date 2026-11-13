import Foundation

@MainActor
final class CaptureEngine {
    private let settings: SettingsStore
    private let capture: () async -> Void
    private let pauseReason: () -> AppRules.Pause?
    private let render: (String) -> Void
    private var timer: Timer?
    private var nextCapture: Date?
    private var pausedRemaining: TimeInterval?
    // Time left on the countdown when stopped, so the next start resumes instead of restarting.
    private var resumeRemaining: TimeInterval?
    private var scheduledInterval: TimeInterval?
    private var pendingStartCapture = false
    private var captureInFlight = false
    private var activity: NSObjectProtocol?
    private var lastStatus = ""
    private(set) var isStarted = false
    var isMenuOpen = false {
        didSet { tick() }
    }
    // The Settings window counts like the open menu for "Pause while menu is open".
    var isSettingsActive = false {
        didSet { tick() }
    }

    init(
        settings: SettingsStore,
        capture: @escaping () async -> Void,
        pauseReason: @escaping () -> AppRules.Pause?,
        render: @escaping (String) -> Void
    ) {
        self.settings = settings
        self.capture = capture
        self.pauseReason = pauseReason
        self.render = render
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Screenshots Timelapse screenshot timer"
        )
        SSTLLog.write("Capture started")
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Common modes keep the timer firing while the status menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if pauseReason() == nil {
            let interval = TimeInterval(max(1, settings.settings.intervalSeconds))
            if let resume = resumeRemaining {
                nextCapture = Date().addingTimeInterval(min(resume, interval))
            } else {
                if settings.settings.captureOnStart {
                    // A held countdown wins: the first shot waits until the menu or Settings is dismissed.
                    if isHeldByMenu { pendingStartCapture = true } else { performCapture() }
                }
                nextCapture = Date().addingTimeInterval(interval)
            }
        } else if let resume = resumeRemaining {
            pausedRemaining = resume
        }
        resumeRemaining = nil
        tick()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        resumeRemaining = settings.settings.resumeCountdown
            ? pausedRemaining ?? nextCapture.map { max(1, $0.timeIntervalSinceNow) }
            : nil
        timer?.invalidate()
        timer = nil
        nextCapture = nil
        pendingStartCapture = false
        scheduledInterval = nil
        pausedRemaining = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        SSTLLog.write("Capture stopped")
        setStatus("○")
    }

    func toggle() {
        isStarted ? stop() : start()
    }

    private func tick() {
        guard isStarted else {
            render("○")
            return
        }
        if let reason = pauseReason() {
            holdCountdown()
            setStatus(reason.statusText)
            return
        }
        if isHeldByMenu {
            holdCountdown()
            let remaining = pausedRemaining ?? TimeInterval(max(1, settings.settings.intervalSeconds))
            setStatus("⏸ \(Self.compact(remaining))")
            return
        }
        if pendingStartCapture {
            pendingStartCapture = false
            performCapture()
            nextCapture = Date().addingTimeInterval(TimeInterval(max(1, settings.settings.intervalSeconds)))
        }
        if nextCapture == nil {
            let interval = TimeInterval(max(1, settings.settings.intervalSeconds))
            nextCapture = Date().addingTimeInterval(min(pausedRemaining ?? interval, interval))
            pausedRemaining = nil
        }
        let interval = TimeInterval(max(1, settings.settings.intervalSeconds))
        // Shift the pending shot by however much the interval changed, up or down.
        if let pending = nextCapture, let old = scheduledInterval, old != interval {
            nextCapture = max(Date(), pending.addingTimeInterval(interval - old))
        }
        scheduledInterval = interval
        if let nextCapture, Date() >= nextCapture, !captureInFlight {
            performCapture()
            // Step from the scheduled time, not from now, so ticks and capture time do not stretch the interval.
            let stepped = nextCapture.addingTimeInterval(interval)
            self.nextCapture = stepped > Date() ? stepped : Date().addingTimeInterval(interval)
        }
        setStatus("● \(Self.compact((nextCapture ?? Date()).timeIntervalSinceNow))")
    }

    // At most two digits plus a unit: 45s, 2m, 60m, 3h.
    private static func compact(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(remaining)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds <= 3600 { return "\((seconds + 59) / 60)m" }
        return "\((seconds + 3599) / 3600)h"
    }

    private var isHeldByMenu: Bool {
        (isMenuOpen || isSettingsActive) && settings.settings.pauseWhenMenuOpen
    }

    private func holdCountdown() {
        guard let nextCapture else { return }
        pausedRemaining = max(0, nextCapture.timeIntervalSinceNow)
        self.nextCapture = nil
    }

    private func performCapture() {
        guard !captureInFlight else { return }
        captureInFlight = true
        Task { [weak self] in
            guard let self else { return }
            await capture()
            captureInFlight = false
        }
    }

    private func setStatus(_ status: String) {
        guard lastStatus != status else { return }
        lastStatus = status
        SSTLLog.write("Status changed: \(status)")
        render(status)
    }
}
