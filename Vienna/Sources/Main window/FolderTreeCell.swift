//
//  FolderTreeCell.swift
//  Vienna
//
//  Created by Joshua Pore on 9/12/17.
//  Copyright © 2017 uk.co.opencommunity. All rights reserved.
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
