// Copyright 2009-2010 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import UIKit
import AVFoundation

/// Main application delegate for Mumble iOS.
@main
@objc(MUApplicationDelegate)
@objcMembers
class MUApplicationDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Properties

    var window: UIWindow?
    private var navigationController: UINavigationController?
    private var publistFetcher: MUPublicServerListFetcher?
    private var audioWasRunningBeforeInterruption: Bool = false
    private var audioSubsystemConfigured: Bool = false
    private let audioSessionQueue = DispatchQueue(label: "info.mumble.AppDelegate.AudioSession", qos: .userInitiated)

    // MARK: - UIApplicationDelegate

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        registerForAppLifecycleNotifications()

        // Reset application badge
        UIApplication.shared.applicationIconBadgeNumber = 0

        // Initialize the notification controller
        _ = MUNotificationController.shared

        // Try to fetch an updated public server list
        publistFetcher = MUPublicServerListFetcher()
        publistFetcher?.attemptUpdate()

        // Set MumbleKit release string
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        MKVersion.shared()?.setOverrideRelease("Mumble for iOS \(version)")

        // Enable Opus unconditionally
        MKVersion.shared()?.setOpusEnabled(true)

        // Register default settings
        UserDefaults.standard.register(defaults: [
            // Audio
            "AudioOutputVolume": 1.0,
            "AudioVADAbove": 0.6,
            "AudioVADBelow": 0.3,
            "AudioVADKind": "amplitude",
            "AudioTransmitMethod": "vad",
            "AudioPreprocessor": true,
            "AudioEchoCancel": true,
            "AudioMicBoost": 1.0,
            "AudioQualityKind": "balanced",
            "AudioSidetone": false,
            "AudioSidetoneVolume": 0.2,
            "AudioSpeakerPhoneMode": true,
            "AudioOpusCodecForceCELTMode": true,
            // Network
            "NetworkForceTCP": false,
            "DefaultUserName": "MumbleUser"
        ])

        // Disable mixer debugging for all builds
        UserDefaults.standard.set(false, forKey: "AudioMixerDebug")

        reloadPreferences()
        MUDatabase.initializeDatabase()

        registerForAudioSessionNotifications()

        #if ENABLE_REMOTE_CONTROL
        if UserDefaults.standard.bool(forKey: "RemoteControlServerEnabled") {
            MURemoteControlServer.shared.start()
        }
        #endif

        // Use dark keyboard throughout the app
        UITextField.appearance().keyboardAppearance = .dark

        window = UIWindow(frame: UIScreen.main.bounds)

        UINavigationBar.appearance().tintColor = .white
        UINavigationBar.appearance().isTranslucent = false
        UINavigationBar.appearance().barTintColor = .black
        UINavigationBar.appearance().backgroundColor = .black
        UINavigationBar.appearance().barStyle = .black

        // Add background view for prettier transitions
        let bgView = MUBackgroundView.backgroundView()
        window?.addSubview(bgView)

        // Add default navigation controller
        navigationController = UINavigationController()
        navigationController?.isToolbarHidden = true

        let welcomeScreen: UIViewController
        if UIDevice.current.userInterfaceIdiom == .pad {
            welcomeScreen = MUWelcomeScreenPad()
        } else {
            welcomeScreen = MUWelcomeScreenPhone()
        }
        navigationController?.pushViewController(welcomeScreen, animated: true)

        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()

        // Handle mumble:// URL on launch
        if let url = launchOptions?[.url] as? URL, url.scheme == "mumble" {
            let connController = MUConnectionController.shared()
            let hostname = url.host ?? ""
            let port = UInt(url.port ?? 64738)
            let username = url.user
            let password = url.password
            connController.connet(toHostname: hostname, port: port, withUsername: username, andPassword: password, withParentViewController: welcomeScreen)
            return true
        }

        return false
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard url.scheme == "mumble" else { return false }

        let connController = MUConnectionController.shared()
        if connController.isConnected() {
            return false
        }

        let hostname = url.host ?? ""
        let port = UInt(url.port ?? 64738)
        let username = url.user
        let password = url.password

        if let visibleVC = navigationController?.visibleViewController {
            connController.connet(toHostname: hostname, port: port, withUsername: username, andPassword: password, withParentViewController: visibleVC)
        }

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        MUDatabase.teardown()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        let audio = MKAudio.shared()
        let connController = MUConnectionController.shared()

        if !connController.isConnected() {
            NSLog("MumbleApplicationDelegate: Not connected to a server. Stopping MKAudio.")
            audio?.stop()
            MUAudioCaptureManager.shared.stop()

            NSLog("MumbleApplicationDelegate: Not connected to a server. Deactivating audio session.")
            deactivateAudioSession()

            #if ENABLE_REMOTE_CONTROL
            MURemoteControlServer.shared.stop()
            #endif
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        let connController = MUConnectionController.shared()

        // Re-check microphone permission - user may have enabled it in Settings
        let session = AVAudioSession.sharedInstance()
        if session.recordPermission == .granted && !audioSubsystemConfigured {
            // Permission granted but audio not configured (was denied at launch)
            NSLog("MumbleApplicationDelegate: Microphone permission now granted, configuring audio subsystem")
            setupAudio()
        } else if session.recordPermission == .granted {
            // Start audio on background queue to avoid blocking main thread.
            // AudioOutputUnitStart() can block for several seconds waiting on audio daemon.
            audioSessionQueue.async {
                if let audio = MKAudio.shared(), !audio.isRunning() {
                    NSLog("MumbleApplicationDelegate: MKAudio not running. Starting it.")
                    audio.start()
                }
                MUAudioCaptureManager.shared.start()
            }
        } else if session.recordPermission == .undetermined {
            // Permission not yet requested - request it now
            setupAudio()
        }

        if !connController.isConnected() && !AVAudioSession.sharedInstance().isOtherAudioPlaying {
            NSLog("MumbleApplicationDelegate: Reactivating audio session after foregrounding.")
            activateAudioSession()
            MUAudioSessionManager.shared.refreshPlaybackChain()

            #if ENABLE_REMOTE_CONTROL
            MURemoteControlServer.shared.stop()
            MURemoteControlServer.shared.start()
            #endif
        }
    }

    // MARK: - Audio Setup

    /// Requests microphone permission if not already granted.
    /// Shows an alert if permission is denied.
    private func requestMicrophonePermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        let session = AVAudioSession.sharedInstance()

        switch session.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            DispatchQueue.main.async { [weak self] in
                self?.showMicrophonePermissionDeniedAlert()
            }
            completion(false)
        case .undetermined:
            session.requestRecordPermission { granted in
                if !granted {
                    DispatchQueue.main.async { [weak self] in
                        self?.showMicrophonePermissionDeniedAlert()
                    }
                }
                completion(granted)
            }
        @unknown default:
            completion(false)
        }
    }

    private func showMicrophonePermissionDeniedAlert() {
        let title = NSLocalizedString("Microphone Access Required", comment: "Alert title for microphone permission")
        let message = NSLocalizedString("Mumble needs microphone access for voice chat. Please enable it in Settings.", comment: "Alert message for microphone permission")

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: ""), style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })

        navigationController?.present(alert, animated: true)
    }

    private func setupAudio() {
        // Request microphone permission before configuring audio
        requestMicrophonePermissionIfNeeded { [weak self] granted in
            guard granted else {
                NSLog("MUApplicationDelegate: Microphone permission not granted")
                return
            }

            self?.configureAudioSubsystem()
        }
    }

    private func configureAudioSubsystem() {
        let defaults = UserDefaults.standard

        // Mark audio as configured
        audioSubsystemConfigured = true

        // Configure AVAudioSession through the single authority (MUAudioSessionManager).
        // Previously, configureAudioSession(with:) was also called here, setting different
        // mode/options on a separate queue. This caused race conditions where the last
        // async dispatch to complete would win, potentially clobbering the correct
        // .playAndRecord + .voiceChat configuration with incompatible settings, causing
        // MKAudio's audio unit to lose microphone access.
        MUAudioSessionManager.shared.configureSession()
        MUAudioSessionManager.shared.applySavedPreferences()

        var settings = MKAudioSettings()

        // Transmit type
        let transmitMethod = defaults.string(forKey: "AudioTransmitMethod")
        switch transmitMethod {
        case "vad":
            settings.transmitType = MKTransmitTypeVAD
        case "continuous":
            settings.transmitType = MKTransmitTypeContinuous
        case "ptt":
            settings.transmitType = MKTransmitTypeToggle
        default:
            settings.transmitType = MKTransmitTypeVAD
        }

        // VAD kind
        let vadKind = defaults.string(forKey: "AudioVADKind")
        switch vadKind {
        case "snr":
            settings.vadKind = MKVADKindSignalToNoise
        default:
            settings.vadKind = MKVADKindAmplitude
        }

        settings.vadMin = defaults.float(forKey: "AudioVADBelow")
        settings.vadMax = defaults.float(forKey: "AudioVADAbove")

        // Quality settings
        let quality = defaults.string(forKey: "AudioQualityKind")
        switch quality {
        case "low":
            settings.codec = MKCodecFormatOpus
            settings.quality = 16000
            settings.audioPerPacket = 6
        case "balanced":
            settings.codec = MKCodecFormatOpus
            settings.quality = 40000
            settings.audioPerPacket = 2
        case "high", "opus":
            settings.codec = MKCodecFormatOpus
            settings.quality = 72000
            settings.audioPerPacket = 1
        default:
            settings.codec = MKCodecFormatCELT
            let codec = defaults.string(forKey: "AudioCodec")
            switch codec {
            case "opus":
                settings.codec = MKCodecFormatOpus
            case "celt":
                settings.codec = MKCodecFormatCELT
            case "speex":
                settings.codec = MKCodecFormatSpeex
            default:
                break
            }
            settings.quality = Int32(defaults.integer(forKey: "AudioQualityBitrate"))
            settings.audioPerPacket = Int32(defaults.integer(forKey: "AudioQualityFrames"))
        }

        settings.noiseSuppression = -42
        settings.amplification = 20.0
        settings.jitterBufferSize = 0
        settings.volume = defaults.float(forKey: "AudioOutputVolume")
        settings.outputDelay = 0
        settings.micBoost = defaults.float(forKey: "AudioMicBoost")
        let preprocessorEnabled = defaults.bool(forKey: "AudioPreprocessor")
        settings.enablePreprocessor = ObjCBool(preprocessorEnabled)
        settings.enableEchoCancellation = ObjCBool(preprocessorEnabled && defaults.bool(forKey: "AudioEchoCancel"))
        settings.enableSideTone = ObjCBool(defaults.bool(forKey: "AudioSidetone"))
        settings.sidetoneVolume = defaults.float(forKey: "AudioSidetoneVolume")
        settings.preferReceiverOverSpeaker = ObjCBool(!defaults.bool(forKey: "AudioSpeakerPhoneMode"))
        settings.opusForceCELTMode = ObjCBool(defaults.bool(forKey: "AudioOpusCodecForceCELTMode"))
        settings.audioMixerDebug = ObjCBool(defaults.bool(forKey: "AudioMixerDebug"))

        MUAudioCaptureManager.shared.configureFromDefaults()

        if let audio = MKAudio.shared() {
            MUAudioSessionManager.shared.bind(to: audio, defaults: defaults)
            audio.update(&settings)
        }
        MUAudioSessionManager.shared.refreshPlaybackChain()

        // Activate audio session
        activateAudioSession()

        // Start audio on background queue after configuration
        // This is needed because applicationDidBecomeActive may have already fired
        // before microphone permission was granted
        audioSessionQueue.async {
            if let audio = MKAudio.shared(), !audio.isRunning() {
                NSLog("MumbleApplicationDelegate: Starting MKAudio after configuration")
                audio.start()
            }
            MUAudioCaptureManager.shared.start()
        }
    }

    @objc func reloadPreferences() {
        setupAudio()
    }

    // MARK: - Audio Session Configuration

    private func activateAudioSession() {
        audioSessionQueue.async {
            do {
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                NSLog("MUApplicationDelegate: Failed to activate audio session: %@", error.localizedDescription)
            }
        }
    }

    private func deactivateAudioSession() {
        audioSessionQueue.async {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                NSLog("MUApplicationDelegate: Failed to deactivate audio session: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Notifications

    private func registerForAppLifecycleNotifications() {
        let center = NotificationCenter.default

        center.addObserver(self, selector: #selector(handleApplicationActivation(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(handleApplicationActivation(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)

        if #available(iOS 13.0, *) {
            center.addObserver(self, selector: #selector(handleApplicationActivation(_:)), name: UIScene.willEnterForegroundNotification, object: nil)
            center.addObserver(self, selector: #selector(handleApplicationActivation(_:)), name: UIScene.didActivateNotification, object: nil)
        }
    }

    private func registerForAudioSessionNotifications() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        center.addObserver(self, selector: #selector(handleAudioInterruption(_:)), name: AVAudioSession.interruptionNotification, object: session)
        center.addObserver(self, selector: #selector(handleAudioRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: session)
    }

    @objc private func handleApplicationActivation(_ notification: Notification) {
        activateAudioSessionIfNeeded()

        // Start audio on background queue to avoid blocking main thread
        audioSessionQueue.async {
            if let audio = MKAudio.shared(), !audio.isRunning() {
                audio.start()
            }
        }
    }

    private func activateAudioSessionIfNeeded() {
        audioSessionQueue.async {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                NSLog("MUApplicationDelegate: Failed to activate AVAudioSession: %@", error.localizedDescription)
            }
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            audioWasRunningBeforeInterruption = MKAudio.shared()?.isRunning() ?? false
            if audioWasRunningBeforeInterruption {
                MKAudio.shared()?.stop()
            }
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    activateAudioSessionIfNeeded()
                    // Capture value before async to avoid race condition
                    let shouldRestart = audioWasRunningBeforeInterruption
                    audioSessionQueue.async {
                        if shouldRestart {
                            MKAudio.shared()?.start()
                        }
                    }
                }
            }
            audioWasRunningBeforeInterruption = false
        @unknown default:
            break
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .categoryChange, .override, .wakeFromSleep:
            MUAudioSessionManager.shared.handleRouteChange(reasonValue: reasonValue, defaults: UserDefaults.standard)
        default:
            break
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
