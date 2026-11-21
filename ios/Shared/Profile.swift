// Профиль «Сети WYX» — то, что отдаёт GET /api/vpn/profile/ (backend/chat/vpn.py).
// payload приходит строкой JSON и подписан Ed25519; хранится в App Group как есть.
import Foundation

struct VpnNode: Codable, Identifiable, Equatable {
    let id: String          // slug
    let name: String
    let kind: String        // "reality" | "xhttp"
    let host: String
    let port: Int
    let sni: String
    var ips: [String]? = nil
    let weight: Int
    let ok: Bool
    let rtt_ms: Int?
    let checked_at: String?
    // reality
    var pbk: String? = nil
    var sid: String? = nil
    var fp: String? = nil
    var flow: String? = nil
    // xhttp
    var path: String? = nil
    var mode: String? = nil
    var alpn: [String]? = nil

    /// Куда реально подключаться: IP из Москвы (пробник), иначе имя.
    var dialAddress: String { ips?.first ?? host }
    /// Адреса, которые в режиме TUN должны идти мимо туннеля (иначе ядро само себя закольцует).
    var dialIPs: [String] {
        if let ips, !ips.isEmpty { return ips }
        let isIP = host.allSatisfy { $0.isHexDigit || $0 == "." || $0 == ":" } && host.contains(where: { $0 == "." || $0 == ":" })
        return isIP ? [host] : []
    }
    var isReality: Bool { kind == "reality" }
}

struct VpnUser: Codable, Equatable {
    let id: String
    let username: String
    let uuid: String
    let email: String
}

/// Куда ходить напрямую, мимо узла: сам WYX и его хранилища (они в России). Приходит в
/// подписанном профиле; встроенный список — на случай старого сервера или пустого ответа.
struct DirectList: Codable, Equatable {
    var domains: [String] = []
    var cidrs: [String] = []

    static let builtin = DirectList(
        domains: ["hyax.ru", "wyx.su", "huyax.e-tree.su", "storage.yandexcloud.net",
                  "43fb9b03-c74c-45ab-b258-7872345451b3.selcdn.net"],
        cidrs: ["194.164.245.144/32"])

    func merged(_ other: DirectList?) -> DirectList {
        guard let other else { return self }
        func uniq(_ a: [String]) -> [String] { var seen = Set<String>(); return a.filter { seen.insert($0.lowercased()).inserted } }
        return DirectList(domains: uniq(domains + other.domains), cidrs: uniq(cidrs + other.cidrs))
    }

    /// (адрес, длина префикса) для исключения маршрутов; кривые записи пропускаются.
    var parsedCIDRs: [(addr: String, prefix: Int, v6: Bool)] {
        cidrs.compactMap { c in
            let parts = c.split(separator: "/", maxSplits: 1).map(String.init)
            guard let a = parts.first, !a.isEmpty else { return nil }
            let v6 = a.contains(":")
            let def = v6 ? 128 : 32
            let pref = parts.count > 1 ? (Int(parts[1]) ?? def) : def
            guard pref >= 0, pref <= def else { return nil }
            return (a, pref, v6)
        }
    }
}

struct VpnProfile: Codable, Equatable {
    let v: Int
    let issued_at: String
    let ttl: Int
    let user: VpnUser
    let nodes: [VpnNode]
    var direct: DirectList? = nil

    /// Итоговый список «напрямую»: встроенный + с сервера.
    var directList: DirectList { DirectList.builtin.merged(direct) }

    static func decode(_ text: String) throws -> VpnProfile {
        try JSONDecoder().decode(VpnProfile.self, from: Data(text.utf8))
    }

    /// Сохранённый приложением (уже проверенный) профиль.
    static func loadSaved() -> VpnProfile? {
        guard let d = try? Data(contentsOf: AppGroup.profileURL),
              let text = String(data: d, encoding: .utf8) else { return nil }
        return try? decode(text)
    }

    /// Порядок попыток: выбранный вручную первым, дальше как отдал сервер (живые первыми).
    func order(preferred: String?) -> [VpnNode] {
        guard let p = preferred, let i = nodes.firstIndex(where: { $0.id == p }) else { return nodes }
        var list = nodes
        let n = list.remove(at: i)
        list.insert(n, at: 0)
        return list
    }
}
