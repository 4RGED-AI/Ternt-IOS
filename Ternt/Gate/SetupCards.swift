import Contacts
import MapKit
import SwiftUI
import UIKit

struct TranscriptCell: View {
    let id: UUID
    var model: SetupModel
    @Environment(\.palette) private var palette

    private var row: TranscriptRow? {
        model.rows.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let row {
            switch row.kind {
            case .welcome:
                bubble(revealed(model.welcomeLine, typed: model.welcomeText, ink: palette.ink), leading: true)
            case .agent(let text):
                bubble(Text(text), leading: true)
            case .reply(let text):
                bubble(Text(text), leading: false)
            case .location(let name, let latitude, let longitude):
                HStack(alignment: .bottom, spacing: 0) {
                    Spacer(minLength: 36)
                    LocationBubble(name: name, latitude: latitude, longitude: longitude)
                }
            case .settled(let prompt):
                HStack(alignment: .bottom, spacing: 0) {
                    BubbleFit(limit: 280) {
                        SettledCard(prompt: prompt.title, lines: model.summary(for: prompt))
                    }
                    Spacer(minLength: 36)
                }
            case .active:
                ActiveCard(model: model)
            }
            }
        }
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private func bubble(_ text: Text, leading: Bool) -> some View {
        if leading {
            fitted(text.agentBubble(), leading: true)
        } else {
            fitted(text.ownBubble(), leading: false)
        }
    }

    private func fitted<V: View>(_ content: V, leading: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            if !leading { Spacer(minLength: 36) }
            BubbleFit(limit: 280) {
                content
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if leading { Spacer(minLength: 36) }
        }
    }
}

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ThinkingDots: View {
    @Environment(\.palette) private var palette

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    let cycle = 1.05
                    let local = (time - Double(index) * 0.16).truncatingRemainder(dividingBy: cycle)
                    let lift = local >= 0 && local < 0.34 ? sin(local / 0.34 * .pi) : 0
                    Circle()
                        .fill(palette.secondary)
                        .frame(width: 7, height: 7)
                        .offset(y: -6 * CGFloat(lift))
                }
            }
            .frame(height: 18)
        }
    }
}

private struct LocationBubble: View {
    var name: String
    var latitude: Double
    var longitude: Double
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    palette.fillStrong
                }
            }
            .frame(width: 228, height: 128)
            .clipped()
            Text(name)
                .font(.body)
                .foregroundStyle(palette.onInverse)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 228)
        .background(palette.inverse)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 20,
            bottomLeadingRadius: 20,
            bottomTrailingRadius: 6,
            topTrailingRadius: 20
        ))
        .task(id: "\(latitude),\(longitude),\(colorScheme)") {
            let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
            image = await PlaceSnapshot.image(latitude: latitude, longitude: longitude, style: style)
        }
    }
}

private enum PlaceSnapshot {
    static func image(latitude: Double, longitude: Double, style: UIUserInterfaceStyle) async -> UIImage? {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
        options.size = CGSize(width: 456, height: 256)
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)
        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }
        let point = snapshot.point(for: coordinate)
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size, format: format)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            let pin = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: pin.insetBy(dx: -3, dy: -3)).fill()
            UIColor.black.setFill()
            UIBezierPath(ovalIn: pin).fill()
        }
    }
}

struct ContactHit: Identifiable, Hashable {
    var id: String
    var name: String
    var first: String
    var last: String
    var phone: String
    var dial: String
    var length: Int
    var detail: String
}

enum ContactBook {
    static func search(_ query: String) async -> [ContactHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return [] }
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            guard (try? await store.requestAccess(for: .contacts)) == true else { return [] }
        } else if status != .authorized && status != .limited {
            return []
        }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: trimmed)
        let found = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
        return found.prefix(6).compactMap { contact in
            let first = contact.givenName.trimmingCharacters(in: .whitespaces)
            let last = contact.familyName.trimmingCharacters(in: .whitespaces)
            let name = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let raw = contact.phoneNumbers.first?.value.stringValue ?? ""
            let parsed = phone(raw)
            return ContactHit(
                id: contact.identifier,
                name: name,
                first: first,
                last: last,
                phone: parsed.digits,
                dial: parsed.dial,
                length: parsed.length,
                detail: raw
            )
        }
    }

    private static func phone(_ raw: String) -> (digits: String, dial: String, length: Int) {
        let digits = raw.filter(\.isNumber)
        if digits.count >= 12, digits.hasPrefix("91") {
            return (String(digits.suffix(10)), "+91", 10)
        }
        if digits.count > 10 {
            return (String(digits.suffix(10)), "+91", 10)
        }
        return (digits, "+91", 10)
    }
}

private struct BubbleFit: Layout {
    var limit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let cap = min(proposal.width ?? limit, limit)
        let natural = child.sizeThatFits(.unspecified)
        if natural.width <= cap {
            return natural
        }
        let wrapped = child.sizeThatFits(ProposedViewSize(width: cap, height: nil))
        return CGSize(width: min(wrapped.width, cap), height: wrapped.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let size = sizeThatFits(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews, cache: &cache)
        child.place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: ProposedViewSize(width: size.width, height: size.height))
    }
}

private func revealed(_ full: String, typed: String, ink: Color) -> Text {
    let count = min(typed.count, full.count)
    let end = full.index(full.startIndex, offsetBy: count)
    return Text(String(full[..<end])).foregroundStyle(ink)
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
        .fixedSize(horizontal: false, vertical: true)
        .agentBubble()
    }
}

private struct ActiveCard: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            BubbleFit(limit: 280) {
                Group {
                    if model.thinking {
                        ThinkingDots()
                    } else {
                        revealed(promptLine, typed: model.questionText, ink: palette.ink)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .agentBubble()
            }
            Spacer(minLength: 36)
        }
    }

    private var promptLine: String {
        if !model.asked.isEmpty { return model.asked }
        return model.active?.title ?? model.questionText
    }
}

private final class KeyboardHold {
    weak var field: UITextField?
    var suppressed = false

    func reclaim() {
        guard !suppressed, let field, !field.isFirstResponder else { return }
        field.becomeFirstResponder()
    }
}

private struct ComposerField: UIViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var editable: Bool
    var target: PromptComposer.FieldTarget
    var hold: KeyboardHold
    var ink: UIColor
    var tertiary: UIColor
    var darkKeyboard: Bool
    var onSubmit: (() -> Void)?

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.font = .preferredFont(forTextStyle: .body)
        field.autocapitalizationType = .words
        field.autocorrectionType = .no
        field.returnKeyType = .send
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        context.coordinator.hold = hold
        hold.field = field
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        hold.field = field
        field.textColor = ink
        field.tintColor = ink
        field.keyboardAppearance = darkKeyboard ? .dark : .light
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: tertiary]
        )
        if context.coordinator.target != target {
            context.coordinator.target = target
            field.text = text
        } else if field.text != text, !field.isFirstResponder {
            field.text = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ComposerField?
        var hold: KeyboardHold?
        var target: PromptComposer.FieldTarget?

        func textFieldDidBeginEditing(_ textField: UITextField) {
            hold?.suppressed = false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            let window = textField.window
            guard window?.activeTextField() == nil else { return }
            DispatchQueue.main.async { [hold] in
                guard window?.activeTextField() == nil else { return }
                hold?.suppressed = true
            }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            parent?.editable == true
        }

        @objc func changed(_ field: UITextField) {
            guard parent?.editable == true else { return }
            parent?.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent?.onSubmit?()
            return false
        }
    }
}

private struct FocusFirstField: UIViewRepresentable {
    var token: String
    var hold: KeyboardHold

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard context.coordinator.token != token else { return }
        context.coordinator.token = token
        grab(from: uiView, attempt: 0)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func grab(from view: UIView, attempt: Int) {
        DispatchQueue.main.async {
            guard !hold.suppressed else { return }
            if let window = view.window, let target = window.firstEditableField(excluding: hold.field) {
                if !target.isFirstResponder { target.becomeFirstResponder() }
                return
            }
            guard attempt < 5 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                self.grab(from: view, attempt: attempt + 1)
            }
        }
    }

    final class Coordinator { var token = "" }
}

private extension UIView {
    func activeTextField() -> UITextField? {
        if let field = self as? UITextField, field.isFirstResponder { return field }
        for subview in subviews {
            if let found = subview.activeTextField() { return found }
        }
        return nil
    }

    func firstEditableField(excluding held: UITextField?) -> UITextField? {
        if let field = self as? UITextField, field !== held, field.bounds.height > 2, field.alpha > 0.1, !field.isHidden {
            return field
        }
        if isHidden || alpha < 0.1 { return nil }
        for subview in subviews {
            if let found = subview.firstEditableField(excluding: held) { return found }
        }
        return nil
    }
}

struct PromptComposer: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette
    @State private var query = ""
    @State private var hits: [PlaceHit] = []
    @State private var contactQuery = ""
    @State private var people: [ContactHit] = []
    @State private var panelHeight: CGFloat = 0
    @State private var scratch = ""
    @State private var keyboard = KeyboardHold()
    @State private var meter = VoiceMeter()
    @State private var setupLimit = false

    var body: some View {
        VStack(spacing: 8) {
            if showSearch, query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2, !hits.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(hits) { hit in
                            Button {
                                Task {
                                    guard let community = await CommunityPlaces.details(hit.id) else { return }
                                    query = ""
                                    hits = []
                                    model.choosePlace(community)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title)
                                        .font(.body)
                                        .foregroundStyle(palette.ink)
                                    if !hit.subtitle.isEmpty {
                                        Text(hit.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(palette.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: min(CGFloat(hits.count) * 58 + 12, 300))
                .scrollBounceBehavior(.basedOnSize)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            if showContacts, !people.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(people.prefix(5)) { person in
                        Button {
                            contactQuery = ""
                            people = []
                            model.chooseContact(
                                first: person.first,
                                last: person.last,
                                phone: person.phone,
                                dial: person.dial,
                                length: person.length
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                    .font(.body)
                                    .foregroundStyle(palette.ink)
                                if !person.detail.isEmpty {
                                    Text(person.detail)
                                        .font(.caption)
                                        .foregroundStyle(palette.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            controls
        }
        .fixedSize(horizontal: false, vertical: true)
        .task(id: query) {
            let current = query
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            hits = await CommunityPlaces.search(current, near: model.here)
        }
        .onChange(of: model.homeStep) { _, step in
            guard step == .find, !model.askingCommunity else { return }
            query = ""
            hits = []
        }
        .task(id: contactQuery) {
            let current = contactQuery
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            people = await ContactBook.search(current)
        }
        .onAppear {
            model.keepKeyboard = { keyboard.reclaim() }
            model.dismissKeyboard = {
                keyboard.suppressed = true
                keyboard.field?.resignFirstResponder()
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .onChange(of: fieldTarget) { _, target in
            switch target {
            case .search, .door, .contacts, .idle:
                keyboard.reclaim()
            case .hidden:
                break
            }
        }
    }

    fileprivate enum FieldTarget: Equatable {
        case search, door, contacts, idle, hidden
    }

    private var fieldTarget: FieldTarget {
        if model.askingCommunity { return .hidden }
        if model.active == .done { return .hidden }
        if !model.welcomeDone { return .hidden }
        if model.reply == nil, model.active == nil { return .hidden }
        if !model.formVisible { return .idle }
        if model.active == .home, model.homeStep == .door { return .hidden }
        if model.active == .home { return .search }
        if model.active == .workers, model.helpChoice != nil, !model.helpManual, !model.contactsNeedTyping { return .contacts }
        return .hidden
    }

    private var controls: some View {
        VStack(spacing: 0) {
            if fieldTarget == .hidden {
                choiceControls
            }
            composerBar
                .frame(height: fieldTarget == .hidden ? 0 : nil)
                .clipped()
                .opacity(fieldTarget == .hidden ? 0 : 1)
                .allowsHitTesting(fieldTarget != .hidden)
                .accessibilityHidden(fieldTarget == .hidden)
        }
    }

    @ViewBuilder
    private var choiceControls: some View {
        if model.active == .done {
            if model.formVisible {
                composer {
                    pill("Let's go") { model.continueHome() }
                }
            }
        } else if model.askingCommunity {
            yesNo { model.confirmCommunity($0) }
        } else if model.welcomeDone, model.reply == nil, model.active == nil {
            yesNo { model.choose($0) }
        } else if model.active == .home, model.homeStep == .door {
            doorControls
        } else if model.active == .rooms {
            roomControls
        } else if model.active == .workers, model.helpChoice == nil {
            helpPills
        } else if let prompt = model.active {
            promptPanel(prompt)
        }
    }

    private var doorControls: some View {
        let ready = !model.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("A-12", text: $model.unit)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body)
                    .foregroundStyle(palette.ink)
                    .tint(palette.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(palette.fill, in: Capsule())
                Button {
                    model.submitDoor()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ready ? palette.onInverse : palette.tertiary)
                        .frame(width: 44, height: 44)
                        .background(ready ? palette.inverse : palette.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!ready)
                .accessibilityLabel("Next")
            }
            Text("Floor")
                .font(.caption)
                .foregroundStyle(palette.secondary)
                .padding(.leading, 8)
                .padding(.top, 6)
            Picker("Floor", selection: $model.floor) {
                ForEach(1...40, id: \.self) { number in
                    Text("\(number)").tag(number)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .frame(height: 148)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var showSearch: Bool {
        model.formVisible && model.active == .home && model.homeStep == .find && !model.askingCommunity
    }

    private var showContacts: Bool {
        model.formVisible && model.active == .workers && model.helpChoice != nil && !model.helpManual && !model.contactsNeedTyping
    }

    private var composerBar: some View {
        HStack(spacing: 8) {
            micButton
            ComposerField(
                placeholder: fieldPlaceholder,
                text: fieldText,
                editable: fieldEditable,
                target: fieldTarget,
                hold: keyboard,
                ink: UIColor(palette.ink),
                tertiary: UIColor(palette.tertiary),
                darkKeyboard: palette == .dark,
                onSubmit: {
                    if fieldTarget == .door { model.submitDoor() }
                }
            )
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            fieldTrailing
        }
        .padding(8)
        .glassEffect(.regular, in: .capsule)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var fieldPlaceholder: String {
        if fieldTarget == .search, model.locating { return "Looking nearby" }
        if fieldTarget == .search, model.locationRefused { return "Type your society or address" }
        if !model.placeholder.isEmpty, fieldTarget != .hidden { return model.placeholder }
        switch fieldTarget {
        case .door: return "A-1204"
        case .search: return "Society or address"
        case .contacts: return "Search your contacts"
        case .idle, .hidden: return "Message"
        }
    }

    private var fieldText: Binding<String> {
        switch fieldTarget {
        case .search: $query
        case .door: $model.unit
        case .contacts: $contactQuery
        case .idle, .hidden: $scratch
        }
    }

    @ViewBuilder
    private var fieldTrailing: some View {
        switch fieldTarget {
        case .door:
            let ready = !model.unit.trimmingCharacters(in: .whitespaces).isEmpty
            Button {
                model.submitDoor()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ready ? palette.onInverse : palette.tertiary)
                    .frame(width: 40, height: 40)
                    .background(ready ? palette.inverse : palette.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!ready)
        case .search:
            Button {
                model.holdLayout = true
                model.sheet = .community
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .frame(width: 40, height: 40)
                    .background(palette.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New community")
        case .contacts:
            Button {
                model.helpManual = true
                model.onLayoutChange?()
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .frame(width: 40, height: 40)
                    .background(palette.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add without a contact")
        case .idle, .hidden:
            Image(systemName: "arrow.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.tertiary)
                .frame(width: 40, height: 40)
                .background(palette.fill, in: Circle())
                .accessibilityHidden(true)
        }
    }

    private var fieldEditable: Bool {
        fieldTarget == .search || fieldTarget == .door || fieldTarget == .contacts
    }

    @ViewBuilder
    private var micButton: some View {
        if meter.transcribing {
            ProgressView()
                .frame(width: 40, height: 40)
                .background(palette.fill, in: Circle())
        } else {
            Button {
                if meter.recording {
                    Task { await hear() }
                } else {
                    meter.begin()
                }
            } label: {
                Image(systemName: meter.recording ? "stop.fill" : "mic")
                    .foregroundStyle(meter.recording ? .white : palette.ink)
                    .frame(width: 40, height: 40)
                    .background(meter.recording ? Color.red : palette.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!fieldEditable && !meter.recording)
            .opacity(fieldEditable || meter.recording ? 1 : 0.4)
            .accessibilityLabel(meter.recording ? "Stop" : "Microphone")
        }
    }

    private func hear() async {
        guard let said = await meter.finish(), fieldEditable else { return }
        let field = fieldText
        field.wrappedValue = field.wrappedValue.isEmpty ? said : "\(field.wrappedValue) \(said)"
    }

    @ViewBuilder
    private var roomControls: some View {
        switch model.roomStep {
        case .layout:
            counter("Bedrooms", value: model.bedrooms, low: 1, high: 10, capped: true) { model.setBedrooms($0) } send: { model.submitBedrooms() }
        case .baths:
            counter("Bathrooms", value: model.bathrooms, low: 1, high: 10, capped: true) { model.setBathrooms($0) } send: { model.submitBaths() }
        case .balconies:
            counter("Balconies", value: model.balconies, low: 0, high: 6) { model.setBalconies($0) } send: { model.submitBalconies() }
        case .kitchen:
            composer {
                pill("One kitchen") { model.chooseKitchen(wetAndDry: false) }
                pill("Wet and dry") { model.chooseKitchen(wetAndDry: true) }
            }
        }
    }

    private func counter(_ title: String, value: Int, low: Int, high: Int, capped: Bool = false, nudge: @escaping (Int) -> Void, send: @escaping () -> Void) -> some View {
        composer {
            Text(title)
                .font(.body)
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .padding(.leading, 8)
            Button { nudge(value - 1) } label: {
                Image(systemName: "minus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(value > low ? palette.ink : palette.tertiary)
                    .frame(width: 40, height: 40)
                    .background(palette.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(value <= low)
            Text("\(value)")
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.ink)
                .frame(minWidth: 24)
            Button {
                if capped, value >= high {
                    setupLimit = true
                } else {
                    nudge(value + 1)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(value < high ? palette.ink : palette.tertiary)
                    .frame(width: 40, height: 40)
                    .background(palette.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!capped && value >= high)
            .alert("That's 10", isPresented: $setupLimit) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can add more once the initial setup is complete.")
            }
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.onInverse)
                    .frame(width: 40, height: 40)
                    .background(palette.inverse, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var helpPills: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                pill("Driver") { model.chooseHelp(.driver) }
                pill("Maid") { model.chooseHelp(.maid) }
            }
            HStack(spacing: 8) {
                pill("Housekeeper") { model.chooseHelp(.housekeeper) }
                pill("Cook") { model.chooseHelp(.cook) }
            }
        }
        .padding(8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func yesNo(_ send: @escaping (String) -> Void) -> some View {
        composer {
            pill("No") { send("No") }
            pill("Yes") { send("Yes") }
        }
    }

    private func composer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(8)
            .glassEffect(.regular, in: .capsule)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(palette.fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func promptPanel(_ prompt: Prompt) -> some View {
        let sendsItself = prompt == .share || prompt == .workerShare || prompt == .skill || prompt == .name
        let cap: CGFloat = 440
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                panel(prompt)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: PanelHeightKey.self, value: geo.size.height)
                        }
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: panelHeight > 1 ? min(panelHeight, cap) : nil)
            .fixedSize(horizontal: false, vertical: true)
            .onPreferenceChange(PanelHeightKey.self) { height in
                guard height > 1, abs(panelHeight - height) > 1 else { return }
                panelHeight = height
            }
            if !sendsItself {
                HStack {
                    if prompt == .car {
                        Button {
                            model.skipCar()
                        } label: {
                            Text("Skip")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(palette.ink)
                                .frame(height: 44)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    Button {
                        model.deliver()
                    } label: {
                        Group {
                            if model.sequence.last == prompt {
                                Text("Done")
                                    .font(.body.weight(.semibold))
                                    .padding(.horizontal, 18)
                                    .frame(height: 44)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 44, height: 44)
                            }
                        }
                        .foregroundStyle(model.ready ? palette.onInverse : palette.tertiary)
                        .background(model.ready ? palette.inverse : palette.fill, in: model.sequence.last == prompt ? AnyShape(Capsule()) : AnyShape(Circle()))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.ready)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background {
            FocusFirstField(token: "\(String(describing: prompt))-\(model.helpManual)", hold: keyboard)
        }
    }

    @ViewBuilder
    private func panel(_ prompt: Prompt) -> some View {
        switch prompt {
        case .name: NameForm(model: model)
        case .home: EmptyView()
        case .rooms: RoomsForm(model: model)
        case .tasks: TaskList(model: model)
        case .workers: WorkersForm(model: model)
        case .car: CarForm(model: model)
        case .pay: PayForm(model: model)
        case .done: EmptyView()
        case .more: EmptyView()
        case .share, .workerShare: ShareForm(model: model, community: model.community?.name)
        case .skill: SkillForm(model: model)
        case .area: AreaForm(model: model)
        }
    }
}

private struct TaskList: View {
    @Bindable var model: SetupModel

    var body: some View {
        TaskChecklist(
            tasks: model.currentTasks,
            toggle: model.selectTask,
            flip: model.flipTask,
            rename: model.renameTask,
            add: model.addHouseTask
        )
    }
}

struct TaskChecklist: View {
    var tasks: [HouseTask]
    var toggle: (UUID) -> Void
    var flip: (UUID) -> Void
    var rename: (UUID, String) -> Void
    var add: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tasks) { task in
                HStack(spacing: 8) {
                    Button {
                        toggle(task.id)
                    } label: {
                        Image(systemName: task.on ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundStyle(task.on ? palette.ink : palette.tertiary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(task.on ? "Assigned" : "Not assigned")
                    TextField("Task", text: Binding(
                        get: { task.title },
                        set: { rename(task.id, $0) }
                    ))
                    .font(.body)
                    .foregroundStyle(task.on ? palette.ink : palette.secondary)
                    Button {
                        flip(task.id)
                    } label: {
                        Text(task.cadence.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(palette.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
            Button(action: add) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.body)
                        .foregroundStyle(palette.tertiary)
                        .frame(width: 32, height: 32)
                    Text("Add")
                        .font(.body)
                        .foregroundStyle(palette.tertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add task")
        }
    }
}

private struct LineField: UIViewRepresentable {
    var placeholder: String
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.font = .preferredFont(forTextStyle: .body)
        field.autocapitalizationType = .words
        field.autocorrectionType = .no
        field.clipsToBounds = true
        field.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        let palette = context.environment.palette
        context.coordinator.text = $text
        field.textColor = UIColor(palette.ink)
        field.tintColor = UIColor(palette.ink)
        field.keyboardAppearance = palette == .dark ? .dark : .light
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(palette.tertiary)]
        )
        if field.text != text, !field.isFirstResponder {
            field.text = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        @objc func changed(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }
    }
}

private struct NameForm: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LineField(placeholder: "First name", text: $model.firstName)
                    .ternField()
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                LineField(placeholder: "Last name", text: $model.lastName)
                    .ternField()
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            HStack(spacing: 8) {
                Button {
                    model.holdLayout = true
                    UIView.setAnimationsEnabled(false)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    UIView.setAnimationsEnabled(true)
                    model.pickingPhoto = true
                } label: {
                    avatar
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile photo")
                Button {
                    model.holdLayout = true
                    UIView.setAnimationsEnabled(false)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    UIView.setAnimationsEnabled(true)
                    model.sheet = .gender
                } label: {
                    HStack {
                        Text(model.gender?.title ?? "Gender")
                            .foregroundStyle(model.gender == nil ? palette.tertiary : palette.ink)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondary)
                    }
                    .ternField()
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                Button {
                    model.advance()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(model.ready ? palette.onInverse : palette.tertiary)
                        .frame(width: 48, height: 48)
                        .background(model.ready ? palette.inverse : palette.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!model.ready)
                .accessibilityLabel("Next")
            }
        }
        .ignoresSafeArea(.keyboard)
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
            if model.askingCommunity {
                EmptyView()
            } else if model.community == nil {
                HStack(alignment: .bottom, spacing: 8) {
                    Button {
                        open(.pickCommunity)
                    } label: {
                        HStack {
                            Text(model.locating ? "Looking nearby" : (model.locationRefused ? "Type your society or address" : "Search"))
                                .foregroundStyle(palette.tertiary)
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.secondary)
                        }
                        .ternField()
                    }
                    .buttonStyle(.plain)
                    Button {
                        open(.community)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 48, height: 48)
                            .background(palette.surface, in: Circle())
                            .overlay { Circle().stroke(palette.line, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New community")
                }
            }
            if let community = model.community, !model.askingCommunity {
                if model.homeAsk == nil {
                    Text(community.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.ink)
                }
                Text(community.place)
                    .font(.callout)
                    .foregroundStyle(palette.secondary)
                HStack(spacing: 8) {
                    TextField("Door and Floor no.", text: $model.unit)
                        .ternField()
                    Button {
                        model.advance()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(model.ready ? palette.onInverse : palette.tertiary)
                            .frame(width: 48, height: 48)
                            .background(model.ready ? palette.inverse : palette.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.ready)
                    .accessibilityLabel("Next")
                }
            }
        }
        .onAppear { model.locateCommunity() }
    }

    private func open(_ sheet: SetupSheet) {
        model.holdLayout = true
        UIView.setAnimationsEnabled(false)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        UIView.setAnimationsEnabled(true)
        model.sheet = sheet
    }
}

private struct RoomsForm: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            count("Bedrooms", model.bedrooms, high: 10) { model.setBedrooms($0) }
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
                    let answer = model.attached.first
                    chips(["Yes", "No"], selected: answer == nil ? nil : (answer == true ? "Yes" : "No")) { choice in
                        guard !model.attached.isEmpty else { return }
                        model.attached[0] = choice == "Yes"
                    }
                } else {
                    ForEach(0..<model.bedrooms, id: \.self) { index in
                        let answer = index < model.attached.count ? model.attached[index] : nil
                        HStack {
                            Text("Bedroom \(index + 1)")
                            Spacer()
                            chip("Yes", answer == true) {
                                guard index < model.attached.count else { return }
                                model.attached[index] = true
                            }
                            chip("No", answer == false) {
                                guard index < model.attached.count else { return }
                                model.attached[index] = false
                            }
                        }
                    }
                }
            }
            count("Separate bathrooms", model.separateBaths, high: 10) { model.separateBaths = $0 }
            count("Powder room", model.powder) { model.powder = $0 }
            caption("Laundry")
            chips(Laundry.allCases.map(\.rawValue), selected: model.laundry?.rawValue) { raw in
                model.laundry = Laundry(rawValue: raw)
            }
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        model.moreRooms.toggle()
                    }
                    model.onLayoutChange?()
                } label: {
                    HStack(spacing: 12) {
                        Text("More rooms")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: model.moreRooms ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if model.moreRooms {
                    VStack(spacing: 8) {
                        ForEach(model.extraNames, id: \.self) { name in
                            count(name, model.extras[name] ?? 0) { value in
                                if value <= 0 { model.extras[name] = nil } else { model.extras[name] = value }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .animation(nil, value: model.moreRooms)
            .background(palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(palette.tertiary).padding(.top, 4)
    }

    private func count(_ title: String, _ value: Int, high: Int = 8, set: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            step(system: "minus", enabled: value > 0) { set(value - 1) }
            Text("\(value)").frame(width: 24).font(.body.weight(.semibold))
            step(system: "plus", enabled: value < high) { set(value + 1) }
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
            if let worker = model.currentWorker {
                workerBlock(worker)
            }
        }
    }

    private func workerBlock(_ worker: HouseWorker) -> some View {
        let id = worker.id
        return VStack(alignment: .leading, spacing: 10) {
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

    private func open(_ sheet: SetupSheet) {
        model.holdLayout = true
        UIView.setAnimationsEnabled(false)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        UIView.setAnimationsEnabled(true)
        model.sheet = sheet
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
            ForEach(model.currentWorker.map { [$0] } ?? []) { worker in
                VStack(alignment: .leading, spacing: 8) {
                    Text(worker.name).font(.body.weight(.semibold))
                    Text(worker.kind?.rawValue ?? "").font(.caption).foregroundStyle(palette.tertiary)
                    TextField("Monthly salary", text: Binding(
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

private struct PlateField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> PlateRow {
        let row = PlateRow()
        row.onChange = { context.coordinator.text.wrappedValue = $0 }
        return row
    }

    func updateUIView(_ row: PlateRow, context: Context) {
        let palette = context.environment.palette
        context.coordinator.text = $text
        row.onChange = { context.coordinator.text.wrappedValue = $0 }
        row.apply(ink: UIColor(palette.ink), hint: UIColor(palette.tertiary), dark: palette == .dark)
        if !row.editing { row.show(text) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
    }
}

private final class PlateRow: UIView, UITextFieldDelegate {
    var onChange: (String) -> Void = { _ in }
    private let fields: [UITextField]
    private let slots: [(count: Int, letters: Bool)] = [(2, true), (2, false), (2, true), (4, false)]
    private let hints = ["XX", "00", "XX", "0000"]
    private var writing = false

    var editing: Bool { fields.contains { $0.isFirstResponder } }

    override init(frame: CGRect) {
        let font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        fields = (0..<4).map { _ in
            let field = UITextField()
            field.font = font
            field.borderStyle = .none
            field.backgroundColor = .clear
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            field.autocapitalizationType = .allCharacters
            return field
        }
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: fields)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
        for (index, field) in fields.enumerated() {
            field.tag = index
            field.delegate = self
            field.keyboardType = slots[index].letters ? .asciiCapable : .numberPad
            let width = ceil((hints[index] as NSString).size(withAttributes: [.font: font]).width) + 2
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(ink: UIColor, hint: UIColor, dark: Bool) {
        for (index, field) in fields.enumerated() {
            field.textColor = ink
            field.tintColor = ink
            field.keyboardAppearance = dark ? .dark : .light
            field.attributedPlaceholder = NSAttributedString(
                string: hints[index],
                attributes: [.foregroundColor: hint, .font: field.font as Any]
            )
        }
    }

    func show(_ plate: String) {
        let groups = groups(from: plate)
        writing = true
        for (index, field) in fields.enumerated() where field.text != groups[index] {
            field.text = groups[index]
        }
        writing = false
    }

    func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let index = field.tag
        if string.isEmpty, (field.text ?? "").isEmpty {
            guard index > 0 else { return false }
            let previous = fields[index - 1]
            previous.text = String((previous.text ?? "").dropLast())
            previous.becomeFirstResponder()
            publish()
            return false
        }
        var groups = fields.map { $0.text ?? "" }
        groups[index] = ((groups[index] as NSString).replacingCharacters(in: range, with: string))
        let tail = groups[index...].joined().uppercased().filter { $0.isLetter || $0.isNumber }
        var rest = Array(tail)
        for cursor in index..<slots.count {
            let slot = slots[cursor]
            var chunk = ""
            while chunk.count < slot.count, let next = rest.first {
                let matches = slot.letters ? next.isLetter : next.isNumber
                if !matches { break }
                rest.removeFirst()
                chunk.append(next)
            }
            groups[cursor] = chunk
        }
        writing = true
        for cursor in index..<fields.count {
            fields[cursor].text = groups[cursor]
        }
        writing = false
        if !string.isEmpty {
            let filled = (index..<slots.count).last { !groups[$0].isEmpty } ?? index
            let focus = groups[filled].count >= slots[filled].count && filled + 1 < slots.count ? filled + 1 : filled
            fields[focus].becomeFirstResponder()
        }
        publish()
        return false
    }

    private func publish() {
        onChange(fields.compactMap { field -> String? in
            let text = field.text ?? ""
            return text.isEmpty ? nil : text
        }.joined(separator: " "))
    }

    private func groups(from plate: String) -> [String] {
        var rest = Array(plate.uppercased().filter { $0.isLetter || $0.isNumber })
        return slots.map { slot in
            var chunk = ""
            while chunk.count < slot.count, let next = rest.first {
                rest.removeFirst()
                let matches = slot.letters ? next.isLetter : next.isNumber
                if matches { chunk.append(next) }
            }
            return chunk
        }
    }
}

private struct CarForm: View {
    @Bindable var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Car model, like Swift Dzire", text: $model.carModel)
                .textInputAutocapitalization(.words)
                .ternField()
            PlateField(text: $model.carPlate)
                .ternField()
                .frame(height: 48)
        }
    }
}

private struct ShareForm: View {
    @Bindable var model: SetupModel
    var community: String?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 8) {
            option("Keep it private", model.share == false) {
                model.share = false
                model.deliver()
            }
            option("Share with \(community ?? "the community")", model.share == true) {
                model.share = true
                model.deliver()
            }
        }
    }

    private func option(_ title: String, _ selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .foregroundStyle(selected ? palette.onInverse : palette.ink)
                .background(selected ? palette.inverse : palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SkillForm: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette

    var body: some View {
        Flow(spacing: 8) {
            ForEach(WorkerKind.allCases) { kind in
                let selected = model.skill == kind
                Button(kind.rawValue) {
                    model.skill = kind
                    model.deliver()
                }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .foregroundStyle(selected ? palette.onInverse : palette.ink)
                    .background(selected ? palette.inverse : palette.fill, in: Capsule())
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
        .onDisappear { model.holdLayout = false }
    }
}

struct KindSheet: View {
    @Bindable var model: SetupModel
    let id: WorkerID
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Category")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 8)
            ForEach(WorkerKind.allCases) { kind in
                Button {
                    model.update(id) { $0.kind = kind }
                    dismiss()
                } label: {
                    HStack {
                        Text(kind.rawValue).foregroundStyle(palette.ink)
                        Spacer()
                        if model.workers[id: id]?.kind == kind {
                            Image(systemName: "checkmark").foregroundStyle(palette.ink)
                        }
                    }
                    .padding(.horizontal, 22)
                    .frame(minHeight: 56)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.surface)
        .presentationDetents([.height(360)])
        .presentationBackground(palette.surface)
        .presentationDragIndicator(.visible)
        .onDisappear { model.holdLayout = false }
    }
}

struct CommunityPickSheet: View {
    @Bindable var model: SetupModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [PlaceHit] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Community")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 22)
                .padding(.top, 22)
            TextField("Society or address", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .ternField()
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                        ForEach(hits) { hit in
                            Button {
                                Task {
                                    guard let community = await CommunityPlaces.details(hit.id) else { return }
                                    model.choosePlace(community)
                                    dismiss()
                                }
                            } label: {
                                row(hit.title, hit.subtitle, chosen: false)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ForEach(model.communities) { community in
                            Button {
                                model.choosePlace(community)
                                dismiss()
                            } label: {
                                row(community.name, community.place, chosen: model.community?.id == community.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.surface)
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.surface)
        .presentationDragIndicator(.visible)
        .onDisappear { model.holdLayout = false }
        .task(id: query) {
            let current = query
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            hits = await CommunityPlaces.search(current, near: model.here)
        }
    }

    private func row(_ title: String, _ subtitle: String, chosen: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(palette.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(palette.secondary)
                }
            }
            Spacer()
            if chosen {
                Image(systemName: "checkmark").foregroundStyle(palette.ink)
            }
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 56)
    }
}

struct GenderWheel: View {
    @Bindable var model: SetupModel
    @Environment(\.dismiss) private var dismiss
    @State private var gender: Gender = .female

    var body: some View {
        NavigationStack {
            Picker("Gender", selection: $gender) {
                ForEach(Gender.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .navigationTitle("Gender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        UISelectionFeedbackGenerator().selectionChanged()
                        model.gender = gender
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .onAppear { gender = model.gender ?? .female }
        .onDisappear { model.holdLayout = false }
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
    @State private var detent: PresentationDetent = .fraction(0.42)
    @FocusState private var searching: Bool

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
                .focused($searching)
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
        .presentationDetents([.fraction(0.42), .large], selection: $detent)
        .presentationBackground(palette.surface)
        .presentationDragIndicator(.hidden)
        .onChange(of: searching) { _, focused in
            guard focused else { return }
            detent = .large
        }
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
