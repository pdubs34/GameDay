import Foundation

/// Favorite teams, persisted in the App Group so the widget can read them.
enum FavoritesStore {
    static let appGroup = "group.com.pdubs34.gameday"
    private static let key = "favoriteTeams"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Starts with the Minnesota Wild until the user changes their picks.
    static func load() -> [Team] {
        guard let data = defaults.data(forKey: key) else { return [.minnesotaWild] }
        return (try? JSONDecoder().decode([Team].self, from: data)) ?? [.minnesotaWild]
    }

    static func save(_ teams: [Team]) {
        defaults.set(try? JSONEncoder().encode(teams), forKey: key)
    }
}
