// Copyright 2009-2011 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import UIKit

/// Root navigation controller for the connected server view.
/// Contains a segmented control to switch between Server view and Messages view.
/// Handles connection lifecycle events and user actions while connected.
@objc(MUServerRootViewController)
@objcMembers
class MUServerRootViewController: UINavigationController, MKConnectionDelegate, MKServerModelDelegate {

    // MARK: - Private Properties

    private var connection: MKConnection
    private var model: MKServerModel

    private var segmentIndex: Int = 0
    private var segmentedControl: UISegmentedControl!
    private var menuButton: UIBarButtonItem!
    private var smallIcon: UIBarButtonItem!
    private var modeSwitchButton: UIButton!
    private var numberBadgeView: MKNumberBadgeView!

    private var serverView: MUServerViewController!
    private var messagesView: MUMessagesViewController!

    private var unreadMessages: Int = 0

    // MARK: - Initialization

    @objc(initWithConnection:andServerModel:)
    init(connection: MKConnection, andServerModel model: MKServerModel) {
        self.connection = connection
        self.model = model
        super.init(nibName: nil, bundle: nil)
        self.model.addDelegate(self)

        unreadMessages = 0

        serverView = MUServerViewController(serverModel: model)
        messagesView = MUMessagesViewController(serverModel: model)

        numberBadgeView = MKNumberBadgeView(frame: .zero)
        numberBadgeView.shadow = false
        numberBadgeView.font = UIFont.boldSystemFont(ofSize: 11.0)
        numberBadgeView.isHidden = true
        numberBadgeView.shine = false
        numberBadgeView.strokeColor = .red
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        model.removeDelegate(self)
        connection.setDelegate(nil)
    }

    @objc func takeOwnershipOfConnectionDelegate() {
        connection.setDelegate(self)
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        segmentedControl = UISegmentedControl(items: [
            NSLocalizedString("Server", comment: ""),
            NSLocalizedString("Messages", comment: "")
        ])

        segmentIndex = 0
        segmentedControl.selectedSegmentIndex = segmentIndex
        segmentedControl.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)

        menuButton = UIBarButtonItem(
            image: UIImage(named: "MumbleMenuButton"),
            style: .plain,
            target: self,
            action: #selector(actionButtonClicked(_:))
        )
        serverView.navigationItem.rightBarButtonItem = menuButton

        let button = UIButton(type: .custom)
        button.frame = CGRect(x: 0, y: 0, width: 35, height: 30)
        button.setBackgroundImage(UIImage(named: "SmallMumbleIcon"), for: .normal)
        button.adjustsImageWhenDisabled = false
        button.isEnabled = true
        button.addTarget(self, action: #selector(modeSwitchButtonReleased(_:)), for: .touchUpInside)
        smallIcon = UIBarButtonItem(customView: button)
        modeSwitchButton = button
        serverView.navigationItem.leftBarButtonItem = smallIcon

        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: segmentedControl.frame.width, height: 30))
        containerView.addSubview(segmentedControl)
        containerView.addSubview(numberBadgeView)
        numberBadgeView.frame = CGRect(x: segmentedControl.frame.width - 24, y: -10, width: 50, height: 30)
        numberBadgeView.value = UInt(unreadMessages)
        numberBadgeView.isHidden = unreadMessages == 0

        serverView.navigationItem.titleView = containerView

        setViewControllers([serverView], animated: false)

        toolbar.barStyle = .blackOpaque
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    // MARK: - Segment Control

    @objc private func segmentChanged(_ sender: Any) {
        if segmentedControl.selectedSegmentIndex == 0 { // Server view
            serverView.navigationItem.titleView = segmentedControl.superview
            serverView.navigationItem.leftBarButtonItem = smallIcon
            serverView.navigationItem.rightBarButtonItem = menuButton
            setViewControllers([serverView], animated: false)
            modeSwitchButton.isEnabled = true
        } else if segmentedControl.selectedSegmentIndex == 1 { // Messages view
            messagesView.navigationItem.titleView = segmentedControl.superview
            messagesView.navigationItem.leftBarButtonItem = smallIcon
            messagesView.navigationItem.rightBarButtonItem = menuButton
            setViewControllers([messagesView], animated: false)
            modeSwitchButton.isEnabled = false
        }

        if segmentedControl.selectedSegmentIndex == 1 { // Messages view
            unreadMessages = 0
            numberBadgeView.value = 0
            numberBadgeView.isHidden = true
            UIApplication.shared.applicationIconBadgeNumber = 0
        } else if numberBadgeView.value > 0 {
            numberBadgeView.isHidden = false
        }

        segmentedControl.perform(#selector(UIView.bringSubviewToFront(_:)), with: numberBadgeView, afterDelay: 0.0)

        MUAudioCaptureManager.shared.endPushToTalk()
        MKAudio.shared()?.setForceTransmit(false)
    }

    // MARK: - MKConnectionDelegate

    func connectionOpened(_ conn: MKConnection) {
    }

    @objc(connection:rejectedWithReason:explanation:)
    func connection(_ conn: MKConnection!, rejectedWith reason: MKRejectReason, explanation: String!) {
    }

    func connection(_ conn: MKConnection, trustFailureInCertificateChain chain: [Any]) {
    }

    func connection(_ conn: MKConnection, unableToConnectWithError err: Error) {
    }

    func connection(_ conn: MKConnection, closedWithError err: Error?) {
        if let error = err {
            let alertCtrl = UIAlertController(
                title: NSLocalizedString("Connection closed", comment: ""),
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alertCtrl.addAction(UIAlertAction(
                title: NSLocalizedString("OK", comment: ""),
                style: .cancel
            ))
            present(alertCtrl, animated: true)
            MUConnectionController.shared().disconnectFromServer()
        }
    }

    // MARK: - MKServerModelDelegate
    // Note: All delegate methods dispatch to main thread since MKServerModel
    // callbacks may be invoked from background threads (network layer).

    @objc(serverModel:userKicked:byUser:forReason:)
    func serverModel(_ model: MKServerModel, userKicked user: MKUser, by actor: MKUser?, forReason reason: String?) {
        guard user == model.connectedUser() else { return }

        DispatchQueue.main.async { [weak self] in
            let reasonMsg = reason ?? NSLocalizedString("(No reason)", comment: "")
            let title = NSLocalizedString("You were kicked", comment: "")
            let alertMsg = String(
                format: NSLocalizedString("Kicked by %@ for reason: \"%@\"", comment: "Kicked by user for reason"),
                actor?.userName() ?? "", reasonMsg
            )

            let alertCtrl = UIAlertController(title: title, message: alertMsg, preferredStyle: .alert)
            alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
            self?.present(alertCtrl, animated: true)

            MUConnectionController.shared().disconnectFromServer()
        }
    }

    @objc(serverModel:userBanned:byUser:forReason:)
    func serverModel(_ model: MKServerModel, userBanned user: MKUser, by actor: MKUser?, forReason reason: String?) {
        guard user == model.connectedUser() else { return }

        DispatchQueue.main.async { [weak self] in
            let reasonMsg = reason ?? NSLocalizedString("(No reason)", comment: "")
            let title = NSLocalizedString("You were banned", comment: "")
            let alertMsg = String(
                format: NSLocalizedString("Banned by %@ for reason: \"%@\"", comment: ""),
                actor?.userName() ?? "", reasonMsg
            )

            let alertCtrl = UIAlertController(title: title, message: alertMsg, preferredStyle: .alert)
            alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
            self?.present(alertCtrl, animated: true)

            MUConnectionController.shared().disconnectFromServer()
        }
    }

    @objc(serverModel:permissionDenied:forUser:inChannel:)
    func serverModel(_ model: MKServerModel!, permissionDenied perm: MKPermission, for user: MKUser!, in channel: MKChannel!) {
        DispatchQueue.main.async {
            MUNotificationController.shared.addNotification(NSLocalizedString("Permission denied", comment: ""))
        }
    }

    func serverModelInvalidChannelNameError(_ model: MKServerModel) {
        DispatchQueue.main.async {
            MUNotificationController.shared.addNotification(NSLocalizedString("Invalid channel name", comment: ""))
        }
    }

    func serverModelModifySuperUserError(_ model: MKServerModel) {
        DispatchQueue.main.async {
            MUNotificationController.shared.addNotification(NSLocalizedString("Cannot modify SuperUser", comment: ""))
        }
    }

    func serverModelTextMessageTooLongError(_ model: MKServerModel) {
        DispatchQueue.main.async {
            MUNotificationController.shared.addNotification(NSLocalizedString("Message too long", comment: ""))
        }
    }

    func serverModelTemporaryChannelError(_ model: MKServerModel) {
        DispatchQueue.main.async {
            MUNotificationController.shared.addNotification(NSLocalizedString("Not permitted in temporary channel", comment: ""))
        }
    }

    @objc(serverModel:missingCertificateErrorForUser:)
    func serverModel(_ model: MKServerModel!, missingCertificateErrorFor user: MKUser!) {
        DispatchQueue.main.async {
            if user == nil {
                MUNotificationController.shared.addNotification(NSLocalizedString("Missing certificate", comment: ""))
            } else {
                MUNotificationController.shared.addNotification(NSLocalizedString("Missing certificate for user", comment: ""))
            }
        }
    }

    func serverModel(_ model: MKServerModel, invalidUsernameErrorForName name: String?) {
        DispatchQueue.main.async {
            if let name = name {
                MUNotificationController.shared.addNotification("Invalid username: \(name)")
            } else {
                MUNotificationController.shared.addNotification("Invalid username")
            }
        }
    }

    func serverModelChannelFullError(_ model: MKServerModel) {
        DispatchQueue.main.async {
            MUNotificationController.shared.addNotification(NSLocalizedString("Channel is full", comment: ""))
        }
    }

    func serverModel(_ model: MKServerModel, permissionDeniedForReason reason: String?) {
        DispatchQueue.main.async {
            if let reason = reason {
                MUNotificationController.shared.addNotification(String(
                    format: NSLocalizedString("Permission denied: %@", comment: "Permission denied with reason"),
                    reason
                ))
            } else {
                MUNotificationController.shared.addNotification(NSLocalizedString("Permission denied", comment: ""))
            }
        }
    }

    @objc(serverModel:textMessageReceived:fromUser:)
    func serverModel(_ model: MKServerModel, textMessageReceived msg: MKTextMessage, from user: MKUser?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.segmentedControl.selectedSegmentIndex != 1 { // When not in messages view
                self.unreadMessages += 1
                self.numberBadgeView.value = UInt(self.unreadMessages)
                self.numberBadgeView.isHidden = false
            }
        }
    }

    // MARK: - Actions

    @objc private func actionButtonClicked(_ sender: Any) {
        let connUser = model.connectedUser()
        let inMessagesView = viewControllers.first === messagesView

        let sheetCtrl = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        sheetCtrl.addAction(UIAlertAction(
            title: NSLocalizedString("Disconnect", comment: ""),
            style: .destructive
        ) { _ in
            MUConnectionController.shared().disconnectFromServer()
        })

        if UserDefaults.standard.bool(forKey: "AudioMixerDebug") {
            sheetCtrl.addAction(UIAlertAction(
                title: NSLocalizedString("Mixer Debug", comment: ""),
                style: .default
            ) { [weak self] _ in
                let audioMixerDebugVC = MUAudioMixerDebugViewController()
                let navCtrl = UINavigationController(rootViewController: audioMixerDebugVC)
                self?.present(navCtrl, animated: true)
            })
        }

        sheetCtrl.addAction(UIAlertAction(
            title: NSLocalizedString("Access Tokens", comment: ""),
            style: .default
        ) { [weak self] _ in
            guard let self = self else { return }
            let tokenVC = MUAccessTokenViewController(serverModel: self.model)
            let navCtrl = UINavigationController(rootViewController: tokenVC)
            self.present(navCtrl, animated: true)
        })

        if !inMessagesView {
            sheetCtrl.addAction(UIAlertAction(
                title: NSLocalizedString("Certificates", comment: ""),
                style: .default
            ) { [weak self] _ in
                guard let self = self else { return }
                if let certs = self.model.serverCertificates() as? [MKCertificate] {
                    let certView = MUCertificateViewController(certificates: certs)
                    let navCtrl = UINavigationController(rootViewController: certView)
                    let doneButton = UIBarButtonItem(
                        barButtonSystemItem: .done,
                        target: self,
                        action: #selector(self.childDoneButton(_:))
                    )
                    certView.navigationItem.leftBarButtonItem = doneButton
                    self.present(navCtrl, animated: true)
                }
            })
        }

        if let connUser = connUser, !connUser.isAuthenticated() {
            sheetCtrl.addAction(UIAlertAction(
                title: NSLocalizedString("Self-Register", comment: ""),
                style: .default
            ) { [weak self, connUser] _ in
                guard let self = self else { return }

                let title = NSLocalizedString("User Registration", comment: "")
                let msg = String(
                    format: NSLocalizedString(
                        "You are about to register yourself on this server. " +
                        "This cannot be undone, and your username cannot be changed once this is done. " +
                        "You will forever be known as '%@' on this server.\n\n" +
                        "Are you sure you want to register yourself?",
                        comment: "Self-registration with given username"
                    ),
                    connUser.userName() ?? ""
                )

                let alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("No", comment: ""), style: .cancel))
                alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("Yes", comment: ""), style: .default) { _ in
                    self.model.registerConnectedUser()
                })
                self.present(alertCtrl, animated: true)
            })
        }

        if inMessagesView {
            sheetCtrl.addAction(UIAlertAction(
                title: NSLocalizedString("Clear Messages", comment: ""),
                style: .default
            ) { _ in
                // Clear messages implementation
            })
        }

        if let connUser = connUser {
            if connUser.isSelfMuted() && connUser.isSelfDeafened() {
                sheetCtrl.addAction(UIAlertAction(
                    title: NSLocalizedString("Unmute and undeafen", comment: ""),
                    style: .default
                ) { [weak self] _ in
                    self?.model.setSelfMuted(false, andSelfDeafened: false)
                })
            } else {
                let muteHandler: (UIAlertAction) -> Void = { [weak self] _ in
                    guard let self = self, let connUser = self.model.connectedUser() else { return }
                    self.model.setSelfMuted(!connUser.isSelfMuted(), andSelfDeafened: connUser.isSelfDeafened())
                }
                let deafenHandler: (UIAlertAction) -> Void = { [weak self] _ in
                    guard let self = self, let connUser = self.model.connectedUser() else { return }
                    self.model.setSelfMuted(connUser.isSelfMuted(), andSelfDeafened: !connUser.isSelfDeafened())
                }

                if !connUser.isSelfMuted() {
                    sheetCtrl.addAction(UIAlertAction(title: NSLocalizedString("Self-Mute", comment: ""), style: .default, handler: muteHandler))
                } else {
                    sheetCtrl.addAction(UIAlertAction(title: NSLocalizedString("Unmute Self", comment: ""), style: .default, handler: muteHandler))
                }

                if !connUser.isSelfDeafened() {
                    sheetCtrl.addAction(UIAlertAction(title: NSLocalizedString("Self-Deafen", comment: ""), style: .default, handler: deafenHandler))
                } else {
                    sheetCtrl.addAction(UIAlertAction(title: NSLocalizedString("Undeafen Self", comment: ""), style: .default, handler: deafenHandler))
                }
            }
        }

        sheetCtrl.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: ""),
            style: .cancel
        ))

        present(sheetCtrl, animated: true)
    }

    @objc private func childDoneButton(_ sender: Any) {
        presentedViewController?.dismiss(animated: true)
    }

    @objc private func modeSwitchButtonReleased(_ sender: Any) {
        serverView.toggleMode()
    }
}
