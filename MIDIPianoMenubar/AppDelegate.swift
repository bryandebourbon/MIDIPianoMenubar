import Cocoa
import AppKit
import CoreMIDI
import AVFoundation
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    var statusItem: NSStatusItem!
    var midiClient = MIDIClientRef()
    var midiInputPort = MIDIPortRef()
    var audioEngine = AVAudioEngine()
    var sampler = AVAudioUnitSampler()
    var soundFontName = "Piano" // Name of your SoundFont file without extension

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up the status bar item
        setupStatusBarItem()
        
        // Set up the audio engine and sampler
        setupAudioEngine()
        
        // Set up MIDI input
        setupMIDI()
        
        // Start the audio engine
        startAudioEngine()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Dispose of MIDI resources
        MIDIPortDispose(midiInputPort)
        MIDIClientDispose(midiClient)
    }

    // MARK: - Setup Methods

    func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Use an SF Symbol for the status bar icon
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "pianokeys", accessibilityDescription: "MIDI Piano")
            } else {
                // Fallback for older macOS versions
                button.title = "🎹"
            }
        }
        
        // Create a menu for the status item
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit MIDI Piano", action: #selector(quitApplication), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func setupAudioEngine() {
        // Attach and connect the sampler to the audio engine
        audioEngine.attach(sampler)
        let mainMixer = audioEngine.mainMixerNode
        audioEngine.connect(sampler, to: mainMixer, format: nil)
        
        // Load the SoundFont into the sampler
        loadSoundFont()
    }
    func handleMIDINotifyMessage(_ message: UnsafePointer<MIDINotification>) {
        let messageID = message.pointee.messageID
        if messageID == .msgObjectAdded || messageID == .msgObjectRemoved {
            DispatchQueue.main.async {
                self.connectMIDISources()
            }
        }
    }
    func setupMIDI() {
        // Create MIDI client with notification block
        MIDIClientCreateWithBlock("MIDI Client" as CFString, &midiClient) { [weak self] message in
            self?.handleMIDINotifyMessage(message)
        }
        
        // Create MIDI input port
        MIDIInputPortCreate(midiClient, "Input Port" as CFString, midiReadProc, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &midiInputPort)
        
        // Connect existing MIDI sources
        connectMIDISources()
    }


    func startAudioEngine() {
        do {
            try audioEngine.start()
        } catch {
            print("Error starting audio engine: \(error.localizedDescription)")
        }
    }

    // MARK: - MIDI Handling

    func connectMIDISources() {
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let src = MIDIGetSource(i)
            MIDIPortConnectSource(midiInputPort, src, nil)
        }
    }

    let midiReadProc: MIDIReadProc = { (packetList, srcConnRefCon, destConnRefCon) in
        let appDelegate = Unmanaged<AppDelegate>.fromOpaque(srcConnRefCon!).takeUnretainedValue()
        let packetListPointer = UnsafeMutablePointer<MIDIPacketList>(mutating: packetList)
        let packets = packetListPointer.pointee
        var packet = packets.packet
        for _ in 0..<packets.numPackets {
            let midiStatus = packet.data.0
            let midiCommand = midiStatus >> 4
            let channel = midiStatus & 0x0F
            if midiCommand == 0x9 || midiCommand == 0x8 { // Note On or Note Off
                let note = packet.data.1
                let velocity = packet.data.2
                DispatchQueue.main.async {
                    if midiCommand == 0x9 && velocity > 0 {
                        // Note On
                        appDelegate.sampler.startNote(note, withVelocity: velocity, onChannel: channel)
                    } else {
                        // Note Off
                        appDelegate.sampler.stopNote(note, onChannel: channel)
                    }
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

//    let midiNotifyProc: MIDINotifyProc = { (message, srcConnRefCon) in
//        let appDelegate = Unmanaged<AppDelegate>.fromOpaque(srcConnRefCon!).takeUnretainedValue()
//        let messageID = message.pointee.messageID
//        if messageID == .msgObjectAdded || messageID == .msgObjectRemoved {
//            DispatchQueue.main.async {
//                appDelegate.connectMIDISources()
//            }
//        }
//    }

    // MARK: - SoundFont Loading

    func loadSoundFont() {
        guard let bankURL = Bundle.main.url(forResource: soundFontName, withExtension: "sf2") else {
            print("SoundFont file not found.")
            return
        }
        do {
            try sampler.loadSoundBankInstrument(at: bankURL,
                                                program: 0,
                                                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                                bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        } catch {
            print("Error loading SoundFont: \(error.localizedDescription)")
        }
    }

    // MARK: - Actions

    @objc func quitApplication() {
        NSApplication.shared.terminate(self)
    }
}
