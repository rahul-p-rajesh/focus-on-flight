import SwiftUI

/// Timing of the crash shown when a flight is ended early.
enum CrashTiming {
    /// The plane spirals down while the camera drops towards the ground.
    static let fall = 3.2
    /// Fireball, shock ring and smoke, then the scene dims.
    static let total = 5.8
}

/// The crash sequence over the map, driven by the time since it started.
struct CrashScene: View {
    let start: Date

    var body: some View {
        TimelineView(.animation) { tl in
            CrashFrame(t: tl.date.timeIntervalSince(start))
        }
        .allowsHitTesting(false)
    }
}

/// One frame of the crash, `t` seconds in. Shared by the live scene and the offscreen preview.
struct CrashFrame: View {
    let t: Double

    private static let fall = CrashTiming.fall

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let m = min(size.width, size.height)
            let u = t - Self.fall // time since impact
            ZStack {
                Canvas { ctx, _ in
                    drawSmokeTrail(ctx, c: c)
                    if u > 0 { drawImpact(ctx, c: c, m: m, u: u) }
                }
                if u < 0 {
                    let f = max(0, t) / Self.fall
                    PlaneSilhouetteView(span: 26)
                        .rotation3DEffect(.degrees(sin(t * 3.1) * 55), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .rotationEffect(.degrees(Self.spin(t)))
                        .scaleEffect(1 - 0.3 * f)
                        .position(Self.planePoint(t, c: c, m: m))
                }
                // Impact flash.
                if u > 0 && u < 0.6 {
                    Color(red: 1, green: 0.86, blue: 0.62).opacity(0.55 * (1 - u / 0.6))
                }
                // The scene settles into darkness before the summary.
                Color.black.opacity(0.6 * Self.ease((u - 1.1) / 1.4))
            }
        }
    }

    // MARK: Motion

    /// Accelerating spin, in degrees: about three turns by impact.
    static func spin(_ t: Double) -> Double { 50 * t + 90 * t * t }

    /// The plane spirals out from the centre and back in, landing in the middle of the screen.
    static func planePoint(_ t: Double, c: CGPoint, m: CGFloat) -> CGPoint {
        let f = min(max(t / fall, 0), 1)
        let r = m * 0.07 * sin(.pi * f)
        let a = f * 2.6 * .pi
        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
    }

    static func ease(_ x: Double) -> Double { let v = min(1, max(0, x)); return v * v * (3 - 2 * v) }
    static func easeOut(_ x: Double) -> Double { let v = min(1, max(0, x)); return 1 - (1 - v) * (1 - v) }

    // MARK: Drawing

    /// Dark smoke streaming from the falling plane. Older puffs grow, fade and slide back as the camera moves on.
    private func drawSmokeTrail(_ ctx: GraphicsContext, c: CGPoint) {
        let m = min(c.x, c.y) * 2
        let step = 0.04
        let fallEnd = min(t, Self.fall)
        var i = 0
        while i < 90 {
            let born = fallEnd - Double(i) * step
            i += 1
            guard born >= 0 else { break }
            let age = t - born
            guard age < 3.4 else { continue }
            let p = Self.planePoint(born, c: c, m: m)
            let drift = age * 34
            let r = 2.5 + age * 11
            let fade = 1 - age / 3.4
            let tone = 0.16 + min(age, 1.5) * 0.12
            let rect = CGRect(x: p.x - r + sin(born * 7) * age * 3, y: p.y - r + drift, width: r * 2, height: r * 2)
            Self.puff(ctx, in: rect, color: Color(white: tone), opacity: 0.9 * fade)
            // Fresh smoke glows with the fire behind it.
            if age < 0.18 && t < Self.fall {
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: r * 0.3, dy: r * 0.3)),
                         with: .color(Color(red: 1, green: 0.55, blue: 0.15).opacity(0.7 * (1 - age / 0.18))))
            }
        }
    }

    /// A soft round puff: solid in the middle, fading to nothing at the edge.
    static func puff(_ ctx: GraphicsContext, in rect: CGRect, color: Color, opacity: Double) {
        guard opacity > 0.005, rect.width > 0 else { return }
        let g = Gradient(stops: [
            .init(color: color.opacity(opacity), location: 0),
            .init(color: color.opacity(opacity * 0.7), location: 0.5),
            .init(color: color.opacity(0), location: 1),
        ])
        let c = CGPoint(x: rect.midX, y: rect.midY)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(g, center: c, startRadius: 0, endRadius: rect.width / 2))
    }

    private func drawImpact(_ ctx: GraphicsContext, c: CGPoint, m: CGFloat, u: Double) {
        // Shock ring racing outwards.
        if u < 1.0 {
            let r = m * (0.04 + 0.5 * Self.easeOut(u / 1.0))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(.white.opacity(0.6 * (1 - u))), lineWidth: 3 * (1 - u) + 0.5)
        }
        // Billowing smoke that stays over the site. Fixed angles so each puff keeps its place frame to frame.
        let grow = Self.easeOut(u / 2.2)
        for k in 0..<28 {
            let a = Double(k) * 2.399 // golden angle
            let d = m * (0.01 + 0.11 * grow) * (0.25 + Double((k * 7) % 10) / 10)
            let r = m * (0.035 + 0.08 * grow) * (0.7 + Double((k * 3) % 5) / 8)
            let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d + u * 6)
            let o = 0.7 * Self.ease((u - 0.15) / 0.5)
            Self.puff(ctx, in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2),
                      color: Color(white: 0.1 + Double(k % 4) * 0.05), opacity: o)
        }
        // Fireball: bright core, orange body, fading as the smoke takes over.
        let fr = m * (0.03 + 0.13 * Self.easeOut(u / 0.55))
        let fo = 1 - Self.ease((u - 0.35) / 1.1)
        if fo > 0 {
            let g = Gradient(stops: [
                .init(color: Color(red: 1, green: 0.97, blue: 0.82).opacity(fo), location: 0),
                .init(color: Color(red: 1, green: 0.62, blue: 0.16).opacity(0.95 * fo), location: 0.35),
                .init(color: Color(red: 0.85, green: 0.2, blue: 0.05).opacity(0.7 * fo), location: 0.7),
                .init(color: .clear, location: 1),
            ])
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - fr, y: c.y - fr, width: fr * 2, height: fr * 2)),
                     with: .radialGradient(g, center: c, startRadius: 0, endRadius: fr))
        }
        // Sparks thrown outwards.
        if u < 1.1 {
            for k in 0..<22 {
                let a = Double(k) * 2.399 + 0.4
                let speed = m * (0.18 + Double((k * 5) % 7) / 18)
                let d = speed * Self.easeOut(u / 1.1)
                let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
                let r = 1.6 * (1 - u / 1.1) + 0.4
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(Color(red: 1, green: 0.8, blue: 0.45).opacity(1 - u / 1.1)))
            }
        }
    }
}

/// Shakes the view on impact. `amount` animates from 0 to 1; the shake dies away as it goes.
struct ImpactShake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard amount > 0, amount < 1 else { return ProjectionTransform() }
        let decay = 1 - amount
        let x = sin(amount * .pi * 14) * 9 * decay
        let y = cos(amount * .pi * 11) * 6 * decay
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}
