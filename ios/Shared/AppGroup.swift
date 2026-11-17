// Общее для приложения и расширения туннеля: где лежат файлы в контейнере App Group.
// Приложение пишет profile.json (проверенный подписью список узлов) и settings.json,
// расширение — status.json (состояние раз в несколько секунд), tunnel.log и events.jsonl
// (отчёты для сервера, приложение их отправляет и подрезает файл).
import Foundation

enum AppGroup {
    static let id = "group.com.hyax.bypen"
    static let appBundleId = "com.hyax.bypen"
    static let tunnelBundleId = "com.hyax.bypen.tunnel"

    static var container: URL {
        #if os(macOS)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bypen")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #else
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.temporaryDirectory
        #endif
    }
    static var profileURL: URL { container.appendingPathComponent("profile.json") }
    static var settingsURL: URL { container.appendingPathComponent("settings.json") }
    static var statusURL: URL { container.appendingPathComponent("status.json") }
    static var logURL: URL { container.appendingPathComponent("tunnel.log") }
    static var xrayLogURL: URL { container.appendingPathComponent("xray.log") }
    static var eventsURL: URL { container.appendingPathComponent("events.jsonl") }
}

/// Настройки, которые читает расширение (приложение правит их в «Настройках»).
struct TunnelSettings: Codable, Equatable {
    /// Переключаться на другой узел, когда текущий перестал отвечать.
    var autoSwitch = true
    /// В простое менять узел, чтобы трафик не шёл всё время в одну точку.
    var rotateIdle = true
    /// Не раньше чем через столько минут на одном узле.
    var rotateMinutes = 60
    /// Узел, выбранный вручную (nil — автоматически, живые первыми).
    var preferredNode: String?
    /// Мак: вместо системного прокси поднимать TUN (весь трафик, нужен пароль администратора).
    var macTun = false
    /// Версия формата: 2 — «менять узел в простое» включено по умолчанию (17.11.2026).
    var v = 2

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoSwitch = try c.decodeIfPresent(Bool.self, forKey: .autoSwitch) ?? true
        // Файлы до версии 2 хранили выключенную ротацию просто как прежнее значение по умолчанию —
        // включаем один раз; после этого выбор пользователя сохраняется.
        let version = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        rotateIdle = version < 2 ? true : (try c.decodeIfPresent(Bool.self, forKey: .rotateIdle) ?? true)
        rotateMinutes = try c.decodeIfPresent(Int.self, forKey: .rotateMinutes) ?? 60
        preferredNode = try c.decodeIfPresent(String.self, forKey: .preferredNode)
        macTun = try c.decodeIfPresent(Bool.self, forKey: .macTun) ?? false
    }

    static func load() -> TunnelSettings {
        guard let d = try? Data(contentsOf: AppGroup.settingsURL),
              let s = try? JSONDecoder().decode(TunnelSettings.self, from: d) else { return TunnelSettings() }
        return s
    }
    func save() {
        try? JSONEncoder().encode(self).write(to: AppGroup.settingsURL, options: .atomic)
    }
}
