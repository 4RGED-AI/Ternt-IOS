import Dependencies
import Foundation
import GRDB

final class HouseholdStore {
    private let queue: DatabaseQueue

    init(queue: DatabaseQueue) {
        self.queue = queue
    }

    static func live() -> HouseholdStore {
        let folder = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = folder.appendingPathComponent("ternt.sqlite")
        let queue = try! DatabaseQueue(path: url.path)
        try! queue.write { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS household (
              id TEXT PRIMARY KEY NOT NULL,
              payload TEXT NOT NULL
            )
            """)
        }
        return HouseholdStore(queue: queue)
    }

    func load() throws -> PortalState? {
        try queue.read { db in
            guard let payload = try String.fetchOne(
                db,
                sql: "SELECT payload FROM household WHERE id = 'current'"
            ) else { return nil }
            return try JSONDecoder().decode(PortalState.self, from: Data(payload.utf8))
        }
    }

    func save(_ state: PortalState) throws {
        let payload = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO household (id, payload) VALUES ('current', ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
                """,
                arguments: [payload]
            )
        }
    }
}

private enum HouseholdStoreKey: DependencyKey {
    static let liveValue = HouseholdStore.live()
}

extension DependencyValues {
    var householdStore: HouseholdStore {
        get { self[HouseholdStoreKey.self] }
        set { self[HouseholdStoreKey.self] = newValue }
    }
}
