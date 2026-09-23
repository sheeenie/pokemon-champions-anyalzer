import CoreGraphics

/// Where things sit on one device's screen, as fractions of the captured frame
/// with the origin at top-left.
///
/// Every region the analyzer reads was measured on one phone. A phone with a
/// different screen shape draws the game's name plates somewhere else in the
/// frame, so these numbers belong to a device rather than to the app. Keeping a
/// device's regions together is what lets another phone be added as a profile,
/// rather than as edits scattered through the analyzer.
struct CaptureProfile {
    let name: String
    /// The frame the regions were measured on. Profiles are matched on its shape.
    let frameSize: CGSize
    /// Where each slot's species artwork is drawn: the identification target.
    let spriteBoxes: [BattleSlot: CGRect]
    /// Name plate bounds. Only used to annotate calibration dumps, so a profile
    /// may leave them out rather than invent them.
    let plateBoxes: [BattleSlot: CGRect]
    /// The loading screen's bottom-right corner, where its Rotom icon appears.
    let loadingIconBox: CGRect

    var aspect: CGFloat { frameSize.width / frameSize.height }

    func spriteRect(_ slot: BattleSlot, in size: CGSize) -> CGRect {
        pixels(spriteBoxes[slot]!, in: size)
    }

    func plateRect(_ slot: BattleSlot, in size: CGSize) -> CGRect? {
        plateBoxes[slot].map { pixels($0, in: size) }
    }

    private func pixels(_ box: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: (box.origin.x * size.width).rounded(),
               y: (box.origin.y * size.height).rounded(),
               width: (box.size.width * size.width).rounded(),
               height: (box.size.height * size.height).rounded())
    }
}

extension CaptureProfile {

    /// Every profile the app knows. Add a device here.
    static let all: [CaptureProfile] = [.iPhone17, .pixel7]

    /// The profile measured on the screen shape closest to this frame's.
    ///
    /// Fractions carry over between phones of the same shape at any resolution,
    /// so shape, not size, is what decides. With one profile this is always
    /// iPhone 17; the point is that a second device slots in here.
    static func matching(_ size: CGSize) -> CaptureProfile {
        let aspect = size.width / size.height
        return all.min { abs($0.aspect - aspect) < abs($1.aspect - aspect) } ?? .iPhone17
    }

    /// iPhone 17, captured at 2622x1206 over USB.
    ///
    /// Sprite boxes: the game renders every species at one fixed size, measured
    /// at 121px here, 10.0% of frame height - so one placement per slot covers
    /// all of them, and reference sprites are rasterized once at load instead of
    /// searched for at match time. Fitted independently on two species
    /// (Garchomp on the opponent side, Maushold on the player side), which
    /// agreed on the size. Positions were found by searching captured frames
    /// for a known reference icon rather than derived from one another: a
    /// player2 once guessed as "player1 plus the plate offset" sat 36px too far
    /// right, cropped half the artwork, and left that slot silently
    /// unidentifiable. The inner slot spacing is 0.1686, not the 0.183 the
    /// plate edges suggest. opponent1 is inferred by mirroring the measured
    /// player spacing, since no frame yet has had both opponent slots filled;
    /// the matcher's search window is what keeps that from mattering.
    ///
    /// Plates: opponent plates anchor right and grow leftward, player plates
    /// anchor left and grow rightward. The sides are not mirror images - the
    /// opponent plate has its icon top-left, the player plate low on the left
    /// under the HP bar - so the player plates are taller and start higher.
    ///
    /// Loading icon: measured on a recorded loading screen, where the Rotom
    /// icon and its progress bar sit well inside this corner.
    static let iPhone17 = CaptureProfile(
        name: "iPhone 17",
        frameSize: CGSize(width: 2622, height: 1206),
        spriteBoxes: [
            .opponent1: CGRect(x: 0.5774, y: 0.0431, width: 0.0450, height: 0.0978),
            .opponent2: CGRect(x: 0.7460, y: 0.0431, width: 0.0450, height: 0.0978),
            .player1:   CGRect(x: 0.0915, y: 0.8425, width: 0.0450, height: 0.0978),
            .player2:   CGRect(x: 0.2601, y: 0.8425, width: 0.0450, height: 0.0978),
        ],
        plateBoxes: [
            .opponent1: CGRect(x: 0.586, y: 0.045, width: 0.151, height: 0.105),
            .opponent2: CGRect(x: 0.743, y: 0.045, width: 0.174, height: 0.105),
            .player1:   CGRect(x: 0.081, y: 0.790, width: 0.177, height: 0.170),
            .player2:   CGRect(x: 0.264, y: 0.790, width: 0.177, height: 0.170),
        ],
        loadingIconBox: CGRect(x: 0.70, y: 0.58, width: 0.29, height: 0.40)
    )
}

extension CaptureProfile {

    /// Pixel 7, mirrored by scrcpy and captured at 2746x1236.
    ///
    /// The game anchors its plates to the screen edges, so a 2.222 screen is not
    /// a 2.174 screen with different numbers in the same places: the player's
    /// sprite sits at y 0.8916 here against 0.8425 on the iPhone. Measured the
    /// same way - searching a captured battle for a known reference icon, which
    /// found Gengar at distance 0.021 on the opponent's plate and 0.023 on the
    /// player's, both 123px square.
    ///
    /// All four slots are measured, each from a battle where that plate was on
    /// screen: Gengar on both singles slots, Drampa at 0.050 and Toxicroak at
    /// 0.051 on the two opponent slots, and Whimsicott at 0.026 on the
    /// player's partner slot.
    ///
    /// Inference is not a substitute, and the two inner slots show both sides
    /// of that. opponent1, placed from the iPhone's spacing, sat 8px from the
    /// truth - under 0.3% of the frame - and lost the slot completely: the
    /// sprite is 123px, so the matcher's search window straddled the real
    /// position and every probe it tried landed far enough off to be rejected.
    /// player2, placed from this phone's own measured opponent spacing of
    /// 0.1650, landed within a pixel of where the search later found it. The
    /// difference between the two guesses was whose spacing they used.
    ///
    /// The loading-screen corner is the iPhone's, deliberately generous and not
    /// yet confirmed against a Pixel loading screen.
    ///
    /// Plates are not measured here: they only annotate calibration dumps.
    static let pixel7 = CaptureProfile(
        name: "Pixel 7",
        frameSize: CGSize(width: 2746, height: 1236),
        spriteBoxes: [
            .opponent1: CGRect(x: 0.5983, y: 0.0421, width: 0.0450, height: 0.0999),
            .opponent2: CGRect(x: 0.7633, y: 0.0421, width: 0.0450, height: 0.0999),
            .player1:   CGRect(x: 0.0768, y: 0.8916, width: 0.0450, height: 0.0999),
            .player2:   CGRect(x: 0.2422, y: 0.8916, width: 0.0450, height: 0.0999),
        ],
        plateBoxes: [:],
        loadingIconBox: CGRect(x: 0.70, y: 0.58, width: 0.29, height: 0.40)
    )
}
