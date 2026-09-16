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

    /// Where the species artwork is drawn, in normalized frame coordinates.
    ///
    /// This is the identification target. The game renders every species at the
    /// same fixed size — measured at 121px in a 2622x1206 frame, i.e. 10.0% of
    /// frame height — so a single placement per slot describes all of them, and
    /// reference sprites can be pre-rendered once at load rather than searched
    /// for at match time.
    ///
    /// Independently fitted on two species (Garchomp on the opponent side,
    /// Maushold on the player side); both agreed on the 121px size.
    /// Positions were located by searching captured frames for a known
    /// reference icon, not derived from each other: an earlier player2 guessed
    /// as "player1 plus the plate offset" sat 36px too far right, which cropped
    /// half the artwork and made that slot silently unidentifiable. The inner
    /// slot spacing is 0.1686, not the 0.183 the plate edges suggest.
    ///
    /// opponent1 is still inferred, by mirroring the measured player spacing -
    /// no captured frame so far has had both opponent slots filled. The match
    /// window below is what keeps that from mattering.
    var normalizedSpriteBox: CGRect {
        let w = 0.0450, h = 0.0978
        switch self {
        case .opponent1: return CGRect(x: 0.5774, y: 0.0431, width: w, height: h)
        case .opponent2: return CGRect(x: 0.7460, y: 0.0431, width: w, height: h)
        case .player1:   return CGRect(x: 0.0915, y: 0.8425, width: w, height: h)
        case .player2:   return CGRect(x: 0.2601, y: 0.8425, width: w, height: h)
        }
    }

    /// Sprite box in pixels for a frame of the given size.
    func spriteRect(in size: CGSize) -> CGRect {
        let n = normalizedSpriteBox
        return CGRect(
            x: (n.origin.x * size.width).rounded(),
            y: (n.origin.y * size.height).rounded(),
            width: (n.size.width * size.width).rounded(),
            height: (n.size.height * size.height).rounded()
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
