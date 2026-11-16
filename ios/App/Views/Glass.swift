// Фон, карточки и кнопки по макету Figma «vopoen»: «круги на воде» — два размытых пятна
// (оливковое вверху и бирюзовое внизу справа), карточки с градиентом и тонкой рамкой,
// круглые лаймовые кнопки шапки с мягким свечением.
import SwiftUI

/// Фон: цвет темы и размытые пятна из макета. Пятна медленно плывут.
struct GlassBackground: View {
    let t: Theme
    var active: Bool
    @State private var drift = false

    var body: some View {
        // Color.clear занимает весь экран, пятна — в overlay: они не раздувают раскладку
        // (в ZStack большие размытые круги делали экран шире телефона — контент вылезал за края).
        Color.clear.overlay {
          GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [t.background, t.backgroundEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
                // Координаты из макета (кадр 1177×2559): Ellipse 1 — центр (316, 428), 1056×1024, #2E471C 69 %;
                // Ellipse 2 — центр (844, 2199), 962×936, #489D8E 33 %; размытие σ 283 px ≈ 94 pt.
                if t.scheme == .dark {
                    Ellipse()
                        .fill(Color(hex: 0x2E471C).opacity(0.69))
                        .frame(width: w * 0.897, height: w * 0.87)
                        .blur(radius: 90)
                        .position(x: w * (drift ? 0.30 : 0.268), y: h * (drift ? 0.18 : 0.167))
                }
                Ellipse()
                    .fill(Color(hex: 0x489D8E).opacity(0.33))
                    .frame(width: w * 0.817, height: w * 0.795)
                    .blur(radius: 90)
                    .position(x: w * (drift ? 0.69 : 0.717), y: h * (drift ? 0.845 : 0.859))
                if active {
                    Circle()
                        .fill(t.accent.opacity(0.10))
                        .frame(width: w * 1.3, height: w * 1.3)
                        .blur(radius: 110)
                        .position(x: w / 2, y: h * 0.48)
                }
            }
          }
        }
        .clipped()
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) { drift = true }
        }
        .animation(.easeInOut(duration: 0.8), value: active)
    }
}

/// Карточка статуса: градиент 41°, рамка 1 pt, радиус 20.
struct GlassCard: ViewModifier {
    let t: Theme
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [t.cardStart, t.cardEnd], startPoint: .bottomLeading, endPoint: .topTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(t.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(t.scheme == .dark ? 0.25 : 0.2), radius: 17, y: 4)
    }
}

/// Карточка настроек: тёмный градиент с лаймовой рамкой 30 % (светлая — белая), тень 0 13 50 20 %.
struct SettingsCard: ViewModifier {
    let t: Theme
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(stops: [.init(color: t.settingsCardStart, location: 0.25), .init(color: t.settingsCardEnd, location: 0.82),
                                                 .init(color: t.scheme == .dark ? t.accent.opacity(0.35) : t.settingsCardEnd, location: 2.5)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(t.settingsCardBorder, lineWidth: 0.7))
            .shadow(color: .black.opacity(0.2), radius: 17, y: 4)
    }
}

/// Круглая кнопка шапки: лаймовый диск со свечением (светлая: белый с тенью), тёмно-зелёный символ.
struct GlassIconButton: View {
    let t: Theme
    let system: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(t.headerSymbol)
                .frame(width: 40, height: 40)
                .background(Circle().fill(t.headerButton))
                .shadow(color: t.scheme == .dark ? t.accent.opacity(0.6) : .clear, radius: 9)
                .shadow(color: .black.opacity(0.2), radius: 17, y: 4)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func glassCard(_ t: Theme, radius: CGFloat = 20) -> some View { modifier(GlassCard(t: t, radius: radius)) }
    func settingsCard(_ t: Theme, radius: CGFloat = 20) -> some View { modifier(SettingsCard(t: t, radius: radius)) }
}

/// Символ питания из макета: дуга с разрывом сверху и вертикальная черта.
struct PowerSymbol: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY + r.height * 0.05)
        let rad = min(r.width, r.height) * 0.42
        p.addArc(center: c, radius: rad, startAngle: .degrees(-60), endAngle: .degrees(240), clockwise: false)
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.midY - r.height * 0.02))
        return p
    }
}

/// Щит из макета (контур Feather «shield»): верх — ровная кромка, низ — остриё.
struct ShieldShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX + w * 0.5, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w * 0.95, y: r.minY + h * 0.17))
        p.addQuadCurve(to: CGPoint(x: r.minX + w, y: r.minY + h * 0.27), control: CGPoint(x: r.minX + w, y: r.minY + h * 0.19))
        p.addLine(to: CGPoint(x: r.minX + w, y: r.minY + h * 0.46))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.5, y: r.minY + h), control1: CGPoint(x: r.minX + w, y: r.minY + h * 0.78), control2: CGPoint(x: r.minX + w * 0.78, y: r.minY + h * 0.92))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.46), control1: CGPoint(x: r.minX + w * 0.22, y: r.minY + h * 0.92), control2: CGPoint(x: r.minX, y: r.minY + h * 0.78))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.27))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.05, y: r.minY + h * 0.17), control: CGPoint(x: r.minX, y: r.minY + h * 0.19))
        p.closeSubpath()
        return p
    }
}

/// Галочка из макета.
struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.33, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// Символ на большой кнопке по состоянию.
struct BigButtonSymbol: View {
    enum Kind { case power, halfShield, checkShield, warnShield }
    let kind: Kind
    let t: Theme
    var body: some View {
        ZStack {
            switch kind {
            case .power:
                PowerSymbol().stroke(t.buttonIdleSymbol, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 52, height: 54)
            case .halfShield:
                ShieldShape().stroke(t.buttonIdleSymbol, style: StrokeStyle(lineWidth: 6, lineJoin: .round))
                    .frame(width: 56, height: 68)
                ShieldShape().fill(t.buttonIdleSymbol.opacity(0.75))
                    .frame(width: 56, height: 68)
                    .mask(alignment: .leading) { Rectangle().frame(width: 28) }
            case .checkShield:
                ShieldShape().fill(t.onSymbol).frame(width: 56, height: 68)
                ShieldShape().stroke(t.onSymbol, style: StrokeStyle(lineWidth: 6, lineJoin: .round)).frame(width: 56, height: 68)
                CheckShape().stroke(t.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .frame(width: 23, height: 16).offset(y: -2)
            case .warnShield:
                ShieldShape().stroke(t.destructive, style: StrokeStyle(lineWidth: 6, lineJoin: .round)).frame(width: 56, height: 68)
                Text("!").font(.system(size: 34, weight: .bold)).foregroundStyle(t.destructive).offset(y: -4)
            }
        }
        .frame(width: 60, height: 70)
    }
}

enum Haptic {
    #if canImport(UIKit)
    static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    #else
    static func tap() {}
    static func success() {}
    static func warning() {}
    #endif
}
