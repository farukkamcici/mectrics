/// Stable preference locations shared by the app and its bundled read-only CLI.
public enum AlertConfigurationStorage {
    public static let preferencesDomain = "com.mectrics.app"
    public static let thresholdRulesKey = "alertRules"
    public static let systemRulesKey = "systemAlertRules"
}
