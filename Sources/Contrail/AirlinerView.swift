import SwiftUI

/// A top-down private jet, nose up, drawn in a 100 × 100 unit box: slim fuselage with a long nose,
/// swept wings with winglets, two engines mounted on the rear fuselage, and a T-tail.
/// No coloured navigation lights.
struct PrivateJetView: View {
    var span: CGFloat = 72

    /// Where the engine exhausts sit, as fractions of `span` from the centre (for contrails).
    static let exhaustX: CGFloat = 0.085
    static let exhaustY: CGFloat = 0.36

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 100
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100 * s, ty: 0)
            let outline = GraphicsContext.Shading.color(Color(red: 0.40, green: 0.44, blue: 0.50).opacity(0.7))
            let lw = 0.4 * s
            let skin = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(white: 0.98), Color(red: 0.82, green: 0.85, blue: 0.89)]),
                startPoint: pt(50, 30), endPoint: pt(50, 72))

            // Swept wings with small winglets at the tips.
            var wing = Path()
            wing.move(to: pt(53.2, 41))
            wing.addQuadCurve(to: pt(88.5, 61), control: pt(72, 49))
            wing.addLine(to: pt(90.5, 61.4))
            wing.addLine(to: pt(90.8, 64.6))
            wing.addQuadCurve(to: pt(53.2, 56), control: pt(73, 60.5))
            wing.closeSubpath()
            for w in [wing, wing.applying(mirror)] {
                ctx.fill(w, with: skin)
                ctx.stroke(w, with: outline, lineWidth: lw)
            }
            var flaps = Path()
            flaps.move(to: pt(55.5, 54.2)); flaps.addQuadCurve(to: pt(78, 59.6), control: pt(66, 57.4))
            var winglet = Path()
            winglet.move(to: pt(89.6, 61.2)); winglet.addLine(to: pt(90.6, 58.6))
            for f in [flaps, flaps.applying(mirror), winglet, winglet.applying(mirror)] {
                ctx.stroke(f, with: .color(Color(white: 0.55).opacity(0.75)), lineWidth: 0.45 * s)
            }

            // T-tail: horizontal stabiliser on top of the fin at the very back.
            var stab = Path()
            stab.move(to: pt(51, 86.5))
            stab.addQuadCurve(to: pt(66.5, 92), control: pt(59, 88))
            stab.addLine(to: pt(67, 94.6))
            stab.addLine(to: pt(51, 93.2))
            stab.closeSubpath()

            // Fuselage: long pointed nose, slim body, tapered tail.
            var body = Path()
            body.move(to: pt(50, 3))
            body.addQuadCurve(to: pt(53.8, 22), control: pt(53.8, 6))
            body.addLine(to: pt(53.8, 76))
            body.addQuadCurve(to: pt(51, 96), control: pt(53.8, 90))
            body.addLine(to: pt(49, 96))
            body.addQuadCurve(to: pt(46.2, 76), control: pt(46.2, 90))
            body.addLine(to: pt(46.2, 22))
            body.addQuadCurve(to: pt(50, 3), control: pt(46.2, 6))
            body.closeSubpath()
            ctx.fill(body, with: .linearGradient(
                Gradient(stops: [.init(color: Color(red: 0.76, green: 0.79, blue: 0.84), location: 0),
                                 .init(color: .white, location: 0.42),
                                 .init(color: Color(white: 0.94), location: 0.62),
                                 .init(color: Color(red: 0.70, green: 0.74, blue: 0.80), location: 1)]),
                startPoint: pt(46.2, 0), endPoint: pt(53.8, 0)))
            ctx.stroke(body, with: outline, lineWidth: lw)

            // A thin accent stripe along each side of the cabin.
            for x in [CGFloat(47.3), 52.7] {
                var stripe = Path()
                stripe.move(to: pt(x, 20)); stripe.addLine(to: pt(x, 74))
                ctx.stroke(stripe, with: .color(Color(red: 0.42, green: 0.55, blue: 0.70).opacity(0.55)), lineWidth: 0.5 * s)
            }

            // Rear-mounted engines on short pylons.
            for x in [CGFloat(58.5), 41.5] {
                // Short pylon joining the engine to the fuselage side.
                let pylon = x < 50
                    ? Path(CGRect(x: (x + 2.6) * s, y: 77 * s, width: (46.4 - x - 2.6) * s, height: 3 * s))
                    : Path(CGRect(x: 53.6 * s, y: 77 * s, width: (x - 2.6 - 53.6) * s, height: 3 * s))
                ctx.fill(pylon, with: .color(Color(white: 0.78)))
                let nacelle = Path(roundedRect: CGRect(x: (x - 2.9) * s, y: 71 * s, width: 5.8 * s, height: 16 * s), cornerRadius: 2.9 * s)
                ctx.fill(nacelle, with: .linearGradient(
                    Gradient(colors: [Color(white: 0.66), Color(white: 0.95), Color(white: 0.62)]),
                    startPoint: pt(x - 2.9, 0), endPoint: pt(x + 2.9, 0)))
                ctx.stroke(nacelle, with: outline, lineWidth: lw)
                ctx.fill(Path(ellipseIn: CGRect(x: (x - 2.2) * s, y: 71.4 * s, width: 4.4 * s, height: 2.4 * s)), with: .color(Color(white: 0.2)))
                ctx.fill(Path(ellipseIn: CGRect(x: (x - 1.4) * s, y: 85 * s, width: 2.8 * s, height: 1.8 * s)), with: .color(Color(white: 0.38)))
            }

            for t in [stab, stab.applying(mirror)] {
                ctx.fill(t, with: skin)
                ctx.stroke(t, with: outline, lineWidth: lw)
            }
            ctx.fill(Path(roundedRect: CGRect(x: 49.3 * s, y: 80 * s, width: 1.4 * s, height: 16 * s), cornerRadius: 0.7 * s),
                     with: .color(Color(red: 0.55, green: 0.60, blue: 0.67)))

            // Cockpit windscreen.
            var cockpit = Path()
            cockpit.move(to: pt(47.2, 13.6))
            cockpit.addQuadCurve(to: pt(52.8, 13.6), control: pt(50, 10.8))
            cockpit.addLine(to: pt(53.2, 15.6))
            cockpit.addQuadCurve(to: pt(46.8, 15.6), control: pt(50, 12.9))
            cockpit.closeSubpath()
            ctx.fill(cockpit, with: .color(Color(red: 0.14, green: 0.18, blue: 0.24)))
        }
        .frame(width: span, height: span)
        .shadow(color: .black.opacity(0.5), radius: span * 0.07, x: 0, y: span * 0.06)
        .accessibilityLabel("Your plane")
    }
}
