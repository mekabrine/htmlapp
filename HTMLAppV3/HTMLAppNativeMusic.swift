import AVFoundation
import CoreMIDI

/// Native sampler and MIDI output. The caller supplies its licensed sound bank;
/// this is not a JavaScript audio callback on the real-time render thread.
@MainActor
final class HTMLAppNativeMusic {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var ready = false
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var activeNotes: Set<UInt8> = []
    init() { engine.attach(sampler); engine.connect(sampler, to: engine.mainMixerNode, format: nil) }
    func load(_ file: URL, program: UInt8) throws {
        guard ["sf2", "dls"].contains(file.pathExtension.lowercased()) else { throw Failure.invalid }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try audio.setPreferredIOBufferDuration(0.005)
        try audio.setActive(true)
        try sampler.loadSoundBankInstrument(at: file, program: program, bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: 0)
        engine.prepare(); try engine.start(); ready = true
    }
    func note(_ args: [String: Any], on: Bool) throws {
        let velocity = args["velocity"] as? Int ?? (on ? 90 : 0)
        guard ready, let raw = args["note"] as? Int, (0...127).contains(raw),
              (0...127).contains(velocity) else { throw Failure.invalid }
        let note = UInt8(raw)
        if on {
            guard activeNotes.count < 32 || activeNotes.contains(note) else { throw Failure.limit }
            sampler.startNote(note, withVelocity: UInt8(velocity), onChannel: 0); activeNotes.insert(note)
        } else { sampler.stopNote(note, onChannel: 0); activeNotes.remove(note) }
    }
    func destinations() -> [[String: Any]] {
        (0..<MIDIGetNumberOfDestinations()).map { index in
            let endpoint = MIDIGetDestination(index)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
            return ["index": index, "name": name?.takeRetainedValue() as String? ?? "MIDI destination"]
        }
    }
    func send(_ args: [String: Any]) throws {
        guard let destination = args["destination"] as? Int, destination >= 0, destination < MIDIGetNumberOfDestinations(),
              let bytes = args["bytes"] as? [Int], (1...3).contains(bytes.count), bytes.allSatisfy({ (0...255).contains($0) }),
              let status = bytes.first, (0x80...0xEF).contains(status),
              bytes.dropFirst().allSatisfy({ $0 < 128 }),
              bytes.count == (((status & 0xF0) == 0xC0 || (status & 0xF0) == 0xD0) ? 2 : 3) else { throw Failure.invalid }
        if client == 0 { guard MIDIClientCreate("HTMLApp" as CFString, nil, nil, &client) == noErr else { throw Failure.unavailable } }
        if port == 0 { guard MIDIOutputPortCreate(client, "HTMLApp Output" as CFString, &port) == noErr else { throw Failure.unavailable } }
        var list = MIDIPacketList()
        let data = bytes.map(UInt8.init)
        let statusCode = withUnsafeMutablePointer(to: &list) { pointer -> OSStatus in
            let packet = MIDIPacketListInit(pointer)
            return data.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress, MIDIPacketListAdd(pointer, MemoryLayout<MIDIPacketList>.size, packet, 0, data.count, base) != nil else { return -1 }
                return MIDISend(port, MIDIGetDestination(destination), pointer)
            }
        }
        guard statusCode == noErr else { throw Failure.unavailable }
    }
    func stop() {
        activeNotes.forEach { sampler.stopNote($0, onChannel: 0) }; activeNotes.removeAll()
        engine.stop(); ready = false
        if port != 0 { MIDIPortDispose(port); port = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
    }
    enum Failure: LocalizedError { case invalid, unavailable, limit
        var errorDescription: String? { "Native music requires a valid local SF2/DLS bank or MIDI destination and bounded note/message values." }
    }
}
