import Foundation

enum IntroBehavior: String, CaseIterable, Identifiable {
    case adaptive, countdown, manual

    var id: Self { self }
    var title: String {
        switch self {
        case .adaptive: return "Adaptatif"
        case .countdown: return "Après 5 secondes"
        case .manual: return "Manuel"
        }
    }
}

struct IntroPreference: Codable, Equatable {
    enum Mode: String, Codable { case countdown, immediate, manual }
    var mode = Mode.countdown
    private var lastEpisode: Int?
    private var lastKept: Bool?

    mutating func record(_ number: Int?, kept: Bool) {
        guard let number else { return }
        if lastEpisode == number { return }
        if lastEpisode == number - 1, lastKept == kept { mode = kept ? .manual : .immediate }
        lastEpisode = number
        lastKept = kept
    }
}

struct IntroSession {
    enum Action: Equatable { case countdown(Int), skip, none }
    var enteredAt: Double?
    var lastActivity = 0.0
    var resolved = false
    var previousPosition: Double?
    var wasVisible: Bool { enteredAt != nil }

    mutating func assess(mode: IntroPreference.Mode, uptime: Double, position: Double, playing: Bool, inside: Bool) -> Action {
        guard !resolved else { return .none }
        guard inside, playing else { return .none }
        if enteredAt == nil { enteredAt = uptime }
        if let previousPosition, abs(position - previousPosition) > 1.3 { lastActivity = uptime }
        previousPosition = position
        if mode == .manual { return .none }
        if mode == .immediate { return .skip }
        let remaining = 5 - (uptime - max(enteredAt ?? uptime, lastActivity))
        return remaining <= 0 ? .skip : .countdown(Int(ceil(remaining)))
    }
}
