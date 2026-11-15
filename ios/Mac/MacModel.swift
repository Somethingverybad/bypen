// Состояние приложения на маке: вход, профиль, движок прокси, отчёты.
import Foundation
import SwiftUI

@MainActor
final class MacModel: ObservableObject {
    @Published var loggedIn = API.shared.isLoggedIn
    @Published var username = API.shared.username
    @Published var profile: VpnProfile? = VpnProfile.loadSaved()
    @Published var profileNote: String?
    @Published var settings = TunnelSettings.load() { didSet { settings.save() } }
    @Published var status = TunnelStatus()
    @Published var busy = false
    @Published var error: String?
    @AppStorage("appearance") var appearance = "dark"
    var theme: Theme { Theme.named(appearance) }
    let engine = MacEngine()
    private let log = TunnelLog.shared
    private var lastProfileFetch = Date.distantPast
    private var lastProfileError: (String?, Date) = (nil, .distantPast)

    var isActive: Bool { status.state != .stopped }
    var currentNode: VpnNode? { profile?.nodes.first { $0.id == status.nodeId } }

    init() {
        log.tag = "mac"
        engine.onStatus = { [weak self] s in self?.status = s }
    }

    func bootstrap() async {
        guard loggedIn else { return }
        await refreshProfile(force: false)
        await uploadEvents()
    }

    func login(username: String, password: String) async {
        busy = true; defer { busy = false }
        error = nil
        do {
            try await API.shared.login(username: username.trimmingCharacters(in: .whitespaces), password: password)
            self.username = API.shared.username; loggedIn = true
            log.log("вход: \(username)")
            await refreshProfile(force: true)
        } catch { self.error = error.localizedDescription }
    }

    func logout() {
        if isActive { engine.stop(reason: "выход") }
        API.shared.logout()
        try? FileManager.default.removeItem(at: AppGroup.profileURL)
        profile = nil; loggedIn = false; username = nil
        log.log("выход")
    }

    func refreshProfile(force: Bool) async {
        guard loggedIn else { return }
        if !force, let p = profile, Date().timeIntervalSince(lastProfileFetch) < Double(p.ttl) { return }
        do {
            let s = try await API.shared.fetchProfile()
            let warning = try Signature.verify(payload: s.payload, sig: s.sig, pub: s.pub)
            let p = try VpnProfile.decode(s.payload)
            try Data(s.payload.utf8).write(to: AppGroup.profileURL, options: .atomic)
            profile = p; profileNote = warning; lastProfileFetch = Date(); error = nil
            log.log("профиль обновлён: узлов \(p.nodes.count), живых \(p.nodes.filter(\.ok).count)" + (warning.map { "; \($0)" } ?? ""))
        } catch let e as APIError where e.unauthorized {
            logout(); error = e.message
        } catch {
            self.error = error.localizedDescription
            if lastProfileError.0 != error.localizedDescription || Date().timeIntervalSince(lastProfileError.1) > 60 {
                log.log("профиль не обновлён: \(error.localizedDescription)")
            }
            lastProfileError = (error.localizedDescription, Date())
        }
    }

    func connect(nodeId: String? = nil) async {
        busy = true; defer { busy = false }
        error = nil
        if profile == nil { await refreshProfile(force: true) }
        guard let p = profile, !p.nodes.isEmpty else { if error == nil { error = "Нет узлов — доступ к сети WYX не выдан?" }; return }
        log.log("подключение" + (nodeId.map { " к \($0)" } ?? ""))
        engine.start(preferred: nodeId ?? settings.preferredNode)
    }

    func disconnect() { engine.stop() }

    func select(node: VpnNode) async {
        settings.preferredNode = node.id
        if isActive { engine.switchNow(to: node.id) } else { await connect(nodeId: node.id) }
    }

    func uploadEvents() async {
        guard loggedIn, let data = try? Data(contentsOf: AppGroup.eventsURL), !data.isEmpty else { return }
        let consumed = data.count
        let events: [[String: Any]] = data.split(separator: 0x0A).compactMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        guard !events.isEmpty else { try? Data().write(to: AppGroup.eventsURL); return }
        do {
            var sent = 0
            for chunk in stride(from: 0, to: events.count, by: 200) { sent += try await API.shared.report(Array(events[chunk..<min(chunk + 200, events.count)])) }
            if let now = try? Data(contentsOf: AppGroup.eventsURL), now.count >= consumed { try? now.suffix(from: consumed).write(to: AppGroup.eventsURL, options: .atomic) }
            log.log("отчёты отправлены: \(sent)")
        } catch { log.log("отчёты не отправлены: \(error.localizedDescription)") }
    }
}
