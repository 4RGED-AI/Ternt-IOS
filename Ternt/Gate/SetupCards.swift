import Nuke
import PhotosUI
import SwiftUI

struct TranscriptCell: View {
    let id: UUID
    var model: SetupModel
    @Environment(\.palette) private var palette

    private var row: TranscriptRow? {
        model.rows.first { $0.id == id }
    }

    var body: some View {
        if let row {
            switch row.kind {
            case .welcome:
                Text(model.welcomeText + (model.welcomeDone ? "" : "|"))
                    .font(.body)
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: 320, alignment: .leading)
                    .agentBubble()
            case .reply:
                Text(model.reply ?? "")
                    .font(.body)
                    .ownBubble()
            case .settled(let prompt):
                SettledCard(prompt: prompt.title, lines: model.summary(for: prompt))
                    .frame(maxWidth: 340, alignment: .leading)
            case .active:
                ActiveCard(model: model)
            }
        }
    }
}

private struct SettledCard: View {
    let prompt: String
    let lines: [String]
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(prompt)
                .font(.caption)
                .foregroundStyle(palette.tertiary)
                .padding(.bottom, 5)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(index == 0 ? .body.weight(.semibold) : .callout)
                    .foregroundStyle(index == 0 ? palette.ink : palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentBubble()
    }
}

private struct ActiveCard: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.questionText + (model.formVisible ? "" : "|"))
                .font(.body)
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.formVisible, let prompt = model.active {
                form(prompt)
                Button(model.sequence.last == prompt ? "Done" : "Next") {
                    model.advance()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!model.ready)
            }
        }
        .agentBubble()
    }

    @ViewBuilder
    private func form(_ prompt: Prompt) -> some View {
        switch prompt {
        case .name: NameForm(model: model)
        case .home: HomeForm(model: model)
        case .rooms: RoomsForm(model: model)
        case .workers: WorkersForm(model: model)
        case .pay: PayForm(model: model)
        case .share, .workerShare: ShareForm(model: model, community: model.community?.name)
        case .skill: SkillForm(model: model)
        case .area: AreaForm(model: model)
        }
    }
}

private struct NameForm: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette
    @State private var picker: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $picker, matching: .images) {
                avatar
            }
            .buttonStyle(.plain)
            TextField("First name", text: $model.firstName)
                .textInputAutocapitalization(.words)
                .ternField()
            TextField("Last name", text: $model.lastName)
                .textInputAutocapitalization(.words)
                .ternField()
            ForEach(Gender.allCases) { gender in
                let selected = model.gender == gender
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    model.gender = gender
                } label: {
                    Image(systemName: gender.symbol)
                        .font(.body.weight(.medium))
                        .frame(width: 44, height: 48)
                        .foregroundStyle(selected ? palette.onInverse : palette.ink)
                        .background(selected ? palette.inverse : palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selected ? palette.inverse : palette.line, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(gender.title)
            }
        }
        .onChange(of: picker) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("ternt-profile.jpg")
                try? data.write(to: url, options: .atomic)
                if let image = try? await ImagePipeline.shared.image(for: url) {
                    model.photo = image
                }
            }
        }
    }

    private var avatar: some View {
        ZStack {
            if let photo = model.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .foregroundStyle(palette.ink)
            }
        }
        .frame(width: 48, height: 48)
        .background(palette.surface, in: Circle())
        .overlay { Circle().stroke(palette.line, lineWidth: 1) }
        .clipShape(Circle())
    }
}

private struct HomeForm: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    ForEach(model.communities) { community in
                        Button(community.name) { model.community = community }
                    }
                } label: {
                    HStack {
                        Text(model.community?.name ?? "Choose")
                            .foregroundStyle(model.community == nil ? palette.tertiary : palette.ink)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondary)
                    }
                    .ternField()
                }
                Button {
                    model.sheet = .community
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 48, height: 48)
                        .background(palette.surface, in: Circle())
                        .overlay { Circle().stroke(palette.line, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New community")
            }
            if let community = model.community {
                Text(community.place)
                    .font(.callout)
                    .foregroundStyle(palette.secondary)
                TextField("12 · 1204", text: $model.unit)
                    .ternField()
            }
        }
    }
}

private struct RoomsForm: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            count("Bedrooms", model.bedrooms) { model.setBedrooms($0) }
            count("Living", model.living) { model.living = $0 }
            count("Kitchens", model.kitchens) { value in
                model.kitchens = value
                if value < 2 { model.secondKitchen = nil }
            }
            if model.kitchens > 1 {
                caption("The extra kitchen is")
                chips(SecondKitchen.allCases.map(\.rawValue), selected: model.secondKitchen?.rawValue) { raw in
                    model.secondKitchen = SecondKitchen(rawValue: raw)
                }
            }
            if model.bedrooms > 0 {
                caption("Attached bathroom")
                if model.bedrooms == 1 {
                    chips(["Yes", "No"], selected: model.attached.first == nil ? nil : (model.attached[0] == true ? "Yes" : "No")) { answer in
                        model.attached[0] = answer == "Yes"
                    }
                } else {
                    ForEach(0..<model.bedrooms, id: \.self) { index in
                        HStack {
                            Text("Bedroom \(index + 1)")
                            Spacer()
                            chip("Yes", model.attached[index] == true) { model.attached[index] = true }
                            chip("No", model.attached[index] == false) { model.attached[index] = false }
                        }
                    }
                }
            }
            count("Separate bathrooms", model.separateBaths) { model.separateBaths = $0 }
            count("Powder room", model.powder) { model.powder = $0 }
            caption("Laundry")
            chips(Laundry.allCases.map(\.rawValue), selected: model.laundry?.rawValue) { raw in
                model.laundry = Laundry(rawValue: raw)
            }
            Button(model.moreRooms ? "Hide extra rooms" : "More rooms") {
                model.moreRooms.toggle()
                model.onLayoutChange?()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
            if model.moreRooms {
                ForEach(model.extraNames, id: \.self) { name in
                    count(name, model.extras[name] ?? 0) { value in
                        if value <= 0 { model.extras[name] = nil } else { model.extras[name] = value }
                    }
                }
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(palette.tertiary).padding(.top, 4)
    }

    private func count(_ title: String, _ value: Int, set: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            step(system: "minus", enabled: value > 0) { set(value - 1) }
            Text("\(value)").frame(width: 24).font(.body.weight(.semibold))
            step(system: "plus", enabled: value < 8) { set(value + 1) }
        }
    }

    private func step(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.footnote.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(palette.fill, in: Circle())
                .foregroundStyle(enabled ? palette.ink : palette.tertiary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func chips(_ options: [String], selected: String?, choose: @escaping (String) -> Void) -> some View {
        Flow(spacing: 8) {
            ForEach(options, id: \.self) { option in
                chip(option, selected == option) { choose(option) }
            }
        }
    }

    private func chip(_ title: String, _ selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(selected ? palette.onInverse : palette.ink)
                .background(selected ? palette.inverse : palette.fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct WorkersForm: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(model.workers) { worker in
                workerBlock(worker)
                if worker.id != model.workers.last?.id {
                    Divider()
                }
            }
            Button {
                model.addWorker()
            } label: {
                Label("Add another", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
    }

    private func workerBlock(_ worker: HouseWorker) -> some View {
        let id = worker.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    ForEach(WorkerKind.allCases) { kind in
                        Button(kind.rawValue) { model.update(id) { $0.kind = kind } }
                    }
                } label: {
                    HStack {
                        Text(worker.kind?.rawValue ?? "Category")
                            .foregroundStyle(worker.kind == nil ? palette.tertiary : palette.ink)
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    }
                    .ternField()
                }
                if model.workers.count > 1 {
                    Button {
                        model.removeWorker(id)
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 48, height: 48)
                            .background(palette.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                TextField("First name", text: binding(id, \.first))
                    .ternField()
                TextField("Last name", text: binding(id, \.last))
                    .ternField()
            }
            Text("Phone").font(.caption).foregroundStyle(palette.tertiary)
            HStack(spacing: 8) {
                Button {
                    model.sheet = .code(id)
                } label: {
                    HStack(spacing: 4) {
                        Text(worker.dial).font(.body.weight(.semibold))
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 54)
                    .background(palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                TextField("00000 00000", text: binding(id, \.phone))
                    .keyboardType(.phonePad)
                    .onChange(of: worker.phone) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(worker.dialLength))
                        if digits != value { model.update(id) { $0.phone = digits } }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func binding(_ id: WorkerID, _ keyPath: WritableKeyPath<HouseWorker, String>) -> Binding<String> {
        Binding(
            get: { model.workers[id: id]?[keyPath: keyPath] ?? "" },
            set: { newValue in model.update(id) { $0[keyPath: keyPath] = newValue } }
        )
    }
}

private struct PayForm: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(model.workers) { worker in
                VStack(alignment: .leading, spacing: 8) {
                    Text(worker.name).font(.body.weight(.semibold))
                    Text(worker.kind?.rawValue ?? "").font(.caption).foregroundStyle(palette.tertiary)
                    TextField("18000", text: Binding(
                        get: { model.workers[id: worker.id]?.salary ?? "" },
                        set: { newValue in
                            model.update(worker.id) { $0.salary = newValue.filter(\.isNumber) }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .ternField()
                    HStack(spacing: 8) {
                        timeButton("Starts", worker.starts) { model.sheet = .starts(worker.id) }
                        timeButton("Ends", worker.ends) { model.sheet = .ends(worker.id) }
                    }
                }
            }
        }
    }

    private func timeButton(_ title: String, _ date: Date?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(palette.tertiary)
                Text(date.map(ClockText.label) ?? "Choose")
                    .foregroundStyle(date == nil ? palette.tertiary : palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ShareForm: View {
    @Bindable var model: SetupModel
    var community: String?

    var body: some View {
        VStack(spacing: 8) {
            option("Keep it private", model.share == false) { model.share = false }
            option("Share with \(community ?? "the community")", model.share == true) { model.share = true }
        }
    }

    private func option(_ title: String, _ selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.black : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SkillForm: View {
    @Bindable var model: SetupModel

    var body: some View {
        Flow(spacing: 8) {
            ForEach(WorkerKind.allCases) { kind in
                Button(kind.rawValue) { model.skill = kind }
                    .buttonStyle(.bordered)
                    .tint(model.skill == kind ? Color.primary : Color.secondary)
            }
        }
    }
}

private struct AreaForm: View {
    @Bindable var model: SetupModel

    var body: some View {
        VStack(spacing: 12) {
            TextField("Indiranagar", text: $model.workArea).ternField()
            Menu {
                ForEach(model.cities, id: \.self) { city in
                    Button(city) { model.workCity = city }
                }
            } label: {
                HStack {
                    Text(model.workCity ?? "City")
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .ternField()
            }
        }
    }
}

struct CommunitySheet: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Building name", text: $model.draftName)
                TextField("Street", text: $model.draftStreet)
                TextField("Area", text: $model.draftArea)
                TextField("Pincode", text: $model.draftPin)
                    .keyboardType(.numberPad)
                    .onChange(of: model.draftPin) { _, value in
                        model.draftPin = String(value.filter(\.isNumber).prefix(6))
                        model.lookupPin()
                    }
                LabeledContent("City", value: model.draftCity.isEmpty ? "—" : model.draftCity)
                LabeledContent("State", value: model.draftState.isEmpty ? "—" : model.draftState)
            }
            .navigationTitle("New community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        model.createCommunity()
                        dismiss()
                    }
                    .disabled(!model.canCreateCommunity)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.surface)
    }
}

struct TimeWheel: View {
    @Bindable var model: SetupModel
    let id: WorkerID
    let ends: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            DatePicker(
                ends ? "Ends" : "Starts",
                selection: $date,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "en_US"))
            .navigationTitle(ends ? "Ends" : "Starts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.update(id) { worker in
                            if ends { worker.ends = date } else { worker.starts = date }
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
        .onAppear {
            let existing = ends ? model.workers[id: id]?.ends : model.workers[id: id]?.starts
            date = existing ?? Calendar.current.date(bySettingHour: ends ? 18 : 9, minute: 0, second: 0, of: Date()) ?? Date()
        }
    }
}

struct CodeSheet: View {
    var onPick: (DialCode) -> Void
    @Environment(\.palette) private var palette
    @State private var query = ""

    private var matches: [DialCode] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return DialCodes.all }
        return DialCodes.all.filter {
            $0.name.lowercased().contains(needle) || $0.dial.contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(palette.fillStrong).frame(width: 36, height: 4).padding(.top, 10)
            HStack {
                Text("Country code").font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .padding(14)
                .background(palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if matches.isEmpty {
                        Text("No matches.")
                            .foregroundStyle(palette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(22)
                    } else {
                        ForEach(matches) { code in
                            Button {
                                onPick(code)
                            } label: {
                                HStack {
                                    Text(code.name).foregroundStyle(palette.ink)
                                    Spacer()
                                    Text(code.dial).foregroundStyle(palette.secondary)
                                }
                                .padding(.horizontal, 22)
                                .frame(height: 52)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 22)
                        }
                    }
                }
            }
        }
        .background(palette.surface)
        .presentationDetents([.fraction(0.42), .large])
        .presentationBackground(palette.surface)
        .presentationDragIndicator(.hidden)
    }
}

struct Flow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += row + spacing
                row = 0
            }
            row = max(row, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += row + spacing
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            row = max(row, size.height)
            x += size.width + spacing
        }
    }
}
