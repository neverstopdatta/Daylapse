import Foundation

@MainActor
final class CaptureEngine {
    private let settings: SettingsStore
    private let capture: () async -> Void
    private let pauseReason: () -> AppRules.Pause?
    private let render: (String) -> Void
    private var timer: Timer?
    private var nextCapture: Date?
    private var captureInFlight = false
    private var activity: NSObjectProtocol?
    private var lastStatus = ""
    private(set) var isStarted = false

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
            reason: "Daylapse screenshot timer"
        )
        DaylapseLog.write("Capture started")
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if pauseReason() == nil {
            performCapture()
            nextCapture = Date().addingTimeInterval(TimeInterval(max(1, settings.settings.intervalSeconds)))
        }
        tick()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        timer?.invalidate()
        timer = nil
        nextCapture = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        DaylapseLog.write("Capture stopped")
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
            nextCapture = nil
            setStatus(reason.statusText)
            return
        }
        if nextCapture == nil {
            nextCapture = Date().addingTimeInterval(TimeInterval(max(1, settings.settings.intervalSeconds)))
        }
        if let nextCapture, Date() >= nextCapture, !captureInFlight {
            performCapture()
            self.nextCapture = Date().addingTimeInterval(TimeInterval(max(1, settings.settings.intervalSeconds)))
        }
        let seconds = max(0, Int(ceil((nextCapture ?? Date()).timeIntervalSinceNow)))
        setStatus("● \(seconds)s")
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
        DaylapseLog.write("Status changed: \(status)")
        render(status)
    }
}
