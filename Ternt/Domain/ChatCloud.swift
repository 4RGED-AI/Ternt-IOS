import Foundation
import Supabase

struct SavedLine: Codable, Hashable {
    var text: String
    var mine: Bool
}

struct SavedChat: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: String
    var title: String
    var lines: [SavedLine]
}

enum ChatCloud {
    private struct Row: Encodable {
        var id: UUID
        var userId: UUID
        var kind: String
        var title: String
        var lines: [SavedLine]

        enum CodingKeys: String, CodingKey {
            case id, kind, title, lines
            case userId = "user_id"
        }
    }

    static func save(id: UUID, kind: String, lines: [SavedLine]) async {
        guard let first = lines.first(where: \.mine) ?? lines.first else { return }
        guard let user = try? await TernedBackend.client.auth.session.user else { return }
        let row = Row(id: id, userId: user.id, kind: kind, title: String(first.text.prefix(200)), lines: lines)
        _ = try? await TernedBackend.client
            .from("chats")
            .upsert(row, onConflict: "id")
            .execute()
    }

    static func list(kind: String) async -> [SavedChat] {
        guard (try? await TernedBackend.client.auth.session) != nil else { return [] }
        let rows: [SavedChat]? = try? await TernedBackend.client
            .from("chats")
            .select("id,kind,title,lines")
            .eq("kind", value: kind)
            .order("updated_at", ascending: false)
            .limit(50)
            .execute()
            .value
        return rows ?? []
    }
}
