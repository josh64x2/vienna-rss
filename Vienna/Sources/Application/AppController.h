//
//  AppController.h
//  Vienna
//
//  Created by Steve on Sat Jan 24 2004.
//  Copyright (c) 2004-2017 Steve Palmer and Vienna contributors. All rights reserved.
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

#define APPCONTROLLER ((AppController *)[NSApp delegate])

@class FoldersTree;
@class NewSubscription;
@class PluginManager;
@class SearchMethod;
@class Database;
@class Article;
@protocol Browser;

@interface AppController : NSObject <NSApplicationDelegate> {
#pragma clang diagnostic ignored "-Wobjc-interface-ivars"
    Database *db;
}

@property (nonatomic) PluginManager *pluginManager;
@property (nonatomic, weak) id<Browser> browser;
@property (nonatomic) NewSubscription *rssFeed;
@property (nonatomic) FoldersTree *foldersTree;
@property (readonly, nonatomic) NSMenu *searchFieldMenu;

// Menu action items
-(IBAction)reindexDatabase:(id)sender;
-(IBAction)deleteMessage:(id)sender;
-(IBAction)deleteFolder:(id)sender;
-(IBAction)searchUsingToolbarTextField:(id)sender;
-(IBAction)markAllRead:(id)sender;
-(IBAction)markAllSubscriptionsRead:(id)sender;
-(IBAction)markUnread:(id)sender;
-(IBAction)markRead:(id)sender;
-(IBAction)markFlagged:(id)sender;
-(IBAction)renameFolder:(id)sender;
-(IBAction)viewFirstUnread:(id)sender;
-(IBAction)viewArticlesTab:(id)sender;
-(IBAction)viewNextUnread:(id)sender;
-(IBAction)printDocument:(id)sender;
-(IBAction)goBack:(id)sender;
-(IBAction)goForward:(id)sender;
-(IBAction)newSmartFolder:(id)sender;
-(IBAction)newSubscription:(id)sender;
-(IBAction)newGroupFolder:(id)sender;
-(IBAction)editFolder:(id)sender;
-(IBAction)openHomePage:(id)sender;
-(IBAction)viewArticlePages:(id)sender;
-(IBAction)viewArticlePagesInAlternateBrowser:(id)sender;
-(IBAction)doSelectScript:(id)sender;
-(IBAction)doSelectStyle:(id)sender;
-(IBAction)doOpenScriptsFolder:(id)sender;
-(IBAction)viewSourceHomePage:(id)sender;
-(IBAction)viewSourceHomePageInAlternateBrowser:(id)sender;
-(IBAction)emptyTrash:(id)sender;
-(IBAction)refreshAllFolderIcons:(id)sender;
-(IBAction)refreshSelectedSubscriptions:(id)sender;
-(IBAction)forceRefreshSelectedSubscriptions:(id)sender;
-(IBAction)updateRemoteSubscriptions:(id)sender;
-(IBAction)refreshAllSubscriptions:(id)sender;
-(IBAction)cancelAllRefreshes:(id)sender;
-(IBAction)openStylesPage:(id)sender;
-(IBAction)showMainWindow:(id)sender;
-(IBAction)previousTab:(id)sender;
-(IBAction)nextTab:(id)sender;
-(IBAction)closeActiveTab:(id)sender;
-(IBAction)closeAllTabs:(id)sender;
-(IBAction)reloadPage:(id)sender;
-(IBAction)stopReloadingPage:(id)sender;
-(IBAction)restoreMessage:(id)sender;
-(IBAction)skipFolder:(id)sender;
-(IBAction)openWebLocation:(id)sender;
-(IBAction)getInfo:(id)sender;
-(IBAction)unsubscribeFeed:(id)sender;
-(IBAction)useCurrentStyleForArticles:(id)sender;
-(IBAction)useWebPageForArticles:(id)sender;
-(IBAction)keyboardShortcutsHelp:(id)sender;
-(IBAction)downloadEnclosure:(id)sender;
-(IBAction)setFocusToSearchField:(id)sender;
-(IBAction)localPerformFindPanelAction:(id)sender;
-(IBAction)keepFoldersArranged:(id)sender;
-(IBAction)exportSubscriptions:(id)sender;
-(IBAction)importSubscriptions:(id)sender;
- (IBAction)searchUsingTreeFilter:(id)sender;

// Public functions
-(void)showUnreadCountOnApplicationIconAndWindowTitle;
-(void)openURLFromString:(NSString *)urlString inPreferredBrowser:(BOOL)openInPreferredBrowserFlag;
-(void)openURL:(NSURL *)url inPreferredBrowser:(BOOL)openInPreferredBrowserFlag;
-(BOOL)handleKeyDown:(NSEvent *)event;
-(void)openURLInDefaultBrowser:(NSURL *)url;
-(void)handleRSSLink:(NSString *)linkPath;
-(void)selectFolder:(NSInteger)folderId;
-(void)createSubscriptionInCurrentLocationForUrl:(NSURL *)url;
-(void)createNewSubscription:(NSString *)urlString underFolder:(NSInteger)parentId afterChild:(NSInteger)predecessorId;
-(void)markSelectedFoldersRead:(NSArray *)arrayOfFolders;
-(void)doSafeInitialisation;
-(void)clearUndoStack;
@property (nonatomic, copy) NSString *searchString;
@property (nonatomic, readonly) Article *selectedArticle;
@property (nonatomic, readonly) NSInteger currentFolderId;
@property (nonatomic, readonly) NSString *currentTextSelection;
@property (nonatomic, getter=isConnecting, readonly) BOOL connecting;
@property (weak, nonatomic) NSWindow *mainWindow;
-(void)runAppleScript:(NSString *)scriptName;
@property (readonly, nonatomic) NSArray *folders;
-(void)blogWithExternalEditor:(NSString *)externalEditorBundleIdentifier;
-(void)performWebSearch:(SearchMethod *)searchMethod;
-(void)performAllArticlesSearch;
-(void)performWebPageSearch;
-(void)searchArticlesWithString:(NSString *)searchString;

@end
