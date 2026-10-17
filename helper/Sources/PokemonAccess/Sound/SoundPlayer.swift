import AVFoundation
import Foundation

/// Plays the upstream WAV cues. Upstream passes pan -100..100 and volume
/// 0..100; AVAudioPlayer takes -1..1 and 0..1, scaled here by the soundGain
/// preference (the Windows audio.dll scale is unknown, see PORTING.md 6.6).
/// Every WAV under <root>/sounds is preloaded; paths outside the root are refused.
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    private let root: URL
    private let gain: Double
    private let log: FileLog
    private var preloaded: [String: Data] = [:]
    private var players: [Int: AVAudioPlayer] = [:]
    private var idsByPlayer: [ObjectIdentifier: Int] = [:]
    private let lock = NSLock()

    init(root: URL, gain: Double, log: FileLog) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.gain = gain
        self.log = log
        super.init()
        preload()
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func preload() {
        let soundsDirectory = root.appendingPathComponent("sounds", isDirectory: true)
        guard let files = FileManager.default.enumerator(at: soundsDirectory, includingPropertiesForKeys: nil) else {
            log.error("no sounds directory at \(soundsDirectory.path)")
            return
        }
        var count = 0
        for case let url as URL in files where url.pathExtension.lowercased() == "wav" {
            if let data = try? Data(contentsOf: url) {
                preloaded[canonicalPath(url)] = data
                count += 1
            }
        }
        log.info("preloaded \(count) sounds from \(soundsDirectory.path)")
    }

    func play(id: Int, path: String, loop: Bool, pan: Int, volume: Int) {
        let key = canonicalPath(URL(fileURLWithPath: path))
        guard key.hasPrefix(root.path + "/") else {
            log.error("rejected sound path \(path)")
            return
        }
        var data = preloaded[key]
        if data == nil, let loaded = try? Data(contentsOf: URL(fileURLWithPath: key)) {
            preloaded[key] = loaded
            data = loaded
        }
        guard let data else {
            log.error("sound not found: \(path)")
            return
        }
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.enableRate = true
            player.pan = Float(max(-100, min(100, pan))) / 100
            player.volume = Float(Double(max(0, min(100, volume))) / 100 * gain)
            player.numberOfLoops = loop ? -1 : 0
            lock.lock()
            players[id] = player
            idsByPlayer[ObjectIdentifier(player)] = id
            lock.unlock()
            let started = player.play()
            let relative = key.dropFirst(root.path.count + 1)
            log.info("sound \(id) \(relative) pan \(player.pan) volume \(player.volume) \(started ? "playing" : "did not start")")
        } catch {
            log.error("sound \(path) failed: \(error)")
        }
    }

    func stop(id: Int) {
        lock.lock()
        let player = players.removeValue(forKey: id)
        if let player { idsByPlayer.removeValue(forKey: ObjectIdentifier(player)) }
        lock.unlock()
        player?.stop()
    }

    func setPitch(id: Int, value: Double) {
        lock.lock()
        let player = players[id]
        lock.unlock()
        player?.rate = Float(value)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        lock.lock()
        if let id = idsByPlayer.removeValue(forKey: ObjectIdentifier(player)) {
            players.removeValue(forKey: id)
        }
        lock.unlock()
    }
}
