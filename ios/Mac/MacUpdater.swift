// Самообновление Бупеня на маке. Манифест mac.json в бакете (кладёт scripts/publish-mac.sh):
// {version, build, url, sha256, size, notes}. Обновление ставится только если архив сходится
// по sha256, внутри — Бупень с подписью Developer ID нашей команды, заверенный Apple
// (spctl), и номер сборки больше текущего. Подмена — переименованием рядом с текущим
// приложением, затем перезапуск; при сбое прежнее приложение возвращается на место.
import AppKit
import CryptoKit
import Foundation

struct MacUpdateInfo: Codable, Equatable {
    let version: String
    let build: Int
    let url: String
    let sha256: String
    var size: Int?
    var notes: String?
}

enum MacUpdater {
    static let manifestURL = URL(string: "https://storage.yandexcloud.net/hyax-public/installers/bypen/mac.json")!
    static let teamID = "BTQ69VVHX6"
    static let bundleID = "com.hyax.bypen.mac"
    /// После перезапуска — подключиться снова, если перед обновлением VPN был включён.
    static let reconnectKey = "reconnectAfterUpdate"

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var currentBuild: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0 }

    /// Есть ли сборка новее текущей.
    static func check() async throws -> MacUpdateInfo? {
        var c = URLComponents(url: manifestURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]   // мимо кэша CDN
        var req = URLRequest(url: c.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("Bypen/\(API.version) mac", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let info = try JSONDecoder().decode(MacUpdateInfo.self, from: data)
        return info.build > currentBuild ? info : nil
    }

    /// nil — подменять можно; иначе — почему нельзя (что сделать пользователю).
    static var blocker: String? {
        let path = Bundle.main.bundlePath
        if path.contains("/AppTranslocation/") {
            return "macOS запустила Бупень из карантина — перенесите его в «Программы» и откройте оттуда"
        }
        let parent = (path as NSString).deletingLastPathComponent
        if !FileManager.default.isWritableFile(atPath: parent) {
            return "Нет прав на запись в \(parent) — перенесите Бупень в «Программы»"
        }
        return nil
    }

    /// Скачать, проверить, подменить. После успеха вызывающий перезапускает приложение.
    static func install(_ u: MacUpdateInfo, progress: @escaping @Sendable (Double) -> Void) async throws {
        if let b = blocker { throw Failure(message: b) }
        guard let url = URL(string: u.url), url.scheme == "https" else { throw Failure(message: "Плохая ссылка на обновление") }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("bypen-update-\(u.build)-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // 1. скачать
        let zip = work.appendingPathComponent("Bypen.zip")
        try await download(url, to: zip, expected: u.size, progress: progress)

        // 2. сумма
        let digest = try sha256(of: zip)
        guard digest == u.sha256.lowercased() else { throw Failure(message: "Архив не сошёлся по контрольной сумме — обновление не ставлю") }

        // 3. распаковать и проверить подпись
        let out = work.appendingPathComponent("x")
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path])
        let app = out.appendingPathComponent("Bypen.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw Failure(message: "В архиве нет Bypen.app") }
        try verify(app: app, expectBuild: u.build)

        // 4. подменить: текущее → рядом с точкой в имени, новое → на место текущего
        let cur = Bundle.main.bundleURL
        let backup = cur.deletingLastPathComponent().appendingPathComponent(".Bypen-old-\(currentBuild).app")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.moveItem(at: cur, to: backup)
        do {
            try FileManager.default.moveItem(at: app, to: cur)
        } catch {
            try? FileManager.default.moveItem(at: backup, to: cur)
            throw Failure(message: "Не удалось поставить новую версию: \(error.localizedDescription)")
        }
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", cur.path])
        TunnelLog.shared.log("обновление \(u.version) (\(u.build)) поставлено, перезапуск")
    }

    /// Перезапуск из того же места (новое приложение) и выход из текущего.
    @MainActor static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1.5; /usr/bin/open -n \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// При запуске новой версии — убрать прежнюю, оставленную рядом.
    static func cleanupOld() {
        let dir = Bundle.main.bundleURL.deletingLastPathComponent()
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for name in items where name.hasPrefix(".Bypen-old-") && name.hasSuffix(".app") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    // MARK: проверки

    private static func verify(app: URL, expectBuild: Int) throws {
        // подпись цела и полная
        let v = try? run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        guard v != nil else { throw Failure(message: "Подпись новой версии не сходится — не ставлю") }
        // чья подпись и что за приложение
        let info = (try? run("/usr/bin/codesign", ["-dv", "--verbose=2", app.path])) ?? ""
        guard info.contains("TeamIdentifier=\(teamID)"), info.contains("Identifier=\(bundleID)") else {
            throw Failure(message: "Новая версия подписана не нами — не ставлю")
        }
        // заверена Apple (Gatekeeper её пропустит)
        guard (try? run("/usr/sbin/spctl", ["-a", "-t", "exec", app.path])) != nil else {
            throw Failure(message: "Новая версия не заверена Apple — не ставлю")
        }
        // номер сборки — тот, что обещан, и новее текущего
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let d = NSDictionary(contentsOf: plist),
              let b = Int(d["CFBundleVersion"] as? String ?? ""), b == expectBuild, b > currentBuild else {
            throw Failure(message: "Номер сборки в архиве не тот — не ставлю")
        }
    }

    /// Вывод (stdout+stderr) или ошибка при ненулевом коде.
    @discardableResult
    private static func run(_ path: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else { throw Failure(message: "\((path as NSString).lastPathComponent): \(out.prefix(300))") }
        return out
    }

    private static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func download(_ url: URL, to dest: URL, expected: Int?, progress: @escaping @Sendable (Double) -> Void) async throws {
        let (bytes, resp) = try await URLSession.shared.bytes(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(message: "Архив не скачался (\((resp as? HTTPURLResponse)?.statusCode ?? 0))") }
        let total = expected ?? Int(resp.expectedContentLength)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let h = try FileHandle(forWritingTo: dest)
        defer { try? h.close() }
        var buf = Data(); buf.reserveCapacity(1 << 20)
        var got = 0, lastReport = 0
        for try await b in bytes {
            buf.append(b)
            if buf.count >= 1 << 20 {
                try h.write(contentsOf: buf); got += buf.count; buf.removeAll(keepingCapacity: true)
                if total > 0, got - lastReport > total / 50 { lastReport = got; progress(Double(got) / Double(total)) }
            }
        }
        if !buf.isEmpty { try h.write(contentsOf: buf); got += buf.count }
        progress(1)
        if let e = expected, e > 0, got != e { throw Failure(message: "Архив скачан не целиком (\(got) из \(e) байт)") }
    }
}
