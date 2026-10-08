import SwiftUI

@main
public struct OllamaChatApp: App {
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 850, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }
    }
}
