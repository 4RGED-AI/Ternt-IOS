import Foundation
import Tagged

enum RoomNames {
    private static let extras = ["Dining", "Pooja", "Study", "Balcony", "Terrace", "Garden", "Store", "Parking", "Staff room"]

    static func rows(from lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.flatMap(expand).filter { seen.insert($0.lowercased()).inserted }
    }

    static func expand(_ line: String) -> [String] {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let count = count(in: line, unit: "bedroom") {
            return numbered("Bedroom", count)
        }
        if let count = count(in: line, unit: "living") {
            return numbered("Living room", count)
        }
        if line.compare("1 kitchen", options: .caseInsensitive) == .orderedSame {
            return ["Kitchen"]
        }
        if let (count, detail) = kitchens(in: line) {
            let extra = max(count - 1, 0)
            if extra <= 0 { return ["Kitchen"] }
            if extra == 1 { return ["Kitchen", detail] }
            return ["Kitchen"] + numbered(detail, extra)
        }
        if let count = count(in: line, unit: "separate bathroom") {
            return numbered("Bathroom", count)
        }
        if let count = count(in: line, unit: "bathroom") {
            return numbered("Bathroom", count)
        }
        if line.compare("powder room", options: .caseInsensitive) == .orderedSame {
            return ["Powder room"]
        }
        if let count = count(in: line, unit: "powder room") {
            return numbered("Powder room", count)
        }
        if line.lowercased().hasPrefix("laundry ·") {
            return ["Laundry"]
        }
        for name in extras {
            if let count = count(in: line, unit: name) {
                return numbered(name, count)
            }
        }
        return line.isEmpty ? [] : [line]
    }

    private static func numbered(_ name: String, _ count: Int) -> [String] {
        guard count > 1 else { return count == 1 ? [name] : [] }
        return (1...count).map { "\(name) \($0)" }
    }

    private static func count(in line: String, unit: String) -> Int? {
        let lower = line.lowercased()
        let unit = unit.lowercased()
        guard let space = lower.firstIndex(of: " ") else { return nil }
        guard let number = Int(lower[..<space]), number > 0 else { return nil }
        let rest = String(lower[lower.index(after: space)...])
        for head in [unit, unit + "s"] {
            if rest == head || rest.hasPrefix(head + " ") || rest.hasPrefix(head + " ·") {
                return number
            }
        }
        return nil
    }

    private static func kitchens(in line: String) -> (Int, String)? {
        let lower = line.lowercased()
        guard let space = lower.firstIndex(of: " ") else { return nil }
        guard let number = Int(lower[..<space]), number > 1 else { return nil }
        guard let marker = line.range(of: "kitchens · ", options: .caseInsensitive) else { return nil }
        let detail = String(line[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return nil }
        return (number, detail)
    }
}

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
    case housekeeper = "Housekeeper"
    case cook = "Cook"
    case nanny = "Nanny"

    var id: String { rawValue }
    var atHome: Bool { self != .driver }
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
    case dry = "Dry kitchen"

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
    var latitude: Double?
    var longitude: Double?

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

struct OwnerIdentity: Codable, Equatable {
    var first: String
    var last: String
    var gender: Gender?

    var name: String {
        "\(first) \(last)".trimmingCharacters(in: .whitespaces)
    }
}

struct PortalPerson: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var detail: String
    var phone: String
    var salary: String = ""
    /// Yearly incentive. Zero is a real amount; an empty value is not.
    var incentive: String = "0"
    /// Calendar weekdays the worker is on. 1 is Sunday through 7 is Saturday.
    var days: [Int] = []
    /// Public portrait set by the manager, or by the worker when the manager has not set one.
    var portrait: String = ""

    var kind: WorkerKind? {
        let head = detail.split(separator: "·").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return WorkerKind(rawValue: head)
    }

    var dayPart: DayPart? {
        DayPart.parse(detail)
    }

    var hours: String {
        detail.split(separator: "·").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " · ")
    }

    var dayLabel: String {
        let names = ["", "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        return [2, 3, 4, 5, 6, 7, 1].filter { days.contains($0) }.map { names[$0] }.joined(separator: " ")
    }

    /// Drivers only take car tasks; everyone else only takes room tasks.
    func takes(_ task: PortalTask) -> Bool {
        kind == .driver ? !task.car.isEmpty : task.car.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, detail, phone, salary, incentive, days, portrait
    }

    init(id: String, name: String, detail: String, phone: String, salary: String = "", incentive: String = "0", days: [Int] = [], portrait: String = "") {
        self.id = id
        self.name = name
        self.detail = detail
        self.phone = phone
        self.salary = salary
        self.incentive = incentive
        self.days = days
        self.portrait = portrait
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(String.self, forKey: .id)
        name = try box.decode(String.self, forKey: .name)
        detail = try box.decodeIfPresent(String.self, forKey: .detail) ?? ""
        phone = try box.decodeIfPresent(String.self, forKey: .phone) ?? ""
        salary = try box.decodeIfPresent(String.self, forKey: .salary) ?? ""
        incentive = try box.decodeIfPresent(String.self, forKey: .incentive) ?? "0"
        days = try box.decodeIfPresent([Int].self, forKey: .days) ?? []
        portrait = try box.decodeIfPresent(String.self, forKey: .portrait) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(name, forKey: .name)
        try box.encode(detail, forKey: .detail)
        try box.encode(phone, forKey: .phone)
        try box.encode(salary, forKey: .salary)
        try box.encode(incentive, forKey: .incentive)
        try box.encode(days, forKey: .days)
        try box.encode(portrait, forKey: .portrait)
    }
}

enum DayPart: String, CaseIterable, Identifiable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"

    var id: String { rawValue }

    static func parse(_ detail: String) -> DayPart? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})\s*(AM|PM)"#) else { return nil }
        let range = NSRange(detail.startIndex..., in: detail)
        guard let match = regex.firstMatch(in: detail, range: range),
              let hourRange = Range(match.range(at: 1), in: detail),
              let markRange = Range(match.range(at: 3), in: detail),
              var hour = Int(detail[hourRange]) else { return nil }
        if String(detail[markRange]) == "PM", hour < 12 { hour += 12 }
        if String(detail[markRange]) == "AM", hour == 12 { hour = 0 }
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        default: return .evening
        }
    }
}

struct PortalTask: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var detail: String
    var review: Bool
    var room: String
    var worker: String

    private enum CodingKeys: String, CodingKey {
        case id, title, detail, review, room, worker, car, member, memberSide, note, kind, photo
    }

    var car: String
    var member: String
    var memberSide: String
    var note: String
    /// Category this task belongs to. The home keeps the task; workers of this category get copies.
    var kind: String
    /// The worker has to attach a photo before this can count as done.
    var photo: Bool

    init(id: String, title: String, detail: String = "", review: Bool, room: String = "", worker: String = "", car: String = "", member: String = "", memberSide: String = "", note: String = "", kind: String = "", photo: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.review = review
        self.room = room
        self.worker = worker
        self.car = car
        self.member = member
        self.memberSide = memberSide
        self.note = note
        self.kind = kind
        self.photo = photo
    }

    var place: String {
        if !room.isEmpty { return room }
        guard detail.range(of: #"\d"#, options: .regularExpression) == nil else { return "" }
        return detail
    }

    static func granular(for person: PortalPerson) -> [PortalTask] {
        let kind = person.detail.split(separator: "·").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let items: [(String, String)]
        switch kind {
        case "Cook":
            items = [("Wipe the counters", "Kitchen"), ("Wash the vessels", "Kitchen"), ("Sweep the floor", "Kitchen")]
        case "Maid":
            items = [("Make the beds", "Bedroom"), ("Fold the laundry", "Bedroom"), ("Dust", "Living room")]
        case "Driver":
            items = [("School drop", ""), ("Market run", "")]
        case "Nanny":
            items = [("Breakfast", "Kitchen"), ("School bag", "Bedroom"), ("Play", "Living room")]
        default:
            items = [("Straighten up", ""), ("Wipe down", "")]
        }
        return items.enumerated().map { index, item in
            PortalTask(id: "\(person.id)-\(index)", title: item.0, review: false, room: item.1, worker: person.name)
        }
    }

    static func seeded(forRoom room: String, category: String = "", workers: [PortalPerson]) -> [PortalTask] {
        let key = (category.isEmpty ? RoomCategory.infer(room) : category).lowercased()
        let guest = room.lowercased().contains("guest") || key.contains("guest")
        let pairs: [(String, WorkerKind)]
        if key == "kitchen" || key.hasPrefix("kitchen ") || key.contains("kitchen") {
            pairs = [("Wipe the counters", .cook), ("Wash the vessels", .cook), ("Sweep the floor", .cook)]
        } else if key == "living room" || key.hasPrefix("living room") {
            pairs = [("Dust", .maid), ("Vacuum the rug", .maid)]
        } else if key == "bedroom" || key.hasPrefix("bedroom ") {
            pairs = [("Make the beds", .maid), ("Fold the laundry", .maid)]
        } else if key.contains("bathroom") || key.contains("bath") {
            let scrub = guest ? "Scrub the guest bathroom" : "Scrub the bathroom"
            pairs = [(scrub, .maid), ("Restock the towels", .maid)]
        } else if key == "hall" || key.hasPrefix("hall ") {
            pairs = [("Sweep the hall", .maid), ("Mop the hall", .maid)]
        } else if key.contains("garden") {
            pairs = [("Water the plants", .maid), ("Wipe the chairs", .maid)]
        } else if key == "laundry" || key.hasPrefix("laundry ") {
            pairs = [("Run the wash", .maid), ("Fold the laundry", .maid)]
        } else if key.contains("powder") {
            pairs = [("Wipe the powder room", .maid), ("Restock the towels", .maid)]
        } else {
            pairs = [("Straighten up", .maid), ("Wipe down", .maid)]
        }
        return pairs.map { title, kind in
            let worker = workers.first { $0.kind == kind }?.name
                ?? workers.first { $0.kind?.atHome == true }?.name
                ?? ""
            return PortalTask(id: UUID().uuidString, title: title, review: false, room: room, worker: worker)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        review = try container.decodeIfPresent(Bool.self, forKey: .review) ?? false
        room = try container.decodeIfPresent(String.self, forKey: .room) ?? ""
        worker = try container.decodeIfPresent(String.self, forKey: .worker) ?? ""
        car = try container.decodeIfPresent(String.self, forKey: .car) ?? ""
        member = try container.decodeIfPresent(String.self, forKey: .member) ?? ""
        memberSide = try container.decodeIfPresent(String.self, forKey: .memberSide) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        photo = try container.decodeIfPresent(Bool.self, forKey: .photo) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encode(review, forKey: .review)
        try container.encode(room, forKey: .room)
        try container.encode(worker, forKey: .worker)
        try container.encode(car, forKey: .car)
        try container.encode(member, forKey: .member)
        try container.encode(memberSide, forKey: .memberSide)
        try container.encode(note, forKey: .note)
        try container.encode(kind, forKey: .kind)
        try container.encode(photo, forKey: .photo)
    }
}

enum RoomCategory: String, CaseIterable, Identifiable, Codable {
    case bedroom = "Bedroom"
    case living = "Living room"
    case kitchen = "Kitchen"
    case bathroom = "Bathroom"
    case powder = "Powder room"
    case laundry = "Laundry"
    case dining = "Dining"
    case pooja = "Pooja"
    case study = "Study"
    case balcony = "Balcony"
    case terrace = "Terrace"
    case garden = "Garden"
    case hall = "Hall"
    case store = "Store"
    case parking = "Parking"
    case staff = "Staff room"

    var id: String { rawValue }

    static func infer(_ name: String) -> String {
        let key = name.lowercased()
        if key.contains("bedroom") { return Self.bedroom.rawValue }
        if key.contains("living") { return Self.living.rawValue }
        if key.contains("kitchen") { return Self.kitchen.rawValue }
        if key.contains("powder") { return Self.powder.rawValue }
        if key.contains("bathroom") || key.contains("bath") { return Self.bathroom.rawValue }
        if key.contains("laundry") { return Self.laundry.rawValue }
        if key.contains("dining") { return Self.dining.rawValue }
        if key.contains("pooja") { return Self.pooja.rawValue }
        if key.contains("study") { return Self.study.rawValue }
        if key.contains("balcony") { return Self.balcony.rawValue }
        if key.contains("terrace") { return Self.terrace.rawValue }
        if key.contains("garden") { return Self.garden.rawValue }
        if key.contains("hall") { return Self.hall.rawValue }
        if key.contains("store") { return Self.store.rawValue }
        if key.contains("parking") { return Self.parking.rawValue }
        if key.contains("staff") { return Self.staff.rawValue }
        return ""
    }
}

struct PortalRoom: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var category: String
    var people: [String]

    init(id: String, name: String, category: String, people: [String] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.people = people
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, people
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? RoomCategory.infer(name)
        people = try container.decodeIfPresent([String].self, forKey: .people) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(people, forKey: .people)
    }
}

struct PortalCar: Identifiable, Hashable, Codable {
    var id: String
    var model: String
    var plate: String
    var driver: String

    init(id: String, model: String, plate: String, driver: String = "") {
        self.id = id
        self.model = model
        self.plate = plate
        self.driver = driver
    }

    private enum CodingKeys: String, CodingKey {
        case id, model, plate, driver
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        plate = try container.decodeIfPresent(String.self, forKey: .plate) ?? ""
        driver = try container.decodeIfPresent(String.self, forKey: .driver) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(model, forKey: .model)
        try container.encode(plate, forKey: .plate)
        try container.encode(driver, forKey: .driver)
    }
}

enum HouseholdRelation: String, CaseIterable, Identifiable, Codable {
    case grandfather = "Grandfather"
    case grandmother = "Grandmother"
    case father = "Father"
    case mother = "Mother"
    case husband = "Husband"
    case wife = "Wife"
    case son = "Son"
    case daughter = "Daughter"
    case brother = "Brother"
    case sister = "Sister"
    case uncle = "Uncle"
    case aunt = "Aunt"

    var id: String { rawValue }
}

struct PortalMember: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var relation: String
    var born: Date?

    init(id: String, name: String, relation: String = "", born: Date? = nil) {
        self.id = id
        self.name = name
        self.relation = relation
        self.born = born
    }

    var ageLabel: String {
        guard let born else { return "" }
        let years = Calendar.current.dateComponents([.year], from: born, to: Date()).year ?? 0
        guard years > 0 else { return "Under 1" }
        return years == 1 ? "1 year" : "\(years) years"
    }

    var line: String {
        [relation, ageLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, relation, born
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        relation = try container.decodeIfPresent(String.self, forKey: .relation) ?? ""
        born = try container.decodeIfPresent(Date.self, forKey: .born)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(relation, forKey: .relation)
        try container.encodeIfPresent(born, forKey: .born)
    }
}

struct UpcomingPeriod: Identifiable {
    var id: String
    var name: String
    var period: String
    var tasks: [PortalTask]
}

struct PortalHome: Identifiable, Hashable {
    var id: String
    var name: String
    var line: String
    /// Floor chosen in setup. Zero means this home was saved before floors were separate.
    var floor: Int = 0
    var area: String
    var community: String
    var city: String
    var rooms: [PortalRoom]
    var cars: [PortalCar] = []
    var members: [PortalMember] = []
    var people: [PortalPerson]
    var tasks: [PortalTask]
    var communityKey = ""
    var roomCategories: [String] = []
    /// Once true, opening the home does not hand workers another copy of tasks they already received.
    var copiesAligned = false
    /// Tasks a worker finished, kept by day so the home can show that date later.
    var finished: [TaskFinish] = []
    /// What this house keeps on hand, and what it needs to buy back to that level.
    var groceries: [GroceryItem] = []

    static func key(community: String, city: String) -> String {
        let name = community.trimmingCharacters(in: .whitespaces).lowercased()
        let town = city.trimmingCharacters(in: .whitespaces).lowercased()
        return "n:\(name)|\(town)"
    }

    var workers: [PortalPerson] {
        people.filter { person in
            person.id != "you"
                && person.name != "You"
                && person.detail != "Owner"
                && person.detail != "Manager"
                && Gender.allCases.allSatisfy { $0.title != person.detail }
        }
    }

    var upcoming: [UpcomingPeriod] {
        workers.map { person in
            UpcomingPeriod(
                id: person.id,
                name: person.name,
                period: person.kind?.rawValue ?? "",
                tasks: granularTasks(for: person)
            )
        }
    }

    func granularTasks(for person: PortalPerson) -> [PortalTask] {
        tasks.filter { !$0.review && $0.worker == person.name && $0.memberSide != "by" }
    }

    /// People added to the room, plus workers who already have a task there.
    func people(in room: PortalRoom) -> [PortalPerson] {
        var seen = Set<String>()
        var list: [PortalPerson] = []
        func add(_ person: PortalPerson) {
            guard seen.insert(person.id).inserted else { return }
            list.append(person)
        }
        for id in room.people {
            if let worker = workers.first(where: { $0.id == id }) {
                add(worker)
            } else if let member = members.first(where: { $0.id == id }) {
                add(PortalPerson(id: member.id, name: member.name, detail: member.relation, phone: ""))
            }
        }
        let names = Set(tasks.filter {
            $0.room.caseInsensitiveCompare(room.name) == .orderedSame
                && $0.car.isEmpty
                && !$0.worker.isEmpty
                && !$0.review
                && $0.memberSide != "by"
        }.map { $0.worker.lowercased() })
        for worker in workers where names.contains(worker.name.lowercased()) {
            add(worker)
        }
        return list
    }

    func workers(on task: PortalTask, room: String) -> [PortalPerson] {
        let names = Set(tasks.filter {
            $0.room.caseInsensitiveCompare(room) == .orderedSame
                && $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                && $0.car == task.car
                && !$0.worker.isEmpty
                && !$0.review
        }.map { $0.worker.lowercased() })
        return workers.filter { names.contains($0.name.lowercased()) }
    }

    func roomTasks(_ room: String) -> [PortalTask] {
        var seen = Set<String>()
        var result: [PortalTask] = []
        func add(_ task: PortalTask) {
            guard seen.insert(task.title + "|" + task.worker).inserted else { return }
            result.append(task)
        }
        for task in tasks where task.room == room && task.car.isEmpty && task.worker.isEmpty && task.memberSide != "by" && !task.review {
            add(task)
        }
        return result
    }

    func carTasks(_ carID: String) -> [PortalTask] {
        var seen = Set<String>()
        var result: [PortalTask] = []
        func add(_ task: PortalTask) {
            guard seen.insert(task.title + "|" + task.worker).inserted else { return }
            result.append(task)
        }
        for task in tasks where task.car == carID && task.worker.isEmpty && !task.review { add(task) }
        return result
    }
}

struct TaskFinish: Codable, Hashable, Identifiable {
    var id: String
    var day: String
    var worker: String
    var title: String
    var place: String
    var photo: String = ""
    var ok: Bool = false

    init(id: String, day: String, worker: String, title: String, place: String, photo: String = "", ok: Bool = false) {
        self.id = id
        self.day = day
        self.worker = worker
        self.title = title
        self.place = place
        self.photo = photo
        self.ok = ok
    }

    private enum CodingKeys: String, CodingKey {
        case id, day, worker, title, place, photo, ok
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        day = try container.decodeIfPresent(String.self, forKey: .day) ?? ""
        worker = try container.decodeIfPresent(String.self, forKey: .worker) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        place = try container.decodeIfPresent(String.self, forKey: .place) ?? ""
        photo = try container.decodeIfPresent(String.self, forKey: .photo) ?? ""
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
    }
}

enum DayKey {
    static var today: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.startOfDay(for: .now))
    }
}

enum GroceryAisle: String, Codable, CaseIterable, Identifiable {
    case staples, dairy, produce, household, personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .staples: "Staples"
        case .dairy: "Dairy"
        case .produce: "Produce"
        case .household: "Household"
        case .personal: "Personal"
        }
    }
}

enum GroceryLevel {
    case stocked, low, out

    var title: String {
        switch self {
        case .stocked: "In stock"
        case .low: "Low"
        case .out: "Out"
        }
    }
}

struct GroceryItem: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var aisle: GroceryAisle
    var par: Int
    var onHand: Int
    var unit: String

    var level: GroceryLevel {
        if onHand <= 0 { return .out }
        if onHand < par { return .low }
        return .stocked
    }

    var shortfall: Int { max(0, par - max(0, onHand)) }

    static let usual: [GroceryItem] = [
        GroceryItem(id: "atta", name: "Atta", aisle: .staples, par: 1, onHand: 1, unit: "5 kg"),
        GroceryItem(id: "rice", name: "Rice", aisle: .staples, par: 1, onHand: 1, unit: "5 kg"),
        GroceryItem(id: "dal", name: "Toor dal", aisle: .staples, par: 2, onHand: 1, unit: "kg"),
        GroceryItem(id: "oil", name: "Sunflower oil", aisle: .staples, par: 1, onHand: 0, unit: "L"),
        GroceryItem(id: "salt", name: "Salt", aisle: .staples, par: 1, onHand: 1, unit: "pack"),
        GroceryItem(id: "sugar", name: "Sugar", aisle: .staples, par: 1, onHand: 1, unit: "kg"),
        GroceryItem(id: "milk", name: "Milk", aisle: .dairy, par: 2, onHand: 1, unit: "L"),
        GroceryItem(id: "curd", name: "Curd", aisle: .dairy, par: 1, onHand: 1, unit: "kg"),
        GroceryItem(id: "eggs", name: "Eggs", aisle: .dairy, par: 1, onHand: 0, unit: "dozen"),
        GroceryItem(id: "bread", name: "Bread", aisle: .dairy, par: 1, onHand: 1, unit: "loaf"),
        GroceryItem(id: "tomato", name: "Tomatoes", aisle: .produce, par: 1, onHand: 0, unit: "kg"),
        GroceryItem(id: "onion", name: "Onions", aisle: .produce, par: 2, onHand: 1, unit: "kg"),
        GroceryItem(id: "potato", name: "Potatoes", aisle: .produce, par: 2, onHand: 2, unit: "kg"),
        GroceryItem(id: "banana", name: "Bananas", aisle: .produce, par: 1, onHand: 1, unit: "dozen"),
        GroceryItem(id: "dish", name: "Dishwash liquid", aisle: .household, par: 1, onHand: 1, unit: "bottle"),
        GroceryItem(id: "detergent", name: "Detergent", aisle: .household, par: 1, onHand: 0, unit: "pack"),
        GroceryItem(id: "tissue", name: "Tissue", aisle: .household, par: 2, onHand: 1, unit: "pack"),
        GroceryItem(id: "soap", name: "Soap", aisle: .personal, par: 4, onHand: 2, unit: "bar"),
        GroceryItem(id: "paste", name: "Toothpaste", aisle: .personal, par: 1, onHand: 1, unit: "tube")
    ]
}

struct PortalState: Codable, Equatable {
    var activeHomeID: String
    var homes: [PortalHome]

    var active: PortalHome {
        if let home = homes.first(where: { $0.id == activeHomeID }) { return home }
        if let home = homes.first { return home }
        return PortalHome(id: "", name: "", line: "", area: "", community: "", city: "", rooms: [], people: [], tasks: [])
    }

    static let empty = PortalState(activeHomeID: "", homes: [])

    var ownerName: String {
        let name = homes.lazy.flatMap(\.people).first { $0.id == "you" }?.name
            .trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "You" : name
    }
}

extension PortalHome: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, line, floor, area, community, city, rooms, cars, members, people, tasks, communityKey, roomCategories, copiesAligned, finished, groceries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        line = try container.decode(String.self, forKey: .line)
        floor = try container.decodeIfPresent(Int.self, forKey: .floor) ?? 0
        area = try container.decode(String.self, forKey: .area)
        community = try container.decode(String.self, forKey: .community)
        city = try container.decode(String.self, forKey: .city)
        if let stored = try? container.decode([PortalRoom].self, forKey: .rooms) {
            rooms = stored
        } else {
            let names = try container.decode([String].self, forKey: .rooms)
            rooms = names.map { PortalRoom(id: UUID().uuidString, name: $0, category: RoomCategory.infer($0)) }
        }
        cars = try container.decodeIfPresent([PortalCar].self, forKey: .cars) ?? []
        members = try container.decodeIfPresent([PortalMember].self, forKey: .members) ?? []
        people = try container.decode([PortalPerson].self, forKey: .people)
        tasks = try container.decode([PortalTask].self, forKey: .tasks)
        communityKey = try container.decodeIfPresent(String.self, forKey: .communityKey)
            ?? PortalHome.key(community: community, city: city)
        roomCategories = try container.decodeIfPresent([String].self, forKey: .roomCategories) ?? []
        copiesAligned = try container.decodeIfPresent(Bool.self, forKey: .copiesAligned) ?? false
        finished = try container.decodeIfPresent([TaskFinish].self, forKey: .finished) ?? []
        groceries = try container.decodeIfPresent([GroceryItem].self, forKey: .groceries) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(line, forKey: .line)
        try container.encode(floor, forKey: .floor)
        try container.encode(area, forKey: .area)
        try container.encode(community, forKey: .community)
        try container.encode(city, forKey: .city)
        try container.encode(rooms, forKey: .rooms)
        try container.encode(cars, forKey: .cars)
        try container.encode(members, forKey: .members)
        try container.encode(people, forKey: .people)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(communityKey.isEmpty ? PortalHome.key(community: community, city: city) : communityKey, forKey: .communityKey)
        try container.encode(roomCategories, forKey: .roomCategories)
        try container.encode(copiesAligned, forKey: .copiesAligned)
        try container.encode(finished, forKey: .finished)
        try container.encode(groceries, forKey: .groceries)
    }
}

enum Prompt: Equatable, Hashable {
    case name
    case home
    case rooms
    case workers
    case car
    case pay
    case done
    case tasks
    case more
    case share
    case skill
    case area
    case workerShare

    var title: String {
        switch self {
        case .name: "What's your name?"
        case .home: "Which property are we setting up today?"
        case .rooms: "Which rooms are in it?"
        case .workers: "Who helps at home?"
        case .car: "Which car?"
        case .pay: "Salary and hours?"
        case .done: "Initial setup is complete."
        case .tasks: "What do they do?"
        case .more: "Anyone else who helps?"
        case .share: "Share this with the community?"
        case .skill: "What do you do?"
        case .area: "Where do you go?"
        case .workerShare: "Share your work with that community?"
        }
    }

    static func sequence(for role: Role) -> [Prompt] {
        switch role {
        case .owner: [.name, .home, .rooms, .workers, .car, .tasks, .pay, .more]
        case .worker: [.skill, .area, .workerShare]
        }
    }
}

enum TranscriptKind: Equatable {
    case welcome
    case agent(String)
    case reply(String)
    case location(String, Double, Double)
    case settled(Prompt)
    case active(Prompt)
}

enum SetupSheet: Identifiable, Equatable {
    case community
    case pickCommunity
    case gender
    case starts(WorkerID)
    case ends(WorkerID)
    case code(WorkerID)
    case kind(WorkerID)

    var id: String {
        switch self {
        case .community: "community"
        case .pickCommunity: "pick-community"
        case .gender: "gender"
        case .starts(let worker): "starts-\(worker.rawValue.uuidString)"
        case .ends(let worker): "ends-\(worker.rawValue.uuidString)"
        case .code(let worker): "code-\(worker.rawValue.uuidString)"
        case .kind(let worker): "kind-\(worker.rawValue.uuidString)"
        }
    }
}

struct TranscriptRow: Identifiable, Equatable {
    let id: UUID
    var kind: TranscriptKind
    var date: Date

    init(kind: TranscriptKind, date: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.date = date
    }
}
