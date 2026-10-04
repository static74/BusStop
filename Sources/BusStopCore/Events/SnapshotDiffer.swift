import Foundation

/// Compares two snapshots and describes what changed.
public enum SnapshotDiffer {
    /// Events in a stable order: disconnections, connections, link changes,
    /// charger and display changes, new diagnostics.
    /// Returns no events when `old` is nil (first capture).
    public static func events(from old: HostSnapshot?, to new: HostSnapshot, at date: Date) -> [ConnectionEvent] {
        fatalError("not implemented")
    }
}
