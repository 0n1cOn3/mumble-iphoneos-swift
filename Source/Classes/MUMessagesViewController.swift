// Copyright 2009-2011 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import UIKit
import UserNotifications
import UniformTypeIdentifiers

// MARK: - Helper Function

/// Recursively searches for a UIView whose description starts with the given prefix.
private func findUIView(in rootView: UIView, withPrefix prefix: String) -> UIView? {
    for subview in rootView.subviews {
        if subview.description.hasPrefix(prefix) {
            return subview
        }
        if let candidate = findUIView(in: subview, withPrefix: prefix) {
            return candidate
        }
    }
    return nil
}

// MARK: - MUConsistentTextField

/// A text field with consistent text positioning regardless of left view width.
private class MUConsistentTextField: UITextField {

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        return editingRect(forBounds: bounds)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        let padding: CGFloat = 13

        let leftRect = super.leftViewRect(forBounds: bounds)
        var rect = super.editingRect(forBounds: bounds)

        let minX = leftRect.width + padding

        if rect.origin.x < minX {
            let delta = minX - rect.origin.x
            rect.origin.x += delta
        }

        return rect
    }
}

// MARK: - MUMessageReceiverButton

/// A rounded button displaying the message recipient name.
private class MUMessageReceiverButton: UIControl {

    private var displayString: String = ""

    init(text: String) {
        super.init(frame: .zero)

        isOpaque = false

        // Truncate long names
        if text.count >= 15 {
            displayString = String(text.prefix(11)) + "..."
        } else {
            displayString = text
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 14.0)
        ]
        let size = (displayString as NSString).size(withAttributes: attributes)
        frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ rect: CGRect) {
        var drawRect = bounds
        let radius: CGFloat = 6.0

        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.clear(drawRect)
        context.setLineWidth(1.0)

        if isHighlighted {
            UIColor.lightGray.setFill()
        } else {
            MUColor.selectedText().setFill()
        }

        // Draw rounded rectangle
        context.beginPath()
        context.move(to: CGPoint(x: drawRect.origin.x, y: drawRect.origin.y + radius))
        context.addLine(to: CGPoint(x: drawRect.origin.x, y: drawRect.origin.y + drawRect.height - radius))
        context.addArc(
            center: CGPoint(x: drawRect.origin.x + radius, y: drawRect.origin.y + drawRect.height - radius),
            radius: radius,
            startAngle: .pi,
            endAngle: .pi / 2,
            clockwise: true
        )
        context.addLine(to: CGPoint(x: drawRect.origin.x + drawRect.width - radius, y: drawRect.origin.y + drawRect.height))
        context.addArc(
            center: CGPoint(x: drawRect.origin.x + drawRect.width - radius, y: drawRect.origin.y + drawRect.height - radius),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: 0,
            clockwise: true
        )
        context.addLine(to: CGPoint(x: drawRect.origin.x + drawRect.width, y: drawRect.origin.y + radius))
        context.addArc(
            center: CGPoint(x: drawRect.origin.x + drawRect.width - radius, y: drawRect.origin.y + radius),
            radius: radius,
            startAngle: 0,
            endAngle: -.pi / 2,
            clockwise: true
        )
        context.addLine(to: CGPoint(x: drawRect.origin.x + radius, y: drawRect.origin.y))
        context.addArc(
            center: CGPoint(x: drawRect.origin.x + radius, y: drawRect.origin.y + radius),
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: .pi,
            clockwise: true
        )
        context.closePath()
        context.fillPath()

        // Draw text
        drawRect.origin.x = radius
        drawRect.size.width -= radius

        UIColor.white.set()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 14.0)
        ]
        (displayString as NSString).draw(in: drawRect, withAttributes: attributes)
    }

    override var isHighlighted: Bool {
        didSet {
            setNeedsDisplay()
        }
    }
}

// MARK: - MUMessagesViewController

/// The main messages view controller for sending and receiving chat messages.
/// Displays messages in a table view with chat bubbles and provides a text field
/// for composing new messages to users or channels.
@objc(MUMessagesViewController)
@objcMembers
class MUMessagesViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, MKServerModelDelegate, UITextFieldDelegate, MUMessageBubbleTableViewCellDelegate, MUMessageRecipientViewControllerDelegate {

    // MARK: - Private Properties

    private var model: MKServerModel?
    private var tableView: UITableView!
    private var textBarView: UIView!
    private var textField: MUConsistentTextField!
    private var autoCorrectGuard = false
    private var msgdb: MUMessagesDatabase!

    // Message recipient state
    private var channel: MKChannel?
    private var tree: MKChannel?
    private var user: MKUser?

    // MARK: - Initialization

    @objc(initWithServerModel:)
    init(serverModel: MKServerModel) {
        self.model = serverModel
        super.init(nibName: nil, bundle: nil)
        serverModel.addDelegate(self)
        msgdb = MUMessagesDatabase()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        model?.removeDelegate(self)
    }

    // MARK: - Public Methods

    func clearAllMessages() {
        msgdb = MUMessagesDatabase()
        tableView?.reloadData()
    }

    // MARK: - Private Methods

    private func setReceiverName(_ receiver: String, imageName: String) {
        // Guard against textField not yet initialized (viewWillAppear not called)
        guard let textField = textField else { return }

        let receiverView = MUMessageReceiverButton(text: receiver)
        receiverView.addTarget(self, action: #selector(showRecipientPicker(_:)), for: .touchUpInside)

        // Add padding for receiver button
        let paddedRect = CGRect(x: 0, y: 0, width: receiverView.frame.width + 12, height: receiverView.frame.height)
        let paddedView = UIView(frame: paddedRect)
        paddedView.addSubview(receiverView)
        var adjustedFrame = paddedRect
        adjustedFrame.origin.x += 6
        receiverView.frame = adjustedFrame
        textField.leftView = paddedView

        // Add image for message type indicator
        let imgView = UIImageView(image: UIImage(named: imageName))
        let imgPaddedFrame = CGRect(x: 0, y: 0, width: imgView.frame.width + 6, height: imgView.frame.height)
        let imgPaddedView = UIView(frame: imgPaddedFrame)
        imgPaddedView.addSubview(imgView)
        textField.rightView = imgPaddedView
        textField.rightViewMode = .always
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Register for keyboard notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )

        // Set up UI if not already created
        if tableView == nil {
            let textBarHeight: CGFloat = 44

            let viewSafeAreaInsets = view.safeAreaInsets
            let bottomInset = viewSafeAreaInsets.bottom

            let viewFrame = view.frame

            // Create table view
            let tableViewFrame = CGRect(
                x: 0,
                y: 0,
                width: viewFrame.width,
                height: viewFrame.height - textBarHeight - bottomInset
            )
            tableView = UITableView(frame: tableViewFrame, style: .plain)
            tableView.backgroundView = MUBackgroundView.backgroundView()
            tableView.separatorStyle = .none
            tableView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
            tableView.delegate = self
            tableView.dataSource = self
            view.addSubview(tableView)

            // Add swipe gestures for keyboard
            let hideSwipe = UISwipeGestureRecognizer(target: self, action: #selector(hideKeyboard(_:)))
            hideSwipe.direction = .down
            view.addGestureRecognizer(hideSwipe)

            let showSwipe = UISwipeGestureRecognizer(target: self, action: #selector(showKeyboard(_:)))
            showSwipe.direction = .up
            view.addGestureRecognizer(showSwipe)

            // Create text bar
            let textBarFrame = CGRect(
                x: 0,
                y: tableViewFrame.height,
                width: tableViewFrame.width,
                height: textBarHeight
            )
            textBarView = UIView(frame: textBarFrame)
            textBarView.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
            if let patternImage = UIImage(named: "BlackToolbarPatterniOS7") {
                textBarView.backgroundColor = UIColor(patternImage: patternImage)
            } else {
                textBarView.backgroundColor = .darkGray
            }

            // Create text field
            let textFieldMargin: CGFloat = 6
            textField = MUConsistentTextField(frame: CGRect(
                x: textFieldMargin,
                y: textFieldMargin,
                width: tableViewFrame.width - 2 * textFieldMargin,
                height: textBarHeight - 2 * textFieldMargin
            ))
            textField.leftViewMode = .always
            textField.rightViewMode = .always
            textField.borderStyle = .roundedRect
            textField.textColor = .black
            textField.font = UIFont.systemFont(ofSize: 17.0)
            textField.contentVerticalAlignment = .center
            textField.returnKeyType = .send
            textField.delegate = self
            textBarView.addSubview(textField)
            view.addSubview(textBarView)

            // Set default recipient to current channel
            if let channelName = model?.connectedUser()?.channel()?.channelName() {
                setReceiverName(channelName, imageName: "channelmsg")
            }
        }

        tableView?.reloadData()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        textField.resignFirstResponder()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if UIMenuController.shared.isMenuVisible {
            if #available(iOS 13.0, *) {
                UIMenuController.shared.hideMenu()
            } else {
                UIMenuController.shared.setMenuVisible(false, animated: true)
            }
        }
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return msgdb.count()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "MUMessageViewCell"
        var cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier) as? MUMessageBubbleTableViewCell
        if cell == nil {
            cell = MUMessageBubbleTableViewCell(reuseIdentifier: cellIdentifier)
        }

        guard let cell = cell, let txtMsg = msgdb.message(at: indexPath.row) else {
            return UITableViewCell()
        }

        cell.setHeading(txtMsg.heading())
        cell.setMessage(txtMsg.message())
        cell.setShownImages(txtMsg.embeddedImages())
        cell.setDate(txtMsg.date())

        if txtMsg.hasAttachments() {
            let footer: String
            if txtMsg.numberOfAttachments() > 1 {
                footer = String(format: NSLocalizedString("%li attachments", comment: ""), txtMsg.numberOfAttachments())
            } else {
                footer = NSLocalizedString("1 attachment", comment: "")
            }
            cell.setFooter(footer)
        } else {
            cell.setFooter(nil)
        }

        cell.setRightSide(txtMsg.isSentBySelf())
        cell.isSelected = false
        cell.delegate = self
        cell.backgroundColor = .clear

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let txtMsg = msgdb.message(at: indexPath.row) else {
            return 0
        }

        var footer: String? = nil
        if txtMsg.hasAttachments() {
            if txtMsg.numberOfAttachments() > 1 {
                footer = String(format: NSLocalizedString("%li attachments", comment: ""), txtMsg.numberOfAttachments())
            } else {
                footer = NSLocalizedString("1 attachment", comment: "")
            }
        }

        return MUMessageBubbleTableViewCell.heightForCell(
            withHeading: txtMsg.heading(),
            message: txtMsg.message(),
            images: txtMsg.embeddedImages() as? [UIImage],
            footer: footer,
            date: txtMsg.date()
        )
    }

    // MARK: - Keyboard Handling

    @objc private func showKeyboard(_ sender: Any) {
        textField.becomeFirstResponder()
    }

    @objc private func hideKeyboard(_ sender: Any) {
        textField.resignFirstResponder()
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo, !autoCorrectGuard else { return }

        // Style the keyboard background on iOS 7+
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.0001) {
            for window in UIApplication.shared.windows {
                if window.description.hasPrefix("<UITextEffectsWindow") {
                    if let backdropView = findUIView(in: window, withPrefix: "<UIKBBackdropView") {
                        for subview in backdropView.subviews {
                            if subview.description.hasPrefix("<UIView") {
                                subview.backgroundColor = .black
                            }
                        }
                    }
                }
            }
        }

        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRaw = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
        let curve = UIView.AnimationCurve(rawValue: Int(curveRaw)) ?? .easeInOut

        var keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        keyboardFrame = view.convert(keyboardFrame, from: nil)

        UIView.beginAnimations(nil, context: nil)
        UIView.setAnimationDuration(duration)
        UIView.setAnimationCurve(curve)

        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: keyboardFrame.height, right: 0)
        tableView.scrollIndicatorInsets = tableView.contentInset
        textBarView.frame = CGRect(
            x: 0,
            y: keyboardFrame.origin.y - 44,
            width: tableView.frame.width,
            height: 44
        )

        UIView.commitAnimations()

        if msgdb.count() > 0 {
            let indexPath = IndexPath(row: msgdb.count() - 1, section: 0)
            tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let userInfo = notification.userInfo, !autoCorrectGuard else { return }

        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRaw = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
        let curve = UIView.AnimationCurve(rawValue: Int(curveRaw)) ?? .easeInOut

        UIView.beginAnimations(nil, context: nil)
        UIView.setAnimationDuration(duration)
        UIView.setAnimationCurve(curve)

        tableView.contentInset = .zero
        tableView.scrollIndicatorInsets = .zero
        textBarView.frame = CGRect(
            x: 0,
            y: tableView.frame.height,
            width: tableView.frame.width,
            height: 44
        )

        UIView.commitAnimations()

        if msgdb.count() > 0 {
            let indexPath = IndexPath(row: msgdb.count() - 1, section: 0)
            tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let text = textField.text, !text.isEmpty else {
            return false
        }

        // Hack: resign/become to accept autocorrect
        autoCorrectGuard = true
        textField.resignFirstResponder()
        textField.becomeFirstResponder()
        autoCorrectGuard = false

        guard let htmlText = MUTextMessageProcessor.processedHTML(fromPlainTextMessage: text),
              let txtMsg = MKTextMessage(html: htmlText) else {
            return false
        }

        var destName: String? = nil

        if tree == nil && channel == nil && user == nil {
            // Send to current channel
            if let currentChannel = model?.connectedUser()?.channel() {
                model?.send(txtMsg, to: currentChannel)
                destName = currentChannel.channelName()
            }
        } else if let targetUser = user {
            model?.send(txtMsg, to: targetUser)
            destName = targetUser.userName()
        } else if let targetChannel = channel {
            model?.send(txtMsg, to: targetChannel)
            destName = targetChannel.channelName()
        } else if let targetTree = tree {
            model?.send(txtMsg, toTree: targetTree)
            destName = targetTree.channelName()
        }

        if let destName = destName {
            let heading = String(format: NSLocalizedString("To %@", comment: "Message recipient title"), destName)
            let countBefore = msgdb.count()
            msgdb.addMessage(txtMsg, withHeading: heading, andSentBySelf: true)
            let countAfter = msgdb.count()

            // Only insert row if message was actually added
            if countAfter > countBefore {
                let indexPath = IndexPath(row: countAfter - 1, section: 0)
                tableView.insertRows(at: [indexPath], with: .fade)
                tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
            }
        }

        textField.text = nil
        return false
    }

    // MARK: - Actions

    @objc private func showRecipientPicker(_ sender: Any) {
        guard let model = model else { return }

        let recipientViewController = MUMessageRecipientViewController(serverModel: model)
        recipientViewController.delegate = self
        let navCtrl = UINavigationController(rootViewController: recipientViewController)
        present(navCtrl, animated: true, completion: nil)
    }

    // MARK: - MUMessageBubbleTableViewCellDelegate

    func messageBubbleTableViewCellRequestedCopy(_ cell: MUMessageBubbleTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell),
              let txtMsg = msgdb.message(at: indexPath.row),
              let message = txtMsg.message() else {
            return
        }

        UIPasteboard.general.string = message
    }

    func messageBubbleTableViewCellRequestedDeletion(_ cell: MUMessageBubbleTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }

        msgdb.clearMessage(at: indexPath.row)
        tableView.reloadRows(at: [indexPath], with: .fade)
    }

    func messageBubbleTableViewCellRequestedAttachmentViewer(_ cell: MUMessageBubbleTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell),
              let txtMsg = msgdb.message(at: indexPath.row),
              txtMsg.hasAttachments() else {
            return
        }

        cell.isSelected = true

        if let links = txtMsg.embeddedLinks() as? [String], !links.isEmpty {
            let attachmentViewController = MUMessageAttachmentViewController(
                images: txtMsg.embeddedImages(),
                links: links
            )
            navigationController?.pushViewController(attachmentViewController, animated: true)
        } else if let images = txtMsg.embeddedImages() as? [UIImage], !images.isEmpty {
            let imgViewController = MUImageViewController(images: images)
            navigationController?.pushViewController(imgViewController, animated: true)
        }
    }

    // MARK: - MUMessageRecipientViewControllerDelegate

    func messageRecipientViewController(_ viewCtrlr: MUMessageRecipientViewController, didSelectChannel channel: MKChannel) {
        tree = nil
        self.channel = channel
        user = nil

        setReceiverName(channel.channelName() ?? "", imageName: "channelmsg")
    }

    func messageRecipientViewController(_ viewCtrlr: MUMessageRecipientViewController, didSelectUser user: MKUser) {
        tree = nil
        channel = nil
        self.user = user

        setReceiverName(user.userName() ?? "", imageName: "usermsg")
    }

    func messageRecipientViewControllerDidSelectCurrentChannel(_ viewCtrlr: MUMessageRecipientViewController) {
        tree = nil
        channel = nil
        user = nil

        if let channelName = model?.connectedUser()?.channel()?.channelName() {
            setReceiverName(channelName, imageName: "channelmsg")
        }
    }

    // MARK: - MKServerModelDelegate

    @objc(serverModel:joinedServerAsUser:withWelcomeMessage:)
    func serverModel(_ model: MKServerModel!, joinedServerAs user: MKUser!, withWelcome msg: MKTextMessage!) {
        // Dispatch to main thread since MKServerModel delegates may be called from background
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let msg = msg else { return }

            let countBefore = self.msgdb.count()
            self.msgdb.addMessage(msg, withHeading: NSLocalizedString("Welcome Message", comment: "Title for welcome message"), andSentBySelf: false)
            let countAfter = self.msgdb.count()

            // Only insert row if message was actually added
            guard countAfter > countBefore else { return }

            // Guard against tableView not yet initialized (viewWillAppear not called)
            guard let tableView = self.tableView else { return }

            let indexPath = IndexPath(row: countAfter - 1, section: 0)
            tableView.insertRows(at: [indexPath], with: .fade)
            if !tableView.isDragging && !UIMenuController.shared.isMenuVisible {
                tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
            }
        }
    }

    @objc(serverModel:userMoved:toChannel:fromChannel:byUser:)
    func serverModel(_ model: MKServerModel!, userMoved user: MKUser!, to chan: MKChannel!, from prevChan: MKChannel!, by mover: MKUser!) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let model = model else { return }
            if user == model.connectedUser() {
                // Are we in 'send to default channel mode'?
                if self.user == nil && self.channel == nil && self.tree == nil {
                    if let channelName = model.connectedUser()?.channel()?.channelName() {
                        self.setReceiverName(channelName, imageName: "channelmsg")
                    }
                }
            }
        }
    }

    func serverModel(_ model: MKServerModel!, userLeft user: MKUser!) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let model = model else { return }
            if user == self.user {
                self.user = nil
            }

            if let channelName = model.connectedUser()?.channel()?.channelName() {
                self.setReceiverName(channelName, imageName: "channelmsg")
            }
        }
    }

    func serverModel(_ model: MKServerModel!, channelRenamed channel: MKChannel!) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let channel = channel else { return }
            if channel == self.tree {
                self.setReceiverName(channel.channelName() ?? "", imageName: "channelmsg")
            } else if channel == self.channel {
                self.setReceiverName(channel.channelName() ?? "", imageName: "channelmsg")
            } else if self.channel == nil && self.tree == nil && self.user == nil && model?.connectedUser()?.channel() == channel {
                if let channelName = model?.connectedUser()?.channel()?.channelName() {
                    self.setReceiverName(channelName, imageName: "channelmsg")
                }
            }
        }
    }

    func serverModel(_ model: MKServerModel!, channelRemoved channel: MKChannel!) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let channel = channel else { return }
            if channel == self.tree {
                self.tree = nil
                if let channelName = model?.connectedUser()?.channel()?.channelName() {
                    self.setReceiverName(channelName, imageName: "channelmsg")
                }
            } else if channel == self.channel {
                self.channel = nil
                if let channelName = model?.connectedUser()?.channel()?.channelName() {
                    self.setReceiverName(channelName, imageName: "channelmsg")
                }
            }
        }
    }

    @objc(serverModel:textMessageReceived:fromUser:)
    func serverModel(_ model: MKServerModel!, textMessageReceived msg: MKTextMessage!, from user: MKUser!) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let msg = msg else { return }

            var heading = NSLocalizedString("Server Message", comment: "A message sent from the server itself")
            if let user = user, let userName = user.userName() {
                heading = String(format: NSLocalizedString("From %@", comment: "Message sender title"), userName)
            }

            let countBefore = self.msgdb.count()
            self.msgdb.addMessage(msg, withHeading: heading, andSentBySelf: false)
            let countAfter = self.msgdb.count()

            // Only insert row if message was actually added
            guard countAfter > countBefore else { return }

            // Guard against tableView not yet initialized (viewWillAppear not called)
            guard let tableView = self.tableView else { return }

            let indexPath = IndexPath(row: countAfter - 1, section: 0)
            tableView.insertRows(at: [indexPath], with: .fade)
            if !tableView.isDragging && !UIMenuController.shared.isMenuVisible {
                tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
            }

            // Send local notification if app is in background
            let app = UIApplication.shared
            if app.applicationState == .background {
                var trimSet = CharacterSet.whitespaces
                trimSet.formUnion(.newlines)

                var msgText = (msg.plainTextString() ?? "").trimmingCharacters(in: trimSet)
                let numImages = msg.embeddedImages()?.count ?? 0

                if msgText.isEmpty {
                    if numImages == 0 {
                        msgText = NSLocalizedString("(Empty body)", comment: "")
                    } else if numImages == 1 {
                        msgText = NSLocalizedString("(Message with image attachment)", comment: "")
                    } else {
                        msgText = NSLocalizedString("(Message with image attachments)", comment: "")
                    }
                } else {
                    msgText = msg.plainTextString() ?? ""
                }

                let content = UNMutableNotificationContent()
                content.body = msgText
                if let user = user, let userName = user.userName() {
                    content.title = userName
                }

                let request = UNNotificationRequest(
                    identifier: "info.mumble.Mumble.TextMessageNotification",
                    content: content,
                    trigger: nil
                )
                UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                app.applicationIconBadgeNumber += 1
            }
        }
    }
}
