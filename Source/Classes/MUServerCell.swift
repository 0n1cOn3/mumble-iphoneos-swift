// Copyright 2009-2011 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import UIKit

/// Table view cell for displaying server information with ping and user count.
/// Uses MKServerPinger to fetch server status and displays a color-coded indicator.
@objc(MUServerCell)
@objcMembers
class MUServerCell: UITableViewCell, MKServerPingerDelegate {

    // MARK: - Private Properties

    private var displayname: String?
    private var hostname: String?
    private var port: String?
    private var username: String?
    private var pinger: MKServerPinger?

    // MARK: - Class Methods

    static func reuseIdentifier() -> String {
        return "ServerCell"
    }

    // MARK: - Initialization

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier ?? MUServerCell.reuseIdentifier())
    }

    convenience init() {
        self.init(style: .subtitle, reuseIdentifier: MUServerCell.reuseIdentifier())
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        stopPinger()
    }

    // MARK: - Cell Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        stopPinger()
        displayname = nil
        hostname = nil
        port = nil
        username = nil
        imageView?.image = nil
    }

    // MARK: - Private Pinger Management

    private func stopPinger() {
        pinger?.setDelegate(nil)
        pinger = nil
    }

    // MARK: - Public Methods

    @objc(populateFromDisplayName:hostName:port:)
    func populate(fromDisplayName displayName: String?, hostName: String?, port: String?) {
        self.displayname = displayName
        self.port = port
        stopPinger()

        if let hostName = hostName, !hostName.isEmpty {
            self.hostname = hostName
            self.pinger = MKServerPinger(hostname: hostName, port: port)
            self.pinger?.setDelegate(self)
        } else {
            self.hostname = NSLocalizedString("(No Server)", comment: "")
        }

        textLabel?.text = displayname
        detailTextLabel?.text = "\(hostname ?? ""):\(port ?? "")"
        imageView?.image = drawPingImage(pingValue: 999, userCount: 0, isFull: false)
    }

    @objc(populateFromFavouriteServer:)
    func populate(from favServ: MUFavouriteServer) {
        self.displayname = favServ.displayName
        self.hostname = favServ.hostName
        self.port = String(favServ.port)

        if let userName = favServ.userName, !userName.isEmpty {
            self.username = userName
        } else {
            self.username = UserDefaults.standard.string(forKey: "DefaultUserName")
        }

        stopPinger()
        if let hostname = self.hostname, !hostname.isEmpty {
            self.pinger = MKServerPinger(hostname: hostname, port: port)
            self.pinger?.setDelegate(self)
        } else {
            self.hostname = NSLocalizedString("(No Server)", comment: "")
        }

        textLabel?.text = displayname
        let detailFormat = NSLocalizedString("%@ on %@:%@", comment: "username on hostname:port")
        detailTextLabel?.text = String(format: detailFormat, username ?? "", hostname ?? "", port ?? "")
        imageView?.image = drawPingImage(pingValue: 999, userCount: 0, isFull: false)
    }

    // MARK: - Private Methods

    private func drawPingImage(pingValue: Int, userCount: Int, isFull: Bool) -> UIImage? {
        var pingColor = MUColor.badPing()
        if pingValue <= 125 {
            pingColor = MUColor.goodPing()
        } else if pingValue > 125 && pingValue <= 250 {
            pingColor = MUColor.mediumPing()
        }

        var pingStr = "\(pingValue)\nms"
        if pingValue >= 999 {
            pingStr = "∞\nms"
        }

        UIGraphicsBeginImageContextWithOptions(CGSize(width: 66, height: 32), false, UIScreen.main.scale)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

        // Draw ping box
        ctx.setFillColor(pingColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))

        // Draw ping text
        ctx.setTextDrawingMode(.fill)
        ctx.setFillColor(UIColor.white.cgColor)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.alignment = .center

        let pingAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: UIColor.white
        ]
        (pingStr as NSString).draw(in: CGRect(x: 0, y: 0, width: 32, height: 32), withAttributes: pingAttributes)

        // Draw user count box
        let userCountColor = isFull ? MUColor.badPing() : MUColor.userCount()
        ctx.setFillColor(userCountColor.cgColor)
        ctx.fill(CGRect(x: 34, y: 0, width: 32, height: 32))

        // Draw user count text
        let usersFormat = NSLocalizedString("%lu\nppl", comment: "user count")
        let usersStr = String(format: usersFormat, userCount)
        (usersStr as NSString).draw(in: CGRect(x: 34, y: 0, width: 32, height: 32), withAttributes: pingAttributes)

        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return img
    }

    // MARK: - MKServerPingerDelegate

    func serverPingerResult(_ result: UnsafeMutablePointer<MKServerPingerResult>!) {
        guard let result = result?.pointee else { return }

        let pingValue = Int(result.ping * 1000.0)
        let userCount = Int(result.cur_users)
        let isFull = result.cur_users == result.max_users

        imageView?.image = drawPingImage(pingValue: pingValue, userCount: userCount, isFull: isFull)
    }
}
