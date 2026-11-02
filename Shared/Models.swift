import Foundation

enum League: String, CaseIterable, Codable, Identifiable, Hashable {
    case nhl, nfl, nba, mlb, wnba, mls
    case collegeFootball, mensCollegeBasketball, womensCollegeVolleyball, mensCollegeVolleyball

    var id: String { rawValue }

    /// Path segment used by ESPN's site API, e.g. `hockey/nhl`.
    var apiPath: String {
        switch self {
        case .nhl: "hockey/nhl"
        case .nfl: "football/nfl"
        case .nba: "basketball/nba"
        case .mlb: "baseball/mlb"
        case .wnba: "basketball/wnba"
        case .mls: "soccer/usa.1"
        case .collegeFootball: "football/college-football"
        case .mensCollegeBasketball: "basketball/mens-college-basketball"
        case .womensCollegeVolleyball: "volleyball/womens-college-volleyball"
        case .mensCollegeVolleyball: "volleyball/mens-college-volleyball"
        }
    }

    /// Path segment used on espn.com game pages.
    var webSlug: String {
        switch self {
        case .mls: "soccer"
        case .collegeFootball: "college-football"
        case .mensCollegeBasketball: "mens-college-basketball"
        case .womensCollegeVolleyball: "womens-college-volleyball"
        case .mensCollegeVolleyball: "mens-college-volleyball"
        default: rawValue
        }
    }

    var isCollege: Bool {
        switch self {
        case .collegeFootball, .mensCollegeBasketball, .womensCollegeVolleyball, .mensCollegeVolleyball: true
        default: false
        }
    }

    var displayName: String {
        switch self {
        case .nhl: "NHL"
        case .nfl: "NFL"
        case .nba: "NBA"
        case .mlb: "MLB"
        case .wnba: "WNBA"
        case .mls: "MLS"
        case .collegeFootball: "College Football"
        case .mensCollegeBasketball: "Men's College Basketball"
        case .womensCollegeVolleyball: "Women's College Volleyball"
        case .mensCollegeVolleyball: "Men's College Volleyball"
        }
    }

    /// The sport itself, e.g. "Hockey" or "Women's Volleyball". College schools
    /// field teams in many sports, so this is what tells them apart.
    var sportName: String {
        switch self {
        case .nhl: "Hockey"
        case .nfl, .collegeFootball: "Football"
        case .nba, .wnba: "Basketball"
        case .mensCollegeBasketball: "Men's Basketball"
        case .mlb: "Baseball"
        case .mls: "Soccer"
        case .womensCollegeVolleyball: "Women's Volleyball"
        case .mensCollegeVolleyball: "Men's Volleyball"
        }
    }

    /// Compact label for badges: the league for pros ("NHL"), the sport for college.
    var badgeLabel: String { isCollege ? sportName : displayName }

    var symbol: String {
        switch self {
        case .nhl: "hockey.puck"
        case .nfl, .collegeFootball: "football"
        case .nba, .wnba, .mensCollegeBasketball: "basketball"
        case .mlb: "baseball"
        case .mls: "soccerball"
        case .womensCollegeVolleyball, .mensCollegeVolleyball: "volleyball"
        }
    }

    var emoji: String {
        switch self {
        case .nhl: "🏒"
        case .nfl, .collegeFootball: "🏈"
        case .nba, .wnba, .mensCollegeBasketball: "🏀"
        case .mlb: "⚾️"
        case .mls: "⚽️"
        case .womensCollegeVolleyball, .mensCollegeVolleyball: "🏐"
        }
    }

    /// Typical game length, used for calendar event end times.
    var typicalDuration: TimeInterval {
        switch self {
        case .nfl, .collegeFootball, .mlb: 3.5 * 3600
        case .mls, .womensCollegeVolleyball, .mensCollegeVolleyball: 2 * 3600
        default: 2.75 * 3600
        }
    }
}

struct Team: Codable, Hashable, Identifiable {
    let league: League
    let espnID: String
    let name: String
    let shortName: String
    let abbreviation: String
    let colorHex: String?
    let alternateColorHex: String?
    let logoURL: URL?

    /// Stable id across leagues, e.g. `nhl:30`.
    var id: String { "\(league.rawValue):\(espnID)" }

    /// Adds the sport for college teams, since "Minnesota Golden Gophers"
    /// alone could mean football, basketball, or volleyball.
    var fullName: String { league.isCollege ? "\(name) \(league.sportName)" : name }

    static let minnesotaWild = Team(
        league: .nhl,
        espnID: "30",
        name: "Minnesota Wild",
        shortName: "Wild",
        abbreviation: "MIN",
        colorHex: "124734",
        alternateColorHex: "ae122a",
        logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nhl/500/min.png")
    )
}

struct Opponent: Codable, Hashable {
    let name: String
    let shortName: String
    let abbreviation: String
    let logoURL: URL?
}

struct Game: Codable, Hashable, Identifiable {
    enum State: String, Codable { case pre, live, final }

    let id: String
    let league: League
    let date: Date
    /// False when ESPN lists the game with a TBD start time.
    let timeIsKnown: Bool
    let isHome: Bool
    let opponent: Opponent
    let venue: String?
    let city: String?
    let broadcasts: [String]
    let state: State
    let statusDetail: String

    /// "vs" for home games, "@" for away games.
    var matchupPrefix: String { isHome ? "vs" : "@" }

    var webURL: URL? {
        URL(string: "https://www.espn.com/\(league.webSlug)/game/_/gameId/\(id)")
    }

    var estimatedEnd: Date { date.addingTimeInterval(league.typicalDuration) }
}
