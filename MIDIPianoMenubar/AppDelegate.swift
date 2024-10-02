import Cocoa
import AppKit
import CoreMIDI
import AVFoundation
import SwiftUI
import IOKit
import IOKit.usb

class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    var statusItem: NSStatusItem!
    var midiClient = MIDIClientRef()
    var midiInputPort = MIDIPortRef()
    var audioEngine = AVAudioEngine()
    var sampler = AVAudioUnitSampler()
    var soundFontName = "Piano" // Name of your SoundFont file without extension
    
    var notifyPort: IONotificationPortRef?
    var addedIterator: io_iterator_t = 0
    var removedIterator: io_iterator_t = 0
    
    var volumeLevel: Float = 0.5 // Default volume level (range 0.0 to 1.0)
    let volumeStep: Float = 0.1  // Amount to increase or decrease the volume

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up the status bar item
        setupStatusBarItem()
        
        // Set up the audio engine and sampler
        setupAudioEngine()
        
        // Set up MIDI input
        setupMIDI()
        
        // Set up USB device notifications
        setupUSBDeviceNotifications()
        
        // Start the audio engine
        startAudioEngine()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Dispose of MIDI resources
        MIDIPortDispose(midiInputPort)
        MIDIClientDispose(midiClient)
        
        // Remove USB notifications
        if let notifyPort = notifyPort {
            IONotificationPortDestroy(notifyPort)
        }
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
        
        // Volume Display (Disabled Menu Item)
        let volumeItem = NSMenuItem(title: "Volume: \(Int(volumeLevel * 100))%", action: nil, keyEquivalent: "")
        volumeItem.isEnabled = false
        menu.addItem(volumeItem)
        
        // Volume Control Menu Items
        menu.addItem(NSMenuItem(title: "Increase Volume", action: #selector(increaseVolume), keyEquivalent: "+"))
        menu.addItem(NSMenuItem(title: "Decrease Volume", action: #selector(decreaseVolume), keyEquivalent: "-"))
        menu.addItem(NSMenuItem.separator())
        
        // Refresh and Quit Menu Items
        menu.addItem(NSMenuItem(title: "Refresh MIDI Devices", action: #selector(refreshMIDIDevices), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MIDI Piano", action: #selector(quitApplication), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func setupAudioEngine() {
        // Attach and connect the sampler to the audio engine
        audioEngine.attach(sampler)
        let mainMixer = audioEngine.mainMixerNode
        audioEngine.connect(sampler, to: mainMixer, format: nil)
        
        // Set initial volume
        mainMixer.outputVolume = volumeLevel
        
        // Load the SoundFont into the sampler
        loadSoundFont()
    }

    func setupMIDI() {
        // Create MIDI client with notification block
        MIDIClientCreateWithBlock("MIDI Client" as CFString, &midiClient) { [weak self] message in
            self?.handleMIDINotifyMessage(message)
        }
        
        // Create MIDI input port
        MIDIInputPortCreateWithBlock(midiClient, "Input Port" as CFString, &midiInputPort) { [weak self] packetList, _ in
            self?.handleMIDIPacketList(packetList)
        }
        
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
        print("Connected to \(sourceCount) MIDI source(s).")
    }

    func handleMIDINotifyMessage(_ message: UnsafePointer<MIDINotification>) {
        let messageID = message.pointee.messageID
        if messageID == .msgObjectAdded || messageID == .msgObjectRemoved {
            DispatchQueue.main.async {
                self.refreshMIDIDevices()
            }
        }
    }

    func handleMIDIPacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            let midiStatus = packet.data.0
            let midiCommand = midiStatus >> 4
            let channel = midiStatus & 0x0F
            if midiCommand == 0x9 || midiCommand == 0x8 { // Note On or Note Off
                let note = packet.data.1
                let velocity = packet.data.2
                DispatchQueue.main.async {
                    if midiCommand == 0x9 && velocity > 0 {
                        // Note On
                        self.sampler.startNote(note, withVelocity: velocity, onChannel: channel)
                    } else {
                        // Note Off
                        self.sampler.stopNote(note, onChannel: channel)
                    }
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    // MARK: - USB Device Notifications

    func setupUSBDeviceNotifications() {
        // Create matching dictionary for device addition
        guard let matchingDictAdd = IOServiceMatching(kIOUSBDeviceClassName) else { return }
        
        // Create matching dictionary for device removal
        guard let matchingDictRemove = IOServiceMatching(kIOUSBDeviceClassName) else { return }
        
        notifyPort = IONotificationPortCreate(kIOMasterPortDefault)
        guard let notifyPort = notifyPort else { return }
        
        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPort).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        
        let observerContext = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        // Device Added Callback
        let addCallback: IOServiceMatchingCallback = { (refcon, iterator) in
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
            appDelegate.deviceAdded(iterator: iterator)
        }
        
        // Device Removed Callback
        let removeCallback: IOServiceMatchingCallback = { (refcon, iterator) in
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
            appDelegate.deviceRemoved(iterator: iterator)
        }
        
        // Register for device addition
        let krAdd = IOServiceAddMatchingNotification(
            notifyPort,
            kIOMatchedNotification,
            matchingDictAdd,
            addCallback,
            observerContext,
            &addedIterator
        )
        if krAdd != KERN_SUCCESS {
            print("Failed to add matching notification for device addition: \(krAdd)")
        }
        // Iterate existing devices to arm the notification
        deviceAdded(iterator: addedIterator)
        
        // Register for device removal
        let krRemove = IOServiceAddMatchingNotification(
            notifyPort,
            kIOTerminatedNotification,
            matchingDictRemove,
            removeCallback,
            observerContext,
            &removedIterator
        )
        if krRemove != KERN_SUCCESS {
            print("Failed to add matching notification for device removal: \(krRemove)")
        }
        // Iterate existing devices to arm the notification
        deviceRemoved(iterator: removedIterator)
    }

    func deviceAdded(iterator: io_iterator_t) {
        while case let device = IOIteratorNext(iterator), device != 0 {
            // Device added
            print("USB Device Connected")
            IOObjectRelease(device)
        }
        // Refresh MIDI sources
        DispatchQueue.main.async {
            self.refreshMIDIDevices()
        }
    }

    func deviceRemoved(iterator: io_iterator_t) {
        while case let device = IOIteratorNext(iterator), device != 0 {
            // Device removed
            print("USB Device Disconnected")
            IOObjectRelease(device)
        }
        // Refresh MIDI sources
        DispatchQueue.main.async {
            self.refreshMIDIDevices()
        }
    }

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

    // MARK: - Volume Control

    @objc func increaseVolume() {
        volumeLevel = min(volumeLevel + volumeStep, 1.0)
        setVolume(volumeLevel)
        updateVolumeDisplay()
        print("Volume increased to \(volumeLevel)")
    }

    @objc func decreaseVolume() {
        volumeLevel = max(volumeLevel - volumeStep, 0.0)
        setVolume(volumeLevel)
        updateVolumeDisplay()
        print("Volume decreased to \(volumeLevel)")
    }

    func setVolume(_ volume: Float) {
        audioEngine.mainMixerNode.outputVolume = volume
    }

    func updateVolumeDisplay() {
        if let menu = statusItem.menu, let volumeItem = menu.item(at: 0) {
            volumeItem.title = "Volume: \(Int(volumeLevel * 100))%"
        }
    }

    // MARK: - Actions

    @objc func quitApplication() {
        NSApplication.shared.terminate(self)
    }

    @objc func refreshMIDIDevices() {
        // Dispose of existing MIDI resources
        MIDIPortDispose(midiInputPort)
        MIDIClientDispose(midiClient)
        
        // Re-initialize MIDI setup
        setupMIDI()
        print("MIDI devices refreshed.")
    }
}
