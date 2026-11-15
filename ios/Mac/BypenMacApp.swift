import AppKit
import SwiftUI

@main
struct BypenMacApp: App {
    @StateObject private var model = MacModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Бупень", id: "main") {
            MacRoot()
                .environmentObject(model)
                .frame(width: 380, height: 640)
                .task { delegate.model = model; await model.bootstrap() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 640)

        MenuBarExtra {
            MenuBarContent().environmentObject(model)
        } label: {
            Image(systemName: model.isActive ? (model.status.lastProbeMs != nil && model.status.failures == 0 ? "checkmark.shield.fill" : "shield.lefthalf.filled") : "shield.slash")
        }
    }
}

/// При выходе из приложения системный прокси выключается — иначе сеть останется без выхода.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: MacModel?
    /// Если прошлый запуск убили силой, прокси остаётся включённым и сеть «висит» — снимаем при старте.
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.global().async {
            if SystemProxy.isEnabled, let err = SystemProxy.disable() {
                TunnelLog.shared.log("прокси с прошлого запуска не снялся: \(err)")
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let m = model, m.isActive { m.engine.stop(reason: "выход из приложения") }
        if SystemProxy.isEnabled { _ = SystemProxy.disable() }
        MacTun.quitHelper()
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct MenuBarContent: View {
    @EnvironmentObject var model: MacModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.isActive ? "Защищено · \(model.status.nodeName ?? "")" : "Не подключено")
        if let ms = model.status.lastProbeMs, model.isActive { Text("Задержка \(ms) мс") }
        Divider()
        Button(model.isActive ? "Отключить" : "Подключить") {
            Task { if model.isActive { model.disconnect() } else { await model.connect() } }
        }.disabled(!model.loggedIn)
        if let p = model.profile {
            Menu("Узел") {
                ForEach(p.nodes) { n in
                    Button((model.status.nodeId == n.id ? "✓ " : "") + n.name + (n.ok ? "" : " (не отвечает)")) { Task { await model.select(node: n) } }
                }
            }
        }
        Divider()
        Button("Открыть Бупень") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Выйти из приложения") { NSApp.terminate(nil) }
    }
}
