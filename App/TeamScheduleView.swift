import SwiftUI

struct TeamScheduleView: View {
    let team: Team

    @EnvironmentObject private var favorites: FavoritesModel
    @State private var games: [Game] = []
    @State private var loading = true
    @State private var failed = false
    @State private var draft: DraftEvent?
    @State private var addingAll = false
    @State private var message: String?

    var body: some View {
        List {
            if let next = games.first {
                Section {
                    NextGameCard(team: team, game: next) { addToCalendar(next) }
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

            if games.count > 1 {
                Section {
                    ForEach(games.dropFirst()) { game in
                        GameRow(game: game, tint: team.backgroundColor) { addToCalendar(game) }
                            .swipeActions {
                                Button("Add to Calendar", systemImage: "calendar.badge.plus") {
                                    addToCalendar(game)
                                }
                                .tint(team.primaryColor)
                            }
                            .contextMenu {
                                Button("Add to Calendar", systemImage: "calendar.badge.plus") {
                                    addToCalendar(game)
                                }
                                if let url = game.webURL {
                                    Link(destination: url) { Label("Open on ESPN", systemImage: "safari") }
                                }
                            }
                    }
                } header: {
                    Text("Upcoming")
                        .font(.scoreboard(22))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
        }
        .overlay {
            if loading && games.isEmpty {
                ProgressView()
            } else if failed {
                ContentUnavailableView("Couldn't Load Schedule", systemImage: "wifi.slash")
            } else if games.isEmpty {
                ContentUnavailableView(
                    "No Upcoming Games",
                    systemImage: team.league.symbol,
                    description: Text("\(team.fullName) has no games scheduled right now.")
                )
            }
        }
        .navigationTitle(team.shortName)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    favorites.toggle(team)
                } label: {
                    Image(systemName: favorites.contains(team) ? "star.fill" : "star")
                }
                Button {
                    Task { await addAllToCalendar() }
                } label: {
                    if addingAll {
                        ProgressView()
                    } else {
                        Label("Add All to Calendar", systemImage: "calendar.badge.plus")
                    }
                }
                .disabled(games.isEmpty || addingAll)
            }
        }
        .sheet(item: $draft) { EventEditView(event: $0.event).ignoresSafeArea() }
        .alert("Calendar", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            games = try await ESPNClient.shared.upcomingGames(for: team)
            failed = false
        } catch {
            failed = games.isEmpty
        }
    }

    private func addToCalendar(_ game: Game) {
        draft = DraftEvent(event: CalendarService.shared.draftEvent(for: game, team: team))
    }

    private func addAllToCalendar() async {
        addingAll = true
        defer { addingAll = false }
        do {
            let result = try await CalendarService.shared.addAll(games, for: team)
            var parts = ["Added \(result.added) game\(result.added == 1 ? "" : "s") to the “\(team.fullName)” calendar."]
            if result.updated > 0 { parts.append("Updated \(result.updated) with new times.") }
            message = parts.joined(separator: " ")
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct NextGameCard: View {
    let team: Team
    let game: Game
    let onAddToCalendar: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                SportBadge(league: team.league)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .opacity(0.85)
                Spacer()
                if game.state == .live {
                    LivePill()
                } else {
                    Text(game.date, style: .relative)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.18), in: Capsule())
                }
            }

            HStack(spacing: 18) {
                logo(team.logoURL)
                Text(game.matchupPrefix.uppercased())
                    .font(.scoreboard(22))
                    .opacity(0.7)
                logo(game.opponent.logoURL)
            }

            VStack(spacing: 2) {
                Text(game.dayLabel.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .opacity(0.75)
                Text(game.timeLabel)
                    .font(.scoreboard(48))
                Text(game.opponent.name)
                    .font(.headline)
                    .opacity(0.9)
            }
            .multilineTextAlignment(.center)

            if game.venue != nil || !game.broadcasts.isEmpty {
                // Side by side when they fit, stacked otherwise.
                ViewThatFits {
                    HStack(spacing: 8) { infoChips }
                    VStack(spacing: 8) { infoChips }
                }
            }

            Button(action: onAddToCalendar) {
                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(team.backgroundColor)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(PressableCardStyle())
        }
        .foregroundStyle(.white)
        .padding(20)
        .background {
            ZStack {
                team.cardGradient
                TeamLogo(url: team.logoURL, league: team.league)
                    .frame(width: 320, height: 320)
                    .offset(x: -120, y: 40)
                    .opacity(0.1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder private var infoChips: some View {
        if let venue = game.venue {
            InfoChip(text: venue, systemImage: "mappin.and.ellipse")
        }
        if !game.broadcasts.isEmpty {
            InfoChip(text: game.broadcasts.prefix(2).joined(separator: " · "), systemImage: "tv")
        }
    }

    private func logo(_ url: URL?) -> some View {
        TeamLogo(url: url, league: team.league)
            .padding(12)
            .frame(width: 88, height: 88)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

private struct InfoChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(text)
        }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.16), in: Capsule())
    }
}

private struct GameRow: View {
    let game: Game
    let tint: Color
    let onAddToCalendar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Calendar-style date tile.
            VStack(spacing: 0) {
                Text(game.weekdayLabel).font(.system(size: 9, weight: .bold)).tracking(0.5)
                Text(game.dayNumber).font(.scoreboard(22))
                Text(game.monthLabel).font(.system(size: 9, weight: .bold)).tracking(0.5)
            }
            .foregroundStyle(.white)
            .frame(width: 46, height: 54)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            TeamLogo(url: game.opponent.logoURL, league: game.league)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(game.shortMatchup).font(.scoreboard(19)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(game.isHome ? "HOME" : "AWAY")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.5)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .foregroundStyle(game.isHome ? .white : tint)
                        .background(game.isHome ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)), in: Capsule())
                    Text(game.timeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            // Borderless so only the icon is tappable, not the whole row.
            Button(action: onAddToCalendar) {
                Image(systemName: "calendar.badge.plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add \(game.shortMatchup) to Calendar")
        }
        .padding(.vertical, 2)
    }
}
