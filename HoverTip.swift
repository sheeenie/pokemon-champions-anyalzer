import SwiftUI
import AppKit

/// A tip that waits before it appears and then follows the pointer.
///
/// Popovers came first, with two faults for a panel read mid-battle. They
/// opened the moment the pointer crossed a row, so running it down a card
/// flashed one per move; and they stayed pinned to the row with an arrow,
/// covering the rows below. A popover cannot follow the mouse, so this is a
/// small panel of its own that does.
final class TipPanel {
    static let shared = TipPanel()

    /// How long the pointer has to stay on something before its tip appears.
    static let delay: TimeInterval = 0.5
    /// Once a tip has been showing, the next one within this long appears at
    /// once, so reading down a list of moves does not wait on every row.
    static let warm: TimeInterval = 0.4
    /// Where the tip sits relative to the pointer: below and to the right,
    /// clear of the cursor so it never hides what is being pointed at.
    private static let offset = CGSize(width: 16, height: 20)

    private let panel: NSPanel
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var owner: UUID?
    private var pendingOwner: UUID?
    private var pending: DispatchWorkItem?
    private var lastHidden = Date.distantPast

    private init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        // It must never take the mouse: if it did, appearing under the pointer
        // would end the hover that opened it, and it would flicker.
        panel.ignoresMouseEvents = true
        // Stays up while the game, not this app, is frontmost - which during
        // play is most of the time.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = host
    }

    var isShowing: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    /// The pointer is over `id`. Counts down once per visit rather than on
    /// every movement, so a slowly moving pointer still gets its tip.
    func hover(_ id: UUID, content: @escaping () -> AnyView) {
        if owner == id, panel.isVisible { follow(); return }
        if pendingOwner == id { return }

        pending?.cancel()
        pendingOwner = id
        let show = DispatchWorkItem { [weak self] in
            guard let self, self.pendingOwner == id else { return }
            self.pendingOwner = nil
            self.owner = id
            self.host.rootView = content()
            self.panel.setContentSize(self.host.fittingSize)
            self.follow()
            self.panel.orderFrontRegardless()
            self.panel.invalidateShadow()
        }
        pending = show
        let warm = panel.isVisible || Date().timeIntervalSince(lastHidden) < TipPanel.warm
        DispatchQueue.main.asyncAfter(deadline: .now() + (warm ? 0 : TipPanel.delay), execute: show)
    }

    /// The pointer left `id`. Leaving one row for the next can report the new
    /// row first, so only the current owner can close the tip.
    func leave(_ id: UUID) {
        if pendingOwner == id {
            pending?.cancel()
            pending = nil
            pendingOwner = nil
        }
        guard owner == id else { return }
        owner = nil
        if panel.isVisible { lastHidden = Date() }
        panel.orderOut(nil)
    }

    /// Puts the tip beside the pointer, flipping to the other side where the
    /// screen runs out rather than hanging off the edge.
    private func follow() {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + TipPanel.offset.width,
                             y: mouse.y - TipPanel.offset.height - size.height)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let bounds = screen.visibleFrame
            if origin.x + size.width > bounds.maxX {
                origin.x = mouse.x - TipPanel.offset.width - size.width
            }
            if origin.y < bounds.minY {
                origin.y = mouse.y + TipPanel.offset.height
            }
            origin.x = min(max(bounds.minX, origin.x), bounds.maxX - size.width)
            origin.y = min(max(bounds.minY, origin.y), bounds.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
    }
}

/// The system popover material, which SwiftUI's own materials do not reliably
/// draw in a transparent borderless window.
private struct TipBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct HoverTip<Tip: View>: ViewModifier {
    let enabled: Bool
    let tip: () -> Tip
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    guard enabled else { return }
                    TipPanel.shared.hover(id) {
                        AnyView(
                            tip()
                                .background(TipBackground())
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12)))
                        )
                    }
                case .ended:
                    TipPanel.shared.leave(id)
                }
            }
            // A card replaced mid-hover takes its tip with it.
            .onDisappear { TipPanel.shared.leave(id) }
    }
}

extension View {
    /// Shows `tip` beside the pointer after it rests here a moment.
    func hoverTip<Tip: View>(enabled: Bool = true,
                             @ViewBuilder _ tip: @escaping () -> Tip) -> some View {
        modifier(HoverTip(enabled: enabled, tip: tip))
    }
}
