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
    @State private var withPassword = false
    var body: some View {
        ZStack {
            GlassBackground(t: t, active: false)
            VStack(spacing: 20) {
                Text("WYX").font(.system(size: 40, weight: .semibold)).foregroundStyle(t.text)
                Text("сеть").font(.system(size: 15)).foregroundStyle(t.subtitle).padding(.top, -14)
                Group {
                    if let bot = model.awaitingBot { waiting(bot) } else { form }
                }
                .padding(18).glassCard(t, radius: 20)
                if model.awaitingBot == nil {
                    Button("Нет аккаунта WYX") { NSWorkspace.shared.open(API.wyxDownloads) }
                        .buttonStyle(.plain).font(.subheadline.weight(.medium)).foregroundStyle(t.accent)
                    Button(withPassword ? "Войти через WYX" : "Войти паролем") { withPassword.toggle(); model.error = nil }
                        .buttonStyle(.plain).font(.footnote).foregroundStyle(t.muted)
                }
                Text("Бупень \(API.version)").font(.caption2).foregroundStyle(t.muted.opacity(0.6))
            }
            .padding(28)
        }
        .preferredColorScheme(t.scheme)
    }

    private var form: some View {
        VStack(spacing: 10) {
            TextField("Ник в WYX", text: $username).textFieldStyle(.plain).themedField(t).onSubmit { submit() }
            if withPassword {
                SecureField("Пароль", text: $password).textFieldStyle(.plain).themedField(t).onSubmit { submit() }
            }
            if let e = model.error { Text(e).font(.footnote).foregroundStyle(t.destructive).multilineTextAlignment(.center) }
            primary(model.busy ? "Отправляю…" : (withPassword ? "Войти" : "Войти через WYX")) { submit() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || model.busy)
            if !withPassword {
                Text("Бот «Бупень» пришлёт в WYX запрос на вход — подтвердите его там.")
                    .font(.footnote).foregroundStyle(t.muted).multilineTextAlignment(.center)
            }
        }
    }

    private func waiting(_ bot: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "paperplane.fill").font(.system(size: 28)).foregroundStyle(t.accent)
            Text("Подтвердите вход в WYX").font(.headline).foregroundStyle(t.text)
            Text("Бот «\(bot)» прислал вам сообщение. Нажмите в нём «Да, это я» — на телефоне или здесь, в WYX.")
                .font(.subheadline).foregroundStyle(t.subtitle).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView().controlSize(.small)
            if let wyx = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.hyax.messenger") {
                primary("Открыть WYX") { NSWorkspace.shared.openApplication(at: wyx, configuration: .init()) }
            }
            Button("Отмена") { model.cancelBotLogin() }.buttonStyle(.plain).font(.subheadline).foregroundStyle(t.muted)
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && (!withPassword || !password.isEmpty)
    }

    private func submit() {
        guard canSubmit, !model.busy else { return }
        if withPassword {
            Task { await model.login(username: username, password: password) }
        } else {
            model.loginViaWYX(username: username)
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(t.scheme == .dark ? t.accent : t.text, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(t.scheme == .dark ? t.primaryForeground : .white)
        }
        .buttonStyle(.plain)
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
    private var symbol: BigButtonSymbol.Kind {
        switch phase { case .on: return .checkShield; case .trouble: return .warnShield; case .checking, .busy: return .halfShield; case .off: return .power }
    }

    var body: some View {
        let on = phase == .on
        let working = phase == .busy || phase == .checking
        ZStack {
            GlassBackground(t: t, active: on)
            VStack(spacing: 16) {
                HStack {
                    GlassIconButton(t: t, system: "doc.text") { showLog = true }
                    Spacer()
                    VStack(spacing: 3) {
                        Text("WYX").font(.system(size: 24, weight: .semibold)).foregroundStyle(t.text)
                        Text("сеть").font(.system(size: 11)).foregroundStyle(t.subtitle)
                    }
                    Spacer()
                    GlassIconButton(t: t, system: "gearshape") { showSettings = true }
                }
                Spacer()
                Button {
                    Task { if model.isActive { model.disconnect() } else { await model.connect() } }
                } label: {
                    ZStack {
                        Circle().strokeBorder(t.accent.opacity(working ? 0.25 : 0), lineWidth: 1).frame(width: 200, height: 200)
                            .scaleEffect(working ? (breathe ? 1.25 : 1.05) : 1).opacity(breathe ? 0 : 1)
                        Circle()
                            .fill(on
                                  ? LinearGradient(colors: [t.buttonOnStart, t.buttonOnEnd], startPoint: UnitPoint(x: 0.2, y: 0.1), endPoint: UnitPoint(x: 0.8, y: 0.95))
                                  : LinearGradient(colors: [t.buttonIdleStart.opacity(working && t.scheme == .dark ? 0.85 : 1), t.buttonIdleEnd.opacity(working && t.scheme == .dark ? 0.85 : 1)], startPoint: UnitPoint(x: 0.2, y: 0.1), endPoint: UnitPoint(x: 0.8, y: 0.95)))
                            .frame(width: 200, height: 200)
                            .overlay(Circle().strokeBorder(on ? .clear : t.buttonIdleBorder, lineWidth: 1))
                            .shadow(color: on ? t.accent.opacity(0.47) : (working ? t.accent.opacity(0.48) : .clear), radius: on ? 50 : 30)
                            .scaleEffect(on ? (breathe ? 1.015 : 1) : 1)
                        VStack(spacing: 12) {
                            BigButtonSymbol(kind: symbol, t: t).scaleEffect(0.9)
                            Text(title).font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(on ? t.onSymbol : t.buttonIdleLabel)
                        .offset(y: 5)
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.busy || phase == .busy)
                .onAppear { withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true } }
                .animation(.easeInOut(duration: 0.5), value: phase)
                Spacer()
                if model.update != nil || model.updateError != nil { MacUpdateCard().environmentObject(model) }
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
            let stateColor: Color = phase == .on ? t.dotOk : (phase == .trouble ? t.dotBad : (phase == .off ? t.dotIdle : t.dotBusy))
            let text = phase == .on ? (model.settings.macTun ? "Трафик идёт через сеть WYX" : "Системный прокси ведёт в сеть WYX") : (phase == .trouble ? "Узел не отвечает, ищу другой" : (phase == .checking ? "Прокси включён, проверяю связь" : (phase == .busy ? "Секунду…" : "Не подключено")))
            HStack(spacing: 8) {
                Circle().fill(stateColor).frame(width: 8, height: 8).shadow(color: stateColor.opacity(0.9), radius: 5)
                Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(t.text)
            }
            if model.isActive {
                HStack(alignment: .top, spacing: 12) {
                    metric("Узел", model.status.nodeName ?? "—").frame(maxWidth: .infinity, alignment: .leading)
                    metric("Задержка", model.status.lastProbeMs.map { "\($0) мс" } ?? "…").fixedSize()
                    metric("Переключений", "\(model.status.switches)").fixedSize()
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
            Text(label).font(.system(size: 11)).foregroundStyle(t.muted)
            Text(value).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(t.text).lineLimit(1).truncationMode(.tail)
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
                if let u = model.update {
                    LabeledContent("Есть обновление", value: "\(u.version) (\(u.build))")
                    Button(model.updating ? "Обновляю…" : "Обновить и перезапустить") { Task { await model.installUpdate() } }
                        .disabled(model.updating)
                } else {
                    Button("Проверить обновления") { Task { await model.checkUpdate(manual: true) } }
                    if let d = model.updateChecked {
                        Text("Последняя версия · проверено \(d.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let e = model.updateError { Text(e).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped).frame(width: 440, height: 520)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
    }
}


/// Карточка «Есть обновление» над полем состояния.
struct MacUpdateCard: View {
    @EnvironmentObject var model: MacModel
    private var t: Theme { model.theme }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let u = model.update {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 18)).foregroundStyle(t.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Есть обновление \(u.version)").font(.system(size: 13, weight: .medium)).foregroundStyle(t.text)
                        if let n = u.notes, !n.isEmpty { Text(n).font(.system(size: 11)).foregroundStyle(t.muted).lineLimit(2) }
                    }
                    Spacer(minLength: 6)
                    Button { Task { await model.installUpdate() } } label: {
                        Text(model.updating ? "\(Int(model.updateProgress * 100))%" : "Обновить")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(t.scheme == .dark ? t.accent : t.text, in: Capsule())
                            .foregroundStyle(t.scheme == .dark ? t.primaryForeground : .white)
                    }
                    .buttonStyle(.plain).disabled(model.updating)
                }
                if model.updating { ProgressView(value: model.updateProgress).tint(t.accent) }
            }
            if let e = model.updateError { Text(e).font(.system(size: 11)).foregroundStyle(t.destructive) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).settingsCard(t, radius: 16)
    }
}
