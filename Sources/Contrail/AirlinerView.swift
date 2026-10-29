import SwiftUI

/// A top-down twin-engine airliner, nose up, drawn in a 100 × 100 unit box.
/// Shaded fuselage, swept wings with flap lines, engines with inlets, tailplane,
/// cockpit windows, and navigation lights (red left, green right, white strobes).
struct AirlinerView: View {
    var span: CGFloat = 66
    /// Seconds, used to blink the strobes and beacon.
    var time: TimeInterval

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 100
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100 * s, ty: 0)
            let outline = GraphicsContext.Shading.color(Color(red: 0.42, green: 0.46, blue: 0.52).opacity(0.75))
            let lw = 0.45 * s

            // Wings (right, then mirrored).
            var wing = Path()
            wing.move(to: pt(53.5, 37))
            wing.addQuadCurve(to: pt(97, 59.3), control: pt(76, 46.5))
            wing.addQuadCurve(to: pt(97.2, 63.4), control: pt(98.2, 61.4))
            wing.addQuadCurve(to: pt(53.5, 56.5), control: pt(77, 58.8))
            wing.closeSubpath()
            let wings = wing.applying(.identity)
            let wingShade = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(white: 0.97), Color(red: 0.80, green: 0.83, blue: 0.87)]),
                startPoint: pt(50, 38), endPoint: pt(50, 64))
            for w in [wings, wings.applying(mirror)] {
                ctx.fill(w, with: wingShade)
                ctx.stroke(w, with: outline, lineWidth: lw)
            }
            // Flap and aileron lines along the trailing edge.
            var flaps = Path()
            flaps.move(to: pt(56, 53.6)); flaps.addQuadCurve(to: pt(80, 58.4), control: pt(68, 56.6))
            flaps.move(to: pt(81.5, 58.7)); flaps.addLine(to: pt(93.5, 61.2))
            for f in [flaps, flaps.applying(mirror)] {
                ctx.stroke(f, with: .color(Color(white: 0.55).opacity(0.7)), lineWidth: 0.4 * s)
            }

            // Engines under the wings.
            for x in [CGFloat(69), 31] {
                let nacelle = Path(roundedRect: CGRect(x: (x - 2.7) * s, y: 39 * s, width: 5.4 * s, height: 14.5 * s), cornerRadius: 2.7 * s)
                ctx.fill(nacelle, with: .linearGradient(
                    Gradient(colors: [Color(white: 0.62), Color(white: 0.90), Color(white: 0.58)]),
                    startPoint: pt(x - 2.7, 0), endPoint: pt(x + 2.7, 0)))
                ctx.stroke(nacelle, with: outline, lineWidth: lw)
                ctx.fill(Path(ellipseIn: CGRect(x: (x - 2.1) * s, y: 39.4 * s, width: 4.2 * s, height: 2.4 * s)),
                         with: .color(Color(white: 0.18)))
                ctx.fill(Path(ellipseIn: CGRect(x: (x - 1.2) * s, y: 52.2 * s, width: 2.4 * s, height: 1.8 * s)),
                         with: .color(Color(white: 0.35)))
            }

            // Tailplane.
            var stab = Path()
            stab.move(to: pt(52.5, 80.5))
            stab.addQuadCurve(to: pt(70, 89.6), control: pt(62, 83.5))
            stab.addLine(to: pt(70.4, 92.6))
            stab.addLine(to: pt(52.5, 90.5))
            stab.closeSubpath()
            for t in [stab, stab.applying(mirror)] {
                ctx.fill(t, with: wingShade)
                ctx.stroke(t, with: outline, lineWidth: lw)
            }

            // Fuselage with a rounded nose and tapered tail cone.
            var body = Path()
            body.move(to: pt(50, 3.5))
            body.addQuadCurve(to: pt(54.6, 16), control: pt(54.6, 5.5))
            body.addLine(to: pt(54.6, 77))
            body.addQuadCurve(to: pt(51.4, 96.5), control: pt(54.6, 90))
            body.addLine(to: pt(48.6, 96.5))
            body.addQuadCurve(to: pt(45.4, 77), control: pt(45.4, 90))
            body.addLine(to: pt(45.4, 16))
            body.addQuadCurve(to: pt(50, 3.5), control: pt(45.4, 5.5))
            body.closeSubpath()
            ctx.fill(body, with: .linearGradient(
                Gradient(stops: [.init(color: Color(red: 0.76, green: 0.79, blue: 0.84), location: 0),
                                 .init(color: .white, location: 0.42),
                                 .init(color: Color(white: 0.93), location: 0.62),
                                 .init(color: Color(red: 0.70, green: 0.74, blue: 0.80), location: 1)]),
                startPoint: pt(45.4, 0), endPoint: pt(54.6, 0)))
            ctx.stroke(body, with: outline, lineWidth: lw)

            // Wing-to-body fairing and fin.
            ctx.fill(Path(ellipseIn: CGRect(x: 46 * s, y: 35 * s, width: 8 * s, height: 24 * s)),
                     with: .color(Color(white: 0.86).opacity(0.6)))
            ctx.fill(Path(roundedRect: CGRect(x: 49.25 * s, y: 78 * s, width: 1.5 * s, height: 18 * s), cornerRadius: 0.75 * s),
                     with: .color(Color(red: 0.55, green: 0.60, blue: 0.67)))

            // Cockpit windows.
            var cockpit = Path()
            cockpit.move(to: pt(46.6, 11.6))
            cockpit.addQuadCurve(to: pt(53.4, 11.6), control: pt(50, 8.9))
            cockpit.addLine(to: pt(53.8, 13.4))
            cockpit.addQuadCurve(to: pt(46.2, 13.4), control: pt(50, 10.9))
            cockpit.closeSubpath()
            ctx.fill(cockpit, with: .color(Color(red: 0.15, green: 0.19, blue: 0.25)))

            // Lights: steady red (left) and green (right) wingtips, double-flash white strobes, red beacon.
            let flash = (time.truncatingRemainder(dividingBy: 1.2))
            let strobe = flash < 0.06 || (flash > 0.16 && flash < 0.22)
            let beacon = time.truncatingRemainder(dividingBy: 1.0) < 0.12
            func light(_ x: CGFloat, _ y: CGFloat, _ color: Color, _ r: CGFloat) {
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: r * s * 0.9))
                    l.fill(Path(ellipseIn: CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s)), with: .color(color.opacity(0.85)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: (x - 0.8) * s, y: (y - 0.8) * s, width: 1.6 * s, height: 1.6 * s)), with: .color(color))
            }
            light(3.2, 61.6, Color(red: 1, green: 0.25, blue: 0.2), 2.2)
            light(96.8, 61.6, Color(red: 0.25, green: 1, blue: 0.45), 2.2)
            if strobe {
                light(3.4, 63.2, .white, 3)
                light(96.6, 63.2, .white, 3)
                light(50, 96.8, .white, 2.6)
            }
            if beacon { light(50, 44, Color(red: 1, green: 0.2, blue: 0.15), 1.9) }
        }
        .frame(width: span, height: span)
        .shadow(color: .black.opacity(0.5), radius: span * 0.07, x: 0, y: span * 0.06)
        .accessibilityLabel("Your plane")
    }
}
