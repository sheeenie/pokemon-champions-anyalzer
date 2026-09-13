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

/// A Pokemon confirmed at some point this battle, kept for the speed list after
/// it has switched out.
struct SeenPokemon {
    let species: Species
    let side: BattleSide
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
    /// Everything confirmed since the last reset, on both sides.
    @Published private(set) var seen: [String: SeenPokemon] = [:]

    /// Species key currently proposed for each slot, with an agreement count.
    private var pending: [BattleSlot: (key: String, count: Int)] = [:]
    private var committed: [BattleSlot: String] = [:]
    /// Mirror of `seen`'s keys on the analysis queue, so only additions publish.
    private var seenIDs: Set<String> = []

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
            // Recorded here too, not only on commit: after a reset the same
            // Pokemon can return in the next battle to a slot already showing
            // it, which never commits again and would stay off the list.
            recordSeen(slot, result.species)
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
        recordSeen(slot, result.species)
        publish(slot, SlotOccupant(species: result.species,
                                   distance: result.distance,
                                   margin: result.margin))
    }

    /// Clears the speed list, for a new battle. Cards are left alone: they
    /// persist until a different Pokemon replaces them.
    func resetSeen() {
        seenIDs.removeAll()
        DispatchQueue.main.async { self.seen.removeAll() }
    }

    private func recordSeen(_ slot: BattleSlot, _ species: Species) {
        // Identity ignores shininess: a shiny is the same Pokemon at the same speed.
        let id = "\(slot.side)-\(species.dex)-\(species.form)"
        guard seenIDs.insert(id).inserted else { return }
        let entry = SeenPokemon(species: species, side: slot.side)
        DispatchQueue.main.async { self.seen[id] = entry }
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
