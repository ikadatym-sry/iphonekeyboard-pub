import SwiftUI
import CoreMotion
import Foundation

class SensorManager: ObservableObject {
    private let altimeter = CMAltimeter()
    private let motionManager = CMMotionManager()

    @Published var altitude: Double = 0.0
    @Published var pressure: Double = 0.0
    @Published var estimatedAltitude: Double = 0.0
    @Published var isSupported: Bool = false
    @Published var accelerometerData: CMAcceleration = CMAcceleration(x: 0, y: 0, z: 0)
    @Published var gyroData: CMRotationRate = CMRotationRate(x: 0, y: 0, z: 0)
    
    var referenceSeaLevelPressure: Double = 1013.25

    init() {
        checkSupport()
    }

    private func checkSupport() {
        isSupported = CMAltimeter.isRelativeAltitudeAvailable()
    }

    func startUpdates() {
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let data = data, error == nil, let self = self else { return }
                self.altitude = data.relativeAltitude.doubleValue
                
                let currentPressure = data.pressure.doubleValue * 10.0 // Convert kPa to hPa (mbar)
                self.pressure = currentPressure
                
                // Calculate estimated absolute altitude using the barometric formula
                self.estimatedAltitude = 44330.0 * (1.0 - pow(currentPressure / self.referenceSeaLevelPressure, 1.0 / 5.255))
            }
        }

        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 / 10.0 // 10Hz
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                guard let data = data, error == nil else { return }
                self?.accelerometerData = data.acceleration
            }
        }

        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 1.0 / 10.0 // 10Hz
            motionManager.startGyroUpdates(to: .main) { [weak self] data, error in
                guard let data = data, error == nil else { return }
                self?.gyroData = data.rotationRate
            }
        }
    }

    func stopUpdates() {
        altimeter.stopRelativeAltitudeUpdates()
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
    }
}

struct SensorTestView: View {
    @StateObject private var sensorManager = SensorManager()
    @AppStorage("seaLevelPressure") private var seaLevelPressure: Double = 1013.25

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Barometer / Altimeter")) {
                    if sensorManager.isSupported {
                        HStack {
                            Text("QNH (Sea Level Pressure)")
                            Spacer()
                            TextField("1013.25", value: $seaLevelPressure, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            Text("hPa")
                        }
                        
                        HStack {
                            Text("Raw Pressure")
                            Spacer()
                            Text(String(format: "%.2f hPa", sensorManager.pressure))
                        }
                        
                        HStack {
                            Text("Est. Absolute Altitude")
                            Spacer()
                            Text(String(format: "%.2f m", sensorManager.estimatedAltitude))
                                .bold()
                                .foregroundColor(.blue)
                        }

                        HStack {
                            Text("Relative Altitude (from start)")
                            Spacer()
                            Text(String(format: "%.2f m", sensorManager.altitude))
                        }
                    } else {
                        Text("Barometer not supported on this device.")
                            .foregroundColor(.red)
                    }
                }

                Section(header: Text("Accelerometer (G)")) {
                    HStack {
                        Text("X")
                        Spacer()
                        Text(String(format: "%.3f", sensorManager.accelerometerData.x))
                    }
                    HStack {
                        Text("Y")
                        Spacer()
                        Text(String(format: "%.3f", sensorManager.accelerometerData.y))
                    }
                    HStack {
                        Text("Z")
                        Spacer()
                        Text(String(format: "%.3f", sensorManager.accelerometerData.z))
                    }
                }

                Section(header: Text("Gyroscope (rad/s)")) {
                    HStack {
                        Text("X")
                        Spacer()
                        Text(String(format: "%.3f", sensorManager.gyroData.x))
                    }
                    HStack {
                        Text("Y")
                        Spacer()
                        Text(String(format: "%.3f", sensorManager.gyroData.y))
                    }
                    HStack {
                        Text("Z")
                        Spacer()
                        Text(String(format: "%.3f", sensorManager.gyroData.z))
                    }
                }
            }
            .navigationTitle("Sensor Data")
            .onAppear {
                sensorManager.referenceSeaLevelPressure = seaLevelPressure
                sensorManager.startUpdates()
            }
            .onDisappear {
                sensorManager.stopUpdates()
            }
            .onChange(of: seaLevelPressure) { newValue in
                sensorManager.referenceSeaLevelPressure = newValue
            }
        }
    }
}
