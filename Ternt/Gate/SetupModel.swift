import Collections
import Contacts
import CoreLocation
import Dependencies
import Foundation
import IdentifiedCollections
import UIKit

enum HomeStep: Equatable {
    case find
    case door
}

enum RoomStep: Equatable {
    case layout
    case baths
    case balconies
    case kitchen
}

enum TaskCadence: String, Equatable {
    case daily = "Daily"
    case weekly = "Weekly"
    case fortnightly = "Fortnightly"
    case monthly = "Monthly"

    var next: TaskCadence {
        switch self {
        case .daily: .weekly
        case .weekly: .fortnightly
        case .fortnightly: .monthly
        case .monthly: .daily
        }
    }

    static func parsed(_ raw: String) -> TaskCadence {
        let value = raw.lowercased()
        if value.contains("month") { return .monthly }
        if value.contains("fort") || value.contains("bi") { return .fortnightly }
        if value.hasPrefix("w") { return .weekly }
        return .daily
    }
}

struct HouseTask: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var cadence: TaskCadence
    var on = true
    var worker: WorkerID?
    var room = ""
    var car = ""
}

enum PlaceTasks {
    struct Item {
        var title: String
        var cadence: TaskCadence
        var room: String
        var car: String
        var kind: WorkerKind
    }

    static func items(rooms: [(name: String, category: String)], cars: [PortalCar]) -> [Item] {
        var list: [Item] = []
        var groceries = false
        for room in rooms {
            list.append(contentsOf: forRoom(room.name, category: room.category, groceries: &groceries))
        }
        if !rooms.isEmpty {
            list.append(Item(title: "Clean the fans", cadence: .monthly, room: "", car: "", kind: .housekeeper))
        }
        for (index, car) in cars.enumerated() {
            list.append(contentsOf: forCar(car, trips: index == 0))
        }
        return list
    }

    static func forRoom(_ name: String, category: String) -> [Item] {
        var groceries = false
        return forRoom(name, category: category, groceries: &groceries)
    }

    static func forCar(_ car: PortalCar, trips: Bool) -> [Item] {
        var list = [
            Item(title: "Wipe the car", cadence: .daily, room: "", car: car.id, kind: .driver),
            Item(title: "Fuel and tyre air", cadence: .weekly, room: "", car: car.id, kind: .driver),
            Item(title: "Wash the car", cadence: .fortnightly, room: "", car: car.id, kind: .driver),
            Item(title: "Car service", cadence: .monthly, room: "", car: car.id, kind: .driver)
        ]
        if trips {
            list.append(Item(title: "School drop and pickup", cadence: .daily, room: "", car: car.id, kind: .driver))
            list.append(Item(title: "Office drop", cadence: .daily, room: "", car: car.id, kind: .driver))
            list.append(Item(title: "Market run", cadence: .weekly, room: "", car: car.id, kind: .driver))
        }
        return list
    }

    private static func forRoom(_ name: String, category: String, groceries: inout Bool) -> [Item] {
        let key = "\(category) \(name)".lowercased()
        func item(_ title: String, _ cadence: TaskCadence, _ kind: WorkerKind) -> Item {
            Item(title: title, cadence: cadence, room: name, car: "", kind: kind)
        }
        if key.contains("bedroom") {
            return [
                item("Make the bed", .daily, .maid),
                item("Dust", .weekly, .maid),
                item("Change the sheets", .weekly, .housekeeper)
            ]
        }
        if key.contains("powder") {
            return [item("Wipe the powder room", .daily, .maid)]
        }
        if key.contains("bathroom") || key.contains("bath") {
            return [
                item("Clean the bathroom", .daily, .maid),
                item("Scrub the bathroom", .weekly, .housekeeper)
            ]
        }
        if key.contains("living") || key.contains("hall") {
            return [
                item("Sweep and mop", .daily, .maid),
                item("Dust", .weekly, .maid)
            ]
        }
        if key.contains("kitchen") {
            if key.contains("dry") {
                return [item("Wipe the dry kitchen", .daily, .maid)]
            }
            var list = [
                item("Cook breakfast", .daily, .cook),
                item("Cook lunch", .daily, .cook),
                item("Cook dinner", .daily, .cook),
                item("Wash the vessels", .daily, .maid),
                item("Wipe the counters", .daily, .maid),
                item("Clear up after cooking", .daily, .cook),
                item("Clean the fridge", .weekly, .cook),
                item("Clean the chimney", .monthly, .cook)
            ]
            if !groceries {
                groceries = true
                list.append(item("List the groceries", .weekly, .cook))
            }
            return list
        }
        if key.contains("balcony") { return [item("Clean the balcony", .weekly, .housekeeper)] }
        if key.contains("terrace") { return [item("Sweep the terrace", .weekly, .housekeeper)] }
        if key.contains("garden") { return [item("Water the plants", .daily, .housekeeper)] }
        if key.contains("laundry") { return [item("Do the laundry", .daily, .housekeeper)] }
        return []
    }
}

private func ownedTasks(_ items: [PlaceTasks.Item], workers: some Sequence<HouseWorker>) -> [PortalTask] {
    items.flatMap { item in
        let people = workers.filter { $0.kind == item.kind }.map(\.name)
        return ([""] + people).map { name in
            PortalTask(
                id: UUID().uuidString,
                title: item.title,
                detail: item.cadence.rawValue,
                review: false,
                room: item.room,
                worker: name,
                car: item.car,
                kind: item.kind.rawValue
            )
        }
    }
}

enum HelperTasks {
    static func make(for kind: WorkerKind?, rooms: [String], car: String = "", taken: Set<String> = []) -> [HouseTask] {
        guard let kind else { return [] }
        let pairs = rooms.map { (name: $0, category: RoomCategory.infer($0)) }
        let cars = car.isEmpty ? [] : [PortalCar(id: car, model: "", plate: "")]
        return PlaceTasks.items(rooms: pairs, cars: cars)
            .filter { $0.kind == kind && !taken.contains($0.title.lowercased()) }
            .map { item in
                HouseTask(title: item.title, cadence: item.cadence, room: item.room, car: item.car)
            }
    }
}

@MainActor
@Observable
final class SetupModel {
    let role: Role
    let sequence: [Prompt]

    @ObservationIgnored
    @Dependency(\.continuousClock) var clock
    @ObservationIgnored
    @Dependency(\.householdStore) var store

    var rows: [TranscriptRow] = []
    var welcomeText = ""
    var welcomeDone = false
    var reply: String?
    var questionText = ""
    var thinking = false
    var formVisible = false
    var timeReveal: CGFloat = 0
    var active: Prompt?

    var firstName = ""
    var lastName = ""
    var gender: Gender?
    var photo: UIImage?
    var pickingPhoto = false {
        didSet {
            if !pickingPhoto { holdLayout = false }
            onPickerChange?(pickingPhoto || holdLayout)
        }
    }
    var holdLayout = false {
        didSet { onPickerChange?(pickingPhoto || holdLayout) }
    }
    @ObservationIgnored var onPickerChange: ((Bool) -> Void)?

    var communities: [Community] = []
    var community: Community?
    var here: MapPoint?
    var locating = false
    var locationRefused = false
    var askingCommunity = false
    var homeAsk: String?
    var homeStep: HomeStep = .find
    var passedSuggestion = false
    var asked = ""
    var composerInset: CGFloat = 88
    @ObservationIgnored weak var composerProbe: UIView?
    var unit = ""
    var floor = 1
    var draftName = ""
    var draftStreet = ""
    var draftArea = ""
    var draftPin = ""
    var draftCity = ""
    var draftState = ""

    var bedrooms = 1
    var living = 1
    var kitchens = 1
    var bathrooms = 1
    var balconies = 1
    var roomStep: RoomStep = .layout
    var houseTasks: [HouseTask] = []
    var attached: [Bool?] = [nil]
    var separateBaths = 0
    var powder = 0
    var secondKitchen: SecondKitchen?
    var laundry: Laundry?
    var moreRooms = false
    var extras = OrderedDictionary<String, Int>()
    let extraNames = ["Dining", "Pooja", "Study", "Balcony", "Terrace", "Garden", "Store", "Parking", "Staff room"]

    var workers: IdentifiedArrayOf<HouseWorker> = []
    var current: WorkerID?
    var carModel = ""
    var carPlate = ""
    var cars: [PortalCar] = []
    var driverCar: [WorkerID: String] = [:]
    var placeholder = ""
    var helpChoice: WorkerKind?
    var helpManual = false
    var layoutChosen = false
    var skill: WorkerKind?
    var workArea = ""
    var workCity: String?
    var share: Bool? = false

    let cities = ["Bengaluru", "Mumbai", "Delhi", "Hyderabad", "Chennai", "Pune", "Kolkata"]

    var sheet: SetupSheet?
    var onStructureChange: (() -> Void)?
    var onLayoutChange: (() -> Void)?
    var keepKeyboard: (() -> Void)?
    var dismissKeyboard: (() -> Void)?
    var showsBackHeader = false
    var onFinish: ((PortalState) -> Void)?
    private var finished: PortalState?
    @ObservationIgnored private var base: PortalState?

    private var stream: Task<Void, Never>?
    init(role: Role) {
        self.role = role
        sequence = Prompt.sequence(for: role)
    }

    var welcomeLine = SetupModel.defaultWelcome
    static let defaultWelcome = "Hello, welcome to Trytern."

    static func greeting(_ name: String) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return defaultWelcome }
        return "Hello \(name)."
    }

    func prepare(_ person: SignedInPerson) {
        firstName = person.givenName
        lastName = person.familyName
        welcomeLine = Self.greeting(person.givenName)
        guard let url = person.photoURL else { return }
        Task { [weak self] in
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            self?.photo = image
        }
    }

    func openAddHome(from portal: PortalState) {
        base = portal
        let you = portal.homes.lazy.flatMap(\.people).first { $0.id == "you" }
        let parts = (you?.name ?? "").split(separator: " ").map(String.init)
        firstName = parts.first ?? "You"
        lastName = parts.dropFirst().joined(separator: " ")
        gender = Gender.allCases.first { $0.title == you?.detail }
        welcomeDone = true
        reply = "Yes"
        active = .home
        questionText = Prompt.home.title
        formVisible = true
        rows = [
            TranscriptRow(kind: .settled(.name)),
            TranscriptRow(kind: .active(.home))
        ]
        onStructureChange?()
    }

    func showNameCard() {
        welcomeText = welcomeLine
        welcomeDone = true
        reply = "Yes"
        active = .name
        questionText = Prompt.name.title
        formVisible = true
        rows = [
            TranscriptRow(kind: .welcome),
            TranscriptRow(kind: .active(.name))
        ]
        onStructureChange?()
    }

    func start() {
        stream?.cancel()
        stream = Task { [weak self] in
            guard let self else { return }
            guard role == .owner else {
                welcomeDone = true
                return
            }
            reply = ""
            let name = firstName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                open(.name, line: "Hello, what's your name?")
                welcomeDone = true
                return
            }
            open(.home, line: "Hello \(name), which property are we setting up today?")
            welcomeDone = true
        }
    }

    func choose(_ answer: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reply = answer
        speak(answer)
        let knownName = !firstName.trimmingCharacters(in: .whitespaces).isEmpty
        guard answer == "Yes", let first = sequence.first(where: { !($0 == .name && knownName) }) else { return }
        open(first)
    }

    func open(_ prompt: Prompt, line custom: String? = nil) {
        if prompt == .home {
            homeStep = .find
            askingCommunity = false
            homeAsk = nil
        }
        if prompt == .rooms {
            roomStep = .layout
        }
        if prompt == .tasks {
            generateTasks()
        }
        if prompt == .workers {
            helpChoice = nil
            helpManual = false
            current = nil
        }
        if prompt == .car {
            let saved = cars.first { $0.id == current.flatMap { driverCar[$0] } }
            carModel = saved?.model ?? ""
            carPlate = saved?.plate ?? ""
        }
        placeholder = ""
        let first = currentWorker?.first.trimmingCharacters(in: .whitespaces) ?? ""
        let who = first.isEmpty ? "them" : first
        let line: String
        if let custom {
            line = custom
        } else {
        switch prompt {
        case .rooms: line = "How many bedrooms?"
        case .workers: line = workers.contains(where: workerReady) ? "Who else helps?" : "Who helps at home?"
        case .car: line = "Which car does \(who) drive?"
        case .tasks: line = "What does \(who) do? Untick what isn't theirs."
        case .pay: line = "Salary and hours for \(who)?"
        default: line = prompt.title
        }
        }
        ask(line, prompt: prompt)
        if prompt == .home { locateCommunity() }
    }

    var currentWorker: HouseWorker? {
        current.flatMap { workers[id: $0] }
    }

    var currentTasks: [HouseTask] {
        guard let current else { return [] }
        return houseTasks.filter { $0.worker == current }
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rows.append(TranscriptRow(kind: .reply(trimmed)))
        onStructureChange?()
    }

    func speakLocation(_ text: String, _ place: Community) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let latitude = place.latitude, let longitude = place.longitude {
            rows.append(TranscriptRow(kind: .location(trimmed, latitude, longitude)))
            onStructureChange?()
        } else {
            speak(trimmed)
        }
    }

    func deliver() {
        guard ready, let active else { return }
        if active == .tasks {
            houseTasks.removeAll { task in
                task.worker == current && (!task.on || task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        if active == .car {
            saveCar()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let text = summary(for: active).filter { !$0.isEmpty }.joined(separator: "\n")
        freezeQuestion()
        speak(text)
        goNext(after: active)
    }

    func submitDoor() {
        let door = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard community != nil, !door.isEmpty, (1...40).contains(floor) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        freezeQuestion()
        speak("\(door), floor \(floor)")
        goNext(after: .home)
    }

    private func ask(_ line: String, prompt: Prompt) {
        if prompt == .done {
            dismissKeyboard?()
            Task { [weak self] in
                try? await self?.clock.sleep(for: .milliseconds(80))
                self?.dismissKeyboard?()
            }
        } else {
            keepKeyboard?()
        }
        active = prompt
        asked = line
        if prompt == .home { homeAsk = line }
        questionText = ""
        formVisible = false
        thinking = true
        if let index = rows.lastIndex(where: { if case .active = $0.kind { return true }; return false }) {
            rows[index] = TranscriptRow(kind: .active(prompt), date: rows[index].date)
        } else {
            rows.append(TranscriptRow(kind: .active(prompt)))
        }
        onStructureChange?()
        stream?.cancel()
        stream = Task { [weak self] in
            guard let self else { return }
            try? await clock.sleep(for: .milliseconds(980))
            if Task.isCancelled { return }
            thinking = false
            onLayoutChange?()
            for index in line.indices {
                if Task.isCancelled { return }
                try? await clock.sleep(for: .milliseconds(18))
                questionText = String(line[...index])
                onLayoutChange?()
            }
            try? await clock.sleep(for: .milliseconds(180))
            formVisible = true
            if prompt == .done { dismissKeyboard?() }
            onLayoutChange?()
        }
    }

    private func askFollowUp(_ line: String) {
        homeStep = .door
        askingCommunity = false
        ask(line, prompt: .home)
    }

    private func freezeQuestion() {
        let line = asked.isEmpty ? (homeAsk ?? active?.title ?? questionText) : asked
        guard let index = rows.lastIndex(where: {
            if case .active = $0.kind { return true }
            return false
        }) else { return }
        let date = rows[index].date
        rows[index] = TranscriptRow(kind: .agent(line), date: date, id: rows[index].id)
        onLayoutChange?()
    }

    private func goNext(after prompt: Prompt) {
        if role == .owner, prompt == .name {
            open(.home)
            return
        }
        if role == .owner {
            switch prompt {
            case .home: open(.rooms)
            case .rooms: open(.workers)
            case .workers: open(currentWorker?.kind == .driver ? .car : .pay)
            case .car: open(.pay)
            default: finish()
            }
            return
        }
        guard let position = sequence.firstIndex(of: prompt), position + 1 < sequence.count else {
            finish()
            return
        }
        open(sequence[position + 1])
    }

    var ready: Bool {
        guard let active else { return false }
        switch active {
        case .name:
            return !firstName.trimmingCharacters(in: .whitespaces).isEmpty
                && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
                && gender != nil
        case .home:
            return community != nil && !unit.trimmingCharacters(in: .whitespaces).isEmpty
        case .rooms:
            return bedrooms > 0
        case .tasks:
            return currentTasks.contains { $0.on && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case .workers:
            return currentWorker.map(workerReady) ?? false
        case .car:
            return !carModel.trimmingCharacters(in: .whitespaces).isEmpty
        case .pay:
            return currentWorker.map(workerPaid) ?? false
        case .done:
            return true
        case .more:
            return true
        case .share, .workerShare:
            return share != nil
        case .skill:
            return skill != nil
        case .area:
            return !workArea.trimmingCharacters(in: .whitespaces).isEmpty && workCity != nil
        }
    }

    func advance() {
        deliver()
    }

    func chooseHelp(_ kind: WorkerKind) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        startHelper(kind)
        freezeQuestion()
        speak(kind.rawValue)
        placeholder = contactsNeedTyping ? "" : "Search your contacts"
        ask("Who's the \(kind.rawValue.lowercased())?", prompt: .workers)
        requestContactsIfNeeded()
    }

    func skipHelp() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        freezeQuestion()
        speak("Skip")
        finish()
    }

    func refreshContacts() {
        guard helpChoice != nil else { return }
        let typing = contactsNeedTyping
        guard helpManual != typing else { return }
        helpManual = typing
        placeholder = typing ? "" : "Search your contacts"
        onLayoutChange?()
    }

    private func startHelper(_ kind: WorkerKind) {
        if let current, let worker = workers[id: current], !workerReady(worker) {
            workers.remove(id: current)
            houseTasks.removeAll { $0.worker == current }
        }
        var person = HouseWorker.make()
        person.kind = kind
        workers.append(person)
        current = person.id
        helpChoice = kind
        helpManual = contactsNeedTyping
    }

    func skipCar() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        carModel = ""
        carPlate = ""
        freezeQuestion()
        speak("Skip")
        open(.pay)
    }

    private func saveCar() {
        guard let current else { return }
        let model = carModel.trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else { return }
        let plate = carPlate.trimmingCharacters(in: .whitespaces).uppercased()
        let id = driverCar[current] ?? UUID().uuidString
        if let index = cars.firstIndex(where: { $0.id == id }) {
            cars[index] = PortalCar(id: id, model: model, plate: plate)
        } else {
            cars.append(PortalCar(id: id, model: model, plate: plate))
        }
        driverCar[current] = id
        for index in houseTasks.indices where houseTasks[index].worker == current {
            houseTasks[index].car = id
        }
    }

    var contactsNeedTyping: Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited, .notDetermined:
            return false
        default:
            return true
        }
    }

    private func requestContactsIfNeeded() {
        guard CNContactStore.authorizationStatus(for: .contacts) == .notDetermined else { return }
        Task { [weak self] in
            let allowed = (try? await CNContactStore().requestAccess(for: .contacts)) == true
            guard let self, self.helpChoice != nil, !self.helpManual else { return }
            if !allowed {
                self.helpManual = true
                self.placeholder = ""
                self.onLayoutChange?()
            }
        }
    }

    func chooseContact(first: String, last: String, phone: String, dial: String, length: Int) {
        guard let id = current else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        update(id) { worker in
            worker.first = first
            worker.last = last
            worker.phone = phone
            worker.dial = dial
            worker.dialLength = length
        }
        let name = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        guard phone.count == length, !name.isEmpty else {
            helpManual = true
            onLayoutChange?()
            return
        }
        freezeQuestion()
        speak(name)
        goNext(after: .workers)
    }

    func submitBedrooms() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let count = min(10, max(1, bedrooms))
        setBedrooms(count)
        living = 1
        kitchens = 1
        secondKitchen = nil
        attached = Array(repeating: true, count: count)
        separateBaths = 0
        powder = 0
        laundry = nil
        bathrooms = count
        balconies = 1
        roomStep = .baths
        freezeQuestion()
        layoutChosen = true
        speak(count == 1 ? "1 bedroom" : "\(count) bedrooms")
        ask("How many bathrooms?", prompt: .rooms)
    }

    func setBathrooms(_ value: Int) {
        bathrooms = min(10, max(1, value))
    }

    func setBalconies(_ value: Int) {
        balconies = min(6, max(0, value))
    }

    func submitBaths() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        freezeQuestion()
        speak(bathrooms == 1 ? "1 bathroom" : "\(bathrooms) bathrooms")
        roomStep = .balconies
        ask("How many balconies?", prompt: .rooms)
    }

    func submitBalconies() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        freezeQuestion()
        let line = switch balconies {
        case 0: "No balconies"
        case 1: "1 balcony"
        default: "\(balconies) balconies"
        }
        speak(line)
        roomStep = .kitchen
        ask("And the kitchen?", prompt: .rooms)
    }

    func chooseKitchen(wetAndDry: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        kitchens = wetAndDry ? 2 : 1
        secondKitchen = wetAndDry ? .dry : nil
        extras["Balcony"] = balconies
        freezeQuestion()
        speak(wetAndDry ? "Wet and dry" : "One kitchen")
        goNext(after: .rooms)
    }

    func flipTask(_ id: UUID) {
        guard let index = houseTasks.firstIndex(where: { $0.id == id }) else { return }
        houseTasks[index].cadence = houseTasks[index].cadence.next
    }

    func selectTask(_ id: UUID) {
        guard let index = houseTasks.firstIndex(where: { $0.id == id }) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        houseTasks[index].on.toggle()
    }

    func renameTask(_ id: UUID, _ title: String) {
        guard let index = houseTasks.firstIndex(where: { $0.id == id }) else { return }
        houseTasks[index].title = title
    }

    func addHouseTask() {
        guard let current else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        houseTasks.append(HouseTask(title: "", cadence: .daily, worker: current, car: driverCar[current] ?? ""))
        onLayoutChange?()
    }

    private func generateTasks() {
        guard let current, let worker = workers[id: current] else { return }
        guard !houseTasks.contains(where: { $0.worker == current }) else { return }
        let taken = Set(houseTasks.filter { $0.on && $0.worker != current }.map { $0.title.lowercased() })
        var list = HelperTasks.make(
            for: worker.kind,
            rooms: RoomNames.rows(from: roomLines()),
            car: driverCar[current] ?? "",
            taken: taken
        )
        for index in list.indices { list[index].worker = current }
        houseTasks.append(contentsOf: list)
    }

    func setBedrooms(_ value: Int) {
        let next = min(10, max(0, value))
        if next > attached.count {
            attached.append(contentsOf: Array(repeating: nil, count: next - attached.count))
            bedrooms = next
        } else {
            bedrooms = next
            if attached.count > next {
                attached.removeLast(attached.count - next)
            }
        }
        onLayoutChange?()
    }

    func update(_ id: WorkerID, _ change: (inout HouseWorker) -> Void) {
        guard var worker = workers[id: id] else { return }
        change(&worker)
        workers[id: id] = worker
    }

    func addWorker() {
        UISelectionFeedbackGenerator().selectionChanged()
        workers.append(HouseWorker.make())
        onLayoutChange?()
    }

    func removeWorker(_ id: WorkerID) {
        workers.remove(id: id)
        onLayoutChange?()
    }

    func locateCommunity() {
        guard community == nil, !locating else { return }
        locationRefused = locationDenied
        guard !locationRefused else {
            onLayoutChange?()
            return
        }
        locating = true
        Task { [weak self] in
            guard let self else { return }
            let point = await CommunityPlaces.locate()
            here = point
            locationRefused = locationDenied
            if let point {
                let found = await CommunityPlaces.nearby(point)
                communities = found
                if community == nil, homeStep == .find, !passedSuggestion, let place = found.first {
                    suggest(place)
                }
            }
            locating = false
            onLayoutChange?()
        }
    }

    func suggest(_ place: Community) {
        guard homeStep == .find, community == nil, !passedSuggestion else { return }
        remember(place)
        stream?.cancel()
        thinking = false
        let area = place.area.isEmpty ? place.city : place.area
        let line = area.isEmpty ? "Are you in \(place.name)?" : "Are you in \(place.name), \(area)?"
        asked = line
        homeAsk = line
        questionText = line
        askingCommunity = true
        formVisible = true
        onLayoutChange?()
    }

    func choosePlace(_ place: Community) {
        remember(place)
        askingCommunity = false
        let line = place.name.isEmpty ? place.area : place.name
        freezeQuestion()
        speakLocation(line, place)
        askFollowUp("Which door and floor?")
    }

    func confirmCommunity(_ answer: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        askingCommunity = false
        freezeQuestion()
        if answer == "Yes", let community {
            speakLocation(answer, community)
        } else {
            speak(answer)
        }
        if answer == "Yes" {
            askFollowUp("Which door and floor?")
        } else {
            passedSuggestion = true
            community = nil
            unit = ""
            floor = 1
            homeStep = .find
            ask(Prompt.home.title, prompt: .home)
        }
    }

    private func remember(_ place: Community) {
        community = place
        if let index = communities.firstIndex(where: { $0.id == place.id }) {
            communities[index] = place
        } else {
            communities.insert(place, at: 0)
        }
    }

    func lookupPin() {
        let pin = draftPin
        guard pin.count == 6 else {
            draftCity = ""
            draftState = ""
            return
        }
        Task { [weak self] in
            let place = await Pincode.fetch(pin)
            guard let self, self.draftPin == pin else { return }
            draftCity = place?.city ?? ""
            draftState = place?.state ?? ""
        }
    }

    var canCreateCommunity: Bool {
        !draftName.trimmingCharacters(in: .whitespaces).isEmpty
            && !draftStreet.trimmingCharacters(in: .whitespaces).isEmpty
            && !draftArea.trimmingCharacters(in: .whitespaces).isEmpty
            && draftPin.count == 6
            && !draftCity.isEmpty
            && !draftState.isEmpty
    }

    func createCommunity() {
        guard canCreateCommunity else { return }
        let created = Community(
            id: UUID().uuidString,
            name: draftName.trimmingCharacters(in: .whitespaces),
            street: draftStreet.trimmingCharacters(in: .whitespaces),
            area: draftArea.trimmingCharacters(in: .whitespaces),
            city: draftCity,
            pincode: draftPin,
            state: draftState
        )
        choosePlace(created)
        draftName = ""
        draftStreet = ""
        draftArea = ""
        draftPin = ""
        draftCity = ""
        draftState = ""
    }

    func summary(for prompt: Prompt) -> [String] {
        switch prompt {
        case .name:
            return ["\(firstName.trimmingCharacters(in: .whitespaces)) \(lastName.trimmingCharacters(in: .whitespaces))", gender?.title ?? ""]
        case .home:
            guard let community else { return [] }
            let door = unit.trimmingCharacters(in: .whitespaces)
            return [community.name, door, door.isEmpty ? "" : "Floor \(floor)"].filter { !$0.isEmpty }
        case .rooms:
            return roomLines()
        case .tasks:
            return currentTasks.filter(\.on).map { "\($0.title) · \($0.cadence.rawValue)" }
        case .workers:
            guard let worker = currentWorker else { return [] }
            return [worker.name]
        case .car:
            return [carModel.trimmingCharacters(in: .whitespaces), carPlate.trimmingCharacters(in: .whitespaces).uppercased()]
        case .pay:
            guard let worker = currentWorker else { return [] }
            let start = worker.starts.map(ClockText.label) ?? ""
            let end = worker.ends.map(ClockText.label) ?? ""
            return ["₹\(worker.salary) · \(start)–\(end)"]
        case .done:
            return []
        case .more:
            return []
        case .share:
            return [share == true ? "Shared with \(community?.name ?? "the community")" : "Kept private"]
        case .skill:
            return [skill?.rawValue ?? ""]
        case .area:
            return ["\(workArea.trimmingCharacters(in: .whitespaces)) · \(workCity ?? "")"]
        case .workerShare:
            return [share == true ? "Shared" : "Kept private"]
        }
    }

    private func roomLines() -> [String] {
        var lines: [String] = []
        if bedrooms > 0 { lines.append(bedrooms == 1 ? "1 bedroom" : "\(bedrooms) bedrooms") }
        if living > 0 { lines.append("\(living) living") }
        if kitchens == 1 { lines.append("1 kitchen") }
        if kitchens > 1 { lines.append("\(kitchens) kitchens · \(secondKitchen?.rawValue ?? "")") }
        if bathrooms == 1 { lines.append("1 bathroom") }
        if bathrooms > 1 { lines.append("\(bathrooms) bathrooms") }
        if powder == 1 { lines.append("powder room") }
        if powder > 1 { lines.append("\(powder) powder rooms") }
        if let laundry { lines.append("Laundry · \(laundry.rawValue)") }
        for name in extraNames where (extras[name] ?? 0) > 0 {
            lines.append("\(extras[name] ?? 0) \(name)")
        }
        return lines
    }

    private func workerReady(_ worker: HouseWorker) -> Bool {
        worker.kind != nil
            && !worker.first.trimmingCharacters(in: .whitespaces).isEmpty
            && worker.phone.count == worker.dialLength
    }

    private func workerPaid(_ worker: HouseWorker) -> Bool {
        (Int(worker.salary) ?? 0) > 0 && worker.starts != nil && worker.ends != nil
    }

    private func workerDone(_ worker: HouseWorker) -> Bool {
        workerReady(worker) && workerPaid(worker)
    }

    private func finish() {
        var state = base ?? PortalState.empty
        if role == .owner, let community {
            let done = workers.filter(workerDone)
            let people = done.map { worker in
                let start = worker.starts.map(ClockText.label) ?? ""
                let end = worker.ends.map(ClockText.label) ?? ""
                return PortalPerson(
                    id: worker.id.rawValue.uuidString,
                    name: worker.name,
                    detail: "\(worker.kind?.rawValue ?? "") · \(start)–\(end)",
                    phone: "\(worker.dial) \(worker.phone)",
                    salary: worker.salary
                )
            }
            let home = PortalHome(
                id: UUID().uuidString,
                name: community.name,
                line: unit.trimmingCharacters(in: .whitespaces),
                floor: floor,
                area: community.area,
                community: community.name,
                city: community.city,
                rooms: RoomNames.rows(from: roomLines()).map {
                    PortalRoom(id: UUID().uuidString, name: $0, category: RoomCategory.infer($0))
                },
                cars: cars.filter { car in done.contains { driverCar[$0.id] == car.id } },
                people: [PortalPerson(id: "you", name: "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces), detail: gender?.title ?? "Manager", phone: "")] + people,
                tasks: ownedTasks(
                    PlaceTasks.items(
                        rooms: RoomNames.rows(from: roomLines()).map { ($0, RoomCategory.infer($0)) },
                        cars: cars.filter { car in done.contains { driverCar[$0.id] == car.id } }
                    ),
                    workers: done
                )
            )
            var saved = home
            saved.copiesAligned = true
            saved.communityKey = "p:\(community.id)"
            state.homes.insert(saved, at: 0)
            state.activeHomeID = saved.id
        }
        try? store.save(state)
        guard role == .owner else {
            onFinish?(state)
            return
        }
        finished = state
        ask("Thank you. Initial setup is complete. Next is People, where you can review, add, and edit staff and tasks.", prompt: .done)
    }

    func continueHome() {
        guard let finished else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        freezeQuestion()
        let chat: [SavedLine] = rows.compactMap { row in
            switch row.kind {
            case .agent(let text): SavedLine(text: text, mine: false)
            case .reply(let text), .location(let text, _, _): SavedLine(text: text, mine: true)
            default: nil
            }
        }
        let chatID = UUID(uuidString: finished.activeHomeID) ?? UUID()
        Task { await ChatCloud.save(id: chatID, kind: "setup", lines: chat) }
        onFinish?(finished)
    }

    private var locationDenied: Bool {
        switch CLLocationManager().authorizationStatus {
        case .denied, .restricted: return true
        default: return false
        }
    }

}
