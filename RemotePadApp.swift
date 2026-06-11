import SwiftUI

@main
struct BLERemotePadApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Label("Keyboard", systemImage: "keyboard")
                    }
                
                SensorTestView()
                    .tabItem {
                        Label("Sensors", systemImage: "sensor.tag.radiowaves.forward")
                    }
            }
        }
    }
}
