import Foundation

/// Shuffled traversal of a playlist, ported from upstream AudioEngine's shuffle state so the
/// Linux engine walks shuffle and repeat exactly as the macOS one does: a stable order per pass,
/// the current track anchored first, and a fresh order (not starting on the same track) per repeat.
struct ShuffleOrder {
    private(set) var order: [Int] = []
    private(set) var position = -1
    private var pendingRepeat: [Int]?

    mutating func clear() {
        order = []
        position = -1
        pendingRepeat = nil
    }

    private func isValid(_ candidate: [Int], count: Int) -> Bool {
        candidate.count == count && Set(candidate) == Set(0..<count)
    }

    mutating func rebuild(count: Int, anchoredAt index: Int?) {
        guard count > 0 else { clear(); return }
        var indices = Array(0..<count)
        if let index, index >= 0, index < count {
            indices.removeAll { $0 == index }
            indices.shuffle()
            order = [index] + indices
        } else {
            indices.shuffle()
            order = indices
        }
        position = 0
        pendingRepeat = nil
    }

    /// Picks a random first track and builds the pass around it.
    mutating func startCycle(count: Int) -> Int? {
        guard count > 0 else { return nil }
        let start = Int.random(in: 0..<count)
        rebuild(count: count, anchoredAt: start)
        return start
    }

    private mutating func align(count: Int, current: Int) {
        guard count > 0 else { clear(); return }
        if !isValid(order, count: count) {
            rebuild(count: count, anchoredAt: current)
            return
        }
        if current >= 0, current < count {
            guard let found = order.firstIndex(of: current) else {
                rebuild(count: count, anchoredAt: current)
                return
            }
            position = found
        }
        if let pendingRepeat, !isValid(pendingRepeat, count: count) {
            self.pendingRepeat = nil
        }
    }

    private func repeatedOrder(count: Int, avoiding index: Int) -> [Int] {
        var next = Array(0..<count)
        next.shuffle()
        if next.count > 1, next.first == index {
            next.swapAt(0, Int.random(in: 1..<next.count))
        }
        return next
    }

    private mutating func preparedRepeat(count: Int, current: Int) -> [Int] {
        if let pendingRepeat, isValid(pendingRepeat, count: count) { return pendingRepeat }
        let next = repeatedOrder(count: count, avoiding: current)
        pendingRepeat = next
        return next
    }

    /// The track natural playback moves to next, without committing to it. Nil = pass over, no repeat.
    mutating func peekNext(count: Int, current: Int, repeating: Bool) -> Int? {
        guard count > 0 else { return nil }
        align(count: count, current: current)
        if current < 0 || current >= count { return order.first }
        if position >= 0, position + 1 < order.count { return order[position + 1] }
        guard repeating else { return nil }
        return preparedRepeat(count: count, current: current).first
    }

    /// Records that playback moved to `index` (after a `peekNext`).
    mutating func commitAdvance(to index: Int, count: Int, current: Int) {
        guard index >= 0, index < count else { clear(); return }
        align(count: count, current: current)
        if position >= 0, position + 1 < order.count, order[position + 1] == index {
            position += 1
            pendingRepeat = nil
        } else if let pendingRepeat, isValid(pendingRepeat, count: count), pendingRepeat.first == index {
            order = pendingRepeat
            position = 0
            self.pendingRepeat = nil
        } else if let found = order.firstIndex(of: index) {
            position = found
            pendingRepeat = nil
        } else {
            rebuild(count: count, anchoredAt: index)
        }
    }

    /// Next/Previous buttons: always land somewhere, starting a new pass at either end.
    mutating func manualNext(count: Int, current: Int) -> Int? {
        guard count > 0 else { return nil }
        align(count: count, current: current)
        if current < 0 || current >= count {
            if order.isEmpty { rebuild(count: count, anchoredAt: nil) }
            position = 0
            pendingRepeat = nil
            return order.first
        }
        if position >= 0, position + 1 < order.count {
            position += 1
            pendingRepeat = nil
            return order[position]
        }
        order = repeatedOrder(count: count, avoiding: current)
        position = 0
        pendingRepeat = nil
        return order.first
    }

    mutating func manualPrevious(count: Int, current: Int) -> Int? {
        guard count > 0 else { return nil }
        align(count: count, current: current)
        if current < 0 || current >= count {
            if order.isEmpty { rebuild(count: count, anchoredAt: nil) }
        } else if position > 0 {
            position -= 1
            pendingRepeat = nil
            return order[position]
        }
        guard !order.isEmpty else { return nil }
        position = order.count - 1
        pendingRepeat = nil
        return order[position]
    }

    /// Moves the cursor onto a track the user picked directly.
    mutating func select(_ index: Int, count: Int) {
        align(count: count, current: index)
        if let found = order.firstIndex(of: index) {
            position = found
            pendingRepeat = nil
        } else {
            rebuild(count: count, anchoredAt: index)
        }
    }
}
