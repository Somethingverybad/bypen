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
