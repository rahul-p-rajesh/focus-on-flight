import SwiftUI

/// A small, clean top-down airliner silhouette, nose up, in a 100 × 100 unit box: white fuselage,
/// swept wings with an engine under each, and a tailplane. Flat white with a soft drop shadow,
/// so it reads clearly over any scenery without looking busy. No coloured lights.
struct PlaneSilhouetteView: View {
    var span: CGFloat = 40

    /// Where the engine exhausts sit, as fractions of `span` from the centre (for contrails).
    static let exhaustX: CGFloat = 0.18
    static let exhaustY: CGFloat = 0.06

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 100
            let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100 * s, ty: 0)
            let white = GraphicsContext.Shading.color(.white)
            let engineTone = GraphicsContext.Shading.color(Color(white: 0.86))

            let unit = CGAffineTransform(scaleX: s, y: s)
            let wing = Self.wing.applying(unit), stab = Self.stabiliser.applying(unit), body = Self.fuselage.applying(unit)

            // Engines first so the wing edge sits over their back half.
            for x in [CGFloat(68), 32] {
                ctx.fill(Path(roundedRect: CGRect(x: (x - 2.8) * s, y: 40 * s, width: 5.6 * s, height: 13 * s), cornerRadius: 2.8 * s), with: engineTone)
            }
            for p in [wing, wing.applying(mirror), stab, stab.applying(mirror), body] { ctx.fill(p, with: white) }
            // A faint centre seam keeps the fuselage readable against bright fields.
            var seam = Path()
            seam.move(to: CGPoint(x: 50 * s, y: 16 * s)); seam.addLine(to: CGPoint(x: 50 * s, y: 80 * s))
            ctx.stroke(seam, with: .color(Color(white: 0.9)), lineWidth: 0.8 * s)
        }
        .frame(width: span, height: span)
        .shadow(color: .black.opacity(0.45), radius: span * 0.06, x: 0, y: span * 0.05)
        .accessibilityLabel("Your plane")
    }
}

// MARK: Shape

extension PlaneSilhouetteView {
    // The plane in a 100 × 100 box, nose up, y pointing down.

    /// Right wing; the left one is its mirror image.
    static let wing: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 53, y: 38))
        p.addLine(to: CGPoint(x: 97, y: 58.5))
        p.addQuadCurve(to: CGPoint(x: 97, y: 63), control: CGPoint(x: 98.6, y: 60.8))
        p.addLine(to: CGPoint(x: 53, y: 54.5))
        p.closeSubpath()
        return p
    }()

    /// Right tailplane.
    static let stabiliser: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 52.5, y: 81))
        p.addLine(to: CGPoint(x: 70.5, y: 90))
        p.addQuadCurve(to: CGPoint(x: 70.5, y: 93), control: CGPoint(x: 71.6, y: 91.5))
        p.addLine(to: CGPoint(x: 52.5, y: 90.5))
        p.closeSubpath()
        return p
    }()

    static let fuselage: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 50, y: 4))
        p.addQuadCurve(to: CGPoint(x: 54, y: 15), control: CGPoint(x: 54, y: 5.5))
        p.addLine(to: CGPoint(x: 54, y: 78))
        p.addQuadCurve(to: CGPoint(x: 50.9, y: 97), control: CGPoint(x: 54, y: 91))
        p.addLine(to: CGPoint(x: 49.1, y: 97))
        p.addQuadCurve(to: CGPoint(x: 46, y: 78), control: CGPoint(x: 46, y: 91))
        p.addLine(to: CGPoint(x: 46, y: 15))
        p.addQuadCurve(to: CGPoint(x: 50, y: 4), control: CGPoint(x: 46, y: 5.5))
        p.closeSubpath()
        return p
    }()

    /// The whole plane as one shape, for single-colour drawing such as the menu bar icon.
    static let outline: Path = {
        let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100, ty: 0)
        var p = Path()
        for part in [wing, wing.applying(mirror), stabiliser, stabiliser.applying(mirror), fuselage] { p.addPath(part) }
        return p
    }()
}
