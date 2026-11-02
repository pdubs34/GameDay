import SwiftUI

struct TeamPickerView: View {
    @EnvironmentObject private var favorites: FavoritesModel
    @Environment(\.dismiss) private var dismiss
    @State private var league: League = .nhl
    @State private var teams: [Team] = []
    @State private var search = ""
    @State private var failed = false

    private var filtered: [Team] {
        guard !search.isEmpty else { return teams }
        return teams.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.abbreviation.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("League", selection: $league) {
                    ForEach(League.allCases) { league in
                        Label(league.displayName, systemImage: league.symbol).tag(league)
                    }
                }

                Section {
                    ForEach(filtered) { team in
                        Button {
                            favorites.toggle(team)
                        } label: {
                            HStack(spacing: 12) {
                                TeamLogo(url: team.logoURL, league: team.league)
                                    .frame(width: 32, height: 32)
                                Text(team.name).foregroundStyle(.primary)
                                Spacer()
                                if favorites.contains(team) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if teams.isEmpty && !failed {
                    ProgressView()
                } else if failed {
                    ContentUnavailableView("Couldn't Load Teams", systemImage: "wifi.slash")
                }
            }
            .searchable(text: $search, prompt: "Search \(league.displayName)")
            .navigationTitle("Add Teams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: league) {
                teams = []
                failed = false
                do {
                    teams = try await ESPNClient.shared.teams(in: league)
                } catch {
                    failed = true
                }
            }
        }
    }
}
