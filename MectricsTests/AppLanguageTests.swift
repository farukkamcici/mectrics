import XCTest
@testable import Mectrics

final class AppLanguageTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppLanguageTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testEverySupportedLanguageWritesAnAppleLanguageOverride() {
        for language in AppLanguage.allCases where language != .system {
            AppLanguage.apply(language, to: defaults)

            XCTAssertEqual(AppLanguage.selected(in: defaults), language)
            XCTAssertEqual(
                defaults.stringArray(forKey: "AppleLanguages"),
                [language.rawValue]
            )
        }
    }

    func testExpectedLanguagesAreAvailableAlongsideSystemDefault() {
        XCTAssertEqual(
            AppLanguage.allCases.map(\.rawValue),
            ["system", "en", "tr", "ru", "es", "fr", "pt-BR"]
        )
    }

    func testAppBundleShipsEverySelectableLocalization() {
        let selectable = Set(
            AppLanguage.allCases
                .filter { $0 != .system }
                .map(\.rawValue)
        )
        XCTAssertTrue(
            selectable.isSubset(of: Set(Bundle.main.localizations)),
            "bundle localizations: \(Bundle.main.localizations)"
        )
    }

    func testSystemLanguageRemovesTheAppOverride() {
        AppLanguage.apply(.turkish, to: defaults)
        AppLanguage.apply(.system, to: defaults)

        XCTAssertEqual(AppLanguage.selected(in: defaults), .system)
        XCTAssertNil(
            defaults.persistentDomain(forName: suiteName)?["AppleLanguages"]
        )
    }

    func testRelaunchHelperWaitsAndSafelyQuotesTheBundlePath() {
        let script = AppRelauncher.helperScript(
            pid: 4242,
            bundle: URL(filePath: "/Applications/Mectrics User's Copy.app")
        )

        let wait = try! XCTUnwrap(script.range(of: "kill -0 4242"))
        let timeout = try! XCTUnwrap(script.range(of: "[ $i -lt 100 ] || exit 1"))
        let open = try! XCTUnwrap(script.range(of: "/usr/bin/open -n"))
        XCTAssertTrue(wait.lowerBound < open.lowerBound)
        XCTAssertTrue(timeout.lowerBound < open.lowerBound)
        XCTAssertTrue(script.contains("'/Applications/Mectrics User'\\''s Copy.app'"))
    }
}
