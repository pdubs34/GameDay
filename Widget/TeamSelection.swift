import AppIntents
import WidgetKit

/// Lets each widget instance pick its team (long-press › Edit Widget).
struct SelectTeamIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Team"
    static var description = IntentDescription("Pick which team's next game to show.")

    @Parameter(title: "Team")
    var team: TeamEntity?
}

struct TeamEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Team"
    static var defaultQuery = TeamQuery()

    let team: Team

    var id: String { team.id }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(team.name)", subtitle: "\(team.league.displayName)")
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
