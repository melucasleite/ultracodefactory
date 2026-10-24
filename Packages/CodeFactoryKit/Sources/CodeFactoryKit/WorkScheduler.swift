import Foundation

/// Decides what can be worked on next. Pure functions over a board's cards,
/// so the rules are easy to test and reason about.
public enum WorkScheduler {
    /// The cards `card` is still waiting on: dependencies that exist on the
    /// board and aren't Done yet. Unknown names are ignored (deleted cards
    /// shouldn't block forever).
    public static func blockers(of card: Card, in cards: [Card]) -> [Card] {
        let bySlug = Dictionary(cards.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        return card.dependsOn.compactMap { bySlug[$0] }.filter { $0.status != .done }
    }

    public static func isReady(_ card: Card, in cards: [Card]) -> Bool {
        blockers(of: card, in: cards).isEmpty
    }

    /// To-Do cards that can start now, in build order, skipping any already
    /// claimed by a running worker.
    public static func ready(in cards: [Card], excluding claimed: Set<String> = []) -> [Card] {
        // A name that also lives in another column is already being (or has
        // been) worked on: a duplicate To-Do copy must never start a worker.
        let elsewhere = Set(cards.filter { $0.status != .todo }.map(\.slug))
        return cards
            .filter { $0.status == .todo && !claimed.contains($0.slug) && !elsewhere.contains($0.slug) && isReady($0, in: cards) }
            .sorted(by: Card.executionOrder)
    }

    /// True when `card` has had `attempts` or more workers finish within
    /// `window` without leaving To-Do: Auto mode should stop retrying it.
    public static func isStuck(_ card: String, jobs: [Job], attempts: Int = 2, window: TimeInterval = 15 * 60, now: Date = .now) -> Bool {
        jobs.filter { $0.card == card && !$0.state.isActive && now.timeIntervalSince($0.finishedAt ?? .distantPast) < window }
            .count >= attempts
    }

    /// How many new workers to start: fill up to `limit` running workers.
    /// Workers waiting on a question don't count, so the line keeps moving,
    /// but the total never exceeds twice the limit.
    public static func slotsToFill(limit: Int, running: Int, waiting: Int) -> Int {
        let byRunning = limit - running
        let byTotal = limit * 2 - (running + waiting)
        return max(0, min(byRunning, byTotal))
    }
}
