// Does a second `tell application "VoiceOver" to output` interrupt the first
// utterance or queue behind it? Nobody can listen in an unattended session, so
// this watches whether the default audio output device is still running: a
// 120-word paragraph takes well over 10 s to speak; if audio stops within a few
// seconds of the short second output, `output` interrupts.
// Run with the screen unlocked, VoiceOver on, and nothing else playing audio:
//   swift tools/dev/vo_output_semantics.swift
import CoreAudio
import Foundation

func defaultOutputDevice() -> AudioDeviceID {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
    return device
}

func isRunning(_ device: AudioDeviceID) -> Bool {
    var running = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
    return running != 0
}

func voiceOverOutput(_ text: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
    process.arguments = ["-e", "tell application \"VoiceOver\" to output \"\(escaped)\""]
    try? process.run()
    process.waitUntilExit()
    print(String(format: "%.2f", Date().timeIntervalSince(start)), "output returned, status", process.terminationStatus)
}

let start = Date()
let device = defaultOutputDevice()
print("device running before:", isRunning(device))
let paragraph = Array(repeating: "The quick brown fox jumps over the lazy dog near the river bank while the sun sets slowly.", count: 8).joined(separator: " ")
voiceOverOutput(paragraph)
Thread.sleep(forTimeInterval: 0.5)
voiceOverOutput("bravo")
for _ in 0..<48 {
    Thread.sleep(forTimeInterval: 0.25)
    print(String(format: "%.2f", Date().timeIntervalSince(start)), "running:", isRunning(device))
}
