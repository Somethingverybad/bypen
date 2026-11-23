// Связь с сервером WYX: вход по аккаунту мессенджера (JWT), профиль узлов, отчёты.
// Сам сервер (hyax.ru) из России доступен — через него клиент и узнаёт, куда ходить.
import Foundation

struct APIError: LocalizedError {
    let message: String
    var unauthorized = false
    var errorDescription: String? { message }
}

final class API {
    static let shared = API()
    private let keychain = Keychain(service: "com.hyax.bypen")
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    var base: URL { URL(string: UserDefaults.standard.string(forKey: "apiBase") ?? Pinned.apiBase)! }
    var access: String? { get { keychain["access"] } set { keychain["access"] = newValue } }
    var refresh: String? { get { keychain["refresh"] } set { keychain["refresh"] = newValue } }
    var username: String? {
        get { UserDefaults.standard.string(forKey: "username") }
        set { UserDefaults.standard.set(newValue, forKey: "username") }
    }
    var isLoggedIn: Bool { refresh != nil }

    static var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] ?? "?") (\(i?["CFBundleVersion"] ?? "?"))"
    }
    #if os(macOS)
    static let platform = "mac"
    static let deviceName = "Бупень · Mac"
    #else
    static let platform = "ios"
    static let deviceName = "Бупень · iPhone"
    #endif
    static var appTag: String { "\(platform) \(version)" }

    var deviceId: String {
        if let d = UserDefaults.standard.string(forKey: "deviceId") { return d }
        let d = "bypen-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(d, forKey: "deviceId")
        return d
    }

    // MARK: вход

    func login(username: String, password: String) async throws {
        let body: [String: Any] = [
            "username": username, "password": password,
            "device_id": deviceId, "device_name": API.deviceName,
            "platform": API.platform, "app_version": API.version,
        ]
        let (data, resp) = try await send(path: "token/", method: "POST", body: body, auth: false)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard resp.statusCode == 200, let a = obj?["access"] as? String, let r = obj?["refresh"] as? String else {
            throw APIError(message: API.detail(obj) ?? "Не удалось войти (\(resp.statusCode))")
        }
        access = a
        refresh = r
        self.username = username
    }

    // MARK: вход через бота в WYX (сервер: chat/bypen_login.py)

    /// Где скачать WYX — для тех, у кого нет аккаунта.
    static let wyxDownloads = URL(string: "https://wyx.su/#download")!

    struct BotLoginRequest { let id: String; let secret: String; let expiresIn: Int; let interval: Int; let bot: String }

    enum BotLoginError: LocalizedError {
        case denied, expired
        var errorDescription: String? {
            switch self {
            case .denied: return "Вход отклонён в WYX"
            case .expired: return "Запрос устарел — попробуйте ещё раз"
            }
        }
    }

    /// Бот «Бупень» пишет человеку в WYX «Подтвердить вход?».
    func startBotLogin(username: String) async throws -> BotLoginRequest {
        let body: [String: Any] = [
            "username": username, "device_id": deviceId, "device_name": API.deviceName,
            "platform": API.platform, "app_version": API.version,
        ]
        let (data, resp) = try await send(path: "vpn/login/start/", method: "POST", body: body, auth: false)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard resp.statusCode == 200, let id = obj?["id"] as? String, let secret = obj?["secret"] as? String else {
            throw APIError(message: API.detail(obj) ?? "Не удалось отправить запрос (\(resp.statusCode))")
        }
        return BotLoginRequest(id: id, secret: secret, expiresIn: obj?["expires_in"] as? Int ?? 300,
                               interval: max(1, obj?["interval"] as? Int ?? 2), bot: obj?["bot"] as? String ?? "Бупень")
    }

    /// Ждать «Да» в WYX. Отмена задачи прерывает ожидание. Сетевые сбои по пути
    /// не страшны — спрашиваем снова, пока запрос не устарел.
    func waitBotLogin(_ r: BotLoginRequest) async throws {
        let deadline = Date().addingTimeInterval(TimeInterval(r.expiresIn + 10))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(r.interval) * 1_000_000_000)
            guard let (data, resp) = try? await send(path: "vpn/login/poll/", method: "POST",
                                                      body: ["id": r.id, "secret": r.secret], auth: false) else { continue }
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if resp.statusCode == 404 { throw BotLoginError.expired }
            guard resp.statusCode == 200 else { continue }
            switch obj?["status"] as? String {
            case "approved":
                guard let a = obj?["access"] as? String, let rf = obj?["refresh"] as? String else { throw BotLoginError.expired }
                access = a
                refresh = rf
                username = obj?["username"] as? String
                return
            case "denied": throw BotLoginError.denied
            case "expired", "used": throw BotLoginError.expired
            default: continue
            }
        }
        throw BotLoginError.expired
    }

    func logout() {
        access = nil
        refresh = nil
        username = nil
    }

    private func refreshTokens() async throws {
        guard let r = refresh else { throw APIError(message: "Нужно войти", unauthorized: true) }
        let (data, resp) = try await send(path: "token/refresh/", method: "POST", body: ["refresh": r], auth: false)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard resp.statusCode == 200, let a = obj?["access"] as? String else {
            if resp.statusCode == 401 || resp.statusCode == 400 { logout(); throw APIError(message: "Сеанс истёк — войдите снова", unauthorized: true) }
            throw APIError(message: API.detail(obj) ?? "Не удалось обновить сеанс (\(resp.statusCode))")
        }
        access = a
        if let nr = obj?["refresh"] as? String { refresh = nr }
    }

    // MARK: профиль и отчёты

    struct SignedProfile { let payload: String; let sig: String; let pub: String }

    func fetchProfile() async throws -> SignedProfile {
        let (data, resp) = try await authorized(path: "vpn/profile/", method: "GET")
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard resp.statusCode == 200 else {
            throw APIError(message: API.detail(obj) ?? "Профиль не получен (\(resp.statusCode))")
        }
        guard let payload = obj?["payload"] as? String else { throw APIError(message: "Профиль в неожиданном виде") }
        return SignedProfile(payload: payload, sig: obj?["sig"] as? String ?? "", pub: obj?["pub"] as? String ?? "")
    }

    // MARK: напрямую, мимо VPN — настройки в профиле WYX (сервер: chat/vpn.py VpnDirectView)

    struct DirectSettings: Equatable { var ru: Bool; var custom: [String]; var ruCount: Int }

    private static func direct(_ obj: [String: Any]?) -> DirectSettings {
        DirectSettings(ru: obj?["ru"] as? Bool ?? true, custom: obj?["custom"] as? [String] ?? [], ruCount: obj?["ru_count"] as? Int ?? 0)
    }

    func fetchDirect() async throws -> DirectSettings {
        let (data, resp) = try await authorized(path: "vpn/direct/", method: "GET")
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard resp.statusCode == 200 else { throw APIError(message: API.detail(obj) ?? "Настройки не получены (\(resp.statusCode))") }
        return API.direct(obj)
    }

    func saveDirect(ru: Bool? = nil, custom: [String]? = nil) async throws -> DirectSettings {
        var body: [String: Any] = [:]
        if let ru { body["ru"] = ru }
        if let custom { body["custom"] = custom }
        let (data, resp) = try await authorized(path: "vpn/direct/", method: "PUT", body: body)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard resp.statusCode == 200 else { throw APIError(message: API.detail(obj) ?? "Не сохранилось (\(resp.statusCode))") }
        return API.direct(obj)
    }

    /// Отправить свои настройки «напрямую» человеку по логину WYX — бот «Бупень» спросит его «Принять?».
    func shareDirect(username: String) async throws -> String {
        let (data, resp) = try await authorized(path: "vpn/direct/share/", method: "POST", body: ["username": username])
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard resp.statusCode == 200 else { throw APIError(message: API.detail(obj) ?? "Не отправилось (\(resp.statusCode))") }
        return obj?["username"] as? String ?? username
    }

    func report(_ events: [[String: Any]]) async throws -> Int {
        let (data, resp) = try await authorized(path: "vpn/report/", method: "POST", body: ["events": events])
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard resp.statusCode == 200 else { throw APIError(message: API.detail(obj) ?? "Отчёт не принят (\(resp.statusCode))") }
        return obj?["saved"] as? Int ?? 0
    }

    // MARK: низкий уровень

    private func authorized(path: String, method: String, body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        if access == nil { try await refreshTokens() }
        var (data, resp) = try await send(path: path, method: method, body: body, auth: true)
        if resp.statusCode == 401 {
            try await refreshTokens()
            (data, resp) = try await send(path: path, method: method, body: body, auth: true)
            if resp.statusCode == 401 { logout(); throw APIError(message: "Сеанс истёк — войдите снова", unauthorized: true) }
        }
        return (data, resp)
    }

    private func send(path: String, method: String, body: [String: Any]?, auth: Bool) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(API.appTag, forHTTPHeaderField: "X-WYX-App")
        req.setValue("Bypen/\(API.version) \(API.platform)", forHTTPHeaderField: "User-Agent")
        if auth, let a = access { req.setValue("Bearer \(a)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError(message: "Странный ответ сервера") }
            return (data, http)
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError(message: "Сервер недоступен: \(error.localizedDescription)")
        }
    }

    private static func detail(_ obj: [String: Any]?) -> String? {
        if let d = obj?["detail"] as? String { return d }
        if let d = obj?["error"] as? String { return d }
        if let d = obj?["non_field_errors"] as? [String] { return d.joined(separator: " ") }
        return nil
    }
}
