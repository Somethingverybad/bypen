import SwiftUI

/// Вход: ник в WYX → бот «Бупень» спрашивает там «Подтвердить вход?» → «Да».
/// Вход паролем — мелкой ссылкой (для проверяющих Apple и на всякий случай).
struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openURL) private var openURL
    private var t: Theme { model.theme }
    @State private var username = ""
    @State private var password = ""
    @State private var withPassword = false
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
                Group {
                    if let bot = model.awaitingBot { waiting(bot) } else { form }
                }
                .padding(20)
                .settingsCard(t, radius: 24)
                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 24)
                .animation(.spring(duration: 0.4), value: model.awaitingBot)
                if model.awaitingBot == nil {
                    VStack(spacing: 12) {
                        Button { openURL(API.wyxDownloads) } label: {
                            Text("Нет аккаунта WYX").font(.subheadline.weight(.medium)).foregroundStyle(t.accent)
                        }
                        Button { withAnimation { withPassword.toggle() }; model.error = nil } label: {
                            Text(withPassword ? "Войти через WYX" : "Войти паролем").font(.footnote).foregroundStyle(t.muted)
                        }
                    }
                }
                Spacer()
                Text("Бупень \(API.version)").font(.caption2).foregroundStyle(t.muted.opacity(0.6))
            }
            .padding(24)
        }
        .preferredColorScheme(t.scheme)
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.2).delay(0.1)) { appeared = true } }
    }

    private var form: some View {
        VStack(spacing: 12) {
            TextField("", text: $username, prompt: Text("Ник в WYX").foregroundStyle(t.muted))
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { submit() }
                .themedField(t)
            if withPassword {
                SecureField("", text: $password, prompt: Text("Пароль").foregroundStyle(t.muted))
                    .textContentType(.password)
                    .themedField(t)
            }
            if let e = model.error {
                Text(e).font(.footnote).foregroundStyle(t.destructive).multilineTextAlignment(.center)
            }
            primaryButton(withPassword ? "Войти" : "Войти через WYX", busy: model.busy) { submit() }
                .disabled(!canSubmit || model.busy)
                .opacity(canSubmit ? 1 : 0.55)
                .padding(.top, 4)
            if !withPassword {
                Text("Бот «Бупень» пришлёт в WYX запрос на вход — подтвердите его там.")
                    .font(.footnote).foregroundStyle(t.muted).multilineTextAlignment(.center)
            }
        }
    }

    private func waiting(_ bot: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "paperplane.fill").font(.system(size: 34)).foregroundStyle(t.accent)
            Text("Подтвердите вход в WYX").font(.title3.weight(.semibold)).foregroundStyle(t.text)
            Text("Бот «\(bot)» прислал вам сообщение. Нажмите в нём «Да, это я».")
                .font(.subheadline).foregroundStyle(t.subtitle).multilineTextAlignment(.center)
            ProgressView().tint(t.accent).padding(.vertical, 4)
            primaryButton("Открыть WYX", busy: false) {
                if let u = URL(string: "whoyax://") { openURL(u) }
            }
            Button("Отмена") { model.cancelBotLogin() }
                .font(.subheadline).foregroundStyle(t.muted)
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && (!withPassword || !password.isEmpty)
    }

    private func submit() {
        guard canSubmit, !model.busy else { return }
        Haptic.tap()
        if withPassword {
            Task { await model.login(username: username, password: password) }
        } else {
            model.loginViaWYX(username: username)
        }
    }

    private func primaryButton(_ title: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if busy { ProgressView().tint(t.scheme == .dark ? t.primaryForeground : .white) }
                Text(title).font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(t.scheme == .dark ? t.accent : t.text)
            )
            .shadow(color: t.scheme == .dark ? t.accent.opacity(0.45) : .black.opacity(0.2), radius: 16, y: 6)
            .foregroundStyle(t.scheme == .dark ? t.primaryForeground : .white)
        }
    }
}
