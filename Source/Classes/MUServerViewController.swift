// Copyright 2009-2010 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import UIKit

/// View modes for the server view controller
@objc enum MUServerViewControllerViewMode: Int {
    case server = 0
    case channel = 1
}

/// Helper class representing an item in the channel navigation tree
private class MUChannelNavigationItem {
    let object: AnyObject
    let indentLevel: Int

    init(object: AnyObject, indentLevel: Int) {
        self.object = object
        self.indentLevel = indentLevel
    }

    static func navigationItem(with object: AnyObject, indentLevel: Int) -> MUChannelNavigationItem {
        return MUChannelNavigationItem(object: object, indentLevel: indentLevel)
    }
}

/// Displays the server's channel/user tree or current channel's user list.
/// Supports Push-to-Talk and switching between server and channel view modes.
@objc(MUServerViewController)
@objcMembers
class MUServerViewController: UITableViewController, MKServerModelDelegate {

    // MARK: - Private Properties

    private var viewMode: MUServerViewControllerViewMode = .server
    private var serverModel: MKServerModel
    private var modelItems: [MUChannelNavigationItem] = []
    private var userIndexMap: [Int: Int] = [:]
    private var channelIndexMap: [Int: Int] = [:]
    private var pttState: Bool = false
    private var talkButton: UIButton?

    // MARK: - Initialization

    @objc(initWithServerModel:)
    init(serverModel: MKServerModel) {
        self.serverModel = serverModel
        super.init(style: .plain)
        self.serverModel.addDelegate(self)
        viewMode = .server
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        serverModel.removeDelegate(self)
    }

    // MARK: - View Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if #available(iOS 7.0, *) {
            tableView.separatorStyle = .singleLine
            tableView.separatorInset = .zero
        }

        if viewMode == .server {
            if let rootChannel = serverModel.rootChannel() {
                rebuildModelArray(from: rootChannel)
            }
            tableView.reloadData()
        } else if viewMode == .channel {
            switchToChannelMode()
            tableView.reloadData()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if MKAudio.shared()?.transmitType() == MKTransmitTypeToggle {
            guard let onImage = UIImage(named: "talkbutton_on"),
                  let offImage = UIImage(named: "talkbutton_off") else { return }

            guard let window = UIApplication.shared.windows.first else { return }
            let windowRect = window.frame
            let buttonRect = CGRect(
                x: (windowRect.width - onImage.size.width) / 2,
                y: windowRect.height - (onImage.size.height + 40),
                width: onImage.size.width,
                height: onImage.size.height
            )

            let button = UIButton(type: .custom)
            button.frame = buttonRect
            button.setBackgroundImage(onImage, for: .highlighted)
            button.setBackgroundImage(offImage, for: .normal)
            button.isOpaque = false
            button.alpha = 0.80
            window.addSubview(button)
            talkButton = button

            button.addTarget(self, action: #selector(talkOn(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(talkOff(_:)), for: [.touchUpInside, .touchUpOutside])

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(repositionTalkButton),
                name: UIApplication.didChangeStatusBarOrientationNotification,
                object: nil
            )
            repositionTalkButton()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appDidEnterBackground(_:)),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if let talkButton = talkButton {
            talkButton.removeFromSuperview()
            self.talkButton = nil
        }

        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Index Lookup

    private func index(for user: MKUser) -> Int {
        let session = user.session()
        return userIndexMap[Int(session)] ?? NSNotFound
    }

    private func index(for channel: MKChannel) -> Int {
        return channelIndexMap[Int(channel.channelId())] ?? NSNotFound
    }

    private func reloadUser(_ user: MKUser) {
        let userIndex = index(for: user)
        if userIndex != NSNotFound {
            tableView.reloadRows(at: [IndexPath(row: userIndex, section: 0)], with: .none)
        }
    }

    private func reloadChannel(_ channel: MKChannel) {
        let idx = index(for: channel)
        if idx != NSNotFound {
            tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .none)
        }
    }

    // MARK: - Model Building

    private func rebuildModelArray(from channel: MKChannel) {
        modelItems = []
        userIndexMap = [:]
        channelIndexMap = [:]
        addChannelTree(toModel: channel, indentLevel: 0)
    }

    private func switchToServerMode() {
        viewMode = .server
        if let rootChannel = serverModel.rootChannel() {
            rebuildModelArray(from: rootChannel)
        }
    }

    private func switchToChannelMode() {
        viewMode = .channel
        modelItems = []
        userIndexMap = [:]
        channelIndexMap = [:]

        guard let channel = serverModel.connectedUser()?.channel() else { return }
        for user in channel.users() {
            guard let mkUser = user as? MKUser else { continue }
            let session = mkUser.session()
            userIndexMap[Int(session)] = modelItems.count
            modelItems.append(MUChannelNavigationItem.navigationItem(with: mkUser, indentLevel: 0))
        }
    }

    private func addChannelTree(toModel channel: MKChannel, indentLevel: Int) {
        channelIndexMap[Int(channel.channelId())] = modelItems.count
        modelItems.append(MUChannelNavigationItem.navigationItem(with: channel, indentLevel: indentLevel))

        for user in channel.users() {
            guard let mkUser = user as? MKUser else { continue }
            let session = mkUser.session()
            userIndexMap[Int(session)] = modelItems.count
            modelItems.append(MUChannelNavigationItem.navigationItem(with: mkUser, indentLevel: indentLevel + 1))
        }

        for chan in channel.channels() {
            guard let mkChannel = chan as? MKChannel else { continue }
            addChannelTree(toModel: mkChannel, indentLevel: indentLevel + 1)
        }
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return modelItems.count
    }

    override func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        let navItem = modelItems[indexPath.row]
        if let channel = navItem.object as? MKChannel {
            if channel === serverModel.rootChannel() && serverModel.serverCertificatesTrusted() {
                cell.backgroundColor = MUColor.verifiedCertificateChainColor()
            }
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "ChannelNavigationCell"
        var cell = tableView.dequeueReusableCell(withIdentifier: identifier)
        if cell == nil {
            if #available(iOS 7.0, *) {
                cell = MUServerTableViewCell(reuseIdentifier: identifier)
            } else {
                cell = UITableViewCell(style: .default, reuseIdentifier: identifier)
            }
        }

        let navItem = modelItems[indexPath.row]
        let object = navItem.object
        let connectedUser = serverModel.connectedUser()

        cell?.textLabel?.font = UIFont.systemFont(ofSize: 18)

        if let channel = object as? MKChannel {
            cell?.imageView?.image = UIImage(named: "channel")
            cell?.textLabel?.text = channel.channelName()
            if channel === connectedUser?.channel() {
                cell?.textLabel?.font = UIFont.boldSystemFont(ofSize: 18)
            }
            cell?.accessoryView = nil
            cell?.selectionStyle = .default

        } else if let user = object as? MKUser {
            cell?.textLabel?.text = user.userName()
            if user === connectedUser {
                cell?.textLabel?.font = UIFont.boldSystemFont(ofSize: 18)
            }

            var talkImageName = "talking_off"
            let talkState = user.talkState()
            switch talkState {
            case MKTalkStatePassive:
                talkImageName = "talking_off"
            case MKTalkStateTalking:
                talkImageName = "talking_on"
            case MKTalkStateWhispering:
                talkImageName = "talking_whisper"
            case MKTalkStateShouting:
                talkImageName = "talking_alt"
            default:
                talkImageName = "talking_off"
            }

            // Check if the user should be shown as not talking when PTT is released
            if user === connectedUser && MKAudio.shared()?.transmitType() == MKTransmitTypeToggle {
                if MKAudio.shared()?.forceTransmit() == false {
                    talkImageName = "talking_off"
                }
            }

            cell?.imageView?.image = UIImage(named: talkImageName)
            cell?.accessoryView = MUUserStateAcessoryView.view(forUser: user)
            cell?.selectionStyle = .none
        }

        cell?.indentationLevel = navItem.indentLevel

        return cell ?? UITableViewCell()
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let navItem = modelItems[indexPath.row]
        if let channel = navItem.object as? MKChannel {
            serverModel.join(channel)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44.0
    }

    // MARK: - MKServerModelDelegate
    // Note: All delegate methods dispatch to main thread since MKServerModel
    // callbacks may be invoked from background threads (network layer).

    @objc(serverModel:joinedServerAsUser:)
    func serverModel(_ model: MKServerModel, joinedServerAs user: MKUser) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let rootChannel = model.rootChannel() {
                self.rebuildModelArray(from: rootChannel)
            }
            self.tableView.reloadData()
        }
    }

    func serverModel(_ model: MKServerModel, userJoined user: MKUser) {
    }

    func serverModel(_ model: MKServerModel, userDisconnected user: MKUser) {
    }

    func serverModel(_ model: MKServerModel, userLeft user: MKUser) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let idx = self.index(for: user)
            if idx != NSNotFound {
                if self.viewMode == .server {
                    if let rootChannel = model.rootChannel() {
                        self.rebuildModelArray(from: rootChannel)
                    }
                } else {
                    self.switchToChannelMode()
                }
                self.tableView.deleteRows(at: [IndexPath(row: idx, section: 0)], with: .none)
            }
        }
    }

    func serverModel(_ model: MKServerModel, userTalkStateChanged user: MKUser) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let userIndex = self.index(for: user)
            if userIndex == NSNotFound { return }

            guard let cell = self.tableView.cellForRow(at: IndexPath(row: userIndex, section: 0)) else { return }

            var talkImageName = "talking_off"
            let talkState = user.talkState()
            switch talkState {
            case MKTalkStatePassive:
                talkImageName = "talking_off"
            case MKTalkStateTalking:
                talkImageName = "talking_on"
            case MKTalkStateWhispering:
                talkImageName = "talking_whisper"
            case MKTalkStateShouting:
                talkImageName = "talking_alt"
            default:
                talkImageName = "talking_off"
            }

            cell.imageView?.image = UIImage(named: talkImageName)
        }
    }

    func serverModel(_ model: MKServerModel, channelAdded channel: MKChannel) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.viewMode == .server {
                if let rootChannel = model.rootChannel() {
                    self.rebuildModelArray(from: rootChannel)
                }
                let idx = self.index(for: channel)
                self.tableView.insertRows(at: [IndexPath(row: idx, section: 0)], with: .none)
            }
        }
    }

    func serverModel(_ model: MKServerModel, channelRemoved channel: MKChannel) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.viewMode == .server {
                if let rootChannel = model.rootChannel() {
                    self.rebuildModelArray(from: rootChannel)
                }
                self.tableView.reloadData()
            } else if self.viewMode == .channel {
                self.switchToChannelMode()
                self.tableView.reloadData()
            }
        }
    }

    func serverModel(_ model: MKServerModel, channelMoved channel: MKChannel) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.viewMode == .server {
                if let rootChannel = model.rootChannel() {
                    self.rebuildModelArray(from: rootChannel)
                }
                self.tableView.reloadData()
            }
        }
    }

    func serverModel(_ model: MKServerModel, channelRenamed channel: MKChannel) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.viewMode == .server {
                self.reloadChannel(channel)
            }
        }
    }

    @objc(serverModel:userMoved:toChannel:fromChannel:byUser:)
    func serverModel(
        _ model: MKServerModel,
        userMoved user: MKUser,
        to chan: MKChannel,
        from prevChan: MKChannel?,
        by mover: MKUser?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.viewMode == .server {
                self.tableView.beginUpdates()
                if user === model.connectedUser() {
                    self.reloadChannel(chan)
                    if let prevChan = prevChan {
                        self.reloadChannel(prevChan)
                    }
                }

                if prevChan != nil {
                    let prevIdx = self.index(for: user)
                    if prevIdx != NSNotFound {
                        self.tableView.deleteRows(at: [IndexPath(row: prevIdx, section: 0)], with: .none)
                    }
                }

                if let rootChannel = model.rootChannel() {
                    self.rebuildModelArray(from: rootChannel)
                }
                let newIdx = self.index(for: user)
                if newIdx != NSNotFound {
                    self.tableView.insertRows(at: [IndexPath(row: newIdx, section: 0)], with: .none)
                }
                self.tableView.endUpdates()

            } else if self.viewMode == .channel {
                let userIdx = self.index(for: user)
                let curChan = model.connectedUser()?.channel()

                if user === model.connectedUser() {
                    self.switchToChannelMode()
                    self.tableView.reloadData()
                } else {
                    self.tableView.beginUpdates()
                    if prevChan === curChan && userIdx != NSNotFound {
                        self.switchToChannelMode()
                        self.tableView.deleteRows(at: [IndexPath(row: userIdx, section: 0)], with: .none)
                    } else if chan === curChan && userIdx == NSNotFound {
                        self.switchToChannelMode()
                        let newUserIdx = self.index(for: user)
                        if newUserIdx != NSNotFound {
                            self.tableView.insertRows(at: [IndexPath(row: newUserIdx, section: 0)], with: .none)
                        }
                    }
                    self.tableView.endUpdates()
                }
            }
        }
    }

    func serverModel(_ model: MKServerModel, userSelfMuteDeafenStateChanged user: MKUser) {
        DispatchQueue.main.async { [weak self] in
            self?.reloadUser(user)
        }
    }

    @objc(serverModel:userMutedAndDeafened:byUser:)
    func serverModel(_ model: MKServerModel, userMutedAndDeafened user: MKUser, by actor: MKUser?) {
        DispatchQueue.main.async { [weak self] in self?.reloadUser(user) }
    }

    @objc(serverModel:userUnmutedAndUndeafened:byUser:)
    func serverModel(_ model: MKServerModel, userUnmutedAndUndeafened user: MKUser, by actor: MKUser?) {
        DispatchQueue.main.async { [weak self] in self?.reloadUser(user) }
    }

    @objc(serverModel:userMuted:byUser:)
    func serverModel(_ model: MKServerModel, userMuted user: MKUser, by actor: MKUser?) {
        DispatchQueue.main.async { [weak self] in self?.reloadUser(user) }
    }

    @objc(serverModel:userUnmuted:byUser:)
    func serverModel(_ model: MKServerModel, userUnmuted user: MKUser, by actor: MKUser?) {
        DispatchQueue.main.async { [weak self] in self?.reloadUser(user) }
    }

    @objc(serverModel:userDeafened:byUser:)
    func serverModel(_ model: MKServerModel, userDeafened user: MKUser, by actor: MKUser?) {
        DispatchQueue.main.async { [weak self] in self?.reloadUser(user) }
    }

    @objc(serverModel:userUndeafened:byUser:)
    func serverModel(_ model: MKServerModel, userUndeafened user: MKUser, by actor: MKUser?) {
        DispatchQueue.main.async { [weak self] in self?.reloadUser(user) }
    }

    @objc(serverModel:userSuppressed:byUser:)
    func serverModel(_ model: MKServerModel, userSuppressed user: MKUser, by actor: MKUser?) {
        DispatchQueue.main.async { [weak self] in self?.reloadUser(user) }
    }

    @objc(serverModel:userUnsuppressed:byUser:)
    func serverModel(_ model: MKServerModel, userUnsuppressed user: MKUser, by actor: MKUser?) {
        DispatchQueue.main.async { [weak self] in self?.reloadUser(user) }
    }

    func serverModel(_ model: MKServerModel, userMuteStateChanged user: MKUser) {
        DispatchQueue.main.async { [weak self] in self?.reloadUser(user) }
    }

    func serverModel(_ model: MKServerModel, userAuthenticatedStateChanged user: MKUser) {
        DispatchQueue.main.async { [weak self] in self?.reloadUser(user) }
    }

    func serverModel(_ model: MKServerModel, userPrioritySpeakerChanged user: MKUser) {
        DispatchQueue.main.async { [weak self] in self?.reloadUser(user) }
    }

    // MARK: - Push-to-Talk

    @objc private func repositionTalkButton() {
        // Note: Original implementation returned early (commented out rotation handling)
    }

    @objc private func talkOn(_ button: UIButton) {
        button.alpha = 1.0
        MUAudioCaptureManager.shared.beginPushToTalk()
        MKAudio.shared()?.setForceTransmit(true)
    }

    @objc private func talkOff(_ button: UIButton) {
        button.alpha = 0.80
        MUAudioCaptureManager.shared.endPushToTalk()
        MKAudio.shared()?.setForceTransmit(false)
    }

    // MARK: - Mode Switch

    @objc func toggleMode() {
        if viewMode == .server {
            let msg = NSLocalizedString("Switched to channel view mode.", comment: "")
            MUNotificationController.shared.addNotification(msg)
            switchToChannelMode()
        } else if viewMode == .channel {
            let msg = NSLocalizedString("Switched to server view mode.", comment: "")
            MUNotificationController.shared.addNotification(msg)
            switchToServerMode()
        }

        tableView.reloadData()

        if viewMode == .server {
            if let curChan = serverModel.connectedUser()?.channel() {
                let idx = index(for: curChan)
                if idx != NSNotFound {
                    tableView.scrollToRow(at: IndexPath(row: idx, section: 0), at: .top, animated: false)
                }
            }
        }
    }

    // MARK: - Background Notification

    @objc private func appDidEnterBackground(_ notification: Notification) {
        // Force Push-to-Talk to stop when the app is backgrounded
        MUAudioCaptureManager.shared.endPushToTalk()
        MKAudio.shared()?.setForceTransmit(false)

        // Reload the table view to re-render the talk state
        tableView.reloadData()
    }
}
