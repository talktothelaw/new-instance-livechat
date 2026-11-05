import Foundation

struct RGB: Equatable {
    var r: Int
    var g: Int
    var b: Int

    init(r: Int, g: Int, b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }

    init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#"), let n = Int(hex.dropFirst(), radix: 16) else { return nil }
        self.init(r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255)
    }

    var hex: String {
        String(format: "#%02x%02x%02x", r, g, b)
    }

    static func mix(_ a: RGB, _ b: RGB, _ w: Double) -> RGB {
        func channel(_ x: Int, _ y: Int) -> Int { Int((Double(x) * w + Double(y) * (1 - w)).rounded()) }
        return RGB(r: channel(a.r, b.r), g: channel(a.g, b.g), b: channel(a.b, b.b))
    }
}

enum HeaderGradient {
    static func stops(_ base: RGB) -> (glow: RGB, deep: RGB) {
        let o = oklch(base)
        let neutral = o.c < 0.03
        let glowL = max(o.l, min(0.98, o.l + (neutral ? 0.8 : 1) * (0.08 + 0.16 * (1 - o.l))))
        let deepL = max(0, o.l - (neutral ? 0.3 : 1) * (0.05 + 0.18 * o.l))
        return (rgb(glowL, o.c * 1.12, o.h), rgb(deepL, o.c * 0.95, o.h))
    }

    static func stops(hex: String) -> (glow: String, deep: String) {
        guard let base = RGB(hex: hex) else { return (hex, hex) }
        let s = stops(base)
        return (s.glow.hex, s.deep.hex)
    }

    private static func lin(_ c: Int) -> Double {
        let v = Double(c) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func gam(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    private static func oklch(_ c: RGB) -> (l: Double, c: Double, h: Double) {
        let r = lin(c.r), g = lin(c.g), b = lin(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        return (L, hypot(A, B), atan2(B, A))
    }

    private static func linear(_ L: Double, _ C: Double, _ H: Double) -> [Double] {
        let A = C * cos(H), B = C * sin(H)
        func cube(_ x: Double) -> Double { x * x * x }
        let l = cube(L + 0.3963377774 * A + 0.2158037573 * B)
        let m = cube(L - 0.1055613458 * A - 0.0638541728 * B)
        let s = cube(L - 0.0894841775 * A - 1.291485548 * B)
        return [
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
        ]
    }

    private static func rgb(_ L: Double, _ C: Double, _ H: Double) -> RGB {
        var chroma = C
        var v = linear(L, chroma, H)
        var i = 0
        while i < 40, v.contains(where: { $0 < 0 || $0 > 1 }) {
            chroma *= 0.9
            v = linear(L, chroma, H)
            i += 1
        }
        let out = v.map { Int((gam(min(1, max(0, $0))) * 255).rounded()) }
        return RGB(r: out[0], g: out[1], b: out[2])
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit

extension Color {
    var rgbaChannels: (rgb: RGB, alpha: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return (RGB(r: byte(r), g: byte(g), b: byte(b)), Double(a))
    }

    init(_ rgb: RGB) {
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

extension ChatColors {
    static func mix(_ a: Color, _ b: Color, _ w: Double) -> Color {
        let x = a.rgbaChannels, y = b.rgbaChannels
        return Color(RGB.mix(x.rgb, y.rgb, w)).opacity(x.alpha * w + y.alpha * (1 - w))
    }

    var hairline: Color { Self.mix(inputBorder, background, 0.35) }
    var closeChip: Color { Self.mix(closeButton, headerBackground, 0.18) }
    var iconChip: Color { Self.mix(headerIcon, headerBackground, 0.18) }
    var logoTile: Color { Self.mix(headerPrimaryText, headerBackground, 0.2) }
    var agentAvatar: Color { Self.mix(headerBackground, background, 0.16) }
    var successTint: Color { Self.mix(successColor, background, 0.12) }
    var warnTint: Color { Self.mix(warningColor, background, 0.18) }
    var errorTint: Color { Self.mix(errorColor, background, 0.1) }

    var headerStops: (glow: Color, deep: Color) {
        let base = headerBackground.rgbaChannels
        guard base.alpha >= 1 else { return (headerBackground, headerBackground) }
        let s = HeaderGradient.stops(base.rgb)
        return (Color(s.glow), Color(s.deep))
    }
}
#endif
