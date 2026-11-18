import Dependencies
import Foundation
import GRDB
import UIKit

enum ProfileImage {
    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("profile.jpg")
    }

    static func load() -> UIImage? {
        UIImage(contentsOfFile: file.path)
    }

    static func store(_ image: UIImage?) {
        if image == nil {
            try? FileManager.default.removeItem(at: file)
            return
        }
        guard let image else { return }
        let maxSide: CGFloat = 640
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 0 ? min(1, maxSide / longest) : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let data = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.86) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

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
