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

    /// Consecutive agreeing observations before a slot shows a new Pokemon.
    private static let confirmations = 3

    @Published private(set) var format: BattleFormat = .idle
    @Published private(set) var slots: [BattleSlot: SlotOccupant] = [:]

    /// Species key currently proposed for each slot, with an agreement count.
    private var pending: [BattleSlot: (key: String, count: Int)] = [:]
    private var committed: [BattleSlot: String] = [:]

    /// Feed one frame's answer for one slot.
    ///
    /// A nil result is ignored rather than blanking the slot. The name plates
    /// vanish during every move animation, so clearing on nil made the panel
    /// flicker between the cards and "Unidentified" all battle. A card stays up
    /// until a *different* Pokemon is confidently identified in that slot.
    func observe(_ slot: BattleSlot, _ result: MatchResult?) {
        // A no-op, not a reset. Clearing progress here meant a plate that
        // flickers between visible and hidden (which is every plate, during
        // every animation) alternated match/nil and never accumulated the
        // agreements needed to commit at all.
        guard let result else { return }

        let key = result.species.key
        if committed[slot] == key {
            pending[slot] = nil
            return
        }

        let count: Int
        if let seen = pending[slot], seen.key == key {
            count = seen.count + 1
        } else {
            count = 1
        }
        pending[slot] = (key, count)
        guard count >= BattleStateTracker.confirmations else { return }

        pending[slot] = nil
        committed[slot] = key
        publish(slot, SlotOccupant(species: result.species,
                                   distance: result.distance,
                                   margin: result.margin))
    }

    private func publish(_ slot: BattleSlot, _ occupant: SlotOccupant) {
        DispatchQueue.main.async {
            self.slots[slot] = occupant
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
