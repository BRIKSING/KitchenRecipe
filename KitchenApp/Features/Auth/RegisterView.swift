import SwiftUI

// MARK: - RegisterView

/// Экран регистрации нового аккаунта.
///
/// Форма с email, именем пользователя, паролем и его подтверждением. Локальная
/// валидация (``isValid``) повторяет правила Zod-схемы бэкенда, чтобы не слать
/// заведомо отклоняемый запрос. Регистрация выполняется через
/// `authVM.register(...)`; при успехе пользователь сразу авторизован (токены
/// выданы вместе с ответом), и корневой `App` переключается на `MainTabView`.
struct RegisterView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email    = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirm  = ""

    // Валидация повторяет registerBodySchema бекенда (Zod), чтобы не отправлять
    // заведомо отклоняемый запрос: username — 3–50 символов из латиницы/цифр/«_»,
    // password — 8–100 символов. Иначе бэкенд возвращает 400 VALIDATION_ERROR.
    private var isValid: Bool {
        email.contains("@") &&
        (3...50).contains(username.count) &&
        username.allSatisfy { ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_" } &&
        (8...100).contains(password.count) &&
        password == confirm
    }

    var body: some View {
        Form {
            Section("Учётная запись") {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)

                TextField("Имя пользователя (3–50, латиница/цифры/_)", text: $username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
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
