import Foundation
import Supabase

struct StaffCode: Decodable, Sendable {
    var code: String
    var expires_at: String
}

struct WorkerDesk: Decodable, Sendable {
    var name: String
    var homes: [WorkerPlace]
}

struct WorkerPlace: Decodable, Identifiable, Sendable {
    var id: String
    var name: String
    var line: String
    var area: String
    var manager: String
    var portrait: String
    var rooms: [WorkerCluster]
    var cars: [WorkerCluster]

    private enum CodingKeys: String, CodingKey {
        case id, name, line, area, manager, portrait, rooms, cars
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(String.self, forKey: .id)
        name = try box.decodeIfPresent(String.self, forKey: .name) ?? ""
        line = try box.decodeIfPresent(String.self, forKey: .line) ?? ""
        area = try box.decodeIfPresent(String.self, forKey: .area) ?? ""
        manager = try box.decodeIfPresent(String.self, forKey: .manager) ?? ""
        portrait = try box.decodeIfPresent(String.self, forKey: .portrait) ?? ""
        rooms = try box.decodeIfPresent([WorkerCluster].self, forKey: .rooms) ?? []
        cars = try box.decodeIfPresent([WorkerCluster].self, forKey: .cars) ?? []
    }
}

struct WorkerCluster: Decodable, Identifiable, Sendable {
    var id: String
    var title: String
    var tasks: [WorkerTask]
}

struct WorkerTask: Decodable, Identifiable, Sendable {
    var id: String
    var title: String
    var detail: String
    var photo: Bool
    var place: String
    var done: Bool
    var shot: String

    private enum CodingKeys: String, CodingKey {
        case id, title, detail, photo, place, done, shot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        photo = try container.decodeIfPresent(Bool.self, forKey: .photo) ?? false
        place = try container.decodeIfPresent(String.self, forKey: .place) ?? ""
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        shot = try container.decodeIfPresent(String.self, forKey: .shot) ?? ""
    }
}

enum StaffAccess {
    static func issue(phone: String) async throws -> StaffCode {
        try await TernedBackend.client.functions.invoke(
            "staff",
            options: FunctionInvokeOptions(body: ["action": "issue", "phone": phone])
        )
    }

    static func lookup(phone: String) async throws {
        let _: StaffLookup = try await TernedBackend.client.functions.invoke(
            "staff",
            options: FunctionInvokeOptions(body: ["action": "lookup", "phone": phone])
        )
    }

    static func signIn(phone: String, code: String) async throws {
        let tokens: Tokens = try await TernedBackend.client.functions.invoke(
            "staff",
            options: FunctionInvokeOptions(body: ["action": "signin", "phone": phone, "code": code])
        )
        try await TernedBackend.client.auth.setSession(accessToken: tokens.access_token, refreshToken: tokens.refresh_token)
    }

    static func home(day: String) async throws -> WorkerDesk {
        try await TernedBackend.client.functions.invoke(
            "staff",
            options: FunctionInvokeOptions(body: ["action": "home", "day": day])
        )
    }

    static func finish(home: String, day: String, title: String, place: String, photo: Data?) async throws {
        var body: [String: String] = [
            "action": "finish",
            "home": home,
            "day": day,
            "title": title,
            "place": place
        ]
        if let photo { body["photo"] = photo.base64EncodedString() }
        let _: StaffLookup = try await TernedBackend.client.functions.invoke(
            "staff",
            options: FunctionInvokeOptions(body: body)
        )
    }

    static func revert(home: String, day: String, title: String, place: String) async throws {
        let _: StaffLookup = try await TernedBackend.client.functions.invoke(
            "staff",
            options: FunctionInvokeOptions(body: [
                "action": "revert",
                "home": home,
                "day": day,
                "title": title,
                "place": place
            ])
        )
    }

    static func portrait(_ photo: Data) async throws -> String {
        struct Result: Decodable { var portrait: String }
        let result: Result = try await TernedBackend.client.functions.invoke(
            "staff",
            options: FunctionInvokeOptions(body: [
                "action": "portrait",
                "photo": photo.base64EncodedString()
            ])
        )
        return result.portrait
    }

    static func proof(_ path: String) async throws -> URL {
        let ticket: ProofTicket = try await TernedBackend.client.functions.invoke(
            "staff",
            options: FunctionInvokeOptions(body: ["action": "proof", "path": path])
        )
        guard let url = URL(string: ticket.url) else { throw URLError(.badURL) }
        return url
    }

    static func isStaff() async -> Bool {
        guard let user = try? await TernedBackend.client.auth.session.user else { return false }
        return user.appMetadata["staff"]?.boolValue == true
    }

    static func message(_ error: Error) -> String {
        if case let FunctionsError.httpError(_, data) = error,
           let body = try? JSONDecoder().decode([String: String].self, from: data),
           let text = body["error"] {
            return text
        }
        return "Something went wrong. Try again."
    }

    private struct StaffLookup: Decodable {
        var ok: Bool
    }

    private struct ProofTicket: Decodable {
        var url: String
    }

    private struct Tokens: Decodable {
        var access_token: String
        var refresh_token: String
    }
}
