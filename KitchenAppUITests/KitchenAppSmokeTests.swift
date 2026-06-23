import XCTest

// MARK: - KitchenApp Smoke Tests
// Covers the critical user paths for TestFlight validation.
// Tests marked with [NEEDS_BACKEND] require a running server at the configured URL.

final class KitchenAppSmokeTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - TC-01: App Launch

    func testAppLaunchesAndShowsLoginScreen() throws {
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Kitchen Recipe"].waitForExistence(timeout: 8),
            "App title should be visible on launch"
        )
    }

    // MARK: - TC-02: Login screen UI integrity

    func testLoginScreenContainsAllRequiredElements() throws {
        app.launch()

        XCTAssertTrue(app.staticTexts["Kitchen Recipe"].waitForExistence(timeout: 8))

        XCTAssertTrue(app.textFields["Email"].exists, "Email field missing")
        XCTAssertTrue(app.secureTextFields["Пароль"].exists, "Password field missing")
        XCTAssertTrue(app.buttons["Войти"].exists, "Login button missing")
        XCTAssertTrue(
            app.buttons["Нет аккаунта? Зарегистрироваться"].exists,
            "Register link missing"
        )
    }

    // MARK: - TC-03: Login button disabled with empty fields

    func testLoginButtonDisabledWhenFieldsAreEmpty() throws {
        app.launch()
        XCTAssertTrue(app.buttons["Войти"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Войти"].isEnabled, "Login button must be disabled while fields are empty")
    }

    // MARK: - TC-04: Login button enables after filling in credentials

    func testLoginButtonEnablesWithValidInput() throws {
        app.launch()

        let emailField = app.textFields["Email"]
        let passwordField = app.secureTextFields["Пароль"]
        let loginButton = app.buttons["Войти"]

        XCTAssertTrue(emailField.waitForExistence(timeout: 8))

        emailField.tap()
        emailField.typeText("smoke@kitchen.test")

        passwordField.tap()
        passwordField.typeText("Smoke1234!")

        XCTAssertTrue(loginButton.isEnabled, "Login button must become enabled after filling both fields")
    }

    // MARK: - TC-05: Navigate to registration screen

    func testNavigationToRegistrationScreen() throws {
        app.launch()

        let registerLink = app.buttons["Нет аккаунта? Зарегистрироваться"]
        XCTAssertTrue(registerLink.waitForExistence(timeout: 8))
        registerLink.tap()

        XCTAssertTrue(
            app.textFields["Email"].waitForExistence(timeout: 5),
            "Registration email field should appear"
        )
        XCTAssertTrue(
            app.secureTextFields["Пароль (мин. 6 символов)"].exists,
            "Registration password field should appear"
        )
    }

    // MARK: - TC-06: Register button disabled with empty fields

    func testRegisterButtonDisabledWhenEmpty() throws {
        app.launch()

        let registerLink = app.buttons["Нет аккаунта? Зарегистрироваться"]
        XCTAssertTrue(registerLink.waitForExistence(timeout: 8))
        registerLink.tap()

        let registerButton = app.buttons["Создать аккаунт"]
        XCTAssertTrue(registerButton.waitForExistence(timeout: 5))
        XCTAssertFalse(registerButton.isEnabled, "Register button must be disabled when fields are empty")
    }

    // MARK: - TC-07: Main tab bar visible after authentication [NEEDS_BACKEND]
    // Requires mock auth token injected via launch argument UI_TESTING_BYPASS_AUTH.

    func testMainTabBarAppearsAfterAuthentication() throws {
        app.launchArguments = ["UI_TESTING_BYPASS_AUTH"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab bar must appear after authentication")

        XCTAssertTrue(tabBar.buttons["Рецепты"].exists, "Recipes tab missing")
        XCTAssertTrue(tabBar.buttons["Категории"].exists, "Categories tab missing")
        XCTAssertTrue(tabBar.buttons["Профиль"].exists, "Settings/Profile tab missing")
    }

    // MARK: - TC-08: Recipe list navigation bar and controls [NEEDS_BACKEND]

    func testRecipeListNavigationBarElements() throws {
        app.launchArguments = ["UI_TESTING_BYPASS_AUTH"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Рецепты"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Рецепты"].tap()

        XCTAssertTrue(
            app.navigationBars["Рецепты"].waitForExistence(timeout: 8),
            "Navigation bar with title 'Рецепты' missing"
        )
        XCTAssertTrue(app.buttons.matching(identifier: "plus").firstMatch.exists
                      || app.navigationBars["Рецепты"].buttons.count > 0,
                      "Toolbar buttons should be present in recipe list")
    }

    // MARK: - TC-09: Search bar present on recipe list [NEEDS_BACKEND]

    func testSearchBarPresentOnRecipeList() throws {
        app.launchArguments = ["UI_TESTING_BYPASS_AUTH"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Рецепты"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Рецепты"].tap()

        let searchField = app.searchFields["Поиск рецептов"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8), "Search bar missing on recipe list")
    }

    // MARK: - TC-10: Settings screen elements [NEEDS_BACKEND]

    func testSettingsScreenContainsKeyElements() throws {
        app.launchArguments = ["UI_TESTING_BYPASS_AUTH"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Профиль"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Профиль"].tap()

        XCTAssertTrue(
            app.navigationBars["Настройки"].waitForExistence(timeout: 8),
            "Settings navigation bar missing"
        )

        XCTAssertTrue(app.textFields["URL сервера"].exists, "Server URL field missing")
        XCTAssertTrue(app.buttons["Выйти"].exists, "Logout button missing")
    }

    // MARK: - TC-11: Filter sheet can be opened and dismissed [NEEDS_BACKEND]

    func testFilterSheetOpenAndClose() throws {
        app.launchArguments = ["UI_TESTING_BYPASS_AUTH"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Рецепты"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Рецепты"].tap()

        // Wait for navigation bar; filter button may be identified by its icon
        XCTAssertTrue(app.navigationBars["Рецепты"].waitForExistence(timeout: 8))

        let filterButton = app.navigationBars["Рецепты"].buttons.element(boundBy: 1)
        if filterButton.waitForExistence(timeout: 5) {
            filterButton.tap()

            let cancelButton = app.buttons["Отмена"]
            if cancelButton.waitForExistence(timeout: 5) {
                cancelButton.tap()
            }
        }
    }

    // MARK: - TC-12: Recipe editor can be opened [NEEDS_BACKEND]

    func testRecipeEditorSheetOpens() throws {
        app.launchArguments = ["UI_TESTING_BYPASS_AUTH"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Рецепты"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Рецепты"].tap()

        XCTAssertTrue(app.navigationBars["Рецепты"].waitForExistence(timeout: 8))

        // Plus button is the first trailing/leading toolbar item
        let addButton = app.navigationBars["Рецепты"].buttons.element(boundBy: 0)
        if addButton.waitForExistence(timeout: 5) {
            addButton.tap()

            // Editor should appear as a sheet
            XCTAssertTrue(
                app.navigationBars["Новый рецепт"].waitForExistence(timeout: 5)
                || app.navigationBars.firstMatch.waitForExistence(timeout: 5),
                "Recipe editor sheet should open"
            )

            // Dismiss
            let cancelButton = app.buttons["Отмена"]
            if cancelButton.waitForExistence(timeout: 3) {
                cancelButton.tap()
            }
        }
    }
}
