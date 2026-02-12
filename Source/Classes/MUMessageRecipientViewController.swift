// Copyright 2009-2012 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import UIKit

/// Protocol for handling message recipient selection.
@objc protocol MUMessageRecipientViewControllerDelegate: AnyObject {
    func messageRecipientViewControllerDidSelectCurrentChannel(_ viewCtrlr: MUMessageRecipientViewController)
    func messageRecipientViewController(_ viewCtrlr: MUMessageRecipientViewController, didSelectUser user: MKUser)
    func messageRecipientViewController(_ viewCtrlr: MUMessageRecipientViewController, didSelectChannel channel: MKChannel)
}

/// Displays a hierarchical tree of channels and users for selecting message recipients.
/// Shows the server's channel tree with proper indentation and allows selecting
/// a channel or user to send a message to.
@objc(MUMessageRecipientViewController)
@objcMembers
class MUMessageRecipientViewController: UITableViewController, MKServerModelDelegate {

    // MARK: - Private Properties

    private var serverModel: MKServerModel?
    private var modelItems: [[String: Any]] = []
    private var userIndexMap: [UInt: Int] = [:]
    private var channelIndexMap: [UInt: Int] = [:]

    weak var delegate: MUMessageRecipientViewControllerDelegate?

    // MARK: - Initialization

    @objc(initWithServerModel:)
    init(serverModel: MKServerModel) {
        self.serverModel = serverModel
        super.init(style: .plain)
        serverModel.addDelegate(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        serverModel?.removeDelegate(self)
    }

    // MARK: - Private Methods

    private func rebuildModelArray(from channel: MKChannel) {
        modelItems = []
        userIndexMap = [:]
        channelIndexMap = [:]
        addChannelTree(channel, indentLevel: 0)
    }

    private func addChannelTree(_ channel: MKChannel, indentLevel: Int) {
        channelIndexMap[UInt(channel.channelId())] = modelItems.count
        modelItems.append([
            "indentLevel": indentLevel,
            "object": channel
        ])

        // Add users in this channel
        if let users = channel.users() as? [MKUser] {
            for user in users {
                userIndexMap[UInt(user.session())] = modelItems.count
                modelItems.append([
                    "indentLevel": indentLevel + 1,
                    "object": user
                ])
            }
        }

        // Recursively add subchannels
        if let subchannels = channel.channels() as? [MKChannel] {
            for subchannel in subchannels {
                addChannelTree(subchannel, indentLevel: indentLevel + 1)
            }
        }
    }

    private func index(for user: MKUser) -> Int {
        if let idx = userIndexMap[UInt(user.session())] {
            return idx + 1  // +1 for "Current Channel" row
        }
        return NSNotFound
    }

    private func index(for channel: MKChannel) -> Int {
        if let idx = channelIndexMap[UInt(channel.channelId())] {
            return idx + 1  // +1 for "Current Channel" row
        }
        return NSNotFound
    }

    private func reloadUser(_ user: MKUser) {
        let idx = index(for: user)
        if idx != NSNotFound {
            tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .none)
        }
    }

    private func reloadChannel(_ channel: MKChannel) {
        let idx = index(for: channel)
        if idx != NSNotFound {
            tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .none)
        }
    }

    private func talkImageName(for talkState: MKTalkState) -> String {
        switch talkState {
        case MKTalkStatePassive:
            return "talking_off"
        case MKTalkStateTalking:
            return "talking_on"
        case MKTalkStateWhispering:
            return "talking_whisper"
        case MKTalkStateShouting:
            return "talking_alt"
        default:
            return "talking_off"
        }
    }

    // MARK: - View Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationItem.title = NSLocalizedString("Message Recipient", comment: "")

        tableView.separatorStyle = .singleLine
        tableView.separatorInset = .zero

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelClicked(_:))
        )

        if let rootChannel = serverModel?.rootChannel() {
            rebuildModelArray(from: rootChannel)
        }
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func cancelClicked(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1 + modelItems.count  // +1 for "Current Channel"
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row > 0 else { return }

        let dict = modelItems[indexPath.row - 1]
        if let channel = dict["object"] as? MKChannel,
           channel == serverModel?.rootChannel(),
           serverModel?.serverCertificatesTrusted() == true {
            cell.backgroundColor = MUColor.verifiedCertificateChain()
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "MUMessageRecipientCell"
        var cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier)
        if cell == nil {
            cell = MUServerTableViewCell(reuseIdentifier: cellIdentifier)
        }

        guard let cell = cell else { return UITableViewCell() }

        cell.textLabel?.font = UIFont.systemFont(ofSize: 18.0)
        cell.selectionStyle = .default

        if indexPath.row == 0 {
            // "Current Channel" row
            cell.imageView?.image = UIImage(named: "channel")
            cell.textLabel?.text = NSLocalizedString("Current Channel", comment: "")
            cell.textLabel?.font = UIFont.boldSystemFont(ofSize: 18.0)
            cell.indentationLevel = 0
            cell.accessoryView = nil
        } else {
            let dict = modelItems[indexPath.row - 1]
            let indentLevel = dict["indentLevel"] as? Int ?? 0

            if let channel = dict["object"] as? MKChannel {
                // Channel row
                if serverModel?.connectedUser()?.channel() == channel {
                    cell.textLabel?.font = UIFont.boldSystemFont(ofSize: 18.0)
                } else {
                    cell.textLabel?.font = UIFont.systemFont(ofSize: 18.0)
                }
                cell.imageView?.image = UIImage(named: "channel")
                cell.textLabel?.text = channel.channelName()
                cell.indentationLevel = indentLevel
                cell.accessoryView = nil
            } else if let user = dict["object"] as? MKUser {
                // User row
                if user == serverModel?.connectedUser() {
                    cell.textLabel?.font = UIFont.boldSystemFont(ofSize: 18.0)
                } else {
                    cell.textLabel?.font = UIFont.systemFont(ofSize: 18.0)
                }
                cell.textLabel?.text = user.userName()
                cell.indentationLevel = indentLevel

                let talkImageName = talkImageName(for: user.talkState())
                cell.imageView?.image = UIImage(named: talkImageName)
                cell.accessoryView = MUUserStateAcessoryView.view(forUser: user)
            }
        }

        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            delegate?.messageRecipientViewControllerDidSelectCurrentChannel(self)
        } else {
            let dict = modelItems[indexPath.row - 1]
            if let channel = dict["object"] as? MKChannel {
                delegate?.messageRecipientViewController(self, didSelectChannel: channel)
            } else if let user = dict["object"] as? MKUser {
                delegate?.messageRecipientViewController(self, didSelectUser: user)
            }
        }

        tableView.deselectRow(at: indexPath, animated: true)
        dismiss(animated: true, completion: nil)
    }

    // MARK: - MKServerModelDelegate

    @objc(serverModel:joinedServerAsUser:)
    func serverModel(_ model: MKServerModel!, joinedServerAs user: MKUser!) {
        if let rootChannel = model.rootChannel() {
            rebuildModelArray(from: rootChannel)
        }
        tableView.reloadData()
    }

    func serverModel(_ model: MKServerModel!, userJoined user: MKUser!) {
        // No action needed
    }

    func serverModel(_ model: MKServerModel!, userDisconnected user: MKUser!) {
        // No action needed
    }

    func serverModel(_ model: MKServerModel!, userLeft user: MKUser!) {
        let idx = index(for: user)
        if let rootChannel = model.rootChannel() {
            rebuildModelArray(from: rootChannel)
        }
        if idx != NSNotFound {
            tableView.deleteRows(at: [IndexPath(row: idx, section: 0)], with: .none)
        }
    }

    func serverModel(_ model: MKServerModel!, userTalkStateChanged user: MKUser!) {
        let userIndex = index(for: user)
        guard userIndex != NSNotFound,
              let cell = tableView.cellForRow(at: IndexPath(row: userIndex, section: 0)) else {
            return
        }

        let imageName = talkImageName(for: user.talkState())
        cell.imageView?.image = UIImage(named: imageName)
    }

    func serverModel(_ model: MKServerModel!, channelAdded channel: MKChannel!) {
        if let rootChannel = model.rootChannel() {
            rebuildModelArray(from: rootChannel)
        }
        let idx = index(for: channel)
        if idx != NSNotFound {
            tableView.insertRows(at: [IndexPath(row: idx, section: 0)], with: .none)
        }
    }

    func serverModel(_ model: MKServerModel!, channelRemoved channel: MKChannel!) {
        if let rootChannel = model.rootChannel() {
            rebuildModelArray(from: rootChannel)
        }
        tableView.reloadData()
    }

    func serverModel(_ model: MKServerModel!, channelMoved channel: MKChannel!) {
        if let rootChannel = model.rootChannel() {
            rebuildModelArray(from: rootChannel)
        }
        tableView.reloadData()
    }

    func serverModel(_ model: MKServerModel!, channelRenamed channel: MKChannel!) {
        reloadChannel(channel)
    }

    @objc(serverModel:userMoved:toChannel:fromChannel:byUser:)
    func serverModel(_ model: MKServerModel!, userMoved user: MKUser!, to chan: MKChannel!, from prevChan: MKChannel!, by mover: MKUser!) {
        tableView.beginUpdates()

        if user == model.connectedUser() {
            reloadChannel(chan)
            if let prevChan = prevChan {
                reloadChannel(prevChan)
            }
        }

        // Check if the user is moving from a previous channel
        if prevChan != nil {
            let prevIdx = index(for: user)
            if prevIdx != NSNotFound {
                tableView.deleteRows(at: [IndexPath(row: prevIdx, section: 0)], with: .none)
            }
        }

        if let rootChannel = model.rootChannel() {
            rebuildModelArray(from: rootChannel)
        }
        let newIdx = index(for: user)
        if newIdx != NSNotFound {
            tableView.insertRows(at: [IndexPath(row: newIdx, section: 0)], with: .none)
        }

        tableView.endUpdates()
    }

    func serverModel(_ model: MKServerModel!, userSelfMuted user: MKUser!) {
        // No action needed
    }

    func serverModel(_ model: MKServerModel!, userRemovedSelfMute user: MKUser!) {
        // No action needed
    }

    func serverModel(_ model: MKServerModel!, userSelfMutedAndDeafened user: MKUser!) {
        // No action needed
    }

    func serverModel(_ model: MKServerModel!, userRemovedSelfMuteAndDeafen user: MKUser!) {
        // No action needed
    }

    func serverModel(_ model: MKServerModel!, userSelfMuteDeafenStateChanged user: MKUser!) {
        reloadUser(user)
    }

    @objc(serverModel:userMutedAndDeafened:byUser:)
    func serverModel(_ model: MKServerModel!, userMutedAndDeafened user: MKUser!, by actor: MKUser!) {
        reloadUser(user)
    }

    @objc(serverModel:userUnmutedAndUndeafened:byUser:)
    func serverModel(_ model: MKServerModel!, userUnmutedAndUndeafened user: MKUser!, by actor: MKUser!) {
        reloadUser(user)
    }

    @objc(serverModel:userMuted:byUser:)
    func serverModel(_ model: MKServerModel!, userMuted user: MKUser!, by actor: MKUser!) {
        reloadUser(user)
    }

    @objc(serverModel:userUnmuted:byUser:)
    func serverModel(_ model: MKServerModel!, userUnmuted user: MKUser!, by actor: MKUser!) {
        reloadUser(user)
    }

    @objc(serverModel:userDeafened:byUser:)
    func serverModel(_ model: MKServerModel!, userDeafened user: MKUser!, by actor: MKUser!) {
        reloadUser(user)
    }

    @objc(serverModel:userUndeafened:byUser:)
    func serverModel(_ model: MKServerModel!, userUndeafened user: MKUser!, by actor: MKUser!) {
        reloadUser(user)
    }

    @objc(serverModel:userSuppressed:byUser:)
    func serverModel(_ model: MKServerModel!, userSuppressed user: MKUser!, by actor: MKUser!) {
        reloadUser(user)
    }

    @objc(serverModel:userUnsuppressed:byUser:)
    func serverModel(_ model: MKServerModel!, userUnsuppressed user: MKUser!, by actor: MKUser!) {
        reloadUser(user)
    }

    func serverModel(_ model: MKServerModel!, userMuteStateChanged user: MKUser!) {
        reloadUser(user)
    }
}
