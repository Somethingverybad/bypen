// Режим TUN на маке: разговор с помощником bypen-tun (запускается с правами администратора,
// один пароль за запуск приложения). Команды — строки JSON по unix-сокету.
import Foundation

enum MacTun {
    static let socketPath = "/tmp/bypen-tun.sock"
    static var helperURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/bypen-tun") }

    struct Reply { let ok: Bool; let error: String?; let raw: [String: Any] }

    /// Запустить помощник, если он ещё не слушает. Спрашивает пароль администратора.
    static func ensureHelper() -> String? {
        if send(["cmd": "ping"]) != nil { return nil }
        guard FileManager.default.fileExists(atPath: helperURL.path) else { return "в пакете нет bypen-tun" }
        // nohup под osascript не работает («can't detach from console»), помощник сам делает setsid.
        let cmd = "'\(helperURL.path.replacingOccurrences(of: "'", with: "'\\''"))' --uid \(getuid()) --parent \(getpid()) </dev/null >/tmp/bypen-tun.log 2>&1 &"
        let script = "do shell script \"\(cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", script]
        let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
        do { try p.run() } catch { return "osascript: \(error.localizedDescription)" }
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return e.contains("-128") ? "отменено пользователем" : "не удалось запустить помощник: \(e.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        for _ in 0..<40 {
            if send(["cmd": "ping"]) != nil { return nil }
            usleep(100_000)
        }
        return "помощник не ответил за 4 с (см. /tmp/bypen-tun.log)"
    }

    static func up(socksPort: Int, exclude: [String]) -> String? {
        if let e = ensureHelper() { return e }
        guard let r = send(["cmd": "up", "socks": socksPort, "mtu": 1500, "exclude": exclude, "dns": ["1.1.1.1", "8.8.8.8"]]) else { return "помощник не отвечает" }
        return r.ok ? nil : (r.error ?? "ошибка помощника")
    }

    static func exclude(_ ips: [String]) { _ = send(["cmd": "exclude", "ips": ips]) }
    static func down() { _ = send(["cmd": "down"]) }
    static func quitHelper() { _ = send(["cmd": "quit"]) }
    static var isUp: Bool { (send(["cmd": "stats"])?.raw["running"] as? Bool) ?? false }
    static func stats() -> (up: Int, down: Int)? {
        guard let r = send(["cmd": "stats"]), r.ok, (r.raw["running"] as? Bool) == true else { return nil }
        return (r.raw["up"] as? Int ?? 0, r.raw["down"] as? Int ?? 0)
    }

    @discardableResult
    static func send(_ cmd: [String: Any]) -> Reply? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var sa = sockaddr_un(); sa.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &sa.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strcpy($0, socketPath) } }
        let rc = withUnsafePointer(to: &sa) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard rc == 0 else { return nil }
        guard var data = try? JSONSerialization.data(withJSONObject: cmd) else { return nil }
        data.append(10)
        let sent = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard sent == data.count else { return nil }
        var acc = Data(); var buf = [UInt8](repeating: 0, count: 4096)
        while !acc.contains(10) {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { return nil }
            acc.append(buf, count: n)
        }
        guard let nl = acc.firstIndex(of: 10), let obj = (try? JSONSerialization.jsonObject(with: acc.subdata(in: 0..<nl))) as? [String: Any] else { return nil }
        return Reply(ok: obj["ok"] as? Bool ?? false, error: obj["error"] as? String, raw: obj)
    }
}
