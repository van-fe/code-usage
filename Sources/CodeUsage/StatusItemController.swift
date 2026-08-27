import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let codeUsagePanelWillHide = Notification.Name(
        "CodeUsage.PanelWillHide"
    )
}

@MainActor
final class CodeUsageAppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let launchAtLogin = LaunchAtLoginManager()
    private let launchAtLoginPromptKey = "launchAtLogin.didOffer.v1"
    private let panel: StatusMenuPanel = {
        let panel = StatusMenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .none
        return panel
    }()
    private var statusItem: NSStatusItem?
    private var storeCancellable: AnyCancellable?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
        }

        panel.contentViewController = NSHostingController(
            rootView: StatusPanelRootView(
                store: store,
                launchAtLogin: launchAtLogin
            )
        )
        panel.onCancel = { [weak self] in
            self?.hidePanel()
        }

        storeCancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateStatusItem()
                if !self.panel.isVisible {
                    self.updatePanelSize()
                }
            }
        }

        updateStatusItem()
        updatePanelSize()
        store.start()
        if store.isSimulationMode {
            DispatchQueue.main.async { [weak self] in
                guard let self, let button = self.statusItem?.button else { return }
                self.showPanel(relativeTo: button)
            }
        } else {
            offerLaunchAtLoginIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        storeCancellable?.cancel()
        stopDismissMonitoring()
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel(relativeTo: sender)
        }
    }

    private func showPanel(relativeTo sender: NSStatusBarButton) {
        launchAtLogin.refreshStatus()
        updatePanelSize()
        sender.layoutSubtreeIfNeeded()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        setStatusItemHighlighted(true)
        startDismissMonitoring()
    }

    private func offerLaunchAtLoginIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: launchAtLoginPromptKey) == nil else { return }
        if launchAtLogin.isRegistered {
            defaults.set(true, forKey: launchAtLoginPromptKey)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            defaults.set(true, forKey: self.launchAtLoginPromptKey)

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "登录时自动启动 CodeUsage？"
            alert.informativeText = "开启后，CodeUsage 会在你登录 Mac 时自动出现在状态栏。之后可在面板底部随时关闭。"
            alert.addButton(withTitle: "开启")
            alert.addButton(withTitle: "暂不")
            NSApplication.shared.activate(ignoringOtherApps: true)

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if let message = self.launchAtLogin.setEnabled(true) {
                let errorAlert = NSAlert()
                errorAlert.alertStyle = .warning
                errorAlert.messageText = "无法开启开机启动"
                errorAlert.informativeText = message
                errorAlert.addButton(withTitle: "好")
                errorAlert.runModal()
            }
        }
    }

    private func updateStatusItem() {
        guard let item = statusItem, let button = item.button else { return }
        let image = makeStatusImage()
        button.image = image
        button.toolTip = statusToolTip
        item.length = NSStatusItem.variableLength
        button.invalidateIntrinsicContentSize()
        if panel.isVisible {
            setStatusItemHighlighted(true)
        }
    }

    private func updatePanelSize() {
        guard let view = panel.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let fitting = view.fittingSize
        let desiredSize = NSSize(
            width: 360,
            height: min(max(fitting.height, 220), 720)
        )
        if abs(panel.frame.width - desiredSize.width) > 0.5
            || abs(panel.frame.height - desiredSize.height) > 0.5 {
            panel.setContentSize(desiredSize)
        }
    }

    private func positionPanel() {
        guard let button = statusItem?.button,
              let statusWindow = button.window else { return }

        statusWindow.layoutIfNeeded()
        button.layoutSubtreeIfNeeded()

        let buttonWindowRect = button.convert(button.bounds, to: nil)
        let buttonScreenRect = statusWindow.convertToScreen(buttonWindowRect)
        let screenFrame = (statusWindow.screen ?? NSScreen.main)?.visibleFrame
            ?? buttonScreenRect
        let panelSize = panel.frame.size
        let leftScreenMargin: CGFloat = 8
        let verticalGap: CGFloat = 4

        let idealX = buttonScreenRect.maxX - panelSize.width
        let minX = screenFrame.minX + leftScreenMargin
        let maxX = screenFrame.maxX - panelSize.width
        let x = min(max(idealX, minX), maxX)

        let idealY = buttonScreenRect.minY - verticalGap - panelSize.height
        let minY = screenFrame.minY + leftScreenMargin
        let maxY = screenFrame.maxY - panelSize.height
        let y = min(max(idealY, minY), maxY)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        NotificationCenter.default.post(
            name: .codeUsagePanelWillHide,
            object: panel
        )
        panel.orderOut(nil)
        setStatusItemHighlighted(false)
        stopDismissMonitoring()
        updatePanelSize()
    }

    private func setStatusItemHighlighted(_ highlighted: Bool) {
        guard let button = statusItem?.button else { return }
        button.highlight(highlighted)
        button.needsDisplay = true

        guard highlighted else { return }
        DispatchQueue.main.async { [weak self, weak button] in
            guard let self, let button, self.panel.isVisible else { return }
            button.highlight(true)
            button.needsDisplay = true
        }
    }

    private func startDismissMonitoring() {
        stopDismissMonitoring()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                self.hidePanel()
                return nil
            }

            if event.window === self.panel || self.isInsideStatusButton(event) {
                return event
            }

            self.hidePanel()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hidePanel()
            }
        }
    }

    private func stopDismissMonitoring() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func isInsideStatusButton(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button,
              let buttonWindow = button.window,
              let eventWindow = event.window else { return false }

        let eventScreenPoint = eventWindow.convertToScreen(
            NSRect(origin: event.locationInWindow, size: .zero)
        ).origin
        let buttonWindowRect = button.convert(button.bounds, to: nil)
        let buttonScreenRect = buttonWindow.convertToScreen(buttonWindowRect)
        return buttonScreenRect.contains(eventScreenPoint)
    }

    private var statusToolTip: String {
        let providers = store.visibleMenuBarProviders
        guard !providers.isEmpty else { return "打开 CodeUsage" }
        return "查看用量：\(store.menuBarText(for: providers))"
    }

    private func makeStatusImage() -> NSImage {
        let providers = store.visibleMenuBarProviders
        let height: CGFloat = 20
        let appLogoSize: CGFloat = 20
        let providerLogoSize: CGFloat = 13
        let groupSpacing: CGFloat = 7
        let valueSpacing: CGFloat = 3
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        let values = providers.map { store.remainingText(for: $0) }
        let valueSizes = values.map {
            ($0 as NSString).size(withAttributes: attributes)
        }
        let providerWidths = valueSizes.map {
            providerLogoSize + valueSpacing + ceil($0.width)
        }
        let contentWidth = appLogoSize + providerWidths.reduce(0) {
            $0 + groupSpacing + $1
        }
        let width = contentWidth

        let image = NSImage(size: NSSize(width: ceil(width), height: height))
        image.lockFocus()
        NSColor.black.set()

        var x: CGFloat = 0
        draw(
            appLogoImage(size: appLogoSize),
            atX: x,
            size: appLogoSize,
            canvasHeight: height
        )
        x += appLogoSize

        for (index, provider) in providers.enumerated() {
            x += groupSpacing
            draw(
                providerLogoImage(provider, size: providerLogoSize),
                atX: x,
                size: providerLogoSize,
                canvasHeight: height
            )
            x += providerLogoSize + valueSpacing

            let value = values[index] as NSString
            let valueSize = valueSizes[index]
            value.draw(
                at: NSPoint(
                    x: x,
                    y: floor((height - valueSize.height) / 2) - 1
                ),
                withAttributes: attributes
            )
            x += ceil(valueSize.width)
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func appLogoImage(size: CGFloat) -> NSImage? {
        if let url = Bundle.main.resourceURL?
            .appendingPathComponent("statusbar-logo.svg"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: size, height: size)
            image.isTemplate = true
            return image
        }

        return NSImage(
            systemSymbolName: "gauge.with.dots.needle.67percent",
            accessibilityDescription: "CodeUsage"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        )
    }

    private func providerLogoImage(_ provider: ProviderKind, size: CGFloat) -> NSImage? {
        if let url = Bundle.main.resourceURL?
            .appendingPathComponent("provider-\(provider.rawValue).svg"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: size, height: size)
            return image
        }

        let fallback: String
        switch provider {
        case .codex: fallback = "sparkles"
        case .cursor: fallback = "cube"
        case .claude: fallback = "asterisk"
        case .kiro: fallback = "wand.and.stars"
        case .qoder: fallback = "q.square"
        }
        return NSImage(
            systemSymbolName: fallback,
            accessibilityDescription: provider.title
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        )
    }

    private func draw(
        _ image: NSImage?,
        atX x: CGFloat,
        size: CGFloat,
        canvasHeight: CGFloat
    ) {
        image?.draw(
            in: NSRect(
                x: x,
                y: floor((canvasHeight - size) / 2),
                width: size,
                height: size
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }
}

private final class StatusMenuPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private struct StatusPanelRootView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager

    var body: some View {
        DashboardView(store: store, launchAtLogin: launchAtLogin)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
            }
    }
}
