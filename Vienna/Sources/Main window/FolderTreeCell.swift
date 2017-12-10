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
    
    @objc var inProgress = false {
        didSet {
            if (inProgress == true) {
                auxiliaryImageView?.image = nil
                refreshProgressIndicator?.startAnimation(nil)
            } else {
                refreshProgressIndicator?.stopAnimation(nil)
            }
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }

}
