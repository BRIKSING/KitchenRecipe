import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email    = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirm  = ""

    private var isValid: Bool {
        !email.isEmpty && !username.isEmpty && password.count >= 6 && password == confirm
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
                SecureField("Пароль (мин. 6 символов)", text: $password)
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
