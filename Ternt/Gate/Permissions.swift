import AVFoundation
import Contacts
import CoreLocation
import SwiftUI

enum AppPermissions {
    enum State {
        case ask, allowed, off
        var label: String {
            switch self {
            case .ask: "Will ask"
            case .allowed: "Allowed"
            case .off: "Off"
            }
        }
    }

    static var contacts: State { state(CNContactStore.authorizationStatus(for: .contacts) == .notDetermined, CNContactStore.authorizationStatus(for: .contacts) == .authorized || CNContactStore.authorizationStatus(for: .contacts) == .limited) }

    static var location: State {
        switch CLLocationManager().authorizationStatus {
        case .notDetermined: .ask
        case .authorizedAlways, .authorizedWhenInUse: .allowed
        default: .off
        }
    }

    static var microphone: State {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: .ask
        case .granted: .allowed
        default: .off
        }
    }

    static var anyOff: Bool { contacts == .off || location == .off || microphone == .off }

    private static func state(_ asking: Bool, _ allowed: Bool) -> State {
        if asking { return .ask }
        return allowed ? .allowed : .off
    }

    @MainActor
    static func requestAll() async {
        await LocationAuth().request()
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        }
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
    }

    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct PermissionsView: View {
    let role: Role
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var asking = false
    @State private var revision = 0
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let _ = revision
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "shield")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(palette.secondary.opacity(0.45))
            Text("Before we start")
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.ink)
            VStack(alignment: .leading, spacing: 22) {
                item("location", "Location", "Find your society nearby", AppPermissions.location)
                item("person.crop.circle", "Contacts", "Pick your helpers' names and numbers", AppPermissions.contacts)
                item("mic", "Microphone", "Talk instead of typing", AppPermissions.microphone)
            }
            .frame(maxWidth: 300, alignment: .leading)
            Text(AppPermissions.anyOff
                 ? "Anything left off can be typed instead. You can allow it in Settings."
                 : "You can say no to any of these and type instead.")
                .font(.callout)
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            if AppPermissions.anyOff {
                Button {
                    AppPermissions.openSettings()
                } label: {
                    Text("Open Settings")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.fill, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
            }
            Button {
                guard !asking else { return }
                asking = true
                Task {
                    await AppPermissions.requestAll()
                    app.startSetup(role)
                }
            } label: {
                Text("Continue")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.onInverse)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.inverse, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(asking)
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvas.ignoresSafeArea())
        .onChange(of: phase) { _, phase in
            if phase == .active { revision += 1 }
        }
    }

    private func item(_ symbol: String, _ title: String, _ line: String, _ state: AppPermissions.State) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(palette.secondary.opacity(0.55))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(palette.ink)
                Text(line)
                    .font(.callout)
                    .foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 8)
            Text(state.label)
                .font(.callout)
                .foregroundStyle(state == .off ? palette.secondary : palette.ink)
        }
    }
}

private final class LocationAuth: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Void, Never>?

    @MainActor
    func request() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        continuation?.resume()
        continuation = nil
    }
}
