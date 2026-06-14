import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email    = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirm  = ""

    private var isValid: Bool {
        // Требования бэкенда: username 3–50 символов, пароль 8–100 символов
        !email.isEmpty && username.count >= 3 && password.count >= 8 && password == confirm
    }

    var body: some View {
        Form {
            Section("Учётная запись") {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)

                TextField("Имя пользователя", text: $username)
                    .autocapitalization(.none)
            }

            Section("Пароль") {
                SecureField("Пароль (мин. 8 символов)", text: $password)
                    .textContentType(.newPassword)

                SecureField("Повторите пароль", text: $confirm)
                    .textContentType(.newPassword)
            }

            Section {
                Button {
                    Task { await authVM.register(email: email, username: username, password: password) }
                } label: {
                    if authVM.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Создать аккаунт").frame(maxWidth: .infinity)
                    }
                }
                .disabled(!isValid || authVM.isLoading)
            }
        }
        .navigationTitle("Регистрация")
    }
}
