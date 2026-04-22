import Foundation
import SwiftUI
import UIKit

struct QuickKey: Identifiable {
    let id = UUID()
    let title: String
    let usageID: UInt16
}

struct ModifierKey: Identifiable {
    let id = UUID()
    let title: String
    let usageID: UInt16
}

struct MediaKey: Identifiable {
    let id = UUID()
    let title: String
    let usageID: UInt16
}

enum ControlPreset: String, CaseIterable, Identifiable {
    case precision
    case balanced
    case fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .precision:
            return "Precision"
        case .balanced:
            return "Balanced"
        case .fast:
            return "Fast"
        }
    }

    var pointerSensitivity: Double {
        switch self {
        case .precision:
            return 0.9
        case .balanced:
            return 1.4
        case .fast:
            return 2.1
        }
    }

    var scrollThreshold: Double {
        switch self {
        case .precision:
            return 24.0
        case .balanced:
            return 18.0
        case .fast:
            return 12.0
        }
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum KeyboardInputMode: String, CaseIterable, Identifiable {
    case sendText
    case onScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sendText:
            return "Send Text"
        case .onScreen:
            return "On-screen"
        }
    }
}

enum PhoneWorkspaceSection: String, CaseIterable, Identifiable {
    case controls
    case settings
    case webcam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controls:
            return "Controls"
        case .settings:
            return "Settings"
        case .webcam:
            return "Webcam"
        }
    }
}

enum NetworkTransportMode: String, CaseIterable, Identifiable {
    case wifi
    case usb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .usb:
            return "USB"
        }
    }
}

struct TrackpadGestureSurface: UIViewRepresentable {
    var sensitivity: Double
    var scrollThreshold: Double
    var onPointerMove: (Int16, Int16) -> Void
    var onScroll: (Int16, Int16) -> Void
    var onLeftClick: () -> Void
    var onRightClick: () -> Void
    var onMiddleClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pointerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePointerPan(_:)))
        pointerPan.minimumNumberOfTouches = 1
        pointerPan.maximumNumberOfTouches = 1
        pointerPan.delegate = context.coordinator

        let scrollPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleScrollPan(_:)))
        scrollPan.minimumNumberOfTouches = 2
        scrollPan.maximumNumberOfTouches = 2
        scrollPan.delegate = context.coordinator

        let leftTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLeftTap(_:)))
        leftTap.numberOfTouchesRequired = 1
        leftTap.numberOfTapsRequired = 1

        let rightTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRightTap(_:)))
        rightTap.numberOfTouchesRequired = 2
        rightTap.numberOfTapsRequired = 1

        let middleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMiddleTap(_:)))
        middleTap.numberOfTouchesRequired = 3
        middleTap.numberOfTapsRequired = 1

        view.addGestureRecognizer(pointerPan)
        view.addGestureRecognizer(scrollPan)
        view.addGestureRecognizer(leftTap)
        view.addGestureRecognizer(rightTap)
        view.addGestureRecognizer(middleTap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TrackpadGestureSurface
        private var scrollResidualX = 0.0
        private var scrollResidualY = 0.0

        init(parent: TrackpadGestureSurface) {
            self.parent = parent
        }

        @objc func handlePointerPan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else {
                return
            }

            let translation = recognizer.translation(in: view)
            recognizer.setTranslation(.zero, in: view)

            guard recognizer.state == .changed else {
                return
            }

            let scaledDx = Double(translation.x) * parent.sensitivity
            let scaledDy = Double(translation.y) * parent.sensitivity
            let dx = Int16(clamping: Int(scaledDx.rounded()))
            let dy = Int16(clamping: Int(scaledDy.rounded()))
            if dx != 0 || dy != 0 {
                parent.onPointerMove(dx, dy)
            }
        }

        @objc func handleScrollPan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else {
                return
            }

            let translation = recognizer.translation(in: view)
            recognizer.setTranslation(.zero, in: view)

            scrollResidualX += Double(translation.x)
            scrollResidualY += Double(translation.y)

            let threshold = max(parent.scrollThreshold, 8.0)
            var stepX: Int16 = 0
            var stepY: Int16 = 0

            while abs(scrollResidualX) >= threshold {
                if scrollResidualX > 0 {
                    stepX += 1
                    scrollResidualX -= threshold
                } else {
                    stepX -= 1
                    scrollResidualX += threshold
                }
            }

            while abs(scrollResidualY) >= threshold {
                if scrollResidualY > 0 {
                    stepY -= 1
                    scrollResidualY -= threshold
                } else {
                    stepY += 1
                    scrollResidualY += threshold
                }
            }

            if stepX != 0 || stepY != 0 {
                parent.onScroll(stepX, stepY)
            }

            if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
                scrollResidualX = 0
                scrollResidualY = 0
            }
        }

        @objc func handleLeftTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else {
                return
            }

            parent.onLeftClick()
        }

        @objc func handleRightTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else {
                return
            }

            parent.onRightClick()
        }

        @objc func handleMiddleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else {
                return
            }

            parent.onMiddleClick()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var bluetooth = BluetoothInputManager()
    @StateObject private var webcam = WebcamStreamingManager()
    @AppStorage("remotePad.savedAppearanceMode") private var savedAppearanceModeRawValue = AppAppearanceMode.system.rawValue
    @AppStorage("remotePad.savedPreset") private var savedPresetRawValue = ControlPreset.balanced.rawValue
    @AppStorage("remotePad.savedPointerSensitivity") private var savedPointerSensitivity = ControlPreset.balanced.pointerSensitivity
    @AppStorage("remotePad.savedScrollThreshold") private var savedScrollThreshold = ControlPreset.balanced.scrollThreshold
    @AppStorage("remotePad.savedWebSocketURL") private var legacySavedWebSocketURL = "ws://192.168.1.100:8765"
    @AppStorage("remotePad.savedWebSocketToken") private var savedWebSocketToken = "remotepad-token"
    @AppStorage("remotePad.savedKeyboardInputMode") private var savedKeyboardInputModeRawValue = KeyboardInputMode.sendText.rawValue
    @AppStorage("remotePad.savedDeviceName") private var savedDeviceName = "iPhoneRemotePad"
    @AppStorage("remotePad.savedPhoneWorkspaceSection") private var savedPhoneWorkspaceSectionRawValue = PhoneWorkspaceSection.controls.rawValue
    @AppStorage("remotePad.requireSecureWebSocket") private var requireSecureWebSocket = false
    @AppStorage("remotePad.savedWebcamURL") private var legacySavedWebcamURL = "ws://192.168.1.100:8767"
    @AppStorage("remotePad.savedWebcamToken") private var savedWebcamToken = "remotepad-token"
    @AppStorage("remotePad.savedWebcamMicEnabled") private var savedWebcamMicEnabled = false
    @AppStorage("remotePad.savedWebcamResolution") private var savedWebcamResolutionRawValue = WebcamResolutionPreset.p1080.rawValue
    @AppStorage("remotePad.savedWebcamFPS") private var savedWebcamFPSRawValue = WebcamFPSPreset.fps30.rawValue
    @AppStorage("remotePad.savedTransportMode") private var savedTransportModeRawValue = NetworkTransportMode.wifi.rawValue
    @AppStorage("remotePad.savedWiFiWebSocketURL") private var savedWiFiWebSocketURL = "ws://192.168.1.100:8765"
    @AppStorage("remotePad.savedUSBWebSocketURL") private var savedUSBWebSocketURL = "ws://172.20.10.2:8765"
    @AppStorage("remotePad.savedWiFiWebcamURL") private var savedWiFiWebcamURL = "ws://192.168.1.100:8767"
    @AppStorage("remotePad.savedUSBWebcamURL") private var savedUSBWebcamURL = "ws://172.20.10.2:8767"
    @AppStorage("remotePad.keepScreenAwake") private var keepScreenAwake = true

    @State private var textToSend = ""
    @State private var keyboardInputMode: KeyboardInputMode = .sendText
    @State private var selectedAppearanceMode: AppAppearanceMode = .system
    @State private var selectedPreset: ControlPreset = .balanced
    @State private var pointerSensitivity = ControlPreset.balanced.pointerSensitivity
    @State private var scrollThreshold = ControlPreset.balanced.scrollThreshold
    @State private var transportMode: NetworkTransportMode = .wifi
    @State private var webSocketWiFiURL = "ws://192.168.1.100:8765"
    @State private var webSocketUSBURL = "ws://172.20.10.2:8765"
    @State private var webSocketToken = "remotepad-token"
    @State private var deviceName = "iPhoneRemotePad"
    @State private var phoneWorkspaceSection: PhoneWorkspaceSection = .controls
    @State private var webcamWiFiURL = "ws://192.168.1.100:8767"
    @State private var webcamUSBURL = "ws://172.20.10.2:8767"
    @State private var webcamToken = "remotepad-token"
    @State private var webcamMicEnabled = false
    @State private var webcamResolution: WebcamResolutionPreset = .p1080
    @State private var webcamFPS: WebcamFPSPreset = .fps30
    @State private var activeModifierUsageIDs: Set<UInt16> = []
    @State private var loadedPersistedSettings = false

    private let quickKeys: [QuickKey] = [
        QuickKey(title: "Enter", usageID: 0x28),
        QuickKey(title: "Esc", usageID: 0x29),
        QuickKey(title: "Backspace", usageID: 0x2A),
        QuickKey(title: "Tab", usageID: 0x2B),
        QuickKey(title: "Space", usageID: 0x2C),
        QuickKey(title: "Ins", usageID: 0x49),
        QuickKey(title: "Del", usageID: 0x4C),
        QuickKey(title: "Home", usageID: 0x4A),
        QuickKey(title: "End", usageID: 0x4D),
        QuickKey(title: "PgUp", usageID: 0x4B),
        QuickKey(title: "PgDn", usageID: 0x4E),
        QuickKey(title: "Left", usageID: 0x50),
        QuickKey(title: "Down", usageID: 0x51),
        QuickKey(title: "Up", usageID: 0x52),
        QuickKey(title: "Right", usageID: 0x4F)
    ]

    private let functionKeys: [QuickKey] = (1...12).map { index in
        QuickKey(title: "F\(index)", usageID: UInt16(0x39 + index))
    }

    private let modifierKeys: [ModifierKey] = [
        ModifierKey(title: "Ctrl", usageID: 0xE0),
        ModifierKey(title: "Shift", usageID: 0xE1),
        ModifierKey(title: "Alt", usageID: 0xE2),
        ModifierKey(title: "Win", usageID: 0xE3)
    ]

    private let mediaKeys: [MediaKey] = [
        MediaKey(title: "Vol-", usageID: 0x00EA),
        MediaKey(title: "Mute", usageID: 0x00E2),
        MediaKey(title: "Vol+", usageID: 0x00E9),
        MediaKey(title: "Prev", usageID: 0x00B6),
        MediaKey(title: "Play", usageID: 0x00CD),
        MediaKey(title: "Next", usageID: 0x00B5)
    ]

    private let onScreenLetterRows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"]
    ]

    private struct LayoutMetrics {
        let isPadLayout: Bool
        let isPhoneLayout: Bool
        let isLandscape: Bool
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let stackSpacing: CGFloat
        let trackpadHeight: CGFloat
        let splitTopCards: Bool
        let controlButtonMinWidth: CGFloat
        let navigationMinWidth: CGFloat
        let functionMinWidth: CGFloat
        let mediaMinWidth: CGFloat
        let modifierMinWidth: CGFloat
        let onScreenKeyFontSize: CGFloat
        let onScreenKeySpacing: CGFloat
        let onScreenKeyWidth: CGFloat
        let onScreenKeyHeight: CGFloat
        let onScreenActionKeyWidth: CGFloat
        let onScreenSpaceKeyWidth: CGFloat
        let cardPadding: CGFloat
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = layoutMetrics(for: proxy.size)

            ScrollView {
                VStack(spacing: layout.stackSpacing) {
                    phoneWorkspacePicker

                    switch phoneWorkspaceSection {
                    case .controls:
                        controlsWorkspace(layout: layout)
                    case .settings:
                        topSection(layout: layout)
                    case .webcam:
                        webcamCard(layout: layout)
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, layout.verticalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .preferredColorScheme(selectedAppearanceMode.colorScheme)
            .onAppear {
                guard !loadedPersistedSettings else {
                    return
                }

                if let savedAppearanceMode = AppAppearanceMode(rawValue: savedAppearanceModeRawValue) {
                    selectedAppearanceMode = savedAppearanceMode
                }

                if let savedPreset = ControlPreset(rawValue: savedPresetRawValue) {
                    selectedPreset = savedPreset
                }

                pointerSensitivity = savedPointerSensitivity
                scrollThreshold = savedScrollThreshold
                webSocketToken = savedWebSocketToken
                deviceName = savedDeviceName
                bluetooth.setAdvertisingName(savedDeviceName)
                deviceName = bluetooth.advertisingName
                savedDeviceName = bluetooth.advertisingName

                webSocketWiFiURL = savedWiFiWebSocketURL
                webSocketUSBURL = savedUSBWebSocketURL
                webcamWiFiURL = savedWiFiWebcamURL
                webcamUSBURL = savedUSBWebcamURL

                if webSocketWiFiURL == "ws://192.168.1.100:8765", !legacySavedWebSocketURL.isEmpty {
                    webSocketWiFiURL = legacySavedWebSocketURL
                    savedWiFiWebSocketURL = legacySavedWebSocketURL
                }

                if webcamWiFiURL == "ws://192.168.1.100:8767", !legacySavedWebcamURL.isEmpty {
                    webcamWiFiURL = legacySavedWebcamURL
                    savedWiFiWebcamURL = legacySavedWebcamURL
                }

                if let savedTransportMode = NetworkTransportMode(rawValue: savedTransportModeRawValue) {
                    transportMode = savedTransportMode
                }

                if let savedKeyboardInputMode = KeyboardInputMode(rawValue: savedKeyboardInputModeRawValue) {
                    keyboardInputMode = savedKeyboardInputMode
                }

                if let savedPhoneWorkspaceSection = PhoneWorkspaceSection(rawValue: savedPhoneWorkspaceSectionRawValue) {
                    phoneWorkspaceSection = savedPhoneWorkspaceSection
                }

                webcamToken = savedWebcamToken
                webcamMicEnabled = savedWebcamMicEnabled

                if let savedWebcamResolution = WebcamResolutionPreset(rawValue: savedWebcamResolutionRawValue) {
                    webcamResolution = savedWebcamResolution
                }

                if let savedWebcamFPS = WebcamFPSPreset(rawValue: savedWebcamFPSRawValue) {
                    webcamFPS = savedWebcamFPS
                }

                updateIdleTimerSetting()

                loadedPersistedSettings = true
            }
            .onChange(of: selectedPreset) { newPreset in
                pointerSensitivity = newPreset.pointerSensitivity
                scrollThreshold = newPreset.scrollThreshold
                savedPresetRawValue = newPreset.rawValue
                savedPointerSensitivity = newPreset.pointerSensitivity
                savedScrollThreshold = newPreset.scrollThreshold
            }
            .onChange(of: selectedAppearanceMode) { newValue in
                savedAppearanceModeRawValue = newValue.rawValue
            }
            .onChange(of: pointerSensitivity) { newValue in
                savedPointerSensitivity = newValue
            }
            .onChange(of: scrollThreshold) { newValue in
                savedScrollThreshold = newValue
            }
            .onChange(of: transportMode) { newValue in
                savedTransportModeRawValue = newValue.rawValue
            }
            .onChange(of: webSocketWiFiURL) { newValue in
                savedWiFiWebSocketURL = newValue
            }
            .onChange(of: webSocketUSBURL) { newValue in
                savedUSBWebSocketURL = newValue
            }
            .onChange(of: webSocketToken) { newValue in
                savedWebSocketToken = newValue
            }
            .onChange(of: keyboardInputMode) { newValue in
                savedKeyboardInputModeRawValue = newValue.rawValue
            }
            .onChange(of: phoneWorkspaceSection) { newValue in
                savedPhoneWorkspaceSectionRawValue = newValue.rawValue
            }
            .onChange(of: webcamWiFiURL) { newValue in
                savedWiFiWebcamURL = newValue
            }
            .onChange(of: webcamUSBURL) { newValue in
                savedUSBWebcamURL = newValue
            }
            .onChange(of: webcamToken) { newValue in
                savedWebcamToken = newValue
            }
            .onChange(of: webcamMicEnabled) { newValue in
                savedWebcamMicEnabled = newValue
            }
            .onChange(of: webcamResolution) { newValue in
                savedWebcamResolutionRawValue = newValue.rawValue
            }
            .onChange(of: webcamFPS) { newValue in
                savedWebcamFPSRawValue = newValue.rawValue
            }
            .onChange(of: keepScreenAwake) { _ in
                updateIdleTimerSetting()
            }
            .onChange(of: deviceName) { newValue in
                bluetooth.setAdvertisingName(newValue)
                if deviceName != bluetooth.advertisingName {
                    deviceName = bluetooth.advertisingName
                }
                savedDeviceName = bluetooth.advertisingName
            }
            .onDisappear {
                releaseAllModifiers()
                webcam.stopStreaming()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    private var activeControlURL: String {
        transportMode == .wifi ? webSocketWiFiURL : webSocketUSBURL
    }

    private var activeWebcamURL: String {
        transportMode == .wifi ? webcamWiFiURL : webcamUSBURL
    }

    private var activeControlURLBinding: Binding<String> {
        Binding(
            get: { activeControlURL },
            set: { newValue in
                setActiveControlURL(newValue)
            }
        )
    }

    private var activeWebcamURLBinding: Binding<String> {
        Binding(
            get: { activeWebcamURL },
            set: { newValue in
                setActiveWebcamURL(newValue)
            }
        )
    }

    private func setActiveControlURL(_ value: String) {
        if transportMode == .wifi {
            webSocketWiFiURL = value
        } else {
            webSocketUSBURL = value
        }
    }

    private func setActiveWebcamURL(_ value: String) {
        if transportMode == .wifi {
            webcamWiFiURL = value
        } else {
            webcamUSBURL = value
        }
    }

    private func updateIdleTimerSetting() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
    }

    private func layoutMetrics(for size: CGSize) -> LayoutMetrics {
        let isLandscape = size.width > size.height
        let isPadLayout = UIDevice.current.userInterfaceIdiom == .pad

        if isPadLayout {
            let trackpadHeight = min(max(size.height * (isLandscape ? 0.44 : 0.34), 280), 420)
            return LayoutMetrics(
                isPadLayout: true,
                isPhoneLayout: false,
                isLandscape: isLandscape,
                horizontalPadding: 24,
                verticalPadding: 20,
                stackSpacing: 18,
                trackpadHeight: trackpadHeight,
                splitTopCards: true,
                controlButtonMinWidth: 150,
                navigationMinWidth: 96,
                functionMinWidth: 68,
                mediaMinWidth: 84,
                modifierMinWidth: 96,
                onScreenKeyFontSize: 19,
                onScreenKeySpacing: 8,
                onScreenKeyWidth: 62,
                onScreenKeyHeight: 48,
                onScreenActionKeyWidth: 176,
                onScreenSpaceKeyWidth: 308,
                cardPadding: 14
            )
        }

        let trackpadHeight = min(max(size.height * (isLandscape ? 0.20 : 0.19), isLandscape ? 120 : 138), isLandscape ? 165 : 190)
        return LayoutMetrics(
            isPadLayout: false,
            isPhoneLayout: true,
            isLandscape: isLandscape,
            horizontalPadding: 6,
            verticalPadding: 8,
            stackSpacing: 8,
            trackpadHeight: trackpadHeight,
            splitTopCards: false,
            controlButtonMinWidth: isLandscape ? 98 : 110,
            navigationMinWidth: isLandscape ? 70 : 62,
            functionMinWidth: isLandscape ? 52 : 50,
            mediaMinWidth: isLandscape ? 64 : 58,
            modifierMinWidth: isLandscape ? 76 : 66,
            onScreenKeyFontSize: isLandscape ? 11 : 12,
            onScreenKeySpacing: 3,
            onScreenKeyWidth: 34,
            onScreenKeyHeight: isLandscape ? 34 : 36,
            onScreenActionKeyWidth: isLandscape ? 104 : 100,
            onScreenSpaceKeyWidth: isLandscape ? 184 : 162,
            cardPadding: 8
        )
    }

    private func topSection(layout: LayoutMetrics) -> some View {
        Group {
            if layout.splitTopCards {
                HStack(alignment: .top, spacing: layout.stackSpacing) {
                    statusCard(layout: layout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    wifiCard(layout: layout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: layout.stackSpacing) {
                    statusCard(layout: layout)
                    wifiCard(layout: layout)
                }
            }
        }
    }

    @ViewBuilder
    private func controlsWorkspace(layout: LayoutMetrics) -> some View {
        if layout.isPhoneLayout {
            compactBLECard(layout: layout)
            trackpadCard(height: layout.trackpadHeight, layout: layout)
            mouseButtonRow(layout: layout)
            scrollButtonRow(layout: layout)
            keyboardCard(layout: layout)
        } else {
            topSection(layout: layout)
            trackpadCard(height: layout.trackpadHeight, layout: layout)
            mouseButtonRow(layout: layout)
            scrollButtonRow(layout: layout)
            keyboardCard(layout: layout)
        }
    }

    private var phoneWorkspacePicker: some View {
        Picker("Workspace", selection: $phoneWorkspaceSection) {
            ForEach(PhoneWorkspaceSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
    }

    private func compactBLECard(layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bluetooth.isAdvertising ? "BLE Ready" : "BLE Paused")
                        .font(.subheadline)
                        .bold()
                    Text(bluetooth.stateSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button(bluetooth.isAdvertising || bluetooth.subscribedCentralCount > 0 ? "Disconnect" : "Enable") {
                    bluetooth.toggleBluetoothConnection()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .lineLimit(1)
            }

            if bluetooth.subscribedCentralCount > 0 {
                Text("Connected BLE clients: \(bluetooth.subscribedCentralCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(layout.cardPadding)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statusCard(layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bluetooth Remote เพราะกู ขก. ลุก")
                .font(layout.isPadLayout ? .title2 : .headline)
                .bold()
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Text(bluetooth.stateSummary)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Connected BLE clients: \(bluetooth.subscribedCentralCount)")
                .font(.footnote)
                .foregroundColor(.secondary)

            TextField("BLE Device Name", text: $deviceName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            Text("Shown in Advertising as ...")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Button(bluetooth.isAdvertising || bluetooth.subscribedCentralCount > 0 ? "Disconnect BLE" : "Enable BLE") {
                    bluetooth.toggleBluetoothConnection()
                }
                .buttonStyle(.bordered)
                .tint(bluetooth.isAdvertising || bluetooth.subscribedCentralCount > 0 ? .red : .blue)

                Text(bluetooth.isAdvertising ? "Advertising" : "Paused")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if layout.isPhoneLayout {
                Picker("Appearance", selection: $selectedAppearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Picker("Control Profile", selection: $selectedPreset) {
                    ForEach(ControlPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Appearance", selection: $selectedAppearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Control Profile", selection: $selectedPreset) {
                    ForEach(ControlPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Text("Sensitivity")
                Slider(value: $pointerSensitivity, in: 0.5...3.0)
                Text(String(format: "%.1fx", pointerSensitivity))
                    .font(.caption)
                    .frame(width: layout.isPadLayout ? 44 : 38, alignment: .trailing)
            }
            HStack {
                Text("Scroll Step")
                Slider(value: $scrollThreshold, in: 8.0...30.0)
                Text(String(format: "%.0f", scrollThreshold))
                    .font(.caption)
                    .frame(width: layout.isPadLayout ? 44 : 38, alignment: .trailing)
            }

            Toggle("Keep screen awake", isOn: $keepScreenAwake)
                .toggleStyle(.switch)
        }
        .padding(layout.cardPadding)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func wifiCard(layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wifi connector")
                .font(.headline)

            if layout.isPhoneLayout {
                Picker("Transport", selection: $transportMode) {
                    ForEach(NetworkTransportMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Transport", selection: $transportMode) {
                    ForEach(NetworkTransportMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text(bluetooth.wifiStatus)
                .font(.footnote)
                .foregroundColor(.secondary)

            Text(transportMode == .usb
                    ? "USB mode uses iPhone Personal Hotspot network. Windows is commonly at 172.20.10.2."
                    : "Wi-Fi mode uses your local LAN IP on Windows.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("ws://<windows-ip>:8765", text: activeControlURLBinding)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            TextField("Token", text: $webSocketToken)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            Toggle("Require secure WebSocket (wss://)", isOn: $requireSecureWebSocket)
                .toggleStyle(.switch)

            if !bluetooth.discoveredWebSocketURL.isEmpty {
                Text("Discovered: \(bluetooth.discoveredWebSocketURL)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.isPhoneLayout ? 104 : 120), spacing: 10)], spacing: 10) {
                Button("Auto Discover") {
                    bluetooth.discoverWebSocketServer { discoveredURL in
                        guard let discoveredURL else {
                            return
                        }
                        setActiveControlURL(discoveredURL)
                    }
                }
                .buttonStyle(.bordered)

                Button("Connect") {
                    bluetooth.connectWebSocket(
                        urlString: activeControlURL.trimmingCharacters(in: .whitespacesAndNewlines),
                        token: webSocketToken,
                        requireSecure: requireSecureWebSocket
                    )
                }
                .buttonStyle(.borderedProminent)

                Button("Disconnect") {
                    bluetooth.disconnectWebSocket()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(layout.cardPadding)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func webcamCard(layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Webcam")
                .font(.headline)

            if layout.isPhoneLayout {
                Picker("Transport", selection: $transportMode) {
                    ForEach(NetworkTransportMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Transport", selection: $transportMode) {
                    ForEach(NetworkTransportMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text(webcam.status)
                .font(.footnote)
                .foregroundColor(.secondary)

            Text(transportMode == .usb
                    ? "USB mode streams over Personal Hotspot network. Try ws://172.20.10.2:8767 first."
                    : "Wi-Fi mode streams over local LAN.")
                .font(.caption)
                .foregroundColor(.secondary)

            WebcamPreviewView(session: webcam.captureSession)
                .frame(height: layout.isPhoneLayout ? 220 : 320)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            TextField("ws://<windows-ip>:8767", text: activeWebcamURLBinding)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            TextField("Token", text: $webcamToken)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            if layout.isPhoneLayout {
                Picker("Resolution", selection: $webcamResolution) {
                    ForEach(WebcamResolutionPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)

                Picker("Frame Rate", selection: $webcamFPS) {
                    ForEach(WebcamFPSPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Resolution", selection: $webcamResolution) {
                    ForEach(WebcamResolutionPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Frame Rate", selection: $webcamFPS) {
                    ForEach(WebcamFPSPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
            }

            Toggle("Enable microphone audio", isOn: $webcamMicEnabled)
                .toggleStyle(.switch)

            Text("Default is OFF. Use LAN or USB tethering network for lowest latency.")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(String(format: "Send FPS: %.1f", webcam.transmittedFPS))
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.isPhoneLayout ? 104 : 120), spacing: 10)], spacing: 10) {
                Button("Use Discovered Host") {
                    bluetooth.discoverWebSocketServer { discoveredURL in
                        guard let discoveredURL,
                              var components = URLComponents(string: discoveredURL),
                              components.host != nil else {
                            return
                        }

                        components.port = 8767
                        if let wsURL = components.string {
                            setActiveWebcamURL(wsURL)
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button("Start Webcam") {
                    webcam.startStreaming(
                        urlString: activeWebcamURL,
                        token: webcamToken,
                        resolution: webcamResolution,
                        fps: webcamFPS,
                        micEnabled: webcamMicEnabled
                    )
                }
                .buttonStyle(.borderedProminent)

                Button("Stop Webcam") {
                    webcam.stopStreaming()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(layout.cardPadding)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func trackpadCard(height: CGFloat, layout: LayoutMetrics) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.blue.opacity(0.36), Color.cyan.opacity(0.28)]
                            : [Color.blue.opacity(0.22), Color.cyan.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: layout.isPhoneLayout ? 30 : 36))
                    .foregroundColor(colorScheme == .dark ? .cyan.opacity(0.9) : .blue.opacity(0.9))
                Text("แตะกู กูบอกให้มึงแตะกู")
                    .font(layout.isPhoneLayout ? .subheadline : .headline)
                    .lineLimit(layout.isPhoneLayout ? 1 : nil)
                    .minimumScaleFactor(0.84)

                if layout.isPhoneLayout {
                    Text("1 finger move, 2 finger scroll, tap to click")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                } else {
                    Text("คือกูขี้เกียจลุกมากๆ กูเลยทำแอพนี้มาใช้เอง จะได้ไม่ต้องลุกไปจับเม้าส์ พอกูจะหาแอปแบบนี้ใน App Store แม่งก็เสือกมีโฆษณาเต็มแอป หรือไม่ก็กูต้องจ่ายตังซื้อแอปหลอกแดกตังโง่ๆ ควย ไอ่เหี้ย")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }
            }
            .padding(12)

            TrackpadGestureSurface(
                sensitivity: pointerSensitivity,
                scrollThreshold: scrollThreshold,
                onPointerMove: { dx, dy in
                    bluetooth.sendMouseMove(dx: dx, dy: dy)
                },
                onScroll: { dx, dy in
                    bluetooth.sendScroll(dx: dx, dy: dy)
                },
                onLeftClick: {
                    bluetooth.sendMouseButton(button: .left, action: .click)
                },
                onRightClick: {
                    bluetooth.sendMouseButton(button: .right, action: .click)
                },
                onMiddleClick: {
                    bluetooth.sendMouseButton(button: .middle, action: .click)
                }
            )
            .contentShape(Rectangle())
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func mouseButtonRow(layout: LayoutMetrics) -> some View {
        let columns: [GridItem]
        if layout.isPhoneLayout {
            let phoneColumnCount = layout.isLandscape ? 3 : 2
            columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: phoneColumnCount)
        } else {
            columns = [GridItem(.adaptive(minimum: layout.controlButtonMinWidth), spacing: 8)]
        }

        let leftTitle = layout.isPhoneLayout ? "Left" : "Left Click"
        let middleTitle = "Middle"
        let rightTitle = layout.isPhoneLayout ? "Right" : "Right Click"

        return LazyVGrid(columns: columns, spacing: 8) {
            Button(leftTitle) {
                bluetooth.sendMouseButton(button: .left, action: .click)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(layout.isPhoneLayout ? .small : .regular)
            .lineLimit(1)
            .minimumScaleFactor(0.78)

            Button(middleTitle) {
                bluetooth.sendMouseButton(button: .middle, action: .click)
            }
            .buttonStyle(.bordered)
            .controlSize(layout.isPhoneLayout ? .small : .regular)
            .lineLimit(1)
            .minimumScaleFactor(0.78)

            Button(rightTitle) {
                bluetooth.sendMouseButton(button: .right, action: .click)
            }
            .buttonStyle(.bordered)
            .controlSize(layout.isPhoneLayout ? .small : .regular)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
    }

    private func keyboardCard(layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard")
                .font(.headline)

            if layout.isPhoneLayout {
                Picker("Keyboard Mode", selection: $keyboardInputMode) {
                    ForEach(KeyboardInputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Keyboard Mode", selection: $keyboardInputMode) {
                    ForEach(KeyboardInputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if keyboardInputMode == .sendText {
                VStack(spacing: 8) {
                    TextField("Type text to send", text: $textToSend)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Spacer()
                        Button("Send") {
                            let trimmed = textToSend.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else {
                                return
                            }

                            bluetooth.sendText(trimmed)
                            textToSend = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                onScreenKeyboardPanel(layout: layout)
            }

            modifierPanel(layout: layout)

            Text("Navigation")
                .font(.subheadline)
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.navigationMinWidth), spacing: 8)], spacing: 8) {
                ForEach(quickKeys) { key in
                    Button(key.title) {
                        bluetooth.sendKey(usageID: key.usageID, action: .tap)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("Function")
                .font(.subheadline)
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.functionMinWidth), spacing: 8)], spacing: 8) {
                ForEach(functionKeys) { key in
                    Button(key.title) {
                        bluetooth.sendKey(usageID: key.usageID, action: .tap)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("Media")
                .font(.subheadline)
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.mediaMinWidth), spacing: 8)], spacing: 8) {
                ForEach(mediaKeys) { key in
                    Button(key.title) {
                        bluetooth.sendConsumerKey(usageID: key.usageID, action: .tap)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(layout.cardPadding)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func onScreenKeyboardPanel(layout: LayoutMetrics) -> some View {
        let useFlexiblePhoneKeys = layout.isPhoneLayout
        let backspaceTitle = layout.isPhoneLayout ? "Back" : "Backspace"

        return VStack(spacing: layout.onScreenKeySpacing) {
            ForEach(Array(onScreenLetterRows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: layout.onScreenKeySpacing) {
                    ForEach(row, id: \.self) { letter in
                        onScreenKeyButton(
                            title: letter,
                            width: useFlexiblePhoneKeys ? nil : layout.onScreenKeyWidth,
                            height: layout.onScreenKeyHeight,
                            fontSize: layout.onScreenKeyFontSize,
                            expandToFill: useFlexiblePhoneKeys
                        ) {
                            sendLetterTap(letter)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(x: onScreenRowOffset(rowIndex: rowIndex, layout: layout))
            }

            HStack(spacing: layout.onScreenKeySpacing) {
                onScreenKeyButton(
                    title: "Space",
                    width: useFlexiblePhoneKeys ? nil : layout.onScreenSpaceKeyWidth,
                    height: layout.onScreenKeyHeight,
                    fontSize: layout.onScreenKeyFontSize,
                    expandToFill: useFlexiblePhoneKeys
                ) {
                    bluetooth.sendKey(usageID: 0x2C, action: .tap)
                }

                onScreenKeyButton(
                    title: backspaceTitle,
                    width: useFlexiblePhoneKeys ? nil : layout.onScreenActionKeyWidth,
                    height: layout.onScreenKeyHeight,
                    fontSize: layout.onScreenKeyFontSize,
                    expandToFill: useFlexiblePhoneKeys
                ) {
                    bluetooth.sendKey(usageID: 0x2A, action: .tap)
                }

                onScreenKeyButton(
                    title: "Enter",
                    width: useFlexiblePhoneKeys ? nil : layout.onScreenActionKeyWidth,
                    height: layout.onScreenKeyHeight,
                    fontSize: layout.onScreenKeyFontSize,
                    expandToFill: useFlexiblePhoneKeys
                ) {
                    bluetooth.sendKey(usageID: 0x28, action: .tap)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func onScreenRowOffset(rowIndex: Int, layout: LayoutMetrics) -> CGFloat {
        guard layout.isPadLayout else {
            return 0
        }

        switch rowIndex {
        case 1:
            return layout.onScreenKeyWidth * 0.45
        case 2:
            return layout.onScreenKeyWidth * 0.90
        default:
            return 0
        }
    }

    private func onScreenKeyButton(
        title: String,
        width: CGFloat?,
        height: CGFloat,
        fontSize: CGFloat,
        expandToFill: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title) {
            action()
        }
        .buttonStyle(.bordered)
        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: expandToFill ? .infinity : nil)
        .frame(width: width, height: height)
    }

    private func scrollButtonRow(layout: LayoutMetrics) -> some View {
        let columns: [GridItem] = layout.isPhoneLayout
            ? Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
            : [GridItem(.adaptive(minimum: layout.controlButtonMinWidth), spacing: 8)]

        let upTitle = layout.isPhoneLayout ? "Up" : "Scroll Up"
        let downTitle = layout.isPhoneLayout ? "Down" : "Scroll Down"
        let leftTitle = layout.isPhoneLayout ? "Left" : "Scroll Left"
        let rightTitle = layout.isPhoneLayout ? "Right" : "Scroll Right"

        return LazyVGrid(columns: columns, spacing: 8) {
            Button(upTitle) {
                bluetooth.sendScroll(dx: 0, dy: 1)
            }
            .buttonStyle(.bordered)
            .controlSize(layout.isPhoneLayout ? .small : .regular)
            .lineLimit(1)
            .minimumScaleFactor(0.82)

            Button(downTitle) {
                bluetooth.sendScroll(dx: 0, dy: -1)
            }
            .buttonStyle(.bordered)
            .controlSize(layout.isPhoneLayout ? .small : .regular)
            .lineLimit(1)
            .minimumScaleFactor(0.82)

            Button(leftTitle) {
                bluetooth.sendScroll(dx: -1, dy: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(layout.isPhoneLayout ? .small : .regular)
            .lineLimit(1)
            .minimumScaleFactor(0.82)

            Button(rightTitle) {
                bluetooth.sendScroll(dx: 1, dy: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(layout.isPhoneLayout ? .small : .regular)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
    }

    private func modifierPanel(layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let releaseTitle = layout.isPhoneLayout ? "Release" : "Release All"

            if layout.isPhoneLayout {
                Text("Modifiers")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Spacer()
                    Button(releaseTitle) {
                        releaseAllModifiers()
                    }
                    .buttonStyle(.bordered)
                    .lineLimit(1)
                }
            } else {
                HStack {
                    Text("Modifiers")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(releaseTitle) {
                        releaseAllModifiers()
                    }
                    .buttonStyle(.bordered)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.modifierMinWidth), spacing: 8)], spacing: 8) {
                ForEach(modifierKeys) { key in
                    let isActive = activeModifierUsageIDs.contains(key.usageID)
                    Button(key.title) {
                        toggleModifier(key)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isActive ? .blue : .gray.opacity(0.55))
                }
            }
        }
    }

    private func toggleModifier(_ key: ModifierKey) {
        if activeModifierUsageIDs.contains(key.usageID) {
            bluetooth.sendKey(usageID: key.usageID, action: .up)
            activeModifierUsageIDs.remove(key.usageID)
        } else {
            bluetooth.sendKey(usageID: key.usageID, action: .down)
            activeModifierUsageIDs.insert(key.usageID)
        }
    }

    private func releaseAllModifiers() {
        for usageID in activeModifierUsageIDs.sorted() {
            bluetooth.sendKey(usageID: usageID, action: .up)
        }
        activeModifierUsageIDs.removeAll()
    }

    private func sendLetterTap(_ letter: String) {
        let upper = letter.uppercased()
        guard let scalar = upper.unicodeScalars.first else {
            return
        }

        let value = scalar.value
        guard value >= 65, value <= 90 else {
            return
        }

        let usageID = UInt16(value - 65 + 0x04)
        bluetooth.sendKey(usageID: usageID, action: .tap)
    }
}
