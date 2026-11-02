import SwiftUI
import WidgetKit

@main
struct GameDayApp: App {
    @StateObject private var favorites = FavoritesModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(favorites)
        }
    }
}

@MainActor
final class FavoritesModel: ObservableObject {
    @Published private(set) var teams: [Team] = FavoritesStore.load()

    func contains(_ team: Team) -> Bool {
        teams.contains { $0.id == team.id }
    }

    func toggle(_ team: Team) {
        if contains(team) {
            teams.removeAll { $0.id == team.id }
        } else {
            teams.append(team)
        }
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        teams.remove(atOffsets: offsets)
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        teams.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        FavoritesStore.save(teams)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
