import NetworkExtension
import SwiftUI

/// Главный экран по макету: шапка «WYX / сеть» с двумя лаймовыми кнопками, большая круглая кнопка
/// (в покое — графит с рамкой и символом питания; проверка — тот же диск со свечением и кольцами;
/// защищено — сплошной лайм с широким свечением и щитом), внизу карточка состояния с тремя колонками.
struct MainView: View {
    @EnvironmentObject var model: AppModel
    private var t: Theme { model.theme }
    @State private var showLog = false
    @State private var showSettings = false
    @State private var pulse = false
    @State private var breathe = false
    @State private var pressed = false
    @State private var lastPhase: Phase = .off

    var body: some View {
        ZStack {
            GlassBackground(t: t, active: phase == .on)
            VStack(spacing: 0) {
                header
                Spacer(minLength: 24)
                bigButton
                Spacer(minLength: 24)
                statusBox
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .preferredColorScheme(t.scheme)
        .sheet(isPresented: $showLog) { LogView() }
        .sheet(isPresented: $showSettings) { SettingsView().presentationDragIndicator(.visible) }
        .onAppear { if ProcessInfo.processInfo.environment["BYPEN_PREVIEW_SETTINGS"] != nil { showSettings = true } }
        .onChange(of: phase) { _, p in
            if p == .on, lastPhase != .on { Haptic.success() }
            if p == .trouble, lastPhase != .trouble { Haptic.warning() }
            lastPhase = p
        }
    }

    private var header: some View {
        HStack {
            GlassIconButton(t: t, system: "doc.text") { showLog = true }
            Spacer()
            VStack(spacing: 4) {
                Text("WYX").font(.system(size: 27, weight: .semibold)).foregroundStyle(t.text)
                Text("сеть").font(.system(size: 12)).foregroundStyle(t.subtitle)
            }
            Spacer()
            GlassIconButton(t: t, system: "gearshape") { showSettings = true }
        }
        .padding(.top, 8)
    }

    // MARK: состояние

    enum Phase { case off, busy, checking, on, trouble }

    private var phase: Phase {
        switch model.vpnStatus {
        case .connected:
            if model.status.state == .switching { return .busy }
            if model.status.state == .error || model.status.failures > 0 { return .trouble }
            return model.status.lastProbeMs == nil ? .checking : .on
        case .connecting, .reasserting, .disconnecting: return .busy
        default: return .off
        }
    }

    private var title: String {
        switch phase {
        case .off: return "Подключить"
        case .busy: return model.vpnStatus == .disconnecting ? "Отключаю…" : (model.status.state == .switching ? "Меняю узел…" : "Подключаю…")
        case .checking: return "Проверяю…"
        case .on: return "Защищено"
        case .trouble: return "Нет ответа"
        }
    }

    private var symbol: BigButtonSymbol.Kind {
        switch phase {
        case .on: return .checkShield
        case .trouble: return .warnShield
        case .checking, .busy: return .halfShield
        case .off: return .power
        }
    }

    // MARK: кнопка

    private var bigButton: some View {
        let on = phase == .on
        let working = phase == .busy || phase == .checking
        let size: CGFloat = 227
        return Button {
            Haptic.tap()
            Task {
                if model.tunnel.isActive { model.disconnect() } else { await model.connect() }
            }
        } label: {
            ZStack {
                // кольца «на воде» при проверке (Ellipse 5 макета: 800 px, лайм 25 %)
                ForEach(0..<2, id: \.self) { i in
                    Circle().strokeBorder(t.accent.opacity(working ? 0.25 : 0), lineWidth: 1)
                        .frame(width: size, height: size)
                        .scaleEffect(pulse ? 1.22 + CGFloat(i) * 0.1 : 1.0)
                        .opacity(pulse ? 0 : 1)
                        .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(i) * 0.8), value: pulse)
                }
                // диск: покой — графит (тёмная) или лайм→бирюза 61 % (светлая); проверка — то же, прозрачнее в тёмной,
                // со свечением 100 px; защищено — сплошной лайм (тёмная) или лайм→бирюза (светлая) со свечением 243 px
                Circle()
                    .fill(
                        on
                        ? LinearGradient(colors: [t.buttonOnStart, t.buttonOnEnd], startPoint: UnitPoint(x: 0.2, y: 0.1), endPoint: UnitPoint(x: 0.8, y: 0.95))
                        : LinearGradient(colors: [t.buttonIdleStart.opacity(working && t.scheme == .dark ? 0.85 : 1), t.buttonIdleEnd.opacity(working && t.scheme == .dark ? 0.85 : 1)],
                                         startPoint: UnitPoint(x: 0.2, y: 0.1), endPoint: UnitPoint(x: 0.8, y: 0.95))
                    )
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(on ? .clear : t.buttonIdleBorder, lineWidth: 1))
                    .shadow(color: on ? t.accent.opacity(t.scheme == .dark ? 0.47 : 0.8) : (working ? t.accent.opacity(t.scheme == .dark ? 0.48 : 0.7) : .clear), radius: on ? 60 : 33)
                    .shadow(color: on ? t.accent.opacity(0.35) : .clear, radius: 30)
                    .scaleEffect(on ? (breathe ? 1.015 : 1) : 1)
                VStack(spacing: 14) {
                    BigButtonSymbol(kind: symbol, t: t)
                        .scaleEffect(working && breathe ? 1.06 : 1)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .contentTransition(.opacity)
                }
                .foregroundStyle(on ? t.onSymbol : t.buttonIdleLabel)
                .offset(y: 6)
            }
            .scaleEffect(pressed ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .disabled(model.busy || model.vpnStatus == .connecting || model.vpnStatus == .disconnecting)
        .onAppear {
            pulse = true
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
        }
        .animation(.spring(duration: 0.35, bounce: 0.25), value: pressed)
        .animation(.easeInOut(duration: 0.5), value: phase)
    }

    // MARK: поле состояния

    private var stateColor: Color {
        switch phase {
        case .on: return t.dotOk
        case .trouble: return t.dotBad
        case .off: return t.dotIdle
        default: return t.dotBusy
        }
    }

    private var stateText: String {
        switch phase {
        case .on: return "Трафик идёт через сеть WYX"
        case .trouble: return "Узел не отвечает, ищу другой"
        case .checking: return "Туннель поднят, проверяю связь"
        case .busy: return "Секунду…"
        case .off: return "Не подключено"
        }
    }

    private var statusBox: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                Circle().fill(stateColor).frame(width: 9, height: 9)
                    .shadow(color: stateColor.opacity(0.9), radius: 5)
                Text(stateText).font(.system(size: 14, weight: .medium)).foregroundStyle(t.text)
                    .contentTransition(.opacity)
                Spacer()
            }
            if model.tunnel.isActive {
                // колонки макета (x = 56 / 441 / 707 из 941 px): 41 % / 28 % / 31 %
                columns([0.41, 0.28, 0.31], [
                    ("Узел", model.status.nodeName ?? "—"),
                    ("Задержка", model.status.lastProbeMs.map { "\($0) мс" } ?? "…"),
                    ("Трафик", "↑\(bytes(model.status.up)) ↓\(bytes(model.status.down))"),
                ])
                if let e = model.status.lastError, model.status.failures > 0 {
                    Text(e).font(.caption).foregroundStyle(t.destructive).lineLimit(2)
                }
            } else {
                // колонки макета: 0 / 41 % / 78 % ширины
                columns([0.41, 0.37, 0.22], [
                    ("Аккаунт", model.username.map { "@\($0)" } ?? "—"),
                    ("Узлов", model.profile.map { "\($0.nodes.filter(\.ok).count) из \($0.nodes.count)" } ?? "—"),
                    ("Выбор", model.settings.preferredNode.flatMap { id in model.profile?.nodes.first { $0.id == id }?.name } ?? "авто"),
                ])
            }
            if let note = model.profileNote { warn(note) }
            if let e = model.error { warn(e) }
        }
        .padding(.horizontal, 18).padding(.vertical, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(t)
        .onTapGesture { showLog = true }
        .animation(.easeInOut(duration: 0.3), value: model.status)
    }

    /// Три колонки по долям ширины карточки (как в макете); длинное значение режется многоточием.
    private func columns(_ fractions: [CGFloat], _ items: [(String, String)]) -> some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.0).font(.system(size: 12)).foregroundStyle(t.muted)
                        Text(item.1).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(t.text)
                            .lineLimit(1).minimumScaleFactor(0.85).truncationMode(.tail)
                            .contentTransition(.numericText())
                    }
                    .padding(.trailing, 4)
                    .frame(width: geo.size.width * fractions[i], alignment: .leading)
                }
            }
        }
        .frame(height: 34)
    }

    private func warn(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(t.warning)
            Text(text).font(.caption).foregroundStyle(t.muted)
        }
    }

    private func bytes(_ b: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .binary)
    }
}
