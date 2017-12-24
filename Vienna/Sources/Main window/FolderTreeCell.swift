//
//  FolderTreeCell.swift
//  Vienna
//
//  Copyright 2017
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Cocoa

final class FolderTreeCell: NSTableCellView {

    // MARK: Properties

    @IBOutlet private weak var stackView: NSStackView!

    // These outlets must be strong, as removing them from the stack view,
    // removes them from the view hierarchy also.
    @IBOutlet private var unreadCountButton: NSButton!
    @IBOutlet private var progressIndicator: NSProgressIndicator!
    @IBOutlet private var auxiliaryImageView: NSImageView!

    @objc var inProgress = false {
        didSet {
            if inProgress {
                auxiliaryImageView.isHidden = true
                progressIndicator.isHidden = false
                progressIndicator.startAnimation(nil)
            } else {
                progressIndicator.stopAnimation(nil)
                progressIndicator.isHidden = true
            }
        }
    }

    @objc var didError = false {
        didSet {
            auxiliaryImageView.isHidden = !didError
        }
    }

    @objc var unreadCount = 0 {
        didSet {
            unreadCountButton.title = "\(unreadCount)"
            unreadCountButton.isHidden = unreadCount <= 0
        }
    }

}
