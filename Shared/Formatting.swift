import SwiftUI

extension Color {
    /// Parses ESPN-style hex strings like `124734` (no leading #).
    init?(hex: String?) {
        guard var hex = hex?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Font {
    /// Heavy, condensed type for matchups and times; reads like a scoreboard.
    static func scoreboard(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.condensed)
    }
}

extension Team {
    var primaryColor: Color { Color(hex: colorHex) ?? .accentColor }

    /// A team color dark enough for white text: the primary color, or the
    /// alternate when the primary is very light (e.g. white or yellow).
    var backgroundColor: Color {
        for hex in [colorHex, alternateColorHex] {
            if let hex, let luminance = Self.luminance(hex), luminance < 0.6, let color = Color(hex: hex) {
                return color
            }
        }
        return Color(white: 0.2)
    }

    var cardGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundColor, backgroundColor.mix(with: .black, by: 0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func luminance(_ hex: String) -> Double? {
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF), g = Double((value >> 8) & 0xFF), b = Double(value & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255
    }
}

/// Sport icon plus "NHL" or "Women's Volleyball", so it's clear which sport a team plays.
struct SportBadge: View {
    let league: League

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: league.symbol).imageScale(.small)
            Text(league.badgeLabel)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

private extension Color {
    func mix(with other: Color, by amount: Double) -> Color {
        if #available(iOS 18.0, *) {
            return mix(with: other, by: amount, in: .perceptual)
        }
        return opacity(1 - amount * 0.5)
    }
}

extension Game {
    /// "Today", "Tomorrow", or "Tue, Nov 3".
    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "7:00 PM", "TBD", or "LIVE".
    var timeLabel: String {
        switch state {
        case .live: "LIVE"
        case .final: "Final"
        case .pre: timeIsKnown ? date.formatted(date: .omitted, time: .shortened) : "TBD"
        }
    }

    /// "NOV", "6", "FRI" for calendar-style date tiles.
    var monthLabel: String { date.formatted(.dateTime.month(.abbreviated)).uppercased() }
    var dayNumber: String { date.formatted(.dateTime.day()) }
    var weekdayLabel: String { date.formatted(.dateTime.weekday(.abbreviated)).uppercased() }

    /// e.g. "@ Flyers" or "vs Bruins".
    var shortMatchup: String { "\(matchupPrefix) \(opponent.shortName)" }
}

extension Game {
    /// Tiny label for round Lock Screen widgets: "7 PM" today, "LIVE", or "TUE".
    var compactWhen: String {
        if state == .live { return "LIVE" }
        if Calendar.current.isDateInToday(date), timeIsKnown {
            return date.formatted(.dateTime.hour())
        }
        return weekdayLabel
    }
}
