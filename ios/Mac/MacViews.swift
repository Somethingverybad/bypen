import SwiftUI

struct MacRoot: View {
    @EnvironmentObject var model: MacModel
    var body: some View {
        if model.loggedIn { MacMainView() } else { MacLoginView() }
    }
}

struct MacLoginView: View {
    @EnvironmentObject var model: MacModel
    private var t: Theme { model.theme }
    @State private var username = ""
    @State private var password = ""
    var body: some View {
        ZStack {
            GlassBackground(t: t, active: false)
            VStack(spacing: 20) {
                Text("WYX").font(.system(size: 44, weight: .heavy)).tracking(-2).foregroundStyle(t.text)
                Text("сеть").font(.title3).foregroundStyle(t.muted).padding(.top, -16)
                VStack(spacing: 10) {
                    TextField("Ник или почта", text: $username).textFieldStyle(.plain).themedField(t)
                    SecureField("Пароль", text: $password).textFieldStyle(.plain).themedField(t)
                    if let e = model.error { Text(e).font(.footnote).foregroundStyle(t.destructive).multilineTextAlignment(.center) }
                    Button {
                        Task { await model.login(username: username, password: password) }
                    } label: {
                        Text(model.busy ? "Вхожу…" : "Войти").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(t.primary, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(t.primaryForeground)
                    }
                    .buttonStyle(.plain).keyboardShortcut(.defaultAction)
                    .disabled(username.isEmpty || password.isEmpty || model.busy)
                }
                .padding(18).glassCard(t, radius: 20)
                Text("Аккаунт тот же, что в мессенджере.").font(.footnote).foregroundStyle(t.muted)
                Text("Бупень \(API.version)").font(.caption2).foregroundStyle(t.muted.opacity(0.6))
            }
            .padding(28)
        }
        .preferredColorScheme(t.scheme)
    }
}

struct MacMainView: View {
    @EnvironmentObject var model: MacModel
    private var t: Theme { model.theme }
    @State private var showLog = false
    @State private var showSettings = false
    @State private var breathe = false

    private enum Phase { case off, busy, checking, on, trouble }
    private var phase: Phase {
        switch model.status.state {
        case .stopped: return .off
        case .starting, .switching: return .busy
        case .error: return .trouble
        case .connected: return model.status.failures > 0 ? .trouble : (model.status.lastProbeMs == nil ? .checking : .on)
        }
    }
    private var title: String {
        switch phase { case .off: return "Подключить"; case .busy: return "Секунду…"; case .checking: return "Проверяю…"; case .on: return "Защищено"; case .trouble: return "Нет ответа" }
    }
    private var color: Color {
        switch phase { case .off: return t.surface2; case .busy, .checking: return t.primaryDeep; case .on: return t.primary; case .trouble: return t.destructive }
    }

    var body: some View {
        ZStack {
            GlassBackground(t: t, active: phase == .on)
            VStack(spacing: 16) {
                HStack {
                    GlassIconButton(t: t, system: "doc.text") { showLog = true }
                    Spacer()
                    VStack(spacing: 0) {
                        Text("WYX").font(.system(size: 20, weight: .heavy)).tracking(-1).foregroundStyle(t.text)
                        Text("сеть").font(.caption).foregroundStyle(t.muted)
                    }
                    Spacer()
                    GlassIconButton(t: t, system: "gearshape") { showSettings = true }
                }
                Spacer()
                Button {
                    Task { if model.isActive { model.disconnect() } else { await model.connect() } }
                } label: {
                    ZStack {
                        Circle().fill(color.opacity(phase == .off ? 0 : 0.45)).frame(width: 220, height: 220).blur(radius: 36)
                            .scaleEffect(phase == .on ? (breathe ? 1.08 : 0.96) : 1)
                        Circle().fill(phase == .on ? AnyShapeStyle(LinearGradient(colors: [t.accent, t.primaryDeep], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(t.surface.opacity(0.8)))
                            .frame(width: 190, height: 190)
                            .overlay(Circle().strokeBorder(Color.white.opacity(t.scheme == .dark ? 0.4 : 0.9), lineWidth: 1.2))
                            .shadow(color: color.opacity(0.35), radius: 24, y: 10)
                        VStack(spacing: 8) {
                            Image(systemName: phase == .on ? "checkmark.shield.fill" : (phase == .trouble ? "exclamationmark.shield" : "power")).font(.system(size: 44, weight: .semibold))
                            Text(title).font(.title3.weight(.semibold))
                        }
                        .foregroundStyle(phase == .on ? t.primaryForeground : t.text)
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.busy || phase == .busy)
                .onAppear { withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true } }
                Spacer()
                statusBox
            }
            .padding(20)
        }
        .preferredColorScheme(t.scheme)
        .sheet(isPresented: $showLog) { MacLogView().environmentObject(model) }
        .sheet(isPresented: $showSettings) { MacSettingsView().environmentObject(model) }
    }

    private var statusBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            let stateColor: Color = phase == .on ? t.success : (phase == .trouble ? t.destructive : (phase == .off ? t.muted : t.warning))
            let text = phase == .on ? "Системный прокси ведёт в сеть WYX" : (phase == .trouble ? "Узел не отвечает, ищу другой" : (phase == .checking ? "Прокси включён, проверяю связь" : (phase == .busy ? "Секунду…" : "Не подключено")))
            HStack(spacing: 8) {
                Circle().fill(stateColor).frame(width: 8, height: 8).shadow(color: stateColor.opacity(0.8), radius: 5)
                Text(text).font(.subheadline.weight(.medium)).foregroundStyle(t.text)
            }
            if model.isActive {
                HStack {
                    metric("Узел", model.status.nodeName ?? "—")
                    metric("Задержка", model.status.lastProbeMs.map { "\($0) мс" } ?? "…")
                    metric("Переключений", "\(model.status.switches)")
                }
                if let e = model.status.lastError, model.status.failures > 0 { Text(e).font(.caption).foregroundStyle(t.destructive).lineLimit(2) }
            } else {
                HStack {
                    metric("Аккаунт", model.username.map { "@\($0)" } ?? "—")
                    metric("Узлов", model.profile.map { "\($0.nodes.filter(\.ok).count) из \($0.nodes.count)" } ?? "—")
                    metric("Выбор", model.settings.preferredNode.flatMap { id in model.profile?.nodes.first { $0.id == id }?.name } ?? "авто")
                }
            }
            if let n = model.profileNote { Text("⚠︎ \(n)").font(.caption).foregroundStyle(t.warning) }
            if let e = model.error { Text("⚠︎ \(e)").font(.caption).foregroundStyle(t.warning) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(t)
        .onTapGesture { showLog = true }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(t.muted)
            Text(value).font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(t.text).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MacLogView: View {
    @EnvironmentObject var model: MacModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Журнал").font(.headline)
                Spacer()
                Button("Очистить") { TunnelLog.shared.clear(); reload() }
                Button("Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView { Text(text.isEmpty ? "Пока пусто." : text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(16).frame(width: 560, height: 420)
        .onAppear(perform: reload).onReceive(timer) { _ in reload() }
    }
    private func reload() {
        let x = (try? String(contentsOf: AppGroup.xrayLogURL, encoding: .utf8)) ?? ""
        text = TunnelLog.shared.read() + (x.isEmpty ? "" : "\n— ядро Xray —\n" + x.suffix(4000))
    }
}

struct MacSettingsView: View {
    @EnvironmentObject var model: MacModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("Оформление") {
                Picker("Тема", selection: $model.appearance) { Text("Мята тёмная").tag("dark"); Text("Мята светлая").tag("light") }
            }
            Section("Режим") {
                Picker("Как пускать трафик", selection: $model.settings.macTun) {
                    Text("Системный прокси").tag(false)
                    Text("TUN — весь трафик").tag(true)
                }
                .disabled(model.isActive)
                Text(model.settings.macTun
                     ? "Виртуальный сетевой интерфейс: через туннель идут все программы, включая те, что не уважают прокси. При подключении один раз спросит пароль администратора."
                     : "SOCKS и HTTP-прокси в настройках сети. Программы, которые прокси не уважают, идут напрямую. Пароль не нужен.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.isActive { Text("Сменить режим можно после отключения.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Переключение") {
                Toggle("Переключать узел, если не отвечает", isOn: $model.settings.autoSwitch)
            }
            Section("Узел") {
                Picker("Выбор", selection: Binding(get: { model.settings.preferredNode ?? "" }, set: { model.settings.preferredNode = $0.isEmpty ? nil : $0 })) {
                    Text("Автоматически").tag("")
                    ForEach(model.profile?.nodes ?? []) { Text($0.name + ($0.ok ? "" : " (не отвечает)")).tag($0.id) }
                }
                Button("Обновить список узлов") { Task { await model.refreshProfile(force: true) } }
            }
            Section("Аккаунт") {
                LabeledContent("Пользователь", value: model.username.map { "@\($0)" } ?? "—")
                Button("Выйти", role: .destructive) { model.logout(); dismiss() }
            }
            Section("О приложении") {
                LabeledContent("Версия", value: API.version)
                LabeledContent("Ядро Xray", value: model.status.xrayVersion ?? "—")
            }
        }
        .formStyle(.grouped).frame(width: 440, height: 520)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
    }
}
