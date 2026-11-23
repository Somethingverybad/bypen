// Состояние приложения: вход, профиль узлов (проверенный подписью), туннель, отчёты.
import Foundation
import NetworkExtension
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var loggedIn = API.shared.isLoggedIn
    @Published var username = API.shared.username
    @Published var profile: VpnProfile? = VpnProfile.loadSaved()
    @Published var profileNote: String?
    @Published var settings = TunnelSettings.load() { didSet { settings.save() } }
    @Published var status = TunnelStatus.load() ?? TunnelStatus()
    @Published var busy = false
    @AppStorage("appearance") var appearance = "dark"
    var theme: Theme { Theme.named(appearance) }
    @Published var error: String?
    let tunnel = TunnelManager()
    private let log = TunnelLog.shared
    private var pollTask: Task<Void, Never>?
    private var lastProfileFetch = Date.distantPast

    var vpnStatus: NEVPNStatus { tunnel.vpnStatus }
    var currentNode: VpnNode? { profile?.nodes.first { $0.id == status.nodeId } }

    func bootstrap() async {
        log.tag = "app"
        await tunnel.load()
        startPolling()
        if let mode = ProcessInfo.processInfo.environment["BYPEN_PREVIEW"] { applyPreview(mode); return }
        guard loggedIn else { return }
        await refreshProfile(force: false)
        await uploadEvents()
    }

    static let preview = ProcessInfo.processInfo.environment["BYPEN_PREVIEW"] != nil

    /// Только для скриншотов в симуляторе: BYPEN_PREVIEW=off|checking|on подменяет состояние без сети.
    private func applyPreview(_ mode: String) {
        let json = """
        {"v":1,"issued_at":"2026-11-16T00:00:00Z","ttl":600,"user":{"id":"1","username":"varivari","uuid":"1fc88e7f-0000-0000-0000-000000000000","email":""},
         "nodes":[{"id":"a","name":"Москва → NL • Reality","kind":"reality","host":"1.1.1.1","port":443,"sni":"x","weight":1,"ok":true,"rtt_ms":114,"checked_at":null},
                  {"id":"b","name":"Москва → NL • XHTTP","kind":"xhttp","host":"1.1.1.1","port":443,"sni":"x","weight":1,"ok":true,"rtt_ms":189,"checked_at":null},
                  {"id":"c","name":"NL напрямую • Reality","kind":"reality","host":"1.1.1.1","port":443,"sni":"x","weight":1,"ok":false,"rtt_ms":null,"checked_at":null}]}
        """
        profile = try? VpnProfile.decode(json)
        username = "varivari"; loggedIn = true
        pollTask?.cancel()
        guard mode != "off" else { return }
        tunnel.vpnStatus = .connected
        status = TunnelStatus(state: .connected, nodeId: "a", nodeName: "Москва → NL • Reality", since: Date(), up: 9 * 1024, down: 18 * 1024,
                              lastProbeMs: mode == "on" ? 238 : nil, failures: 0, switches: 0, xrayVersion: "26.11.9")
    }

    // MARK: вход

    func login(username: String, password: String) async {
        busy = true; defer { busy = false }
        error = nil
        do {
            try await API.shared.login(username: username.trimmingCharacters(in: .whitespaces), password: password)
            self.username = API.shared.username
            loggedIn = true
            log.log("вход: \(username)")
            await refreshProfile(force: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Пока ждём «Да» в WYX — имя бота, который прислал запрос.
    @Published var awaitingBot: String?
    private var botTask: Task<Void, Never>?

    /// Вход без пароля: бот «Бупень» спрашивает в WYX «Подтвердить вход?».
    func loginViaWYX(username: String) {
        botTask?.cancel()
        let u = username.trimmingCharacters(in: .whitespaces)
        botTask = Task { [weak self] in
            guard let self else { return }
            busy = true; error = nil
            defer { busy = false; awaitingBot = nil }
            do {
                let r = try await API.shared.startBotLogin(username: u)
                awaitingBot = r.bot
                log.log("вход через WYX: запрос для \(u)")
                try await API.shared.waitBotLogin(r)
                self.username = API.shared.username
                loggedIn = true
                log.log("вход через WYX: подтверждён")
                await refreshProfile(force: true)
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: напрямую, мимо VPN (хранится в профиле WYX — одно на все устройства)

    @Published var direct: API.DirectSettings?
    @Published var directError: String?
    @Published var directSaving = false

    /// Последний итог «Поделиться» — показывается под секцией.
    @Published var directNote: String?

    func shareDirect(username: String) async {
        let u = username.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !u.isEmpty else { return }
        do {
            let name = try await API.shared.shareDirect(username: u)
            directNote = "Отправлено @\(name) — бот «Бупень» спросит, принять ли настройки"
            directError = nil
        } catch {
            directError = error.localizedDescription
        }
    }

    func loadDirect() async {
        do { direct = try await API.shared.fetchDirect(); directError = nil }
        catch { directError = error.localizedDescription }
    }

    /// Сохранить, перечитать профиль и, если VPN включён, переподключить — иначе правила не применятся.
    @discardableResult
    func saveDirect(ru: Bool? = nil, custom: [String]? = nil) async -> Bool {
        directSaving = true; defer { directSaving = false }
        do {
            direct = try await API.shared.saveDirect(ru: ru, custom: custom)
            directError = nil
            log.log("напрямую: российские \(direct?.ru == true ? "вкл" : "выкл"), своих \(direct?.custom.count ?? 0)")
            await refreshProfile(force: true)
            if tunnel.isActive {
                let node = status.nodeId
                tunnel.stop()
                for _ in 0..<40 where tunnel.isActive { try? await Task.sleep(nanoseconds: 250_000_000) }
                await connect(nodeId: node)
            }
            return true
        } catch {
            directError = error.localizedDescription
            return false
        }
    }

    func cancelBotLogin() {
        botTask?.cancel(); botTask = nil
        awaitingBot = nil; busy = false
    }

    func logout() {
        if tunnel.isActive { tunnel.stop() }
        API.shared.logout()
        try? FileManager.default.removeItem(at: AppGroup.profileURL)
        profile = nil
        loggedIn = false
        username = nil
        log.log("выход")
    }

    // MARK: профиль

    func refreshProfile(force: Bool) async {
        if Self.preview { return }
        guard loggedIn else { return }
        if !force, let p = profile, Date().timeIntervalSince(lastProfileFetch) < Double(p.ttl) { return }
        do {
            let s = try await API.shared.fetchProfile()
            let warning = try Signature.verify(payload: s.payload, sig: s.sig, pub: s.pub)
            let p = try VpnProfile.decode(s.payload)
            try Data(s.payload.utf8).write(to: AppGroup.profileURL, options: .atomic)
            profile = p
            profileNote = warning
            lastProfileFetch = Date()
            error = nil
            log.log("профиль обновлён: узлов \(p.nodes.count), живых \(p.nodes.filter(\.ok).count)" + (warning.map { "; \($0)" } ?? ""))
        } catch let e as APIError where e.unauthorized {
            logout()
            error = e.message
        } catch {
            self.error = error.localizedDescription
            log.log("профиль не обновлён: \(error.localizedDescription)")
        }
    }

    // MARK: туннель

    func connect(nodeId: String? = nil) async {
        busy = true; defer { busy = false }
        error = nil
        if profile == nil { await refreshProfile(force: true) }
        guard let p = profile, !p.nodes.isEmpty else {
            if error == nil { error = "Нет узлов — доступ к сети WYX не выдан?" }
            return
        }
        do {
            log.log("подключение" + (nodeId.map { " к \($0)" } ?? ""))
            try await tunnel.start(nodeId: nodeId ?? settings.preferredNode)
        } catch {
            self.error = "VPN не запустился: \(error.localizedDescription)"
            log.log(self.error!)
        }
    }

    func disconnect() {
        log.log("отключение по кнопке")
        tunnel.stop()
    }

    func select(node: VpnNode) async {
        settings.preferredNode = node.id
        if tunnel.isActive {
            if let s = await tunnel.send(TunnelCommand.switchNode, node: node.id) { status = s }
        } else {
            await connect(nodeId: node.id)
        }
    }

    func probeNow() async {
        if let s = await tunnel.send(TunnelCommand.probe) { status = s }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.tunnel.isActive {
                    if let s = await self.tunnel.send(TunnelCommand.status) { self.status = s }
                } else if let s = TunnelStatus.load() {
                    self.status = s
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    // MARK: отчёты

    /// Отправить накопленные расширением события и подрезать файл.
    func uploadEvents() async {
        if Self.preview { return }
        guard loggedIn, let data = try? Data(contentsOf: AppGroup.eventsURL), !data.isEmpty else { return }
        let consumed = data.count
        let lines = data.split(separator: 0x0A)
        let events: [[String: Any]] = lines.compactMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        guard !events.isEmpty else { try? Data().write(to: AppGroup.eventsURL); return }
        do {
            var sent = 0
            for chunk in stride(from: 0, to: events.count, by: 200) {
                sent += try await API.shared.report(Array(events[chunk..<min(chunk + 200, events.count)]))
            }
            // убрать отправленное, оставить то, что расширение дописало за это время
            if let now = try? Data(contentsOf: AppGroup.eventsURL), now.count >= consumed {
                try? now.suffix(from: consumed).write(to: AppGroup.eventsURL, options: .atomic)
            }
            log.log("отчёты отправлены: \(sent)")
        } catch {
            log.log("отчёты не отправлены: \(error.localizedDescription)")
        }
    }
}
