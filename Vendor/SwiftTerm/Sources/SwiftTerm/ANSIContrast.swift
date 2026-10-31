import Foundation

/// Farport: improve basic ANSI text contrast without changing its background or buffer attributes.
enum ANSIContrast {
    static func luminance(_ color: SIMD3<Double>) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return linear(color.x) * 0.2126 + linear(color.y) * 0.7152 + linear(color.z) * 0.0722
    }

    static func ratio(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func resolve(_ foreground: SIMD3<Double>, on background: SIMD3<Double>) -> SIMD3<Double> {
        // Preserve intentionally identical foreground/background (hidden text).
        guard foreground != background, ratio(foreground, background) < 4.5 else { return foreground }
        var best = foreground
        var smallestChange = Double.infinity
        for endpoint in [SIMD3<Double>(repeating: 0), SIMD3<Double>(repeating: 1)] {
            guard ratio(endpoint, background) >= 4.5 else { continue }
            var low = 0.0, high = 1.0
            for _ in 0..<24 {
                let fraction = (low + high) / 2
                let candidate = foreground + (endpoint - foreground) * fraction
                if ratio(candidate, background) >= 4.5 { high = fraction } else { low = fraction }
            }
            let candidate = foreground + (endpoint - foreground) * high
            let difference = candidate - foreground
            let distance = difference.x * difference.x + difference.y * difference.y + difference.z * difference.z
            if distance < smallestChange { best = candidate; smallestChange = distance }
        }
        return best
    }
}
