import AppIntents
import WidgetKit

/// Lets each widget instance pick its teams (long-press › Edit Widget).
struct SelectTeamsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Teams"
    static var description = IntentDescription(
        "Pick up to 5 teams. Tap the arrows to flip between them; Lock Screen widgets show whichever team plays next."
    )

    @Parameter(title: "Teams", size: 5)
    var teams: [TeamEntity]?

    /// The configured teams, or the app's favorites (the Minnesota Wild by default).
    var resolvedTeams: [Team] {
        let picked = (teams ?? []).map(\.team)
        if !picked.isEmpty { return picked }
        let favorites = FavoritesStore.load()
        return favorites.isEmpty ? [.minnesotaWild] : favorites
    }
}

/// The arrow buttons on home-screen widgets. Runs in the widget extension,
/// which then reloads the timeline showing the new team.
struct FlipTeamIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Another Team"
    static var isDiscoverable = false

    @Parameter(title: "Widget Teams")
    var widgetKey: String

    @Parameter(title: "Step")
    var step: Int

    init() {}

    init(widgetKey: String, step: Int) {
        self.widgetKey = widgetKey
        self.step = step
    }

    func perform() async throws -> some IntentResult {
        WidgetPager.advance(widgetKey, by: step)
        return .result()
    }
}

/// Remembers which team each widget is showing, keyed by its list of teams.
enum WidgetPager {
    private static let defaults = UserDefaults.standard

    static func key(for teams: [Team]) -> String {
        teams.map(\.id).joined(separator: ",")
    }

    static func index(for key: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let stored = defaults.integer(forKey: "page." + key)
        return ((stored % count) + count) % count
    }

    static func advance(_ key: String, by step: Int) {
        defaults.set(defaults.integer(forKey: "page." + key) + step, forKey: "page." + key)
    }
}

struct TeamEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Team"
    static var defaultQuery = TeamQuery()

    let team: Team

    var id: String { team.id }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(team.fullName)",
            subtitle: "\(team.league.displayName)",
            image: DisplayRepresentation.Image(systemName: team.league.symbol)
        )
    }
}

struct TeamQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [TeamEntity] {
        let known = FavoritesStore.load() + [.minnesotaWild]
        var results: [TeamEntity] = []
        for id in identifiers {
            if let team = known.first(where: { $0.id == id }) {
                results.append(TeamEntity(team: team))
            } else if let team = try? await ESPNClient.shared.team(withID: id) {
                results.append(TeamEntity(team: team))
            }
        }
        return results
    }

    /// Favorites from the app show first in the picker; typing searches every league.
    func suggestedEntities() async throws -> [TeamEntity] {
        FavoritesStore.load().map(TeamEntity.init)
    }

    func entities(matching string: String) async throws -> [TeamEntity] {
        await ESPNClient.shared.searchTeams(string).map(TeamEntity.init)
    }

    func defaultResult() async -> TeamEntity? {
        TeamEntity(team: FavoritesStore.load().first ?? .minnesotaWild)
    }
}
