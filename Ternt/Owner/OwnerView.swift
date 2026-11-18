import AudioToolbox
import AVFoundation
import Contacts
import ContactsUI
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum OwnerSection: Hashable {
    case home, finance, people, groceries, work, community, ai
}

struct OwnerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var section: OwnerSection = .home
    @State private var menu = false
    @State private var ai = false
    @State private var safeBottom: CGFloat = 34

    var body: some View {
        ZStack(alignment: .bottom) {
            sectionPage
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear
                        .frame(height: max(0, OwnerDock.barHeight + OwnerDock.screenGap - safeBottom))
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ZStack(alignment: .bottom) {
                if menu {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { setMenu(false) }
                }
                OwnerDock(section: $section, menu: $menu) {
                    ai = true
                }
                .padding(.horizontal, 12)
                .padding(.bottom, OwnerDock.screenGap - safeBottom)
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .allowsHitTesting(false)
                    .onAppear { safeBottom = geo.safeAreaInsets.bottom }
                    .onChange(of: geo.safeAreaInsets.bottom) { _, next in safeBottom = next }
            }
            .allowsHitTesting(false)
        }
        .background(palette.canvas)
        .sheet(isPresented: $ai) {
            AIChatDrawer()
        }
        .sheet(item: Binding(get: { app.tasking }, set: { app.tasking = $0 })) { person in
            HelperTasksSheet(person: person)
        }
        .onAppear {
            guard app.openPeople else { return }
            section = .people
            app.openPeople = false
        }
    }

    @ViewBuilder
    private var sectionPage: some View {
        switch section {
        case .home: HomeTab()
        case .finance: FinanceTab()
        case .people: PeopleTab()
        case .groceries: GroceriesTab()
        case .work: WorkTab()
        case .community: CommunityTab()
        case .ai: HomeTab()
        }
    }

    private func setMenu(_ open: Bool) {
        menu = open
    }
}

private struct OwnerDockItem: Identifiable {
    let section: OwnerSection
    let label: String
    let symbol: String
    var id: OwnerSection { section }
}

private struct OwnerDock: View {
    @Binding var section: OwnerSection
    @Binding var menu: Bool
    var openAI: () -> Void
    @Environment(\.palette) private var palette
    @State private var touched: OwnerSection?
    @State private var rowsShown = false
    @State private var pillHeight: CGFloat = OwnerDock.barHeight
    @State private var closeToken = 0
    @State private var barWidth: CGFloat = 0
    @State private var lens: CGFloat = 0
    @State private var dragging = false
    @State private var crossed = 0
    @State private var tick = DockTick()

    static let barHeight: CGFloat = 56
    /// Gap from the physical bottom edge. Sits with the system glass bar, fully on screen.
    static let screenGap: CGFloat = 21

    private let pinned: [OwnerDockItem] = [
        OwnerDockItem(section: .home, label: "Dashboard", symbol: "square.grid.2x2"),
        OwnerDockItem(section: .finance, label: "Finance", symbol: "indianrupeesign"),
        OwnerDockItem(section: .work, label: "Home", symbol: "house")
    ]

    private let menuItems: [OwnerDockItem] = [
        OwnerDockItem(section: .home, label: "Dashboard", symbol: "square.grid.2x2"),
        OwnerDockItem(section: .finance, label: "Finance", symbol: "indianrupeesign"),
        OwnerDockItem(section: .groceries, label: "Groceries", symbol: "cart"),
        OwnerDockItem(section: .work, label: "Home", symbol: "house"),
        OwnerDockItem(section: .community, label: "Community", symbol: "person.3")
    ]

    private var menuHeight: CGFloat {
        CGFloat(menuItems.count) * 56 + 18
    }

    private var dockMotion: Animation { .easeInOut(duration: 0.32) }
    private var lensSpring: Animation { .spring(response: 0.26, dampingFraction: 0.9) }
    private var restingSlot: CGFloat {
        CGFloat(pinned.firstIndex { $0.section == section } ?? pinned.count)
    }
    private var litSlot: Int { Int(lens.rounded()) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            dockPill
                .frame(maxWidth: .infinity)
            aiButton
        }
    }

    private var dockPill: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
                .environment(\.colorScheme, palette == .dark ? .dark : .light)
                .allowsHitTesting(false)
            menuPanel
                .frame(height: menuHeight, alignment: .bottom)
                .opacity(rowsShown ? 1 : 0)
                .allowsHitTesting(rowsShown)
            iconRow
                .opacity(rowsShown ? 0 : 1)
                .allowsHitTesting(!rowsShown)
        }
        .frame(maxWidth: .infinity)
        .frame(height: pillHeight, alignment: .bottom)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(palette == .dark ? 0.35 : 0.08), radius: 12, y: 4)
        .onChange(of: menu) { _, open in
            followMenu(open)
        }
    }

    private var iconRow: some View {
        let slots = CGFloat(pinned.count + 1)
        let slotWidth = barWidth > 0 ? barWidth / slots : 0
        let lensFill = palette == .dark ? Color(white: 0.38) : Color.white
        return ZStack {
            if slotWidth > 0 {
                Capsule()
                    .fill(lensFill)
                    .frame(width: max(0, slotWidth - 6), height: Self.barHeight - 8)
                    .shadow(color: .black.opacity(palette == .dark ? 0.5 : 0.18), radius: 8, y: 2)
                    .offset(x: (lens + 0.5) * slotWidth - barWidth / 2)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 0) {
                ForEach(Array(pinned.enumerated()), id: \.element.id) { index, item in
                    let on = litSlot == index
                    Image(systemName: item.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolVariant(on ? .fill : .none)
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(on ? palette.ink : palette.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(item.label)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityAction { settle(on: index) }
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .contentTransition(.identity)
                    .foregroundStyle(litSlot == pinned.count ? palette.ink : palette.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("More")
                    .accessibilityAction {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        openMenu()
                    }
            }
        }
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { setBarWidth(geo.size.width) }
                    .onChange(of: geo.size.width) { _, next in setBarWidth(next) }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onAppear {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                lens = restingSlot
                crossed = Int(restingSlot.rounded())
            }
        }
        .onChange(of: section) { _, _ in
            guard !dragging else { return }
            let target = restingSlot
            guard abs(lens - target) > 0.01 else { return }
            withAnimation(lensSpring) { lens = target }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    guard barWidth > 1 else { return }
                    let travel = hypot(value.translation.width, value.translation.height)
                    guard travel > 3 else { return }
                    dragging = true
                    let width = barWidth / slots
                    let next = min(slots - 1, max(0, value.location.x / width - 0.5))
                    let slot = Int(next.rounded())
                    if slot != crossed {
                        crossed = slot
                        tick.moved()
                    }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { lens = next }
                }
                .onEnded { value in
                    guard barWidth > 1 else { return }
                    dragging = false
                    let next = slotIndex(at: value.location.x, width: barWidth)
                    settle(on: next)
                }
        )
    }

    private func setBarWidth(_ next: CGFloat) {
        guard next > 0, abs(next - barWidth) > 0.5 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { barWidth = next }
    }

    private var menuPanel: some View {
        let highlight = touched ?? section
        let highlightIndex = menuItems.firstIndex { $0.section == highlight } ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(menuItems) { item in
                let selected = item.section == highlight
                HStack(spacing: 14) {
                    Image(systemName: item.symbol)
                        .font(.body.weight(selected ? .semibold : .regular))
                        .symbolVariant(selected ? .fill : .none)
                        .contentTransition(.identity)
                        .frame(width: 24)
                    Text(item.label)
                        .font(.body.weight(selected ? .semibold : .regular))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(selected ? palette.ink : palette.secondary)
                .padding(.leading, 22)
                .padding(.trailing, 16)
                .frame(height: 50)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityAction { choose(item.section) }
            }
        }
        .background(alignment: .top) {
            Capsule()
                .fill(palette == .dark ? Color(white: 0.38) : Color.white)
                .shadow(color: .black.opacity(palette == .dark ? 0.45 : 0.12), radius: 6, y: 1)
                .frame(height: 50)
                .padding(.horizontal, 4)
                .offset(y: CGFloat(highlightIndex) * 56 + 3)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    let next = menuItems[rowIndex(at: value.location.y)].section
                    guard next != touched else { return }
                    tick.moved()
                    withAnimation(.easeOut(duration: 0.14)) {
                        touched = next
                    }
                }
                .onEnded { value in
                    let next = menuItems[rowIndex(at: value.location.y)].section
                    touched = nil
                    choose(next)
                }
        )
    }

    private func rowIndex(at y: CGFloat) -> Int {
        let index = Int((y - 6) / 56)
        return min(max(index, 0), menuItems.count - 1)
    }

    private func slotIndex(at x: CGFloat, width: CGFloat) -> Int {
        let slots = pinned.count + 1
        guard width > 0 else { return 0 }
        let index = Int(x / (width / CGFloat(slots)))
        return min(max(index, 0), slots - 1)
    }

    private var aiButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            menu = false
            openAI()
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(width: Self.barHeight, height: Self.barHeight)
                .background { Circle().fill(Color.white.opacity(0.001)) }
                .contentShape(Circle())
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .environment(\.colorScheme, palette == .dark ? .dark : .light)
        .accessibilityLabel("AI")
    }

    private func openMenu() {
        tick.prepare()
        var transaction = Transaction(animation: nil)
        withTransaction(transaction) {
            rowsShown = true
            menu = true
        }
    }

    private func followMenu(_ open: Bool) {
        if open {
            closeToken += 1
            rowsShown = true
            tick.prepare()
            withAnimation(dockMotion) { pillHeight = menuHeight }
        } else {
            touched = nil
            closeToken += 1
            let token = closeToken
            withAnimation(dockMotion) {
                pillHeight = Self.barHeight
            } completion: {
                guard token == closeToken, !menu else { return }
                rowsShown = false
            }
        }
    }

    private func settle(on next: Int) {
        let slots = pinned.count + 1
        let target = CGFloat(min(max(next, 0), slots - 1))
        withAnimation(lensSpring) { lens = target }
        crossed = Int(target)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if next < pinned.count {
            section = pinned[next].section
        } else {
            openMenu()
        }
    }

    private func choose(_ next: OwnerSection) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        touched = nil
        section = next
        menu = false
    }
}

private final class DockTick {
    let selection = UISelectionFeedbackGenerator()
    let impact = UIImpactFeedbackGenerator(style: .light)

    func prepare() {
        selection.prepare()
        impact.prepare()
    }

    func moved() {
        selection.selectionChanged()
        impact.impactOccurred(intensity: 0.9)
        prepare()
    }
}

private struct FinanceTab: View {
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            palette.canvas
                .homeSwitcher()
                .navigationTitle("Finance")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
                .toolbarBackground(palette.canvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private struct LineBubble: ViewModifier {
    var mine: Bool

    func body(content: Content) -> some View {
        if mine {
            content.ownBubble()
        } else {
            content.agentBubble()
        }
    }
}

private struct AIThread: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var lines: [AILine]
}

private struct AIChatDrawer: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var text = ""
    @State private var greeting = ""
    @State private var greetingToken = UUID()
    @State private var lines: [AILine] = []
    @State private var thinking = false
    @State private var replyToken = UUID()
    @State private var brain = HouseholdBrain()
    @State private var history: [AIThread] = []
    @State private var threadID = UUID()
    @State private var showingHistory = false
    @State private var meter = VoiceMeter()
    @State private var composerWidth: CGFloat = 0
    @State private var micWidth: CGFloat = 40

    private let welcome = "How can I help you today?"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !greeting.isEmpty {
                            Text(greeting)
                                .foregroundStyle(palette.ink)
                                .agentBubble()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(lines) { line in
                            Text(line.text)
                                .modifier(LineBubble(mine: line.mine))
                                .frame(maxWidth: .infinity, alignment: line.mine ? .trailing : .leading)
                        }
                        if thinking {
                            Text("Thinking")
                                .foregroundStyle(palette.secondary)
                                .agentBubble()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(22)
                }
                ComposerLayout(expanded: fieldExpanded) {
                    micControl
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { micWidth = $0 }
                    messageField
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .foregroundStyle(palette.ink)
                            .frame(width: 40, height: 40)
                            .background(palette.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Send")
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { composerWidth = $0 }
                .padding(8)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(palette.line, lineWidth: 1)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
                .animation(.smooth(duration: 0.22), value: fieldExpanded)
            }
            .background(palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        newChat()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New chat")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHistory = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("Chat history")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .toolbarBackground(palette.canvas, for: .navigationBar)
            .sheet(isPresented: $showingHistory) {
                AIHistorySheet(history: history) { thread in
                    archiveCurrent()
                    greetingToken = UUID()
                    greeting = welcome
                    threadID = thread.id
                    lines = thread.lines
                    showingHistory = false
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onAppear { streamWelcome() }
        .task {
            let saved = await ChatCloud.list(kind: "ai")
            let known = Set(history.map(\.id))
            history += saved.filter { !known.contains($0.id) && $0.id != threadID }.map { chat in
                AIThread(id: chat.id, title: chat.title, lines: chat.lines.map { AILine(text: $0.text, mine: $0.mine) })
            }
        }
        .onDisappear {
            meter.stop()
            let saved = lines
            let id = threadID
            guard !saved.isEmpty else { return }
            Task { await ChatCloud.save(id: id, kind: "ai", lines: saved.map { SavedLine(text: $0.text, mine: $0.mine) }) }
        }
    }

    private var fieldExpanded: Bool {
        guard composerWidth > 1, !text.isEmpty else { return false }
        if text.contains(where: \.isNewline) { return true }
        let font = UIFont.preferredFont(forTextStyle: .body)
        let measured = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let available = composerWidth - micWidth - 40 - 28
        return measured > available
    }

    private var messageField: some View {
        ZStack(alignment: .topLeading) {
            GrowingText(text: $text, ink: UIColor(palette.ink), tint: UIColor(palette.ink), appearance: palette == .dark ? .dark : .light)
            if text.isEmpty {
                Text(meter.error ?? "Message")
                    .font(.body)
                    .foregroundStyle(palette.tertiary)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var micControl: some View {
        HStack(spacing: 8) {
            if meter.transcribing {
                ProgressView()
                    .frame(width: 40, height: 40)
            } else if meter.recording {
                Button {
                    Task {
                        guard let said = await meter.finish() else { return }
                        text = text.isEmpty ? said : "\(text) \(said)"
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.red, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop")
                .padding(.leading, 6)
                HStack(alignment: .center, spacing: 3) {
                    ForEach(meter.samples.indices, id: \.self) { index in
                        Capsule()
                            .fill(palette.ink)
                            .frame(width: 3, height: max(4, meter.samples[index] * 22))
                    }
                }
                .frame(height: 24)
                .padding(.trailing, 8)
            } else {
                Button {
                    meter.begin()
                } label: {
                    Image(systemName: "mic")
                        .foregroundStyle(palette.ink)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Microphone")
            }
        }
        .frame(height: 40)
        .background(palette.fill, in: Capsule())
        .animation(.smooth(duration: 0.28), value: meter.recording)
    }

    private func send() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !thinking else { return }
        let prior = lines
        lines.append(AILine(text: message, mine: true))
        text = ""
        thinking = true
        let token = UUID()
        replyToken = token
        let home = app.portal.active
        Task {
            let reply = await brain.reply(message, earlier: prior, home: home)
            guard replyToken == token else { return }
            lines.append(AILine(text: reply, mine: false))
            thinking = false
            await ChatCloud.save(id: threadID, kind: "ai", lines: lines.map { SavedLine(text: $0.text, mine: $0.mine) })
        }
    }

    private func newChat() {
        archiveCurrent()
        replyToken = UUID()
        thinking = false
        lines = []
        text = ""
        meter.stop()
        streamWelcome()
    }

    private func streamWelcome() {
        let token = UUID()
        greetingToken = token
        greeting = ""
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard greetingToken == token else { return }
            for character in welcome {
                guard greetingToken == token else { return }
                greeting.append(character)
                try? await Task.sleep(for: .milliseconds(14))
            }
        }
    }

    private func archiveCurrent() {
        guard !lines.isEmpty else { return }
        history.removeAll { $0.id == threadID }
        history.insert(AIThread(id: threadID, title: lines[0].text, lines: lines), at: 0)
        threadID = UUID()
    }

}

private struct AIHistorySheet: View {
    let history: [AIThread]
    var open: (AIThread) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if history.isEmpty {
                    Text("No chats yet.")
                        .foregroundStyle(palette.secondary)
                        .listRowBackground(palette.canvas)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, thread in
                        Button {
                            open(thread)
                        } label: {
                            Text(thread.title)
                                .foregroundStyle(palette.ink)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .betweenDivider(palette, last: index == history.count - 1)
                    }
                }
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .listSectionSeparator(.hidden)
            .scrollContentBackground(.hidden)
            .background(palette.canvas)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .toolbarBackground(palette.canvas, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }
}

private struct ComposerLayout: Layout {
    var expanded: Bool
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let mic = subviews[0].sizeThatFits(.unspecified)
        let send = subviews[2].sizeThatFits(.unspecified)
        let row = max(mic.height, send.height)
        if expanded {
            let field = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: width, height: field.height + spacing + row)
        }
        let fieldWidth = max(0, width - mic.width - send.width - spacing * 2)
        let field = subviews[1].sizeThatFits(ProposedViewSize(width: fieldWidth, height: row))
        return CGSize(width: width, height: max(row, field.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let mic = subviews[0].sizeThatFits(.unspecified)
        let send = subviews[2].sizeThatFits(.unspecified)
        if expanded {
            let field = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[1].place(
                at: bounds.origin,
                proposal: ProposedViewSize(width: bounds.width, height: field.height)
            )
            let y = bounds.minY + field.height + spacing
            let row = max(mic.height, send.height)
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: y + (row - mic.height) / 2),
                proposal: ProposedViewSize(width: mic.width, height: mic.height)
            )
            subviews[2].place(
                at: CGPoint(x: bounds.maxX - send.width, y: y + (row - send.height) / 2),
                proposal: ProposedViewSize(width: send.width, height: send.height)
            )
        } else {
            let row = bounds.height
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + (row - mic.height) / 2),
                proposal: ProposedViewSize(width: mic.width, height: mic.height)
            )
            let fieldWidth = max(0, bounds.width - mic.width - send.width - spacing * 2)
            let field = subviews[1].sizeThatFits(ProposedViewSize(width: fieldWidth, height: nil))
            subviews[1].place(
                at: CGPoint(x: bounds.minX + mic.width + spacing, y: bounds.minY + (row - field.height) / 2),
                proposal: ProposedViewSize(width: fieldWidth, height: field.height)
            )
            subviews[2].place(
                at: CGPoint(x: bounds.maxX - send.width, y: bounds.minY + (row - send.height) / 2),
                proposal: ProposedViewSize(width: send.width, height: send.height)
            )
        }
    }
}

private struct GrowingText: UIViewRepresentable {
    @Binding var text: String
    var ink: UIColor
    var tint: UIColor
    var appearance: UIKeyboardAppearance

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.textContainer.lineBreakMode = .byWordWrapping
        view.isScrollEnabled = false
        view.showsVerticalScrollIndicator = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        view.textColor = ink
        view.tintColor = tint
        view.keyboardAppearance = appearance
        context.coordinator.fit(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 1 else { return CGSize(width: 0, height: 36) }
        uiView.bounds.size.width = width
        return CGSize(width: width, height: context.coordinator.fit(uiView))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingText
        init(_ parent: GrowingText) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            fit(textView)
        }

        @discardableResult
        func fit(_ view: UITextView) -> CGFloat {
            let width = max(view.bounds.width, 1)
            let line = view.font?.lineHeight ?? 22
            let inset = view.textContainerInset.top + view.textContainerInset.bottom
            let fitting = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            let cap = ceil(line * 6 + inset)
            let height = min(cap, max(line + inset, fitting.height))
            view.isScrollEnabled = fitting.height > cap + 1
            return height
        }
    }
}

private struct OwnerChrome: UIViewControllerRepresentable {
    var canvas: UIColor

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.canvas = canvas
        controller.apply()
    }

    final class Controller: UIViewController {
        var canvas: UIColor = .black
        weak var circle: UIView?

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            apply()
        }

        func apply() {
            guard let root = view.window else { return }
            var responder: UIResponder? = self
            while let next = responder {
                if let tab = next as? UITabBarController {
                    tab.view.backgroundColor = canvas
                }
                if let navigation = next as? UINavigationController {
                    navigation.view.backgroundColor = canvas
                }
                responder = next.next
            }
            guard let bar = find(UITabBar.self, in: root) else { return }
            style(bar)
            let barFrame = bar.convert(bar.bounds, to: root)
            guard barFrame.height > 20 else { return }
            if circle?.window == nil {
                circle = searchCircle(beside: barFrame, in: root, bar: bar)
            }
            guard let circle else { return }
            let previous = circle.transform
            circle.transform = .identity
            let current = circle.convert(circle.bounds, to: root)
            guard current.height > 20 else {
                circle.transform = previous
                return
            }
            let scale = barFrame.height / current.height
            let dy = barFrame.midY - current.midY
            guard abs(scale - 1) > 0.01 || abs(dy) > 0.5 else {
                circle.transform = previous
                return
            }
            circle.transform = CGAffineTransform(translationX: 0, y: dy)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        }

        private func style(_ bar: UITabBar) {
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            let ink = UIColor.label
            let quiet = UIColor.secondaryLabel
            for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
                layout.normal.iconColor = quiet
                layout.normal.titleTextAttributes = [.foregroundColor: quiet]
                layout.selected.iconColor = ink
                layout.selected.titleTextAttributes = [.foregroundColor: ink]
            }
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.tintColor = ink
            bar.unselectedItemTintColor = quiet
        }

        private func searchCircle(beside barFrame: CGRect, in root: UIView, bar: UITabBar) -> UIView? {
            var best: UIView?
            var bestArea: CGFloat = 0
            func walk(_ view: UIView) {
                if view !== bar, !view.isDescendant(of: bar) {
                    let frame = view.convert(view.bounds, to: root)
                    let side = max(frame.width, frame.height)
                    let ratio = frame.width / max(frame.height, 1)
                    let area = frame.width * frame.height
                    if frame.minX > barFrame.maxX - 12,
                       frame.midY > barFrame.minY - 24,
                       frame.midY < barFrame.maxY + 24,
                       side > 36, side < 120,
                       ratio > 0.72, ratio < 1.35,
                       area > bestArea {
                        best = view
                        bestArea = area
                    }
                }
                for child in view.subviews { walk(child) }
            }
            walk(root)
            return best
        }

        private func find<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
            if let match = root as? T { return match }
            for child in root.subviews {
                if let match = find(type, in: child) { return match }
            }
            return nil
        }
    }
}

private enum DayStamp {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(_ date: Date) -> String {
        formatter.string(from: Calendar.current.startOfDay(for: date))
    }

    static func date(_ key: String) -> Date? {
        formatter.date(from: key)
    }
}

private struct DaySwitch: View {
    @Binding var day: String?
    @Binding var open: Bool
    @Binding var frame: CGRect
    @Environment(\.palette) private var palette

    private var shown: Date {
        if let day, let date = DayStamp.date(day) { return date }
        return Calendar.current.startOfDay(for: .now)
    }

    private var today: Bool {
        Calendar.current.isDateInToday(shown)
    }

    var body: some View {
        HStack(spacing: 10) {
            step("chevron.left", delta: -1)
            Button {
                open = true
            } label: {
                Text(today ? "Today" : shown.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(today ? palette.ink : palette.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        palette == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.92),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            step("chevron.right", delta: 1)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
        .environment(\.colorScheme, palette == .dark ? .dark : .light)
        .fixedSize()
        .overlay {
            GeometryReader { geo in
                Color.clear
                    .allowsHitTesting(false)
                    .onAppear { frame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, next in frame = next }
            }
        }
        .opacity(open ? 0 : 1)
        .accessibilityElement(children: .contain)
    }

    private func step(_ symbol: String, delta: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guard let next = Calendar.current.date(byAdding: .day, value: delta, to: shown) else { return }
            day = DayStamp.key(next)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.ink)
                .frame(width: 22, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Previous day" : "Next day")
    }
}

private struct DayCalendar: View {
    @Binding var day: String?
    @Binding var open: Bool
    @Environment(\.palette) private var palette
    @State private var month: Date

    init(day: Binding<String?>, open: Binding<Bool>) {
        _day = day
        _open = open
        let shown = day.wrappedValue.flatMap(DayStamp.date) ?? .now
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: shown)) ?? shown
        _month = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                monthButton("chevron.left", delta: -1)
                Spacer(minLength: 8)
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 8)
                monthButton("chevron.right", delta: 1)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(weekdayLabels, id: \.offset) { item in
                    Text(item.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.tertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 18)
                }
                ForEach(cells) { cell in
                    dayButton(cell)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }

    private var weekdayLabels: [(offset: Int, text: String)] {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return (0..<7).map { offset in
            let name = symbols[(offset + start) % 7]
            return (offset, String(name.prefix(2)))
        }
    }

    private var cells: [DayCell] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var result = (0..<leading).map { DayCell(id: "pad-\(month.timeIntervalSinceReferenceDate)-\($0)", date: nil) }
        for offset in 0..<count {
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { continue }
            result.append(DayCell(id: DayStamp.key(date), date: date))
        }
        return result
    }

    private func monthButton(_ symbol: String, delta: Int) -> some View {
        Button {
            guard let next = Calendar.current.date(byAdding: .month, value: delta, to: month) else { return }
            month = next
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.ink)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Previous month" : "Next month")
    }

    private func dayButton(_ cell: DayCell) -> some View {
        let date = cell.date
        let selected = date.map { DayStamp.key($0) == (day ?? DayStamp.key(.now)) } ?? false
        let today = date.map { Calendar.current.isDateInToday($0) } ?? false
        return Button {
            guard let date else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            day = DayStamp.key(date)
            open = false
        } label: {
            Text(date.map { String(Calendar.current.component(.day, from: $0)) } ?? "")
                .font(.subheadline.weight(selected || today ? .semibold : .regular))
                .foregroundStyle(selected ? palette.onInverse : (today ? palette.ink : palette.secondary))
                .frame(width: 34, height: 34)
                .background {
                    if selected {
                        Circle().fill(palette.ink)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(date == nil)
        .accessibilityLabel(date?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? "")
    }
}

private struct DayCell: Identifiable {
    var id: String
    var date: Date?
}

private enum HomeArea: String, CaseIterable, Identifiable {
    case home = "Home"
    case car = "Car"
    case kitchen = "Kitchen"
    var id: String { rawValue }
}

private struct AuroraRing: View {
    var progress: Double
    var diameter: CGFloat
    var line: CGFloat
    var font: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(red: 0.48, green: 0.40, blue: 0.82).opacity(0.22), lineWidth: line)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(gradient: Aurora.loop, center: .center),
                    style: StrokeStyle(lineWidth: line, lineCap: progress >= 0.999 ? .butt : .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: font, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Aurora.color(progress))
                .contentTransition(.numericText())
        }
        .frame(width: diameter, height: diameter)
        .animation(.smooth(duration: 0.55), value: progress)
    }
}

private func areaTasks(_ home: PortalHome, _ area: HomeArea) -> [PortalTask] {
    let kitchens = Set(home.rooms.compactMap { room -> String? in
        let category = room.category.isEmpty ? RoomCategory.infer(room.name) : room.category
        let isKitchen = room.name.localizedCaseInsensitiveContains("kitchen")
            || category.caseInsensitiveCompare(RoomCategory.kitchen.rawValue) == .orderedSame
        return isKitchen ? room.name.lowercased() : nil
    })
    let assigned = home.tasks.filter { !$0.worker.isEmpty && !$0.review && $0.memberSide != "by" }
    return assigned.filter { task in
        let kitchen = task.car.isEmpty && kitchens.contains(task.room.lowercased())
        switch area {
        case .car: return !task.car.isEmpty
        case .kitchen: return kitchen
        case .home: return task.car.isEmpty && !kitchen
        }
    }
}

private func areaProgress(_ tasks: [PortalTask], day: String, home: PortalHome) -> Double {
    guard !tasks.isEmpty else { return 0 }
    let done = tasks.filter { taskFinished($0, day: day, home: home) }.count
    return Double(done) / Double(tasks.count)
}

private func taskFinished(_ task: PortalTask, day: String, home: PortalHome) -> Bool {
    let place = task.room.isEmpty ? task.car : task.room
    return home.finished.contains {
        $0.day == day
            && $0.worker.caseInsensitiveCompare(task.worker) == .orderedSame
            && $0.title.caseInsensitiveCompare(task.title) == .orderedSame
            && $0.place.caseInsensitiveCompare(place) == .orderedSame
    }
}

private func works(_ person: PortalPerson, on day: String) -> Bool {
    guard let date = DayStamp.date(day) else { return true }
    let weekday = Calendar.current.component(.weekday, from: date)
    return person.days.isEmpty || person.days.contains(weekday)
}

private struct HomeTab: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var day: String? = DayStamp.key(.now)
    @State private var homeWork = false

    var body: some View {
        let home = app.portal.active
        let selected = day ?? DayStamp.key(.now)
        NavigationStack {
            ScrollView {
                areaRow(day: selected, home: home)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
            }
            .background(palette.canvas)
            .safeAreaInset(edge: .top, spacing: 0) {
                NorthernWord(size: 14.3, tracking: 2.4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(palette.canvas)
            }
            .ownerHeader(day: $day)
            .sensoryFeedback(.selection, trigger: day)
            .navigationDestination(isPresented: $homeWork) {
                HomeDayWorkers(day: day ?? DayStamp.key(.now))
            }
        }
    }

    private func areaRow(day: String, home: PortalHome) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(HomeArea.allCases) { area in
                let tasks = areaTasks(home, area)
                areaCircle(area.rawValue, progress: areaProgress(tasks, day: day, home: home), opens: area == .home)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 18)
    }

    private func areaCircle(_ title: String, progress: Double, opens: Bool) -> some View {
        let mark = VStack(spacing: 8) {
            AuroraRing(progress: progress, diameter: 72, line: 7, font: 15)
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.tertiary)
                            .alignmentGuide(.trailing) { $0[.leading] - 4 }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(Int((progress * 100).rounded())) percent")
        return Group {
            if opens {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    homeWork = true
                } label: {
                    mark
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows workers for this day")
            } else {
                mark
            }
        }
    }
}

private struct HomeDayWorkers: View {
    var day: String
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var opened: PortalPerson?

    private var dateLabel: String {
        guard let date = DayStamp.date(day) else { return day }
        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    var body: some View {
        let home = app.portal.active
        let tasks = areaTasks(home, .home)
        let roster = home.workers.map(\.id)
        let people = home.workers
            .filter { person in
                works(person, on: day) && tasks.contains {
                    $0.worker.caseInsensitiveCompare(person.name) == .orderedSame
                }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        ScrollView {
            VStack(spacing: 10) {
                if people.isEmpty {
                    Text("No home work on \(dateLabel).")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                } else {
                    ForEach(people) { person in
                        Button {
                            opened = person
                        } label: {
                            workerCard(person, tasks: tasks, home: home, roster: roster)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(palette.canvas)
        .navigationTitle("Home")
        .navigationSubtitle(dateLabel)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.backward") { dismiss() }
            }
        }
        .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        .toolbarBackground(palette.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            if let remote = try? await HouseholdCloud.shared.pull() {
                app.replacePortal(remote)
            }
        }
        .sheet(item: $opened) { person in
            WorkerDayDrawer(day: day, person: person)
        }
    }

    private func workerCard(_ person: PortalPerson, tasks: [PortalTask], home: PortalHome, roster: [String]) -> some View {
        let mine = tasks.filter { $0.worker.caseInsensitiveCompare(person.name) == .orderedSame }
        let progress = areaProgress(mine, day: day, home: home)
        return HStack(spacing: 10) {
            AvatarMark(person: person, roster: roster, size: 40)
            Text(person.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            if let kind = person.kind {
                categoryPill(kind)
            }
            Spacer(minLength: 8)
            AuroraRing(progress: progress, diameter: 44, line: 4, font: 11)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(person.name), \(person.kind?.rawValue ?? "Worker"), \(Int((progress * 100).rounded())) percent")
    }
}

private struct WorkerDayDrawer: View {
    var day: String
    var person: PortalPerson
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var preview: ProofLink?
    @State private var opening = ""

    private var home: PortalHome { app.portal.active }

    private var tasks: [PortalTask] {
        areaTasks(home, .home).filter { $0.worker.caseInsensitiveCompare(person.name) == .orderedSame }
    }

    private var places: [String] {
        var seen: [String] = []
        for task in tasks {
            let name = task.room.isEmpty ? "Home" : task.room
            if !seen.contains(name) { seen.append(name) }
        }
        return seen
    }

    private var doneRows: [TaskFinish] {
        tasks.compactMap { finish(for: $0) }
    }

    private var confirmed: Bool {
        !doneRows.isEmpty && doneRows.allSatisfy(\.ok)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if tasks.isEmpty {
                        Text("No tasks for this day.")
                            .font(.callout)
                            .foregroundStyle(palette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Home")
                                .font(.headline)
                                .foregroundStyle(palette.ink)
                            ForEach(places, id: \.self) { place in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(place)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(palette.ink)
                                    ForEach(tasks.filter { ($0.room.isEmpty ? "Home" : $0.room) == place }) { task in
                                        taskRow(task)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        .padding(16)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(palette.canvas)
            .navigationTitle(person.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .navigationSubtitle(confirmed ? "Confirmed" : "")
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .sheet(item: $preview) { link in
                ProofView(url: link.url)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }

    private func taskRow(_ task: PortalTask) -> some View {
        let row = finish(for: task)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.callout)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Text(row == nil ? "To do" : "Done")
                    .font(.caption)
                    .foregroundStyle(row == nil ? palette.secondary : palette.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if task.photo, row?.photo.isEmpty != false {
                Image(systemName: "camera.fill")
                    .font(.caption2)
                    .foregroundStyle(palette.secondary)
            }
            if let path = row?.photo, !path.isEmpty {
                Button {
                    openProof(path, id: task.id)
                } label: {
                    Group {
                        if opening == task.id {
                            ProgressView()
                        } else {
                            Text("Preview")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(palette.fill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .frame(maxWidth: .infinity)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func finish(for task: PortalTask) -> TaskFinish? {
        let place = task.room.isEmpty ? task.car : task.room
        return home.finished.first {
            $0.day == day
                && $0.worker.caseInsensitiveCompare(task.worker) == .orderedSame
                && $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                && $0.place.caseInsensitiveCompare(place) == .orderedSame
        }
    }

    private func openProof(_ path: String, id: String) {
        opening = id
        Task {
            if let url = try? await StaffAccess.proof(path) {
                preview = ProofLink(url: url)
            }
            opening = ""
        }
    }
}

private struct WorkPlace: Identifiable {
    var id: String
    var title: String
    var room = ""
    var roomID = ""
    var car = ""
    var member = ""
}

private struct PlaceEdit: Identifiable {
    var id: String
    var title: String
    var plate = ""
    var room = ""
    var member = ""
    var car = ""
}

private struct WorkTab: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var addingPlace = false
    @State private var addingCar = false
    @State private var addingWorker = false
    @State private var workerDraft = PortalPerson(id: "", name: "", detail: "", phone: "")
    @State private var selecting = false
    @State private var chosen: Set<String> = []
    @State private var aim: TaskHand?
    @State private var confirmingDelete = false
    @State private var place: WorkPlace?
    @State private var renaming: PlaceEdit?
    @State private var homeOpen = true
    @State private var carsOpen = true
    @State private var dropRoom = ""
    @State private var dropWorker = ""
    @State private var aimedWorker = ""
    @State private var dropCar = ""
    @State private var dragging = false
    @State private var draggedTask = ""
    @State private var dragToken = 0
    @State private var dragBook = SelectionDrag()
    @State private var hover = HoverClock()
    @State private var openedWorker: PortalPerson?
    @State private var editing: TaskEdit?
    @State private var contentEdges = StaffEdges()
    @State private var flightContent = CGRect.zero
    @State private var flightHeader = CGRect.zero
    @State private var flightHost = CGRect.zero
    @State private var flightRestY: CGFloat = 0
    @State private var flightMoved: CGFloat = 0
    @State private var staffOffset: CGFloat = 0
    @State private var scroller = DragScroller()
    @State private var frames = FrameBook()

    private var home: PortalHome { app.portal.active }

    private var avatarRoster: [String] {
        home.workers.map(\.id) + home.members.map(\.id)
    }

    private var flightReady: Bool {
        flightContent.width > 1 && flightHeader.height > 1 && flightHost.width > 1 && flightRestY > 0
    }

    /// Header controls are 44pt. The circles land at that height.
    private var headerPill: CGFloat { 44 }

    private var dockScale: CGFloat { headerPill / 56 }

    private var flightProgress: CGFloat {
        guard flightReady, flightTravel > 1 else { return 0 }
        return min(1, max(0, flightMoved / flightTravel))
    }

    private var flightScale: CGFloat {
        1 + (dockScale - 1) * flightProgress
    }

    private var flightTravel: CGFloat {
        guard flightHeader.height > 1, flightRestY > 0 else { return 0 }
        return max(0, flightRestY - flightHeader.minY)
    }

    private var flightX: CGFloat {
        let start = flightContent.minX - flightHost.minX
        let end = flightHeader.minX - flightHost.minX - 2 * dockScale
        return start + (end - start) * flightProgress
    }

    private var flightY: CGFloat {
        let start = flightContent.minY - flightHost.minY
        let end = flightHeader.minY - flightHost.minY - 2 * dockScale
        return start + (end - start) * flightProgress
    }

    private var flightWidth: CGFloat {
        let full = max(flightContent.width, 1)
        return full + (min(240, full) - full) * flightProgress
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    staffRow(size: 56, named: true, plus: true, interactive: flightProgress < 0.02, onPick: aim == nil ? nil : { apply($0) })
                        .opacity(flightProgress < 0.02 ? 1 : 0)
                        .allowsHitTesting(flightProgress < 0.02)
                        .accessibilityHidden(flightProgress >= 0.02)
                        .background {
                            GlobalFrame { frame in
                                trackFlight(frame)
                            }
                        }
                    homeCard
                    carsCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .background(ScrollFinder { scroller.attach($0) })
            }
            .background(palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, _ in
                scroller.settleIfResting()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HomeSwitcher()
                        .padding(.horizontal, 2)
                        .frame(height: headerPill)
                        .glassEffect(.regular, in: .capsule)
                        .opacity(max(0, 1 - flightProgress / 0.7))
                        .allowsHitTesting(flightProgress < 0.35)
                        .overlay {
                            GeometryReader { geo in
                                Color.clear
                                    .allowsHitTesting(false)
                                    .onAppear { rememberHeader(geo.frame(in: .global)) }
                                    .onChange(of: geo.frame(in: .global)) { _, frame in rememberHeader(frame) }
                            }
                        }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        selecting.toggle()
                        if !selecting {
                            chosen = []
                            aim = nil
                        }
                        publishSelection()
                    } label: {
                        Image(systemName: selecting ? "checkmark" : "checkmark.circle")
                    }
                    .accessibilityLabel(selecting ? "Done selecting" : "Select tasks")
                    Menu {
                        Button("Add worker", systemImage: "person.badge.plus") {
                            workerDraft = PortalPerson(id: UUID().uuidString, name: "", detail: "", phone: "")
                            addingWorker = true
                        }
                        Button("Add room", systemImage: "door.left.hand.open") {
                            addingPlace = true
                        }
                        Button("Add car", systemImage: "car") {
                            addingCar = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
            }
            .sheet(isPresented: $addingPlace) {
                RoomSheet(room: nil, taken: home.rooms.map(\.name), extras: home.roomCategories) { app.addRoom($0) }
            }
            .sheet(isPresented: $addingCar) {
                AddCarSheet { app.addCar(model: $0, plate: $1) }
            }
            .sheet(item: $place) { place in
                WorkTasksDrawer(place: place)
            }
            .sheet(item: $editing) { edit in
                WorkerTaskEditor(edit: edit)
            }
            .sheet(isPresented: $addingWorker) {
                NavigationStack {
                    PersonEditor(person: workerDraft, creating: true, drawer: true)
                }
                .presentationDetents([.large])
                .presentationBackground(palette.canvas)
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $openedWorker) { person in
                WorkerDrawer(person: person)
            }
            .safeAreaInset(edge: .bottom) {
                if selecting, !chosen.isEmpty {
                    TaskAimBar(aim: aim, choose: { next in
                        aim = aim == next ? nil : next
                    }, delete: { confirmingDelete = true })
                }
            }
            .onAppear { publishSelection() }
            .onChange(of: selecting) { _, _ in publishSelection() }
            .onChange(of: chosen) { _, _ in publishSelection() }
            .alert("Delete \(chosen.count) \(chosen.count == 1 ? "task" : "tasks")?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    app.removeTasks(tasksToDelete)
                    chosen = []
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $renaming) { edit in
                if !edit.room.isEmpty, let room = home.rooms.first(where: { $0.id == edit.room }) {
                    RoomSheet(room: room, taken: home.rooms.map(\.name), extras: home.roomCategories) { app.saveRoom($0) }
                } else if !edit.member.isEmpty, let member = home.members.first(where: { $0.id == edit.member }) {
                    MemberSheet(member: member) { app.saveMember($0) }
                } else {
                    AddCarSheet(model: edit.title, plate: edit.plate) { app.updateCar(edit.car, model: $0, plate: $1) }
                }
            }
        }
        .background(palette.canvas.ignoresSafeArea())
        .onDisappear { scroller.end() }
        if flightReady, flightProgress > 0.01 {
            staffRow(size: 56, named: true, plus: true, labels: max(0, 1 - flightProgress * 1.8), interactive: true, edges: $contentEdges, token: 1, onPick: aim == nil ? nil : { apply($0) })
                .frame(width: flightWidth, alignment: .leading)
                .scaleEffect(flightScale, anchor: .topLeading)
                .offset(x: flightX, y: flightY)
                .transaction { $0.animation = nil }
        }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { flightHost = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, frame in
                        guard abs(frame.minY - flightHost.minY) > 0.3 || abs(frame.minX - flightHost.minX) > 0.3 || flightHost == .zero else { return }
                        flightHost = frame
                    }
            }
        }
    }

    private func trackFlight(_ frame: CGRect) {
        guard frame.width > 1, frame.minY > 0 else { return }
        let atTop = scroller.atTop
        if flightRestY <= 0 || atTop || frame.minY >= flightRestY - 0.5 {
            if abs(frame.minY - flightRestY) > 0.3 { flightRestY = frame.minY }
            if flightMoved != 0 { flightMoved = 0 }
        } else {
            let moved = max(0, flightRestY - frame.minY)
            if abs(moved - flightMoved) > 0.3 { flightMoved = moved }
        }
        var content = frame
        if flightContent != .zero {
            content.size.height = frame.height
        }
        guard flightContent == .zero
            || abs(content.minX - flightContent.minX) > 0.3
            || abs(content.minY - flightContent.minY) > 0.3
            || abs(content.width - flightContent.width) > 0.3 else { return }
        flightContent = content
    }

    private func rememberHeader(_ frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        guard abs(frame.minY - flightHeader.minY) > 0.3
            || abs(frame.minX - flightHeader.minX) > 0.3
            || abs(frame.height - flightHeader.height) > 0.3
            || flightHeader == .zero else { return }
        flightHeader = frame
    }

    private func staffRow(size: CGFloat, named: Bool, plus: Bool, labels: CGFloat = 1, interactive: Bool = false, edges: Binding<StaffEdges>? = nil, token: Int = 0, onPick: ((PortalPerson) -> Void)? = nil) -> some View {
        let row = ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: named ? 14 : 10) {
                ForEach(home.workers) { person in
                    staffAvatar(person, size: size, named: named, labels: labels, interactive: interactive, token: token, onPick: onPick)
                }
                if plus, labels > 0.05 {
                    addStaffAvatar(size: size)
                        .opacity(labels * (dragging && !dropWorker.isEmpty ? 0.32 : 1))
                        .animation(.smooth(duration: 0.16), value: dropWorker)
                        .allowsHitTesting(labels > 0.4)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 10)
            .padding(.leading, 2)
            .padding(.trailing, 36)
            .background {
                if interactive {
                    StaffScrollDrop(ids: home.workers.map(\.id), column: max(64, size + 8), spacing: named ? 14 : 10, leading: 2, accepts: { id in
                        guard let person = home.workers.first(where: { $0.id == id }) else { return false }
                        guard let task = home.tasks.first(where: { $0.id == draggedTask }) else { return true }
                        return person.takes(task)
                    }, hover: { id in
                        if let id {
                            claimWorker(id)
                        } else if !dropWorker.isEmpty {
                            dropWorker = ""
                            aimedWorker = ""
                        }
                    }, receive: { payload, id in
                        guard let person = home.workers.first(where: { $0.id == id }) else { return }
                        give(payload, to: person)
                    })
                }
            }
            .coordinateSpace(name: "staff")
        }
        let scrolling = row.onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.x
        } action: { _, next in
            if abs(next - staffOffset) > 0.5 { staffOffset = next }
        }
        let base: AnyView = interactive ? AnyView(scrolling) : AnyView(row)
        return Group {
            if let edges {
                base
                    .onScrollGeometryChange(for: StaffEdges.self) { geo in
                        StaffEdges(
                            left: geo.contentOffset.x > 4,
                            right: geo.contentOffset.x + geo.containerSize.width < geo.contentSize.width - 4
                        )
                    } action: { _, next in
                        if next != edges.wrappedValue { edges.wrappedValue = next }
                    }
                    .overlay {
                        HStack(spacing: 0) {
                            staffFade.opacity(edges.wrappedValue.left ? 1 : 0)
                            Spacer(minLength: 0)
                            staffFade.scaleEffect(x: -1).opacity(edges.wrappedValue.right ? 1 : 0)
                        }
                        .allowsHitTesting(false)
                    }
            } else {
                base
            }
        }
    }

    private var staffFade: some View {
        LinearGradient(colors: [palette.canvas, palette.canvas.opacity(0)], startPoint: .leading, endPoint: .trailing)
            .frame(width: 22)
    }

    private func addStaffAvatar(size: CGFloat) -> some View {
        Button {
            workerDraft = PortalPerson(id: UUID().uuidString, name: "", detail: "", phone: "")
            addingWorker = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .frame(width: size, height: size)
                    .background(palette.fill, in: Circle())
                Text("Add")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .frame(width: max(64, size + 8))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add worker")
    }

    private func beginDrag(_ id: String) -> Int {
        dragToken += 1
        StaffMarks.shared.dragging = true
        dragging = true
        draggedTask = id
        dropWorker = ""
        return dragToken
    }

    private func endDrag(_ token: Int) {
        guard dragToken == token else { return }
        StaffMarks.shared.dragging = false
        dragging = false
        draggedTask = ""
        dropWorker = ""
        aimedWorker = ""
        dropRoom = ""
        dropCar = ""
    }

    private func trackWorkers(_ local: CGPoint) {
        guard dragging else { return }
        let direct = worker(at: local)
        let shifted = worker(at: CGPoint(x: local.x + staffOffset, y: local.y))
        let pick: (id: String, distance: CGFloat)?
        if direct?.distance == 0 {
            pick = direct
        } else if shifted?.distance == 0 {
            pick = shifted
        } else if let direct, let shifted {
            pick = direct.distance <= shifted.distance ? direct : shifted
        } else {
            pick = direct ?? shifted
        }
        if let pick, pick.distance <= 28 {
            claimWorker(pick.id)
        }
    }

    private func worker(at point: CGPoint) -> (id: String, distance: CGFloat)? {
        let people = home.workers
        var bestID = ""
        var best = CGFloat.greatestFiniteMagnitude
        for (index, person) in people.enumerated() {
            var frame = frames.values["staff-\(person.id)"] ?? .zero
            guard frame.width > 1, frame.height > 1 else { continue }
            if index == people.count - 1 { frame.size.width += 72 }
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            let distance = hypot(dx, dy)
            if distance < best {
                best = distance
                bestID = person.id
            }
        }
        guard !bestID.isEmpty else { return nil }
        return (bestID, best)
    }

    private func give(_ payload: String, to person: PortalPerson) {
        let ids = taskIDs(payload)
        guard !ids.isEmpty else { return }
        if person.kind == .driver {
            for taskID in ids {
                guard let task = home.tasks.first(where: { $0.id == taskID }), !task.car.isEmpty else { continue }
                app.placeDriver(person.id, onCar: task.car)
            }
        } else {
            for taskID in ids { app.assignStaff(person.id, toTask: taskID) }
        }
    }

    private func claimWorker(_ id: String) {
        guard dragging, !id.isEmpty else { return }
        hover.armWorker {
            guard hover.worker == $0 else { return }
            dropWorker = ""
        }
        guard dropWorker != id else { return }
        aimedWorker = id
        dropWorker = id
        DragFeedback.moved()
    }

    private func releaseWorker(_ id: String) {
        let token = hover.worker
        DispatchQueue.main.async {
            guard hover.worker == token, dropWorker == id else { return }
            dropWorker = ""
        }
    }

    private func claimRoom(_ id: String) {
        hover.armRoom {
            guard hover.room == $0 else { return }
            dropRoom = ""
        }
        guard dropRoom != id else { return }
        dropRoom = id
        DragFeedback.moved()
    }

    private func releaseRoom(_ id: String) {
        let token = hover.room
        DispatchQueue.main.async {
            guard hover.room == token, dropRoom == id else { return }
            dropRoom = ""
        }
    }

    private func staffAvatar(_ person: PortalPerson, size: CGFloat, named: Bool, labels: CGFloat = 1, interactive: Bool = false, token: Int = 0, onPick: ((PortalPerson) -> Void)? = nil) -> some View {
        let count = home.granularTasks(for: person).count
        let blocked = unfit(person)
        let ghost = blocked || (dragging && !dropWorker.isEmpty && person.id != dropWorker)
        let column = VStack(spacing: named ? 6 * labels : 0) {
            ZStack(alignment: .bottomTrailing) {
                personMark(person, size: size)
                Text("\(count)")
                    .font(.system(size: max(8, size * 0.18), weight: .bold))
                    .foregroundStyle(palette.ink)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .background(palette.surface, in: Circle())
                    .overlay { Circle().stroke(palette.line, lineWidth: 0.5) }
                    .offset(x: size * 0.06, y: size * 0.05)
            }
            if named {
                Text(person.name.split(separator: " ").first.map(String.init) ?? person.name)
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .opacity(labels)
                    .frame(width: max(64, size + 8), height: 16 * labels)
                    .clipped()
            }
        }
        .opacity(ghost ? 0.32 : 1)
        .animation(.smooth(duration: 0.16), value: ghost)
        .accessibilityLabel("\(person.name), \(count) \(count == 1 ? "task" : "tasks")")
        return Group {
            if interactive {
                column
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let onPick {
                            if !blocked { onPick(person) }
                        } else {
                            openedWorker = person
                        }
                    }
            } else {
                column
            }
        }
    }

    private var homeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            foldHeader("Home", open: homeOpen, addLabel: "Add room", add: { addingPlace = true }) { homeOpen.toggle() }
            if homeOpen {
                if home.rooms.isEmpty {
                    Text("No rooms yet.")
                        .font(.callout)
                        .foregroundStyle(palette.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(home.rooms) { room in
                            roomTile(room)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.smooth(duration: 0.22), value: homeOpen)
    }

    private var carsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            foldHeader("Cars", open: carsOpen, addLabel: "Add car", add: { addingCar = true }) { carsOpen.toggle() }
            if carsOpen {
                if home.cars.isEmpty {
                    Text("No cars yet.")
                        .font(.callout)
                        .foregroundStyle(palette.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(home.cars) { car in
                            carRow(car)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.smooth(duration: 0.22), value: carsOpen)
    }

    private func foldHeader(_ title: String, open: Bool, addLabel: String, add: @escaping () -> Void, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(addLabel)
            Button(action: toggle) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .animation(.smooth(duration: 0.22), value: open)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Collapse \(title)" : "Expand \(title)")
        }
    }

    private func personMark(_ person: PortalPerson, size: CGFloat) -> some View {
        AvatarMark(person: person, roster: avatarRoster, size: size)
    }

    private func apply(_ person: PortalPerson) {
        guard let aim, fitsChosen(person) else { return }
        app.handTasks(chosen, to: person.id, alone: aim == .move)
        DragFeedback.placed()
        self.aim = nil
        chosen = []
        selecting = false
        publishSelection()
    }

    private func fitsChosen(_ person: PortalPerson) -> Bool {
        home.tasks.contains { chosen.contains($0.id) && person.takes($0) }
    }

    private func unfit(_ person: PortalPerson) -> Bool {
        if dragging, let task = home.tasks.first(where: { $0.id == draggedTask }) {
            return !person.takes(task)
        }
        if aim != nil { return !fitsChosen(person) }
        return false
    }

    private func publishSelection() {
        dragBook.selecting = selecting
        dragBook.chosen = chosen
        for task in home.tasks {
            dragBook.labels[task.id] = task.title
        }
    }

    private var tasksToDelete: Set<String> {
        var ids = chosen
        for task in home.tasks where chosen.contains(task.id) {
            for other in home.tasks where other.room.caseInsensitiveCompare(task.room) == .orderedSame
                && other.title.caseInsensitiveCompare(task.title) == .orderedSame
                && other.car == task.car
                && !other.review {
                ids.insert(other.id)
            }
        }
        return ids
    }

    private func toggle(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        if ids.isSubset(of: chosen) {
            chosen.subtract(ids)
        } else {
            chosen.formUnion(ids)
        }
    }

    private func roomTile(_ room: PortalRoom) -> some View {
        let tasks = home.roomTasks(room.name)
        let ids = Set(tasks.map(\.id))
        let roomOn = !ids.isEmpty && ids.isSubset(of: chosen)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if selecting {
                    Image(systemName: roomOn ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundStyle(roomOn ? palette.ink : palette.tertiary)
                }
                Text(room.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selecting {
                    toggle(ids)
                } else {
                    place = WorkPlace(id: "room-\(room.id)", title: room.name, room: room.name, roomID: room.id)
                }
            }
            ForEach(tasks) { task in
                roomTaskRow(task, room: room)
            }
            if !selecting {
                Button {
                    editing = TaskEdit(
                        id: UUID().uuidString,
                        worker: "",
                        title: "",
                        preferCars: false,
                        rooms: [room.name],
                        cars: []
                    )
                } label: {
                    addTaskRow()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if dropRoom == room.id {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.ink.opacity(0.06))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(palette.ink, lineWidth: 2)
            }
        }
        .animation(.smooth(duration: 0.16), value: dropRoom == room.id)
        .onDrop(of: [.utf8PlainText], delegate: StaffDrop(
            frame: { frames.values[room.id] ?? .zero },
            scroller: scroller,
            enter: { claimRoom(room.id) },
            leave: { releaseRoom(room.id) },
            accept: { payload in
                let ids = taskIDs(payload)
                guard !ids.isEmpty else { return }
                app.moveTasks(Set(ids), toRoom: room.name)
            }
        ))
        .background(GlobalFrame { frames.values[room.id] = $0 })
    }

    private func roomTaskRow(_ task: PortalTask, room: PortalRoom) -> some View {
        let people = home.workers(on: task, room: room.name)
        let on = chosen.contains(task.id)
        return HStack(spacing: 12) {
            if selecting {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(on ? palette.ink : palette.tertiary)
            }
            Text(task.title)
                .font(.callout)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            AvatarGroup(people: people, roster: avatarRoster, size: 24, ring: palette.surface, limit: 3)
                .frame(width: 72, height: 24, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            if selecting {
                toggle([task.id])
            } else {
                editing = edit(for: task)
            }
        }
        .onDrop(of: [.utf8PlainText], delegate: StaffDrop(
            frame: { frames.values[task.id] ?? .zero },
            scroller: scroller,
            enter: { claimRoom(room.id) },
            leave: { releaseRoom(room.id) },
            accept: { payload in
                let ids = taskIDs(payload)
                guard !ids.isEmpty else { return }
                app.moveTasks(Set(ids), toRoom: room.name)
            }
        ))
        .background(GlobalFrame { frames.values[task.id] = $0 })
        .modifier(TaskDrag(
            enabled: !selecting,
            text: { dragBook.payload(prefix: "task:", group: [task.id]) },
            book: dragBook,
            anchor: task.id,
            fallback: task.title,
            began: { beginDrag(task.id) },
            ended: endDrag
        ))
    }

    private func edit(for task: PortalTask) -> TaskEdit {
        let siblings = home.tasks.filter {
            $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                && $0.worker.caseInsensitiveCompare(task.worker) == .orderedSame
                && !$0.review
                && $0.memberSide != "by"
        }
        let rooms = uniqueNames(siblings.map(\.room))
        let cars = uniqueIDs(siblings.map(\.car))
        return TaskEdit(
            id: task.id,
            worker: task.worker,
            title: task.title,
            preferCars: rooms.isEmpty && !cars.isEmpty,
            rooms: rooms,
            cars: cars
        )
    }

    private func carRow(_ car: PortalCar) -> some View {
        let tasks = home.carTasks(car.id)
        let ids = Set(tasks.map(\.id))
        let carOn = !ids.isEmpty && ids.isSubset(of: chosen)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if selecting {
                    Image(systemName: carOn ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundStyle(carOn ? palette.ink : palette.tertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(car.model)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(car.plate)
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let driver = home.workers.first(where: { $0.id == car.driver }) {
                    personMark(driver, size: 28)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selecting {
                    toggle(ids)
                } else {
                    place = WorkPlace(id: "car-\(car.id)", title: car.model, car: car.id)
                }
            }
            ForEach(tasks) { task in
                carTaskRow(task, car: car)
            }
            if !selecting {
                Button {
                    editing = TaskEdit(
                        id: UUID().uuidString,
                        worker: "",
                        title: "",
                        preferCars: true,
                        rooms: [],
                        cars: [car.id]
                    )
                } label: {
                    addTaskRow()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if dropCar == car.id {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.ink.opacity(0.06))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(palette.ink, lineWidth: 2)
            }
        }
        .animation(.smooth(duration: 0.16), value: dropCar == car.id)
        .onDrop(of: [.utf8PlainText], delegate: StaffDrop(
            frame: { frames.values[car.id] ?? .zero },
            scroller: scroller,
            enter: { dropCar = car.id },
            leave: { if dropCar == car.id { dropCar = "" } },
            accept: { payload in
                guard let id = staffPayload(payload), home.workers.first(where: { $0.id == id })?.kind == .driver else { return }
                app.placeDriver(id, onCar: car.id)
            }
        ))
        .background(GlobalFrame { frames.values[car.id] = $0 })
    }

    private func carTaskRow(_ task: PortalTask, car: PortalCar) -> some View {
        let people = home.workers.filter { person in
            home.tasks.contains {
                $0.car == car.id
                    && $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                    && $0.worker.caseInsensitiveCompare(person.name) == .orderedSame
                    && !$0.review
            }
        }
        let on = chosen.contains(task.id)
        return HStack(spacing: 12) {
            if selecting {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(on ? palette.ink : palette.tertiary)
            }
            Text(task.title)
                .font(.callout)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if task.photo {
                Image(systemName: "camera.fill")
                    .font(.caption2)
                    .foregroundStyle(palette.secondary)
            }
            AvatarGroup(people: people, roster: avatarRoster, size: 24, ring: palette.surface, limit: 3)
                .frame(width: 72, height: 24, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            if selecting {
                toggle([task.id])
            } else {
                editing = edit(for: task)
            }
        }
    }

    private func addTaskRow() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.body.weight(.medium))
            Text("Add task")
                .font(.body)
        }
        .foregroundStyle(palette.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct WorkTasksDrawer: View {
    let place: WorkPlace
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var pickingPeople = false
    @State private var roomName = ""
    @State private var editing: TaskEdit?
    @FocusState private var nameFocused: Bool

    private var home: PortalHome { app.portal.active }

    private var linkedRoom: PortalRoom? {
        if !place.roomID.isEmpty {
            return home.rooms.first { $0.id == place.roomID }
        }
        guard !place.room.isEmpty else { return nil }
        return home.rooms.first { $0.name == place.room }
    }

    private var tasks: [PortalTask] {
        if let linkedRoom { return home.roomTasks(linkedRoom.name) }
        if !place.car.isEmpty { return home.carTasks(place.car) }
        return home.tasks.filter { $0.member == place.member }
    }

    private var categoryNames: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for name in RoomCategory.allCases.map(\.rawValue) + home.roomCategories {
            let key = name.lowercased()
            guard seen.insert(key).inserted else { continue }
            list.append(name)
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let linkedRoom {
                        roomFields(linkedRoom)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                    }
                    if linkedRoom == nil {
                        placePills
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                    }
                    VStack(spacing: 16) {
                        if let room = linkedRoom {
                            peopleCard(room)
                        }
                        tasksCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
            .background(palette.canvas)
            .navigationTitle(linkedRoom?.name ?? place.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .sheet(isPresented: $pickingPeople) {
                if let linkedRoom {
                    RoomPeopleSheet(selected: linkedRoom.people) { app.setRoomPeople(linkedRoom.id, $0) }
                }
            }
            .sheet(item: $editing) { edit in
                WorkerTaskEditor(edit: edit)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onAppear {
            if roomName.isEmpty { roomName = linkedRoom?.name ?? "" }
        }
    }

    private func roomFields(_ room: PortalRoom) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                HStack(spacing: 8) {
                    TextField("Name", text: $roomName)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(palette.ink)
                        .tint(palette.ink)
                        .onSubmit { commitRoomName(room) }
                    if !roomName.isEmpty {
                        Button {
                            roomName = ""
                            nameFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(palette.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                Rectangle()
                    .fill(palette.line)
                    .frame(height: 1)
            }
            Menu {
                ForEach(categoryNames, id: \.self) { item in
                    Button(item) { commitRoomCategory(room, item) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Category")
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                    HStack {
                        Text(room.category.isEmpty ? "Category" : room.category)
                            .foregroundStyle(room.category.isEmpty ? palette.tertiary : palette.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.tertiary)
                    }
                    Rectangle()
                        .fill(palette.line)
                        .frame(height: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .onChange(of: nameFocused) { _, on in
            if !on { commitRoomName(room) }
        }
    }

    private func commitRoomName(_ room: PortalRoom) {
        let trimmed = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare(room.name) != .orderedSame else {
            roomName = room.name
            return
        }
        var next = room
        next.name = trimmed
        app.saveRoom(next)
    }

    private func commitRoomCategory(_ room: PortalRoom, _ category: String) {
        guard category.caseInsensitiveCompare(room.category) != .orderedSame else { return }
        var next = room
        next.category = category
        app.saveRoom(next)
    }

    private var placePills: some View {
        PillFlow(spacing: 8) {
            if !place.member.isEmpty {
                metaPill(place.title, symbol: "person")
                if let member = home.members.first(where: { $0.id == place.member }), !member.relation.isEmpty {
                    metaPill(member.relation, symbol: "person.2")
                }
            }
            if !place.car.isEmpty {
                metaPill(place.title, symbol: "car")
                if let car = home.cars.first(where: { $0.id == place.car }), !car.plate.isEmpty {
                    metaPill(car.plate, symbol: "numbersign")
                }
            }
            if let room = linkedRoom {
                ForEach(room.people, id: \.self) { id in
                    if let person = pillPerson(id) {
                        metaPill(person.name, symbol: "person", dot: person.kind?.pill)
                    }
                }
                Button {
                    pickingPeople = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.ink)
                        .frame(width: 26, height: 26)
                        .background(pillFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add person")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func pillPerson(_ id: String) -> (name: String, kind: WorkerKind?, relation: String)? {
        if let worker = home.workers.first(where: { $0.id == id }) {
            return (worker.name, worker.kind, "")
        }
        if let member = home.members.first(where: { $0.id == id }) {
            return (member.name, nil, member.relation)
        }
        return nil
    }

    private func peopleCard(_ room: PortalRoom) -> some View {
        let assigned = home.people(in: room)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(assigned) { person in
                HStack(spacing: 12) {
                    AvatarMark(person: person, roster: home.workers.map(\.id) + home.members.map(\.id), size: 32)
                    Text(person.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let kind = person.kind {
                        categoryPill(kind)
                    } else if !person.detail.isEmpty, person.detail != "Owner" {
                        Text(person.detail)
                            .font(.caption)
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(palette.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button { pickingPeople = true } label: {
                addLabel("Add person")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var tasksCard: some View {
        VStack(spacing: 8) {
            ForEach(tasks) { task in
                let people = linkedRoom.map { home.workers(on: task, room: $0.name) } ?? []
                Button {
                    editing = edit(for: task)
                } label: {
                    HStack(spacing: 12) {
                        Text(task.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if task.photo {
                            Image(systemName: "camera.fill")
                                .font(.caption2)
                                .foregroundStyle(palette.secondary)
                        }
                        AvatarGroup(people: people, roster: home.workers.map(\.id) + home.members.map(\.id), size: 24, ring: palette.canvas, limit: 3)
                            .frame(width: 72, height: 24, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                    .background(palette.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button {
                editing = TaskEdit(
                    id: UUID().uuidString,
                    worker: "",
                    title: "",
                    preferCars: linkedRoom == nil && !place.car.isEmpty,
                    rooms: linkedRoom.map { [$0.name] } ?? [],
                    cars: place.car.isEmpty ? [] : [place.car]
                )
            } label: {
                addLabel("Add task")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func edit(for task: PortalTask) -> TaskEdit {
        let siblings = home.tasks.filter {
            $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                && $0.worker.caseInsensitiveCompare(task.worker) == .orderedSame
                && !$0.review
                && $0.memberSide != "by"
        }
        let rooms = uniqueNames(siblings.map(\.room))
        let cars = uniqueIDs(siblings.map(\.car))
        return TaskEdit(
            id: task.id,
            worker: task.worker,
            title: task.title,
            preferCars: rooms.isEmpty && !cars.isEmpty,
            rooms: rooms,
            cars: cars
        )
    }

    private func addLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.body.weight(.medium))
            Text(title)
                .font(.body)
        }
        .foregroundStyle(palette.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metaPill(_ title: String, symbol: String, dot: Color? = nil, muted: Bool = false) -> some View {
        HStack(spacing: 6) {
            if let dot {
                Circle().fill(dot).frame(width: 8, height: 8)
            } else {
                Image(systemName: symbol)
                    .font(.caption2)
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(muted ? palette.secondary : palette.ink)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(pillFill, in: Capsule())
    }

    private var pillFill: Color {
        palette == .dark ? palette.fillStrong : palette.surface
    }
}

private struct RoomPeopleSheet: View {
    var selected: [String]
    var save: ([String]) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String>

    init(selected: [String], save: @escaping ([String]) -> Void) {
        self.selected = selected
        self.save = save
        _chosen = State(initialValue: Set(selected))
    }

    private var home: PortalHome { app.portal.active }

    var body: some View {
        NavigationStack {
            List {
                if home.workers.isEmpty && home.members.isEmpty {
                    Text("No people yet.")
                        .foregroundStyle(palette.secondary)
                        .listRowBackground(palette.canvas)
                        .listRowSeparator(.hidden)
                }
                ForEach(home.workers) { person in
                    personRow(person.id, name: person.name) {
                        if let kind = person.kind {
                            categoryPill(kind)
                        }
                    }
                }
                ForEach(home.members) { member in
                    personRow(member.id, name: member.name) {
                        if !member.relation.isEmpty {
                            Text(member.relation)
                                .font(.caption)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .background(palette.canvas)
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(home.workers.map(\.id).filter { chosen.contains($0) } + home.members.map(\.id).filter { chosen.contains($0) })
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }

    private func personRow<Pill: View>(_ id: String, name: String, @ViewBuilder pill: () -> Pill) -> some View {
        let on = chosen.contains(id)
        return Button {
            toggle(id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? palette.ink : palette.tertiary)
                Text(name)
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 8)
                pill()
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .listRowBackground(palette.canvas)
        .listRowSeparatorTint(palette.line)
    }

    private func toggle(_ id: String) {
        if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
    }
}

private struct TaskForm: View {
    var drafts: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var detail: String
    @State private var worker: String
    @State private var room: String
    @State private var car: String
    @State private var member: String
    @State private var memberSide: String
    @State private var pick: TaskPick?
    @FocusState private var focused: Bool
    private let original: PortalTask

    init(task: PortalTask, drafts: Bool) {
        self.drafts = drafts
        original = task
        _title = State(initialValue: task.title)
        _detail = State(initialValue: task.detail)
        _worker = State(initialValue: task.worker)
        _room = State(initialValue: task.room)
        _car = State(initialValue: task.car)
        _member = State(initialValue: task.member)
        _memberSide = State(initialValue: task.memberSide)
    }

    private var home: PortalHome { app.portal.active }
    private var ready: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var byThem: Bool { memberSide == "by" }
    private var workerKind: WorkerKind? { home.workers.first { $0.name == worker }?.kind }
    private var memberName: String { home.members.first { $0.id == member }?.name ?? "" }
    private var carName: String { home.cars.first { $0.id == car }?.model ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TextField("Task", text: $title, axis: .vertical)
                    .focused($focused)
                    .font(.title.weight(.bold))
                    .foregroundStyle(palette.ink)
                    .tint(palette.ink)
                    .lineLimit(1...4)
                if drafts {
                    description
                        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                } else {
                    pills
                    description
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(palette.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if drafts {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        commit()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!ready)
                }
            }
        }
        .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        .toolbarBackground(palette.canvas, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if drafts {
                pills
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(palette.canvas)
            }
        }
        .sheet(item: $pick) { pick in
            TaskPickSheet(pick: pick, home: home, worker: $worker, room: $room, car: $car, memberSide: $memberSide)
        }
        .onAppear {
            if drafts { focused = true }
        }
        .onDisappear {
            if !drafts, pick == nil { commit() }
        }
    }

    private var description: some View {
        TextField("Description", text: $detail, axis: .vertical)
            .font(.body)
            .foregroundStyle(palette.ink)
            .tint(palette.ink)
            .lineLimit(2...16)
    }

    private var pills: some View {
        PillFlow(spacing: 8) {
            if !member.isEmpty {
                taskPill(memberName.isEmpty ? "Person" : memberName, symbol: "person", muted: false)
                taskPill(byThem ? "By them" : "For them", symbol: byThem ? "person.fill" : "person.badge.plus", muted: false) {
                    pick = .purpose
                }
            }
            if member.isEmpty || !byThem {
                taskPill(worker.isEmpty ? "Who" : worker, symbol: "person", dot: workerKind?.pill, muted: worker.isEmpty) {
                    pick = .who
                }
            }
            if !room.isEmpty {
                taskPill(room, symbol: "house", muted: false) { pick = .room }
            }
            if !car.isEmpty {
                taskPill(carName.isEmpty ? "Car" : carName, symbol: "car", muted: carName.isEmpty) { pick = .car }
            }
        }
        .padding(drafts ? 0 : 10)
        .background {
            if !drafts {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.fill)
            }
        }
    }

    private func taskPill(_ title: String, symbol: String, dot: Color? = nil, muted: Bool, action: (() -> Void)? = nil) -> some View {
        let label = HStack(spacing: 6) {
            if let dot {
                Circle().fill(dot).frame(width: 8, height: 8)
            } else {
                Image(systemName: symbol)
                    .font(.caption)
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.subheadline)
        .foregroundStyle(muted ? palette.secondary : palette.ink)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(palette.surface, in: Capsule())

        return Group {
            if let action {
                Button(action: action) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
    }

    private func commit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = original
        next.title = trimmed
        next.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        next.worker = byThem ? "" : worker
        next.room = room
        next.car = car
        next.member = member
        next.memberSide = member.isEmpty ? "" : (byThem ? "by" : "for")
        guard next != original else { return }
        app.saveTask(next)
    }
}

private enum TaskPick: String, Identifiable {
    case who, purpose, room, car
    var id: String { rawValue }
    var title: String {
        switch self {
        case .who: "Who"
        case .purpose: "Purpose"
        case .room: "Home"
        case .car: "Car"
        }
    }
}

private struct TaskPickSheet: View {
    let pick: TaskPick
    let home: PortalHome
    @Binding var worker: String
    @Binding var room: String
    @Binding var car: String
    @Binding var memberSide: String
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                switch pick {
                case .who:
                    pickRow("None", chosen: worker.isEmpty) { worker = "" }
                    ForEach(home.workers) { person in
                        pickRow(person.name, chosen: worker == person.name) {
                            worker = person.name
                            if memberSide == "by" { memberSide = "for" }
                        }
                    }
                case .purpose:
                    pickRow("For them", chosen: memberSide != "by") { memberSide = "for" }
                    pickRow("By them", chosen: memberSide == "by") {
                        memberSide = "by"
                        worker = ""
                    }
                case .room:
                    ForEach(home.rooms) { item in
                        pickRow(item.name, chosen: room == item.name) { room = item.name }
                    }
                case .car:
                    ForEach(home.cars) { item in
                        pickRow(item.model, chosen: car == item.id) { car = item.id }
                    }
                }
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .background(palette.canvas)
            .navigationTitle(pick.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }

    private func pickRow(_ title: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(palette.ink)
                Spacer()
                if chosen {
                    Image(systemName: "checkmark")
                        .foregroundStyle(palette.ink)
                }
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(palette.canvas)
        .listRowSeparatorTint(palette.line)
    }
}

private struct PillFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
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
            if x > bounds.minX, x + size.width > bounds.maxX {
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

private struct CategorySheet: View {
    var taken: [String]
    var save: (String) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    private var ready: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !taken.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Category")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                HStack(spacing: 8) {
                    TextField("Name", text: $name)
                        .focused($focused)
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(palette.ink)
                        .tint(palette.ink)
                    if !name.isEmpty {
                        Button {
                            name = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(palette.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                Rectangle()
                    .fill(palette.line)
                    .frame(height: 1)
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.canvas)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(name)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!ready)
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }
}

private struct RoomSheet: View {
    var room: PortalRoom?
    var taken: [String]
    var extras: [String] = []
    var save: (PortalRoom) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var category: String
    @State private var name: String
    @State private var naming: Bool
    @State private var pickingCategory = false
    @FocusState private var focused: Bool

    var preset: String?
    init(room: PortalRoom?, taken: [String], extras: [String] = [], preset: String? = nil, save: @escaping (PortalRoom) -> Void) {
        self.room = room
        self.taken = taken
        self.extras = extras
        self.preset = preset
        self.save = save
        if let preset, room == nil {
            _category = State(initialValue: preset)
            _name = State(initialValue: Self.suggestion(preset, taken: taken, current: nil))
            _naming = State(initialValue: true)
        } else {
            _category = State(initialValue: room?.category ?? "")
            _name = State(initialValue: room?.name ?? "")
            _naming = State(initialValue: room != nil)
        }
    }

    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !category.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if pickingCategory || (room == nil && !naming) {
                    categoryList
                } else {
                    namePage
                }
            }
            .background(palette.canvas)
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onAppear { if naming { focused = true } }
    }

    private var categoryList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(categoryChoices.enumerated()), id: \.offset) { index, item in
                    Button {
                        category = item
                        if room == nil { name = Self.suggestion(item, taken: taken, current: room?.name) }
                        naming = true
                        pickingCategory = false
                    } label: {
                        Text(item)
                            .font(.body)
                            .foregroundStyle(palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .overlay(alignment: .bottom) {
                                if index < categoryChoices.count - 1 {
                                    Rectangle()
                                        .fill(palette.line)
                                        .frame(height: 1)
                                        .padding(.horizontal, 20)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    if pickingCategory {
                        pickingCategory = false
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: pickingCategory ? "chevron.left" : "xmark")
                }
                .accessibilityLabel(pickingCategory ? "Back" : "Close")
            }
        }
    }

    private var namePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                HStack(spacing: 8) {
                    TextField("Name", text: $name)
                        .focused($focused)
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(palette.ink)
                        .tint(palette.ink)
                    if !name.isEmpty {
                        Button {
                            name = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(palette.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                Rectangle()
                    .fill(palette.line)
                    .frame(height: 1)
            }
            Button {
                pickingCategory = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Category")
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                    HStack {
                        Text(category.isEmpty ? "Category" : category)
                            .foregroundStyle(category.isEmpty ? palette.tertiary : palette.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.tertiary)
                    }
                    Rectangle()
                        .fill(palette.line)
                        .frame(height: 1)
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Room")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if room == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        naming = false
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                }
            } else {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    save(PortalRoom(id: room?.id ?? "", name: name, category: category))
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .disabled(!ready)
            }
        }
        .onAppear { focused = true }
    }

    private var categoryChoices: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for name in RoomCategory.allCases.map(\.rawValue) + extras {
            let key = name.lowercased()
            guard seen.insert(key).inserted else { continue }
            list.append(name)
        }
        return list
    }

    private static func suggestion(_ category: String, taken: [String], current: String?) -> String {
        let names = taken.filter { $0.caseInsensitiveCompare(current ?? "") != .orderedSame }
        if !names.contains(where: { $0.caseInsensitiveCompare(category) == .orderedSame }) { return category }
        var number = 2
        while names.contains(where: { $0.caseInsensitiveCompare("\(category) \(number)") == .orderedSame }) {
            number += 1
        }
        return "\(category) \(number)"
    }
}

private struct AddRoomSheet: View {
    var heading: String
    var save: (String) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var focused: Bool

    init(heading: String, name: String = "", save: @escaping (String) -> Void) {
        self.heading = heading
        self.save = save
        _name = State(initialValue: name)
    }

    var body: some View {
        NavigationStack {
            TextField("Name", text: $name)
                .focused($focused)
                .textInputAutocapitalization(.words)
                .foregroundStyle(palette.ink)
                .tint(palette.ink)
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(palette.canvas)
                .navigationTitle(heading)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            save(name)
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.height(240)])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }
}

private struct MemberSheet: View {
    var member: PortalMember?
    var save: (PortalMember) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var relation: String
    @State private var born: Date?
    @State private var choosingRelation = false
    @State private var choosingBorn = false
    @FocusState private var focused: Bool

    init(member: PortalMember?, save: @escaping (PortalMember) -> Void) {
        self.member = member
        self.save = save
        _name = State(initialValue: member?.name ?? "")
        _relation = State(initialValue: member?.relation ?? "")
        _born = State(initialValue: member?.born)
    }

    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !relation.isEmpty && born != nil
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                field("Name", text: $name)
                Button {
                    choosingRelation = true
                } label: {
                    choice("Who", value: relation.isEmpty ? "Who they are" : relation, filled: !relation.isEmpty)
                }
                .buttonStyle(.plain)
                Button {
                    choosingBorn = true
                } label: {
                    choice("Born", value: bornText, filled: born != nil)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.canvas)
            .navigationTitle("Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(PortalMember(id: member?.id ?? "", name: name, relation: relation, born: born))
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!ready)
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .sheet(isPresented: $choosingRelation) {
                RelationWheel(relation: $relation)
            }
            .sheet(isPresented: $choosingBorn) {
                BirthWheel(born: $born)
            }
        }
        .presentationDetents([.height(420)])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onAppear { if member == nil { focused = true } }
    }

    private var bornText: String {
        guard let born else { return "Date of birth" }
        let formatted = born.formatted(.dateTime.day().month(.abbreviated).year())
        let age = PortalMember(id: "", name: "", born: born).ageLabel
        return age.isEmpty ? formatted : "\(formatted) · \(age)"
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.secondary)
            TextField(title, text: text)
                .focused($focused)
                .textInputAutocapitalization(.words)
                .foregroundStyle(palette.ink)
                .tint(palette.ink)
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
    }

    private func choice(_ title: String, value: String, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.secondary)
            HStack {
                Text(value)
                    .foregroundStyle(filled ? palette.ink : palette.tertiary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.tertiary)
            }
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
    }
}

private struct RelationWheel: View {
    @Binding var relation: String
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var choice: HouseholdRelation = .father

    var body: some View {
        NavigationStack {
            Picker("Who", selection: $choice) {
                ForEach(HouseholdRelation.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .background(palette.canvas)
            .navigationTitle("Who")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        relation = choice.rawValue
                        dismiss()
                    }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.height(320)])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onAppear {
            choice = HouseholdRelation(rawValue: relation) ?? .father
        }
    }
}

private struct BirthWheel: View {
    @Binding var born: Date?
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            DatePicker("Born", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "en_IN"))
                .background(palette.canvas)
                .navigationTitle("Date of birth")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            born = date
                            dismiss()
                        }
                    }
                }
                .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.height(360)])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onAppear {
            date = born ?? Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
        }
    }
}

private struct AddCarSheet: View {
    var save: (String, String) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var model: String
    @State private var plate: String
    @FocusState private var focused: Bool

    init(model: String = "", plate: String = "", save: @escaping (String, String) -> Void) {
        self.save = save
        _model = State(initialValue: model)
        _plate = State(initialValue: plate)
    }

    private var ready: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                labeled("Model", text: $model, capitals: .words, focus: true)
                labeled("Plate", text: $plate, capitals: .characters, focus: false)
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.canvas)
            .navigationTitle("Car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(model, plate)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!ready)
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.height(320)])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }

    private func labeled(_ title: String, text: Binding<String>, capitals: TextInputAutocapitalization, focus: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.secondary)
            TextField(title, text: text)
                .focused($focused, equals: focus)
                .textInputAutocapitalization(capitals)
                .foregroundStyle(palette.ink)
                .tint(palette.ink)
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
    }
}

private struct TaskGroup: Identifiable {
    var title: String
    var tasks: [PortalTask]
    var id: String { title.lowercased() }
    var ids: Set<String> { Set(tasks.map(\.id)) }
}

private struct TaskEdit: Identifiable {
    var id: String
    var worker: String
    var title: String
    var preferCars: Bool
    var rooms: [String]
    var cars: [String]
}

private func uniqueNames(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
}

private func uniqueIDs(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { !$0.isEmpty && seen.insert($0).inserted }
}

private struct PlaceOption: Identifiable, Hashable {
    var id: String
    var name: String
}

private struct WorkerTaskEditor: View {
    var edit: TaskEdit
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var photo: Bool
    @State private var rooms: [String]
    @State private var cars: [String]
    @State private var picking = false
    @FocusState private var nameFocused: Bool

    init(edit: TaskEdit) {
        self.edit = edit
        _title = State(initialValue: edit.title)
        _note = State(initialValue: "")
        _photo = State(initialValue: false)
        _rooms = State(initialValue: edit.rooms)
        _cars = State(initialValue: edit.cars)
    }

    private var home: PortalHome { app.portal.active }
    private var ready: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var placePills: [PlaceOption] {
        if edit.preferCars {
            return cars.compactMap { id in
                guard let car = home.cars.first(where: { $0.id == id }) else { return nil }
                let name = car.model.isEmpty ? car.plate : car.model
                return PlaceOption(id: id, name: name.isEmpty ? "Car" : name)
            }
        }
        let chosen = Set(rooms.map { $0.lowercased() })
        return home.rooms.filter { chosen.contains($0.name.lowercased()) }.map { PlaceOption(id: $0.name, name: $0.name) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TextField("Task", text: $title, axis: .vertical)
                            .focused($nameFocused)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(palette.ink)
                            .tint(palette.ink)
                            .textInputAutocapitalization(.sentences)
                        if !title.isEmpty {
                            Button {
                                title = ""
                                nameFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(palette.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear")
                        }
                    }
                    TextField("Description", text: $note, axis: .vertical)
                        .font(.body)
                        .foregroundStyle(palette.ink)
                        .tint(palette.ink)
                        .lineLimit(3...8)
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    photoRow
                    placeCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(palette.canvas)
            .navigationTitle(edit.title.isEmpty ? "Task" : edit.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        app.saveGroupedTask(
                            worker: edit.worker,
                            fromTitle: edit.title,
                            title: title,
                            note: note,
                            rooms: edit.preferCars ? [] : rooms,
                            cars: edit.preferCars ? cars : [],
                            photo: photo
                        )
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!ready)
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .sheet(isPresented: $picking) {
                PlacePickSheet(
                    title: edit.preferCars ? "Cars" : "Rooms",
                    options: placeOptions,
                    selected: edit.preferCars ? cars : rooms
                ) { picked in
                    if edit.preferCars { cars = picked } else { rooms = picked }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onAppear {
            if edit.title.isEmpty {
                nameFocused = true
            } else {
                let matches = home.tasks.filter {
                    $0.title.caseInsensitiveCompare(edit.title) == .orderedSame
                        && !$0.review
                        && $0.memberSide != "by"
                }
                if note.isEmpty {
                    note = matches.first {
                        $0.worker.caseInsensitiveCompare(edit.worker) == .orderedSame
                    }?.note ?? matches.first?.note ?? ""
                }
                photo = matches.contains { $0.photo }
            }
        }
    }

    private var placeOptions: [PlaceOption] {
        if edit.preferCars {
            return home.cars.map {
                let name = $0.model.isEmpty ? $0.plate : $0.model
                return PlaceOption(id: $0.id, name: name.isEmpty ? "Car" : name)
            }
        }
        return home.rooms.map { PlaceOption(id: $0.name, name: $0.name) }
    }

    private var photoRow: some View {
        Toggle(isOn: $photo) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo required")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Text("A photo is needed to mark this done.")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
            }
        }
        .tint(palette.ink)
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var placeCard: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { picking = true } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .foregroundStyle(palette.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(edit.preferCars ? "Add car" : "Add room")
            if placePills.isEmpty {
                Button { picking = true } label: {
                    Text(edit.preferCars ? "Add car" : "Add room")
                        .font(.body)
                        .foregroundStyle(palette.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                PillFlow(spacing: 8) {
                    ForEach(placePills) { place in
                        Text(place.name)
                            .font(.subheadline)
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(palette.fill, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct PlacePickSheet: View {
    var title: String
    var options: [PlaceOption]
    var selected: [String]
    var save: ([String]) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String>

    init(title: String, options: [PlaceOption], selected: [String], save: @escaping ([String]) -> Void) {
        self.title = title
        self.options = options
        self.selected = selected
        self.save = save
        _chosen = State(initialValue: Set(selected))
    }

    var body: some View {
        NavigationStack {
            List {
                if options.isEmpty {
                    Text(title == "Cars" ? "No cars yet." : "No rooms yet.")
                        .foregroundStyle(palette.secondary)
                        .listRowBackground(palette.canvas)
                        .listRowSeparator(.hidden)
                }
                ForEach(options) { option in
                    let on = chosen.contains(option.id)
                    Button {
                        if on { chosen.remove(option.id) } else { chosen.insert(option.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(on ? palette.ink : palette.tertiary)
                            Text(option.name)
                                .foregroundStyle(palette.ink)
                            Spacer(minLength: 8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .listRowBackground(palette.canvas)
                    .listRowSeparatorTint(palette.line)
                }
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .background(palette.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(options.map(\.id).filter { chosen.contains($0) })
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }
}

private struct GroceriesTab: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var query = ""
    @State private var filter: GroceryFilter = .all
    @State private var editor: GroceryDraft?
    @State private var reviewing = false
    @FocusState private var searchFocused: Bool

    private var items: [GroceryItem] { app.portal.active.groceries }

    private var shown: [GroceryItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .restock: item.shortfall > 0
            case .stocked: item.level == .stocked
            }
            let matchesQuery = needle.isEmpty
                || item.name.localizedStandardContains(needle)
                || item.aisle.title.localizedStandardContains(needle)
            return matchesFilter && matchesQuery
        }
    }

    private var restock: [GroceryItem] {
        items.filter { $0.shortfall > 0 }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if items.isEmpty {
                        emptyStock
                    } else {
                        restockCard
                        searchField
                        filterRow
                        if shown.isEmpty {
                            Text("Nothing matches.")
                                .font(.body)
                                .foregroundStyle(palette.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(GroceryAisle.allCases) { aisle in
                                let rows = shown.filter { $0.aisle == aisle }
                                if !rows.isEmpty {
                                    aisleSection(aisle, rows: rows)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(palette.canvas)
            .navigationTitle("Groceries")
            .navigationBarTitleDisplayMode(.inline)
            .homeSwitcher()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = GroceryDraft()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add product")
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .toolbarBackground(palette.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: $editor) { draft in
                GroceryEditor(draft: draft)
            }
            .sheet(isPresented: $reviewing) {
                RestockSheet(items: restock)
            }
        }
    }

    private var emptyStock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What this house keeps")
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.ink)
            Text("Add the products you stock. When something falls under the amount you keep, it joins the restock list.")
                .font(.body)
                .foregroundStyle(palette.secondary)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                app.addUsualGroceries()
            } label: {
                Text("Start with the usual")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(white: 0.1))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Aurora.arc[8], in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
                editor = GroceryDraft()
            } label: {
                Text("Add one product")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(palette.fill, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var restockCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Restock")
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("\(restock.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.secondary)
            }
            if restock.isEmpty {
                Text("Everything is at the amount this house keeps.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondary)
            } else {
                Text(restock.map(\.name).prefix(4).joined(separator: ", ") + (restock.count > 4 ? "…" : ""))
                    .font(.subheadline)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    reviewing = true
                } label: {
                    Text("Review restock")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(white: 0.1))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Aurora.arc[8], in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(palette.secondary)
            TextField("Search products", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(palette.fill, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { searchFocused = true }
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(GroceryFilter.allCases) { item in
                let on = filter == item
                Button {
                    filter = item
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(on ? Color(white: 0.1) : palette.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(on ? Aurora.arc[8] : palette.fill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func aisleSection(_ aisle: GroceryAisle, rows: [GroceryItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(aisle.title)
                .font(.headline)
                .foregroundStyle(palette.ink)
            VStack(spacing: 0) {
                ForEach(rows) { item in
                    groceryRow(item)
                    if item.id != rows.last?.id {
                        Rectangle().fill(palette.line).frame(height: 1).padding(.leading, 16)
                    }
                }
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func groceryRow(_ item: GroceryItem) -> some View {
        HStack(spacing: 12) {
            Button {
                editor = GroceryDraft(item)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text("Keep \(item.par) \(item.unit) · \(item.onHand) on hand")
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            levelPill(item.level)
            HStack(spacing: 0) {
                stockButton("minus") { change(item, by: -1) }
                stockButton("plus") { change(item, by: 1) }
            }
            .background(palette.fill, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func stockButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.ink)
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func change(_ item: GroceryItem, by delta: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var next = item
        next.onHand = max(0, item.onHand + delta)
        app.updateGrocery(next)
    }

    private func levelPill(_ level: GroceryLevel) -> some View {
        let fill: Color = switch level {
        case .stocked: Aurora.arc[8]
        case .low: Aurora.arc[1]
        case .out: palette.fill
        }
        let ink: Color = level == .out ? palette.secondary : Color(white: 0.1)
        return Text(level.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(fill, in: Capsule())
    }
}

private enum GroceryFilter: String, CaseIterable, Identifiable {
    case all, restock, stocked
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .restock: "To restock"
        case .stocked: "In stock"
        }
    }
}

private struct GroceryDraft: Identifiable {
    var id: String
    var existing: String?
    var name: String
    var aisle: GroceryAisle
    var par: Int
    var onHand: Int
    var unit: String

    init() {
        id = UUID().uuidString
        existing = nil
        name = ""
        aisle = .staples
        par = 1
        onHand = 1
        unit = ""
    }

    init(_ item: GroceryItem) {
        id = item.id
        existing = item.id
        name = item.name
        aisle = item.aisle
        par = item.par
        onHand = item.onHand
        unit = item.unit
    }
}

private struct GroceryEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var aisle: GroceryAisle
    @State private var par: Int
    @State private var onHand: Int
    @State private var unit: String
    private let existing: String?

    init(draft: GroceryDraft) {
        existing = draft.existing
        _name = State(initialValue: draft.name)
        _aisle = State(initialValue: draft.aisle)
        _par = State(initialValue: draft.par)
        _onHand = State(initialValue: draft.onHand)
        _unit = State(initialValue: draft.unit)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Product", text: $name, prompt: "Milk")
                    field("Unit", text: $unit, prompt: "L, kg, pack")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aisle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(GroceryAisle.allCases) { item in
                                    let on = aisle == item
                                    Button {
                                        aisle = item
                                    } label: {
                                        Text(item.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(on ? Color(white: 0.1) : palette.secondary)
                                            .padding(.horizontal, 12)
                                            .frame(height: 32)
                                            .background(on ? Aurora.arc[8] : palette.fill, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    counter("Keep on hand", value: $par, floor: 1)
                    counter("On hand now", value: $onHand, floor: 0)
                    if existing != nil {
                        Button(role: .destructive) {
                            if let existing { app.removeGrocery(existing) }
                            dismiss()
                        } label: {
                            Text("Remove from this house")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                    }
                }
                .padding(22)
            }
            .background(palette.canvas)
            .navigationTitle(existing == nil ? "Add product" : "Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.secondary)
            TextField(prompt, text: text)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(palette.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func counter(_ title: String, value: Binding<Int>, floor: Int) -> some View {
        HStack {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.ink)
            Spacer()
            HStack(spacing: 0) {
                Button {
                    value.wrappedValue = max(floor, value.wrappedValue - 1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 36, height: 36)
                }
                Text("\(value.wrappedValue)")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 28)
                Button {
                    value.wrappedValue += 1
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 36, height: 36)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.ink)
            .background(palette.fill, in: Capsule())
        }
    }

    private func save() {
        if let existing {
            app.updateGrocery(GroceryItem(id: existing, name: name, aisle: aisle, par: par, onHand: onHand, unit: unit))
        } else {
            app.addGrocery(name: name, aisle: aisle, par: par, onHand: onHand, unit: unit)
        }
        dismiss()
    }
}

private struct RestockSheet: View {
    var items: [GroceryItem]
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Buy these back to the amount this house keeps.")
                        .font(.body)
                        .foregroundStyle(palette.secondary)
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(palette.ink)
                                    Text(item.aisle.title)
                                        .font(.caption)
                                        .foregroundStyle(palette.secondary)
                                }
                                Spacer(minLength: 12)
                                Text("\(item.shortfall) \(item.unit)")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(palette.ink)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            if item.id != items.last?.id {
                                Rectangle().fill(palette.line).frame(height: 1).padding(.leading, 16)
                            }
                        }
                    }
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text("Ordering is not connected yet. When it is, this list can go to Blinkit, Instamart, or both if one store cannot cover it. Prices and what is actually available will show here first.")
                        .font(.footnote)
                        .foregroundStyle(palette.secondary)
                }
                .padding(22)
            }
            .background(palette.canvas)
            .navigationTitle("Restock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
    }
}

private struct PeopleTab: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var query = ""
    @State private var adding = false
    @State private var draft = PortalPerson(id: "", name: "", detail: "", phone: "")
    @State private var selecting = false
    @State private var chosen: Set<String> = []
    @State private var aim: TaskHand?
    @State private var confirmingDelete = false
    @State private var opened: PortalPerson?
    @State private var editing: TaskEdit?
    @State private var dropPerson = ""
    @State private var draggedTask = ""
    @State private var dragBook = SelectionDrag()
    @State private var hover = HoverClock()
    @FocusState private var searchFocused: Bool

    private var people: [PortalPerson] {
        matching(app.portal.active.workers).sorted { left, right in
            let order = Self.kindOrder(left.kind)
            let other = Self.kindOrder(right.kind)
            if order != other { return order < other }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private static func kindOrder(_ kind: WorkerKind?) -> Int {
        switch kind {
        case .maid: 0
        case .housekeeper: 1
        case .cook: 2
        case .nanny: 3
        case .driver: 4
        case nil: 5
        }
    }

    private func matching(_ source: [PortalPerson]) -> [PortalPerson] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return source }
        return source.filter {
            $0.name.localizedStandardContains(needle) || $0.phone.localizedStandardContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.secondary)
                    TextField("Search", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(palette.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(palette.fill, in: Capsule())
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .contentShape(Capsule())
                .onTapGesture { searchFocused = true }
                ScrollView {
                    VStack(spacing: 12) {
                        if app.portal.active.workers.isEmpty {
                            peopleNote("No workers in this home yet.")
                        } else if people.isEmpty {
                            peopleNote("No one matches.")
                        } else {
                            ForEach(people) { person in
                                personCard(person)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .background(palette.canvas)
            }
            .background(palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .homeSwitcher()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draft = PortalPerson(id: UUID().uuidString, name: "", detail: "", phone: "")
                        adding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add worker")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !app.portal.active.workers.isEmpty {
                        Button {
                            selecting.toggle()
                            if !selecting {
                                chosen = []
                                aim = nil
                            }
                            publishSelection()
                        } label: {
                            Image(systemName: selecting ? "checkmark" : "checkmark.circle")
                        }
                        .accessibilityLabel(selecting ? "Done selecting" : "Select tasks")
                    }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .navigationDestination(isPresented: $adding) {
                PersonEditor(person: draft, creating: true)
            }
            .navigationDestination(item: $opened) { person in
                PersonProfile(person: person)
            }
            .safeAreaInset(edge: .bottom) {
                if selecting, !chosen.isEmpty {
                    TaskAimBar(aim: aim, choose: { next in
                        aim = aim == next ? nil : next
                    }, delete: { confirmingDelete = true })
                }
            }
            .onAppear { publishSelection() }
            .onChange(of: selecting) { _, _ in publishSelection() }
            .onChange(of: chosen) { _, _ in publishSelection() }
            .sheet(item: $editing) { edit in
                WorkerTaskEditor(edit: edit)
            }
            .alert("Delete \(chosen.count) \(chosen.count == 1 ? "task" : "tasks")?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    app.removeTasks(chosen)
                    chosen = []
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func fitsChosen(_ person: PortalPerson) -> Bool {
        app.portal.active.tasks.contains { chosen.contains($0.id) && person.takes($0) }
    }

    private func apply(_ person: PortalPerson) {
        guard let aim, fitsChosen(person) else { return }
        DragFeedback.placed()
        switch aim {
        case .move:
            app.moveTask(chosen.sorted().joined(separator: "\u{1e}"), to: person.name)
        case .copy:
            app.copyTasks(chosen, to: [person.name])
        }
        self.aim = nil
        chosen = []
        selecting = false
        publishSelection()
    }

    private func publishSelection() {
        dragBook.selecting = selecting
        dragBook.chosen = chosen
        for task in app.portal.active.tasks {
            dragBook.labels[task.id] = task.title
        }
    }

    private func peopleNote(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(palette.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
    }

    private func groups(for person: PortalPerson) -> [TaskGroup] {
        var order: [String] = []
        var map: [String: [PortalTask]] = [:]
        for task in app.portal.active.granularTasks(for: person) {
            let key = task.title.lowercased()
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(task)
        }
        return order.map { TaskGroup(title: map[$0]?.first?.title ?? $0, tasks: map[$0] ?? []) }
    }

    private func personCard(_ person: PortalPerson) -> some View {
        let groups = groups(for: person)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if aim != nil {
                    apply(person)
                } else {
                    guard !selecting else { return }
                    opened = person
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(palette.ink)
                        if !person.phone.isEmpty {
                            Text(person.phone)
                                .font(.caption)
                                .foregroundStyle(palette.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let kind = person.kind {
                        categoryPill(kind)
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
            if app.busyPeople.contains(person.id) {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
            VStack(spacing: 8) {
                ForEach(groups) { group in
                    taskRow(group, person: person)
                }
                Button {
                    editing = TaskEdit(
                        id: UUID().uuidString,
                        worker: person.name,
                        title: "",
                        preferCars: person.kind == .driver,
                        rooms: [],
                        cars: []
                    )
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                        Text("Add task")
                            .font(.body)
                    }
                    .foregroundStyle(palette.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(palette.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(aim != nil && !fitsChosen(person) ? 0.32 : 1)
        .animation(.smooth(duration: 0.16), value: aim)
        .overlay {
            if dropPerson == person.id {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.ink, lineWidth: 2)
            }
        }
        .animation(.smooth(duration: 0.16), value: dropPerson == person.id)
        .onDrop(of: [.utf8PlainText], delegate: WorkerDrop(
            allowed: { takesDragged(person) },
            enter: { claimPerson(person.id) },
            leave: { releasePerson(person.id) },
            move: { payload in
                guard !selecting, takesDragged(person) else { return }
                app.moveTask(payload, to: person.name)
            }
        ))
    }

    private func takesDragged(_ person: PortalPerson) -> Bool {
        guard let task = app.portal.active.tasks.first(where: { $0.id == draggedTask }) else { return true }
        return person.takes(task)
    }

    private func claimPerson(_ id: String) {
        guard let person = app.portal.active.workers.first(where: { $0.id == id }), takesDragged(person) else {
            dropPerson = ""
            return
        }
        hover.armWorker {
            guard hover.worker == $0 else { return }
            dropPerson = ""
        }
        guard dropPerson != id else { return }
        dropPerson = id
        DragFeedback.moved()
    }

    private func releasePerson(_ id: String) {
        let token = hover.worker
        DispatchQueue.main.async {
            guard hover.worker == token, dropPerson == id else { return }
            dropPerson = ""
        }
    }

    private func taskRow(_ group: TaskGroup, person: PortalPerson) -> some View {
        let on = !group.ids.isEmpty && group.ids.isSubset(of: chosen)
        return HStack(spacing: 10) {
            if selecting {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(on ? palette.ink : palette.tertiary)
            }
            Text(group.title)
                .font(.body.weight(.medium))
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if group.tasks.contains(where: \.photo) {
                Image(systemName: "camera.fill")
                    .font(.caption2)
                    .foregroundStyle(palette.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if selecting {
                if on { chosen.subtract(group.ids) } else { chosen.formUnion(group.ids) }
            } else {
                let rooms = uniqueNames(group.tasks.map(\.room))
                let cars = uniqueIDs(group.tasks.map(\.car))
                editing = TaskEdit(
                    id: group.tasks.first?.id ?? group.id,
                    worker: person.name,
                    title: group.title,
                    preferCars: rooms.isEmpty && !cars.isEmpty,
                    rooms: rooms,
                    cars: cars
                )
            }
        }
        .modifier(TaskDrag(
            enabled: !selecting,
            text: { dragBook.payload(prefix: "", group: group.tasks.map(\.id)) },
            book: dragBook,
            anchor: group.tasks.first?.id ?? group.id,
            fallback: group.title,
            began: {
                draggedTask = group.tasks.first?.id ?? ""
                return 0
            },
            ended: { _ in draggedTask = "" }
        ))
    }
}

private struct TaskDrag: ViewModifier {
    var enabled: Bool = true
    var text: () -> String
    var book: SelectionDrag
    var anchor: String
    var fallback: String
    var began: () -> Int = { 0 }
    var ended: (Int) -> Void = { _ in }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .clipShape(shape)
                .contentShape(.dragPreview, shape)
                .onDrag {
                let token = began()
                DragFeedback.lifted()
                let provider = NSItemProvider()
                let load = text
                provider.registerObject(ofClass: NSString.self, visibility: .all) { completion in
                    completion(load() as NSString, nil)
                    return nil
                }
                let lifetime = DragLifetime { ended(token) }
                objc_setAssociatedObject(provider, &DragLifetime.association, lifetime, .OBJC_ASSOCIATION_RETAIN)
                return provider
            } preview: {
                DragLiftPreview(book: book, anchor: anchor, fallback: fallback)
            }
        } else {
            content
        }
    }
}

private struct DragLiftPreview: View {
    var book: SelectionDrag
    var anchor: String
    var fallback: String
    @Environment(\.palette) private var palette

    var body: some View {
        let titles = book.liftTitles(anchor: anchor, fallback: fallback)
        let shown = Array(titles.prefix(4))
        ZStack(alignment: .top) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, title in
                Text(title)
                    .font(.callout)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(width: 260, height: 48, alignment: .leading)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(palette.line, lineWidth: 0.5)
                    }
                    .offset(y: CGFloat(index) * 12)
            }
        }
        .frame(width: 260, height: 48 + CGFloat(max(shown.count - 1, 0)) * 12, alignment: .top)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

private final class DragLifetime: NSObject {
    static var association: UInt8 = 0
    private let end: () -> Void

    init(_ end: @escaping () -> Void) {
        self.end = end
    }

    deinit {
        let end = end
        if Thread.isMainThread {
            end()
        } else {
            DispatchQueue.main.async(execute: end)
        }
    }
}

private struct AvatarMark: View {
    var person: PortalPerson
    var roster: [String]
    var size: CGFloat

    private var tint: Color {
        AvatarTint.color(for: person.id.isEmpty ? person.name : person.id, among: roster)
    }

    var body: some View {
        let mark = Text(personInitials(person.name))
            .font(size > 40 ? .body.weight(.semibold) : .caption2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background { Circle().fill(tint) }
        return Group {
            if let url = URL(string: person.portrait), !person.portrait.isEmpty {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        mark
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                mark
            }
        }
        .compositingGroup()
    }
}

private struct AvatarGroup: View {
    var people: [PortalPerson]
    var roster: [String]
    var size: CGFloat
    var ring: Color
    var limit = 4

    var body: some View {
        let shown = Array(people.prefix(limit))
        let extra = people.count - shown.count
        HStack(spacing: -8) {
            ForEach(shown) { person in
                AvatarMark(person: person, roster: roster, size: size)
                    .padding(1.5)
                    .background { Circle().fill(ring) }
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background { Circle().fill(Color(white: 0.35)) }
                    .padding(1.5)
                    .background { Circle().fill(ring) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(people.map(\.name).joined(separator: ", "))
    }
}

private func personInitials(_ name: String) -> String {
    let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
    let text = String(letters)
    return text.isEmpty ? "?" : text
}

private enum AvatarTint {
    static func color(for key: String, among keys: [String]) -> Color {
        var pool = Array(Set(keys.filter { !$0.isEmpty }))
        if !key.isEmpty, !pool.contains(key) { pool.append(key) }
        pool.sort()
        let count = max(pool.count, 1)
        let index = pool.firstIndex(of: key) ?? 0
        let hue = (Double(index) / Double(count) + 0.07).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.72, brightness: 0.62)
    }
}

private func staffPayload(_ payload: String) -> String? {
    let prefix = "staff:"
    guard payload.hasPrefix(prefix) else { return nil }
    let id = String(payload.dropFirst(prefix.count))
    return id.isEmpty ? nil : id
}

private func taskIDs(_ payload: String) -> [String] {
    let prefix = "task:"
    guard payload.hasPrefix(prefix) else { return [] }
    return payload.dropFirst(prefix.count).split(separator: "\u{1e}").map(String.init).filter { !$0.isEmpty }
}

private struct StaffDrop: DropDelegate {
    var frame: () -> CGRect = { .zero }
    var scroller: DragScroller = DragScroller()
    var enter: () -> Void
    var leave: () -> Void
    var accept: (String) -> Void
    var point: ((CGPoint) -> Void)? = nil

    func dropEntered(info: DropInfo) {
        report(info)
        enter()
    }

    func dropExited(info: DropInfo) {
        scroller.end()
        leave()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        report(info)
        enter()
        let rect = frame()
        if rect.width > 1, rect.height > 1 {
            scroller.hover(globalY: rect.minY + info.location.y)
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        scroller.end()
        leave()
        guard let provider = info.itemProviders(for: [.utf8PlainText]).first else { return false }
        DragFeedback.placed()
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? String else { return }
            DispatchQueue.main.async { accept(payload) }
        }
        return true
    }

    private func report(_ info: DropInfo) {
        point?(info.location)
    }
}

private struct StaffEdges: Equatable {
    var left = false
    var right = false
}

private struct ScrollBox: Equatable {
    var offset: CGFloat = 0
    var limit: CGFloat = 0
    var viewport: CGFloat = 0
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}

final class FrameBook {
    var values: [String: CGRect] = [:]
}

private struct ContentFrame: View {
    var space: String
    var onChange: (CGRect) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { onChange(geo.frame(in: .named(space))) }
                .onChange(of: geo.frame(in: .named(space))) { _, frame in onChange(frame) }
        }
    }
}

private struct GlobalFrame: View {
    var onChange: (CGRect) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { onChange(geo.frame(in: .global)) }
                .onChange(of: geo.frame(in: .global)) { _, frame in onChange(frame) }
        }
    }
}

private struct PillFrame: UIViewRepresentable {
    var onChange: (CGRect) -> Void

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.onChange = onChange
        uiView.report()
    }

    final class Probe: UIView {
        var onChange: ((CGRect) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        func report() {
            guard window != nil else { return }
            var match: UIView?
            var view: UIView? = superview
            while let current = view {
                if current is UIWindow { break }
                let height = current.bounds.height
                let width = current.bounds.width
                if height >= 30, height <= 52, width >= bounds.width, width < 300 {
                    match = current
                    break
                }
                if height > 80 { break }
                view = current.superview
            }
            let target = match ?? self
            let frame = target.convert(target.bounds, to: nil)
            guard frame.width > 1, frame.height > 1 else { return }
            onChange?(frame)
        }
    }
}

final class DragScroller: NSObject {
    weak var scrollView: UIScrollView?
    private var link: CADisplayLink?
    private var direction: CGFloat = 0

    func attach(_ view: UIView) {
        var current: UIView? = view
        while let next = current {
            if let scroll = next as? UIScrollView {
                scrollView = scroll
                return
            }
            current = next.superview
        }
    }

    func hover(globalY: CGFloat) {
        guard let scroll = scrollView else { return }
        let frame = scroll.convert(scroll.bounds, to: nil)
        let edge: CGFloat = 96
        if globalY < frame.minY + edge {
            direction = -1
        } else if globalY > frame.maxY - edge {
            direction = 1
        } else {
            end()
            return
        }
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    var atTop: Bool {
        guard let scroll = scrollView else { return false }
        return scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 1
    }

    /// Pulls a leftover few points back to the top once the finger is gone.
    func settleIfResting() {
        guard let scroll = scrollView else { return }
        guard !scroll.isDragging, !scroll.isDecelerating, !scroll.isTracking else { return }
        let rest = -scroll.adjustedContentInset.top
        let delta = scroll.contentOffset.y - rest
        guard delta > 1, delta < 20 else { return }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: rest), animated: false)
    }

    func end() {
        direction = 0
        link?.invalidate()
        link = nil
    }

    @objc private func tick() {
        guard let scroll = scrollView, direction != 0 else {
            end()
            return
        }
        let inset = scroll.adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
        let next = min(maxY, max(minY, scroll.contentOffset.y + direction * 8))
        guard next != scroll.contentOffset.y else { return }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: next), animated: false)
    }
}

private struct ScrollFinder: UIViewRepresentable {
    var onFind: (UIView) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { onFind(uiView) }
    }
}

private struct WorkerDrop: DropDelegate {
    var allowed: () -> Bool = { true }
    var enter: () -> Void = {}
    var leave: () -> Void = {}
    var move: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        allowed()
    }

    func dropEntered(info: DropInfo) {
        enter()
    }

    func dropExited(info: DropInfo) {
        leave()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        enter()
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        leave()
        guard let provider = info.itemProviders(for: [.utf8PlainText]).first else { return false }
        DragFeedback.placed()
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? String else { return }
            DispatchQueue.main.async { move(payload) }
        }
        return true
    }
}

private enum DragFeedback {
    private static let move = UIImpactFeedbackGenerator(style: .light)
    private static let lift = UIImpactFeedbackGenerator(style: .medium)
    private static let place = UIImpactFeedbackGenerator(style: .soft)

    static func lifted() {
        lift.prepare()
        lift.impactOccurred()
        move.prepare()
        place.prepare()
    }

    static func moved() {
        AudioServicesPlaySystemSound(1519)
        move.impactOccurred(intensity: 1)
        move.prepare()
    }

    static func placed() {
        place.impactOccurred()
        move.prepare()
    }
}

private final class SelectionDrag {
    var selecting = false
    var chosen: Set<String> = []
    var labels: [String: String] = [:]

    func payload(prefix: String, group: [String]) -> String {
        let set = Set(group)
        let ids = selecting && !chosen.isDisjoint(with: set) ? Array(chosen) : group
        return prefix + ids.joined(separator: "\u{1e}")
    }

    func liftTitles(anchor: String, fallback: String) -> [String] {
        let ids = selecting && chosen.contains(anchor) ? Array(chosen) : [anchor]
        var seen = Set<String>()
        let titles = ids.compactMap { labels[$0] }.filter { seen.insert($0).inserted }
        return titles.isEmpty ? [fallback] : titles
    }
}

private final class HoverClock {
    var worker = 0
    var room = 0
    private var workerClear: DispatchWorkItem?
    private var roomClear: DispatchWorkItem?

    func armWorker(reset: @escaping (Int) -> Void) {
        arm(token: &worker, clear: &workerClear, reset: reset)
    }

    func armRoom(reset: @escaping (Int) -> Void) {
        arm(token: &room, clear: &roomClear, reset: reset)
    }

    private func arm(token: inout Int, clear: inout DispatchWorkItem?, reset: @escaping (Int) -> Void) {
        token += 1
        let current = token
        clear?.cancel()
        let item = DispatchWorkItem { reset(current) }
        clear = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }
}

private struct CopyRow: Identifiable {
    var id: String
    var title: String
    var kind: WorkerKind? = nil
}

private struct CopyTasksSheet: View {
    var rows: [CopyRow]
    var empty: String
    var copy: ([String]) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    Text(empty)
                        .foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(rows) { row in
                            Button {
                                if picked.contains(row.id) { picked.remove(row.id) } else { picked.insert(row.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(row.title)
                                        .foregroundStyle(palette.ink)
                                    Spacer()
                                    if let kind = row.kind {
                                        categoryPill(kind)
                                    }
                                    Image(systemName: picked.contains(row.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(picked.contains(row.id) ? palette.ink : palette.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(palette.canvas)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(palette.canvas)
            .navigationTitle("Copy to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        copy(rows.filter { picked.contains($0.id) }.map(\.id))
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(picked.isEmpty)
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }
}

private struct CommunityPostSheet: View {
    var homes: [PortalHome]
    var post: (String, String, [String], [TaskPostItem], WorkerKind, String) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var homeID: String
    @State private var kind: WorkerKind?
    @State private var starts: Date
    @State private var ends: Date
    @State private var ending = false
    @State private var clock: Date
    @State private var dates: Set<String> = []
    @State private var salary = ""
    @State private var work = ""

    init(homes: [PortalHome], homeID: String, post: @escaping (String, String, [String], [TaskPostItem], WorkerKind, String) -> Void) {
        self.homes = homes
        self.post = post
        let calendar = Calendar.current
        let open = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
        let close = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
        _homeID = State(initialValue: homeID)
        _starts = State(initialValue: open)
        _ends = State(initialValue: close)
        _clock = State(initialValue: open)
    }

    private var span: String { "\(ClockText.label(starts))–\(ClockText.label(ends))" }
    private var chosenHome: PortalHome? { homes.first { $0.id == homeID } ?? homes.first }
    private var chosenDates: [String] { dates.sorted() }

    private var ready: Bool {
        let community = chosenHome?.community.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return kind != nil && !community.isEmpty && !salary.isEmpty && !chosenDates.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    homeRow
                    placeRow
                    kindRow
                    hoursWheel
                    PostDates(dates: $dates)
                    salaryRow
                    workRow
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(palette.canvas)
            .navigationTitle("Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let kind else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let note = work.trimmingCharacters(in: .whitespacesAndNewlines)
                    let tasks = note.isEmpty ? [] : [TaskPostItem(id: "work", place: "", title: note)]
                    post(span, salary, chosenDates, tasks, kind, chosenHome?.id ?? homeID)
                    dismiss()
                } label: {
                    Text("Post")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(palette.fill, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!ready)
                .opacity(ready ? 1 : 0.4)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(palette.canvas)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onChange(of: ending) { _, isEnd in
            clock = isEnd ? ends : starts
        }
        .onChange(of: clock) { _, value in
            if ending { ends = value } else { starts = value }
        }
    }

    private var homeRow: some View {
        let home = chosenHome
        let community = home?.community.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Group {
            if homes.count > 1 {
                Menu {
                    ForEach(homes) { item in
                        Button {
                            homeID = item.id
                        } label: {
                            if item.id == home?.id {
                                Label(item.name, systemImage: "checkmark")
                            } else {
                                Text(item.name)
                            }
                        }
                    }
                } label: {
                    placeLabel(title: home?.name ?? "Home", detail: community.isEmpty ? "No community on this home" : community, choosable: true)
                }
                .buttonStyle(.plain)
            } else {
                placeLabel(title: community.isEmpty ? "No community on this home" : community, detail: home?.name ?? "", choosable: false)
            }
        }
    }

    private func placeLabel(title: String, detail: String, choosable: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(choosable ? "Home" : "Community")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                Text(title)
                    .font(.body)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if choosable {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var placeRow: some View {
        let door = chosenHome?.line.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let floor = chosenHome?.floor ?? 0
        return VStack(spacing: 0) {
            labeled("Door", door.isEmpty ? "Not set" : door, dim: door.isEmpty)
            if (1...40).contains(floor) {
                Rectangle().fill(palette.line).frame(height: 1).padding(.horizontal, 16)
                labeled("Floor", "\(floor)", dim: false)
            }
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func labeled(_ title: String, _ value: String, dim: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(palette.secondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(dim ? palette.tertiary : palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }

    private var kindRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who")
                .font(.caption)
                .foregroundStyle(palette.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                ForEach(WorkerKind.allCases) { item in
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        kind = item
                    } label: {
                        Text(item.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(kind == item ? palette.onInverse : palette.ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(kind == item ? palette.inverse : palette.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var hoursWheel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hours needed")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                Spacer(minLength: 8)
                Text(span)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.ink)
            }
            .padding(.horizontal, 4)
            Picker("Hours", selection: $ending) {
                Text("Starts").tag(false)
                Text("Ends").tag(true)
            }
            .pickerStyle(.segmented)
            DatePicker("Time", selection: $clock, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .environment(\.locale, Locale(identifier: "en_US"))
        }
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var salaryRow: some View {
        HStack(spacing: 12) {
            Text("Pay")
                .foregroundStyle(palette.ink)
            Spacer(minLength: 12)
            Text("₹")
                .foregroundStyle(palette.secondary)
            TextField("0", text: $salary)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(palette.ink)
                .frame(width: 96)
                .onChange(of: salary) { _, value in
                    let next = value.filter(\.isNumber)
                    if next != value { salary = next }
                }
        }
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var workRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Work")
                .font(.caption)
                .foregroundStyle(palette.secondary)
            TextField("What they do", text: $work)
                .font(.body)
                .foregroundStyle(palette.ink)
                .tint(palette.ink)
        }
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RequestSheet: View {
    var community: String
    var initialText = ""
    var initialKind: WorkerKind?
    var editing = false
    var send: (String, WorkerKind?) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var kind: WorkerKind?
    @State private var picking = false
    @FocusState private var focused: Bool

    private var ready: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Request")
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                    TextField("What do you need", text: $text, axis: .vertical)
                        .focused($focused)
                        .lineLimit(2...4)
                        .foregroundStyle(palette.ink)
                        .tint(palette.ink)
                    Rectangle()
                        .fill(palette.line)
                        .frame(height: 1)
                }
                Button {
                    picking = true
                } label: {
                    HStack {
                        Text("Who")
                            .foregroundStyle(palette.ink)
                        Spacer()
                        Text(kind?.rawValue ?? "Anyone")
                            .foregroundStyle(palette.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.canvas)
            .navigationTitle(editing ? "Edit" : (community.isEmpty ? "Request" : community))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        send(text, kind)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!ready)
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .sheet(isPresented: $picking) {
                RequestKindSheet(kind: $kind)
            }
        }
        .presentationDetents([.height(320)])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onAppear {
            if text.isEmpty { text = initialText }
            if kind == nil { kind = initialKind }
            focused = true
        }
    }
}

private struct RequestKindSheet: View {
    @Binding var kind: WorkerKind?
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    kind = nil
                    dismiss()
                } label: {
                    HStack {
                        Text("Anyone")
                            .foregroundStyle(palette.ink)
                        Spacer()
                        if kind == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(palette.ink)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(palette.canvas)
                ForEach(WorkerKind.allCases) { item in
                    Button {
                        kind = item
                        dismiss()
                    } label: {
                        HStack {
                            Text(item.rawValue)
                                .foregroundStyle(palette.ink)
                            Spacer()
                            if kind == item {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(palette.ink)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(palette.canvas)
                }
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .background(palette.canvas)
            .navigationTitle("Who")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }
}

private struct PeopleFilterSheet: View {
    @Binding var categories: Set<WorkerKind>?
    @Binding var parts: Set<DayPart>?
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                    NavigationLink {
                        FilterTogglePage(
                            title: "Category",
                            items: WorkerKind.allCases,
                            name: \.rawValue,
                            symbol: { kind in
                                switch kind {
                                case .driver: "car"
                                case .maid: "sparkles"
                                case .housekeeper: "house"
                                case .nanny: "figure.and.child"
                                case .cook: "fork.knife"
                                }
                            },
                            selection: $categories
                        )
                    } label: {
                        filterLink("Category", symbol: "person.2", value: summary(categories, order: WorkerKind.allCases))
                    }
                    .betweenDivider(palette, last: false)
                    NavigationLink {
                        FilterTogglePage(
                            title: "Period",
                            items: DayPart.allCases,
                            name: \.rawValue,
                            symbol: { part in
                                switch part {
                                case .morning: "sunrise"
                                case .afternoon: "sun.max"
                                case .evening: "moon.stars"
                                }
                            },
                            selection: $parts
                        )
                    } label: {
                        filterLink("Period", symbol: "clock", value: summary(parts, order: DayPart.allCases))
                    }
                    .betweenDivider(palette, last: true)
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .listSectionSeparator(.hidden)
            .scrollContentBackground(.hidden)
            .background(palette.canvas)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }

    private func filterLink(_ title: String, symbol: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(palette.secondary)
                .frame(width: 22)
            Text(title)
                .foregroundStyle(palette.ink)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
    }

    private func summary<Item: Hashable & RawRepresentable>(_ selection: Set<Item>?, order: [Item]) -> String where Item.RawValue == String {
        guard let selection else { return "All" }
        if selection.isEmpty { return "None" }
        let names = order.filter { selection.contains($0) }.map(\.rawValue)
        return names.count == 1 ? names[0] : names.joined(separator: ", ")
    }
}

private struct FilterTogglePage<Item: Hashable & Identifiable>: View {
    let title: String
    let items: [Item]
    let name: (Item) -> String
    let symbol: (Item) -> String
    @Binding var selection: Set<Item>?
    @Environment(\.palette) private var palette

    var body: some View {
        List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Toggle(isOn: binding(item)) {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(item))
                                .foregroundStyle(palette.secondary)
                                .frame(width: 22)
                            Text(name(item))
                                .foregroundStyle(palette.ink)
                        }
                    }
                    .tint(palette.ink)
                    .betweenDivider(palette, last: index == items.count - 1)
            }
        }
        .listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
        .listSectionSeparator(.hidden)
        .scrollContentBackground(.hidden)
        .background(palette.canvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
    }

    private func binding(_ item: Item) -> Binding<Bool> {
        Binding(
            get: { selection?.contains(item) ?? true },
            set: { on in
                var next = selection ?? Set(items)
                if on { next.insert(item) } else { next.remove(item) }
                selection = next.count == items.count ? nil : next
            }
        )
    }
}

private struct StaffCodeCopy: View {
    var phone: String
    var height: CGFloat = 48
    var inset: CGFloat = 16
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var code: String?
    @State private var loading = false
    @State private var copied = false
    @State private var problem: String?
    @State private var reset: Task<Void, Never>?

    private var digits: String { phone.filter(\.isNumber) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if digits.count < 10 {
                Text("Add a phone number to make a sign-in code.")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button {
                    if let code {
                        UIPasteboard.general.string = code
                        copied = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        reset?.cancel()
                        reset = Task {
                            try? await Task.sleep(for: .milliseconds(1400))
                            guard !Task.isCancelled else { return }
                            copied = false
                        }
                    } else {
                        Task { await load() }
                    }
                } label: {
                    Group {
                        if loading && code == nil {
                            ProgressView().tint(palette.onInverse)
                        } else {
                            Text(label)
                                .font(.body.weight(.semibold))
                                .contentTransition(.numericText())
                        }
                    }
                    .foregroundStyle(palette.onInverse)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(palette.inverse, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(loading && code == nil)
                .animation(.smooth(duration: 0.2), value: copied)
                if let problem, code == nil {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, inset)
        .padding(.bottom, 16)
        .task(id: digits) { await load() }
    }

    private var label: String {
        if copied { return "Copied" }
        if let code { return "Copy: \(code)" }
        return "Copy"
    }

    private func load() async {
        guard digits.count >= 10 else {
            code = nil
            return
        }
        loading = true
        await app.syncNow()
        do {
            code = try await StaffAccess.issue(phone: digits).code
            problem = nil
        } catch {
            problem = StaffAccess.message(error)
        }
        loading = false
    }
}

private struct WorkerDrawer: View {
    let person: PortalPerson
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var selecting = false
    @State private var chosen: Set<String> = []
    @State private var confirmingDelete = false
    @State private var posting = false
    @State private var taskEdit: TaskEdit?

    private var home: PortalHome { app.portal.active }

    private var current: PortalPerson {
        home.workers.first { $0.id == person.id } ?? person
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profileCard
                    if groups.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No tasks yet.")
                                .font(.body)
                                .foregroundStyle(palette.secondary)
                            if !selecting {
                                Button {
                                    taskEdit = newTask(room: "", car: "")
                                } label: {
                                    clusterAdd("Add task")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(groups) { group in
                                placeCard(group)
                            }
                        }
                        .padding(16)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 22)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(palette.canvas)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $editing) {
                PersonEditor(person: current)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        selecting.toggle()
                        if !selecting { chosen = [] }
                    } label: {
                        Image(systemName: selecting ? "checkmark" : "checkmark.circle")
                    }
                    .accessibilityLabel(selecting ? "Done selecting" : "Select tasks")
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if selecting, !chosen.isEmpty {
                    HStack(spacing: 10) {
                        Button {
                            posting = true
                        } label: {
                            Text("Post")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(palette.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(palette.fill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            confirmingDelete = true
                        } label: {
                            Text("Delete")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(palette.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(palette.fill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(palette.canvas)
                }
            }
            .sheet(item: $taskEdit) { edit in
                WorkerTaskEditor(edit: edit)
            }
            .sheet(isPresented: $posting) {
                TaskPostSheet(
                    homes: app.portal.homes,
                    homeID: home.id,
                    hours: current.hours,
                    tasks: postTasks
                ) { hours, salary, dates, homeID in
                    let home = app.portal.homes.first { $0.id == homeID }
                    app.sendRequest(
                        text: Self.postDetails(hours: hours, salary: salary, dates: dates, tasks: postTasks, door: home?.line ?? "", floor: home?.floor ?? 0),
                        kind: current.kind,
                        homeID: homeID
                    )
                    chosen = []
                    selecting = false
                }
            }
            .alert("Delete \(chosen.count) \(chosen.count == 1 ? "task" : "tasks")?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    app.removeTasks(chosen)
                    chosen = []
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onChange(of: home.workers.contains { $0.id == person.id }) { _, here in
            if !here { dismiss() }
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                AvatarMark(person: current, roster: home.workers.map(\.id) + home.members.map(\.id), size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.ink)
                    Text(current.kind?.rawValue ?? "Worker")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.tertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture { editing = true }
            StaffCodeCopy(phone: current.phone)
            if !current.phone.isEmpty {
                profileLine("Phone", current.phone)
            }
            if !current.hours.isEmpty {
                profileLine("Hours", current.hours)
            }
            if !current.dayLabel.isEmpty {
                profileLine("Days", current.dayLabel)
            }
            if !current.salary.isEmpty {
                profileLine("Salary", "₹\(current.salary)")
            }
            profileLine("Yearly incentive", "₹\(current.incentive.isEmpty ? "0" : current.incentive)")
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 22)
    }

    private struct TaskGroup: Identifiable {
        var id: String
        var title: String
        var tasks: [PortalTask]
        var ids: Set<String> { Set(tasks.map(\.id)) }
    }

    private var groups: [TaskGroup] {
        let mine = home.granularTasks(for: current)
        var list: [TaskGroup] = []
        for room in home.rooms {
            let rows = mine.filter { $0.car.isEmpty && $0.room.caseInsensitiveCompare(room.name) == .orderedSame }
            if !rows.isEmpty { list.append(TaskGroup(id: "room-\(room.id)", title: room.name, tasks: rows)) }
        }
        let named = Set(home.rooms.map { $0.name.lowercased() })
        let looseRooms = Array(Set(mine.filter { $0.car.isEmpty && !$0.room.isEmpty && !named.contains($0.room.lowercased()) }.map(\.room))).sorted()
        for name in looseRooms {
            let rows = mine.filter { $0.car.isEmpty && $0.room.caseInsensitiveCompare(name) == .orderedSame }
            list.append(TaskGroup(id: "room-name-\(name)", title: name, tasks: rows))
        }
        for car in home.cars {
            let rows = mine.filter { $0.car == car.id }
            if !rows.isEmpty { list.append(TaskGroup(id: "car-\(car.id)", title: car.model, tasks: rows)) }
        }
        let parked = mine.filter { $0.room.isEmpty && $0.car.isEmpty }
        if !parked.isEmpty { list.append(TaskGroup(id: "open", title: "", tasks: parked)) }
        return list
    }

    private func placeCard(_ group: TaskGroup) -> some View {
        let on = !group.ids.isEmpty && group.ids.isSubset(of: chosen)
        return VStack(alignment: .leading, spacing: 8) {
            if !group.title.isEmpty || selecting {
                HStack(spacing: 10) {
                    if selecting {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundStyle(on ? palette.ink : palette.tertiary)
                    }
                    if !group.title.isEmpty {
                        Text(group.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard selecting else { return }
                    if on { chosen.subtract(group.ids) } else { chosen.formUnion(group.ids) }
                }
            }
            ForEach(group.tasks) { task in
                TaskSlide(enabled: !selecting, onTap: {
                    guard selecting else { return }
                    if chosen.contains(task.id) { chosen.remove(task.id) } else { chosen.insert(task.id) }
                }) {
                    app.removeTasks([task.id])
                    chosen.remove(task.id)
                } content: {
                    workerTaskRow(task)
                }
            }
            if !selecting {
                Button {
                    taskEdit = newTask(room: group.id.hasPrefix("car-") ? "" : group.title, car: group.id.hasPrefix("car-") ? String(group.id.dropFirst(4)) : "")
                } label: {
                    clusterAdd("Add task")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func workerTaskRow(_ task: PortalTask) -> some View {
        let people = people(on: task)
        let on = chosen.contains(task.id)
        return HStack(spacing: 12) {
            if selecting {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(on ? palette.ink : palette.tertiary)
            }
            Text(task.title)
                .font(.callout)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if task.photo {
                Image(systemName: "camera.fill")
                    .font(.caption2)
                    .foregroundStyle(palette.secondary)
            }
            AvatarGroup(people: people, roster: home.workers.map(\.id) + home.members.map(\.id), size: 24, ring: palette.surface, limit: 3)
                .frame(width: 72, height: 24, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func newTask(room: String, car: String) -> TaskEdit {
        let driving = !car.isEmpty || (room.isEmpty && current.kind == .driver)
        return TaskEdit(
            id: UUID().uuidString,
            worker: current.name,
            title: "",
            preferCars: driving,
            rooms: room.isEmpty ? [] : [room],
            cars: car.isEmpty ? [] : [car]
        )
    }

    private func clusterAdd(_ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.body.weight(.medium))
            Text(title)
                .font(.body)
        }
        .foregroundStyle(palette.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func people(on task: PortalTask) -> [PortalPerson] {
        let names = Set(home.tasks.filter {
            $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                && $0.room.caseInsensitiveCompare(task.room) == .orderedSame
                && $0.car == task.car
                && !$0.worker.isEmpty
                && !$0.review
        }.map { $0.worker.lowercased() })
        return home.workers.filter { names.contains($0.name.lowercased()) }
    }

    private var postTasks: [TaskPostItem] {
        groups.flatMap { group in
            group.tasks.filter { chosen.contains($0.id) }.map {
                TaskPostItem(id: $0.id, place: group.title, title: $0.title)
            }
        }
    }

    private static func postDetails(hours: String, salary: String, dates: [String], tasks: [TaskPostItem], door: String = "", floor: Int = 0) -> String {
        RequestBody.written(hours: hours, salary: salary, dates: dates, tasks: tasks, door: door, floor: floor)
    }

    private func profileLine(_ title: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
                .padding(.horizontal, 16)
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(palette.secondary)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
    }
}

private struct TaskPostItem: Identifiable, Hashable {
    var id: String
    var place: String
    var title: String
}

private struct TaskPostSheet: View {
    var homes: [PortalHome]
    var hours: String
    var tasks: [TaskPostItem]
    var title: String
    var commit: String
    var post: (String, String, [String], String) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var homeID: String
    @State private var starts: Date
    @State private var ends: Date
    @State private var ending = false
    @State private var clock: Date
    @State private var dates: Set<String>
    @State private var salary: String

    init(homes: [PortalHome], homeID: String, hours: String, tasks: [TaskPostItem], offered: String = "", dates: Set<String> = [], title: String = "Post", commit: String = "Post", post: @escaping (String, String, [String], String) -> Void) {
        self.homes = homes
        self.hours = hours
        self.tasks = tasks
        self.title = title
        self.commit = commit
        self.post = post
        let clocks = ClockText.span(hours)
        _homeID = State(initialValue: homeID)
        _starts = State(initialValue: clocks.starts)
        _ends = State(initialValue: clocks.ends)
        _clock = State(initialValue: clocks.starts)
        _dates = State(initialValue: dates)
        _salary = State(initialValue: offered.filter(\.isNumber))
    }

    private var span: String { "\(ClockText.label(starts))–\(ClockText.label(ends))" }
    private var chosenHome: PortalHome? { homes.first { $0.id == homeID } ?? homes.first }
    private var chosenDates: [String] { dates.sorted() }

    private var ready: Bool {
        let community = chosenHome?.community.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !community.isEmpty && !salary.isEmpty && !tasks.isEmpty && !chosenDates.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    homeRow
                    hoursWheel
                    PostDates(dates: $dates)
                    salaryRow
                    taskList
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(palette.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    post(span, salary, chosenDates, chosenHome?.id ?? homeID)
                    dismiss()
                } label: {
                    Text(commit)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(palette.fill, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!ready)
                .opacity(ready ? 1 : 0.4)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(palette.canvas)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
        .onChange(of: ending) { _, isEnd in
            clock = isEnd ? ends : starts
        }
        .onChange(of: clock) { _, value in
            if ending { ends = value } else { starts = value }
        }
    }

    private var homeRow: some View {
        let home = chosenHome
        let community = home?.community.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let several = homes.count > 1
        return Group {
            if several {
                Menu {
                    ForEach(homes) { item in
                        Button {
                            homeID = item.id
                        } label: {
                            if item.id == home?.id {
                                Label(item.name, systemImage: "checkmark")
                            } else {
                                Text(item.name)
                            }
                        }
                    }
                } label: {
                    homeLabel(name: home?.name ?? "Home", community: community, choosable: true)
                }
                .buttonStyle(.plain)
            } else {
                homeLabel(name: home?.name ?? "Home", community: community, choosable: false)
            }
        }
    }

    private func homeLabel(name: String, community: String, choosable: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(choosable ? "Home" : "Community")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                Text(choosable ? name : (community.isEmpty ? "No community on this home" : community))
                    .font(.body)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                if choosable {
                    Text(community.isEmpty ? "No community on this home" : community)
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if choosable {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.tertiary)
            } else if !community.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(palette.ink)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var hoursWheel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hours needed")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                Spacer(minLength: 8)
                Text(span)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.ink)
            }
            .padding(.horizontal, 4)
            Picker("Hours", selection: $ending) {
                Text("Starts").tag(false)
                Text("Ends").tag(true)
            }
            .pickerStyle(.segmented)
            DatePicker("Time", selection: $clock, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 216)
                .environment(\.locale, Locale(identifier: "en_US"))
        }
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var salaryRow: some View {
        HStack(spacing: 12) {
            Text("Salary offered")
                .foregroundStyle(palette.ink)
            Spacer(minLength: 12)
            Text("₹")
                .foregroundStyle(palette.secondary)
            TextField("0", text: $salary)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(palette.ink)
                .frame(width: 96)
                .onChange(of: salary) { _, value in
                    let next = value.filter(\.isNumber)
                    if next != value { salary = next }
                }
        }
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 8) {
            let places = taskPlaces
            ForEach(places, id: \.self) { place in
                if !place.isEmpty {
                    Text(place)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.ink)
                        .padding(.top, 4)
                }
                ForEach(tasks.filter { $0.place == place }) { task in
                    Text(task.title)
                        .font(.callout)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var taskPlaces: [String] {
        var seen: [String] = []
        for task in tasks where !seen.contains(task.place) {
            seen.append(task.place)
        }
        return seen
    }
}

private struct PostDates: View {
    @Binding var dates: Set<String>
    @Environment(\.palette) private var palette
    @State private var month: Date

    init(dates: Binding<Set<String>>) {
        _dates = dates
        let calendar = Calendar.current
        let anchor = dates.wrappedValue.compactMap(DayStamp.date).min() ?? .now
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? .now
        _month = State(initialValue: start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(dates.isEmpty ? "Dates" : CoverDates.summary(Array(dates)))
                .font(.caption)
                .foregroundStyle(dates.isEmpty ? palette.secondary : palette.ink)
            HStack {
                monthButton("chevron.left", delta: -1)
                Spacer(minLength: 8)
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 8)
                monthButton("chevron.right", delta: 1)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(weekdayLabels, id: \.offset) { item in
                    Text(item.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.tertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 18)
                }
                ForEach(cells) { cell in
                    dayButton(cell)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var weekdayLabels: [(offset: Int, text: String)] {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return (0..<7).map { offset in
            (offset, String(symbols[(offset + start) % 7].prefix(2)))
        }
    }

    private var cells: [DayCell] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var result = (0..<leading).map { DayCell(id: "post-\(month.timeIntervalSinceReferenceDate)-\($0)", date: nil) }
        for offset in 0..<count {
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { continue }
            result.append(DayCell(id: "post-\(DayStamp.key(date))", date: date))
        }
        return result
    }

    private func monthButton(_ symbol: String, delta: Int) -> some View {
        Button {
            guard let next = Calendar.current.date(byAdding: .month, value: delta, to: month) else { return }
            month = next
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.ink)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Previous month" : "Next month")
    }

    private func dayButton(_ cell: DayCell) -> some View {
        let date = cell.date
        let key = date.map(DayStamp.key)
        let selected = key.map { dates.contains($0) } ?? false
        let today = date.map { Calendar.current.isDateInToday($0) } ?? false
        let past = date.map { Calendar.current.startOfDay(for: $0) < Calendar.current.startOfDay(for: .now) } ?? false
        return Button {
            guard let key, !past else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if selected { dates.remove(key) } else if dates.count < 31 { dates.insert(key) }
        } label: {
            Text(date.map { String(Calendar.current.component(.day, from: $0)) } ?? "")
                .font(.subheadline.weight(selected || today ? .semibold : .regular))
                .foregroundStyle(selected ? palette.onInverse : (past ? palette.tertiary : (today ? palette.ink : palette.secondary)))
                .frame(width: 34, height: 34)
                .background {
                    if selected { Circle().fill(palette.ink) }
                }
        }
        .buttonStyle(.plain)
        .disabled(date == nil || past)
        .accessibilityLabel(date?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? "")
    }
}

private struct TaskSlide<Content: View>: View {
    var enabled: Bool
    var onTap: () -> Void
    var delete: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            Image(systemName: "trash")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(offset < -6 ? 1 : 0)
                .onTapGesture { delete() }
            content()
                .offset(x: offset)
                .onTapGesture {
                    if offset != 0 { offset = 0 } else { onTap() }
                }
                .gesture(enabled ? slide : nil)
        }
    }

    private var slide: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(0, max(value.translation.width, -88))
            }
            .onEnded { value in
                if value.translation.width < -110 {
                    delete()
                    offset = 0
                } else if value.translation.width < -40 {
                    offset = -56
                } else {
                    offset = 0
                }
            }
    }
}

private struct PersonProfile: View {
    let person: PortalPerson
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private var current: PortalPerson {
        app.portal.homes.lazy.flatMap(\.people).first { $0.id == person.id } ?? person
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(initials)
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 156, height: 156)
                    .background(AvatarTint.color(for: current.id, among: app.portal.active.workers.map(\.id) + app.portal.active.members.map(\.id)), in: Circle())
                    .padding(.top, 8)
                Text(current.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                StaffCodeCopy(phone: current.phone, height: 52, inset: 22)
                    .padding(.bottom, 12)
                if let kind = current.kind {
                    detailRow("Category") { categoryPill(kind) }
                }
                if !current.phone.isEmpty {
                    detailRow("Phone", current.phone)
                }
                if !current.hours.isEmpty {
                    detailRow("Hours", current.hours)
                }
                if !current.dayLabel.isEmpty {
                    detailRow("Days", current.dayLabel)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(palette.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    PersonEditor(person: current)
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit")
                Button {
                    app.removePerson(current.id)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete")
            }
        }
        .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
    }

    private var initials: String {
        current.name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        detailRow(title) {
            Text(value)
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private func detailRow<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(palette.secondary)
                Spacer(minLength: 12)
                value()
            }
            .padding(.horizontal, 22)
            .frame(minHeight: 52)
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
                .padding(.horizontal, 22)
        }
    }
}

private enum TaskHand: Equatable {
    case move, copy
}

private struct TaskAimBar: View {
    var aim: TaskHand?
    var choose: (TaskHand) -> Void
    var delete: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 8) {
            if aim != nil {
                Text("Tap a worker")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
            }
            HStack(spacing: 8) {
                aimButton("Move", .move)
                aimButton("Copy", .copy)
                Button(action: delete) {
                    Text("Delete")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(palette.fill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(palette.canvas)
    }

    private func aimButton(_ title: String, _ hand: TaskHand) -> some View {
        let on = aim == hand
        return Button {
            choose(hand)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? palette.onInverse : palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(on ? palette.inverse : palette.fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct PersonEditor: View {
    let person: PortalPerson
    var creating = false
    var drawer = false
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var dial = DialCodes.all[0]
    @State private var digits = ""
    @State private var starts = Date()
    @State private var ends = Date()
    @State private var kind: WorkerKind?
    @State private var salary = ""
    @State private var incentive = "0"
    @State private var days: Set<Int> = [1, 2, 3, 4, 5, 6, 7]

    init(person: PortalPerson, creating: Bool = false, drawer: Bool = false) {
        self.person = person
        self.creating = creating
        self.drawer = drawer
        let week: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
        _days = State(initialValue: creating && person.days.isEmpty ? week : Set(person.days))
    }
    @State private var choosingKind = false
    @State private var choosingCode = false
    @State private var choosingHours = false
    @State private var seeded = false
    @State private var confirmingDelete = false
    @State private var photo: UIImage?
    @State private var photoChanged = false
    @State private var pickingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var saving = false
    @State private var photoError = false
    @State private var contactHits: [ContactHit] = []
    @State private var filledContact = ""
    @FocusState private var typingName: Bool

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Button {
                        pickingPhoto = true
                    } label: {
                        portraitMark
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo")
                    Text(person.portrait.isEmpty && photo == nil ? "Add photo" : "Change photo")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            Section {
                editorRow("Name") {
                    TextField("Name", text: $name)
                        .multilineTextAlignment(.trailing)
                        .focused($typingName)
                        .submitLabel(.next)
                        .onSubmit { typingName = false }
                }
                if creating, typingName, !contactHits.isEmpty {
                    contactCard
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(palette.canvas)
                        .listRowSeparator(.hidden)
                }
                HStack(spacing: 8) {
                    Button {
                        choosingCode = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(dial.dial)
                                .font(.body.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(palette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    TextField("00000 00000", text: $digits)
                        .keyboardType(.phonePad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .onChange(of: digits) { _, value in
                            let next = String(value.filter(\.isNumber).prefix(dial.length))
                            if next != value { digits = next }
                        }
                }
                .listRowBackground(palette.canvas)
                .listRowSeparatorTint(palette.line)
                Button {
                    choosingHours = true
                } label: {
                    HStack(spacing: 12) {
                        Text("Hours")
                            .foregroundStyle(palette.ink)
                        Spacer(minLength: 12)
                        Text("\(ClockText.label(starts))–\(ClockText.label(ends))")
                            .foregroundStyle(palette.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(palette.canvas)
                .listRowSeparatorTint(palette.line)
                editorRow("Salary") {
                    TextField("Monthly", text: $salary)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: salary) { _, value in
                            let next = value.filter(\.isNumber)
                            if next != value { salary = next }
                        }
                }
                editorRow("Yearly incentive") {
                    TextField("0", text: $incentive)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: incentive) { _, value in
                            let next = value.filter(\.isNumber)
                            if next != value { incentive = next }
                        }
                }
                Button {
                    choosingKind = true
                } label: {
                    HStack(spacing: 12) {
                        Text("Category")
                            .foregroundStyle(palette.ink)
                        Spacer(minLength: 12)
                        Text(kind?.rawValue ?? "Choose")
                            .foregroundStyle(kind == nil ? palette.tertiary : palette.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(palette.canvas)
                .listRowSeparatorTint(palette.line)
                dayRow
            }
            if !creating {
                Section {
                    Button("Delete worker", role: .destructive) {
                        confirmingDelete = true
                    }
                    .listRowBackground(palette.canvas)
                }
            }
        }
        .listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .background(palette.canvas)
        .navigationTitle(creating ? "Add" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if drawer {
                    Button(role: .close) { dismiss() }
                } else {
                    Button("Back", systemImage: "chevron.backward") { dismiss() }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await commit() }
                } label: {
                    if saving {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .disabled(saving)
                .accessibilityLabel("Save")
            }
        }
        .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    photo = image
                    photoChanged = true
                }
                photoItem = nil
            }
        }
        .alert("Could not save the photo", isPresented: $photoError) {
            Button("OK", role: .cancel) {}
        }
        .onAppear {
            guard !seeded else { return }
            seeded = true
            name = person.name
            let split = Self.splitPhone(person.phone)
            dial = split.code
            digits = split.digits
            let clocks = ClockText.span(person.hours)
            starts = clocks.starts
            ends = clocks.ends
            kind = person.kind
            salary = person.salary
            incentive = person.incentive.isEmpty ? "0" : person.incentive
            days = creating && person.days.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : Set(person.days)
        }
        .task(id: name) {
            guard creating else { return }
            let current = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current != filledContact else {
                contactHits = []
                return
            }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let found = await ContactBook.search(current)
            guard typingName else { return }
            withAnimation(.smooth(duration: 0.2)) { contactHits = found }
        }
        .onChange(of: typingName) { _, typing in
            guard !typing else { return }
            withAnimation(.smooth(duration: 0.2)) { contactHits = [] }
        }
        .sheet(isPresented: $choosingKind) {
            PersonKindSheet(kind: $kind)
        }
        .sheet(isPresented: $choosingCode) {
            CodeSheet { code in
                dial = code
                digits = String(digits.filter(\.isNumber).prefix(code.length))
                choosingCode = false
            }
        }
        .sheet(isPresented: $choosingHours) {
            PersonHoursSheet(starts: $starts, ends: $ends)
        }
        .alert("Delete \(name.isEmpty ? "this worker" : name)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                app.removePerson(person.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their tasks stay on the rooms.")
        }
    }

    private var portraitMark: some View {
        Group {
            if let photo {
                profileAvatar(photo, empty: "plus", palette: palette, size: 84)
            } else if let url = URL(string: person.portrait), !person.portrait.isEmpty {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        profileAvatar(nil, empty: "plus", palette: palette, size: 84)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(Circle())
            } else {
                profileAvatar(nil, empty: "plus", palette: palette, size: 84)
            }
        }
    }

    private func commit() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard digits.count == dial.length else { return }
        guard !salary.isEmpty else { return }
        guard !incentive.isEmpty else { return }
        guard kind != nil else {
            choosingKind = true
            return
        }
        saving = true
        defer { saving = false }
        var updated = person
        if updated.id.trimmingCharacters(in: .whitespaces).isEmpty {
            updated.id = UUID().uuidString
        }
        if photoChanged, let photo {
            guard let url = await PortraitStore.upload(photo, id: updated.id) else {
                photoError = true
                return
            }
            updated.portrait = url
        }
        updated.name = trimmed
        updated.phone = "\(dial.dial) \(digits)"
        updated.salary = salary
        updated.incentive = incentive
        updated.days = [2, 3, 4, 5, 6, 7, 1].filter { days.contains($0) }
        let span = "\(ClockText.label(starts))–\(ClockText.label(ends))"
        if let kind {
            updated.detail = "\(kind.rawValue) · \(span)"
        } else {
            updated.detail = span
        }
        if creating { app.addPerson(updated) } else { app.savePerson(updated) }
        dismiss()
    }

    private var contactCard: some View {
        let shown = Array(contactHits.prefix(4))
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, hit in
                Button {
                    fill(hit)
                } label: {
                    HStack(spacing: 12) {
                        Text(personInitials(hit.name))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.ink)
                            .frame(width: 36, height: 36)
                            .background(palette.fill, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.name)
                                .font(.body)
                                .foregroundStyle(palette.ink)
                                .lineLimit(1)
                            if !hit.detail.isEmpty {
                                Text(hit.detail)
                                    .font(.caption)
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < shown.count - 1 {
                    Rectangle()
                        .fill(palette.line)
                        .frame(height: 0.5)
                        .padding(.leading, 62)
                }
            }
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.line, lineWidth: 0.5)
        }
    }

    private func fill(_ hit: ContactHit) {
        name = hit.name
        filledContact = hit.name
        contactHits = []
        typingName = false
        if let code = DialCodes.all.first(where: { $0.dial == hit.dial }) {
            dial = code
        }
        digits = String(hit.phone.filter(\.isNumber).prefix(dial.length))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private static func splitPhone(_ stored: String) -> (code: DialCode, digits: String) {
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        let code = DialCodes.all.sorted { $0.dial.count > $1.dial.count }.first { trimmed.hasPrefix($0.dial) } ?? DialCodes.all[0]
        let rest = trimmed.hasPrefix(code.dial) ? String(trimmed.dropFirst(code.dial.count)) : trimmed
        return (code, String(rest.filter(\.isNumber).prefix(code.length)))
    }

    private var dayRow: some View {
        let week: [(number: Int, letter: String)] = [
            (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Days")
                .foregroundStyle(palette.ink)
            HStack(spacing: 0) {
                ForEach(week, id: \.number) { day in
                    let on = days.contains(day.number)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if on { days.remove(day.number) } else { days.insert(day.number) }
                    } label: {
                        Text(day.letter)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(white: 0.1))
                            .frame(width: 34, height: 34)
                            .background {
                                Circle().fill(on ? Aurora.arc[Aurora.arc.count - 1] : Aurora.arc[1])
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(on ? "\(day.letter) on" : "\(day.letter) off")
                }
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(palette.canvas)
        .listRowSeparatorTint(palette.line)
    }

    private func editorRow<Field: View>(_ title: String, @ViewBuilder field: () -> Field) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(palette.ink)
            field()
                .foregroundStyle(palette.ink)
        }
        .listRowBackground(palette.canvas)
        .listRowSeparatorTint(palette.line)
    }
}

private struct ContactBox: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.onPick = onPick
        context.coordinator.close = { isPresented = false }
        guard isPresented, controller.presentedViewController == nil else { return }
        DispatchQueue.main.async {
            guard isPresented, controller.presentedViewController == nil else { return }
            let host = controller.view.window?.rootViewController?.presentedViewController ?? controller
            var top = host
            while let next = top.presentedViewController { top = next }
            guard !(top is CNContactPickerViewController) else { return }
            let picker = CNContactPickerViewController()
            picker.delegate = context.coordinator
            picker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey]
            top.present(picker, animated: true)
        }
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var onPick: (String, String) -> Void = { _, _ in }
        var close: () -> Void = {}

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let first = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
            let last = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = contact.phoneNumbers.first?.value.stringValue ?? ""
            onPick(name, raw)
            close()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            close()
        }
    }
}

private final class StaffMarks {
    static let shared = StaffMarks()
    var dragging = false
}

private final class StaffDot: UIView {
    var personID = ""
}

private final class StaffDots {
    static let shared = StaffDots()
    var views: [ObjectIdentifier: StaffDot] = [:]

    func note(_ view: StaffDot) {
        views[ObjectIdentifier(view)] = view
    }

    func forget(_ view: StaffDot) {
        views[ObjectIdentifier(view)] = nil
    }
}

private struct StaffDotMark: UIViewRepresentable {
    var id: String

    func makeUIView(context: Context) -> StaffDot {
        let view = StaffDot()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.personID = id
        StaffDots.shared.note(view)
        return view
    }

    func updateUIView(_ uiView: StaffDot, context: Context) {
        uiView.personID = id
        StaffDots.shared.note(uiView)
    }

    static func dismantleUIView(_ uiView: StaffDot, coordinator: ()) {
        StaffDots.shared.forget(uiView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: StaffDot, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

private struct StaffScrollDrop: UIViewRepresentable {
    var ids: [String]
    var column: CGFloat
    var spacing: CGFloat
    var leading: CGFloat
    var accepts: (String) -> Bool
    var hover: (String?) -> Void
    var receive: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> StaffDropAnchor {
        let view = StaffDropAnchor()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onLayout = { [weak view] in
            guard let view else { return }
            context.coordinator.attach(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: StaffDropAnchor, context: Context) {
        context.coordinator.ids = ids
        context.coordinator.column = column
        context.coordinator.spacing = spacing
        context.coordinator.leading = leading
        context.coordinator.accepts = accepts
        context.coordinator.hover = hover
        context.coordinator.receive = receive
        context.coordinator.attach(from: uiView)
    }

    static func dismantleUIView(_ uiView: StaffDropAnchor, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIDropInteractionDelegate {
        var ids: [String] = []
        var column: CGFloat = 64
        var spacing: CGFloat = 14
        var leading: CGFloat = 2
        var accepts: (String) -> Bool = { _ in true }
        var hover: (String?) -> Void = { _ in }
        var receive: (String, String) -> Void = { _, _ in }
        private weak var scroller: UIScrollView?
        private var interaction: UIDropInteraction?

        func attach(from anchor: UIView) {
            DispatchQueue.main.async { [weak self, weak anchor] in
                guard let self, let anchor else { return }
                guard let scroll = anchor.ancestorStaffScroll(), scroll !== self.scroller else { return }
                self.detach()
                let drop = UIDropInteraction(delegate: self)
                scroll.addInteraction(drop)
                self.scroller = scroll
                self.interaction = drop
            }
        }

        func detach() {
            if let scroller, let interaction {
                scroller.removeInteraction(interaction)
            }
            scroller = nil
            interaction = nil
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            session.canLoadObjects(ofClass: NSString.self)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
            aim(session)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            hover(nil)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            aim(session)
            guard let scroll = scroller, worker(in: session, scroll: scroll) != nil else {
                return UIDropProposal(operation: .forbidden)
            }
            return UIDropProposal(operation: .move)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            guard let scroll = scroller, let id = worker(in: session, scroll: scroll) else {
                hover(nil)
                return
            }
            DragFeedback.placed()
            session.loadObjects(ofClass: NSString.self) { items in
                let payload = items.first as? String ?? ""
                DispatchQueue.main.async { self.receive(payload, id) }
            }
        }

        private func aim(_ session: UIDropSession) {
            guard let scroll = scroller else { return }
            hover(worker(in: session, scroll: scroll))
        }

        private func worker(in session: UIDropSession, scroll: UIScrollView) -> String? {
            guard let window = scroll.window else { return nil }
            let point = scroll.convert(session.location(in: window), from: window)
            let pitch = column + spacing
            let slot = Int(floor((point.x - leading + spacing / 2) / pitch))
            guard scroll.bounds.contains(point), !ids.isEmpty else { return nil }
            let id = ids[min(max(slot, 0), ids.count - 1)]
            return accepts(id) ? id : nil
        }
    }
}

private final class StaffDropAnchor: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private extension UIView {
    func ancestorStaffScroll() -> UIScrollView? {
        var current: UIView? = superview
        while let next = current {
            if let scroll = next as? UIScrollView, scroll.bounds.height > 40, scroll.bounds.height < 180 {
                return scroll
            }
            current = next.superview
        }
        return nil
    }
}

private struct WorkerDropTarget: UIViewRepresentable {
    var enter: () -> Void
    var leave: () -> Void
    var receive: (String) -> Void
    var tap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.addInteraction(UIDropInteraction(delegate: context.coordinator))
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped)))
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIDropInteractionDelegate {
        var parent: WorkerDropTarget
        init(_ parent: WorkerDropTarget) { self.parent = parent }

        @objc func tapped() { parent.tap() }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            session.canLoadObjects(ofClass: NSString.self)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
            parent.enter()
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            parent.leave()
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: .move)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            session.loadObjects(ofClass: NSString.self) { items in
                let payload = items.first as? String ?? ""
                DispatchQueue.main.async { self.parent.receive(payload) }
            }
        }
    }
}

private struct PersonHoursSheet: View {
    @Binding var starts: Date
    @Binding var ends: Date
    @Environment(\.dismiss) private var dismiss
    @State private var ending = false
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Picker("Hours", selection: $ending) {
                    Text("Starts").tag(false)
                    Text("Ends").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 22)
                DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "en_US"))
            }
            .navigationTitle("Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .onAppear { date = starts }
        .onChange(of: ending) { _, isEnd in
            date = isEnd ? ends : starts
        }
        .onChange(of: date) { _, value in
            if ending { ends = value } else { starts = value }
        }
    }
}

private struct PersonKindSheet: View {
    @Binding var kind: WorkerKind?
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(WorkerKind.allCases) { item in
                    Button {
                        kind = item
                        dismiss()
                    } label: {
                        HStack {
                            Text(item.rawValue)
                                .foregroundStyle(palette.ink)
                            Spacer()
                            if kind == item {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(palette.ink)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(palette.canvas)
                    .listRowSeparatorTint(palette.line)
                }
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .background(palette.canvas)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }
}

private struct TaskDrawer: View {
    let task: PortalTask
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(task.title)
                .font(.title3.weight(.semibold))
            if !task.worker.isEmpty {
                Text(task.worker)
                    .font(.body)
                    .foregroundStyle(palette.secondary)
            }
            if !task.place.isEmpty {
                Text(task.place)
                    .font(.body)
                    .foregroundStyle(palette.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Photo")
                    .font(.headline)
                Text("No photo submitted.")
                    .font(.body)
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                    .background(palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(22)
        .background(palette.canvas)
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }
}

private struct CommunityTab: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var posting = false
    @State private var opened: CommunityPost?

    var body: some View {
        let home = app.portal.active
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = app.postError {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(palette.secondary)
                    }
                    if app.postingJob {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if app.posts.isEmpty && !app.postingJob {
                        Text(home.community.isEmpty
                             ? "No requests yet."
                             : "No requests in \(home.community) yet.")
                            .font(.body)
                            .foregroundStyle(palette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        ForEach(app.posts) { post in
                            RequestCard(post: post, mine: post.authorId == app.me) {
                                opened = post
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .refreshable { await app.loadPosts() }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .toolbarBackground(palette.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .homeSwitcher()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        posting = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Post a job")
                }
            }
            .sheet(isPresented: $posting) {
                CommunityPostSheet(homes: app.portal.homes, homeID: home.id) { hours, salary, dates, tasks, kind, homeID in
                    let chosen = app.portal.homes.first { $0.id == homeID }
                    app.sendRequest(
                        text: RequestBody.written(hours: hours, salary: salary, dates: dates, tasks: tasks, door: chosen?.line ?? "", floor: chosen?.floor ?? 0),
                        kind: kind,
                        homeID: homeID
                    )
                }
            }
            .sheet(item: $opened) { post in
                RequestDrawer(post: post, mine: post.authorId == app.me) {
                    opened = nil
                    app.closePost(post)
                }
            }
            .task(id: home.communityKey) { await app.loadPosts() }
        }
    }
}

private enum CoverDates {
    static func label(_ key: String) -> String {
        guard let date = DayStamp.date(key) else { return key }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func ago(_ date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes) \(minutes == 1 ? "min" : "mins") ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) \(hours == 1 ? "hour" : "hours") ago" }
        let days = hours / 24
        if days < 30 { return "\(days) \(days == 1 ? "day" : "days") ago" }
        let months = days / 30
        if months < 12 { return "\(months) \(months == 1 ? "month" : "months") ago" }
        let years = months / 12
        return "\(years) \(years == 1 ? "year" : "years") ago"
    }

    static func summary(_ keys: [String]) -> String {
        let dates = keys.compactMap(DayStamp.date).sorted()
        guard let first = dates.first else { return "" }
        if dates.count == 1 { return label(DayStamp.key(first)) }
        guard let last = dates.last else { return "" }
        let calendar = Calendar.current
        let span = calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: last)).day ?? 0
        if span == dates.count - 1 {
            if calendar.isDate(first, equalTo: last, toGranularity: .month) {
                return "\(calendar.component(.day, from: first))–\(last.formatted(.dateTime.day().month(.abbreviated)))"
            }
            return "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
        }
        let shown = dates.prefix(2).map { label(DayStamp.key($0)) }
        let extra = dates.count - shown.count
        return shown.joined(separator: ", ") + (extra > 0 ? " +\(extra)" : "")
    }
}

private struct RequestBody {
    var hours: String?
    var dates: [String]
    var salary: String?
    var door: String?
    var floor: Int?
    var groups: [RequestGroup]
    var note: String?

    static func parse(_ details: String) -> RequestBody {
        var hours: String?
        var dates: [String] = []
        var salary: String?
        var door: String?
        var floor: Int?
        var groups: [RequestGroup] = []
        var loose: [String] = []
        for raw in details.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("Hours:") {
                hours = String(line.dropFirst("Hours:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Dates:") {
                dates = String(line.dropFirst("Dates:".count))
                    .split(separator: " ")
                    .map(String.init)
                    .filter { DayStamp.date($0) != nil }
                    .sorted()
            } else if line.hasPrefix("Days:") {
                continue
            } else if line.hasPrefix("Salary:") {
                salary = String(line.dropFirst("Salary:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Door:") {
                let number = String(line.dropFirst("Door:".count)).trimmingCharacters(in: .whitespaces)
                if !number.isEmpty { door = number }
            } else if line.hasPrefix("Floor:") {
                let number = String(line.dropFirst("Floor:".count)).trimmingCharacters(in: .whitespaces)
                if let value = Int(number), (1...40).contains(value) { floor = value }
            } else if line.hasPrefix("•") {
                let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
                let parts = body.components(separatedBy: " — ")
                let place = parts.count >= 2 ? parts[0] : ""
                let title = parts.count >= 2 ? parts.dropFirst().joined(separator: " — ") : body
                if let index = groups.lastIndex(where: { $0.place == place }) {
                    groups[index].tasks.append(title)
                } else {
                    groups.append(RequestGroup(id: "\(groups.count)-\(place)", place: place, tasks: [title]))
                }
            } else {
                loose.append(line)
            }
        }
        if groups.isEmpty, !loose.isEmpty, hours != nil || salary != nil {
            groups.append(RequestGroup(id: "loose", place: "", tasks: loose))
        }
        let note = hours == nil && salary == nil && dates.isEmpty ? details.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return RequestBody(hours: hours, dates: dates, salary: salary, door: door, floor: floor, groups: groups, note: note)
    }

    static func written(hours: String, salary: String, dates: [String], tasks: [TaskPostItem], door: String = "", floor: Int = 0) -> String {
        var lines = ["Hours: \(hours)"]
        if !dates.isEmpty { lines.append("Dates: \(dates.sorted().joined(separator: " "))") }
        let amount = salary.filter(\.isNumber)
        lines.append("Salary: ₹\(amount)")
        let number = door.trimmingCharacters(in: .whitespacesAndNewlines)
        if !number.isEmpty { lines.append("Door: \(number)") }
        if (1...40).contains(floor) { lines.append("Floor: \(floor)") }
        for task in tasks {
            lines.append("• \(task.place.isEmpty ? task.title : "\(task.place) — \(task.title)")")
        }
        return lines.joined(separator: "\n")
    }

    static func money(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let digits = raw.filter(\.isNumber)
        guard let value = Int(digits) else { return raw.isEmpty ? nil : raw }
        return "₹\(value.formatted(.number.grouping(.automatic)))"
    }

    static func hoursLine(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let separated = trimmed
            .replacingOccurrences(of: "—", with: " – ")
            .replacingOccurrences(of: "–", with: " – ")
            .replacingOccurrences(of: " - ", with: " – ")
        return separated.replacingOccurrences(of: "  –  ", with: " – ")
    }

    static func schedule(_ dates: [String], hours: String?) -> String {
        let when = CoverDates.summary(dates)
        let clock = hoursLine(hours) ?? ""
        if when.isEmpty { return clock }
        if clock.isEmpty { return when }
        return "\(when) · \(clock)"
    }

    var lines: [(place: String, title: String)] {
        groups.flatMap { group in group.tasks.map { (group.place, $0) } }
    }
}

private struct RequestGroup: Identifiable {
    var id: String
    var place: String
    var tasks: [String]
}

private struct RequestCard: View {
    var post: CommunityPost
    var mine: Bool
    var open: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: open) {
            RequestFace(post: post, mine: mine, parsed: RequestBody.parse(post.details))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct RequestFace: View {
    var post: CommunityPost
    var mine: Bool
    var parsed: RequestBody
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var door = ""
    var floor = 0

    var body: some View {
        let kind = WorkerKind(rawValue: post.kind)
        let who = mine ? "You" : (post.authorName.isEmpty ? "A home" : post.authorName)
        let posted = "\(CoverDates.ago(post.createdAt)) · \(post.createdAt.formatted(.dateTime.day().month(.abbreviated)))"
        let needed = RequestBody.schedule(parsed.dates, hours: parsed.hours)
        let place = RequestFace.placeLine(door: door, floor: floor)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                faceAvatar(who)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(who)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let kind {
                            categoryPill(kind)
                        }
                    }
                    Text(posted)
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if !needed.isEmpty {
                    Text(needed)
                        .font(.subheadline)
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if parsed.groups.isEmpty, let note = parsed.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
                if let money = RequestBody.money(parsed.salary) {
                    Text(money)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                }
            }
            if !place.isEmpty {
                Text(place)
                    .font(.subheadline)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
            }
        }
    }

    static func placeLine(door: String, floor: Int) -> String {
        let number = door.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !number.isEmpty { parts.append("Door \(number)") }
        if (1...40).contains(floor) { parts.append("Floor \(floor)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func faceAvatar(_ name: String) -> some View {
        if mine {
            profileAvatar(app.photo, empty: "person", palette: palette, size: 36)
        } else {
            AvatarMark(
                person: PortalPerson(id: post.authorId.uuidString, name: name, detail: "", phone: ""),
                roster: [post.authorId.uuidString],
                size: 36
            )
        }
    }
}

private struct RequestDrawer: View {
    var post: CommunityPost
    var mine: Bool
    var close: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirming = false

    private var live: CommunityPost {
        app.posts.first { $0.id == post.id } ?? post
    }

    var body: some View {
        let parsed = RequestBody.parse(live.details)
        let door = shownDoor(parsed)
        let floor = shownFloor(parsed)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RequestFace(post: live, mine: mine, parsed: parsed, door: door, floor: floor)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    if !door.isEmpty || floor > 0 {
                        VStack(spacing: 0) {
                            if !door.isEmpty {
                                placeRow("Door", door)
                            }
                            if !door.isEmpty, floor > 0 {
                                Rectangle()
                                    .fill(palette.line)
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                            }
                            if floor > 0 {
                                placeRow("Floor", "\(floor)")
                            }
                        }
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if !parsed.dates.isEmpty {
                        section("Dates") {
                            VStack(spacing: 0) {
                                ForEach(Array(parsed.dates.enumerated()), id: \.element) { index, day in
                                    if index > 0 {
                                        Rectangle()
                                            .fill(palette.line)
                                            .frame(height: 1)
                                            .padding(.horizontal, 16)
                                    }
                                    HStack(spacing: 12) {
                                        Text(CoverDates.label(day))
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(palette.ink)
                                        Spacer(minLength: 12)
                                        if let hours = RequestBody.hoursLine(parsed.hours) {
                                            Text(hours)
                                                .font(.subheadline)
                                                .foregroundStyle(palette.secondary)
                                                .multilineTextAlignment(.trailing)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 52)
                                }
                            }
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    if !parsed.groups.isEmpty {
                        section("Tasks") {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(parsed.groups) { group in
                                    VStack(alignment: .leading, spacing: 8) {
                                        if !group.place.isEmpty {
                                            Text(group.place)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(palette.ink)
                                        }
                                        ForEach(Array(group.tasks.enumerated()), id: \.offset) { _, task in
                                            Text(task)
                                                .font(.callout)
                                                .foregroundStyle(palette.ink)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 14)
                                                .frame(height: 48)
                                                .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    } else if let note = parsed.note, !note.isEmpty {
                        Text(note)
                            .font(.body)
                            .foregroundStyle(palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(palette.canvas)
            .navigationTitle("Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if mine {
                    HStack(spacing: 10) {
                        Button {
                            editing = true
                        } label: {
                            Text("Edit")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(palette.onInverse)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(palette.inverse, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            confirming = true
                        } label: {
                            Text("Delete")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(palette.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(palette.fill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(palette.canvas)
                }
            }
            .sheet(isPresented: $editing) {
                editor(RequestBody.parse(live.details))
            }
            .alert("Delete this request?", isPresented: $confirming) {
                Button("Delete", role: .destructive, action: close)
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }

    private var ownsPost: Bool {
        if let me = app.me, live.authorId == me { return true }
        if mine { return true }
        let author = live.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = app.owner.first.trimmingCharacters(in: .whitespacesAndNewlines)
        return !author.isEmpty && !first.isEmpty && author.caseInsensitiveCompare(first) == .orderedSame
    }

    private func shownDoor(_ parsed: RequestBody) -> String {
        if let door = parsed.door?.trimmingCharacters(in: .whitespacesAndNewlines), !door.isEmpty { return door }
        guard ownsPost else { return "" }
        return app.portal.active.line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shownFloor(_ parsed: RequestBody) -> Int {
        if let floor = parsed.floor, (1...40).contains(floor) { return floor }
        guard ownsPost else { return 0 }
        let floor = app.portal.active.floor
        return (1...40).contains(floor) ? floor : 0
    }

    private func placeRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(palette.secondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 4)
            content()
        }
    }

    @ViewBuilder
    private func editor(_ parsed: RequestBody) -> some View {
        if parsed.groups.isEmpty {
            RequestSheet(
                community: app.portal.active.community,
                initialText: live.details,
                initialKind: WorkerKind(rawValue: live.kind),
                editing: true
            ) { text, kind in
                app.updatePost(live, text: text, kind: kind)
            }
        } else {
            let tasks = parsed.groups.flatMap { group in
                group.tasks.enumerated().map { index, title in
                    TaskPostItem(id: "\(group.id)-\(index)", place: group.place, title: title)
                }
            }
            TaskPostSheet(
                homes: [app.portal.active],
                homeID: app.portal.active.id,
                hours: parsed.hours ?? "",
                tasks: tasks,
                offered: parsed.salary ?? "",
                dates: Set(parsed.dates),
                title: "Edit",
                commit: "Save"
            ) { hours, salary, dates, _ in
                app.updatePost(
                    live,
                    text: RequestBody.written(hours: hours, salary: salary, dates: dates, tasks: tasks, door: parsed.door ?? app.portal.active.line, floor: parsed.floor ?? app.portal.active.floor),
                    kind: WorkerKind(rawValue: live.kind)
                )
            }
        }
    }
}

private struct HomeSwitcher: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        Menu {
            Picker("Homes", selection: Binding(
                get: { app.portal.activeHomeID },
                set: { app.selectHome($0) }
            )) {
                ForEach(app.portal.homes) { home in
                    Text(Self.menuLine(home.name)).tag(home.id)
                }
            }
            Divider()
            Button("Add new home", systemImage: "plus") {
                app.beginAddHome()
            }
        } label: {
            HStack(spacing: 4) {
                Text(app.portal.active.name.isEmpty ? "Home" : app.portal.active.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(palette.ink)
            .frame(maxWidth: 120, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Homes")
    }

    /// One menu line. Word joiners stop the system menu from wrapping or hyphenating, and a too-long name ends in an ellipsis.
    private static func menuLine(_ name: String) -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = clean.isEmpty ? "Home" : clean
        let font = UIFont.systemFont(ofSize: 17)
        let maxWidth = max(180, UIScreen.main.bounds.width - 108)
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        var shown = title
        if width(shown) > maxWidth {
            while shown.count > 1, width(shown + "…") > maxWidth {
                shown.removeLast()
            }
            shown += "…"
        }
        return shown.map(String.init).joined(separator: "\u{2060}")
    }
}

private struct HomeSwitcherBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HomeSwitcher()
                }
            }
    }
}

@Observable
private final class CalendarSession {
    var pill = CGRect.zero
    var grown = false
    var palette = Palette.light
}

private struct OwnerHeader: ViewModifier {
    @Binding var day: String?
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var profile = false
    @State private var calendar = false
    @State private var pill = CGRect.zero
    @State private var cover = false
    @State private var coverToken = 0
    @State private var session = CalendarSession()

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HomeSwitcher()
                }
                ToolbarSpacer(.fixed, placement: .topBarLeading)
                ToolbarItem(placement: .topBarLeading) {
                    DaySwitch(day: $day, open: $calendar, frame: $pill)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        profile = true
                    } label: {
                        Group {
                            if let photo = app.photo {
                                Image(uiImage: photo)
                                    .renderingMode(.original)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(palette.ink)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(palette.fill)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Profile")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .toolbarBackground(palette.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $profile) {
                ProfileSheet()
            }
            .background {
                CalendarWindow(visible: cover, session: session, day: $day, open: $calendar)
            }
            .onChange(of: pill) { _, next in
                session.pill = next
            }
            .onChange(of: palette) { _, next in
                session.palette = next
            }
            .onAppear { session.palette = palette }
            .onChange(of: calendar) { _, show in
                coverToken += 1
                let token = coverToken
                if show {
                    session.pill = pill
                    session.palette = palette
                    session.grown = false
                    cover = true
                } else {
                    session.grown = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(420))
                        if token == coverToken { cover = false }
                    }
                }
            }
    }
}

/// Draws the calendar in the window, so the date pill can grow in its own place above the navigation bar.
private struct CalendarWindow: UIViewRepresentable {
    var visible: Bool
    var session: CalendarSession
    @Binding var day: String?
    @Binding var open: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.session = session
        context.coordinator.day = $day
        context.coordinator.open = $open
        context.coordinator.visible = visible
        if uiView.window == nil {
            DispatchQueue.main.async { context.coordinator.sync(from: uiView) }
        } else {
            context.coordinator.sync(from: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var host: UIHostingController<CalendarCover>?
        var session = CalendarSession()
        var day: Binding<String?> = .constant(nil)
        var open: Binding<Bool> = .constant(false)
        var visible = false

        func sync(from anchor: UIView) {
            guard let window = anchor.window else { return }
            guard visible else {
                remove()
                return
            }
            if host == nil {
                let cover = CalendarCover(session: session, day: day, open: open)
                let host = UIHostingController(rootView: cover)
                host.view.backgroundColor = .clear
                host.safeAreaRegions = []
                self.host = host
            }
            guard let host else { return }
            host.overrideUserInterfaceStyle = session.palette == .dark ? .dark : .light
            if host.view.superview !== window {
                host.view.frame = window.bounds
                host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                window.addSubview(host.view)
            } else {
                host.view.frame = window.bounds
            }
        }

        func remove() {
            host?.view.removeFromSuperview()
            host = nil
        }
    }
}

private struct CalendarCover: View {
    var session: CalendarSession
    @Binding var day: String?
    @Binding var open: Bool

    var body: some View {
        PillExpand(pill: session.pill, grown: session.grown, palette: session.palette, close: { open = false }) {
            VStack(spacing: 0) {
                calendarHead
                DayCalendar(day: $day, open: $open)
            }
        }
        .onAppear {
            Task { @MainActor in session.grown = true }
        }
    }

    private var calendarHead: some View {
        let shown = day.flatMap(DayStamp.date) ?? Calendar.current.startOfDay(for: .now)
        let today = Calendar.current.isDateInToday(shown)
        return HStack(spacing: 0) {
            step("chevron.left", delta: -1, shown: shown)
            Spacer(minLength: 0)
            Button {
                open = false
            } label: {
                Text(today ? "Today" : shown.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(today ? session.palette.ink : session.palette.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            step("chevron.right", delta: 1, shown: shown)
        }
        .padding(.horizontal, 8)
        .frame(height: max(session.pill.height, 44))
    }

    private func step(_ symbol: String, delta: Int, shown: Date) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guard let next = Calendar.current.date(byAdding: .day, value: delta, to: shown) else { return }
            day = DayStamp.key(next)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(session.palette.ink)
                .frame(width: 22, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PillExpand<Content: View>: View {
    var pill: CGRect
    var grown: Bool
    var palette: Palette
    var close: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var fullHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let endWidth = max(pill.width, geo.size.width - 32)
            let width = grown ? endWidth : max(pill.width, 1)
            let limit = max(pill.height, geo.size.height - pill.minY - 12)
            let height = grown ? min(max(fullHeight, pill.height), limit) : max(pill.height, 1)
            let x = grown ? (geo.size.width - endWidth) / 2 : pill.minX
            let y = pill.minY
            let radius = grown ? 28.0 : max(pill.height, 1) / 2
            ZStack(alignment: .topLeading) {
                Color.black.opacity(grown ? 0.12 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                content()
                    .frame(width: endWidth, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .allowsHitTesting(false)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { fullHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, next in
                                    if abs(next - fullHeight) > 0.5 { fullHeight = next }
                                }
                        }
                    }
                content()
                    .frame(width: width, alignment: .topLeading)
                    .frame(width: width, height: height, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .position(x: x + width / 2, y: y + height / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.smooth(duration: 0.38), value: grown)
            .animation(.smooth(duration: 0.38), value: fullHeight)
        }
        .ignoresSafeArea()
        .environment(\.palette, palette)
        .environment(\.colorScheme, palette == .dark ? .dark : .light)
        .preferredColorScheme(palette == .dark ? .dark : .light)
    }
}

private struct ProfileSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var choosingAppearance = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 14) {
                        profileAvatar(app.photo, empty: "person", palette: palette)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.owner.name.isEmpty ? "You" : app.owner.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(palette.ink)
                            Text(app.owner.gender?.title ?? "Gender")
                                .font(.subheadline)
                                .foregroundStyle(palette.secondary)
                        }
                        Spacer(minLength: 8)
                        Button {
                            editing = true
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(palette.ink)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit")
                    }
                    .padding(16)
                    ForEach(options) { option in
                        Rectangle()
                            .fill(palette.line)
                            .frame(height: 1)
                            .padding(.horizontal, 16)
                        Button(action: option.action) {
                            HStack(spacing: 8) {
                                Text(option.title)
                                    .foregroundStyle(palette.ink)
                                Spacer(minLength: 8)
                                Text(option.value)
                                    .foregroundStyle(palette.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.tertiary)
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(22)
            }
            .background(palette.canvas)
            .safeAreaInset(edge: .bottom) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(280))
                        app.logOut()
                    }
                } label: {
                    Text("Log out")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(palette.fill, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(palette.canvas)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $editing) {
                ProfileEditor()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .sheet(isPresented: $choosingAppearance) {
                AppearanceWheel()
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }

    /// Rows under the person. A divider is drawn before each one, never after the last.
    private var options: [ProfileOption] {
        [
            ProfileOption(id: "appearance", title: "Appearance", value: app.theme.title) {
                choosingAppearance = true
            }
        ]
    }
}

private struct ProfileOption: Identifiable {
    var id: String
    var title: String
    var value: String
    var action: () -> Void
}

private struct AppearanceWheel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var theme: ThemeChoice = .system

    var body: some View {
        NavigationStack {
            Picker("Appearance", selection: $theme) {
                ForEach(ThemeChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        app.chooseTheme(theme)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .onAppear { theme = app.theme }
    }
}

private struct ProfileEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var last = ""
    @State private var gender: Gender?
    @State private var photo: UIImage?
    @State private var photoChanged = false
    @State private var picking = false
    @State private var photoItem: PhotosPickerItem?
    @State private var choosingGender = false
    @State private var seeded = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Button {
                        picking = true
                    } label: {
                        profileAvatar(photo, empty: "plus", palette: palette, size: 96)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Profile photo")
                    Text("Change photo")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            Section {
                profileRow("First name") {
                    TextField("First name", text: $first)
                        .textInputAutocapitalization(.words)
                        .multilineTextAlignment(.trailing)
                }
                profileRow("Last name") {
                    TextField("Last name", text: $last)
                        .textInputAutocapitalization(.words)
                        .multilineTextAlignment(.trailing)
                }
                Button {
                    choosingGender = true
                } label: {
                    HStack(spacing: 12) {
                        Text("Gender")
                            .foregroundStyle(palette.ink)
                        Spacer(minLength: 12)
                        Text(gender?.title ?? "Choose")
                            .foregroundStyle(gender == nil ? palette.tertiary : palette.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(palette.canvas)
                .listRowSeparatorTint(palette.line)
            }
        }
        .listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .background(palette.canvas)
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.backward") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.owner.first = first.trimmingCharacters(in: .whitespaces)
                    app.owner.last = last.trimmingCharacters(in: .whitespaces)
                    app.owner.gender = gender
                    if photoChanged { app.setPhoto(photo) }
                    app.saveOwner()
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("Save")
            }
        }
        .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        .photosPicker(isPresented: $picking, selection: $photoItem, matching: .images)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            first = app.owner.first
            last = app.owner.last
            gender = app.owner.gender
            photo = app.photo
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    photo = image
                    photoChanged = true
                }
                photoItem = nil
            }
        }
        .sheet(isPresented: $choosingGender) {
            ProfileGenderSheet(gender: $gender)
        }
    }

    private func profileRow<Field: View>(_ title: String, @ViewBuilder field: () -> Field) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(palette.ink)
            field()
                .foregroundStyle(palette.ink)
        }
        .listRowBackground(palette.canvas)
        .listRowSeparatorTint(palette.line)
    }
}

private struct ProfileGenderSheet: View {
    @Binding var gender: Gender?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Gender = .female

    var body: some View {
        NavigationStack {
            Picker("Gender", selection: $draft) {
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
                        gender = draft
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .onAppear { draft = gender ?? .female }
    }
}

private func categoryPill(_ kind: WorkerKind) -> some View {
    Text(kind.rawValue)
        .font(.caption.weight(.semibold))
        .foregroundStyle(kind.pill)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(kind.pill.opacity(0.16), in: Capsule())
}

private func profileAvatar(_ photo: UIImage?, empty: String, palette: Palette, size: CGFloat = 64) -> some View {
    ZStack {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: empty)
                .font(.body.weight(.medium))
                .foregroundStyle(palette.ink)
        }
    }
    .frame(width: size, height: size)
    .background(palette.canvas, in: Circle())
    .overlay { Circle().stroke(palette.line, lineWidth: 1) }
    .clipShape(Circle())
}

private struct HeaderPicker<Selection: Hashable & CaseIterable & RawRepresentable>: ViewModifier where Selection.RawValue == String, Selection.AllCases: RandomAccessCollection {
    @Binding var selection: Selection
    let title: String
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PaddedSegments(titles: Array(Selection.allCases), title: \.rawValue, selection: $selection)
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .toolbarBackground(palette.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct PaddedSegments<Selection: Hashable>: UIViewRepresentable {
    var titles: [Selection]
    var title: (Selection) -> String
    @Binding var selection: Selection

    private var segmentWidth: CGFloat { titles.count > 2 ? 100 : 118 }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: titles.map(title))
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        control.apportionsSegmentWidthsByContent = false
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.titles = titles
        context.coordinator.selection = $selection
        if control.numberOfSegments != titles.count {
            control.removeAllSegments()
            for (index, item) in titles.enumerated() {
                control.insertSegment(withTitle: title(item), at: index, animated: false)
            }
        }
        for (index, item) in titles.enumerated() {
            control.setTitle(title(item), forSegmentAt: index)
            control.setWidth(segmentWidth, forSegmentAt: index)
            if item == selection, control.selectedSegmentIndex != index {
                control.selectedSegmentIndex = index
            }
        }
        let height = control.constraints.first {
            $0.firstAttribute == .height && $0.secondItem == nil
        }
        if let height {
            if height.constant != 44 { height.constant = 44 }
        } else {
            control.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        CGSize(width: CGFloat(max(titles.count, 1)) * segmentWidth, height: 44)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(titles: titles, selection: $selection)
    }

    final class Coordinator: NSObject {
        var titles: [Selection]
        var selection: Binding<Selection>
        init(titles: [Selection], selection: Binding<Selection>) {
            self.titles = titles
            self.selection = selection
        }

        @objc func changed(_ control: UISegmentedControl) {
            let index = control.selectedSegmentIndex
            guard titles.indices.contains(index) else { return }
            selection.wrappedValue = titles[index]
        }
    }
}

private extension View {
    func betweenDivider(_ palette: Palette, last: Bool) -> some View {
        VStack(spacing: 0) {
            self
                .padding(.top, 14)
            if last {
                Color.clear.frame(height: 14)
            } else {
                Color.clear.frame(height: 14)
                Rectangle()
                    .fill(palette.line)
                    .frame(height: 1)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowBackground(palette.canvas)
        .listRowSeparator(.hidden)
    }

    func ownerHeader(day: Binding<String?>) -> some View {
        modifier(OwnerHeader(day: day))
    }

    func homeSwitcher() -> some View {
        modifier(HomeSwitcherBar())
    }

    func headerPicker<Selection: Hashable & CaseIterable & RawRepresentable>(
        _ title: String,
        selection: Binding<Selection>
    ) -> some View where Selection.RawValue == String, Selection.AllCases: RandomAccessCollection {
        modifier(HeaderPicker(selection: selection, title: title))
    }
}

struct WorkerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var cameraTask: WorkerTask?
    @State private var shooting = false
    @State private var pending: PendingShot?
    @State private var sending = false
    @State private var failure: String?
    @State private var profile = false

    private var place: WorkerPlace? {
        guard let desk = app.workerDesk else { return nil }
        return desk.homes.first { $0.id == app.workerHomeID } ?? desk.homes.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let place {
                        if place.rooms.isEmpty, place.cars.isEmpty {
                            Text("No tasks yet.")
                                .font(.callout)
                                .foregroundStyle(palette.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        ForEach(place.rooms) { cluster in
                            placeCard(cluster)
                        }
                        ForEach(place.cars) { cluster in
                            placeCard(cluster)
                        }
                    } else {
                        Text("No home yet.")
                            .font(.callout)
                            .foregroundStyle(palette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .refreshable { await app.refreshWorker() }
            .task { await app.refreshWorker() }
            .background(palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeMenu
                        .fixedSize(horizontal: true, vertical: false)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        profile = true
                    } label: {
                        workerMark
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Profile")
                }
                .sharedBackgroundVisibility((place?.portrait ?? "").isEmpty ? .automatic : .hidden)
            }
            .sheet(isPresented: $profile) {
                WorkerProfile(name: app.workerDesk?.name ?? "", portrait: place?.portrait ?? "")
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .toolbarBackground(palette.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .fullScreenCover(isPresented: $shooting, onDismiss: { cameraTask = nil }) {
                CameraPick { image in
                    let task = cameraTask
                    shooting = false
                    cameraTask = nil
                    if let task {
                        pending = PendingShot(task: task, image: image)
                    }
                } cancel: {
                    shooting = false
                    cameraTask = nil
                }
            }
            .sheet(item: $pending) { shot in
                ShotPreview(image: shot.image, busy: sending, retake: {
                    let task = shot.task
                    pending = nil
                    openCamera(task)
                }, submit: {
                    submit(shot)
                })
            }
            .alert("Could not save", isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private var workerMark: some View {
        let portrait = place?.portrait ?? ""
        return Group {
            if let url = URL(string: portrait), !portrait.isEmpty {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person")
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                Image(systemName: "person")
            }
        }
    }

    private var homeMenu: some View {
        let homes = app.workerDesk?.homes ?? []
        let title = place?.name ?? "Home"
        return Group {
            if homes.count > 1 {
                Menu {
                    ForEach(homes) { home in
                        Button {
                            app.selectWorkerHome(home.id)
                        } label: {
                            if home.id == (place?.id ?? "") {
                                Label(home.name, systemImage: "checkmark")
                            } else {
                                Text(home.name)
                            }
                        }
                    }
                } label: {
                    homeLabel(title, chevron: true)
                }
                .buttonStyle(.plain)
            } else {
                homeLabel(title, chevron: false)
            }
        }
        .foregroundStyle(palette.ink)
        .accessibilityLabel("Homes")
    }

    private func homeLabel(_ title: String, chevron: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
        }
    }

    private func placeCard(_ cluster: WorkerCluster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(cluster.title)
                .font(.body.weight(.medium))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            ForEach(cluster.tasks) { task in
                WorkerSwipe(done: task.done) {
                    if task.done {
                        undo(task)
                    } else if task.photo {
                        presentCapture(task)
                    } else {
                        submit(PendingShot(task: task, image: UIImage()))
                    }
                } content: {
                    taskRow(task)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func taskRow(_ task: WorkerTask) -> some View {
        HStack(spacing: 12) {
            Text(task.title)
                .font(.callout)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if task.done {
                Text("Done")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(palette.fill, in: Capsule())
            } else if task.photo {
                Image(systemName: "camera.fill")
                    .font(.caption2)
                    .foregroundStyle(palette.secondary)
            }
            if !task.detail.isEmpty {
                Text(task.detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(palette.fill, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func presentCapture(_ task: WorkerTask) {
        cameraTask = task
        Task { @MainActor in
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                cameraTask = nil
                failure = "A live photo is needed, and this device has no camera."
                return
            }
            shooting = true
        }
    }

    private func openCamera(_ task: WorkerTask) {
        presentCapture(task)
    }

    private func submit(_ shot: PendingShot) {
        guard !sending, let home = place?.id else { return }
        sending = true
        let photo = shot.image.size == .zero ? nil : jpeg(shot.image)
        Task {
            do {
                try await StaffAccess.finish(
                    home: home,
                    day: DayKey.today,
                    title: shot.task.title,
                    place: shot.task.place,
                    photo: photo
                )
                pending = nil
                await app.refreshWorker()
            } catch {
                let text = StaffAccess.message(error)
                if text.localizedCaseInsensitiveContains("photo") {
                    presentCapture(shot.task)
                } else {
                    failure = text
                }
            }
            sending = false
        }
    }

    private func undo(_ task: WorkerTask) {
        guard let home = place?.id else { return }
        Task {
            do {
                try await StaffAccess.revert(home: home, day: DayKey.today, title: task.title, place: task.place)
                await app.refreshWorker()
            } catch {
                failure = StaffAccess.message(error)
            }
        }
    }
}

private struct WorkerProfile: View {
    var name: String
    var portrait: String
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var choosingAppearance = false
    @State private var picking = false
    @State private var photoItem: PhotosPickerItem?
    @State private var saving = false
    @State private var failed = false

    private var locked: Bool { !portrait.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 10) {
                        portraitView
                        if !locked {
                            Button {
                                picking = true
                            } label: {
                                Text(saving ? "Saving photo" : "Add photo")
                                    .font(.subheadline)
                                    .foregroundStyle(palette.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(saving)
                        }
                        Text(name.isEmpty ? "You" : name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    Rectangle()
                        .fill(palette.line)
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                    Button {
                        choosingAppearance = true
                    } label: {
                        HStack(spacing: 8) {
                            Text("Appearance")
                                .foregroundStyle(palette.ink)
                            Spacer(minLength: 8)
                            Text(app.theme.title)
                                .foregroundStyle(palette.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.tertiary)
                        }
                        .padding(16)
                    }
                    .buttonStyle(.plain)
                }
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(22)
            }
            .background(palette.canvas)
            .safeAreaInset(edge: .bottom) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(280))
                        app.logOut()
                    }
                } label: {
                    Text("Log out")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(palette.fill, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(palette.canvas)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
            .photosPicker(isPresented: $picking, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item, !locked else { return }
                Task { await save(item) }
            }
            .alert("Could not save the photo", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
            .sheet(isPresented: $choosingAppearance) {
                AppearanceWheel()
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var portraitView: some View {
        if let url = URL(string: portrait), locked {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person")
                        .font(.title2)
                        .foregroundStyle(palette.ink)
                }
            }
            .frame(width: 84, height: 84)
            .background(palette.canvas, in: Circle())
            .clipShape(Circle())
        } else {
            Image(systemName: "person")
                .font(.title2)
                .foregroundStyle(palette.ink)
                .frame(width: 84, height: 84)
                .background(palette.canvas, in: Circle())
                .overlay { Circle().stroke(palette.line, lineWidth: 1) }
        }
    }

    private func save(_ item: PhotosPickerItem) async {
        saving = true
        defer { saving = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            photoItem = nil
            return
        }
        let maxSide: CGFloat = 640
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 0 ? min(1, maxSide / longest) : 1
        let size = CGSize(width: max(image.size.width * scale, 1), height: max(image.size.height * scale, 1))
        let jpeg = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.86) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        do {
            _ = try await StaffAccess.portrait(jpeg)
            await app.refreshWorker()
            dismiss()
        } catch {
            failed = true
        }
        photoItem = nil
    }
}

private struct PendingShot: Identifiable {
    var task: WorkerTask
    var image: UIImage
    var id: String { task.id }
}

private struct ProofLink: Identifiable {
    var url: URL
    var id: String { url.absoluteString }
}

private struct WorkerSwipe<Content: View>: View {
    var done: Bool
    var action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 1

    var body: some View {
        ZStack {
            HStack {
                if done {
                    Text("Undo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.leading, 16)
                    Spacer()
                } else {
                    Spacer()
                    Text("Done")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.trailing, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                (done ? Color.orange : Color(red: 0.29, green: 0.93, blue: 0.42)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(abs(offset) > 8 ? 1 : 0)
            content()
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 18, coordinateSpace: .local)
                        .onChanged { value in
                            let travel = value.translation.width
                            let limit = max(width, 1)
                            offset = done ? min(limit, max(0, travel)) : max(-limit, min(0, travel))
                        }
                        .onEnded { value in
                            let limit = max(width, 1)
                            let go = done ? value.translation.width > limit * 0.72 : value.translation.width < -limit * 0.72
                            if go {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeOut(duration: 0.16)) {
                                    offset = done ? limit : -limit
                                }
                                action()
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(180))
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                        offset = 0
                                    }
                                }
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    offset = 0
                                }
                            }
                        }
                )
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, next in width = next }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: done) { _, _ in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                offset = 0
            }
        }
    }
}

private struct SlideConfirm: View {
    var title: String
    var enabled: Bool
    var onConfirm: () -> Void
    @Environment(\.palette) private var palette
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let limit = max(0, proxy.size.width - 56)
            ZStack(alignment: .leading) {
                Capsule().fill(palette.fill)
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(enabled ? palette.secondary : palette.tertiary)
                    .frame(maxWidth: .infinity)
                Circle()
                    .fill(enabled ? palette.inverse : palette.surface)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(enabled ? palette.onInverse : palette.tertiary)
                    }
                    .padding(4)
                    .offset(x: drag)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard enabled else { return }
                                drag = min(limit, max(0, value.translation.width))
                            }
                            .onEnded { _ in
                                if enabled, limit > 0, drag > limit * 0.85 {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    onConfirm()
                                }
                                drag = 0
                            }
                    )
            }
        }
        .frame(height: 56)
        .opacity(enabled ? 1 : 0.72)
        .allowsHitTesting(enabled)
    }
}

private struct ShotPreview: View {
    var image: UIImage
    var busy: Bool
    var retake: () -> Void
    var submit: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button(action: retake) {
                    Text("Retake")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(palette.fill, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                if busy {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                } else {
                    SlideConfirm(title: "Slide to submit", enabled: true, onConfirm: submit)
                }
            }
            .padding(22)
            .background(palette.canvas)
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
    }
}

private struct ProofView: View {
    var url: URL
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Text("Could not load the photo.")
                        .foregroundStyle(palette.secondary)
                default:
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(22)
            .background(palette.canvas)
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarColorScheme(palette == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
    }
}

private struct CameraPick: UIViewControllerRepresentable {
    var onShot: (UIImage) -> Void
    var cancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onShot: onShot, cancel: cancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onShot: (UIImage) -> Void
        var cancel: () -> Void

        init(onShot: @escaping (UIImage) -> Void, cancel: @escaping () -> Void) {
            self.onShot = onShot
            self.cancel = cancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onShot(image)
            } else {
                cancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            cancel()
        }
    }
}

private func jpeg(_ image: UIImage) -> Data? {
    let longest = max(image.size.width, image.size.height)
    guard longest > 0 else { return nil }
    let scale = min(1, 1280 / longest)
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: size)
    let scaled = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
    return scaled.jpegData(compressionQuality: 0.6)
}
