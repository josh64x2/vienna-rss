//
//  FolderTreeCell.swift
//  Vienna
//
//  Copyright 2018
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
                stackView.detachView(auxiliaryImageView)
                stackView.attachView(progressIndicator, in: .trailing)
                progressIndicator.startAnimation(nil)
            } else {
                progressIndicator.stopAnimation(nil)
                stackView.detachView(progressIndicator)
            }
        }
    }

    @objc var didError = false {
        didSet {
            if didError {
                stackView.attachView(auxiliaryImageView, in: .trailing)
            } else {
                stackView.detachView(auxiliaryImageView)
            }
        }
    }

    @objc var unreadCount = 0 {
        didSet {
            unreadCountButton.title = "\(unreadCount)"
            if unreadCount > 0 {
                stackView.attachView(unreadCountButton, at: 0, in: .trailing)
            } else {
                stackView.detachView(unreadCountButton)
            }
        }
    }

    // MARK: Initialization

    override func awakeFromNib() {
        super.awakeFromNib()

        if #available(OSX 10.11, *) {
            stackView.detachesHiddenViews = true
        }
    }

}

// MARK: - Convenience extensions

private extension NSStackView {

    func attachView(_ view: NSView, in gravity: NSStackView.Gravity) {
        if #available(OSX 10.11, *) {
            view.isHidden = false
        } else {
            if views.contains(view) == false {
                addView(view, in: gravity)
            }
        }
    }

    func attachView(_ view: NSView, at index: Int, in gravity: NSStackView.Gravity) {
        if #available(OSX 10.11, *) {
            view.isHidden = false
        } else {
            if views.contains(view) == false {
                insertView(view, at: index, in: gravity)
            }
        }
    }

    func detachView(_ view: NSView) {
        if #available(OSX 10.11, *) {
            view.isHidden = true
        } else {
            if views.contains(view) {
                removeView(view)
            }
        }
    }

}
