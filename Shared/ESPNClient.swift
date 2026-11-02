import Foundation

/// Thin client over ESPN's public site API (no key required).
actor ESPNClient {
    static let shared = ESPNClient()

    private let base = URL(string: "https://site.api.espn.com/apis/site/v2/sports/")!
    private let session: URLSession
    private var teamCache: [League: [Team]] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Teams

    func teams(in league: League) async throws -> [Team] {
        if let cached = teamCache[league] { return cached }
        let url = base.appendingPathComponent("\(league.apiPath)/teams")
            .appending(queryItems: [URLQueryItem(name: "limit", value: "1000")])
        let response: TeamsResponse = try await fetch(url)
        let teams = (response.sports.first?.leagues.first?.teams ?? [])
            .map(\.team)
            .filter { $0.isActive ?? true }
            .map { $0.makeTeam(league: league) }
            .sorted { $0.name < $1.name }
        teamCache[league] = teams
        return teams
    }

    func team(withID id: String) async throws -> Team? {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let league = League(rawValue: parts[0]) else { return nil }
        return try await teams(in: league).first { $0.espnID == parts[1] }
    }

    func searchTeams(_ query: String) async -> [Team] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return await withTaskGroup(of: [Team].self) { group in
            for league in League.allCases {
                group.addTask { (try? await self.teams(in: league)) ?? [] }
            }
            var matches: [Team] = []
            for await teams in group {
                matches += teams.filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                        || $0.abbreviation.caseInsensitiveCompare(query) == .orderedSame
                }
            }
            return matches.sorted { $0.name < $1.name }
        }
    }

    // MARK: Schedule

    func schedule(for team: Team, seasonType: Int? = nil) async throws -> [Game] {
        var url = base.appendingPathComponent("\(team.league.apiPath)/teams/\(team.espnID)/schedule")
        if let seasonType {
            url.append(queryItems: [URLQueryItem(name: "seasontype", value: String(seasonType))])
        }
        let response: ScheduleResponse = try await fetch(url)
        return (response.events ?? [])
            .compactMap { $0.makeGame(for: team) }
            .sorted { $0.date < $1.date }
    }

    /// Games that haven't finished yet, soonest first. Falls back to the
    /// postseason schedule once the regular season has no games left.
    func upcomingGames(for team: Team) async throws -> [Game] {
        let upcoming = try await schedule(for: team).filter { $0.state != .final }
        if !upcoming.isEmpty { return upcoming }
        let postseason = (try? await schedule(for: team, seasonType: 3)) ?? []
        return postseason.filter { $0.state != .final }
    }

    func nextGame(for team: Team) async throws -> Game? {
        try await upcomingGames(for: team).first
    }

    // MARK: Networking

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Raw ESPN payloads

private struct TeamsResponse: Decodable {
    struct Sport: Decodable { let leagues: [LeagueTeams] }
    struct LeagueTeams: Decodable { let teams: [Wrapper] }
    struct Wrapper: Decodable { let team: RawTeam }
    let sports: [Sport]
}

private struct RawTeam: Decodable {
    struct Logo: Decodable { let href: String; let rel: [String]? }

    let id: String
    let displayName: String
    let shortDisplayName: String?
    let abbreviation: String?
    let color: String?
    let alternateColor: String?
    let isActive: Bool?
    let logos: [Logo]?
    let logo: String?

    var logoURL: URL? {
        let light = logos?.first { !($0.rel ?? []).contains("dark") }
        return (light?.href ?? logo).flatMap(URL.init(string:))
    }

    func makeTeam(league: League) -> Team {
        Team(
            league: league,
            espnID: id,
            name: displayName,
            shortName: shortDisplayName ?? displayName,
            abbreviation: abbreviation ?? String(displayName.prefix(3)).uppercased(),
            colorHex: color,
            alternateColorHex: alternateColor,
            logoURL: logoURL
        )
    }
}

private struct ScheduleResponse: Decodable {
    let events: [RawEvent]?
}

private struct RawEvent: Decodable {
    struct Competition: Decodable {
        let competitors: [Competitor]
        let venue: Venue?
        let broadcasts: [Broadcast]?
        let status: Status?
    }
    struct Competitor: Decodable {
        let id: String
        let homeAway: String?
        let team: RawTeam
    }
    struct Venue: Decodable {
        struct Address: Decodable { let city: String?; let state: String? }
        let fullName: String?
        let address: Address?
    }
    struct Broadcast: Decodable {
        struct Media: Decodable { let shortName: String? }
        let media: Media?
    }
    struct Status: Decodable {
        struct Kind: Decodable { let state: String; let detail: String?; let shortDetail: String? }
        let type: Kind
    }

    let id: String
    let date: String
    let timeValid: Bool?
    let competitions: [Competition]

    func makeGame(for team: Team) -> Game? {
        guard let competition = competitions.first,
              let date = ESPNDate.parse(date),
              let us = competition.competitors.first(where: { $0.id == team.espnID }),
              let them = competition.competitors.first(where: { $0.id != team.espnID })
        else { return nil }

        let state: Game.State = switch competition.status?.type.state {
        case "in": .live
        case "post": .final
        default: .pre
        }

        var seen = Set<String>()
        let broadcasts = (competition.broadcasts ?? [])
            .compactMap { $0.media?.shortName }
            .filter { seen.insert($0).inserted }

        let city = competition.venue?.address.map {
            [$0.city, $0.state].compactMap { $0 }.joined(separator: ", ")
        }

        return Game(
            id: id,
            league: team.league,
            date: date,
            timeIsKnown: timeValid ?? true,
            isHome: us.homeAway == "home",
            opponent: Opponent(
                name: them.team.displayName,
                shortName: them.team.shortDisplayName ?? them.team.displayName,
                abbreviation: them.team.abbreviation ?? "",
                logoURL: them.team.logoURL
            ),
            venue: competition.venue?.fullName,
            city: city?.isEmpty == true ? nil : city,
            broadcasts: broadcasts,
            state: state,
            statusDetail: competition.status?.type.shortDetail ?? ""
        )
    }
}

private enum ESPNDate {
    // ESPN usually omits seconds ("2026-11-04T00:00Z"), which ISO8601DateFormatter rejects.
    private static let minutes: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return formatter
    }()
    private static let iso = ISO8601DateFormatter()

    static func parse(_ string: String) -> Date? {
        minutes.date(from: string) ?? iso.date(from: string)
    }
}
