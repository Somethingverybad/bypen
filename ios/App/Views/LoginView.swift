import SwiftUI

struct LoginView: View {
    @EnvironmentObject var model: AppModel
    private var t: Theme { model.theme }
    @State private var username = ""
    @State private var password = ""
    @State private var appeared = false

    var body: some View {
        ZStack {
            GlassBackground(t: t, active: false)
            VStack(spacing: 24) {
                Spacer()
                VStack(spacing: 2) {
                    Text("WYX").font(.system(size: 48, weight: .semibold)).foregroundStyle(t.text)
                    Text("сеть").font(.system(size: 17)).foregroundStyle(t.subtitle)
                }
                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)
                VStack(spacing: 12) {
                    TextField("", text: $username, prompt: Text("Ник или почта").foregroundStyle(t.muted))
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .themedField(t)
                    SecureField("", text: $password, prompt: Text("Пароль").foregroundStyle(t.muted))
                        .textContentType(.password)
                        .themedField(t)
                    if let e = model.error {
                        Text(e).font(.footnote).foregroundStyle(t.destructive).multilineTextAlignment(.center)
                    }
                    Button {
                        Haptic.tap()
                        Task { await model.login(username: username, password: password) }
                    } label: {
                        HStack {
                            if model.busy { ProgressView().tint(t.primaryForeground) }
                            Text("Войти").font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(t.scheme == .dark ? t.accent : t.text)
                        )
                        .shadow(color: t.scheme == .dark ? t.accent.opacity(0.45) : .black.opacity(0.2), radius: 16, y: 6)
                        .foregroundStyle(t.scheme == .dark ? t.primaryForeground : .white)
                    }
                    .disabled(username.isEmpty || password.isEmpty || model.busy)
                    .opacity(username.isEmpty || password.isEmpty ? 0.55 : 1)
                    .padding(.top, 4)
                }
                .padding(20)
                .settingsCard(t, radius: 24)
                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 24)
                Text("Аккаунт тот же, что в мессенджере. Доступ к сети выдаётся отдельно.")
                    .font(.footnote).foregroundStyle(t.muted).multilineTextAlignment(.center)
                Spacer()
                Text("Бупень \(API.version)").font(.caption2).foregroundStyle(t.muted.opacity(0.6))
            }
            .padding(24)
        }
        .preferredColorScheme(t.scheme)
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.2).delay(0.1)) { appeared = true } }
    }
}
