// Палитра из макета Figma «vopoen» (16.11.2026): тёмная «Мята» по умолчанию, светлая — в настройках.
// Размеры макета 1177 px ≈ 3× pt, отсюда пропорции элементов.
import SwiftUI

struct Theme {
    let scheme: ColorScheme
    let background: Color
    let backgroundEnd: Color      // светлая: лёгкий зелёный уход к низу
    let text: Color
    let muted: Color              // подписи (#BDBDBD / #878787)
    let primary: Color            // лайм #C7F964 / тёмно-зелёный в светлой
    let primaryForeground: Color  // #2F5B53 — символы на лайме
    let primaryDeep: Color
    let accent: Color             // лайм везде
    let destructive: Color
    let success: Color
    let warning: Color
    // шапка: круглые кнопки
    let headerButton: Color
    let headerSymbol: Color
    // карточка статуса
    let cardStart: Color
    let cardEnd: Color
    let cardBorder: Color
    // карточки настроек
    let settingsCardStart: Color
    let settingsCardEnd: Color
    let settingsCardBorder: Color
    let divider: Color
    let toggleOff: Color
    // точки состояния
    let dotIdle: Color
    let dotOk: Color
    let dotBad: Color
    let dotBusy: Color
    // большая кнопка в покое
    let buttonIdleStart: Color
    let buttonIdleEnd: Color
    let buttonIdleBorder: Color
    let buttonIdleSymbol: Color
    // большая кнопка «защищено»: градиент 144° и цвет символа/подписи (#2F5B53 в обеих темах)
    let buttonOnStart: Color
    let buttonOnEnd: Color
    var onSymbol: Color { Color(hex: 0x2F5B53) }
    static let radius: CGFloat = 20

    static let mintDark = Theme(
        scheme: .dark,
        background: Color(hex: 0x222B27), backgroundEnd: Color(hex: 0x222B27),
        text: .white, muted: Color(hex: 0xBDBDBD),
        primary: Color(hex: 0xC7F964), primaryForeground: Color(hex: 0x2F5B53), primaryDeep: Color(hex: 0x9FCB45), accent: Color(hex: 0xC7F964),
        destructive: Color(hex: 0xC65A52), success: Color(hex: 0x489D8E), warning: Color(hex: 0xFBB104),
        headerButton: Color(hex: 0xC7F964), headerSymbol: Color(hex: 0x2F5B53),
        cardStart: Color(red: 50/255, green: 61/255, blue: 57/255, opacity: 0.7), cardEnd: Color(red: 63/255, green: 82/255, blue: 78/255, opacity: 0.7), cardBorder: Color(hex: 0xC4C4C4),
        settingsCardStart: Color(hex: 0x222B27), settingsCardEnd: Color(hex: 0x2D392B), settingsCardBorder: Color(hex: 0xC7F964).opacity(0.3),
        divider: Color(hex: 0xC7F964).opacity(0.15), toggleOff: Color(hex: 0x5D645C),
        dotIdle: Color(hex: 0x97A29C), dotOk: Color(hex: 0x489D8E), dotBad: Color(hex: 0xC65A52), dotBusy: Color(hex: 0xFBB104),
        buttonIdleStart: Color(hex: 0x464D45), buttonIdleEnd: Color(hex: 0x37403D), buttonIdleBorder: Color(hex: 0xC4C4C4), buttonIdleSymbol: .white,
        buttonOnStart: Color(hex: 0xC7F964), buttonOnEnd: Color(hex: 0xC7F964))

    static let mintLight = Theme(
        scheme: .light,
        background: .white, backgroundEnd: Color(hex: 0xE6EFDF),
        text: Color(hex: 0x2F5B53), muted: Color(hex: 0x878787),
        primary: Color(hex: 0x2F5B53), primaryForeground: .white, primaryDeep: Color(hex: 0x24473F), accent: Color(hex: 0xC7F964),
        destructive: Color(hex: 0xC65A52), success: Color(hex: 0x489D8E), warning: Color(hex: 0xE09A00),
        headerButton: .white, headerSymbol: Color(hex: 0x2F5B53),
        cardStart: .white, cardEnd: Color(hex: 0xE4E4E4), cardBorder: .white,
        settingsCardStart: .white, settingsCardEnd: .white, settingsCardBorder: .white,
        divider: Color(hex: 0xD9D9D9), toggleOff: Color(hex: 0xD9D9D9),
        dotIdle: Color(hex: 0x97A29C), dotOk: Color(hex: 0x489D8E), dotBad: Color(hex: 0xC65A52), dotBusy: Color(hex: 0xFBB104),
        buttonIdleStart: Color(hex: 0xC7F964).opacity(0.61), buttonIdleEnd: Color(hex: 0x489D8E).opacity(0.61), buttonIdleBorder: .clear, buttonIdleSymbol: Color(hex: 0x2F5B53),
        buttonOnStart: Color(hex: 0xC7F964), buttonOnEnd: Color(hex: 0x489D8E))

    static func named(_ id: String) -> Theme { id == "light" ? mintLight : mintDark }

    /// Подпись под «сеть» и мелкие тексты в шапке.
    var subtitle: Color { scheme == .dark ? Color(hex: 0xBDBDBD) : Color(hex: 0x9CB2AB) }
    /// Пояснения под карточками настроек.
    var footnote: Color { scheme == .dark ? Color(hex: 0xBDBDBD) : Color(hex: 0xA2A2A2) }
    /// Цвет надписи на большой кнопке в покое.
    var buttonIdleLabel: Color { scheme == .dark ? .white : Color(hex: 0x2F5B53) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct ThemedField: ViewModifier {
    let t: Theme
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [t.settingsCardStart, t.settingsCardEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(t.settingsCardBorder, lineWidth: 1))
            .foregroundStyle(t.text)
    }
}

extension View {
    func themedField(_ t: Theme) -> some View { modifier(ThemedField(t: t)) }
}
