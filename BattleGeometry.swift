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

    /// Name plate bounds as fractions of the rendered game area, origin top-left.
    ///
    /// Calibrated against 2622x1206 capture frames. Opponent plates anchor to the
    /// right edge and grow leftward; player plates anchor left and grow rightward,
    /// so the same table covers singles (where only the outermost slot is occupied).
    ///
    /// The two sides are not vertical mirrors: the opponent plate carries its face
    /// icon at top-left, while the player plate carries it low on the left, hanging
    /// below the HP bar. Player rects are therefore taller and start higher.
    var normalizedPlate: CGRect {
        switch self {
        case .opponent1: return CGRect(x: 0.586, y: 0.045, width: 0.151, height: 0.105)
        case .opponent2: return CGRect(x: 0.743, y: 0.045, width: 0.174, height: 0.105)
        case .player1:   return CGRect(x: 0.081, y: 0.790, width: 0.177, height: 0.170)
        case .player2:   return CGRect(x: 0.264, y: 0.790, width: 0.177, height: 0.170)
        }
    }

    /// The species artwork within the plate, as a fraction of `normalizedPlate`.
    /// This is the identification target: a static 2D asset, so it renders
    /// pixel-identically every time regardless of camera, pose or lighting.
    var normalizedIconInPlate: CGRect {
        switch side {
        case .opponent: return CGRect(x: 0.00, y: 0.00, width: 0.24, height: 1.00)
        case .player:   return CGRect(x: 0.03, y: 0.52, width: 0.28, height: 0.48)
        }
    }

    /// Icon rect in pixels for a frame of the given size.
    func iconRect(in size: CGSize) -> CGRect {
        let plate = plateRect(in: size)
        let f = normalizedIconInPlate
        return CGRect(
            x: (plate.origin.x + f.origin.x * plate.width).rounded(),
            y: (plate.origin.y + f.origin.y * plate.height).rounded(),
            width: (f.size.width * plate.width).rounded(),
            height: (f.size.height * plate.height).rounded()
        )
    }

    /// Plate rect in pixels for a frame of the given size.
    func plateRect(in size: CGSize) -> CGRect {
        let n = normalizedPlate
        return CGRect(
            x: (n.origin.x * size.width).rounded(),
            y: (n.origin.y * size.height).rounded(),
            width: (n.size.width * size.width).rounded(),
            height: (n.size.height * size.height).rounded()
        )
    }
}
