import SwiftUI

@main
struct IQSpeedApp: App {
    var body: some Scene {
        WindowGroup {
            WebContainer()
                .ignoresSafeArea()
                .background(Color(red: 7/255, green: 11/255, blue: 22/255))
                .preferredColorScheme(.dark)
        }
    }
}
