import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:3000"

    var body: some View {
        NavigationStack {
            Form {
                Section("Сервер") {
                    TextField("URL сервера", text: $serverURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .onChange(of: serverURL) { _, new in
                            UserDefaults.standard.set(new, forKey: "serverURL")
                            if let url = URL(string: new) {
                                APIClient.shared.updateBaseURL(url)
                            }
                        }
                }

                Section("Аккаунт") {
                    Button("Выйти", role: .destructive) {
                        authVM.logout()
                    }
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                }
            }
            .navigationTitle("Настройки")
        }
    }
}
