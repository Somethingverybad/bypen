// Движок на маке: ядро Xray в процессе (socks 10808 + http 10809), системный прокси,
// проверка живости через socks и переключение узлов — та же логика, что в расширении iOS.
import Foundation

final class MacEngine {
    private let q = DispatchQueue(label: "bypen.mac.engine")
    private let log = TunnelLog.shared
    var onStatus: ((TunnelStatus) -> Void)?

    private(set) var status = TunnelStatus() { didSet { let s = status; DispatchQueue.main.async { self.onStatus?(s) } } }
    private var profile: VpnProfile?
    private var settings = TunnelSettings()
    private var current: VpnNode?
    private var generation = 0
    private var running = false
    private var probeWork: DispatchWorkItem?
    private var probeAttempt = 0
    private var failures = 0
    private var okOnThisNode = false
    private var lastOkReport = Date.distantPast
    private var lastOkLog = Date.distantPast
    private var connectedAt: Date?
    private var failedRecently: [String: Date] = [:]
    private var samples: [(Date, Int)] = []
    private var bytesUp = 0, bytesDown = 0
    private var tunMode = false

    var isRunning: Bool { running }

    func start(preferred: String?) {
        q.async {
            guard !self.running else { return }
            self.log.tag = "mac"
            let ver = XrayCore.version
            self.log.log("старт, Xray \(ver)")
            guard let p = VpnProfile.loadSaved(), !p.nodes.isEmpty else {
                self.status = TunnelStatus(state: .error, lastError: "Нет профиля — обновите список узлов"); self.status = TunnelStatus(); return
            }
            if let other = SystemProxy.activeVPN() {
                self.log.log("включён другой VPN: \(other) — внутри чужого туннеля узлы не отвечают")
                self.status = TunnelStatus(state: .error, lastError: "Выключите другой VPN (\(other)) и подключитесь снова")
                self.status = TunnelStatus(state: .stopped, lastError: "Выключите другой VPN (\(other)) и подключитесь снова")
                return
            }
            self.profile = p
            self.settings = TunnelSettings.load()
            self.running = true
            self.status = TunnelStatus(state: .starting, xrayVersion: ver)
            guard let node = self.startFirstAvailable(order: p.order(preferred: preferred ?? self.settings.preferredNode)) else {
                self.fail("Ни один узел не запустился"); return
            }
            self.tunMode = self.settings.macTun
            if self.tunMode {
                if let err = MacTun.up(socksPort: XrayConfig.socksPort, exclude: node.dialIPs) {
                    self.log.log("TUN не поднялся: \(err)")
                    XrayCore.stop(); self.fail("TUN не поднялся: \(err)"); return
                }
                self.log.log("TUN поднят (весь трафик через туннель), узел исключён: \(node.dialIPs.joined(separator: ", "))")
            } else {
                if let err = SystemProxy.enable(socksPort: XrayConfig.socksPort, httpPort: XrayConfig.httpPort) {
                    self.log.log("системный прокси не включился: \(err)")
                    XrayCore.stop(); self.fail("Не удалось включить системный прокси: \(err)"); return
                }
                self.log.log("системный прокси включён (SOCKS \(XrayConfig.socksPort), HTTP \(XrayConfig.httpPort))")
            }
            self.became(node)
            self.scheduleProbe(after: 1.5)
        }
    }

    func stop(reason: String = "по кнопке") {
        q.async {
            guard self.running else { return }
            self.running = false
            self.probeWork?.cancel()
            self.log.log("остановка (\(reason))")
            self.tearDownNetwork()
            XrayCore.stop()
            self.current = nil
            self.status = TunnelStatus(state: .stopped)
        }
    }

    func switchNow(to id: String?) { q.async { self.switchNode(to: id, reason: "по команде") } }
    func probeNow() { q.async { self.scheduleProbe(after: 0) } }

    /// Снять то, что ставили: прокси или TUN.
    private func tearDownNetwork() {
        if tunMode { MacTun.down() }
        else if let err = SystemProxy.disable() { log.log("системный прокси не выключился: \(err)") }
    }

    private func fail(_ message: String) {
        log.log(message)
        tearDownNetwork()
        running = false
        status = TunnelStatus(state: .error, lastError: message)
        status = TunnelStatus(state: .stopped, lastError: message)
    }

    private func startFirstAvailable(order: [VpnNode]) -> VpnNode? {
        guard let p = profile else { return nil }
        for node in order {
            if let err = XrayCore.run(configJSON: XrayConfig.build(node: node, uuid: p.user.uuid, withHTTP: true)) {
                log.log("узел \(node.name): ядро не запустилось — \(err)")
                VpnEvent(node: node.id, ok: false, error: "start: \(err.prefix(150))", net: "mac").append()
                XrayCore.stop(); continue
            }
            log.log("узел \(node.name) (\(node.kind), \(node.dialAddress):\(node.port)) — ядро запущено")
            return node
        }
        return nil
    }

    private func became(_ node: VpnNode) {
        current = node; connectedAt = Date(); okOnThisNode = false; failures = 0; probeAttempt = 0; samples.removeAll()
        status = TunnelStatus(state: .connected, nodeId: node.id, nodeName: node.name, since: Date(), up: bytesUp, down: bytesDown,
                              switches: status.switches, xrayVersion: status.xrayVersion)
    }

    private func switchNode(to id: String?, reason: String) {
        guard running else { return }
        if let fresh = VpnProfile.loadSaved() { profile = fresh }
        guard let p = profile else { return }
        settings = TunnelSettings.load()
        let cur = current
        var candidates: [VpnNode]
        if let id {
            candidates = p.nodes.filter { $0.id == id }
            if candidates.isEmpty { log.log("узла \(id) нет в профиле"); return }
        } else {
            let now = Date()
            candidates = p.nodes.filter { $0.id != cur?.id }.enumerated().sorted { a, b in
                let fa = failedRecently[a.element.id].map { now.timeIntervalSince($0) < 600 } ?? false
                let fb = failedRecently[b.element.id].map { now.timeIntervalSince($0) < 600 } ?? false
                if fa != fb { return !fa }
                if a.element.ok != b.element.ok { return a.element.ok }
                return a.offset < b.offset
            }.map { $0.element }
        }
        guard !candidates.isEmpty else { log.log("переключаться некуда"); return }
        generation += 1
        probeWork?.cancel()
        status.state = .switching
        if let cur, !reason.contains("команде"), !reason.contains("ротация") { failedRecently[cur.id] = Date() }
        XrayCore.stop()
        for next in candidates {
            if let err = XrayCore.run(configJSON: XrayConfig.build(node: next, uuid: p.user.uuid, withHTTP: true)) {
                log.log("узел \(next.name): ядро не запустилось — \(err)"); failedRecently[next.id] = Date(); XrayCore.stop(); continue
            }
            if tunMode { MacTun.exclude(next.dialIPs) }
            log.log("переключение: \(cur?.name ?? "—") → \(next.name) (\(reason))")
            status.switches += 1
            became(next)
            scheduleProbe(after: 1.5)
            return
        }
        if let cur, XrayCore.run(configJSON: XrayConfig.build(node: cur, uuid: p.user.uuid, withHTTP: true)) == nil {
            log.log("остаёмся на \(cur.name)"); became(cur)
        } else {
            status.state = .error; status.lastError = "Ни один узел не запустился"
        }
        scheduleProbe(after: 5)
    }

    private func scheduleProbe(after s: Double) {
        guard running else { return }
        probeWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.runProbe() }
        probeWork = w
        q.asyncAfter(deadline: .now() + s, execute: w)
    }

    private func runProbe() {
        guard let node = current, running else { return }
        let gen = generation
        Health.probe(socksPort: XrayConfig.socksPort, attempt: probeAttempt) { [weak self] r in
            self?.q.async { self?.handleProbe(r, node: node, gen: gen) }
        }
    }

    private func handleProbe(_ r: Health.Result, node: VpnNode, gen: Int) {
        guard gen == generation, running else { return }
        status.lastProbeAt = Date()
        if r.ok {
            let first = !okOnThisNode
            okOnThisNode = true; failures = 0; probeAttempt = 0
            failedRecently[node.id] = nil
            status.state = .connected; status.lastProbeMs = r.ms; status.failures = 0; status.lastError = nil
            if first || Date().timeIntervalSince(lastOkLog) > 600 { log.log("связь через \(node.name): \(r.ms) мс"); lastOkLog = Date() }
            if first || Date().timeIntervalSince(lastOkReport) > 300 { VpnEvent(node: node.id, ok: true, rtt_ms: r.ms, net: "mac").append(); lastOkReport = Date() }
            scheduleProbe(after: 20)
        } else {
            failures += 1; probeAttempt += 1
            status.failures = failures; status.lastError = r.error
            log.log("проверка через \(node.name) не прошла (\(failures)): \(r.error ?? "")")
            if failures >= (okOnThisNode ? 3 : 2) {
                VpnEvent(node: node.id, ok: false, error: r.error.map { String($0.prefix(150)) }, net: "mac").append()
                if settings.autoSwitch, (profile?.nodes.count ?? 0) > 1 { switchNode(to: nil, reason: "узел не отвечает") }
                else { status.state = .error; scheduleProbe(after: 10) }
            } else {
                scheduleProbe(after: okOnThisNode ? 5 : 3)
            }
        }
    }
}
