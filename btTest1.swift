import Combine
import CoreBluetooth
import Darwin
import Foundation

final class BluetoothInputManager: NSObject, ObservableObject, CBPeripheralManagerDelegate, URLSessionWebSocketDelegate {
    enum EventType: UInt8 {
        case mouseMove = 0x01
        case mouseButton = 0x02
        case mouseScroll = 0x03
        case keyboard = 0x04
        case text = 0x05
        case ping = 0x06
        case consumer = 0x07
    }

    enum MouseButton: UInt8 {
        case left = 0x01
        case right = 0x02
        case middle = 0x03
    }

    enum ButtonAction: UInt8 {
        case up = 0x00
        case down = 0x01
        case click = 0x02
    }

    enum KeyAction: UInt8 {
        case up = 0x00
        case down = 0x01
        case tap = 0x02
    }

    static let packetMagic: UInt8 = 0x42
    static let packetVersion: UInt8 = 0x01
    private static let defaultAdvertisingName = "iPhoneRemotePad"

    let serviceUUID = CBUUID(string: "E20A3914-ECB4-40E4-BA35-5026E881D26E")
    let inputCharacteristicUUID = CBUUID(string: "01234567-89AB-CDEF-0123-456789ABCDEF")
    let controlCharacteristicUUID = CBUUID(string: "89ABCDEF-0123-4567-89AB-CDEF01234567")

    @Published private(set) var stateSummary = "Initializing Bluetooth..."
    @Published private(set) var subscribedCentralCount = 0
    @Published private(set) var isAdvertising = false
    @Published private(set) var advertisingName = defaultAdvertisingName
    @Published private(set) var wifiStatus = "Wi-Fi disconnected"
    @Published private(set) var isWiFiConnected = false
    @Published private(set) var discoveredWebSocketURL: String = ""

    private var peripheralManager: CBPeripheralManager!
    private var inputCharacteristic: CBMutableCharacteristic?
    private var controlCharacteristic: CBMutableCharacteristic?
    private var pendingPackets: [Data] = []
    private var pendingWebSocketPackets: [Data] = []
    private var serviceAdded = false

    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketAuthToken: String = ""

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    deinit {
        disconnectWebSocket()
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            stateSummary = "Bluetooth ready"
            configureServiceIfNeeded()
        case .poweredOff:
            stateSummary = "Bluetooth is turned off"
            pendingPackets.removeAll()
            isAdvertising = false
        case .resetting:
            stateSummary = "Bluetooth resetting"
            pendingPackets.removeAll()
            isAdvertising = false
        case .unauthorized:
            stateSummary = "Bluetooth permission denied"
            isAdvertising = false
        case .unsupported:
            stateSummary = "Bluetooth LE unsupported"
            isAdvertising = false
        case .unknown:
            stateSummary = "Bluetooth state unknown"
            isAdvertising = false
        @unknown default:
            stateSummary = "Bluetooth state changed"
            isAdvertising = false
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            stateSummary = "Failed to add service: \(error.localizedDescription)"
            serviceAdded = false
            isAdvertising = false
            return
        }

        serviceAdded = true
        startAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            stateSummary = "Advertising error: \(error.localizedDescription)"
            isAdvertising = false
            return
        }

        stateSummary = "Advertising as \(advertisingName)"
        isAdvertising = true
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscribedCentralCount += 1
        stateSummary = "Connected centrals: \(subscribedCentralCount)"
        flushPendingPackets()
        sendPing()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentralCount = max(0, subscribedCentralCount - 1)
        stateSummary = "Connected centrals: \(subscribedCentralCount)"
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        flushPendingPackets()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == controlCharacteristicUUID else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
                continue
            }

            peripheral.respond(to: request, withResult: .success)
        }
    }

    func sendMouseMove(dx: Int16, dy: Int16) {
        var payload = Data()
        payload.appendLittleEndian(dx)
        payload.appendLittleEndian(dy)
        enqueue(event: .mouseMove, payload: payload)
    }

    func sendMouseButton(button: MouseButton, action: ButtonAction) {
        let payload = Data([button.rawValue, action.rawValue])
        enqueue(event: .mouseButton, payload: payload)
    }

    func sendScroll(dx: Int16, dy: Int16) {
        var payload = Data()
        payload.appendLittleEndian(dx)
        payload.appendLittleEndian(dy)
        enqueue(event: .mouseScroll, payload: payload)
    }

    func sendKey(usageID: UInt16, action: KeyAction) {
        var payload = Data()
        payload.appendLittleEndian(usageID)
        payload.append(action.rawValue)
        enqueue(event: .keyboard, payload: payload)
    }

    func sendConsumerKey(usageID: UInt16, action: KeyAction) {
        var payload = Data()
        payload.appendLittleEndian(usageID)
        payload.append(action.rawValue)
        enqueue(event: .consumer, payload: payload)
    }

    func sendText(_ text: String) {
        guard let textData = text.data(using: .utf8), !textData.isEmpty else {
            return
        }

        // Keep packets within a single BLE ATT frame for lower latency.
        let maxPayloadSize = min(textData.count, 180)
        var payload = Data([UInt8(maxPayloadSize)])
        payload.append(textData.prefix(maxPayloadSize))
        enqueue(event: .text, payload: payload)
    }

    func sendPing() {
        enqueue(event: .ping, payload: Data())
    }

    func setAdvertisingName(_ name: String) {
        let sanitizedName = sanitizeAdvertisingName(name)
        guard sanitizedName != advertisingName else {
            return
        }

        advertisingName = sanitizedName

        guard peripheralManager.state == .poweredOn else {
            return
        }

        guard serviceAdded else {
            return
        }

        if peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
        }

        startAdvertising()
    }

    func disconnectBluetooth() {
        pendingPackets.removeAll()
        subscribedCentralCount = 0

        if peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
        }

        peripheralManager.removeAllServices()
        inputCharacteristic = nil
        controlCharacteristic = nil
        serviceAdded = false
        isAdvertising = false
        stateSummary = "Bluetooth disconnected"
    }

    func reconnectBluetooth() {
        guard peripheralManager.state == .poweredOn else {
            stateSummary = "Bluetooth unavailable"
            return
        }

        stateSummary = "Bluetooth reconnecting..."
        configureServiceIfNeeded()
    }

    func toggleBluetoothConnection() {
        if isAdvertising || subscribedCentralCount > 0 {
            disconnectBluetooth()
        } else {
            reconnectBluetooth()
        }
    }

    func connectWebSocket(urlString: String, token: String, requireSecure: Bool = false) {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss" else {
            updateWiFiState(status: "Wi-Fi URL invalid. Use ws:// or wss://", connected: false)
            return
        }

        if requireSecure && scheme != "wss" {
            updateWiFiState(status: "Secure mode requires wss:// URL", connected: false)
            return
        }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            updateWiFiState(status: "Wi-Fi token required", connected: false)
            return
        }

        disconnectWebSocket()

        webSocketAuthToken = trimmedToken

        if requireSecure {
            updateWiFiState(status: "Wi-Fi connecting securely...", connected: false)
        } else {
            updateWiFiState(status: "Wi-Fi connecting...", connected: false)
        }
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        listenForWebSocketMessages()
    }

    func discoverWebSocketServer(discoveryPort: UInt16 = 8766, completion: @escaping (String?) -> Void) {
        updateWiFiState(status: "Discovering Windows receiver...", connected: isWiFiConnected)

        DispatchQueue.global(qos: .userInitiated).async {
            let discoveredURL = UDPDiscoveryClient.discover(discoveryPort: discoveryPort)
            DispatchQueue.main.async {
                if let discoveredURL {
                    self.discoveredWebSocketURL = discoveredURL
                    self.updateWiFiState(status: "Discovered Wi-Fi endpoint", connected: self.isWiFiConnected)
                } else {
                    self.updateWiFiState(status: "Discovery timeout. Enter URL manually.", connected: self.isWiFiConnected)
                }
                completion(discoveredURL)
            }
        }
    }

    func disconnectWebSocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        webSocketAuthToken = ""
        pendingWebSocketPackets.removeAll()
        updateWiFiState(status: "Wi-Fi disconnected", connected: false)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocolValue: String?) {
        updateWiFiState(status: "Wi-Fi connected, authenticating...", connected: false)
        sendWebSocketAuthToken()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        updateWiFiState(status: "Wi-Fi disconnected (\(closeCode.rawValue))", connected: false)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task == webSocketTask else {
            return
        }

        if let error {
            updateWiFiState(status: "Wi-Fi error: \(error.localizedDescription)", connected: false)
        }
    }

    private func configureServiceIfNeeded() {
        guard !serviceAdded else {
            startAdvertising()
            return
        }

        inputCharacteristic = CBMutableCharacteristic(
            type: inputCharacteristicUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )

        controlCharacteristic = CBMutableCharacteristic(
            type: controlCharacteristicUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        guard let inputCharacteristic, let controlCharacteristic else {
            stateSummary = "Failed to create BLE characteristics"
            return
        }

        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [inputCharacteristic, controlCharacteristic]
        peripheralManager.add(service)
    }

    private func startAdvertising() {
        guard peripheralManager.state == .poweredOn else {
            return
        }

        if peripheralManager.isAdvertising {
            return
        }

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: advertisingName,
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])
    }

    private func sanitizeAdvertisingName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Self.defaultAdvertisingName
        }

        // Keep this short so local name + service UUID fit in BLE advertising payload.
        let maxUTF8Bytes = 18
        var result = ""
        var currentBytes = 0

        for scalar in trimmed.unicodeScalars {
            let scalarString = String(scalar)
            let scalarBytes = scalarString.lengthOfBytes(using: .utf8)
            if currentBytes + scalarBytes > maxUTF8Bytes {
                break
            }

            result.unicodeScalars.append(scalar)
            currentBytes += scalarBytes
        }

        return result.isEmpty ? Self.defaultAdvertisingName : result
    }

    private func enqueue(event: EventType, payload: Data) {
        let packet = makePacket(event: event, payload: payload)

        let bleAccepted = enqueueToBLE(packet)
        let webSocketAccepted = enqueueToWebSocket(packet)
        if !bleAccepted && !webSocketAccepted {
            return
        }
    }

    private func enqueueToBLE(_ packet: Data) -> Bool {
        guard subscribedCentralCount > 0 else {
            return false
        }

        guard let inputCharacteristic else {
            pendingPackets.append(packet)
            trimBLEQueueIfNeeded()
            return true
        }

        let didSend = peripheralManager.updateValue(packet, for: inputCharacteristic, onSubscribedCentrals: nil)
        if !didSend {
            pendingPackets.append(packet)
            trimBLEQueueIfNeeded()
        }

        return true
    }

    private func enqueueToWebSocket(_ packet: Data) -> Bool {
        guard webSocketTask != nil else {
            return false
        }

        if isWiFiConnected {
            sendPacketOverWebSocket(packet)
        } else {
            pendingWebSocketPackets.append(packet)
            trimWebSocketQueueIfNeeded()
        }

        return true
    }

    private func flushPendingPackets() {
        guard let inputCharacteristic else {
            return
        }

        while !pendingPackets.isEmpty {
            let packet = pendingPackets[0]
            let didSend = peripheralManager.updateValue(packet, for: inputCharacteristic, onSubscribedCentrals: nil)
            if didSend {
                pendingPackets.removeFirst()
            } else {
                break
            }
        }
    }

    private func listenForWebSocketMessages() {
        guard let webSocketTask else {
            return
        }

        webSocketTask.receive { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let message):
                self.handleWebSocketControlMessage(message)
                self.listenForWebSocketMessages()
            case .failure(let error):
                self.updateWiFiState(status: "Wi-Fi receive error: \(error.localizedDescription)", connected: false)
            }
        }
    }

    private func handleWebSocketControlMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            if text == "AUTH_OK" {
                updateWiFiState(status: "Wi-Fi connected", connected: true)
                flushPendingWebSocketPackets()
            } else if text == "AUTH_FAIL" {
                updateWiFiState(status: "Wi-Fi authentication failed", connected: false)
                disconnectWebSocket()
            }
        case .data:
            break
        @unknown default:
            break
        }
    }

    private func sendWebSocketAuthToken() {
        guard !webSocketAuthToken.isEmpty else {
            updateWiFiState(status: "Wi-Fi authentication token missing", connected: false)
            disconnectWebSocket()
            return
        }

        let authMessage = "AUTH:\(webSocketAuthToken)"
        webSocketTask?.send(.string(authMessage)) { [weak self] error in
            guard let self else {
                return
            }

            if let error {
                self.updateWiFiState(status: "Wi-Fi auth error: \(error.localizedDescription)", connected: false)
                return
            }

            self.updateWiFiState(status: "Wi-Fi auth sent, waiting for ACK...", connected: false)
        }
    }

    private func sendPacketOverWebSocket(_ packet: Data) {
        webSocketTask?.send(.data(packet)) { [weak self] error in
            guard let self, let error else {
                return
            }

            self.updateWiFiState(status: "Wi-Fi send error: \(error.localizedDescription)", connected: false)
        }
    }

    private func flushPendingWebSocketPackets() {
        while !pendingWebSocketPackets.isEmpty {
            let packet = pendingWebSocketPackets.removeFirst()
            sendPacketOverWebSocket(packet)
        }
    }

    private func trimBLEQueueIfNeeded() {
        let maxQueue = 256
        if pendingPackets.count > maxQueue {
            pendingPackets.removeFirst(pendingPackets.count - maxQueue)
        }
    }

    private func trimWebSocketQueueIfNeeded() {
        let maxQueue = 256
        if pendingWebSocketPackets.count > maxQueue {
            pendingWebSocketPackets.removeFirst(pendingWebSocketPackets.count - maxQueue)
        }
    }

    private func updateWiFiState(status: String, connected: Bool) {
        DispatchQueue.main.async {
            self.wifiStatus = status
            self.isWiFiConnected = connected
        }
    }

    private func makePacket(event: EventType, payload: Data) -> Data {
        var packet = Data([Self.packetMagic, Self.packetVersion, event.rawValue])
        packet.append(payload)
        return packet
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }
}

private enum UDPDiscoveryClient {
    static func discover(discoveryPort: UInt16, timeoutSeconds: Int = 2) -> String? {
        let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else {
            return nil
        }
        defer {
            close(socketFD)
        }

        var enableBroadcast: Int32 = 1
        _ = setsockopt(socketFD, SOL_SOCKET, SO_BROADCAST, &enableBroadcast, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        _ = setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var localAddress = sockaddr_in()
        localAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        localAddress.sin_family = sa_family_t(AF_INET)
        localAddress.sin_port = in_port_t(0).bigEndian
        localAddress.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &localAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            return nil
        }

        var broadcastAddress = sockaddr_in()
        broadcastAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        broadcastAddress.sin_family = sa_family_t(AF_INET)
        broadcastAddress.sin_port = discoveryPort.bigEndian
        broadcastAddress.sin_addr = in_addr(s_addr: inet_addr("255.255.255.255"))

        let discoveryPayload = Data("RPAD_DISCOVER_V1".utf8)
        let sentBytes = discoveryPayload.withUnsafeBytes { bytes in
            withUnsafePointer(to: &broadcastAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(socketFD, bytes.baseAddress, bytes.count, 0, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        guard sentBytes > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: 1024)
        var sourceAddress = sockaddr_in()
        var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)

        let receivedBytes = withUnsafeMutablePointer(to: &sourceAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                recvfrom(socketFD, &buffer, buffer.count, 0, sockaddrPointer, &sourceLength)
            }
        }

        guard receivedBytes > 0 else {
            return nil
        }

        let responseData = Data(buffer[0..<receivedBytes])
        if let jsonObject = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            if let wsURL = jsonObject["ws_url"] as? String, !wsURL.isEmpty {
                return wsURL
            }

            if let wsPort = jsonObject["ws_port"] as? Int {
                let address = sourceAddress.sin_addr
                let sourceIP = String(cString: inet_ntoa(address))
                return "ws://\(sourceIP):\(wsPort)"
            }
        }

        if let plainURL = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           plainURL.hasPrefix("ws://") || plainURL.hasPrefix("wss://") {
            return plainURL
        }

        return nil
    }
}