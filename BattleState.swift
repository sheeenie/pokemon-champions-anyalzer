import Foundation

enum BattleFormat {
    case idle
    case singles
    case doubles

    var label: String {
        switch self {
        case .idle: return "No battle"
        case .singles: return "Singles"
        case .doubles: return "Doubles"
        }
    }
}

struct SlotOccupant {
    let species: Species
    let distance: Double
    let margin: Double
}

/// Holds what is currently on the field, smoothing over transient frames.
///
/// Matching runs on individual frames, and a frame can land mid-animation, on a
/// switch-in, or behind a menu. A slot therefore only changes after the same
/// answer arrives several times in a row, which keeps the panel from flickering
/// while still following real switches promptly.
final class BattleStateTracker: ObservableObject {

    /// Consecutive agreeing observations required before a slot changes.
    private static let confirmations = 3

    @Published private(set) var format: BattleFormat = .idle
    @Published private(set) var slots: [BattleSlot: SlotOccupant] = [:]

    /// Species key (nil = empty) currently proposed for each slot, with a count.
    private var pending: [BattleSlot: (key: String?, count: Int)] = [:]
    private var committed: [BattleSlot: String?] = [:]

    /// Feed one frame's answer for one slot. `nil` means the slot looks empty.
    func observe(_ slot: BattleSlot, _ result: MatchResult?) {
        let key = result?.species.key
        let current = committed[slot] ?? nil

        if key == current {
            pending[slot] = nil
            return
        }

        let seen = pending[slot]
        let count = (seen?.key == key ? seen!.count : 0) + 1
        pending[slot] = (key, count)
        guard count >= BattleStateTracker.confirmations else { return }

        pending[slot] = nil
        committed[slot] = key
        let occupant = result.map {
            SlotOccupant(species: $0.species, distance: $0.distance, margin: $0.margin)
        }
        publish(slot, occupant)
    }

    private func publish(_ slot: BattleSlot, _ occupant: SlotOccupant?) {
        DispatchQueue.main.async {
            if let occupant {
                self.slots[slot] = occupant
            } else {
                self.slots.removeValue(forKey: slot)
            }
            self.format = BattleStateTracker.inferFormat(from: self.slots)
        }
    }

    /// The inner slots are only ever used in doubles, so their occupancy is a
    /// more reliable signal than counting - during a switch a doubles battle can
    /// briefly show only two occupants.
    private static func inferFormat(from slots: [BattleSlot: SlotOccupant]) -> BattleFormat {
        if slots[.opponent1] != nil || slots[.player2] != nil { return .doubles }
        return slots.isEmpty ? .idle : .singles
    }
}
