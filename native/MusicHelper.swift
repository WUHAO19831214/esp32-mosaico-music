import Foundation
import IOBluetooth
import CoreAudio
import AVFoundation
import Speech
import AppKit

func emit(_ value: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    if let i=CommandLine.arguments.firstIndex(of:"--result"),CommandLine.arguments.count>i+1 {try? data.write(to:URL(fileURLWithPath:CommandLine.arguments[i+1]),options:.atomic)}
}
func propString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var v: Unmanaged<CFString>?; var n = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &n, &v) == noErr, let value = v?.takeUnretainedValue() else { return "" }
    return value as String
}
func defaultOutput() -> AudioDeviceID {
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var id: AudioDeviceID = 0; var n = UInt32(MemoryLayout<AudioDeviceID>.size)
    _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &n, &id); return id
}
func outputs() -> [[String: Any]] {
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var n: UInt32 = 0; let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &n) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(n) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &a, 0, nil, &n, &ids) == noErr else { return [] }
    return ids.compactMap { id in
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &size) == noErr, size > 0 else { return nil }
        var transport = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var type: UInt32 = 0; size = 4; _ = AudioObjectGetPropertyData(id, &transport, 0, nil, &size, &type)
        return ["uid": propString(id, kAudioDevicePropertyDeviceUID), "name": propString(id, kAudioObjectPropertyName), "bluetooth": type == kAudioDeviceTransportTypeBluetooth || type == kAudioDeviceTransportTypeBluetoothLE, "builtin": type == kAudioDeviceTransportTypeBuiltIn, "default": id == defaultOutput()]
    }
}
func addressKey(_ s: String) -> String { s.lowercased().filter { $0.isHexDigit } }
func audioPeripheral(_ d: IOBluetoothDevice) -> Bool {
    if d.deviceClassMajor == kBluetoothDeviceClassMajorAudio { return true }
    let name = (d.nameOrAddress ?? "").lowercased()
    return ["airpods", "speaker", "headset", "headphone", "buds", "jbl", "bose", "sony", "音箱", "音响", "耳机", "bv370"].contains { name.contains($0) }
}
class Inquiry: NSObject, IOBluetoothDeviceInquiryDelegate {
    var devices: [IOBluetoothDevice] = []; var done = false; var result: IOReturn = kIOReturnSuccess
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) { if let d = device, audioPeripheral(d), !devices.contains(where: { $0.addressString == d.addressString }) { devices.append(d) } }
    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) { result = error; done = true }
}
func bluetoothDevices(scan: Bool) -> ([[String: Any]], String?) {
    var devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter(audioPeripheral)
    var error: String?
    if scan {
        let delegate = Inquiry()
        if let inquiry = IOBluetoothDeviceInquiry(delegate: delegate) {
            inquiry.inquiryLength = 8; inquiry.updateNewDeviceNames = true
            let result = inquiry.start()
            if result == kIOReturnSuccess {
                let deadline = Date().addingTimeInterval(10)
                while !delegate.done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
                inquiry.stop()
                devices += delegate.devices.filter { found in !devices.contains { $0.addressString == found.addressString } }
                if delegate.result != kIOReturnSuccess { error = "蓝牙扫描失败（\(delegate.result)），请检查系统蓝牙权限" }
            } else { error = "无法启动蓝牙扫描（\(result)），请检查蓝牙是否开启及系统授权" }
        } else { error = "系统蓝牙不可用" }
    }
    return (devices.map { ["address": $0.addressString ?? "", "name": $0.nameOrAddress ?? "蓝牙音频", "paired": $0.isPaired(), "connected": $0.isConnected()] }.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }, error)
}
func routeFor(_ d: IOBluetoothDevice) -> [String: Any]? {
    let candidates = outputs().filter { $0["bluetooth"] as? Bool == true }
    let key = addressKey(d.addressString ?? "")
    if key.count == 12, let exact = candidates.first(where: { addressKey($0["uid"] as? String ?? "").contains(key) }) { return exact }
    let names = candidates.filter { ($0["name"] as? String ?? "").caseInsensitiveCompare(d.nameOrAddress ?? "") == .orderedSame }
    return names.count == 1 ? names[0] : nil
}
class PairConfirmation: NSObject, IOBluetoothDevicePairDelegate {
    var done = false; var error: IOReturn = kIOReturnError
    func devicePairingFinished(_ sender: Any!, error: IOReturn) { self.error = error; done = true }
    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        guard let pair = sender as? IOBluetoothDevicePair else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "确认音箱蓝牙配对"; alert.informativeText = "请核对设备与配对码：\(String(format: "%06u", numericValue))"; alert.addButton(withTitle: "确认配对"); alert.addButton(withTitle: "取消")
        pair.replyUserConfirmation(alert.runModal() == .alertFirstButtonReturn)
    }
    func devicePairingPINCodeRequest(_ sender: Any!) {
        guard let pair = sender as? IOBluetoothDevicePair else { return }
        let alert = NSAlert(); alert.messageText = "请输入音箱配对 PIN"; alert.informativeText = "请查看音箱说明，不确定时取消。"; let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 26)); alert.accessoryView = field; alert.addButton(withTitle: "配对"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty, field.stringValue.utf8.count <= 16 else { pair.stop(); return }
        var pin = BluetoothPINCode(); let bytes = Array(field.stringValue.utf8)
        withUnsafeMutableBytes(of: &pin) { b in for (i, value) in bytes.enumerated() { b[i] = value } }; pair.replyPINCode(bytes.count, pinCode: &pin)
    }
}
func connect(_ address: String) -> [String: Any] {
    guard addressKey(address).count == 12, let d = IOBluetoothDevice(addressString: address) else { return ["ok": false, "error": "请选择明确的蓝牙设备"] }
    if !d.isPaired() {
        let delegate = PairConfirmation()
        if let pair = IOBluetoothDevicePair(device: d) {
            pair.delegate = delegate
            if pair.start() == kIOReturnSuccess {
                let end = Date().addingTimeInterval(18)
                while !delegate.done && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
                if !delegate.done { pair.stop() }
            }
        }
        if d.isPaired() { d.openConnection() }
    } else if !d.isConnected() { d.openConnection() }
    let deadline = Date().addingTimeInterval(16)
    while Date() < deadline {
        if d.isConnected(), let route = routeFor(d) { return ["ok": true, "connected": true, "route": route, "address": address, "name": d.nameOrAddress ?? address] }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return ["ok": false, "error": d.isPaired() ? "设备尚未提供音频输出，请让音箱进入连接模式后重试" : "请先在 Mac 系统蓝牙设置完成此设备的配对，再返回连接", "connected": d.isConnected(), "address": address]
}
func speechStatus() -> [String: Any] {
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    return ["authorized": SFSpeechRecognizer.authorizationStatus() == .authorized, "authorization": SFSpeechRecognizer.authorizationStatus().rawValue, "local": recognizer?.supportsOnDeviceRecognition ?? false, "available": recognizer?.isAvailable ?? false]
}
func authorizeSpeech() -> Bool {
    var finished = false; var granted = false
    SFSpeechRecognizer.requestAuthorization { s in granted = s == .authorized; finished = true }
    let deadline = Date().addingTimeInterval(80)
    while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    return granted
}
func transcribe(_ file: String) {
    guard SFSpeechRecognizer.authorizationStatus() == .authorized else { emit(["ok": false, "error": "请先允许音乐助手使用语音识别"]); return }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.supportsOnDeviceRecognition else { emit(["ok": false, "error": "本机暂未提供中文离线识别，请在 macOS 下载中文听写语言后重试"]); return }
    let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: file)); request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = false
    var done = false; var text = ""; var failure = ""
    let task = recognizer.recognitionTask(with: request) { result, error in
        if let result = result, result.isFinal { text = result.bestTranscription.formattedString; done = true }
        if let error = error { failure = error.localizedDescription; done = true }
    }
    let deadline = Date().addingTimeInterval(30)
    while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    task.cancel(); emit(text.isEmpty ? ["ok": false, "error": failure.isEmpty ? "没有识别到歌名，请靠近麦克风重试" : failure] : ["ok": true, "text": text])
}
func player(_ uid: String) {
    guard outputs().contains(where: { $0["uid"] as? String == uid }) else { emit(["ok": false, "error": "所选音频设备已离线"]); return }
    let p = AVPlayer(); p.audioOutputDeviceUniqueID = uid
    guard p.audioOutputDeviceUniqueID == uid else { emit(["ok": false, "error": "系统未确认所选音频输出"]); return }
    var running = true; var desired = "idle"; var failure = ""
    FileHandle.standardInput.readabilityHandler = { h in
        let data = h.availableData
        if data.isEmpty { DispatchQueue.main.async { running = false }; return }
        for line in String(data: data, encoding: .utf8)?.split(separator: "\n") ?? [] {
            guard let raw = line.data(using: .utf8), let d = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { continue }
            DispatchQueue.main.async {
                switch d["action"] as? String ?? "" {
                case "play":
                    if let s = d["url"] as? String, let url = URL(string: s), ["http", "https", "file"].contains(url.scheme ?? "") {
                        p.replaceCurrentItem(with: AVPlayerItem(url: url)); p.volume = Float((d["volume"] as? Double ?? 30) / 100); p.play(); desired = "playing"; failure = ""
                    }
                case "pause": p.pause(); desired = "paused"
                case "resume": p.play(); desired = "playing"
                case "volume": p.volume = Float((d["volume"] as? Double ?? 30) / 100)
                case "stop": p.pause(); p.replaceCurrentItem(with: nil); desired = "idle"
                case "quit": running = false
                default: break
                }
            }
        }
    }
    let token = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { _ in desired = "finished" }
    emit(["ok": true, "ready": true, "uid": uid])
    var last = Date.distantPast
    while running {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        if Date().timeIntervalSince(last) > 0.7 {
            if !outputs().contains(where: { $0["uid"] as? String == uid }) { p.pause(); failure = "所选音频设备已断开，播放已暂停"; desired = "error" }
            if p.currentItem?.status == .failed { failure = p.currentItem?.error?.localizedDescription ?? "音频加载失败"; desired = "error" }
            let state = desired == "playing" && p.timeControlStatus != .playing ? "loading" : desired
            let seconds = p.currentTime().seconds
            emit(["ok": true, "state": state, "uid": p.audioOutputDeviceUniqueID ?? "", "position": seconds.isFinite ? seconds : 0, "error": failure]); last = Date()
        }
    }
    NotificationCenter.default.removeObserver(token); p.pause(); FileHandle.standardInput.readabilityHandler = nil
}
let args = CommandLine.arguments
let action = args.count > 1 ? args[1] : "status"
let value = args.count > 2 ? args[2] : ""
switch action {
case "player": player(value)
case "connect": emit(connect(value))
case "disconnect":
    if addressKey(value).count == 12, let d = IOBluetoothDevice(addressString: value) { _ = d.closeConnection(); emit(["ok": !d.isConnected()]) } else { emit(["ok": false, "error": "未选择蓝牙设备"]) }
case "speech-authorize": emit(["ok": authorizeSpeech(), "speech": speechStatus()])
case "transcribe": transcribe(value)
default:
    let (devices, error) = bluetoothDevices(scan: action == "scan")
    var response: [String: Any] = ["ok": error == nil, "host": Host.current().localizedName ?? ProcessInfo.processInfo.hostName, "outputs": outputs(), "devices": devices, "speech": speechStatus()]
    if let error = error { response["error"] = error }; emit(response)
}
