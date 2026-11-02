import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var favorites: FavoritesModel
    @State private var path: [Team] = []
    @State private var showingPicker = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(favorites.teams) { team in
                    NavigationLink(value: team) {
                        FavoriteRow(team: team)
                    }
                }
                .onDelete(perform: favorites.remove)
                .onMove(perform: favorites.move)
            }
            .overlay {
                if favorites.teams.isEmpty {
                    ContentUnavailableView {
                        Label("No Teams Yet", systemImage: "star")
                    } description: {
                        Text("Add your favorite teams to see their next games.")
                    } actions: {
                        Button("Add Teams") { showingPicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("GameDay")
            .navigationDestination(for: Team.self) { TeamScheduleView(team: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Team", systemImage: "plus") { showingPicker = true }
                }
            }
            .sheet(isPresented: $showingPicker) { TeamPickerView() }
        }
        .onOpenURL(perform: open)
    }

    /// Handles `gameday://team/<league>:<espnID>` links from the widget.
    private func open(_ url: URL) {
        guard url.scheme == "gameday", url.host() == "team" else { return }
        let id = url.lastPathComponent
        if let team = favorites.teams.first(where: { $0.id == id }) {
            path = [team]
            return
        }
        Task {
            if let team = try? await ESPNClient.shared.team(withID: id) {
                path = [team]
            }
        }
    }
}

private struct FavoriteRow: View {
    let team: Team
    @State private var nextGame: Game?
    @State private var loaded = false

    var body: some View {
        HStack(spacing: 12) {
            TeamLogo(url: team.logoURL, league: team.league)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name).font(.headline)
                Group {
                    if let nextGame {
                        Text("\(nextGame.shortMatchup) · \(nextGame.dayLabel), \(nextGame.timeLabel)")
                    } else if loaded {
                        Text("No upcoming games")
                    } else {
                        Text("Loading…")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task(id: team.id) {
            nextGame = try? await ESPNClient.shared.nextGame(for: team)
            loaded = true
        }
    }
}

struct TeamLogo: View {
    let url: URL?
    let league: League

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: league.symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }
}
