import SwiftUI
import AppKit

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore()
        let pricing = PricingStore()
        store = DataStore(settings: settings, pricing: pricing)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "用量")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

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

        let root = SettingsView(settings: store.settings, pricing: store.pricing,
                                onSaved: { [weak self] in
                                    self?.settingsWindow?.performClose(nil)
                                    Task { await self?.store.refreshAll() }
                                })
        let hosting = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: hosting)
        win.title = "设置"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        win.delegate = self
        settingsWindow = win

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow = nil
        }
    }
}
