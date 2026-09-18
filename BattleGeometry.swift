import Foundation
import CoreGraphics

enum BattleSide {
    case opponent
    case player
}

/// The four possible on-field positions. Singles occupies only the outermost
/// slot on each side (`opponent2` / `player1`); doubles occupies all four.
enum BattleSlot: Int, CaseIterable {
    case opponent1
    case opponent2
    case player1
    case player2

    /// The other slot on the same side. Occupied only in doubles, which is
    /// what makes it the test for whether a partner can be caught in the blast.
    var partner: BattleSlot {
        switch self {
        case .opponent1: return .opponent2
        case .opponent2: return .opponent1
        case .player1: return .player2
        case .player2: return .player1
        }
    }

    var side: BattleSide {
        switch self {
        case .opponent1, .opponent2: return .opponent
        case .player1, .player2: return .player
        }
    }

    var label: String {
        switch self {
        case .opponent1: return "opponent1"
        case .opponent2: return "opponent2"
        case .player1: return "player1"
        case .player2: return "player2"
        }
    }
}
