import Foundation
import Supabase

actor HouseholdCloud {
    static let shared = HouseholdCloud()

    private struct Row: Codable {
        var userId: UUID
        var activeHomeId: String
        var homes: [PortalHome]

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case activeHomeId = "active_home_id"
            case homes
        }
    }

    static let pendingKey = "householdPending"

    func push(_ state: PortalState) async -> Bool {
        guard !state.homes.isEmpty else { return true }
        UserDefaults.standard.set(true, forKey: Self.pendingKey)
        guard let user = try? await TernedBackend.client.auth.session.user else { return false }
        let row = Row(userId: user.id, activeHomeId: state.activeHomeID, homes: state.homes)
        do {
            try await TernedBackend.client
                .from("households")
                .upsert(row, onConflict: "user_id")
                .execute()
            UserDefaults.standard.removeObject(forKey: Self.pendingKey)
            return true
        } catch {
            return false
        }
    }

    /// True when the phone holds changes that never reached the account.
    nonisolated static var pending: Bool {
        UserDefaults.standard.bool(forKey: pendingKey)
    }

    /// Returns nil when the account has no saved home; throws when the server can't be reached.
    func pull() async throws -> PortalState? {
        let user = try await TernedBackend.client.auth.session.user
        let rows: [Row] = try await TernedBackend.client
            .from("households")
            .select("user_id,active_home_id,homes")
            .eq("user_id", value: user.id)
            .execute()
            .value
        guard let row = rows.first, !row.homes.isEmpty else { return nil }
        return PortalState(activeHomeID: row.activeHomeId, homes: row.homes)
    }
}
