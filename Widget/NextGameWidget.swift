import SwiftUI
import WidgetKit

@main
struct GameDayWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextGameWidget()
    }
}

struct NextGameWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextGameWidget", intent: SelectTeamsIntent.self, provider: NextGameProvider()) { entry in
            NextGameWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Game")
        .description("Shows your teams' next games. Tap the arrows to flip between teams.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Timeline

struct NextGameEntry: TimelineEntry {
    let date: Date
    let team: Team
    let game: Game?
    var teamLogo: UIImage?
    var opponentLogo: UIImage?
    var failed = false
    /// Set on home-screen widgets showing more than one team.
    var page: Page?

    struct Page {
        let index: Int
        let count: Int
        let widgetKey: String
    }
}

struct NextGameProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NextGameEntry { .preview }

    func snapshot(for configuration: SelectTeamsIntent, in context: Context) async -> NextGameEntry {
        context.isPreview ? .preview : await entry(for: configuration, family: context.family)
    }

    func timeline(for configuration: SelectTeamsIntent, in context: Context) async -> Timeline<NextGameEntry> {
        let entry = await entry(for: configuration, family: context.family)
        return Timeline(entries: [entry], policy: .after(nextRefresh(after: entry)))
    }

    private func entry(for configuration: SelectTeamsIntent, family: WidgetFamily) async -> NextGameEntry {
        let teams = configuration.resolvedTeams
        switch family {
        case .accessoryRectangular, .accessoryCircular, .accessoryInline:
            return await soonestEntry(among: teams)
        default:
            let key = WidgetPager.key(for: teams)
            let index = WidgetPager.index(for: key, count: teams.count)
            var entry = await entry(for: teams[index])
            if teams.count > 1 {
                entry.page = .init(index: index, count: teams.count, widgetKey: key)
            }
            return entry
        }
    }

    private func entry(for team: Team) async -> NextGameEntry {
        do {
            let game = try await ESPNClient.shared.nextGame(for: team)
            async let teamLogo = loadLogo(team.logoURL)
            async let opponentLogo = loadLogo(game?.opponent.logoURL)
            return NextGameEntry(date: .now, team: team, game: game, teamLogo: await teamLogo, opponentLogo: await opponentLogo)
        } catch {
            return NextGameEntry(date: .now, team: team, game: nil, failed: true)
        }
    }

    /// Lock Screen widgets are too small for arrows, so they show whichever
    /// configured team plays next (a live game counts as soonest).
    private func soonestEntry(among teams: [Team]) async -> NextGameEntry {
        let results = await withTaskGroup(of: (Int, Game?).self) { group in
            for (offset, team) in teams.enumerated() {
                group.addTask { (offset, try? await ESPNClient.shared.nextGame(for: team)) }
            }
            var results: [(Int, Game?)] = []
            for await result in group { results.append(result) }
            return results
        }
        let soonest = results
            .compactMap { offset, game in game.map { (offset, $0) } }
            .min { a, b in
                if (a.1.state == .live) != (b.1.state == .live) { return a.1.state == .live }
                return a.1.date < b.1.date
            }
        guard let (offset, game) = soonest else {
            return NextGameEntry(date: .now, team: teams[0], game: nil, failed: results.isEmpty)
        }
        return NextGameEntry(date: .now, team: teams[offset], game: game)
    }

    /// Refresh at puck drop (to show LIVE), every 15 min during a game so the
    /// next one appears soon after the final, and every 6 hours otherwise.
    private func nextRefresh(after entry: NextGameEntry) -> Date {
        let now = Date.now
        guard let game = entry.game, !entry.failed else {
            return now.addingTimeInterval(entry.failed ? 30 * 60 : 6 * 3600)
        }
        if game.state == .live || game.date <= now {
            return now.addingTimeInterval(15 * 60)
        }
        return min(game.date, now.addingTimeInterval(6 * 3600))
    }

    private func loadLogo(_ url: URL?) async -> UIImage? {
        guard let url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data)
        else { return nil }
        // Widgets have a tight memory budget; ESPN logos are 500px.
        return image.preparingThumbnail(of: CGSize(width: 120, height: 120)) ?? image
    }
}

// MARK: - Views

struct NextGameWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextGameEntry

    var body: some View {
        content
            .id(entry.team.id)
            .transition(.push(from: .trailing))
            .containerBackground(for: .widget) {
                if family == .systemSmall || family == .systemMedium {
                    entry.team.cardGradient
                }
            }
            .widgetURL(URL(string: "gameday://team/\(entry.team.id)"))
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemMedium: MediumView(entry: entry)
        case .accessoryRectangular: RectangularView(entry: entry)
        case .accessoryCircular: CircularView(entry: entry)
        case .accessoryInline: InlineView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

private struct Logo: View {
    let image: UIImage?
    let league: League

    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: league.symbol).resizable().scaledToFit().padding(4)
        }
    }
}

private struct CircleLogo: View {
    let image: UIImage?
    let league: League

    var body: some View {
        Logo(image: image, league: league)
            .padding(7)
            .frame(width: 54, height: 54)
            .background(.white, in: Circle())
    }
}

/// Arrow buttons and page dots for flipping between a widget's teams.
private struct Pager: View {
    let page: NextGameEntry.Page

    var body: some View {
        HStack(spacing: 6) {
            arrow("chevron.left", step: -1)
            HStack(spacing: 3) {
                ForEach(0..<page.count, id: \.self) { index in
                    Circle()
                        .frame(width: 5, height: 5)
                        .opacity(index == page.index ? 1 : 0.4)
                }
            }
            arrow("chevron.right", step: 1)
        }
    }

    private func arrow(_ symbol: String, step: Int) -> some View {
        Button(intent: FlipTeamIntent(widgetKey: page.widgetKey, step: step)) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .heavy))
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.2), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step > 0 ? "Next team" : "Previous team")
    }
}

private struct LiveBadge: View {
    var body: some View {
        Text("LIVE")
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red, in: Capsule())
    }
}

private struct SmallView: View {
    let entry: NextGameEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Logo(image: entry.teamLogo, league: entry.team.league)
                    .padding(5)
                    .frame(width: 42, height: 42)
                    .background(.white, in: Circle())
                Spacer()
                if let page = entry.page {
                    Pager(page: page)
                } else if entry.game?.state == .live {
                    LiveBadge()
                }
            }
            Spacer(minLength: 0)
            if let game = entry.game {
                HStack(spacing: 4) {
                    Image(systemName: entry.team.league.symbol)
                        .accessibilityLabel(entry.team.league.sportName)
                    Text(game.state == .live ? "LIVE NOW" : game.dayLabel.uppercased())
                }
                .font(.caption2.weight(.semibold))
                .opacity(0.8)
                Text(game.timeLabel)
                    .font(.scoreboard(30))
                    .minimumScaleFactor(0.6)
                HStack(spacing: 4) {
                    Text(game.matchupPrefix).opacity(0.8)
                    Logo(image: entry.opponentLogo, league: game.league).frame(width: 16, height: 16)
                    Text(game.opponent.shortName.uppercased()).lineLimit(1).minimumScaleFactor(0.6)
                }
                .font(.scoreboard(15))
            } else {
                Text(entry.team.shortName).font(.headline)
                Text(entry.failed ? "Couldn't load schedule" : "No upcoming games")
                    .font(.caption)
                    .opacity(0.8)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct MediumView: View {
    let entry: NextGameEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    CircleLogo(image: entry.teamLogo, league: entry.team.league)
                    if let game = entry.game {
                        Text(game.matchupPrefix.uppercased()).font(.scoreboard(15)).opacity(0.7)
                        CircleLogo(image: entry.opponentLogo, league: game.league)
                    }
                }
                if entry.game?.state == .live { LiveBadge() }
                if let page = entry.page { Pager(page: page) }
            }

            VStack(alignment: .leading, spacing: 3) {
                SportBadge(league: entry.team.league)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .opacity(0.8)
                if let game = entry.game {
                    Text(game.dayLabel.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .opacity(0.75)
                    Text(game.timeLabel)
                        .font(.scoreboard(28))
                        .minimumScaleFactor(0.6)
                    Text(game.shortMatchup.uppercased())
                        .font(.scoreboard(15))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let venue = game.venue {
                        Text(venue).font(.caption).opacity(0.85).lineLimit(1)
                    }
                    if let channel = game.broadcasts.first {
                        Label(game.broadcasts.prefix(2).joined(separator: " · "), systemImage: "tv")
                            .font(.caption)
                            .opacity(0.85)
                            .lineLimit(1)
                            .accessibilityLabel("On \(channel)")
                    }
                } else {
                    Text(entry.team.name).font(.headline)
                    Text(entry.failed ? "Couldn't load schedule" : "No upcoming games")
                        .font(.subheadline)
                        .opacity(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}

private struct RectangularView: View {
    let entry: NextGameEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let game = entry.game {
                Text("\(entry.team.league.emoji) \(entry.team.abbreviation) \(game.matchupPrefix) \(game.opponent.abbreviation)")
                    .font(.headline)
                Text("\(game.dayLabel) · \(game.timeLabel)")
                if let channel = game.broadcasts.first {
                    Text(channel).foregroundStyle(.secondary)
                }
            } else {
                Text(entry.team.shortName).font(.headline)
                Text("No upcoming games").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CircularView: View {
    let entry: NextGameEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: entry.team.league.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(entry.team.abbreviation)
                    .font(.system(size: 13, weight: .heavy).width(.condensed))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(entry.game?.compactWhen ?? "—")
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(4)
        }
        .accessibilityLabel(entry.game.map { "\(entry.team.name) \($0.shortMatchup), \($0.dayLabel) \($0.timeLabel)" } ?? entry.team.name)
    }
}

private struct InlineView: View {
    let entry: NextGameEntry

    var body: some View {
        if let game = entry.game {
            Text("\(entry.team.league.emoji) \(game.shortMatchup) \(game.dayLabel) \(game.timeLabel)")
        } else {
            Text("\(entry.team.shortName): no games")
        }
    }
}

// MARK: - Previews

extension NextGameEntry {
    static let preview = NextGameEntry(
        date: .now,
        team: .minnesotaWild,
        game: Game(
            id: "0",
            league: .nhl,
            date: Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: .now.addingTimeInterval(86400)) ?? .now,
            timeIsKnown: true,
            isHome: true,
            opponent: Opponent(name: "Boston Bruins", shortName: "Bruins", abbreviation: "BOS", logoURL: nil),
            venue: "Grand Casino Arena",
            city: "St. Paul, MN",
            broadcasts: ["FanDuel SN North"],
            state: .pre,
            statusDetail: ""
        )
    )
}

#Preview(as: .systemSmall) {
    NextGameWidget()
} timeline: {
    NextGameEntry.preview
}

#Preview(as: .accessoryCircular) {
    NextGameWidget()
} timeline: {
    NextGameEntry.preview
}

#Preview(as: .systemMedium) {
    NextGameWidget()
} timeline: {
    NextGameEntry.preview
}
