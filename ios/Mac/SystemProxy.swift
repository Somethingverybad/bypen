// Системный прокси macOS: SOCKS и HTTP(S) на локальные входы Xray для всех активных
// сетевых служб. networksetup у администратора работает без пароля; если система
// откажет — повтор через osascript с запросом пароля (один раз на включение/выключение).
import Foundation

enum SystemProxy {
    private static let tool = "/usr/sbin/networksetup"

    static func services() -> [String] {
        let out = run(tool, ["-listallnetworkservices"]).out
        return out.split(separator: "\n").map(String.init)
            .filter { !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") && !$0.isEmpty }
    }

    /// Включить прокси на всех службах. Возвращает описание ошибки или nil.
    static func enable(socksPort: Int, httpPort: Int) -> String? {
        var cmds: [[String]] = []
        for s in services() {
            cmds.append(["-setsocksfirewallproxy", s, "127.0.0.1", "\(socksPort)"])
            cmds.append(["-setwebproxy", s, "127.0.0.1", "\(httpPort)"])
            cmds.append(["-setsecurewebproxy", s, "127.0.0.1", "\(httpPort)"])
            cmds.append(["-setproxybypassdomains", s, "localhost", "127.0.0.1", "*.local", "169.254/16", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"])
        }
        return apply(cmds)
    }

    static func disable() -> String? {
        var cmds: [[String]] = []
        for s in services() {
            cmds.append(["-setsocksfirewallproxystate", s, "off"])
            cmds.append(["-setwebproxystate", s, "off"])
            cmds.append(["-setsecurewebproxystate", s, "off"])
        }
        return apply(cmds)
    }

    static var isEnabled: Bool {
        services().contains { run(tool, ["-getsocksfirewallproxy", $0]).out.contains("Enabled: Yes") }
    }


    /// Имя другого VPN, через который сейчас идёт весь трафик мака (маршрут по умолчанию — через utun).
    /// Внутри чужого туннеля наше соединение с узлом ломается (Reality получает настоящий сертификат), поэтому
    /// сначала просим выключить его.
    static func activeVPN() -> String? {
        let r = run("/sbin/route", ["-n", "get", "1.1.1.1"])
        guard r.code == 0, let line = r.out.split(separator: "\n").first(where: { $0.contains("interface:") }) else { return nil }
        let iface = line.split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard iface.hasPrefix("utun") || iface.hasPrefix("ipsec") || iface.hasPrefix("ppp") else { return nil }
        let nc = run("/usr/sbin/scutil", ["--nc", "list"])
        let connected = nc.out.split(separator: "\n").filter { $0.contains("(Connected)") }
        if let first = connected.first, let q1 = first.firstIndex(of: "\""), let q2 = first[first.index(after: q1)...].firstIndex(of: "\"") {
            return String(first[first.index(after: q1)..<q2])
        }
        return "неизвестный (\(iface))"
    }

    private static func apply(_ cmds: [[String]]) -> String? {
        var failed: [[String]] = []
        for c in cmds where run(tool, c).code != 0 { failed.append(c) }
        if failed.isEmpty { return nil }
        // без прав — одним запросом пароля
        let script = failed.map { c in tool + " " + c.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ") }
            .joined(separator: "; ")
        let r = run("/usr/bin/osascript", ["-e", "do shell script \"\(script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"])
        return r.code == 0 ? nil : "networksetup: \(r.err.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> (code: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let o = Pipe(), e = Pipe()
        p.standardOutput = o; p.standardError = e
        do { try p.run() } catch { return (-1, "", "\(error)") }
        p.waitUntilExit()
        return (p.terminationStatus,
                String(decoding: o.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                String(decoding: e.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
