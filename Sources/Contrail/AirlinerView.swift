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
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100 * s, ty: 0)
            let white = GraphicsContext.Shading.color(.white)
            let engineTone = GraphicsContext.Shading.color(Color(white: 0.86))

            var wing = Path()
            wing.move(to: pt(53, 38))
            wing.addLine(to: pt(97, 58.5))
            wing.addQuadCurve(to: pt(97, 63), control: pt(98.6, 60.8))
            wing.addLine(to: pt(53, 54.5))
            wing.closeSubpath()

            var stab = Path()
            stab.move(to: pt(52.5, 81))
            stab.addLine(to: pt(70.5, 90))
            stab.addQuadCurve(to: pt(70.5, 93), control: pt(71.6, 91.5))
            stab.addLine(to: pt(52.5, 90.5))
            stab.closeSubpath()

            var body = Path()
            body.move(to: pt(50, 4))
            body.addQuadCurve(to: pt(54, 15), control: pt(54, 5.5))
            body.addLine(to: pt(54, 78))
            body.addQuadCurve(to: pt(50.9, 97), control: pt(54, 91))
            body.addLine(to: pt(49.1, 97))
            body.addQuadCurve(to: pt(46, 78), control: pt(46, 91))
            body.addLine(to: pt(46, 15))
            body.addQuadCurve(to: pt(50, 4), control: pt(46, 5.5))
            body.closeSubpath()

            // Engines first so the wing edge sits over their back half.
            for x in [CGFloat(68), 32] {
                ctx.fill(Path(roundedRect: CGRect(x: (x - 2.8) * s, y: 40 * s, width: 5.6 * s, height: 13 * s), cornerRadius: 2.8 * s), with: engineTone)
            }
            for p in [wing, wing.applying(mirror), stab, stab.applying(mirror), body] { ctx.fill(p, with: white) }
            // A faint centre seam keeps the fuselage readable against bright fields.
            var seam = Path()
            seam.move(to: pt(50, 16)); seam.addLine(to: pt(50, 80))
            ctx.stroke(seam, with: .color(Color(white: 0.9)), lineWidth: 0.8 * s)
        }
        .frame(width: span, height: span)
        .shadow(color: .black.opacity(0.45), radius: span * 0.06, x: 0, y: span * 0.05)
        .accessibilityLabel("Your plane")
    }
}
