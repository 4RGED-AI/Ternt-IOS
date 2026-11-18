import Dependencies
import Nuke
import PhotosUI
import Supabase
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppModel {
    var screen: Screen = .gate
    var portal = PortalState.empty
    var addingHome = false
    var theme: ThemeChoice = .system
    var owner = OwnerIdentity(first: "", last: "", gender: nil)
    var photo: UIImage?
    var posts: [CommunityPost] = []
    var postError: String?
    var postingJob = false
    var busyPeople: Set<String> = []
    var me: UUID?
    var signedIn: SignedInPerson?
    var restoring = true
    var returning = false
    var tasking: PortalPerson?
    var workerDesk: WorkerDesk?
    var workerHomeID = ""
    var openPeople = false

    var ownerName: String {
        let name = owner.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "You" : name
    }

    func boot() {
        if let raw = UserDefaults.standard.string(forKey: "theme"),
           let saved = ThemeChoice(rawValue: raw) {
            theme = saved
        }
        @Dependency(\.householdStore) var store
        if let saved = try? store.load() {
            portal = saved
        }
        mendPeopleIDs()
        if portal.homes.indices.map({ dropMisfits(home: $0) }).contains(true) { remember(portal) }
        unfoldRooms()
        if let data = UserDefaults.standard.data(forKey: "owner"),
           let saved = try? JSONDecoder().decode(OwnerIdentity.self, from: data) {
            owner = saved
        } else {
            owner = identity(from: portal)
        }
        photo = ProfileImage.load()
        UserDefaults.standard.removeObject(forKey: "requests")
        applyInterfaceStyle()
        Task { await restoreSession() }
    }

    /// Gives every person a unique id; a blank or repeated id makes that worker unreachable for drops and edits.
    private func mendPeopleIDs() {
        var changed = false
        for home in portal.homes.indices {
            var seen: Set<String> = []
            for index in portal.homes[home].people.indices {
                let id = portal.homes[home].people[index].id
                if id.trimmingCharacters(in: .whitespaces).isEmpty || seen.contains(id) {
                    let fresh = UUID().uuidString
                    portal.homes[home].people[index].id = fresh
                    for room in portal.homes[home].rooms.indices where !seen.contains(id) {
                        portal.homes[home].rooms[room].people = portal.homes[home].rooms[room].people.map { $0 == id ? fresh : $0 }
                    }
                    seen.insert(fresh)
                    changed = true
                } else {
                    seen.insert(id)
                }
            }
        }
        if changed { remember(portal) }
    }

    func enterWorker() async {
        await refreshWorker()
        go(.worker)
    }

    func refreshWorker() async {
        guard let next = try? await StaffAccess.home(day: DayKey.today) else { return }
        workerDesk = next
        if !next.homes.contains(where: { $0.id == workerHomeID }) {
            workerHomeID = next.homes.first?.id ?? ""
        }
    }

    func selectWorkerHome(_ id: String) {
        workerHomeID = id
    }

    func replacePortal(_ state: PortalState) {
        portal = state
        mendPeopleIDs()
        @Dependency(\.householdStore) var store
        try? store.save(portal)
    }

    func confirmFinishes(worker: String, day: String) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        for index in portal.homes[home].finished.indices {
            let finish = portal.homes[home].finished[index]
            guard finish.day == day, finish.worker.caseInsensitiveCompare(worker) == .orderedSame else { continue }
            portal.homes[home].finished[index].ok = true
        }
        savePortal()
    }

    private func restoreSession() async {
        defer { restoring = false }
        guard screen == .gate else { return }
        // The Keychain session outlives an uninstall; UserDefaults does not.
        if !UserDefaults.standard.bool(forKey: "installed") {
            UserDefaults.standard.set(true, forKey: "installed")
            try? await TernedBackend.client.auth.signOut(scope: .local)
            forgetLocal()
            return
        }
        guard (try? await TernedBackend.client.auth.session) != nil else { return }
        do {
            _ = try await TernedBackend.client.auth.user()
        } catch let error as AuthError {
            if case .api = error {
                try? await TernedBackend.client.auth.signOut()
                forgetLocal()
                return
            }
        } catch {}
        guard screen == .gate else { return }
        if await StaffAccess.isStaff() {
            await enterWorker()
            return
        }
        do {
            if let remote = try await HouseholdCloud.shared.pull() {
                portal = remote
                mendPeopleIDs()
                screen = .owner
                if !settleHomeTasks() { remember(portal) }
            } else if HouseholdCloud.pending, !portal.homes.isEmpty {
                screen = .owner
                if !settleHomeTasks() { remember(portal) }
            } else {
                forgetLocal()
                signedIn = SignedInPerson(givenName: owner.first, familyName: owner.last, photoURL: nil)
                screen = .permissions(.owner)
            }
        } catch {
            guard !portal.homes.isEmpty else { return }
            screen = .owner
            if !settleHomeTasks() { remember(portal) }
        }
    }

    func go(_ next: Screen) {
        if next != .gate { returning = false }
        withAnimation(.smooth(duration: 0.45)) {
            screen = next
        }
    }

    func forgetLocal() {
        UserDefaults.standard.removeObject(forKey: HouseholdCloud.pendingKey)
        portal = .empty
        @Dependency(\.householdStore) var store
        try? store.save(.empty)
    }

    func sendRequest(text: String, kind: WorkerKind?, homeID: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let homeID, portal.homes.contains(where: { $0.id == homeID }) {
            portal.activeHomeID = homeID
        }
        if let index = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }),
           portal.homes[index].communityKey.isEmpty {
            let home = portal.homes[index]
            portal.homes[index].communityKey = PortalHome.key(community: home.community, city: home.city)
        }
        let home = portal.active
        let state = portal
        let author = owner.first.trimmingCharacters(in: .whitespaces)
        postingJob = true
        Task {
            defer { postingJob = false }
            do {
                try await CommunityBoard.post(String(trimmed.prefix(4000)), kind: kind, home: home, author: author, state: state)
                postError = nil
                await loadPosts()
            } catch {
                postError = "Couldn't post. Check your connection and try again."
            }
        }
    }

    func loadPosts() async {
        let key = portal.active.communityKey
        guard !key.isEmpty else { return }
        if me == nil { me = await CommunityBoard.me() }
        do {
            let next = try await CommunityBoard.posts(in: key)
            guard key == portal.active.communityKey else { return }
            posts = next
        } catch {
            postError = "Couldn't load posts."
        }
    }

    func closePost(_ post: CommunityPost) {
        posts.removeAll { $0.id == post.id }
        Task {
            try? await CommunityBoard.close(post)
            await loadPosts()
        }
    }

    func updatePost(_ post: CommunityPost, text: String, kind: WorkerKind?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let details = String(trimmed.prefix(500))
        let kindText = kind?.rawValue ?? ""
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index].details = details
            posts[index].kind = kindText
        }
        Task {
            do {
                try await CommunityBoard.revise(post, details: details, kind: kindText)
                postError = nil
                await loadPosts()
            } catch {
                postError = "Couldn't save the post."
                await loadPosts()
            }
        }
    }

    func chooseTheme(_ choice: ThemeChoice) {
        theme = choice
        UserDefaults.standard.set(choice.rawValue, forKey: "theme")
        applyInterfaceStyle()
    }

    func applyInterfaceStyle() {
        let style = theme.interfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    func saveOwner() {
        if let data = try? JSONEncoder().encode(owner) {
            UserDefaults.standard.set(data, forKey: "owner")
        }
        let display = ownerName
        let detail = owner.gender?.title ?? "Manager"
        for index in portal.homes.indices {
            guard let person = portal.homes[index].people.firstIndex(where: { $0.id == "you" || $0.name == "You" }) else { continue }
            portal.homes[index].people[person].name = display
            portal.homes[index].people[person].detail = detail
        }
        remember(portal)
    }

    func addPerson(_ person: PortalPerson) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        var person = person
        if person.id.trimmingCharacters(in: .whitespaces).isEmpty
            || portal.homes[home].people.contains(where: { $0.id == person.id }) {
            person.id = UUID().uuidString
        }
        portal.homes[home].people.append(person)
        liftSources(home: home)
        if let kind = person.kind {
            copySources(kind: kind, to: person.name, home: home)
        }
        busyPeople.insert(person.id)
        remember(portal, done: person.id)
    }

    func assignTasks(_ tasks: [HouseTask], to name: String) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        for task in tasks where task.on {
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            if let index = portal.homes[home].tasks.firstIndex(where: {
                $0.title.caseInsensitiveCompare(title) == .orderedSame && $0.room == task.room && $0.car == task.car
            }) {
                if portal.homes[home].tasks[index].worker.isEmpty {
                    portal.homes[home].tasks[index].worker = name
                }
                continue
            }
            portal.homes[home].tasks.append(PortalTask(
                id: UUID().uuidString,
                title: title,
                detail: task.cadence.rawValue,
                review: false,
                room: task.room,
                worker: name,
                car: task.car
            ))
        }
        savePortal()
    }

    func addRoom(_ room: PortalRoom) {
        let name = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = room.category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !category.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard !portal.homes[home].rooms.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        portal.homes[home].rooms.append(PortalRoom(id: room.id.isEmpty ? UUID().uuidString : room.id, name: name, category: category))
        var items = PlaceTasks.forRoom(name, category: category)
        if portal.homes[home].tasks.contains(where: { $0.title.caseInsensitiveCompare("List the groceries") == .orderedSame }) {
            items.removeAll { $0.title == "List the groceries" }
        }
        if portal.homes[home].rooms.count == 1,
           !portal.homes[home].tasks.contains(where: { $0.title.caseInsensitiveCompare("Clean the fans") == .orderedSame && $0.room.isEmpty && $0.car.isEmpty }) {
            items.append(PlaceTasks.Item(title: "Clean the fans", cadence: .monthly, room: "", car: "", kind: .housekeeper))
        }
        appendOwned(items, home: home)
        savePortal()
    }

    /// Adds home-owned tasks for a new place, then gives every current worker of that category a copy.
    private func appendOwned(_ items: [PlaceTasks.Item], home: Int) {
        var fresh: [PlaceTasks.Item] = []
        for item in items {
            let taken = portal.homes[home].tasks.contains {
                !$0.review && $0.memberSide != "by" && placeKey($0) == placeKey(item)
            }
            guard !taken else { continue }
            portal.homes[home].tasks.append(ownedTask(item, worker: ""))
            fresh.append(item)
        }
        let people = portal.homes[home].workers
        for item in fresh {
            for person in people where person.kind == item.kind {
                guard !portal.homes[home].tasks.contains(where: {
                    $0.worker.caseInsensitiveCompare(person.name) == .orderedSame && placeKey($0) == placeKey(item)
                }) else { continue }
                portal.homes[home].tasks.append(ownedTask(item, worker: person.name))
            }
        }
    }

    func addRoomCategory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        let taken = portal.homes[home].rooms.map(\.category) + portal.homes[home].roomCategories
        guard !taken.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        portal.homes[home].roomCategories.append(trimmed)
        savePortal()
    }

    func saveRoom(_ room: PortalRoom) {
        let name = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = room.category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !category.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard let index = portal.homes[home].rooms.firstIndex(where: { $0.id == room.id }) else { return }
        guard !portal.homes[home].rooms.contains(where: { $0.id != room.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        let previous = portal.homes[home].rooms[index].name
        portal.homes[home].rooms[index].name = name
        portal.homes[home].rooms[index].category = category
        if previous != name {
            for task in portal.homes[home].tasks.indices where portal.homes[home].tasks[task].room == previous {
                portal.homes[home].tasks[task].room = name
            }
        }
        savePortal()
    }

    func setRoomPeople(_ roomID: String, _ people: [String]) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard let index = portal.homes[home].rooms.firstIndex(where: { $0.id == roomID }) else { return }
        portal.homes[home].rooms[index].people = people
        savePortal()
    }

    func assignStaff(_ personID: String, toTask taskID: String) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard let person = portal.homes[home].workers.first(where: { $0.id == personID }), person.kind != .driver else { return }
        guard let task = portal.homes[home].tasks.first(where: { $0.id == taskID }), person.takes(task) else { return }
        let taken = portal.homes[home].tasks.contains {
            $0.worker.caseInsensitiveCompare(person.name) == .orderedSame
                && $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                && $0.room.caseInsensitiveCompare(task.room) == .orderedSame
                && $0.car == task.car
                && !$0.review
        }
        if !taken {
            portal.homes[home].tasks.append(PortalTask(
                id: UUID().uuidString,
                title: task.title,
                detail: task.detail,
                review: false,
                room: task.room,
                worker: person.name,
                car: task.car,
                member: task.member,
                memberSide: task.memberSide,
                note: task.note,
                kind: task.kind.isEmpty ? (person.kind?.rawValue ?? "") : task.kind,
                photo: task.photo
            ))
        }
        if let index = portal.homes[home].rooms.firstIndex(where: { $0.name.caseInsensitiveCompare(task.room) == .orderedSame }),
           !portal.homes[home].rooms[index].people.contains(personID) {
            portal.homes[home].rooms[index].people.append(personID)
        }
        savePortal()
    }

    /// Hands room or car tasks to one worker. With `alone`, other workers lose their copies of those tasks.
    func handTasks(_ ids: Set<String>, to personID: String, alone: Bool) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard let person = portal.homes[home].workers.first(where: { $0.id == personID }) else { return }
        let picked = portal.homes[home].tasks.filter { ids.contains($0.id) && person.takes($0) }
        guard !picked.isEmpty else { return }
        for task in picked {
            if person.kind == .driver {
                placeDriver(person.id, onCar: task.car)
            } else {
                assignStaff(person.id, toTask: task.id)
            }
        }
        guard alone else { return }
        let before = portal.homes[home].tasks.count
        portal.homes[home].tasks.removeAll { other in
            !other.worker.isEmpty
                && other.worker.caseInsensitiveCompare(person.name) != .orderedSame
                && !other.review
                && other.memberSide != "by"
                && picked.contains {
                    $0.title.caseInsensitiveCompare(other.title) == .orderedSame
                        && $0.room.caseInsensitiveCompare(other.room) == .orderedSame
                        && $0.car == other.car
                }
        }
        if portal.homes[home].tasks.count != before { savePortal() }
    }

    func placeStaff(_ personID: String, onRoom roomID: String) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard let person = portal.homes[home].workers.first(where: { $0.id == personID }), person.kind != .driver else { return }
        guard let index = portal.homes[home].rooms.firstIndex(where: { $0.id == roomID }) else { return }
        guard !portal.homes[home].rooms[index].people.contains(personID) else { return }
        portal.homes[home].rooms[index].people.append(personID)
        savePortal()
    }

    func placeDriver(_ personID: String, onCar carID: String) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard let person = portal.homes[home].workers.first(where: { $0.id == personID }), person.kind == .driver else { return }
        guard let index = portal.homes[home].cars.firstIndex(where: { $0.id == carID }) else { return }
        guard portal.homes[home].cars[index].driver != personID else { return }
        portal.homes[home].cars[index].driver = personID
        savePortal()
    }

    func unfoldRooms() {
        var changed = false
        for index in portal.homes.indices {
            let current = portal.homes[index].rooms.map(\.name)
            let expanded = RoomNames.rows(from: current)
            guard expanded != current else { continue }
            changed = true
            var tasks = portal.homes[index].tasks
            for line in current {
                let parts = RoomNames.expand(line)
                guard parts != [line], let first = parts.first else { continue }
                for task in tasks.indices where tasks[task].room == line && tasks[task].car.isEmpty {
                    tasks[task].room = first
                }
            }
            portal.homes[index].rooms = expanded.map { name in
                PortalRoom(id: UUID().uuidString, name: name, category: RoomCategory.infer(name))
            }
            portal.homes[index].tasks = tasks
        }
        if changed { savePortal() }
    }

    func seedRoom(_ name: String) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard let room = portal.homes[home].rooms.first(where: { $0.name == name }) else { return }
        _ = room
    }

    func removeRoom(_ name: String) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        portal.homes[home].rooms.removeAll { $0.name == name }
        portal.homes[home].tasks.removeAll { $0.room == name && $0.car.isEmpty }
        savePortal()
    }

    func saveMember(_ member: PortalMember) {
        let name = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !member.relation.isEmpty, member.born != nil else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard let index = portal.homes[home].members.firstIndex(where: { $0.id == member.id }) else { return }
        guard !portal.homes[home].members.contains(where: { $0.id != member.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        portal.homes[home].members[index].name = name
        portal.homes[home].members[index].relation = member.relation
        portal.homes[home].members[index].born = member.born
        savePortal()
    }

    func removeMember(_ id: String) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        portal.homes[home].members.removeAll { $0.id == id }
        portal.homes[home].tasks.removeAll { $0.member == id }
        savePortal()
    }

    func updateCar(_ id: String, model rawModel: String, plate rawPlate: String) {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let plate = rawPlate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !plate.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard let index = portal.homes[home].cars.firstIndex(where: { $0.id == id }) else { return }
        portal.homes[home].cars[index].model = model
        portal.homes[home].cars[index].plate = plate
        savePortal()
    }

    func removeCar(_ id: String) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        portal.homes[home].cars.removeAll { $0.id == id }
        portal.homes[home].tasks.removeAll { $0.car == id }
        savePortal()
    }

    func toggleFinish(_ task: PortalTask, on day: String) {
        let day = day.trimmingCharacters(in: .whitespaces)
        guard !day.isEmpty, !task.worker.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        let place = task.room.isEmpty ? task.car : task.room
        if let index = portal.homes[home].finished.firstIndex(where: {
            $0.day == day
                && $0.worker.caseInsensitiveCompare(task.worker) == .orderedSame
                && $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                && $0.place.caseInsensitiveCompare(place) == .orderedSame
        }) {
            portal.homes[home].finished.remove(at: index)
        } else {
            portal.homes[home].finished.append(TaskFinish(
                id: UUID().uuidString,
                day: day,
                worker: task.worker,
                title: task.title,
                place: place
            ))
        }
        savePortal()
    }

    func saveTask(_ task: PortalTask) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        if let index = portal.homes[home].tasks.firstIndex(where: { $0.id == task.id }) {
            portal.homes[home].tasks[index] = task
        } else {
            portal.homes[home].tasks.append(task)
        }
        savePortal()
    }

    func moveTask(_ id: String, to worker: String) {
        let ids = id.split(separator: "\u{1e}").map(String.init)
        guard !ids.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        let person = portal.homes[home].workers.first { $0.name.caseInsensitiveCompare(worker) == .orderedSame }
        var tasks = portal.homes[home].tasks
        var changed = false
        for id in ids {
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { continue }
            let task = tasks[index]
            guard task.worker != worker else { continue }
            if let person, !person.takes(task) { continue }
            let already = tasks.contains {
                $0.id != id
                    && $0.worker.caseInsensitiveCompare(worker) == .orderedSame
                    && $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                    && $0.room.caseInsensitiveCompare(task.room) == .orderedSame
                    && $0.car == task.car
            }
            if already {
                tasks.remove(at: index)
            } else {
                tasks[index].worker = worker
            }
            changed = true
        }
        guard changed else { return }
        portal.homes[home].tasks = tasks
        savePortal()
    }

    /// Moves a room's task, and the copies workers already have, into another room.
    func moveTasks(_ ids: Set<String>, toRoom room: String) {
        let room = room.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ids.isEmpty, !room.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        var tasks = portal.homes[home].tasks
        let seeds = tasks.filter { ids.contains($0.id) && $0.room.caseInsensitiveCompare(room) != .orderedSame }
        guard !seeds.isEmpty else { return }
        var changed = false
        for seed in seeds {
            let present = tasks.contains { other in
                other.room.caseInsensitiveCompare(room) == .orderedSame
                    && other.title.caseInsensitiveCompare(seed.title) == .orderedSame
                    && other.car.isEmpty
                    && !other.review
                    && other.memberSide != "by"
            }
            if present { continue }
            let source = seed.room
            let indexes = tasks.indices.filter { index in
                let task = tasks[index]
                return task.room.caseInsensitiveCompare(source) == .orderedSame
                    && task.title.caseInsensitiveCompare(seed.title) == .orderedSame
                    && task.car.isEmpty
                    && !task.review
                    && task.memberSide != "by"
            }
            var names = Set<String>()
            for index in indexes.sorted(by: >) {
                let task = tasks[index]
                if !task.worker.isEmpty { names.insert(task.worker) }
                let already = tasks.contains { other in
                    other.id != task.id
                        && other.room.caseInsensitiveCompare(room) == .orderedSame
                        && other.title.caseInsensitiveCompare(task.title) == .orderedSame
                        && other.worker.caseInsensitiveCompare(task.worker) == .orderedSame
                        && other.car.isEmpty
                        && !other.review
                }
                if already {
                    tasks.remove(at: index)
                } else {
                    tasks[index].room = room
                }
                changed = true
            }
            guard changed,
                  let sourceIndex = portal.homes[home].rooms.firstIndex(where: { $0.name.caseInsensitiveCompare(source) == .orderedSame }),
                  let destIndex = portal.homes[home].rooms.firstIndex(where: { $0.name.caseInsensitiveCompare(room) == .orderedSame }) else { continue }
            for name in names {
                guard let person = portal.homes[home].workers.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
                let still = tasks.contains {
                    $0.room.caseInsensitiveCompare(source) == .orderedSame
                        && $0.worker.caseInsensitiveCompare(name) == .orderedSame
                        && !($0.review)
                }
                if !still {
                    portal.homes[home].rooms[sourceIndex].people.removeAll { $0 == person.id }
                }
                if !portal.homes[home].rooms[destIndex].people.contains(person.id) {
                    portal.homes[home].rooms[destIndex].people.append(person.id)
                }
            }
        }
        guard changed else { return }
        portal.homes[home].tasks = tasks
        savePortal()
    }

    /// Rewrites one worker's copies of a task so the title, note, and rooms or cars match the editor.
    func saveGroupedTask(worker: String, fromTitle: String, title: String, note: String, rooms: [String], cars: [String], photo: Bool = false) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        var tasks = portal.homes[home].tasks
        let matches = fromTitle.isEmpty ? [] : tasks.filter {
            $0.title.caseInsensitiveCompare(fromTitle) == .orderedSame && !$0.review && $0.memberSide != "by"
        }
        let people = portal.homes[home].workers
        let kind = matches.first { !$0.kind.isEmpty }?.kind
            ?? people.first { $0.name.caseInsensitiveCompare(worker) == .orderedSame }?.kind?.rawValue
            ?? ""
        let detail = matches.first?.detail ?? "Daily"
        var holders = Array(Set(matches.map(\.worker)))
        if fromTitle.isEmpty {
            let names = people.filter { $0.kind?.rawValue == kind && !kind.isEmpty }.map(\.name)
            holders = [""] + names
            if !worker.isEmpty && !holders.contains(where: { $0.caseInsensitiveCompare(worker) == .orderedSame }) {
                holders.append(worker)
            }
        } else if !holders.contains("") {
            holders.append("")
        }
        tasks.removeAll { task in matches.contains { $0.id == task.id } }
        let places: [(room: String, car: String)] = !cars.isEmpty
            ? cars.map { ("", $0) }
            : (!rooms.isEmpty ? rooms.map { ($0, "") } : [("", "")])
        for holder in holders {
            let person = people.first { !holder.isEmpty && $0.name.caseInsensitiveCompare(holder) == .orderedSame }
            for place in places {
                if let person, (person.kind == .driver) == place.car.isEmpty { continue }
                tasks.append(PortalTask(
                    id: UUID().uuidString,
                    title: title,
                    detail: detail,
                    review: false,
                    room: place.room,
                    worker: holder,
                    car: place.car,
                    note: note,
                    kind: kind,
                    photo: photo
                ))
            }
        }
        portal.homes[home].tasks = tasks
        savePortal()
    }

    func removeTasks(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        portal.homes[home].tasks.removeAll { ids.contains($0.id) }
        savePortal()
    }

    func copyTasks(_ ids: Set<String>, to workers: [String]) {
        guard !ids.isEmpty, !workers.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        let source = portal.homes[home].tasks.filter { ids.contains($0.id) }
        for name in workers {
            let person = portal.homes[home].workers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            for task in source where task.worker.caseInsensitiveCompare(name) != .orderedSame {
                if let person, !person.takes(task) { continue }
                let has = portal.homes[home].tasks.contains {
                    $0.worker.caseInsensitiveCompare(name) == .orderedSame
                        && $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                        && $0.room.caseInsensitiveCompare(task.room) == .orderedSame
                        && $0.car == task.car
                        && !$0.review
                }
                if has { continue }
                portal.homes[home].tasks.append(PortalTask(
                    id: UUID().uuidString,
                    title: task.title,
                    detail: task.detail,
                    review: false,
                    room: task.room,
                    worker: name,
                    car: task.car,
                    member: task.member,
                    memberSide: task.memberSide,
                    note: task.note,
                    kind: task.kind,
                    photo: task.photo
                ))
            }
        }
        savePortal()
    }

    /// Duplicates the selected room tasks, including the copies workers already have, into other rooms.
    func copyTasks(_ ids: Set<String>, toRooms rooms: [String]) {
        guard !ids.isEmpty, !rooms.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        var tasks = portal.homes[home].tasks
        let seeds = tasks.filter { ids.contains($0.id) }
        guard !seeds.isEmpty else { return }
        var changed = false
        for room in rooms {
            let room = room.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !room.isEmpty else { continue }
            var names = Set<String>()
            for seed in seeds {
                guard seed.room.caseInsensitiveCompare(room) != .orderedSame else { continue }
                let family = tasks.filter {
                    $0.room.caseInsensitiveCompare(seed.room) == .orderedSame
                        && $0.title.caseInsensitiveCompare(seed.title) == .orderedSame
                        && $0.car == seed.car
                        && !$0.review
                        && $0.memberSide != "by"
                }
                for task in family.isEmpty ? [seed] : family {
                    let exists = tasks.contains {
                        $0.room.caseInsensitiveCompare(room) == .orderedSame
                            && $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                            && $0.worker.caseInsensitiveCompare(task.worker) == .orderedSame
                            && $0.car == task.car
                            && !$0.review
                    }
                    guard !exists else { continue }
                    tasks.append(PortalTask(
                        id: UUID().uuidString,
                        title: task.title,
                        detail: task.detail,
                        review: false,
                        room: room,
                        worker: task.worker,
                        car: task.car,
                        member: task.member,
                        memberSide: task.memberSide,
                        note: task.note,
                        kind: task.kind,
                        photo: task.photo
                    ))
                    if !task.worker.isEmpty { names.insert(task.worker) }
                    changed = true
                }
            }
            guard let dest = portal.homes[home].rooms.firstIndex(where: { $0.name.caseInsensitiveCompare(room) == .orderedSame }) else { continue }
            for name in names {
                guard let person = portal.homes[home].workers.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
                if !portal.homes[home].rooms[dest].people.contains(person.id) {
                    portal.homes[home].rooms[dest].people.append(person.id)
                }
            }
        }
        guard changed else { return }
        portal.homes[home].tasks = tasks
        savePortal()
    }

    func addCar(model: String, plate: String) {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let plate = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !plate.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        let id = UUID().uuidString
        let trips = portal.homes[home].cars.isEmpty
        let car = PortalCar(id: id, model: model, plate: plate)
        portal.homes[home].cars.append(car)
        appendOwned(PlaceTasks.forCar(car, trips: trips), home: home)
        savePortal()
    }

    func addMember(_ member: PortalMember) {
        let name = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !member.relation.isEmpty, member.born != nil else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard !portal.homes[home].members.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        portal.homes[home].members.append(PortalMember(id: UUID().uuidString, name: name, relation: member.relation, born: member.born))
        savePortal()
    }

    func addTask(title: String, worker: String, room: String = "", car: String = "", member: String = "", memberSide: String = "") {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        portal.homes[home].tasks.append(PortalTask(
            id: UUID().uuidString,
            title: title,
            review: false,
            room: room,
            worker: worker,
            car: car,
            member: member,
            memberSide: memberSide
        ))
        savePortal()
    }

    func addGrocery(name: String, aisle: GroceryAisle, par: Int, onHand: Int, unit: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !unit.isEmpty else { return }
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        portal.homes[home].groceries.append(GroceryItem(
            id: UUID().uuidString,
            name: name,
            aisle: aisle,
            par: max(1, par),
            onHand: max(0, onHand),
            unit: unit
        ))
        savePortal()
    }

    func updateGrocery(_ item: GroceryItem) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard let index = portal.homes[home].groceries.firstIndex(where: { $0.id == item.id }) else { return }
        var next = item
        next.par = max(1, next.par)
        next.onHand = max(0, next.onHand)
        next.name = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.unit = next.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.name.isEmpty, !next.unit.isEmpty else { return }
        portal.homes[home].groceries[index] = next
        savePortal()
    }

    func removeGrocery(_ id: String) {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        portal.homes[home].groceries.removeAll { $0.id == id }
        savePortal()
    }

    func addUsualGroceries() {
        guard let home = portal.homes.firstIndex(where: { $0.id == portal.activeHomeID }) else { return }
        guard portal.homes[home].groceries.isEmpty else { return }
        portal.homes[home].groceries = GroceryItem.usual.map { item in
            var copy = item
            copy.id = UUID().uuidString
            return copy
        }
        savePortal()
    }

    func syncNow() async {
        _ = await HouseholdCloud.shared.push(portal)
    }

    private func savePortal() {
        remember(portal)
    }

    private func remember(_ state: PortalState, done: String? = nil) {
        @Dependency(\.householdStore) var store
        try? store.save(state)
        guard !state.homes.isEmpty else {
            if let done { busyPeople.remove(done) }
            return
        }
        Task {
            let pushed = await HouseholdCloud.shared.push(state)
            if pushed { await CommunityPeople.publish(state.active) }
            if let done { busyPeople.remove(done) }
        }
    }

    func removePerson(_ id: String) {
        for home in portal.homes.indices {
            guard let index = portal.homes[home].people.firstIndex(where: { $0.id == id }) else { continue }
            let name = portal.homes[home].people[index].name
            if !name.isEmpty {
                var tasks = portal.homes[home].tasks
                let owned = tasks.indices.filter { tasks[$0].worker.caseInsensitiveCompare(name) == .orderedSame }
                for taskIndex in owned.sorted(by: >) {
                    let task = tasks[taskIndex]
                    let kept = tasks.contains { other in
                        other.id != task.id
                            && other.worker.isEmpty
                            && other.title.caseInsensitiveCompare(task.title) == .orderedSame
                            && other.room.caseInsensitiveCompare(task.room) == .orderedSame
                            && other.car == task.car
                            && !other.review
                    }
                    if kept {
                        tasks.remove(at: taskIndex)
                    } else {
                        tasks[taskIndex].worker = ""
                    }
                }
                portal.homes[home].tasks = tasks
            }
            portal.homes[home].people.remove(at: index)
            for room in portal.homes[home].rooms.indices {
                portal.homes[home].rooms[room].people.removeAll { $0 == id }
            }
            for car in portal.homes[home].cars.indices where portal.homes[home].cars[car].driver == id {
                portal.homes[home].cars[car].driver = ""
            }
        }
        savePortal()
    }

    func savePerson(_ person: PortalPerson) {
        for home in portal.homes.indices {
            guard let index = portal.homes[home].people.firstIndex(where: { $0.id == person.id }) else { continue }
            let previous = portal.homes[home].people[index].name
            portal.homes[home].people[index] = person
            if previous != person.name {
                for task in portal.homes[home].tasks.indices where portal.homes[home].tasks[task].worker == previous {
                    portal.homes[home].tasks[task].worker = person.name
                }
            }
        }
        remember(portal)
    }

    func setPhoto(_ image: UIImage?) {
        photo = image
        ProfileImage.store(image)
    }

    private func identity(from portal: PortalState) -> OwnerIdentity {
        let you = portal.homes.lazy.flatMap(\.people).first { $0.id == "you" }
        let parts = (you?.name ?? "").split(separator: " ").map(String.init)
        return OwnerIdentity(
            first: parts.first ?? "",
            last: parts.dropFirst().joined(separator: " "),
            gender: Gender.allCases.first { $0.title == you?.detail }
        )
    }

    func showLogin(_ role: Role) { go(.login(role)) }

    func showSetup(_ role: Role) {
        go(role == .owner && !addingHome ? .permissions(role) : .setup(role))
    }

    func startSetup(_ role: Role) {
        go(.setup(role))
    }

    func showPortal(_ state: PortalState, role: Role, people: Bool = false) {
        openPeople = people
        portal = state
        addingHome = false
        if !settleHomeTasks() { remember(portal) }
        go(role == .owner ? .owner : .worker)
    }

    /// Keeps a home-owned row for every task that already exists, then once gives each worker a copy. Does not run the template again.
    @discardableResult
    private func settleHomeTasks() -> Bool {
        var changed = false
        for index in portal.homes.indices {
            if liftSources(home: index) { changed = true }
            if dropMisfits(home: index) { changed = true }
            guard !portal.homes[index].copiesAligned else { continue }
            for person in portal.homes[index].workers {
                guard let kind = person.kind else { continue }
                if copySources(kind: kind, to: person.name, home: index) { changed = true }
            }
            portal.homes[index].copiesAligned = true
            changed = true
        }
        if changed { savePortal() }
        return changed
    }

    /// The home owns one row per task, with no worker. Existing assigned rows become that list.
    @discardableResult
    private func liftSources(home index: Int) -> Bool {
        var tasks = portal.homes[index].tasks
        var changed = false
        let held = tasks.filter { !$0.worker.isEmpty && !$0.review && $0.memberSide != "by" }
        for task in held {
            let key = placeKey(task)
            if let source = tasks.firstIndex(where: { $0.worker.isEmpty && !$0.review && $0.memberSide != "by" && placeKey($0) == key }) {
                if tasks[source].kind.isEmpty {
                    let kind = resolvedKind(for: task, home: index)
                    if !kind.isEmpty {
                        tasks[source].kind = kind
                        changed = true
                    }
                }
                continue
            }
            var source = task
            source.id = UUID().uuidString
            source.worker = ""
            source.kind = resolvedKind(for: task, home: index)
            tasks.append(source)
            changed = true
        }
        for cursor in tasks.indices where tasks[cursor].kind.isEmpty && !tasks[cursor].worker.isEmpty {
            let kind = resolvedKind(for: tasks[cursor], home: index)
            guard !kind.isEmpty else { continue }
            tasks[cursor].kind = kind
            changed = true
        }
        if changed { portal.homes[index].tasks = tasks }
        return changed
    }

    /// Removes worker copies that break the driver rule; the home's own unassigned rows stay.
    @discardableResult
    private func dropMisfits(home index: Int) -> Bool {
        let workers = portal.homes[index].workers
        let before = portal.homes[index].tasks.count
        portal.homes[index].tasks.removeAll { task in
            guard !task.worker.isEmpty, !task.review, task.memberSide != "by" else { return false }
            guard let person = workers.first(where: { $0.name.caseInsensitiveCompare(task.worker) == .orderedSame }) else { return false }
            return !person.takes(task)
        }
        return portal.homes[index].tasks.count != before
    }

    /// Gives this worker a copy of each home task of their category they do not already have.
    @discardableResult
    private func copySources(kind: WorkerKind, to name: String, home index: Int) -> Bool {
        guard !name.isEmpty else { return false }
        let wantsCar = kind == .driver
        let sources = portal.homes[index].tasks.filter {
            $0.worker.isEmpty && !$0.review && $0.memberSide != "by" && $0.kind == kind.rawValue
                && $0.car.isEmpty != wantsCar
        }
        var added = false
        for source in sources {
            let has = portal.homes[index].tasks.contains {
                $0.worker.caseInsensitiveCompare(name) == .orderedSame && placeKey($0) == placeKey(source)
            }
            guard !has else { continue }
            var copy = source
            copy.id = UUID().uuidString
            copy.worker = name
            portal.homes[index].tasks.append(copy)
            added = true
        }
        return added
    }

    private func resolvedKind(for task: PortalTask, home index: Int) -> String {
        if !task.kind.isEmpty { return task.kind }
        let home = portal.homes[index]
        if let kind = home.workers.first(where: { $0.name.caseInsensitiveCompare(task.worker) == .orderedSame })?.kind {
            return kind.rawValue
        }
        if let holder = home.tasks.first(where: { !$0.worker.isEmpty && placeKey($0) == placeKey(task) }),
           let kind = home.workers.first(where: { $0.name.caseInsensitiveCompare(holder.worker) == .orderedSame })?.kind {
            return kind.rawValue
        }
        let catalog = PlaceTasks.items(
            rooms: home.rooms.map { ($0.name, $0.category) },
            cars: home.cars
        )
        if let match = catalog.first(where: {
            $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                && $0.room.caseInsensitiveCompare(task.room) == .orderedSame
                && $0.car == task.car
        }) {
            return match.kind.rawValue
        }
        return catalog.first { $0.title.caseInsensitiveCompare(task.title) == .orderedSame }?.kind.rawValue ?? ""
    }

    private func placeKey(_ task: PortalTask) -> String {
        "\(task.title.lowercased())|\(task.room.lowercased())|\(task.car)"
    }

    private func placeKey(_ item: PlaceTasks.Item) -> String {
        "\(item.title.lowercased())|\(item.room.lowercased())|\(item.car)"
    }

    private func ownedTask(_ item: PlaceTasks.Item, worker: String) -> PortalTask {
        PortalTask(
            id: UUID().uuidString,
            title: item.title,
            detail: item.cadence.rawValue,
            review: false,
            room: item.room,
            worker: worker,
            car: item.car,
            kind: item.kind.rawValue
        )
    }

    func selectHome(_ id: String) {
        guard portal.homes.contains(where: { $0.id == id }) else { return }
        portal.activeHomeID = id
        remember(portal)
    }

    func beginAddHome() {
        addingHome = true
        go(.setup(.owner))
    }

    func cancelAddHome() {
        addingHome = false
        go(.owner)
    }

    func logOut() {
        let snapshot = portal
        addingHome = false
        Task {
            if !snapshot.homes.isEmpty {
                _ = await HouseholdCloud.shared.push(snapshot)
            }
            try? await TernedBackend.client.auth.signOut()
            signedIn = nil
            workerDesk = nil
            workerHomeID = ""
            portal = .empty
            owner = OwnerIdentity(first: "", last: "", gender: nil)
            photo = nil
            posts = []
            me = nil
            ProfileImage.store(nil)
            UserDefaults.standard.removeObject(forKey: "owner")
            @Dependency(\.householdStore) var store
            try? store.save(.empty)
            returning = true
            go(.gate)
        }
    }
}

enum Screen: Equatable {
    case gate
    case login(Role)
    case permissions(Role)
    case setup(Role)
    case owner
    case worker
}

extension AnyTransition {
    static var forward: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)
        )
    }

    static var back: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .leading),
            removal: .move(edge: .trailing)
        )
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette.resolve(app.theme.preferred ?? scheme)
        ZStack {
            if app.restoring {
                palette.canvas.ignoresSafeArea()
            } else {
                switch app.screen {
                case .gate:
                    RoleGateView()
                        .transition(app.returning ? .back : .identity)
                case .login(let role):
                    LoginView(role: role)
                        .transition(.forward)
                case .permissions(let role):
                    PermissionsView(role: role)
                        .transition(.forward)
                case .setup(let role):
                    SetupScreen(role: role, addingHome: app.addingHome)
                        .transition(.forward)
                case .owner:
                    OwnerView()
                        .transition(app.returning ? .back : .forward)
                case .worker:
                    WorkerView()
                        .transition(app.returning ? .back : .forward)
                }
            }
        }
        .preferredColorScheme(app.theme.preferred)
        .environment(\.palette, palette)
        .animation(.smooth(duration: 0.42), value: app.screen)
        .task { app.boot() }
    }
}

private struct MarkFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct GateFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct RoleGateView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var progress: CGFloat = 0
    @State private var settled = false
    @State private var markFrame: CGRect = .zero
    @State private var gateFrame: CGRect = .zero

    private let heroSize: CGFloat = 52
    private let heroTracking: CGFloat = -0.8
    private let restSize: CGFloat = 14.3
    private let restTracking: CGFloat = 2.4

    var body: some View {
        ZStack(alignment: .topLeading) {
            palette.canvas.ignoresSafeArea()
            GeometryReader { proxy in
                Color.clear.preference(key: GateFrameKey.self, value: proxy.frame(in: .named("gate")))
            }
            VStack(alignment: .leading, spacing: 0) {
                restingMark
                    .padding(.top, 18)
                    .padding(.leading, 22)
                Spacer(minLength: 0)
                signIn
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
            }
            if !settled, gateFrame != .zero, markFrame != .zero {
                flyingMark
            }
        }
        .coordinateSpace(name: "gate")
        .onPreferenceChange(MarkFrameKey.self) { markFrame = $0 }
        .onPreferenceChange(GateFrameKey.self) { gateFrame = $0 }
        .task {
            if app.returning {
                progress = 1
                settled = true
                return
            }
            await playIntro()
        }
    }

    private var restingMark: some View {
        NorthernWord(size: restSize, tracking: restTracking)
            .opacity(settled ? 1 : 0)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MarkFrameKey.self,
                        value: proxy.frame(in: .named("gate"))
                    )
                }
            }
    }

    private var flyingMark: some View {
        let travel = interval(progress, 0.78, 0.92, easeInOutCubic)
        let fill = max(0.001, interval(progress, 0, 0.32, easeInOut))
        let size = lerp(heroSize, restSize, travel)
        let tracking = lerp(heroTracking, restTracking, travel)
        let hero = InterFont.size(of: "TRYTERN", size: heroSize, weight: 560, tracking: heroTracking)
        let current = InterFont.size(of: "TRYTERN", size: size, weight: 560, tracking: tracking)
        let center = CGPoint(x: gateFrame.midX, y: gateFrame.midY)
        let x = lerp(center.x - hero.width / 2, markFrame.minX, travel)
        let y = lerp(center.y - hero.height / 2, markFrame.minY, travel)
        return NorthernWord(size: size, tracking: tracking, reveal: fill, period: 5.5)
            .fixedSize()
            .position(x: x + current.width / 2, y: y + current.height / 2)
    }

    private var signIn: some View {
        let appear = interval(progress, 0.86, 1, easeOutCubic)
        return VStack(spacing: 10) {
            ManagerSignIn()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                app.showLogin(.worker)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "phone")
                    Text("Sign in with phone")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .opacity(appear)
        .offset(y: (1 - appear) * 14)
        .allowsHitTesting(progress >= 0.9 || settled)
    }

    private func playIntro() async {
        while gateFrame == .zero || markFrame == .zero {
            try? await Task.sleep(for: .milliseconds(16))
        }
        let start = Date()
        while true {
            let elapsed = Date().timeIntervalSince(start)
            progress = CGFloat(min(1, elapsed / 4.4))
            if progress >= 1 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
        settled = true
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

private func interval(_ time: CGFloat, _ start: CGFloat, _ end: CGFloat, _ curve: (CGFloat) -> CGFloat) -> CGFloat {
    if time <= start { return 0 }
    if time >= end { return 1 }
    return curve((time - start) / (end - start))
}

private func easeInOut(_ t: CGFloat) -> CGFloat {
    t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
}

private func easeInOutCubic(_ t: CGFloat) -> CGFloat {
    t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

private func easeOutCubic(_ t: CGFloat) -> CGFloat {
    1 - pow(1 - t, 3)
}

struct LoginView: View {
    let role: Role
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var code = DialCodes.all[0]
    @State private var number = ""
    @State private var pass = ""
    @State private var asked = false
    @FocusState private var codeFocused: Bool
    @State private var pickingCode = false
    @State private var signingIn = false
    @State private var failure: String?
    private let pill: CGFloat = 52

    private var phoneReady: Bool { number.count == code.length }
    private var codeReady: Bool { pass.count == 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text(role == .worker ? "Sign in with phone" : "Login / Sign up")
                    .font(.system(size: 28, weight: .medium))
                Spacer(minLength: 12)
                Button { app.go(.gate) } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .frame(width: 44, height: 44)
                        .background(palette.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Spacer()
            if role == .owner {
                ownerSignIn
            } else {
                workerSignIn
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas.ignoresSafeArea())
        .sheet(isPresented: $pickingCode) {
            CodeSheet { picked in
                code = picked
                number = String(number.prefix(picked.length))
                pickingCode = false
            }
        }
        .alert("Sign in failed", isPresented: Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private var ownerSignIn: some View {
        ManagerSignIn()
    }

    private var workerSignIn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if asked {
                Text("Enter the 6 digit code your manager gave you.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondary)
                HStack {
                    Text(shownPhone)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.ink)
                    Spacer(minLength: 12)
                    Button("Change") {
                        asked = false
                        pass = ""
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(palette.secondary)
                }
                CodeBoxes(code: $pass, focused: $codeFocused)
                    .onChange(of: pass) { _, value in
                        guard value.count == 6, !signingIn else { return }
                        staffSignIn()
                    }
                continueButton(ready: codeReady, title: "Continue") {
                    staffSignIn()
                }
            } else {
                Text("Use the phone number your manager saved.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondary)
                HStack(spacing: 10) {
                    Button { pickingCode = true } label: {
                        HStack(spacing: 4) {
                            Text(code.dial).font(.body.weight(.semibold))
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 18)
                        .frame(height: pill)
                        .background(palette.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    TextField("00000 00000", text: $number)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .onChange(of: number) { _, value in
                            number = String(value.filter(\.isNumber).prefix(code.length))
                        }
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity)
                        .frame(height: pill)
                        .background(palette.fill, in: Capsule())
                }
                continueButton(ready: phoneReady, title: "Continue") {
                    checkPhone()
                }
            }
        }
    }

    private var shownPhone: String {
        code.dial + " " + number
    }
}

private struct CodeBoxes: View {
    @Binding var code: String
    var focused: FocusState<Bool>.Binding
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused(focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(width: 1, height: 1)
                .onChange(of: code) { _, value in
                    let next = String(value.filter(\.isNumber).prefix(6))
                    if next != value { code = next }
                }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    let digits = Array(code)
                    Text(index < digits.count ? String(digits[index]) : "")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(palette.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(index == code.count && code.count < 6 ? palette.ink : Color.clear, lineWidth: 1.5)
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused.wrappedValue = true }
        }
        .onAppear { focused.wrappedValue = true }
    }
}

private extension LoginView {

    private func continueButton(ready: Bool, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if signingIn {
                    ProgressView().tint(palette.onInverse)
                } else {
                    Text(title).font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(ready ? palette.onInverse : palette.tertiary)
            .frame(maxWidth: .infinity)
            .frame(height: pill)
            .background(ready ? palette.inverse : palette.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!ready || signingIn)
    }

    private func checkPhone() {
        guard phoneReady, !signingIn else { return }
        signingIn = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let phone = code.dial.filter(\.isNumber) + number
        Task {
            do {
                try await StaffAccess.lookup(phone: phone)
                asked = true
            } catch {
                failure = StaffAccess.message(error)
            }
            signingIn = false
        }
    }

    private func staffSignIn() {
        guard codeReady, !signingIn else { return }
        signingIn = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let phone = code.dial.filter(\.isNumber) + number
        Task {
            do {
                try await StaffAccess.signIn(phone: phone, code: pass)
                await app.enterWorker()
            } catch {
                failure = StaffAccess.message(error)
            }
            signingIn = false
        }
    }
}

struct ManagerSignIn: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var signingIn = false
    @State private var failure: String?
    private let pill: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                signIn(.apple)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                    Text("Sign in with Apple")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(palette.onInverse)
                .frame(maxWidth: .infinity)
                .frame(height: pill)
                .background(palette.inverse, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(signingIn)
            Button {
                signIn(.google)
            } label: {
                HStack(spacing: 8) {
                    GoogleMark()
                    Text("Sign in with Google")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: pill)
                .background(palette.fill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(signingIn)
        }
        .alert("Sign in failed", isPresented: Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func signIn(_ provider: OwnerProvider) {
        guard !signingIn else { return }
        signingIn = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            do {
                let person: SignedInPerson
                switch provider {
                case .apple: person = try await OwnerAuth.apple()
                case .google: person = try await OwnerAuth.google()
                }
                app.signedIn = person
                let first = person.givenName.trimmingCharacters(in: .whitespaces)
                let last = person.familyName.trimmingCharacters(in: .whitespaces)
                if !first.isEmpty || !last.isEmpty {
                    app.owner = OwnerIdentity(first: first, last: last, gender: app.owner.gender)
                    app.saveOwner()
                }
                do {
                    if let remote = try await HouseholdCloud.shared.pull() {
                        app.showPortal(remote, role: .owner)
                    } else if HouseholdCloud.pending, !app.portal.homes.isEmpty {
                        app.showPortal(app.portal, role: .owner)
                    } else {
                        app.forgetLocal()
                        app.showSetup(.owner)
                    }
                } catch {
                    if app.portal.homes.isEmpty {
                        app.showSetup(.owner)
                    } else {
                        app.showPortal(app.portal, role: .owner)
                    }
                }
            } catch {
                if !OwnerAuth.cancelled(error) {
                    failure = error.localizedDescription
                }
            }
            signingIn = false
        }
    }
}

private struct GoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: side / 2, y: side / 2)
            let radius = side * 0.34
            let weight = side * 0.20
            let blue = Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255)
            let green = Color(red: 52 / 255, green: 168 / 255, blue: 83 / 255)
            let yellow = Color(red: 251 / 255, green: 188 / 255, blue: 5 / 255)
            let red = Color(red: 234 / 255, green: 67 / 255, blue: 53 / 255)

            func stroke(_ start: Double, _ end: Double, _ color: Color) {
                var path = Path()
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(start),
                    endAngle: .degrees(end),
                    clockwise: false
                )
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: weight, lineCap: .butt))
            }

            stroke(200, 360, red)
            stroke(150, 200, yellow)
            stroke(30, 150, green)
            stroke(-15, 30, blue)
            let bar = CGRect(
                x: center.x - weight * 0.2,
                y: center.y - weight / 2,
                width: radius + weight * 0.55,
                height: weight
            )
            context.fill(Path(bar), with: .color(blue))
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

private enum OwnerProvider {
    case apple
    case google
}

private struct TopFade: View {
    let color: Color
    @State private var island: CGFloat = 59

    var body: some View {
        VStack(spacing: 0) {
            color.frame(height: island)
            LinearGradient(
                colors: [color, color.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .background {
            WindowInset { island = $0 }
        }
    }
}

struct SetupScreen: View {
    @Environment(\.scenePhase) private var phase
    let role: Role
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var model: SetupModel
    @State private var photoItem: PhotosPickerItem?
    @State private var keyboardUp = false

    init(role: Role, addingHome: Bool = false) {
        self.role = role
        let model = SetupModel(role: role)
        model.showsBackHeader = addingHome
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .bottom) {
            SetupCollection(model: model)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [palette.canvas.opacity(0), palette.canvas],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 64)
                .allowsHitTesting(false)
                PromptComposer(model: model)
                    .padding(.horizontal, keyboardUp ? 8 : 22)
                    .padding(.bottom, 8)
                    .background(palette.canvas)
                    .background {
                        ChromeHeight { probe in
                            if model.composerProbe !== probe {
                                model.composerProbe = probe
                            }
                            let height = probe.bounds.height
                            guard height > 1, abs(model.composerInset - height) > 2 else { return }
                            DispatchQueue.main.async {
                                model.composerInset = height
                            }
                        }
                    }
            }
        }
        .background(palette.canvas.ignoresSafeArea())
        .overlay(alignment: .top) {
            TopFade(color: palette.canvas)
        }
        .overlay(alignment: .topLeading) {
            if model.showsBackHeader {
                Button {
                    app.cancelAddHome()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.titleAndIcon)
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .padding(.leading, 16)
                .padding(.top, 4)
            }
        }
        .photosPicker(isPresented: $model.pickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("ternt-profile.jpg")
                try? data.write(to: url, options: .atomic)
                model.photo = (try? await ImagePipeline.shared.image(for: url)) ?? UIImage(data: data)
                photoItem = nil
            }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .community:
                CommunitySheet(model: model)
            case .pickCommunity:
                CommunityPickSheet(model: model)
            case .gender:
                GenderWheel(model: model)
            case .starts(let id):
                TimeWheel(model: model, id: id, ends: false)
            case .ends(let id):
                TimeWheel(model: model, id: id, ends: true)
            case .code(let id):
                CodeSheet { code in
                    model.update(id) { worker in
                        worker.dial = code.dial
                        worker.dialLength = code.length
                        worker.phone = String(worker.phone.prefix(code.length))
                    }
                    model.sheet = nil
                }
            case .kind(let id):
                KindSheet(model: model, id: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                keyboardUp = frame.minY < UIScreen.main.bounds.height - 1
            }
        }
        .onChange(of: phase) { _, phase in
            guard phase == .active else { return }
            model.refreshContacts()
        }
        .task {
            model.onFinish = { state in
                if let photo = model.photo { app.setPhoto(photo) }
                app.showPortal(state, role: role, people: role == .owner)
            }
            if app.addingHome {
                model.openAddHome(from: app.portal)
            } else if role == .owner, let person = app.signedIn {
                model.prepare(person)
                model.start()
            } else {
                model.showNameCard()
            }
        }
    }
}

private struct WindowInset: UIViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.onChange = onChange
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.onChange = onChange
        probe.report()
    }

    final class Probe: UIView {
        var onChange: ((CGFloat) -> Void)?
        private var last: CGFloat = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        func report() {
            let top = window?.safeAreaInsets.top ?? safeAreaInsets.top
            guard top > 1, abs(top - last) > 1 else { return }
            last = top
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(top)
            }
        }
    }
}

private struct ChromeHeight: UIViewRepresentable {
    var onChange: (UIView) -> Void

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.onChange = onChange
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.onChange = onChange
        probe.report()
    }

    final class Probe: UIView {
        var onChange: ((UIView) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
            setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        func report() {
            guard bounds.height > 1, window != nil else { return }
            onChange?(self)
        }
    }
}

