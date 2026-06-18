import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    /// 请求打开设置窗口（由 SwiftUI 内的设置/去设置按钮发出，AppDelegate 监听）。
    static let openSettings = Notification.Name("ccMonitor.openSettings")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var store: DataStore!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore()
        let pricing = PricingStore()
        let balance = BalanceStore()
        store = DataStore(settings: settings, pricing: pricing, balance: balance)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "用量")
            button.title = "0"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        store.$todaySummary
            .map { formatMenuBarTokens($0.total) }
            .removeDuplicates()
            .sink { [weak self] text in
                self?.statusItem.button?.title = text
            }
            .store(in: &cancellables)
        settings.$appearanceMode
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.applyAppearance(mode, systemIsDark: settings.systemAppearanceIsDark)
            }
            .store(in: &cancellables)
        settings.$systemAppearanceIsDark
            .removeDuplicates()
            .sink { [weak self] systemIsDark in
                self?.applyAppearance(settings.appearanceMode, systemIsDark: systemIsDark)
            }
            .store(in: &cancellables)
        settings.$refreshIntervalMinutes
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.store.startTimer()
            }
            .store(in: &cancellables)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceDidChange),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        popover = NSPopover()
        popover.behavior = .transient
        // 固定尺寸：高度须小于屏幕可用高，否则 .minY 放不下时系统会改从侧边弹出。
        popover.contentSize = NSSize(width: 420, height: 840)
        popover.contentViewController = NSHostingController(rootView: DashboardView(store: store))

        NotificationCenter.default.addObserver(
            self, selector: #selector(openSettings),
            name: .openSettings, object: nil)

        store.startTimer()
    }

    private func applyAppearance(_ mode: AppAppearanceMode, systemIsDark: Bool) {
        let appearance = mode.nsAppearance(systemIsDark: systemIsDark)
        NSApp.appearance = appearance
        popover?.contentViewController?.view.appearance = appearance
        popover?.contentViewController?.view.window?.appearance = appearance
        settingsWindow?.appearance = appearance
        settingsWindow?.contentViewController?.view.appearance = appearance
    }

    @objc private func systemAppearanceDidChange() {
        store.settings.refreshSystemAppearance()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// 打开（或前置）独立设置窗口。独立 NSWindow 可成为前台 key window，
    /// NSOpenPanel 依附其上即可正常置顶，不受 transient popover 影响。
    @objc private func openSettings() {
        popover.performClose(nil)   // 关掉 popover，避免抢焦点

        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = SettingsView(settings: store.settings, pricing: store.pricing, balance: store.balance,
                                onSaved: { [weak self] in
                                    self?.settingsWindow?.performClose(nil)
                                    Task { await self?.store.refreshAll() }
                                })
        let hosting = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: hosting)
        win.title = "设置"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.delegate = self
        settingsWindow = win
        applyAppearance(store.settings.appearanceMode, systemIsDark: store.settings.systemAppearanceIsDark)

        win.makeKeyAndOrderFront(nil)
        win.centerOnScreen()   // 几何正中（NSWindow.center() 是垂直偏上 1/3）
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension NSWindow {
    /// 把窗口放到所在屏幕的几何正中心（区别于 center() 的垂直偏上）。
    func centerOnScreen() {
        guard let screen = screen ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        let x = v.minX + (v.width - frame.width) / 2
        let y = v.minY + (v.height - frame.height) / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow = nil
        }
    }
}
