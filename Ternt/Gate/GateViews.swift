import Dependencies
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppModel {
    var screen: Screen = .gate
    var portal = PortalState.sample

    func boot() {
        @Dependency(\.householdStore) var store
        if let saved = try? store.load() {
            portal = saved
        }
    }

    func showLogin(_ role: Role) { screen = .login(role) }
    func showSetup(_ role: Role) { screen = .setup(role) }
    func showPortal(_ state: PortalState, role: Role) {
        portal = state
        screen = role == .owner ? .owner : .worker
    }

    func selectHome(_ id: String) {
        portal.activeHomeID = id
    }
}

enum Screen: Equatable {
    case gate
    case login(Role)
    case setup(Role)
    case owner
    case worker
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            switch app.screen {
            case .gate:
                RoleGateView()
            case .login(let role):
                LoginView(role: role)
                    .transition(.move(edge: .trailing))
            case .setup(let role):
                SetupScreen(role: role)
                    .transition(.move(edge: .trailing))
            case .owner:
                OwnerView()
                    .transition(.opacity)
            case .worker:
                WorkerView()
                    .transition(.opacity)
            }
        }
        .environment(\.palette, Palette.resolve(scheme))
        .animation(.smooth(duration: 0.42), value: app.screen)
        .task { app.boot() }
    }
}

struct RoleGateView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var phase: CGFloat = 0
    @State private var role: Role?

    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            ZStack(alignment: .top) {
                palette.canvas.ignoresSafeArea()
                wordmark
                    .frame(maxWidth: .infinity, maxHeight: phase < 0.85 ? .infinity : nil)
                    .padding(.top, phase < 0.85 ? 0 : top + 22)
                if phase > 0.8 {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            roleButton(.owner, "Owner")
                            roleButton(.worker, "Worker")
                        }
                        if role != nil {
                            Button("Proceed") {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                if let role { app.showLogin(role) }
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, proxy.safeAreaInsets.bottom + 16)
                    .transition(.opacity)
                }
            }
        }
        .task {
            withAnimation(.easeInOut(duration: 1.05)) { phase = 0.55 }
            try? await Task.sleep(for: .milliseconds(1100))
            withAnimation(.smooth(duration: 0.7)) { phase = 1 }
        }
    }

    private var wordmark: some View {
        let size: CGFloat = phase < 0.7 ? 64 : 22
        let tracking: CGFloat = phase < 0.7 ? 8 : 2.4
        return Text("TERNT")
            .font(.system(size: size, weight: .semibold))
            .tracking(tracking)
            .foregroundStyle(palette.ink.opacity(0.18))
            .overlay {
                Text("TERNT")
                    .font(.system(size: size, weight: .semibold))
                    .tracking(tracking)
                    .foregroundStyle(palette.ink)
                    .mask(alignment: .leading) {
                        GeometryReader { proxy in
                            Rectangle().frame(width: proxy.size.width * min(phase / 0.5, 1))
                        }
                    }
            }
            .animation(.smooth(duration: 0.7), value: phase > 0.7)
    }

    private func roleButton(_ value: Role, _ title: String) -> some View {
        let selected = role == value
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.smooth(duration: 0.2)) { role = value }
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(selected ? palette.onInverse : palette.ink)
                .background(selected ? palette.inverse : palette.surface, in: Capsule())
                .overlay { Capsule().stroke(palette.line, lineWidth: selected ? 0 : 1) }
        }
        .buttonStyle(.plain)
    }
}

struct LoginView: View {
    let role: Role
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var code = DialCodes.india
    @State private var number = ""
    @State private var pickingCode = false

    private var ready: Bool { number.count == code.length }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Mobile number")
                .font(.system(size: 28, weight: .medium))
            HStack(spacing: 10) {
                Button { pickingCode = true } label: {
                    HStack(spacing: 4) {
                        Text(code.dial).font(.body.weight(.semibold))
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 54)
                    .background(palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                TextField("00000 00000", text: $number)
                    .keyboardType(.phonePad)
                    .onChange(of: number) { _, value in
                        number = String(value.filter(\.isNumber).prefix(code.length))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Spacer()
            HStack(spacing: 10) {
                Button { app.screen = .gate } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 52, height: 52)
                        .background(palette.fill, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Button("Continue") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    app.showSetup(role)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!ready)
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
    }
}

struct SetupScreen: View {
    let role: Role
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var model: SetupModel

    init(role: Role) {
        self.role = role
        _model = State(initialValue: SetupModel(role: role))
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
                .frame(height: 56)
                .allowsHitTesting(false)
                composer
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .background(palette.canvas)
            }
        }
        .background(palette.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            LinearGradient(
                colors: [palette.canvas, palette.canvas.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .community:
                CommunitySheet(model: model)
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
            }
        }
        .onAppear {
            model.onFinish = { state in app.showPortal(state, role: role) }
            model.start()
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if model.welcomeDone, model.reply == nil {
                HStack(spacing: 8) {
                    reply("Yes")
                    reply("No")
                }
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 8) {
                Image(systemName: "mic")
                    .frame(width: 40, height: 40)
                    .background(.fill.tertiary, in: Circle())
                Text("Message")
                    .foregroundStyle(palette.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up")
                    .frame(width: 40, height: 40)
                    .background(.fill.tertiary, in: Circle())
                    .foregroundStyle(palette.tertiary)
            }
            .padding(8)
            .glassEffect(.regular, in: .capsule)
            .opacity(0.92)
        }
    }

    private func reply(_ title: String) -> some View {
        Button(title) { model.choose(title) }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
    }
}
