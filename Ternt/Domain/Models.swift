import Foundation
import Tagged

enum Role: String, Codable, Hashable {
    case owner
    case worker
}

enum Gender: String, CaseIterable, Identifiable, Codable {
    case female
    case male

    var id: String { rawValue }
    var title: String { self == .female ? "Female" : "Male" }
    var symbol: String { self == .female ? "venus" : "mars" }
}

enum WorkerKind: String, CaseIterable, Identifiable, Codable {
    case driver = "Driver"
    case maid = "Maid"
    case nanny = "Nanny"
    case cook = "Cook"

    var id: String { rawValue }
}

enum Laundry: String, CaseIterable, Identifiable, Codable {
    case withBathroom = "With the bathroom"
    case wetArea = "Own wet area"
    case split = "Wet and dry"

    var id: String { rawValue }
}

enum SecondKitchen: String, CaseIterable, Identifiable, Codable {
    case full = "Full kitchen"
    case servant = "Servant’s kitchen"

    var id: String { rawValue }
}

struct Community: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var street: String
    var area: String
    var city: String
    var pincode: String
    var state: String

    var streetArea: String {
        [street, area].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var place: String {
        [street, area, city].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

typealias WorkerID = Tagged<HouseWorker, UUID>

struct HouseWorker: Identifiable, Codable, Hashable {
    let id: WorkerID
    var kind: WorkerKind?
    var first: String
    var last: String
    var dial: String
    var dialLength: Int
    var phone: String
    var salary: String
    var starts: Date?
    var ends: Date?

    var name: String { "\(first) \(last)".trimmingCharacters(in: .whitespaces) }

    static func make() -> HouseWorker {
        HouseWorker(
            id: WorkerID(UUID()),
            kind: nil,
            first: "",
            last: "",
            dial: "+91",
            dialLength: 10,
            phone: "",
            salary: "",
            starts: nil,
            ends: nil
        )
    }
}

struct PortalPerson: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var detail: String
    var phone: String
}

struct PortalTask: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var detail: String
    var review: Bool
}

struct PortalHome: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var line: String
    var area: String
    var community: String
    var city: String
    var rooms: [String]
    var people: [PortalPerson]
    var tasks: [PortalTask]
}

struct PortalState: Codable, Equatable {
    var activeHomeID: String
    var homes: [PortalHome]

    var active: PortalHome {
        homes.first { $0.id == activeHomeID } ?? homes[0]
    }

    static let sample = PortalState(
        activeHomeID: "h1",
        homes: [
            PortalHome(
                id: "h1",
                name: "Palm Court",
                line: "B-1204 · 12th floor",
                area: "Indiranagar",
                community: "Palm Court Residents",
                city: "Bengaluru",
                rooms: ["Kitchen", "Living room", "Bedroom", "Guest bathroom"],
                people: [
                    PortalPerson(id: "m1", name: "You", detail: "Owner", phone: ""),
                    PortalPerson(id: "w1", name: "Meera Iyer", detail: "Cook · 7:00 AM–1:00 PM", phone: "+91 9845011122"),
                    PortalPerson(id: "w2", name: "Rafi Khan", detail: "Driver · 2:00 PM–6:00 PM", phone: "+91 9845022233")
                ],
                tasks: [
                    PortalTask(id: "t1", title: "Kitchen reset", detail: "7:30 AM · Kitchen · Meera Iyer", review: false),
                    PortalTask(id: "t2", title: "School drop", detail: "2:30 PM · Outside · Rafi Khan", review: false),
                    PortalTask(id: "t3", title: "Guest bathroom", detail: "Finished. Fresh towels are folded.", review: true)
                ]
            ),
            PortalHome(
                id: "h2",
                name: "House 18",
                line: "Street 4",
                area: "Whitefield",
                community: "Palm Meadows",
                city: "Bengaluru",
                rooms: ["Kitchen", "Hall", "Garden sit-out"],
                people: [
                    PortalPerson(id: "m3", name: "You", detail: "Owner", phone: ""),
                    PortalPerson(id: "w3", name: "Lakshmi Rao", detail: "Maid · mornings", phone: "+91 9845033344")
                ],
                tasks: []
            )
        ]
    )
}

enum Prompt: Equatable, Hashable {
    case name
    case home
    case rooms
    case workers
    case pay
    case share
    case skill
    case area
    case workerShare

    var title: String {
        switch self {
        case .name: "What's your name?"
        case .home: "Where is the home?"
        case .rooms: "Which rooms are in it?"
        case .workers: "Who helps?"
        case .pay: "Salary and hours for each?"
        case .share: "Share this with the community?"
        case .skill: "What do you do?"
        case .area: "Where do you go?"
        case .workerShare: "Share your work with that community?"
        }
    }

    static func sequence(for role: Role) -> [Prompt] {
        switch role {
        case .owner: [.name, .home, .rooms, .workers, .pay, .share]
        case .worker: [.skill, .area, .workerShare]
        }
    }
}

enum TranscriptKind: Equatable {
    case welcome
    case reply
    case settled(Prompt)
    case active(Prompt)
}

enum SetupSheet: Identifiable, Equatable {
    case community
    case starts(WorkerID)
    case ends(WorkerID)
    case code(WorkerID)

    var id: String {
        switch self {
        case .community: "community"
        case .starts(let worker): "starts-\(worker.rawValue.uuidString)"
        case .ends(let worker): "ends-\(worker.rawValue.uuidString)"
        case .code(let worker): "code-\(worker.rawValue.uuidString)"
        }
    }
}

struct TranscriptRow: Identifiable, Equatable {
    let id: UUID
    var kind: TranscriptKind
    var date: Date

    init(kind: TranscriptKind, date: Date = Date()) {
        id = UUID()
        self.kind = kind
        self.date = date
    }
}
