import Foundation

/// Smooth, deterministic variation for demo power readings.
///
/// The app advances `tick` about every two seconds. A reading mixes a slow
/// and a faster sine wave, so sparklines move without looking periodic,
/// and never strays more than `amplitude` (a fraction) from its base value.
struct DemoWave {
    let tick: Int

    /// A multiplier within `1 ± amplitude`. Different `phase` values keep
    /// separate readings out of step with each other.
    func factor(amplitude: Double, phase: Double) -> Double {
        let t = Double(tick)
        let slow = sin(t * 2 * Double.pi / 37 + phase)
        let fast = sin(t * 2 * Double.pi / 11 + phase * 1.7)
        return 1 + amplitude * (0.7 * slow + 0.3 * fast)
    }

    /// `base` varied by `factor(amplitude:phase:)`.
    func value(_ base: Double, amplitude: Double, phase: Double) -> Double {
        base * factor(amplitude: amplitude, phase: phase)
    }
}
