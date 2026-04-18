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
    @AppStorage("remotePad.savedAppearanceMode") private var savedAppearanceModeRawValue = AppAppearanceMode.system.rawValue
    @AppStorage("remotePad.savedPreset") private var savedPresetRawValue = ControlPreset.balanced.rawValue
    @AppStorage("remotePad.savedPointerSensitivity") private var savedPointerSensitivity = ControlPreset.balanced.pointerSensitivity
    @AppStorage("remotePad.savedScrollThreshold") private var savedScrollThreshold = ControlPreset.balanced.scrollThreshold
    @AppStorage("remotePad.savedWebSocketURL") private var savedWebSocketURL = "ws://192.168.1.100:8765"
    @AppStorage("remotePad.savedWebSocketToken") private var savedWebSocketToken = "remotepad-token"
    @AppStorage("remotePad.savedKeyboardInputMode") private var savedKeyboardInputModeRawValue = KeyboardInputMode.sendText.rawValue
    @AppStorage("remotePad.requireSecureWebSocket") private var requireSecureWebSocket = false

    @State private var textToSend = ""
    @State private var keyboardInputMode: KeyboardInputMode = .sendText
    @State private var selectedAppearanceMode: AppAppearanceMode = .system
    @State private var selectedPreset: ControlPreset = .balanced
    @State private var pointerSensitivity = ControlPreset.balanced.pointerSensitivity
    @State private var scrollThreshold = ControlPreset.balanced.scrollThreshold
    @State private var webSocketURL = "ws://192.168.1.100:8765"
    @State private var webSocketToken = "remotepad-token"
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
                    topSection(layout: layout)
                    trackpadCard(height: layout.trackpadHeight)
                    mouseButtonRow(minWidth: layout.controlButtonMinWidth)
                    scrollButtonRow(minWidth: layout.controlButtonMinWidth)
                    keyboardCard(layout: layout)
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
                webSocketURL = savedWebSocketURL
                webSocketToken = savedWebSocketToken

                if let savedKeyboardInputMode = KeyboardInputMode(rawValue: savedKeyboardInputModeRawValue) {
                    keyboardInputMode = savedKeyboardInputMode
                }

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
            .onChange(of: webSocketURL) { newValue in
                savedWebSocketURL = newValue
            }
            .onChange(of: webSocketToken) { newValue in
                savedWebSocketToken = newValue
            }
            .onChange(of: keyboardInputMode) { newValue in
                savedKeyboardInputModeRawValue = newValue.rawValue
            }
            .onDisappear {
                releaseAllModifiers()
            }
        }
    }

    private func layoutMetrics(for size: CGSize) -> LayoutMetrics {
        let shortestSide = min(size.width, size.height)
        let isPadDevice = UIDevice.current.userInterfaceIdiom == .pad
        let isPadLike = isPadDevice || shortestSide >= 700
        let isLandscape = size.width > size.height
        let isWidePhoneLandscape = !isPadLike && isLandscape && size.width >= 760

        if isPadLike {
            let trackpadHeight = min(max(size.height * (isLandscape ? 0.44 : 0.34), 280), 420)
            return LayoutMetrics(
                isPadLayout: true,
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
                onScreenKeyFontSize: 17,
                onScreenKeySpacing: 8,
                onScreenKeyWidth: 62,
                onScreenKeyHeight: 44,
                onScreenActionKeyWidth: 170,
                onScreenSpaceKeyWidth: 300,
                cardPadding: 14
            )
        }

        if size.width >= 390 {
            let trackpadHeight = min(max(size.height * (isLandscape ? 0.30 : 0.29), isLandscape ? 160 : 210), isLandscape ? 218 : 300)
            return LayoutMetrics(
                isPadLayout: false,
                horizontalPadding: isLandscape ? 8 : 10,
                verticalPadding: isLandscape ? 10 : 11,
                stackSpacing: isLandscape ? 10 : 11,
                trackpadHeight: trackpadHeight,
                splitTopCards: isWidePhoneLandscape,
                controlButtonMinWidth: isLandscape ? 108 : 92,
                navigationMinWidth: isLandscape ? 82 : 68,
                functionMinWidth: isLandscape ? 58 : 54,
                mediaMinWidth: isLandscape ? 70 : 64,
                modifierMinWidth: isLandscape ? 82 : 72,
                onScreenKeyFontSize: isLandscape ? 11 : 12,
                onScreenKeySpacing: 4,
                onScreenKeyWidth: isLandscape ? 31 : 33,
                onScreenKeyHeight: isLandscape ? 32 : 34,
                onScreenActionKeyWidth: isLandscape ? 102 : 96,
                onScreenSpaceKeyWidth: isLandscape ? 178 : 152,
                cardPadding: isLandscape ? 10 : 11
            )
        }

        let trackpadHeight = min(max(size.height * (isLandscape ? 0.34 : 0.30), isLandscape ? 170 : 210), isLandscape ? 220 : 300)
        return LayoutMetrics(
            isPadLayout: false,
            horizontalPadding: isLandscape ? 10 : 12,
            verticalPadding: 12,
            stackSpacing: 12,
            trackpadHeight: trackpadHeight,
            splitTopCards: isWidePhoneLandscape,
            controlButtonMinWidth: isLandscape ? 112 : 96,
            navigationMinWidth: isLandscape ? 78 : 72,
            functionMinWidth: isLandscape ? 56 : 52,
            mediaMinWidth: isLandscape ? 66 : 62,
            modifierMinWidth: isLandscape ? 78 : 74,
            onScreenKeyFontSize: isLandscape ? 10 : 11,
            onScreenKeySpacing: 4,
            onScreenKeyWidth: isLandscape ? 26 : 27,
            onScreenKeyHeight: isLandscape ? 30 : 31,
            onScreenActionKeyWidth: isLandscape ? 90 : 88,
            onScreenSpaceKeyWidth: isLandscape ? 142 : 128,
            cardPadding: 10
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

    private func statusCard(layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bluetooth Remote เพราะกู ขก. ลุก")
                .font(layout.isPadLayout ? .title2 : .title3)
                .bold()
                .lineLimit(layout.isPadLayout ? 2 : 3)
                .minimumScaleFactor(0.82)
            Text(bluetooth.stateSummary)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Connected BLE clients: \(bluetooth.subscribedCentralCount)")
                .font(.footnote)
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
        }
        .padding(layout.cardPadding)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func wifiCard(layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wifi connector")
                .font(.headline)

            Text(bluetooth.wifiStatus)
                .font(.footnote)
                .foregroundColor(.secondary)

            TextField("ws://<windows-ip>:8765", text: $webSocketURL)
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                Button("Auto Discover") {
                    bluetooth.discoverWebSocketServer { discoveredURL in
                        guard let discoveredURL else {
                            return
                        }
                        webSocketURL = discoveredURL
                    }
                }
                .buttonStyle(.bordered)

                Button("Connect") {
                    bluetooth.connectWebSocket(
                        urlString: webSocketURL.trimmingCharacters(in: .whitespacesAndNewlines),
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

    private func trackpadCard(height: CGFloat) -> some View {
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
                    .font(.system(size: 36))
                    .foregroundColor(colorScheme == .dark ? .cyan.opacity(0.9) : .blue.opacity(0.9))
                Text("แตะกู กูบอกให้มึงแตะกู")
                    .font(.headline)
                //Text("1 finger move, 2 finger scroll, double-tap left click, long-press right click")
                Text("คือกูขี้เกียจลุกมากๆ กูเลยทำแอพนี้มาใช้เอง จะได้ไม่ต้องลุกไปจับเม้าส์ พอกูจะหาแอปแบบนี้ใน App Store แม่งก็เสือกมีโฆษณาเต็มแอป หรือไม่ก็กูต้องจ่ายตังซื้อแอปหลอกแดกตังโง่ๆ ควย ไอ่เหี้ย")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
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

    private func mouseButtonRow(minWidth: CGFloat) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: 8)], spacing: 8) {
            Button("Left Click") {
                bluetooth.sendMouseButton(button: .left, action: .click)
            }
            .buttonStyle(.borderedProminent)

            Button("Middle") {
                bluetooth.sendMouseButton(button: .middle, action: .click)
            }
            .buttonStyle(.bordered)

            Button("Right Click") {
                bluetooth.sendMouseButton(button: .right, action: .click)
            }
            .buttonStyle(.bordered)
        }
    }

    private func keyboardCard(layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard")
                .font(.headline)

            Picker("Keyboard Mode", selection: $keyboardInputMode) {
                ForEach(KeyboardInputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

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
        VStack(spacing: layout.onScreenKeySpacing) {
            ForEach(Array(onScreenLetterRows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: layout.onScreenKeySpacing) {
                    ForEach(row, id: \.self) { letter in
                        onScreenKeyButton(
                            title: letter,
                            width: layout.onScreenKeyWidth,
                            height: layout.onScreenKeyHeight,
                            fontSize: layout.onScreenKeyFontSize
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
                    width: layout.onScreenSpaceKeyWidth,
                    height: layout.onScreenKeyHeight,
                    fontSize: layout.onScreenKeyFontSize
                ) {
                    bluetooth.sendKey(usageID: 0x2C, action: .tap)
                }

                onScreenKeyButton(
                    title: "Backspace",
                    width: layout.onScreenActionKeyWidth,
                    height: layout.onScreenKeyHeight,
                    fontSize: layout.onScreenKeyFontSize
                ) {
                    bluetooth.sendKey(usageID: 0x2A, action: .tap)
                }

                onScreenKeyButton(
                    title: "Enter",
                    width: layout.onScreenActionKeyWidth,
                    height: layout.onScreenKeyHeight,
                    fontSize: layout.onScreenKeyFontSize
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
        width: CGFloat,
        height: CGFloat,
        fontSize: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(title) {
            action()
        }
        .buttonStyle(.bordered)
        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: width, height: height)
    }

    private func scrollButtonRow(minWidth: CGFloat) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: 8)], spacing: 8) {
            Button("Scroll Up") {
                bluetooth.sendScroll(dx: 0, dy: 1)
            }
            .buttonStyle(.bordered)

            Button("Scroll Down") {
                bluetooth.sendScroll(dx: 0, dy: -1)
            }
            .buttonStyle(.bordered)

            Button("Scroll Left") {
                bluetooth.sendScroll(dx: -1, dy: 0)
            }
            .buttonStyle(.bordered)

            Button("Scroll Right") {
                bluetooth.sendScroll(dx: 1, dy: 0)
            }
            .buttonStyle(.bordered)
        }
    }

    private func modifierPanel(layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Modifiers")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Release All") {
                    releaseAllModifiers()
                }
                .buttonStyle(.bordered)
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
