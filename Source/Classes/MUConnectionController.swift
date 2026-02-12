// Copyright 2009-2011 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import UIKit

/// Notification posted when a connection is opened
let MUConnectionOpenedNotification = "MUConnectionOpenedNotification"

/// Notification posted when a connection is closed
let MUConnectionClosedNotification = "MUConnectionClosedNotification"

/// Manages the connection lifecycle to Mumble servers.
/// Singleton controller that handles connection establishment, authentication,
/// certificate trust, and connection rejection scenarios.
@objc(MUConnectionController)
@objcMembers
class MUConnectionController: UIView, MKConnectionDelegate, MKServerModelDelegate, MUServerCertificateTrustViewControllerProtocol {

    // MARK: - Singleton

    private static var sharedInstance: MUConnectionController?

    @objc static func shared() -> MUConnectionController {
        if sharedInstance == nil {
            NSLog("MUConnectionController: Creating singleton instance (Swift version)")
            sharedInstance = MUConnectionController()
        }
        return sharedInstance!
    }

    // MARK: - Private Properties

    private var connection: MKConnection?
    private var serverModel: MKServerModel?
    private var serverRoot: MUServerRootViewController?
    private weak var parentViewController: UIViewController?
    private var alertCtrl: UIAlertController?
    private var timer: Timer?
    private var numDots: Int = 0

    private var rejectAlertCtrl: UIAlertController?
    private var rejectReason: MKRejectReason = MKRejectReasonNone

    private var hostname: String?
    private var port: UInt = 0
    private var username: String?
    private var password: String?

    private var transitioningDelegate: Any?

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTransitioningDelegate()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTransitioningDelegate()
    }

    private convenience init() {
        self.init(frame: .zero)
    }

    private func setupTransitioningDelegate() {
        if #available(iOS 7.0, *) {
            transitioningDelegate = MUHorizontalFlipTransitionDelegate()
        }
    }

    // MARK: - Public Methods

    @objc(connetToHostname:port:withUsername:andPassword:withParentViewController:)
    func connet(
        toHostname hostName: String?,
        port: UInt,
        withUsername userName: String?,
        andPassword password: String?,
        withParentViewController parentViewController: UIViewController?
    ) {
        NSLog("MUConnectionController: connet called - host=%@, port=%lu, user=%@", hostName ?? "nil", port, userName ?? "nil")
        self.hostname = hostName
        self.port = port
        self.username = userName
        self.password = password
        self.parentViewController = parentViewController

        showConnectingView()
        establishConnection()
    }

    @objc func isConnected() -> Bool {
        return connection != nil
    }

    @objc func disconnectFromServer() {
        serverRoot?.dismiss(animated: true)
        teardownConnection()
    }

    // MARK: - Connection Management

    private func showConnectingView() {
        NSLog("MUConnectionController: showConnectingView called, parentVC=%@", String(describing: parentViewController))
        let title = "\(NSLocalizedString("Connecting", comment: ""))..."
        let msg = String(
            format: NSLocalizedString("Connecting to %@:%lu", comment: "Connecting to hostname:port"),
            hostname ?? "", port
        )

        let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: ""),
            style: .cancel
        ) { [weak self] _ in
            NSLog("MUConnectionController: Cancel button pressed")
            self?.teardownConnection()
        })
        alertCtrl = alert

        if let pvc = parentViewController {
            NSLog("MUConnectionController: Presenting connecting alert on %@", String(describing: pvc))
            pvc.present(alert, animated: true) {
                NSLog("MUConnectionController: Connecting alert presented successfully")
            }
        } else {
            NSLog("MUConnectionController: ERROR - parentViewController is nil!")
        }

        timer = Timer.scheduledTimer(
            timeInterval: 0.2,
            target: self,
            selector: #selector(updateTitle),
            userInfo: nil,
            repeats: true
        )
    }

    private func hideConnectingView() {
        hideConnectingView(completion: nil)
    }

    private func hideConnectingView(completion: (() -> Void)?) {
        NSLog("MUConnectionController: hideConnectingView called, alertCtrl=%@", alertCtrl != nil ? "exists" : "nil")
        timer?.invalidate()
        timer = nil

        if alertCtrl != nil {
            NSLog("MUConnectionController: Dismissing connecting alert")
            parentViewController?.dismiss(animated: true) {
                NSLog("MUConnectionController: Connecting alert dismissed")
                completion?()
            }
            alertCtrl = nil
        } else {
            NSLog("MUConnectionController: No alert to dismiss")
            completion?()
        }
    }

    private func establishConnection() {
        NSLog("MUConnectionController: establishConnection called")
        connection = MKConnection()
        connection?.setDelegate(self)
        connection?.setForceTCP(UserDefaults.standard.bool(forKey: "NetworkForceTCP"))

        serverModel = MKServerModel(connection: connection)
        serverModel?.addDelegate(self)

        if let connection = connection, let serverModel = serverModel {
            serverRoot = MUServerRootViewController(connection: connection, andServerModel: serverModel)
        }

        // Set the connection's client cert if one is set in the app's preferences
        if let certPersistentId = UserDefaults.standard.object(forKey: "DefaultCertificate") as? Data {
            NSLog("MUConnectionController: Found certificate, building chain")
            if let certChain = MUCertificateChainBuilder.buildChain(fromPersistentRef: certPersistentId) {
                NSLog("MUConnectionController: Certificate chain built with %lu items", certChain.count)
                connection?.setCertificateChain(certChain)
            } else {
                NSLog("MUConnectionController: Failed to build certificate chain")
            }
        } else {
            NSLog("MUConnectionController: No certificate configured")
        }

        NSLog("MUConnectionController: Calling connect to %@:%lu", hostname ?? "nil", port)
        connection?.connect(toHost: hostname, port: port)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name(MUConnectionOpenedNotification), object: nil)
        }
    }

    private func teardownConnection() {
        serverModel?.removeDelegate(self)
        serverModel = nil
        connection?.setDelegate(nil)
        connection?.disconnect()
        connection = nil
        timer?.invalidate()
        serverRoot = nil

        // Reset app badge. The connection is no more.
        UIApplication.shared.applicationIconBadgeNumber = 0

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name(MUConnectionClosedNotification), object: nil)
        }
    }

    @objc private func updateTitle() {
        numDots += 1
        if numDots > 3 {
            numDots = 0
        }

        var dots = "   "
        switch numDots {
        case 1: dots = ".  "
        case 2: dots = ".. "
        case 3: dots = "..."
        default: dots = "   "
        }

        alertCtrl?.title = "\(NSLocalizedString("Connecting", comment: ""))\(dots)"
    }

    // MARK: - MKConnectionDelegate

    func connectionOpened(_ conn: MKConnection) {
        NSLog("MUConnectionController: connectionOpened delegate called")
        var tokens: [String]? = nil
        if let hostname = conn.hostname() {
            tokens = MUDatabase.accessTokensForServer(withHostname: hostname, port: Int(conn.port())) as? [String]
        }
        conn.authenticate(withUsername: username, password: password, accessTokens: tokens)
    }

    func connection(_ conn: MKConnection, closedWithError err: Error?) {
        NSLog("MUConnectionController: closedWithError delegate called - error=%@", err?.localizedDescription ?? "nil")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hideConnectingView()

            let title = NSLocalizedString("Connection closed", comment: "")
            let message: String
            if let error = err {
                message = error.localizedDescription
            } else {
                message = NSLocalizedString("The connection was closed unexpectedly.", comment: "")
            }

            let alertCtrl = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertCtrl.addAction(UIAlertAction(
                title: NSLocalizedString("OK", comment: ""),
                style: .cancel
            ))
            self.parentViewController?.present(alertCtrl, animated: true)
            self.teardownConnection()
        }
    }

    func connection(_ conn: MKConnection, unableToConnectWithError err: Error) {
        NSLog("MUConnectionController: unableToConnectWithError delegate called - error=%@", err.localizedDescription)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hideConnectingView()

            var msg = err.localizedDescription

            // errSSLClosedAbort: "connection closed via error".
            // This is the error we get when users hit a global ban on the server.
            let nsError = err as NSError
            if nsError.domain == NSOSStatusErrorDomain && nsError.code == -9806 {
                msg = NSLocalizedString(
                    "The TLS connection was closed due to an error.\n\n" +
                    "The server might be temporarily rejecting your connection because you have " +
                    "attempted to connect too many times in a row.",
                    comment: ""
                )
            }

            let alertCtrl = UIAlertController(
                title: NSLocalizedString("Unable to connect", comment: ""),
                message: msg,
                preferredStyle: .alert
            )
            alertCtrl.addAction(UIAlertAction(
                title: NSLocalizedString("OK", comment: ""),
                style: .cancel
            ))
            self.parentViewController?.present(alertCtrl, animated: true)
            self.teardownConnection()
        }
    }

    func connection(_ conn: MKConnection, trustFailureInCertificateChain chain: [Any]) {
        NSLog("MUConnectionController: trustFailureInCertificateChain delegate called - chain count=%lu", chain.count)
        // Check the database whether the user trusts the leaf certificate of this server.
        var storedDigest: String? = nil
        if let hostname = conn.hostname() {
            storedDigest = MUDatabase.digestForServer(withHostname: hostname, port: Int(conn.port()))
            NSLog("MUConnectionController: Stored digest for %@:%d = %@", hostname, conn.port(), storedDigest ?? "nil")
        }
        let cert = conn.peerCertificates()?.first as? MKCertificate
        let serverDigest = cert?.hexDigest()
        NSLog("MUConnectionController: Server certificate digest = %@", serverDigest ?? "nil")

        if let storedDigest = storedDigest, storedDigest == serverDigest {
            // Match - auto-reconnect with SSL verification disabled (no UIKit needed)
            NSLog("MUConnectionController: Certificate digest matches stored, auto-reconnecting")
            conn.setIgnoreSSLVerification(true)
            conn.reconnect()
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let cancelHandler: (UIAlertAction) -> Void = { [weak self] _ in
                self?.teardownConnection()
            }
            let ignoreHandler: (UIAlertAction) -> Void = { [weak self] _ in
                self?.connection?.setIgnoreSSLVerification(true)
                self?.connection?.reconnect()
                self?.showConnectingView()
            }
            let trustHandler: (UIAlertAction) -> Void = { [weak self] _ in
                guard let self = self else { return }
                if let cert = self.connection?.peerCertificates()?.first as? MKCertificate,
                   let digest = cert.hexDigest(),
                   let hostname = self.connection?.hostname() {
                    MUDatabase.storeDigest(digest, forServerWithHostname: hostname, port: Int(self.connection?.port() ?? 0))
                }
                self.connection?.setIgnoreSSLVerification(true)
                self.connection?.reconnect()
                self.showConnectingView()
            }
            let showCertsHandler: (UIAlertAction) -> Void = { [weak self] _ in
                guard let self = self else { return }
                if let certs = self.connection?.peerCertificates() as? [MKCertificate] {
                    let certTrustView = MUServerCertificateTrustViewController(certificates: certs)
                    certTrustView.delegate = self
                    let navCtrl = UINavigationController(rootViewController: certTrustView)
                    self.parentViewController?.present(navCtrl, animated: true)
                }
            }

            if storedDigest != nil {
                // Mismatch - server is using a new certificate
                NSLog("MUConnectionController: Certificate MISMATCH - showing alert")
                self.hideConnectingView()

                let title = NSLocalizedString("Certificate Mismatch", comment: "")
                let msg = NSLocalizedString("The server presented a different certificate than the one stored for this server", comment: "")

                let alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: cancelHandler))
                alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("Ignore", comment: ""), style: .default, handler: ignoreHandler))
                alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("Trust New Certificate", comment: ""), style: .default, handler: trustHandler))
                alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("Show Certificates", comment: ""), style: .default, handler: showCertsHandler))

                self.parentViewController?.present(alertCtrl, animated: true)
            } else {
                // No cert hash in database for this hostname-port combo
                NSLog("MUConnectionController: No stored certificate digest - showing trust dialog")
                self.hideConnectingView()

                let title = NSLocalizedString("Unable to validate server certificate", comment: "")
                let msg = NSLocalizedString("Mumble was unable to validate the certificate chain of the server.", comment: "")

                let alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: cancelHandler))
                alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("Ignore", comment: ""), style: .default, handler: ignoreHandler))
                alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("Trust Certificate", comment: ""), style: .default, handler: trustHandler))
                alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("Show Certificates", comment: ""), style: .default, handler: showCertsHandler))

                NSLog("MUConnectionController: Presenting certificate trust alert")
                self.parentViewController?.present(alertCtrl, animated: true)
            }
        }
    }

    @objc(connection:rejectedWithReason:explanation:)
    func connection(_ conn: MKConnection!, rejectedWith reason: MKRejectReason, explanation: String!) {
        NSLog("MUConnectionController: rejectedWith delegate called - reason=%d, explanation=%@", reason.rawValue, explanation ?? "nil")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hideConnectingView()
            self.teardownConnection()

            let title = NSLocalizedString("Connection Rejected", comment: "")
            var msg: String?
            var alertCtrl: UIAlertController?

            let cancelHandler: (UIAlertAction) -> Void = { [weak self] _ in
                guard let self = self else { return }
                if self.rejectReason == MKRejectReasonInvalidUsername || self.rejectReason == MKRejectReasonUsernameInUse {
                    self.username = self.rejectAlertCtrl?.textFields?.first?.text
                } else if self.rejectReason == MKRejectReasonWrongServerPassword || self.rejectReason == MKRejectReasonWrongUserPassword {
                    self.password = self.rejectAlertCtrl?.textFields?.first?.text
                }
            }
            let reconnectHandler: (UIAlertAction) -> Void = { [weak self] _ in
                guard let self = self else { return }
                if self.rejectReason == MKRejectReasonInvalidUsername || self.rejectReason == MKRejectReasonUsernameInUse {
                    self.username = self.rejectAlertCtrl?.textFields?.first?.text
                } else if self.rejectReason == MKRejectReasonWrongServerPassword || self.rejectReason == MKRejectReasonWrongUserPassword {
                    self.password = self.rejectAlertCtrl?.textFields?.first?.text
                }
                self.establishConnection()
                self.showConnectingView()
            }
            let usernameConfigHandler: (UITextField) -> Void = { [weak self] textField in
                textField.text = self?.username
            }
            let passwordConfigHandler: (UITextField) -> Void = { [weak self] textField in
                textField.isSecureTextEntry = true
                textField.text = self?.password
            }

            switch reason {
            case MKRejectReasonNone:
                msg = NSLocalizedString("No reason", comment: "")
                alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: cancelHandler))

            case MKRejectReasonWrongVersion:
                msg = "Client/server version mismatch"
                alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: cancelHandler))

            case MKRejectReasonInvalidUsername:
                msg = NSLocalizedString("Invalid username", comment: "")
                alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alertCtrl?.addTextField(configurationHandler: usernameConfigHandler)
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: cancelHandler))
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("Reconnect", comment: ""), style: .default, handler: reconnectHandler))

            case MKRejectReasonWrongUserPassword:
                msg = NSLocalizedString("Wrong certificate or password for existing user", comment: "")
                alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alertCtrl?.addTextField(configurationHandler: passwordConfigHandler)
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: cancelHandler))
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("Reconnect", comment: ""), style: .default, handler: reconnectHandler))

            case MKRejectReasonWrongServerPassword:
                msg = NSLocalizedString("Wrong server password", comment: "")
                alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alertCtrl?.addTextField(configurationHandler: passwordConfigHandler)
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: cancelHandler))
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("Reconnect", comment: ""), style: .default, handler: reconnectHandler))

            case MKRejectReasonUsernameInUse:
                msg = NSLocalizedString("Username already in use", comment: "")
                alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alertCtrl?.addTextField(configurationHandler: usernameConfigHandler)
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: cancelHandler))
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("Reconnect", comment: ""), style: .default, handler: reconnectHandler))

            case MKRejectReasonServerIsFull:
                msg = NSLocalizedString("Server is full", comment: "")
                alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: cancelHandler))

            case MKRejectReasonNoCertificate:
                msg = NSLocalizedString("A certificate is needed to connect to this server", comment: "")
                alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: cancelHandler))

            default:
                msg = NSLocalizedString("Unknown rejection reason", comment: "")
                alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alertCtrl?.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: cancelHandler))
            }

            self.rejectAlertCtrl = alertCtrl
            self.rejectReason = reason

            if let alertCtrl = alertCtrl {
                self.parentViewController?.present(alertCtrl, animated: true)
            }
        }
    }

    // MARK: - MKServerModelDelegate

    @objc(serverModel:joinedServerAsUser:)
    func serverModel(_ model: MKServerModel, joinedServerAs user: MKUser) {
        NSLog("MUConnectionController: joinedServerAs delegate called - user=%@", user.userName() ?? "nil")
        if let username = user.userName(), let hostname = model.hostname() {
            MUDatabase.storeUsername(username, forServerWithHostname: hostname, port: model.port())
        }

        // Start the audio engine now that we've joined the server.
        // Without this, MKAudio (voice to server) and MUAudioCaptureManager
        // (local metering) remain idle until an unrelated OS event triggers them.
        MUAudioSessionManager.shared.startAudioEngine()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hideConnectingView { [weak self] in
                guard let self = self else { return }
                guard let serverRoot = self.serverRoot else { return }

                serverRoot.takeOwnershipOfConnectionDelegate()

                self.username = nil
                self.hostname = nil
                self.password = nil

                serverRoot.modalPresentationStyle = .fullScreen
                self.parentViewController?.navigationController?.present(serverRoot, animated: true)
                self.parentViewController = nil
            }
        }
    }

    // MARK: - MUServerCertificateTrustViewControllerProtocol

    func serverCertificateTrustViewControllerDidDismiss(_ trustView: MUServerCertificateTrustViewController) {
        showConnectingView()
        connection?.reconnect()
    }
}
