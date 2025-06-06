//
//  ViennaApp.h
//  Vienna
//
//  Created by Steve on Tue Jul 06 2004.
//  Copyright (c) 2004-2005 Steve Palmer. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

@import Cocoa;

@class Folder;
@class Article;

#import "FeedListConstants.h"

@interface ViennaApp : NSApplication

@property (nonatomic) IBOutlet NSMenu *articleMenu;
@property (nonatomic) IBOutlet NSMenu *filterMenu;
@property (nonatomic) IBOutlet NSMenu *styleMenu;

// Refresh commands
-(id)handleRefreshAllSubscriptions:(NSScriptCommand *)cmd;
-(id)handleRefreshSubscription:(NSScriptCommand *)cmd;

// Mark all articles read
-(id)handleMarkAllRead:(NSScriptCommand *)cmd;
-(id)handleMarkAllSubscriptionsRead:(NSScriptCommand *)cmd;

// Importing and exporting subscriptions
-(id)handleImportSubscriptions:(NSScriptCommand *)cmd;
-(id)handleExportSubscriptions:(NSScriptCommand *)cmd;

// New subscription
-(id)handleNewSubscription:(NSScriptCommand *)cmd;

// New tab
-(id)handleNewTab:(NSScriptCommand *)cmd;

// Compact database
-(id)handleCompactDatabase:(NSScriptCommand *)cmd;

// Empty trash
-(id)handleEmptyTrash:(NSScriptCommand *)cmd;

// Reset folder sort order
-(id)resetFolderSort:(NSScriptCommand *)cmd;

// General read-only properties.
@property (readonly, nonatomic) NSString *applicationVersion;
@property (readonly, nonatomic) NSArray *folders;
@property (nonatomic, getter=isRefreshing, readonly) BOOL refreshing;
@property (nonatomic, readonly) NSInteger totalUnreadCount;
@property (readonly, nonatomic) NSString *currentTextSelection;
@property (readonly, nonatomic) NSString *documentHTMLSource;
@property (readonly, nonatomic) NSString *documentTabURL;
@property (readonly, nonatomic) NSString *documentTabTitle;

// Change folder selection
@property (nonatomic) Folder *currentFolder;

// Current article
@property (nonatomic, readonly) Article *currentArticle;

// Preference properties
@property (nonatomic) NSInteger autoExpireDuration;
@property (nonatomic) float markReadInterval;
@property (readonly, nonatomic) BOOL readingPaneOnRight;
@property (nonatomic) BOOL refreshOnStartup;
@property (nonatomic) BOOL checkForNewOnStartup;
@property (nonatomic) BOOL openLinksInVienna;
@property (nonatomic) BOOL openLinksInBackground;
@property (nonatomic) NSInteger minimumFontSize;
@property (nonatomic) BOOL enableMinimumFontSize;
@property (nonatomic) NSInteger refreshFrequency;
@property (nonatomic, copy) NSString *displayStyle;
@property (nonatomic) VNAFeedListSizeMode feedListSizeMode;
@property (nonatomic, copy) NSString *articleListFontName;
@property (nonatomic) NSInteger articleListFontSize;
@property (nonatomic) BOOL statusBarVisible;
@property (nonatomic) BOOL filterBarVisible;

@end

