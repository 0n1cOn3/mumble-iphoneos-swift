import XCTest
import AVFoundation
@testable import Mumble

#if __has_include(<MumbleKit/MKAudio.h>)
import MumbleKit
#else
// Minimal stubs to allow the tests to compile in environments where
// the real MumbleKit headers are not available (such as CI runners).
@objc class MKAudio: NSObject {
    private static let _shared = MKAudio()

    @objc static func sharedAudio() -> MKAudio {
        return _shared
    }

    @objc private(set) var running: Bool = false

    @objc func isRunning() -> Bool {
        return running
    }

    @objc func start() {
        running = true
    }

    @objc func stop() {
        running = false
    }

    @objc func restart() {
        stop()
        start()
    }
}
#endif

class MUAudioSessionManagerTests: XCTestCase {
    var sessionManager: MUAudioSessionManager!
    var mockDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        sessionManager = MUAudioSessionManager.shared
        mockDefaults = UserDefaults(suiteName: "MUAudioSessionManagerTests")!
        mockDefaults.removePersistentDomain(forName: "MUAudioSessionManagerTests")

        // Reset to known defaults so tests don't leak state
        sessionManager.updateTransmitMethod(withString: nil)
        sessionManager.updateCodecQualityPreset(nil)
        sessionManager.updateVADThresholds(lower: 0.3, upper: 0.6)
    }

    override func tearDown() {
        mockDefaults.removePersistentDomain(forName: "MUAudioSessionManagerTests")
        super.tearDown()
    }

    // MARK: - updateTransmitMethod Tests

    func testTransmitMethodDefaultsToVAD() {
        let result = sessionManager.updateTransmitMethod(withString: nil)

        XCTAssertEqual(result, "vad")
        XCTAssertEqual(sessionManager.transmitMode, .voiceActivity)
    }

    func testTransmitMethodSetsPTT() {
        let result = sessionManager.updateTransmitMethod(withString: "ptt")

        XCTAssertEqual(result, "ptt")
        XCTAssertEqual(sessionManager.transmitMode, .pushToTalk)
    }

    func testTransmitMethodSetsContinuous() {
        let result = sessionManager.updateTransmitMethod(withString: "continuous")

        XCTAssertEqual(result, "continuous")
        XCTAssertEqual(sessionManager.transmitMode, .continuous)
    }

    func testTransmitMethodSetsVADExplicitly() {
        let result = sessionManager.updateTransmitMethod(withString: "vad")

        XCTAssertEqual(result, "vad")
        XCTAssertEqual(sessionManager.transmitMode, .voiceActivity)
    }

    func testTransmitMethodIsCaseInsensitive() {
        XCTAssertEqual(sessionManager.updateTransmitMethod(withString: "PTT"), "ptt")
        XCTAssertEqual(sessionManager.transmitMode, .pushToTalk)

        XCTAssertEqual(sessionManager.updateTransmitMethod(withString: "Continuous"), "continuous")
        XCTAssertEqual(sessionManager.transmitMode, .continuous)
    }

    func testTransmitMethodFallsBackToVADForGarbage() {
        let result = sessionManager.updateTransmitMethod(withString: "banana")

        XCTAssertEqual(result, "vad")
        XCTAssertEqual(sessionManager.transmitMode, .voiceActivity)
    }

    func testTransmitMethodPersistsToUserDefaults() {
        sessionManager.updateTransmitMethod(withString: "ptt")

        let stored = UserDefaults.standard.string(forKey: "AudioTransmitMethod")
        XCTAssertEqual(stored, "ptt")
    }

    // MARK: - updateVADKind Tests

    func testVADKindDefaultsToAmplitude() {
        let result = sessionManager.updateVADKind(withString: nil)

        XCTAssertEqual(result, "amplitude")
    }

    func testVADKindSetsSNR() {
        let result = sessionManager.updateVADKind(withString: "snr")

        XCTAssertEqual(result, "snr")
    }

    func testVADKindSetsAmplitudeExplicitly() {
        let result = sessionManager.updateVADKind(withString: "amplitude")

        XCTAssertEqual(result, "amplitude")
    }

    func testVADKindIsCaseInsensitive() {
        XCTAssertEqual(sessionManager.updateVADKind(withString: "SNR"), "snr")
    }

    func testVADKindFallsBackForGarbage() {
        XCTAssertEqual(sessionManager.updateVADKind(withString: "xyz"), "amplitude")
    }

    func testVADKindPersistsToUserDefaults() {
        sessionManager.updateVADKind(withString: "snr")

        let stored = UserDefaults.standard.string(forKey: "AudioVADKind")
        XCTAssertEqual(stored, "snr")
    }

    // MARK: - updateVADThresholds Tests

    func testVADThresholdsSetCorrectly() {
        let result = sessionManager.updateVADThresholds(lower: 0.2, upper: 0.8)

        XCTAssertEqual(result["lower"] as? Float, 0.2)
        XCTAssertEqual(result["upper"] as? Float, 0.8)
        XCTAssertEqual(sessionManager.vadLowerThreshold, 0.2)
        XCTAssertEqual(sessionManager.vadUpperThreshold, 0.8)
    }

    func testVADThresholdsClampsNegativeValues() {
        let result = sessionManager.updateVADThresholds(lower: -0.5, upper: 0.5)

        XCTAssertEqual(result["lower"] as? Float, 0.0)
        XCTAssertEqual(sessionManager.vadLowerThreshold, 0.0)
    }

    func testVADThresholdsClampsOverOneValues() {
        let result = sessionManager.updateVADThresholds(lower: 0.5, upper: 1.5)

        XCTAssertEqual(result["upper"] as? Float, 1.0)
        XCTAssertEqual(sessionManager.vadUpperThreshold, 1.0)
    }

    func testVADThresholdsEnforcesUpperAtLeastEqualToLower() {
        // Upper is less than lower — should be forced to match lower
        let result = sessionManager.updateVADThresholds(lower: 0.7, upper: 0.3)

        XCTAssertEqual(result["lower"] as? Float, 0.7)
        XCTAssertEqual(result["upper"] as? Float, 0.7)
        XCTAssertEqual(sessionManager.vadLowerThreshold, 0.7)
        XCTAssertEqual(sessionManager.vadUpperThreshold, 0.7)
    }

    func testVADThresholdsHandlesExactBoundaries() {
        let result = sessionManager.updateVADThresholds(lower: 0.0, upper: 1.0)

        XCTAssertEqual(result["lower"] as? Float, 0.0)
        XCTAssertEqual(result["upper"] as? Float, 1.0)
    }

    func testVADThresholdsHandlesEqualValues() {
        let result = sessionManager.updateVADThresholds(lower: 0.5, upper: 0.5)

        XCTAssertEqual(result["lower"] as? Float, 0.5)
        XCTAssertEqual(result["upper"] as? Float, 0.5)
    }

    func testVADThresholdsHandlesNaN() {
        // NaN should clamp to lowerBound (0.0) via the isFinite guard
        let result = sessionManager.updateVADThresholds(lower: Float.nan, upper: 0.5)

        XCTAssertEqual(result["lower"] as? Float, 0.0)
        XCTAssertEqual(sessionManager.vadLowerThreshold, 0.0)
    }

    func testVADThresholdsHandlesInfinity() {
        let result = sessionManager.updateVADThresholds(lower: 0.3, upper: Float.infinity)

        // Infinity is not finite, so clamp returns lowerBound (0.0),
        // but max(infinity, 0.3) = infinity first, then clamp catches it
        XCTAssertEqual(result["upper"] as? Float, 0.0)
        XCTAssertEqual(sessionManager.vadUpperThreshold, 0.0)
    }

    func testVADThresholdsPersistsToUserDefaults() {
        sessionManager.updateVADThresholds(lower: 0.25, upper: 0.75)

        let storedLower = UserDefaults.standard.float(forKey: "AudioVADBelow")
        let storedUpper = UserDefaults.standard.float(forKey: "AudioVADAbove")
        XCTAssertEqual(storedLower, 0.25)
        XCTAssertEqual(storedUpper, 0.75)
    }

    // MARK: - updateCodecQualityPreset Tests

    func testCodecQualityDefaultsToBalanced() {
        let result = sessionManager.updateCodecQualityPreset(nil)

        XCTAssertEqual(result, "balanced")
        XCTAssertEqual(sessionManager.codecQuality, .balanced)
    }

    func testCodecQualitySetsLow() {
        let result = sessionManager.updateCodecQualityPreset("low")

        XCTAssertEqual(result, "low")
        XCTAssertEqual(sessionManager.codecQuality, .low)
    }

    func testCodecQualitySetsHigh() {
        let result = sessionManager.updateCodecQualityPreset("high")

        XCTAssertEqual(result, "high")
        XCTAssertEqual(sessionManager.codecQuality, .high)
    }

    func testCodecQualitySetsBalancedExplicitly() {
        let result = sessionManager.updateCodecQualityPreset("balanced")

        XCTAssertEqual(result, "balanced")
        XCTAssertEqual(sessionManager.codecQuality, .balanced)
    }

    func testCodecQualityAcceptsOpusAsHigh() {
        // "opus" is an alias for high quality
        let result = sessionManager.updateCodecQualityPreset("opus")

        XCTAssertEqual(result, "high")
        XCTAssertEqual(sessionManager.codecQuality, .high)
    }

    func testCodecQualitySetsCustom() {
        let result = sessionManager.updateCodecQualityPreset("custom")

        XCTAssertEqual(result, "custom")
        XCTAssertEqual(sessionManager.codecQuality, .custom)
    }

    func testCodecQualityIsCaseInsensitive() {
        XCTAssertEqual(sessionManager.updateCodecQualityPreset("LOW"), "low")
        XCTAssertEqual(sessionManager.codecQuality, .low)

        XCTAssertEqual(sessionManager.updateCodecQualityPreset("HIGH"), "high")
        XCTAssertEqual(sessionManager.codecQuality, .high)
    }

    func testCodecQualityFallsBackForGarbage() {
        let result = sessionManager.updateCodecQualityPreset("garbage")

        XCTAssertEqual(result, "balanced")
        XCTAssertEqual(sessionManager.codecQuality, .balanced)
    }

    func testCodecQualityPersistsToUserDefaults() {
        sessionManager.updateCodecQualityPreset("high")

        let stored = UserDefaults.standard.string(forKey: "AudioQualityKind")
        XCTAssertEqual(stored, "high")
    }

    // MARK: - Recorder Settings Tests

    func testRecorderSettingsSetForLowPreset() {
        sessionManager.updateCodecQualityPreset("low")

        let settings = sessionManager.recorderSettings
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 16000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(settings[AVLinearPCMBitDepthKey] as? Int, 16)
        XCTAssertEqual(settings[AVLinearPCMIsFloatKey] as? Bool, false)
    }

    func testRecorderSettingsSetForBalancedPreset() {
        sessionManager.updateCodecQualityPreset("balanced")

        let settings = sessionManager.recorderSettings
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 48000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
    }

    func testRecorderSettingsSetForHighPreset() {
        sessionManager.updateCodecQualityPreset("high")

        let settings = sessionManager.recorderSettings
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 48000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
    }

    func testRecorderSettingsAlwaysMono() {
        for preset in ["low", "balanced", "high"] {
            sessionManager.updateCodecQualityPreset(preset)
            XCTAssertEqual(sessionManager.recorderSettings[AVNumberOfChannelsKey] as? Int, 1,
                           "Preset '\(preset)' should be mono")
        }
    }

    func testRecorderSettingsAlwaysLinearPCM() {
        for preset in ["low", "balanced", "high"] {
            sessionManager.updateCodecQualityPreset(preset)
            XCTAssertEqual(sessionManager.recorderSettings[AVFormatIDKey] as? UInt32,
                           kAudioFormatLinearPCM,
                           "Preset '\(preset)' should use LinearPCM")
        }
    }

    // MARK: - State Transition Tests

    func testTransmitModeTransitions() {
        // Start at VAD (default)
        XCTAssertEqual(sessionManager.transmitMode, .voiceActivity)

        // Move to PTT
        sessionManager.updateTransmitMethod(withString: "ptt")
        XCTAssertEqual(sessionManager.transmitMode, .pushToTalk)

        // Move to continuous
        sessionManager.updateTransmitMethod(withString: "continuous")
        XCTAssertEqual(sessionManager.transmitMode, .continuous)

        // Back to VAD
        sessionManager.updateTransmitMethod(withString: "vad")
        XCTAssertEqual(sessionManager.transmitMode, .voiceActivity)
    }

    func testCodecQualityTransitions() {
        XCTAssertEqual(sessionManager.codecQuality, .balanced)

        sessionManager.updateCodecQualityPreset("low")
        XCTAssertEqual(sessionManager.codecQuality, .low)

        sessionManager.updateCodecQualityPreset("high")
        XCTAssertEqual(sessionManager.codecQuality, .high)

        // Recorder settings should reflect the latest preset
        XCTAssertEqual(sessionManager.recorderSettings[AVSampleRateKey] as? Double, 48000)
    }

    // MARK: - AVAudioSession Smoke Tests
    // These methods interact with AVAudioSession on a background queue.
    // Without mocking, we verify they don't crash.

    func testConfigureSessionDoesNotCrash() {
        sessionManager.configureSession(activate: true)
        sessionManager.configureSession(activate: false)
        sessionManager.configureSession()
    }

    func testBindDoesNotCrash() {
        let audio = MKAudio.sharedAudio()
        sessionManager.bind(to: audio, defaults: mockDefaults)
    }

    func testRefreshPlaybackChainDoesNotCrash() {
        let audio = MKAudio.sharedAudio()
        sessionManager.bind(to: audio, defaults: mockDefaults)
        sessionManager.refreshPlaybackChain()
    }

    func testHandleRouteChangeDoesNotCrash() {
        let audio = MKAudio.sharedAudio()
        sessionManager.bind(to: audio, defaults: mockDefaults)

        let reasons: [AVAudioSession.RouteChangeReason] = [
            .newDeviceAvailable,
            .oldDeviceUnavailable,
            .categoryChange,
            .override,
            .unknown,
        ]

        for reason in reasons {
            sessionManager.handleRouteChange(reasonValue: reason.rawValue, defaults: mockDefaults)
        }
    }
}
