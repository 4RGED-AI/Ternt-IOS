import Foundation
import Supabase

struct CommunityPost: Codable, Identifiable, Hashable {
    var id: Int
    var authorId: UUID
    var authorName: String
    var kind: String
    var details: String
    var createdAt: Date
    var closedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, details
        case authorId = "author_id"
        case authorName = "author_name"
        case createdAt = "created_at"
        case closedAt = "closed_at"
    }
}

struct CommunityPerson: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: String
    var detail: String
}

enum CommunityPeople {
    private struct Row: Encodable {
        var id: String
        var communityKey: String
        var communityName: String
        var homeId: String
        var name: String
        var kind: String
        var detail: String

        enum CodingKeys: String, CodingKey {
            case id, name, kind, detail
            case communityKey = "community_key"
            case communityName = "community_name"
            case homeId = "home_id"
        }
    }

    /// Replaces this home's public helpers so the community list matches People.
    static func publish(_ home: PortalHome) async {
        let key = home.communityKey.isEmpty ? PortalHome.key(community: home.community, city: home.city) : home.communityKey
        guard !key.isEmpty else { return }
        _ = try? await TernedBackend.client.from("community_people").delete().eq("home_id", value: home.id).execute()
        let rows = home.workers.map { person in
            Row(
                id: person.id,
                communityKey: key,
                communityName: home.community,
                homeId: home.id,
                name: person.name,
                kind: person.kind?.rawValue ?? "",
                detail: person.detail
            )
        }
        guard !rows.isEmpty else { return }
        _ = try? await TernedBackend.client.from("community_people").upsert(rows).execute()
    }

    static func list(in key: String) async -> [CommunityPerson] {
        guard !key.isEmpty else { return [] }
        let rows: [CommunityPerson]? = try? await TernedBackend.client
            .from("community_people")
            .select("id,name,kind,detail")
            .eq("community_key", value: key)
            .order("name")
            .limit(200)
            .execute()
            .value
        return rows ?? []
    }
}

enum CommunityBoard {
    private struct NewPost: Encodable {
        var communityKey: String
        var communityName: String
        var authorName: String
        var kind: String
        var details: String

        enum CodingKeys: String, CodingKey {
            case kind, details
            case communityKey = "community_key"
            case communityName = "community_name"
            case authorName = "author_name"
        }
    }

    private struct Close: Encodable {
        var closedAt: Date

        enum CodingKeys: String, CodingKey {
            case closedAt = "closed_at"
        }
    }

    static func me() async -> UUID? {
        try? await TernedBackend.client.auth.session.user.id
    }

    static func posts(in key: String) async throws -> [CommunityPost] {
        try await TernedBackend.client
            .from("community_posts")
            .select("id,author_id,author_name,kind,details,created_at,closed_at")
            .eq("community_key", value: key)
            .is("closed_at", value: nil)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    static func post(_ details: String, kind: WorkerKind?, home: PortalHome, author: String, state: PortalState) async throws {
        guard await HouseholdCloud.shared.push(state) else { throw URLError(.notConnectedToInternet) }
        let row = NewPost(
            communityKey: home.communityKey.isEmpty ? PortalHome.key(community: home.community, city: home.city) : home.communityKey,
            communityName: home.community,
            authorName: author,
            kind: kind?.rawValue ?? "",
            details: details
        )
        try await TernedBackend.client
            .from("community_posts")
            .insert(row)
            .execute()
    }

    static func close(_ post: CommunityPost) async throws {
        try await TernedBackend.client
            .from("community_posts")
            .update(Close(closedAt: .now))
            .eq("id", value: post.id)
            .execute()
    }

    static func revise(_ post: CommunityPost, details: String, kind: String) async throws {
        try await TernedBackend.client
            .from("community_posts")
            .update(Revision(details: details, kind: kind))
            .eq("id", value: post.id)
            .execute()
    }

    private struct Revision: Encodable {
        var details: String
        var kind: String
    }
}
