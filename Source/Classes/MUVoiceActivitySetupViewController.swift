// Copyright 2009-2011 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import UIKit

/// Voice activity detection setup controller for configuring
/// VAD method (amplitude/SNR) and threshold levels.
@objc(MUVoiceActivitySetupViewController)
@objcMembers
class MUVoiceActivitySetupViewController: UITableViewController {

    // MARK: - Initialization

    init() {
        super.init(style: .grouped)
        preferredContentSize = CGSize(width: 320, height: 480)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - View Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationItem.title = NSLocalizedString("Voice Activity", comment: "")

        tableView.backgroundView = MUBackgroundView.backgroundView()
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = .zero
        tableView.isScrollEnabled = false

        // Start the capture pipeline so the audio bar shows live mic levels.
        // MUAudioCaptureManager uses AVAudioEngine which coexists with MKAudio's
        // AudioUnit — both can read from the microphone simultaneously.
        MUAudioCaptureManager.shared.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        MUAudioCaptureManager.shared.stop()
    }

    // MARK: - Private Helpers

    /// Returns the adjusted section index accounting for preprocessor state.
    /// When preprocessor is disabled, section indices are shifted.
    private func adjustedSection(for section: Int) -> Int {
        if !UserDefaults.standard.bool(forKey: "AudioPreprocessor") {
            return section + 1
        }
        return section
    }

    private var vadThresholdSectionIndex: Int {
        return UserDefaults.standard.bool(forKey: "AudioPreprocessor") ? 2 : 1
    }

    private func vadThresholdSlider(at row: Int) -> UISlider? {
        let indexPath = IndexPath(row: row, section: vadThresholdSectionIndex)
        guard let cell = tableView.cellForRow(at: indexPath),
              let slider = cell.accessoryView as? UISlider else {
            return nil
        }
        return slider
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        if !UserDefaults.standard.bool(forKey: "AudioPreprocessor") {
            return 2
        }
        return 3
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let adjustedSection = adjustedSection(for: section)

        switch adjustedSection {
        case 0: return 2  // VAD Method
        case 1: return 1  // Audio Bar
        case 2: return 3  // Threshold sliders + help
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "Cell"
        var cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier)
        if cell == nil {
            cell = UITableViewCell(style: .default, reuseIdentifier: cellIdentifier)
        }

        guard let cell = cell else { return UITableViewCell() }

        let current = UserDefaults.standard.string(forKey: "AudioVADKind") ?? ""
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.textLabel?.textColor = .black
        cell.selectionStyle = .default

        let adjustedSection = adjustedSection(for: indexPath.section)

        switch adjustedSection {
        case 0:
            // VAD Method selection
            if indexPath.row == 0 {
                cell.textLabel?.text = NSLocalizedString("Amplitude", comment: "Amplitude voice-activity mode")
                if current == "amplitude" {
                    cell.accessoryView = UIImageView(image: UIImage(named: "GrayCheckmark"))
                    cell.textLabel?.textColor = MUColor.selectedText()
                }
            } else if indexPath.row == 1 {
                cell.textLabel?.text = NSLocalizedString("Signal to Noise", comment: "SNR voice-activity mode")
                if current == "snr" {
                    cell.accessoryView = UIImageView(image: UIImage(named: "GrayCheckmark"))
                    cell.textLabel?.textColor = MUColor.selectedText()
                }
            }

        case 1:
            // Audio Bar visualization
            let audioBarCell = MUAudioBarViewCell(style: .default, reuseIdentifier: "AudioBarCell")
            audioBarCell.selectionStyle = .none
            return audioBarCell

        case 2:
            // Threshold sliders
            if indexPath.row == 0 {
                cell.textLabel?.text = NSLocalizedString("Silence Below", comment: "Silence Below VAD configuration")
                cell.selectionStyle = .none

                let slider = UISlider()
                slider.minimumValue = 0.0
                slider.maximumValue = 1.0
                slider.value = UserDefaults.standard.float(forKey: "AudioVADBelow")
                slider.maximumTrackTintColor = .white
                slider.minimumTrackTintColor = MUColor.badPing()
                slider.addTarget(self, action: #selector(vadBelowChanged(_:)), for: .valueChanged)
                cell.accessoryView = slider
            } else if indexPath.row == 1 {
                cell.textLabel?.text = NSLocalizedString("Speech Above", comment: "Silence Above VAD configuration")
                cell.selectionStyle = .none

                let slider = UISlider()
                slider.minimumValue = 0.0
                slider.maximumValue = 1.0
                slider.value = UserDefaults.standard.float(forKey: "AudioVADAbove")
                slider.maximumTrackTintColor = MUColor.goodPing()
                slider.minimumTrackTintColor = .white
                slider.addTarget(self, action: #selector(vadAboveChanged(_:)), for: .valueChanged)
                cell.accessoryView = slider
            } else if indexPath.row == 2 {
                cell.accessoryView = nil
                cell.textLabel?.text = NSLocalizedString("Help", comment: "")
            }

        default:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let adjustedSection = adjustedSection(for: section)

        switch adjustedSection {
        case 0:
            return MUTableViewHeaderLabel.label(withText: NSLocalizedString("Method", comment: ""))
        case 1:
            return MUTableViewHeaderLabel.label(withText: NSLocalizedString("Configuration", comment: ""))
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let adjustedSection = adjustedSection(for: section)

        if adjustedSection == 0 || adjustedSection == 1 {
            return MUTableViewHeaderLabel.defaultHeaderHeight()
        }
        return 0
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let adjustedSection = adjustedSection(for: indexPath.section)

        // Transmission setting change
        if adjustedSection == 0 {
            // Clear all checkmarks in section 0
            for i in 0..<2 {
                if let cell = tableView.cellForRow(at: IndexPath(row: i, section: indexPath.section)) {
                    cell.accessoryView = nil
                    cell.textLabel?.textColor = .black
                }
            }

            tableView.deselectRow(at: indexPath, animated: true)

            if indexPath.row == 0 {
                MUAudioSessionManager.shared.updateVADKind(withString: "amplitude")
            } else if indexPath.row == 1 {
                MUAudioSessionManager.shared.updateVADKind(withString: "snr")
            }

            if let cell = tableView.cellForRow(at: indexPath) {
                cell.accessoryView = UIImageView(image: UIImage(named: "GrayCheckmark"))
                cell.textLabel?.textColor = MUColor.selectedText()
            }
        }

        // Help button
        if adjustedSection == 2 && indexPath.row == 2 {
            tableView.deselectRow(at: indexPath, animated: true)

            let title = NSLocalizedString("Voice Activity Help", comment: "")
            let msg = NSLocalizedString(
                "To calibrate the voice activity correctly, adjust the sliders so that:\n\n" +
                "1. The first few utterances you make are inside the green area.\n" +
                "2. While talking, the bar should stay inside the yellow area.\n" +
                "3. When not speaking, the bar should stay inside the red area.",
                comment: "Help text for Voice Activity"
            )

            let alertCtrl = UIAlertController(title: title, message: msg, preferredStyle: .alert)
            alertCtrl.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
            present(alertCtrl, animated: true, completion: nil)
        }
    }

    // MARK: - Actions

    @objc private func vadBelowChanged(_ sender: UISlider) {
        guard let upperSlider = vadThresholdSlider(at: 1) else { return }

        let thresholds = MUAudioSessionManager.shared.updateVADThresholds(lower: sender.value, upper: upperSlider.value)
        if let lower = thresholds["lower"] as? Float,
           let upper = thresholds["upper"] as? Float {
            sender.value = lower
            upperSlider.value = upper
        }
    }

    @objc private func vadAboveChanged(_ sender: UISlider) {
        guard let lowerSlider = vadThresholdSlider(at: 0) else { return }

        let thresholds = MUAudioSessionManager.shared.updateVADThresholds(lower: lowerSlider.value, upper: sender.value)
        if let lower = thresholds["lower"] as? Float,
           let upper = thresholds["upper"] as? Float {
            lowerSlider.value = lower
            sender.value = upper
        }
    }
}
