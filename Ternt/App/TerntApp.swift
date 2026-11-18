import GooglePlacesSwift
import GoogleSignIn
import SwiftUI

@main
struct TerntApp: App {
    init() {
        InterFont.register()
        let key = Bundle.main.object(forInfoDictionaryKey: "PlacesAPIKey") as? String ?? ""
        if !key.isEmpty {
            _ = PlacesClient.provideAPIKey(key)
        }
    }
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.theme.preferred)
                .onAppear { app.applyInterfaceStyle() }
                .onChange(of: app.theme) { _, _ in app.applyInterfaceStyle() }
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}
