import SwiftUI

/// «Напрямую, мимо VPN»: российские сайты (список сети WYX) и свои адреса. Хранится в профиле
/// WYX на сервере — одно на все устройства человека; после сохранения VPN переподключается.
struct DirectSection: View {
    @EnvironmentObject var model: AppModel
    let t: Theme
    @State private var newEntry = ""
    @State private var askShare = false
    @State private var shareTo = ""

    var body: some View {
        SettingsSection(t: t, title: "Напрямую, мимо VPN", footnote: footnote,
                        trailing: model.directSaving ? AnyView(ProgressView().controlSize(.small)) : nil) {
            SettingsRow(t: t, title: "Российские сайты") { MintToggle(t: t, isOn: ruBinding) }
            ForEach(model.direct?.custom ?? [], id: \.self) { e in
                SettingsDivider(t: t)
                SettingsRow(t: t, title: DirectSection.label(e)) {
                    Button { remove(e) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(t.muted)
                    }
                }
            }
            SettingsDivider(t: t)
            HStack(spacing: 10) {
                TextField("", text: $newEntry, prompt: Text("example.com, .ru или =точный.адрес").foregroundStyle(t.muted))
                    .font(.system(size: 14)).foregroundStyle(t.text)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .submitLabel(.done).onSubmit { add() }
                Button { add() } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 20))
                        .foregroundStyle(t.scheme == .dark ? t.accent : t.text)
                }
                .disabled(newEntry.trimmingCharacters(in: .whitespaces).isEmpty || model.directSaving)
            }
            .padding(.horizontal, 18).frame(minHeight: 43)
            SettingsDivider(t: t)
            Button { shareTo = ""; askShare = true } label: {
                SettingsRow(t: t, title: "Поделиться по логину WYX", color: t.scheme == .dark ? t.accent : t.text) {
                    Image(systemName: "paperplane").font(.system(size: 14)).foregroundStyle(t.muted)
                }
            }
        }
        .task { await model.loadDirect() }
        .alert("Поделиться настройками", isPresented: $askShare) {
            TextField("Ник в WYX", text: $shareTo).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Отправить") { let u = shareTo; Task { await model.shareDirect(username: u) } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Бот «Бупень» пришлёт человеку ваши настройки — он сам решит, принять ли их.")
        }
    }

    private var footnote: String {
        var s = "Российские — зоны .ru, .su, .рф"
        if let n = model.direct?.ruCount, n > 4 { s += " и ещё \(n - 4) адресов из списка сети WYX" }
        s += ". Свои: example.com — вместе с поддоменами, .ru — вся зона, =example.com — только этот адрес. Хранится в аккаунте WYX — действует на всех устройствах."
        if let n = model.directNote { s = n + "\n" + s }
        if let e = model.directError { s = e + "\n" + s }
        return s
    }

    private var ruBinding: Binding<Bool> {
        Binding(get: { model.direct?.ru ?? true },
                set: { v in model.direct?.ru = v; Task { await model.saveDirect(ru: v) } })
    }

    private func add() {
        let e = newEntry.trimmingCharacters(in: .whitespaces)
        guard !e.isEmpty else { return }
        let list = (model.direct?.custom ?? []) + [e]
        Task { if await model.saveDirect(custom: list) { newEntry = "" } }
    }

    private func remove(_ e: String) {
        let list = (model.direct?.custom ?? []).filter { $0 != e }
        Task { await model.saveDirect(custom: list) }
    }

    /// «full:x» → «= x», зона без точки → «.ru», домен — как есть.
    static func label(_ e: String) -> String {
        if e.hasPrefix("full:") { return "= " + e.dropFirst(5) }
        return e.contains(".") ? e : "." + e
    }
}
