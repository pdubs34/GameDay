import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var favorites: FavoritesModel
    @State private var path: [Team] = []
    @State private var showingPicker = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(favorites.teams) { team in
                    Button {
                        path.append(team)
                    } label: {
                        FavoriteCard(team: team)
                    }
                    .buttonStyle(PressableCardStyle())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .contextMenu {
                        Button("Remove from Favorites", systemImage: "star.slash", role: .destructive) {
                            favorites.toggle(team)
                        }
                    }
                }
                .onDelete(perform: favorites.remove)
                .onMove(perform: favorites.move)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
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

private struct FavoriteCard: View {
    let team: Team
    @State private var nextGame: Game?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SportBadge(league: team.league)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .opacity(0.85)
                Spacer()
                if nextGame?.state == .live {
                    LivePill()
                }
            }

            HStack(spacing: 14) {
                TeamLogo(url: team.logoURL, league: team.league)
                    .padding(8)
                    .frame(width: 60, height: 60)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                Text(team.name)
                    .font(.scoreboard(28))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            nextGameStrip
        }
        .foregroundStyle(.white)
        .padding(18)
        .background {
            ZStack(alignment: .trailing) {
                team.cardGradient
                // Oversized, faded logo bleeding off the right edge.
                TeamLogo(url: team.logoURL, league: team.league)
                    .frame(width: 210, height: 210)
                    .offset(x: 70, y: -10)
                    .opacity(0.13)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: team.backgroundColor.opacity(0.35), radius: 14, y: 8)
        .task(id: team.id) {
            nextGame = try? await ESPNClient.shared.nextGame(for: team)
            loaded = true
        }
    }

    @ViewBuilder private var nextGameStrip: some View {
        HStack(alignment: .center, spacing: 10) {
            if let nextGame {
                TeamLogo(url: nextGame.opponent.logoURL, league: team.league)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("NEXT UP").font(.caption2.weight(.bold)).tracking(1).opacity(0.7)
                    Text(nextGame.shortMatchup.uppercased())
                        .font(.scoreboard(20))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(nextGame.dayLabel.uppercased()).font(.caption2.weight(.bold)).tracking(1).opacity(0.7)
                    Text(nextGame.timeLabel).font(.scoreboard(20))
                }
            } else {
                Text(loaded ? "No upcoming games" : "Loading…")
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.8)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct LivePill: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(.white).frame(width: 6, height: 6)
            Text("LIVE").font(.caption2.weight(.heavy)).tracking(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.red, in: Capsule())
        .foregroundStyle(.white)
    }
}

/// Cards shrink slightly while pressed.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
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
