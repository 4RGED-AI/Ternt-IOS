import Collections
import Dependencies
import Foundation
import IdentifiedCollections
import UIKit

@MainActor
@Observable
final class SetupModel {
    let role: Role
    let sequence: [Prompt]

    @ObservationIgnored
    @Dependency(\.continuousClock) var clock
    @ObservationIgnored
    @Dependency(\.householdStore) var store

    var rows: [TranscriptRow] = [TranscriptRow(kind: .welcome)]
    var welcomeText = ""
    var welcomeDone = false
    var reply: String?
    var questionText = ""
    var formVisible = false
    var timeReveal: CGFloat = 0
    var active: Prompt?

    var firstName = ""
    var lastName = ""
    var gender: Gender?
    var photo: UIImage?

    var communities: [Community] = [
        Community(id: "c1", name: "Palm Court Residents", street: "12th Main", area: "Indiranagar", city: "Bengaluru", pincode: "560038", state: "Karnataka"),
        Community(id: "c2", name: "Palm Meadows", street: "Street 4", area: "Whitefield", city: "Bengaluru", pincode: "560066", state: "Karnataka")
    ]
    var community: Community?
    var unit = ""
    var draftName = ""
    var draftStreet = ""
    var draftArea = ""
    var draftPin = ""
    var draftCity = ""
    var draftState = ""

    var bedrooms = 1
    var living = 1
    var kitchens = 1
    var attached: [Bool?] = [nil]
    var separateBaths = 0
    var powder = 0
    var secondKitchen: SecondKitchen?
    var laundry: Laundry?
    var moreRooms = false
    var extras = OrderedDictionary<String, Int>()
    let extraNames = ["Dining", "Pooja", "Study", "Balcony", "Terrace", "Garden", "Store", "Parking", "Staff room"]

    var workers: IdentifiedArrayOf<HouseWorker> = [HouseWorker.make()]
    var skill: WorkerKind?
    var workArea = ""
    var workCity: String?
    var share: Bool?

    let cities = ["Bengaluru", "Mumbai", "Delhi", "Hyderabad", "Chennai", "Pune", "Kolkata"]

    var sheet: SetupSheet?
    var onStructureChange: (() -> Void)?
    var onLayoutChange: (() -> Void)?
    var onFinish: ((PortalState) -> Void)?

    private var stream: Task<Void, Never>?

    init(role: Role) {
        self.role = role
        sequence = Prompt.sequence(for: role)
    }

    func start() {
        stream?.cancel()
        stream = Task { [weak self] in
            guard let self else { return }
            let full = "Welcome to TERNT. Are you ready to get started?"
            for index in full.indices {
                if Task.isCancelled { return }
                try? await clock.sleep(for: .milliseconds(16))
                welcomeText = String(full[...index])
            }
            try? await clock.sleep(for: .milliseconds(220))
            welcomeDone = true
        }
    }

    func choose(_ answer: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reply = answer
        rows.append(TranscriptRow(kind: .reply))
        onStructureChange?()
        guard answer == "Yes", let first = sequence.first else { return }
        stream = Task { [weak self] in
            try? await self?.clock.sleep(for: .milliseconds(380))
            self?.open(first)
        }
    }

    func open(_ prompt: Prompt) {
        active = prompt
        questionText = ""
        formVisible = false
        rows.append(TranscriptRow(kind: .active(prompt)))
        onStructureChange?()
        stream = Task { [weak self] in
            guard let self else { return }
            let full = prompt.title
            for index in full.indices {
                if Task.isCancelled { return }
                try? await clock.sleep(for: .milliseconds(12))
                questionText = String(full[...index])
            }
            try? await clock.sleep(for: .milliseconds(160))
            formVisible = true
            onLayoutChange?()
        }
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
            if bedrooms < 1 && living < 1 { return false }
            if bedrooms > 0 && attached.contains(where: { $0 == nil }) { return false }
            if kitchens > 1 && secondKitchen == nil { return false }
            return laundry != nil
        case .workers:
            return !workers.isEmpty && workers.allSatisfy(workerReady)
        case .pay:
            return workers.allSatisfy { worker in
                (Int(worker.salary) ?? 0) > 0 && worker.starts != nil && worker.ends != nil
            }
        case .share, .workerShare:
            return share != nil
        case .skill:
            return skill != nil
        case .area:
            return !workArea.trimmingCharacters(in: .whitespaces).isEmpty && workCity != nil
        }
    }

    func advance() {
        guard ready, let active else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let index = rows.lastIndex(where: {
            if case .active = $0.kind { return true }
            return false
        }) {
            rows[index].kind = .settled(active)
        }
        guard let position = sequence.firstIndex(of: active), position + 1 < sequence.count else {
            finish()
            return
        }
        open(sequence[position + 1])
    }

    func setBedrooms(_ value: Int) {
        bedrooms = value
        if attached.count > value {
            attached = Array(attached.prefix(value))
        } else {
            while attached.count < value { attached.append(nil) }
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
        communities.append(created)
        community = created
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
            return [community.name, unit.trimmingCharacters(in: .whitespaces), community.streetArea, "\(community.city), \(community.state)"].filter { !$0.isEmpty }
        case .rooms:
            return roomLines()
        case .workers:
            return workers.map { "\($0.name) · \($0.kind?.rawValue ?? "")" }
        case .pay:
            return workers.map { worker in
                let start = worker.starts.map(ClockText.label) ?? ""
                let end = worker.ends.map(ClockText.label) ?? ""
                return "\(worker.first) · ₹\(worker.salary) · \(start)–\(end)"
            }
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
        let attachedCount = attached.filter { $0 == true }.count
        let beds = "\(bedrooms) bedroom\(bedrooms == 1 ? "" : "s")"
        let bedroomLine: String = {
            if attachedCount == 0 { return "\(beds) · no attached bath" }
            if attachedCount == bedrooms {
                return bedrooms == 1 ? "1 bedroom · attached bath" : "\(beds) · all attached"
            }
            return "\(beds) · \(attachedCount) attached"
        }()
        var lines: [String] = []
        if bedrooms > 0 { lines.append(bedroomLine) }
        if living > 0 { lines.append("\(living) living") }
        if kitchens == 1 { lines.append("1 kitchen") }
        if kitchens > 1 { lines.append("\(kitchens) kitchens · \(secondKitchen?.rawValue ?? "")") }
        if separateBaths == 1 { lines.append("1 separate bathroom") }
        if separateBaths > 1 { lines.append("\(separateBaths) separate bathrooms") }
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
            && !worker.last.trimmingCharacters(in: .whitespaces).isEmpty
            && worker.phone.count == worker.dialLength
    }

    private func finish() {
        var state = PortalState.sample
        if role == .owner, let community {
            let people = workers.map { worker in
                let start = worker.starts.map(ClockText.label) ?? ""
                let end = worker.ends.map(ClockText.label) ?? ""
                return PortalPerson(
                    id: worker.id.rawValue.uuidString,
                    name: worker.name,
                    detail: "\(worker.kind?.rawValue ?? "") · \(start)–\(end)",
                    phone: "\(worker.dial) \(worker.phone)"
                )
            }
            let home = PortalHome(
                id: "setup",
                name: community.name,
                line: unit.trimmingCharacters(in: .whitespaces),
                area: community.area,
                community: community.name,
                city: community.city,
                rooms: roomLines(),
                people: [PortalPerson(id: "you", name: "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces), detail: gender?.title ?? "Owner", phone: "")] + people,
                tasks: []
            )
            state.homes.insert(home, at: 0)
            state.activeHomeID = home.id
        }
        try? store.save(state)
        onFinish?(state)
    }
}
