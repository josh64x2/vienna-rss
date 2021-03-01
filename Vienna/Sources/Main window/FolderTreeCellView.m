//
//  FolderTreeCellView.m
//  Vienna
//
//  Copyright 2021 Joshua Pore
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

#import "FolderTreeCellView.h"

@interface FolderTreeCellView ()
@property (weak, nonatomic) IBOutlet NSStackView *stackView;
@property (strong, nonatomic) IBOutlet NSButton *unreadCountButton;
@property (strong, nonatomic) IBOutlet NSImageView *errorImageView;
@property (strong, nonatomic) IBOutlet NSProgressIndicator *progressIndicator;
@end

@implementation FolderTreeCellView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _unreadCount = 0;
        _showError = NO;
        _inProgress = NO;
    }
    return self;
}

- (void)setInProgress:(BOOL)inProgress {
    _inProgress = inProgress;
    if (_inProgress) {
        self.errorImageView.hidden = YES;
        self.progressIndicator.hidden = NO;
        [self.progressIndicator startAnimation:nil];
    } else {
        [self.progressIndicator stopAnimation:nil];
        self.progressIndicator.hidden = YES;
    }
}

- (void)setShowError:(BOOL)showError {
    _showError = showError;
    if (_showError) {
        self.errorImageView.hidden = NO;
    } else {
        self.errorImageView.hidden = YES;
    }
}

- (void)setUnreadCount:(NSInteger)unreadCount {
    _unreadCount = unreadCount;
    if (_unreadCount) {
        self.unreadCountButton.title = [NSString stringWithFormat:@"%ld", (long)_unreadCount];
        self.unreadCountButton.hidden = NO;
    } else {
        self.unreadCountButton.hidden = YES;
    }
}

@end
