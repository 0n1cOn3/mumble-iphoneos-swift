// Copyright 2024 The 'Mumble for iOS' Developers.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import Foundation
import AVFoundation

/// Transmit mode for audio capture.
@objc enum MUTransmitMode: Int {
    case continuous = 0
    case pushToTalk
    case vad
}

/// Notification posted when audio metering updates.
let MUAudioCaptureManagerMeterUpdateNotification = NSNotification.Name("MUAudioCaptureManagerMeterUpdate")

/// Centralized capture pipeline built on AVAudioEngine/AVAudioRecorder.
@objc(MUAudioCaptureManager)
@objcMembers
class MUAudioCaptureManager: NSObject {

    // MARK: - Constants

    private static let minimumMeterPowerDb: Float = -96.0

    // MARK: - Singleton

    @objc static let shared = MUAudioCaptureManager()

    /// Alias for shared (Obj-C compatibility)
    @objc class func sharedManager() -> MUAudioCaptureManager {
        return shared
    }

    // MARK: - Public Properties

    @objc private(set) var transmitMode: MUTransmitMode = .vad
    @objc private(set) var vadMin: Float = 0.0
    @objc private(set) var vadMax: Float = 1.0
    @objc private(set) var meterLevel: Float = 0.0
    @objc private(set) var speechProbability: Float = 0.0
    @objc private(set) var transmitting: Bool = false

    // MARK: - Private Properties

    private var engine: AVAudioEngine
    private var recorder: AVAudioRecorder?
    private var tapInstalled: Bool = false
    private var meteringHandler: (() -> Void)?
    private let audioSessionQueue = DispatchQueue(label: "info.mumble.AudioSessionQueue", qos: .userInitiated)

    // MARK: - Initialization

    private override init() {
        engine = AVAudioEngine()
        super.init()
    }

    // MARK: - Configuration

    /// Applies defaults for transmit mode, thresholds, and encoder quality.
    @objc func configureFromDefaults() {
        refreshTransmitMode()
        refreshVADThresholds()
        refreshEncoderPreferences()
    }

    /// Updates only the transmit mode from defaults.
    @objc func refreshTransmitMode() {
        let method = UserDefaults.standard.string(forKey: "AudioTransmitMethod")
        switch method {
        case "continuous":
            transmitMode = .continuous
        case "ptt":
            transmitMode = .pushToTalk
        default:
            transmitMode = .vad
        }
    }

    /// Updates only the VAD thresholds from defaults.
    @objc func refreshVADThresholds() {
        let defaults = UserDefaults.standard
        vadMin = defaults.float(forKey: "AudioVADBelow")
        vadMax = defaults.float(forKey: "AudioVADAbove")
    }

    /// Refreshes encoder/format hints from defaults and prepares the metering recorder.
    ///
    /// NOTE: This method intentionally does NOT configure AVAudioSession.
    /// Audio session configuration is the sole responsibility of MUAudioSessionManager
    /// to avoid race conditions where multiple components set conflicting session
    /// categories/modes on different queues, causing MKAudio's audio unit to lose
    /// microphone access.
    @objc func refreshEncoderPreferences() {
        let defaults = UserDefaults.standard
        let quality = defaults.string(forKey: "AudioQualityKind")

        // Use actual sample rates (not bitrates) for the metering recorder
        let sampleRate: Double
        switch quality {
        case "low":
            sampleRate = 16000.0
        default:
            sampleRate = 48000.0
        }

        audioSessionQueue.async { [weak self] in
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatAppleLossless),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            do {
                let newRecorder = try AVAudioRecorder(url: URL(fileURLWithPath: "/dev/null"), settings: settings)
                newRecorder.isMeteringEnabled = true
                newRecorder.prepareToRecord()
                self?.recorder = newRecorder
            } catch {
                NSLog("MUAudioCaptureManager: failed to create recorder: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Engine Lifecycle

    /// Starts the audio engine/recorder backing the capture pipeline.
    @objc func start() {
        installTapIfNeeded()

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                NSLog("MUAudioCaptureManager: failed to start engine: %@", error.localizedDescription)
            }
        }

        if transmitMode == .continuous {
            transmitting = true
        }

        if transmitMode == .pushToTalk, let recorder = recorder {
            recorder.record()
        }
    }

    /// Stops the audio engine/recorder backing the capture pipeline.
    @objc func stop() {
        if tapInstalled {
            // Use safe removal to avoid potential exceptions
            _ = ObjCExceptionCatcher.safelyRemoveTap(onNode: engine.inputNode, bus: 0)
            tapInstalled = false
        }

        engine.stop()

        if let recorder = recorder, recorder.isRecording {
            recorder.stop()
        }

        transmitting = false
    }

    // MARK: - Push-to-Talk

    /// Begin push-to-talk transmission.
    @objc func beginPushToTalk() {
        guard transmitMode == .pushToTalk else { return }

        transmitting = true

        if let recorder = recorder, !recorder.isRecording {
            recorder.record()
        }
    }

    /// End push-to-talk transmission.
    @objc func endPushToTalk() {
        guard transmitMode == .pushToTalk else { return }

        transmitting = false

        if let recorder = recorder, recorder.isRecording {
            recorder.stop()
        }
    }

    // MARK: - Metering

    /// Allows UI components to receive metering callbacks on the main thread.
    @objc func setMeteringHandler(_ handler: (() -> Void)?) {
        meteringHandler = handler
    }

    private func installTapIfNeeded() {
        guard !tapInstalled else { return }

        // Check microphone permission first
        let session = AVAudioSession.sharedInstance()
        guard session.recordPermission == .granted else {
            NSLog("MUAudioCaptureManager: Microphone permission not granted, skipping tap installation")
            return
        }

        // Accessing inputNode can throw NSException if audio session isn't properly configured
        var input: AVAudioInputNode?
        let inputError = ObjCExceptionCatcher.try {
            input = self.engine.inputNode
        }

        guard inputError == nil, let input = input else {
            NSLog("MUAudioCaptureManager: Failed to get input node: %@", inputError ?? "unknown error")
            return
        }

        // Use the input node's native output format to avoid format mismatch exceptions.
        // Passing a custom format that doesn't match hardware capabilities causes a crash.
        let format = input.outputFormat(forBus: 0)

        // Verify the format is valid (channels > 0) before installing tap
        guard format.channelCount > 0 else {
            NSLog("MUAudioCaptureManager: Invalid input format (0 channels), skipping tap installation")
            return
        }

        // Safely remove any existing tap first to avoid "tap already exists" exception
        let removeError = ObjCExceptionCatcher.safelyRemoveTap(onNode: input, bus: 0)
        if let removeError = removeError {
            NSLog("MUAudioCaptureManager: Note - remove tap returned: %@", removeError)
        }

        // Use the safe Objective-C method to install the tap.
        // This ensures exceptions are caught properly - Swift closures don't support
        // ObjC exception unwinding, causing crashes when exceptions are thrown.
        let installError = ObjCExceptionCatcher.safelyInstallTap(
            onNode: input,
            bus: 0,
            bufferSize: 1024,
            format: format
        ) { [weak self] buffer, _ in
            if let pcmBuffer = buffer as? AVAudioPCMBuffer {
                self?.processBuffer(pcmBuffer)
            }
        }

        if installError == nil {
            tapInstalled = true
        } else {
            NSLog("MUAudioCaptureManager: Failed to install tap: %@", installError ?? "unknown error")
        }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameLength = buffer.frameLength
        guard frameLength > 0 else { return }

        guard let data = buffer.floatChannelData?[0] else { return }

        var sum: Float = 0.0
        for i in 0..<Int(frameLength) {
            sum += data[i] * data[i]
        }

        let rms = sqrtf(sum / Float(frameLength))
        var powerDb = 20.0 * log10f(rms)

        if !powerDb.isFinite {
            powerDb = MUAudioCaptureManager.minimumMeterPowerDb
        }

        var normalizedPower = (powerDb - MUAudioCaptureManager.minimumMeterPowerDb) / abs(MUAudioCaptureManager.minimumMeterPowerDb)
        normalizedPower = max(0.0, min(1.0, normalizedPower))

        meterLevel = normalizedPower

        if transmitMode == .vad {
            var probability: Float = 0.0
            if vadMax > vadMin {
                probability = (normalizedPower - vadMin) / (vadMax - vadMin)
                probability = max(0.0, min(1.0, probability))
            }
            speechProbability = probability

            let shouldTransmit = normalizedPower >= vadMax
            let shouldStop = normalizedPower <= vadMin

            if shouldTransmit {
                transmitting = true
            } else if shouldStop {
                transmitting = false
            }
        } else if transmitMode == .continuous {
            transmitting = true
        }

        if let handler = meteringHandler {
            DispatchQueue.main.async(execute: handler)
        }

        NotificationCenter.default.post(name: MUAudioCaptureManagerMeterUpdateNotification, object: self)
    }
}
