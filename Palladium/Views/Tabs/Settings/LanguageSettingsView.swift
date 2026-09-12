import SwiftUI

struct LanguageSettingsView: View {
    @Bindable private var language = AppLanguageSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("settings.language.title", selection: $language.selection) {
                    Text("settings.language.system").tag(AppLanguageSettings.system)
                    ForEach(language.availableLanguages, id: \.self) { code in
                        Text(verbatim: AppLanguageSettings.nativeName(for: code)).tag(code)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("settings.language.help")
            }
        }
        .navigationTitle("settings.language.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
