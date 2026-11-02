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
        AppIntentConfiguration(kind: "NextGameWidget", intent: SelectTeamIntent.self, provider: NextGameProvider()) { entry in
            NextGameWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Game")
        .description("Shows your team's next game.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
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
}

struct NextGameProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NextGameEntry { .preview }

    func snapshot(for configuration: SelectTeamIntent, in context: Context) async -> NextGameEntry {
        context.isPreview ? .preview : await entry(for: configuration)
    }

    func timeline(for configuration: SelectTeamIntent, in context: Context) async -> Timeline<NextGameEntry> {
        let entry = await entry(for: configuration)
        return Timeline(entries: [entry], policy: .after(nextRefresh(after: entry)))
    }

    private func entry(for configuration: SelectTeamIntent) async -> NextGameEntry {
        let team = configuration.team?.team ?? FavoritesStore.load().first ?? .minnesotaWild
        do {
            let game = try await ESPNClient.shared.nextGame(for: team)
            async let teamLogo = loadLogo(team.logoURL)
            async let opponentLogo = loadLogo(game?.opponent.logoURL)
            return NextGameEntry(date: .now, team: team, game: game, teamLogo: await teamLogo, opponentLogo: await opponentLogo)
        } catch {
            return NextGameEntry(date: .now, team: team, game: nil, failed: true)
        }
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
                    .frame(width: 40, height: 40)
                Spacer()
                if entry.game?.state == .live { LiveBadge() }
            }
            Spacer(minLength: 0)
            if let game = entry.game {
                Text(game.dayLabel.uppercased())
                    .font(.caption2.weight(.semibold))
                    .opacity(0.8)
                Text(game.timeLabel)
                    .font(.title2.bold())
                    .minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Text(game.matchupPrefix).opacity(0.8)
                    Logo(image: entry.opponentLogo, league: game.league).frame(width: 16, height: 16)
                    Text(game.opponent.shortName).lineLimit(1).minimumScaleFactor(0.7)
                }
                .font(.subheadline.weight(.semibold))
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
                    Logo(image: entry.teamLogo, league: entry.team.league).frame(width: 52, height: 52)
                    if let game = entry.game {
                        Text(game.matchupPrefix).font(.headline).opacity(0.8)
                        Logo(image: entry.opponentLogo, league: game.league).frame(width: 52, height: 52)
                    }
                }
                if entry.game?.state == .live { LiveBadge() }
            }

            VStack(alignment: .leading, spacing: 3) {
                if let game = entry.game {
                    Text("\(entry.team.shortName) \(game.shortMatchup)")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(game.dayLabel) · \(game.timeLabel)")
                        .font(.title3.bold())
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

#Preview(as: .systemMedium) {
    NextGameWidget()
} timeline: {
    NextGameEntry.preview
}
