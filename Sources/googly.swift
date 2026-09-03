import Cocoa

// A menu-bar status icon drawn as two googly eyes whose pupils follow the mouse
// pointer anywhere on screen. Replaces the old "🍒" title. It passes clicks
// through to the underlying NSStatusBarButton (hitTest → nil) so the existing
// left-click / right-click behaviour keeps working.
final class GooglyEyesView: NSView {
    private var timer: Timer?
    private var lastMouse: NSPoint = .zero
    private var blink: CGFloat = 0        // 0 = open, 1 = fully shut
    private var blinkPhase: Int = 0        // frames until next blink cycle step
    private var tick = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        guard window != nil else { return }
        // ~60fps poll of the global cursor location — no accessibility permission needed.
        let t = Timer(timeInterval: 1.0/60.0, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func step() {
        tick += 1
        // Occasional blink for a bit of life (~every 4.5s, quick close/open).
        if blinkPhase > 0 {
            blinkPhase -= 1
            blink = blinkPhase > 4 ? min(1, blink + 0.34) : max(0, blink - 0.34)
        } else if tick % 270 == 0 {
            blinkPhase = 8
        }
        let m = NSEvent.mouseLocation
        if abs(m.x - lastMouse.x) > 0.4 || abs(m.y - lastMouse.y) > 0.4 || blinkPhase > 0 || blink > 0 {
            lastMouse = m
            needsDisplay = true
        }
    }

    // Pass all clicks through to the status-bar button beneath us.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let eyeR = min(b.height * 0.46, 8.5)          // eye (white) radius
        let cy = b.midY
        let gap = eyeR * 0.12                          // eyes almost touching, like the 👀 emoji
        let leftC  = NSPoint(x: b.midX - eyeR - gap, y: cy)
        let rightC = NSPoint(x: b.midX + eyeR + gap, y: cy)

        // Fixed colors — NOT labelColor, which turns white in the menu bar's dark
        // appearance and made the pupils invisible.
        let pupilColor = NSColor(white: 0.10, alpha: 1)
        let white = NSColor.white

        for c in [leftC, rightC] {
            // eye white (squashed vertically while blinking)
            let openH = eyeR * 2 * (1 - blink * 0.92)
            let eyeRect = NSRect(x: c.x - eyeR, y: c.y - openH/2, width: eyeR * 2, height: max(openH, 1))
            let eye = NSBezierPath(ovalIn: eyeRect)
            white.setFill(); eye.fill()
            NSColor(white: 0.0, alpha: 0.18).setStroke(); eye.lineWidth = 0.5; eye.stroke()

            if blink < 0.6 {
                // pupil position: point toward the cursor, clamped inside the eye
                let center = pointToScreen(c)
                let dx = lastMouse.x - center.x, dy = lastMouse.y - center.y
                let dist = max(sqrt(dx*dx + dy*dy), 0.0001)
                let pupilR = eyeR * 0.56
                let travel = eyeR - pupilR - 0.5
                let px = c.x + (dx/dist) * travel
                let py = c.y + (dy/dist) * travel * (1 - blink)   // ride up as lid closes
                let pr = NSRect(x: px - pupilR, y: py - pupilR, width: pupilR*2, height: pupilR*2)
                let pupil = NSBezierPath(ovalIn: pr)
                pupilColor.setFill(); pupil.fill()
                // tiny catch-light on the pupil
                let gl = NSBezierPath(ovalIn: NSRect(x: px - pupilR*0.5, y: py + pupilR*0.15,
                                                     width: pupilR*0.42, height: pupilR*0.42))
                white.withAlphaComponent(0.9).setFill(); gl.fill()
            }
        }
    }

    private func pointToScreen(_ p: NSPoint) -> NSPoint {
        guard let win = window else { return p }
        let inWindow = convert(p, to: nil)
        return win.convertPoint(toScreen: inWindow)
    }

    deinit { timer?.invalidate() }
}
