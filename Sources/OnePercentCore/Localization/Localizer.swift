import Foundation

/// Languages the app ships a pack for. Adding one means adding `<code>.lproj/Localizable.strings`.
public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case italian = "it"

    public var locale: Locale { Locale(identifier: rawValue) }

    /// Always written in its own language, so it can be found whatever the current one is.
    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .italian: return "Italiano"
        }
    }
}

/// What the user picks in Settings: follow macOS, or a specific language.
public enum LanguageChoice: String, CaseIterable, Sendable {
    case system
    case english
    case italian

    public func resolve(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        switch self {
        case .english: return .english
        case .italian: return .italian
        case .system:
            for identifier in preferred {
                let code = String(identifier.lowercased().prefix(2))
                if let match = AppLanguage(rawValue: code) { return match }
            }
            return .english
        }
    }
}

/// In-app translation. The English text of a string *is* its key, so a missing translation shows
/// readable English instead of an id. Languages are plain `.strings` files, switchable at runtime
/// without relaunching: the macOS system language is not the only thing that decides.
public final class Localizer: @unchecked Sendable {
    /// What the app uses. Starts in English; `AppDependencies` applies the saved choice at launch.
    public static let shared = Localizer()

    private let lock = NSLock()
    private let roots: [URL]
    private var current: AppLanguage = .english
    private var tables: [AppLanguage: [String: String]] = [:]

    /// `roots` are the folders that contain `<code>.lproj`. The app bundle's Resources by default;
    /// a `Resources` folder next to the working directory also counts, for `swift run`.
    public init(roots: [URL] = Localizer.defaultRoots()) {
        self.roots = roots
    }

    public static func defaultRoots() -> [URL] {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources"))
        return roots
    }

    public var language: AppLanguage {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    public func setLanguage(_ language: AppLanguage) {
        lock.lock(); defer { lock.unlock() }
        current = language
    }

    public func string(_ key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let text = table(for: current)[key] { return text }
        if current != .english, let text = table(for: .english)[key] { return text }
        return key
    }

    public func format(_ key: String, _ args: CVarArg...) -> String {
        formatted(string(key), args)
    }

    /// Picks the singular or plural key for `count`, then fills `%d` with it.
    public func plural(_ one: String, _ other: String, _ count: Int) -> String {
        formatted(string(count == 1 ? one : other), [count])
    }

    private func formatted(_ template: String, _ args: [CVarArg]) -> String {
        lock.lock(); let locale = current.locale; lock.unlock()
        return String(format: template, locale: locale, arguments: args)
    }

    /// Must be called with the lock held.
    private func table(for language: AppLanguage) -> [String: String] {
        if let loaded = tables[language] { return loaded }
        var merged: [String: String] = [:]
        // Earlier roots win, so the app bundle beats a stray development folder.
        for root in roots.reversed() {
            let url = root.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings")
            if let dictionary = NSDictionary(contentsOf: url) as? [String: String] {
                merged.merge(dictionary) { _, new in new }
            }
        }
        tables[language] = merged
        return merged
    }
}

// MARK: - Shorthand used throughout the UI

/// Translates a string into the language chosen in Settings.
public func L(_ key: String) -> String {
    Localizer.shared.string(key)
}

/// `L` with `String(format:)` arguments. Use positional specifiers (`%1$@ %2$d`) when a translation
/// needs another word order.
public func L(_ key: String, _ args: CVarArg...) -> String {
    let template = Localizer.shared.string(key)
    return String(format: template, locale: Localizer.shared.language.locale, arguments: args)
}

/// Singular / plural pair, e.g. `Lp("%d goal left", "%d goals left", n)`.
public func Lp(_ one: String, _ other: String, _ count: Int) -> String {
    Localizer.shared.plural(one, other, count)
}
