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
                        .listRowInsets(EdgeInsets())
                }
            }

            if games.count > 1 {
                Section("Upcoming") {
                    ForEach(games.dropFirst()) { game in
                        GameRow(game: game)
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
                }
            }
        }
        .overlay {
            if loading && games.isEmpty {
                ProgressView()
            } else if failed {
                ContentUnavailableView("Couldn't Load Schedule", systemImage: "wifi.slash")
            } else if games.isEmpty {
                ContentUnavailableView("No Upcoming Games", systemImage: team.league.symbol)
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
            var parts = ["Added \(result.added) game\(result.added == 1 ? "" : "s") to the “\(team.name)” calendar."]
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
        VStack(spacing: 16) {
            HStack {
                Text(game.state == .live ? "LIVE NOW" : "NEXT GAME")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                Spacer()
                if game.state == .pre {
                    Text(game.date, style: .relative)
                        .font(.caption.monospacedDigit())
                }
            }
            .opacity(0.85)

            HStack(spacing: 20) {
                TeamLogo(url: team.logoURL, league: team.league).frame(width: 72, height: 72)
                Text(game.matchupPrefix).font(.title3.weight(.semibold)).opacity(0.8)
                TeamLogo(url: game.opponent.logoURL, league: team.league).frame(width: 72, height: 72)
            }

            VStack(spacing: 4) {
                Text(game.opponent.name).font(.title3.bold())
                Text("\(game.dayLabel) · \(game.timeLabel)").font(.headline)
                if let venue = game.venue {
                    Text(venue).font(.subheadline).opacity(0.85)
                }
                if !game.broadcasts.isEmpty {
                    Label(game.broadcasts.joined(separator: " · "), systemImage: "tv")
                        .font(.footnote)
                        .opacity(0.85)
                }
            }
            .multilineTextAlignment(.center)

            Button(action: onAddToCalendar) {
                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.25))
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(team.cardGradient)
    }
}

private struct GameRow: View {
    let game: Game

    var body: some View {
        HStack(spacing: 12) {
            TeamLogo(url: game.opponent.logoURL, league: game.league)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.shortMatchup).font(.headline)
                if let venue = game.venue {
                    Text(venue).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(game.dayLabel).font(.subheadline)
                Text(game.timeLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
