import SwiftUI

@main
struct TTSEvalApp: App {
    private let appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .task {
                    await appModel.autorunIfRequested()
                }
        }
    }
}
