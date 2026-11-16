import SwiftUI

/// Настройки по макету: заголовок по центру, секции «Оформление», «Переключение», «Узел» карточками
/// с лаймовой рамкой, тумблеры лайм/графит, пояснения под карточками.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    private var t: Theme { model.theme }
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLogout = false
    @State private var showTheme = false

    var body: some View {
        ZStack {
            GlassBackground(t: t, active: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Настройки").font(.system(size: 18, weight: .medium)).foregroundStyle(t.text)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 26).padding(.bottom, 26)

                    SettingsSection(t: t, title: "Оформление") {
                        Button { showTheme = true } label: {
                            SettingsRow(t: t, title: "Тема") {
                                Text(model.appearance == "light" ? "Мята светлая" : "Мята тёмная").foregroundStyle(t.scheme == .dark ? t.accent : t.text)
                                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.muted)
                            }
                        }
                        .confirmationDialog("Тема", isPresented: $showTheme, titleVisibility: .hidden) {
                            Button("Мята тёмная") { model.appearance = "dark" }
                            Button("Мята светлая") { model.appearance = "light" }
                        }
                    }

                    SettingsSection(t: t, title: "Переключение", footnote: "В простое (меньше 300 КБ за 10 минут) трафик уводится на другой живой узел, чтобы не идти всё время в одну точку") {
                        SettingsRow(t: t, title: "Переключать узел, если не отвечает") { MintToggle(t: t, isOn: $model.settings.autoSwitch) }
                        SettingsDivider(t: t)
                        SettingsRow(t: t, title: "Менять узел в простое") { MintToggle(t: t, isOn: $model.settings.rotateIdle) }
                        if model.settings.rotateIdle {
                            SettingsDivider(t: t)
                            SettingsRow(t: t, title: "Не чаще чем") {
                                Picker("", selection: $model.settings.rotateMinutes) {
                                    Text("30 минут").tag(30); Text("1 час").tag(60); Text("2 часа").tag(120); Text("4 часа").tag(240)
                                }
                                .labelsHidden().tint(t.scheme == .dark ? t.accent : t.text)
                            }
                        }
                    }

                    SettingsSection(t: t, title: "Узел", footnote: "Выбранный узел становится первым; если он не отвечает, приложение всё равно уйдёт на другой",
                                    trailing: AnyView(Button { Task { await model.refreshProfile(force: true) } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium)).foregroundStyle(t.muted) })) {
                        Button { model.settings.preferredNode = nil } label: {
                            SettingsRow(t: t, title: "Автоматически") {
                                if model.settings.preferredNode == nil { CheckMark(t: t) }
                            }
                        }
                        ForEach(model.profile?.nodes ?? []) { n in
                            SettingsDivider(t: t)
                            Button { Task { await model.select(node: n) } } label: {
                                HStack(spacing: 13) {
                                    Circle().fill(n.ok ? t.dotOk : t.dotBad).frame(width: 9, height: 9).shadow(color: (n.ok ? t.dotOk : t.dotBad).opacity(0.9), radius: 5)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(n.name).font(.system(size: 14)).foregroundStyle(t.text)
                                        Text("\(n.kind == "reality" ? "Reality" : "XHTTP") • \(n.ok ? (n.rtt_ms.map { "\($0) мс" } ?? "жив") : "не отвечает из Москвы")")
                                            .font(.system(size: 12)).foregroundStyle(t.muted)
                                    }
                                    Spacer()
                                    if model.status.nodeId == n.id && model.tunnel.isActive {
                                        Image(systemName: "shield.fill").font(.system(size: 13)).foregroundStyle(t.dotOk)
                                    } else if model.settings.preferredNode == n.id { CheckMark(t: t) }
                                }
                                .padding(.horizontal, 18).padding(.vertical, 12)
                            }
                        }
                    }

                    SettingsSection(t: t, title: "Аккаунт") {
                        SettingsRow(t: t, title: "Пользователь") { Text(model.username.map { "@\($0)" } ?? "—").foregroundStyle(t.muted) }
                        if let u = model.profile?.user.uuid {
                            SettingsDivider(t: t)
                            SettingsRow(t: t, title: "Ключ доступа") { Text(String(u.prefix(8)) + "…").foregroundStyle(t.muted) }
                        }
                        SettingsDivider(t: t)
                        Button { confirmLogout = true } label: { SettingsRow(t: t, title: "Выйти", color: t.destructive) {} }
                    }

                    SettingsSection(t: t, title: "О приложении") {
                        SettingsRow(t: t, title: "Версия") { Text(API.version).foregroundStyle(t.muted) }
                        SettingsDivider(t: t)
                        SettingsRow(t: t, title: "Ядро Xray") { Text(model.status.xrayVersion ?? "—").foregroundStyle(t.muted) }
                        SettingsDivider(t: t)
                        SettingsRow(t: t, title: "Сервер") { Text(API.shared.base.host ?? "").foregroundStyle(t.muted) }
                        SettingsDivider(t: t)
                        SettingsRow(t: t, title: "Подпись профиля") { Text(Pinned.publicKey == nil ? "не зашита (отладка)" : "проверяется").foregroundStyle(t.muted) }
                    }
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 17)
            }
        }
        .preferredColorScheme(t.scheme)
        .confirmationDialog("Выйти из аккаунта? VPN будет отключён.", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { model.logout(); dismiss() }
        }
    }
}

// MARK: детали оформления настроек

struct SettingsSection<Content: View>: View {
    let t: Theme
    let title: String
    var footnote: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(t.text)
                Spacer()
                if let trailing { trailing }
            }
            VStack(spacing: 0) { content }
                .buttonStyle(.plain)
                .settingsCard(t)
            if let footnote {
                Text(footnote).font(.system(size: 12)).foregroundStyle(t.footnote).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 26)
    }
}

struct SettingsRow<Trailing: View>: View {
    let t: Theme
    let title: String
    var color: Color? = nil
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 14)).foregroundStyle(color ?? t.text)
            Spacer(minLength: 8)
            trailing.font(.system(size: 14))
        }
        .padding(.horizontal, 18).frame(minHeight: 43)
        .contentShape(Rectangle())
    }
}

struct SettingsDivider: View {
    let t: Theme
    var body: some View { Rectangle().fill(t.divider).frame(height: 0.7).padding(.horizontal, 10) }
}

struct CheckMark: View {
    let t: Theme
    var body: some View {
        CheckShape().stroke(t.scheme == .dark ? t.accent : t.text, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            .frame(width: 18, height: 12.5)
    }
}

/// Тумблер из макета: капсула 49×30, лаймовая с тёмным кружком (вкл.) или графитовая (выкл.).
struct MintToggle: View {
    let t: Theme
    @Binding var isOn: Bool
    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) { isOn.toggle() }
            Haptic.tap()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? (t.scheme == .dark ? t.accent : t.text) : t.toggleOff)
                Circle().fill(t.scheme == .dark ? t.background : .white).padding(2.3)
            }
            .frame(width: 49, height: 30)
        }
        .buttonStyle(.plain)
    }
}
