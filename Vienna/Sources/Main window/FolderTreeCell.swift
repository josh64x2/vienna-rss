//
//  FolderTreeCell.swift
//  Vienna
//
//  Created by Joshua Pore on 9/12/17.
//  Copyright © 2017 uk.co.opencommunity. All rights reserved.
//

import Cocoa

class FolderTreeCell: NSTableCellView {
    
    @IBOutlet weak var refreshProgressIndicator: NSProgressIndicator?
    @IBOutlet weak var auxiliaryImageView: NSImageView?
    @IBOutlet weak var stackView: NSStackView?
    @IBOutlet weak var unreadCountButton: NSButton?
    
    @objc var inProgress = false {
        didSet {
            if (inProgress == true) {
                auxiliaryImageView?.image = nil
                stackView?.views[3].isHidden = true
                stackView?.views[4].isHidden = false
                refreshProgressIndicator?.startAnimation(nil)
            } else {
                refreshProgressIndicator?.stopAnimation(nil)
                stackView?.views[4].isHidden = true
            }
        }
    }
    
    @objc var didError = false {
        didSet {
            if (didError == true) {
                auxiliaryImageView?.image = #imageLiteral(resourceName: "folderError.tiff")
                stackView?.views[3].isHidden = false
                
            } else {
                auxiliaryImageView?.image = nil
                stackView?.views[3].isHidden = true
            }
        }
    }
    
    @objc var unreadCount = 0 {
        didSet {
            unreadCountButton?.title = "\(unreadCount)"
            if (unreadCount > 0) {
                stackView?.views[2].isHidden = false
            } else {
                stackView?.views[2].isHidden = true
            }
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
}
