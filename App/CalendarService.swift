import EventKit
import EventKitUI
import SwiftUI

@MainActor
final class CalendarService {
    static let shared = CalendarService()

    enum CalendarError: LocalizedError {
        case accessDenied, noSource

        var errorDescription: String? {
            switch self {
            case .accessDenied: "Calendar access is off. Turn it on in Settings › GameDay."
            case .noSource: "Couldn't find an account to create the calendar in."
            }
        }
    }

    let store = EKEventStore()

    /// An unsaved event for the system "Add Event" sheet, which needs no permission.
    func draftEvent(for game: Game, team: Team) -> EKEvent {
        let event = EKEvent(eventStore: store)
        fill(event, with: game, team: team)
        return event
    }

    /// Adds every game to a calendar named after the team. Games already added
    /// (matched by their ESPN link) are updated in place, so re-running this
    /// picks up time changes instead of creating duplicates.
    func addAll(_ games: [Game], for team: Team) async throws -> (added: Int, updated: Int) {
        guard try await store.requestFullAccessToEvents() else { throw CalendarError.accessDenied }
        guard let first = games.first?.date, let last = games.last?.date else { return (0, 0) }

        let calendar = try calendar(for: team)
        let window = store.predicateForEvents(
            withStart: first.addingTimeInterval(-30 * 86400),
            end: last.addingTimeInterval(30 * 86400),
            calendars: [calendar]
        )
        let existing = Dictionary(
            store.events(matching: window).compactMap { event in event.url.map { ($0, event) } },
            uniquingKeysWith: { first, _ in first }
        )

        var added = 0, updated = 0
        for game in games {
            let event: EKEvent
            if let url = game.webURL, let match = existing[url] {
                event = match
                if event.startDate != game.date { updated += 1 }
            } else {
                event = EKEvent(eventStore: store)
                event.calendar = calendar
                added += 1
            }
            fill(event, with: game, team: team)
            try store.save(event, span: .thisEvent, commit: false)
        }
        try store.commit()
        return (added, updated)
    }

    private func fill(_ event: EKEvent, with game: Game, team: Team) {
        event.title = "\(team.league.emoji) \(team.shortName) \(game.matchupPrefix) \(game.opponent.shortName)"
        if game.timeIsKnown {
            event.isAllDay = false
            event.startDate = game.date
            event.endDate = game.estimatedEnd
        } else {
            event.isAllDay = true
            event.startDate = game.date
            event.endDate = game.date
        }
        let location = [game.venue, game.city].compactMap { $0 }.joined(separator: ", ")
        event.location = location.isEmpty ? nil : location
        event.notes = game.broadcasts.isEmpty ? nil : "Watch: \(game.broadcasts.joined(separator: ", "))"
        event.url = game.webURL
    }

    private func calendar(for team: Team) throws -> EKCalendar {
        let key = "calendar.\(team.id)"
        if let id = UserDefaults.standard.string(forKey: key),
           let calendar = store.calendar(withIdentifier: id) {
            return calendar
        }
        if let calendar = store.calendars(for: .event)
            .first(where: { $0.title == team.name && $0.allowsContentModifications }) {
            UserDefaults.standard.set(calendar.calendarIdentifier, forKey: key)
            return calendar
        }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = team.name
        calendar.cgColor = UIColor(team.primaryColor).cgColor
        guard let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
        else { throw CalendarError.noSource }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: key)
        return calendar
    }
}

/// Identifiable wrapper so an `EKEvent` can drive `.sheet(item:)`.
struct DraftEvent: Identifiable {
    let id = UUID()
    let event: EKEvent
}

/// The system "New Event" sheet, prefilled with a game.
struct EventEditView: UIViewControllerRepresentable {
    let event: EKEvent
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = CalendarService.shared.store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
