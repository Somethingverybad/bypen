// bypen-tun — помощник с правами администратора для режима TUN на маке.
// Создаёт utun, гонит пакеты в локальный SOCKS ядра Xray (hev-socks5-tunnel), ставит маршруты
// и DNS, при остановке — возвращает. Команды принимает по unix-сокету строками JSON; слушает
// только пользователя, запустившего приложение (uid из аргумента). Если приложение исчезло —
// сам всё снимает и выходит.
import Foundation

let args = CommandLine.arguments
func arg(_ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
guard let uidStr = arg("--uid"), let allowedUid = uid_t(uidStr), let parentStr = arg("--parent"), let parentPid = pid_t(parentStr) else {
    FileHandle.standardError.write(Data("usage: bypen-tun --uid UID --parent PID [--socket PATH]\n".utf8)); exit(2)
}
let socketPath = arg("--socket") ?? "/tmp/bypen-tun.sock"
let statePath = "/tmp/bypen-tun.state"

func logLine(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
    FileHandle.standardError.write(Data("\(f.string(from: Date())) \(s)\n".utf8))
}

@discardableResult
func sh(_ path: String, _ a: [String]) -> (Int32, String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = a
    let out = Pipe(); p.standardOutput = out; p.standardError = out
    do { try p.run() } catch { return (-1, "\(error)") }
    let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return (p.terminationStatus, String(decoding: d, as: UTF8.self))
}

// MARK: - utun

func openUtun() -> (Int32, String)? {
    let fd = socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL)
    guard fd >= 0 else { return nil }
    var info = ctl_info()
    withUnsafeMutablePointer(to: &info.ctl_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) { _ = strcpy($0, "com.apple.net.utun_control") }
    }
    guard ioctl(fd, BYPEN_CTLIOCGINFO, &info) == 0 else { close(fd); return nil }
    var addr = sockaddr_ctl()
    addr.sc_len = UInt8(MemoryLayout<sockaddr_ctl>.size)
    addr.sc_family = UInt8(AF_SYSTEM)
    addr.ss_sysaddr = UInt16(AF_SYS_CONTROL)
    addr.sc_id = info.ctl_id
    addr.sc_unit = 0
    let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_ctl>.size)) } }
    guard rc == 0 else { close(fd); return nil }
    var name = [CChar](repeating: 0, count: 64)
    var len = socklen_t(name.count)
    guard getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, &name, &len) == 0 else { close(fd); return nil }
    return (fd, String(cString: name))
}

// MARK: - сеть: маршруты и DNS

struct SavedState: Codable {
    var dns: [String: [String]] = [:]   // служба → прежние DNS ("" — были автоматические)
    var excluded: [String] = []
}

final class Net {
    var iface = ""
    var gateway: String?
    var gatewayIface: String?
    var state = SavedState()

    func defaultRoute() -> (String?, String?) {
        let (_, out) = sh("/sbin/route", ["-n", "get", "default"])
        var gw: String?, ifc: String?
        for line in out.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("gateway:") { gw = t.dropFirst(8).trimmingCharacters(in: .whitespaces) }
            if t.hasPrefix("interface:") { ifc = t.dropFirst(10).trimmingCharacters(in: .whitespaces) }
        }
        return (gw, ifc)
    }

    func services() -> [String] {
        let (_, out) = sh("/usr/sbin/networksetup", ["-listallnetworkservices"])
        return out.split(separator: "\n").dropFirst().map { String($0) }.filter { !$0.hasPrefix("*") }
    }

    func saveState() { try? JSONEncoder().encode(state).write(to: URL(fileURLWithPath: statePath)) }

    /// Если прошлый помощник умер, не вернув DNS, — вернуть сейчас.
    func restoreStale() {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: statePath)), let s = try? JSONDecoder().decode(SavedState.self, from: d) else { return }
        logLine("возвращаю DNS с прошлого запуска")
        state = s; restoreDNS(); state = SavedState()
        try? FileManager.default.removeItem(atPath: statePath)
    }

    func exclude(_ ips: [String]) {
        for ip in ips where !state.excluded.contains(ip) {
            let family = ip.contains(":") ? "-inet6" : "-inet"
            var a = ["-n", "add", family, "-host", ip]
            if ip.contains(":") { a += ["-interface", gatewayIface ?? "en0"] }
            else if let gw = gateway { a.append(gw) } else { a += ["-interface", gatewayIface ?? "en0"] }
            let (rc, out) = sh("/sbin/route", a)
            if rc != 0 && !out.contains("exists") { logLine("исключение \(ip): \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
            state.excluded.append(ip)
        }
        saveState()
    }

    func up(iface: String, mtu: Int, dns: [String]) -> String? {
        self.iface = iface
        (gateway, gatewayIface) = defaultRoute()
        logLine("шлюз \(gateway ?? "—") через \(gatewayIface ?? "—")")
        var r = sh("/sbin/ifconfig", [iface, "inet", "198.18.0.1", "198.18.0.1", "netmask", "255.255.255.0", "mtu", String(mtu), "up"])
        if r.0 != 0 { return "ifconfig: \(r.1)" }
        r = sh("/sbin/ifconfig", [iface, "inet6", "fd00:7779:7878::2", "prefixlen", "64"])
        if r.0 != 0 { logLine("ipv6 на \(iface): \(r.1)") }
        for net in ["0.0.0.0/1", "128.0.0.0/1"] {
            r = sh("/sbin/route", ["-n", "add", "-inet", net, "-interface", iface])
            if r.0 != 0 { return "route \(net): \(r.1)" }
        }
        for net in ["::/1", "8000::/1"] { sh("/sbin/route", ["-n", "add", "-inet6", net, "-interface", iface]) }
        // DNS — на все службы, прежние запоминаем
        for s in services() {
            let (_, cur) = sh("/usr/sbin/networksetup", ["-getdnsservers", s])
            let lines = cur.split(separator: "\n").map(String.init)
            state.dns[s] = lines.first.map { $0.contains(" ") ? [] : lines } ?? []
            sh("/usr/sbin/networksetup", ["-setdnsservers", s] + dns)
        }
        saveState()
        sh("/usr/bin/dscacheutil", ["-flushcache"])
        sh("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        return nil
    }

    func restoreDNS() {
        for (s, old) in state.dns {
            sh("/usr/sbin/networksetup", ["-setdnsservers", s] + (old.isEmpty ? ["Empty"] : old))
        }
        sh("/usr/bin/dscacheutil", ["-flushcache"])
        sh("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }

    func down() {
        for net in ["0.0.0.0/1", "128.0.0.0/1"] { sh("/sbin/route", ["-n", "delete", "-inet", net, "-interface", iface]) }
        for net in ["::/1", "8000::/1"] { sh("/sbin/route", ["-n", "delete", "-inet6", net, "-interface", iface]) }
        for ip in state.excluded { sh("/sbin/route", ["-n", "delete", ip.contains(":") ? "-inet6" : "-inet", "-host", ip]) }
        restoreDNS()
        state = SavedState()
        try? FileManager.default.removeItem(atPath: statePath)
    }
}

// MARK: - туннель

final class Tunnel {
    let net = Net()
    var fd: Int32 = -1
    var running = false
    let lock = NSLock()

    func up(socks: Int, mtu: Int, exclude: [String], dns: [String]) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        if running { net.exclude(exclude); return ["ok": true, "iface": net.iface, "already": true] }
        net.restoreStale()
        guard let (fd, name) = openUtun() else { return ["ok": false, "error": "не удалось создать utun"] }
        self.fd = fd
        if let err = net.up(iface: name, mtu: mtu, dns: dns) { close(fd); self.fd = -1; net.down(); return ["ok": false, "error": err] }
        net.exclude(exclude)
        let yaml = """
        tunnel:
          mtu: \(mtu)
          ipv4: 198.18.0.1
          ipv6: 'fd00:7779:7878::2'
        socks5:
          port: \(socks)
          address: 127.0.0.1
          udp: 'udp'
        misc:
          task-stack-size: 24576
          tcp-buffer-size: 4096
          max-session-count: 1024
          connect-timeout: 5000
          read-write-timeout: 60000
          log-file: stderr
          log-level: warn
          limit-nofile: 65535
        """
        running = true
        Thread.detachNewThread { [self] in
            let code = yaml.withCString { p in
                p.withMemoryRebound(to: UInt8.self, capacity: yaml.utf8.count) { hev_socks5_tunnel_main_from_str($0, UInt32(yaml.utf8.count), fd) }
            }
            logLine("hev-socks5-tunnel завершился: \(code)")
            lock.lock()
            if running { running = false; net.down(); close(fd); self.fd = -1 }
            lock.unlock()
        }
        logLine("TUN поднят: \(name), socks \(socks), исключено \(exclude)")
        return ["ok": true, "iface": name]
    }

    func down() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        guard running else { return ["ok": true] }
        running = false
        hev_socks5_tunnel_quit()
        net.down()
        if fd >= 0 { close(fd); fd = -1 }
        logLine("TUN снят")
        return ["ok": true]
    }

    func stats() -> [String: Any] {
        var tp = 0, tb = 0, rp = 0, rb = 0
        if running { hev_socks5_tunnel_stats(&tp, &tb, &rp, &rb) }
        return ["ok": true, "running": running, "iface": net.iface, "up": tb, "down": rb, "upPackets": tp, "downPackets": rp]
    }
}

let tunnel = Tunnel()

func shutdown(_ why: String) -> Never {
    logLine("выход: \(why)")
    _ = tunnel.down()
    unlink(socketPath)
    exit(0)
}

// MARK: - сокет

func peerUid(_ fd: Int32) -> uid_t? {
    var cred = xucred(); var len = socklen_t(MemoryLayout<xucred>.size)
    guard getsockopt(fd, 0 /* SOL_LOCAL */, LOCAL_PEERCRED, &cred, &len) == 0 else { return nil }
    return cred.cr_uid
}

func handle(_ cmd: [String: Any]) -> [String: Any] {
    switch cmd["cmd"] as? String {
    case "up":
        return tunnel.up(socks: cmd["socks"] as? Int ?? 10808, mtu: cmd["mtu"] as? Int ?? 1500,
                         exclude: cmd["exclude"] as? [String] ?? [], dns: cmd["dns"] as? [String] ?? ["1.1.1.1", "8.8.8.8"])
    case "exclude": tunnel.net.exclude(cmd["ips"] as? [String] ?? []); return ["ok": true]
    case "down": return tunnel.down()
    case "stats": return tunnel.stats()
    case "ping": return ["ok": true, "pid": Int(getpid())]
    case "quit": shutdown("по команде")
    default: return ["ok": false, "error": "неизвестная команда"]
    }
}

func serve(client: Int32) {
    defer { close(client) }
    guard let uid = peerUid(client), uid == allowedUid || uid == 0 else { logLine("чужой клиент, отказ"); return }
    var buf = [UInt8](repeating: 0, count: 65536)
    var acc = Data()
    while true {
        let n = read(client, &buf, buf.count)
        if n <= 0 { return }
        acc.append(buf, count: n)
        while let nl = acc.firstIndex(of: 10) {
            let line = acc.subdata(in: 0..<nl); acc.removeSubrange(0...nl)
            let cmd = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
            let reply = handle(cmd)
            var out = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{}".utf8)
            out.append(10)
            out.withUnsafeBytes { _ = write(client, $0.baseAddress, $0.count) }
        }
    }
}

signal(SIGTERM) { _ in shutdown("SIGTERM") }
signal(SIGINT) { _ in shutdown("SIGINT") }
signal(SIGPIPE, SIG_IGN)

// слежу за приложением: исчезло — снимаю туннель
Thread.detachNewThread {
    while true {
        sleep(1)
        if kill(parentPid, 0) != 0 && errno == ESRCH { shutdown("приложение завершилось") }
    }
}

unlink(socketPath)
let srv = socket(AF_UNIX, SOCK_STREAM, 0)
var sa = sockaddr_un(); sa.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutablePointer(to: &sa.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strcpy($0, socketPath) } }
let bound = withUnsafePointer(to: &sa) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(srv, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
guard bound == 0, listen(srv, 4) == 0 else { logLine("не могу слушать \(socketPath): \(errno)"); exit(1) }
chmod(socketPath, 0o666)
logLine("слушаю \(socketPath), uid \(allowedUid), приложение \(parentPid)")
while true {
    let c = accept(srv, nil, nil)
    if c < 0 { continue }
    Thread.detachNewThread { serve(client: c) }
}
