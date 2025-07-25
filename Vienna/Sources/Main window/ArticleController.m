//
//  ArticleController.m
//  Vienna
//
//  Created by Steve on 5/6/06.
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

#import "ArticleController.h"

@import os.log;

#import "AppController.h"
#import "Preferences.h"
#import "Constants.h"
#import "Database.h"
#import "ArticleRef.h"
#import "OpenReader.h"
#import "ArticleListView.h"
#import "UnifiedDisplayView.h"
#import "FoldersTree.h"
#import "Article.h"
#import "Folder.h"
#import "BackTrackArray.h"
#import "StringExtensions.h"
#import "Vienna-Swift.h"

#define VNA_LOG os_log_create("--", "ArticleController")

static void *VNAArticleControllerObserverContext = &VNAArticleControllerObserverContext;

@interface ArticleController ()

@property (weak, nonatomic) DisclosureView *filterBarDisclosureView;
@property (weak, nonatomic) NSSearchField *filterBarSearchField;

@property (readwrite, copy, nonatomic) NSString *filterModeLabel;
@property (copy, nonatomic) NSString *filterString;

-(NSArray<Article *> *)applyFilter:(NSArray<Article *> *)unfilteredArray;
-(void)setSortColumnIdentifier:(NSString *)str;
-(void)innerMarkReadByArray:(NSArray *)articleArray readFlag:(BOOL)readFlag;
-(void)innerMarkFlaggedByArray:(NSArray *)articleArray flagged:(BOOL)flagged;

@end

@implementation ArticleController {
    NSView<ArticleBaseView> *mainArticleView;
    NSArray *currentArrayOfArticles;
    NSArray *folderArrayOfArticles;
    NSInteger currentFolderId;
    NSDictionary *articleSortSpecifiers;
    NSString *sortColumnIdentifier;
    BackTrackArray *backtrackArray;
    BOOL isBacktracking;
    Article *articleToPreserve;
    NSString *guidOfArticleToSelect;
    BOOL firstUnreadArticleRequired;
    dispatch_queue_t queue;
}

@synthesize mainArticleView, currentArrayOfArticles, folderArrayOfArticles, articleSortSpecifiers, backtrackArray;

/* init
 * Initialise.
 */
-(instancetype)init
{
    if ((self = [super init]) != nil) {
		isBacktracking = NO;
		currentFolderId = -1;
		articleToPreserve = nil;
		guidOfArticleToSelect = nil;
		firstUnreadArticleRequired = NO;
        _filterModeLabel = @"";

		// Set default values to generate article sort descriptors
		articleSortSpecifiers = @{
								  MA_Field_Folder: @{
										  @"key": @"containingFolder.name",
										  @"selector": NSStringFromSelector(@selector(compare:))
										  },
								  MA_Field_Read: @{
										  @"key": @"isRead",
										  @"selector": NSStringFromSelector(@selector(compare:))
										  },
								  MA_Field_Flagged: @{
										  @"key": @"isFlagged",
										  @"selector": NSStringFromSelector(@selector(compare:))
										  },
								  MA_Field_LastUpdate: @{
										  @"key": [@"articleData." stringByAppendingString:MA_Field_LastUpdate],
										  @"selector": NSStringFromSelector(@selector(compare:))
										  },
								  MA_Field_PublicationDate: @{
										  @"key": [@"articleData." stringByAppendingString:MA_Field_PublicationDate],
										  @"selector": NSStringFromSelector(@selector(compare:))
										  },
								  MA_Field_Author: @{
										  @"key": [@"articleData." stringByAppendingString:MA_Field_Author],
										  @"selector": NSStringFromSelector(@selector(caseInsensitiveCompare:))
										  },
								  MA_Field_Headlines: @{
										  @"key": [@"articleData." stringByAppendingString:MA_Field_Subject],
										  @"selector": NSStringFromSelector(@selector(vna_caseInsensitiveNumericCompare:))
										  },
								  MA_Field_Subject: @{
										  @"key": [@"articleData." stringByAppendingString:MA_Field_Subject],
										  @"selector": NSStringFromSelector(@selector(vna_caseInsensitiveNumericCompare:))
										  },
								  MA_Field_Link: @{
										  @"key": [@"articleData." stringByAppendingString:MA_Field_Link],
										  @"selector": NSStringFromSelector(@selector(caseInsensitiveCompare:))
										  },
								  MA_Field_Summary: @{
										  @"key": [@"articleData." stringByAppendingString:MA_Field_Summary],
										  @"selector": NSStringFromSelector(@selector(caseInsensitiveCompare:))
										  },
								  MA_Field_HasEnclosure: @{
										  @"key": @"hasEnclosure",
										  @"selector": NSStringFromSelector(@selector(compare:))
										  },
								  MA_Field_Enclosure: @{
										  @"key": @"enclosure",
										  @"selector": NSStringFromSelector(@selector(caseInsensitiveCompare:))
										  },
								  };

		// Pre-set sort to what was saved in the preferences
		Preferences * prefs = [Preferences standardPreferences];
		[self setSortColumnIdentifier:[prefs stringForKey:MAPref_SortColumn]];
		
		// Create a backtrack array
		backtrackArray = [[BackTrackArray alloc] initWithMaximum:prefs.backTrackQueueSize];
		
		// Register for notifications
		NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
		[nc addObserver:self selector:@selector(handleArticleListContentChange:) name:MA_Notify_ArticleListContentChange object:nil];
        [nc addObserver:self selector:@selector(handleArticleListStateChange:) name:MA_Notify_ArticleListStateChange object:nil];
        [nc addObserver:self
               selector:@selector(folderNameChanged:)
                   name:MA_Notify_FolderNameChanged
                 object:nil];

        NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
        [userDefaults addObserver:self
                       forKeyPath:MAPref_FilterMode
                          options:NSKeyValueObservingOptionNew
                          context:VNAArticleControllerObserverContext];
        [userDefaults addObserver:self
                       forKeyPath:MAPref_ShowFilterBar
                          options:NSKeyValueObservingOptionNew
                          context:VNAArticleControllerObserverContext];

        queue = dispatch_queue_create("uk.co.opencommunity.vienna2.displayRefresh", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

-(void)loadView {
	self.view = [self mainArticleView];
}

/* setLayout
 * Changes the layout of the panes.
 */
-(void)setLayout:(NSInteger)newLayout
{
	Article * currentSelectedArticle = self.selectedArticle;

	switch (newLayout) {
		case VNALayoutReport:
		case VNALayoutCondensed:
			self.mainArticleView = self.articleListView;
			self.filterBarDisclosureView = self.articleListView.filterBarDisclosureView;
			self.filterBarSearchField = self.articleListView.filterBarView.filterSearchField;
			break;

		case VNALayoutUnified:
			self.mainArticleView = self.unifiedListView;
			self.filterBarDisclosureView = self.unifiedListView.filterBarDisclosureView;
			self.filterBarSearchField = self.unifiedListView.filterBarView.filterSearchField;
			break;
	}

    [self setFilterBarState:Preferences.standardPreferences.showFilterBar
              withAnimation:NO];

	[self loadView];
	[Preferences standardPreferences].layout = newLayout;
	if (currentSelectedArticle != nil) {
		[self selectFolderAndArticle:currentFolderId guid:currentSelectedArticle.guid];
		[self ensureSelectedArticle];
	}
    [[NSNotificationCenter defaultCenter] postNotificationName:MA_Notify_ArticleViewChange object:nil];

    self.foldersTree.mainView.nextKeyView = self.mainArticleView;
    if (self.selectedArticle == nil) {
        [self.view.window makeFirstResponder:self.foldersTree.mainView];
    } else {
        [self.view.window makeFirstResponder:self.mainArticleView];
    }

    // TODO: Refactor
    NSTabViewItem *primaryTab = [[NSTabViewItem alloc] initWithIdentifier:@"Articles"];
    primaryTab.label = NSLocalizedString(@"Articles", nil);
    primaryTab.viewController = self;
    APPCONTROLLER.browser.primaryTab = primaryTab;
}

/* currentFolderId
 * Returns the ID of the current folder being displayed by the view.
 */
-(NSInteger)currentFolderId
{
	return currentFolderId;
}

/* markedArticleRange
 * Retrieve an array of selected articles.
 * from the article list.
 */
-(NSArray *)markedArticleRange
{
	return mainArticleView.markedArticleRange;
}

/* saveTableSettings
 * Save selected article and folder
 * and, for relevant layouts, table settings
 */
-(void)saveTableSettings
{
	[mainArticleView saveTableSettings];
}

/* updateVisibleColumns
 * For relevant layouts, adapt table settings
 */
-(void)updateVisibleColumns
{
    if (mainArticleView ==  self.articleListView) {
        [self.articleListView updateVisibleColumns];
    }
}

/* selectedArticle
 * Returns the currently selected article from the article list.
 */
-(Article *)selectedArticle
{
	return mainArticleView.selectedArticle;
}

/* allArticles
 * Returns the current filtered and sorted article array.
 */
-(NSArray *)allArticles
{
	return currentArrayOfArticles;
}

/* ensureSelectedArticle
 * Ensures that an article is selected in the list and that any selected
 * article is scrolled into view.
 */
-(void)ensureSelectedArticle
{
    [mainArticleView ensureSelectedArticle];
}

/* sortColumnIdentifier
 * Returns the name of the column on which we're currently sorting.
 */
-(NSString *)sortColumnIdentifier
{
	return sortColumnIdentifier;
}

/* setSortColumnIdentifier
 * Sets the name of the column on which we're currently sorting.
 */
-(void)setSortColumnIdentifier:(NSString *)str
{
	sortColumnIdentifier = str;
}

/* sortByIdentifier
 * Sort by the column indicated by the specified column name.
 */
-(void)sortByIdentifier:(NSString *)columnName
{
	Preferences * prefs = [Preferences standardPreferences];
	NSMutableArray * descriptors = [NSMutableArray arrayWithArray:prefs.articleSortDescriptors];
	
	if ([sortColumnIdentifier isEqualToString:columnName]) {
		descriptors[0] = [descriptors[0] reversedSortDescriptor];
	} else {
		[self setSortColumnIdentifier:columnName];
		[prefs setObject:sortColumnIdentifier forKey:MAPref_SortColumn];
		NSSortDescriptor * sortDescriptor;
		NSDictionary * specifier = [articleSortSpecifiers valueForKey:sortColumnIdentifier];
		NSUInteger index = [[descriptors valueForKey:@"key"] indexOfObject:[specifier valueForKey:@"key"]];

		if (index == NSNotFound) {
			// Dates should be sorted initially in descending order
			// MIGHT DO : Add a key to articleSortSpecifiers for a default sort order
			BOOL ascending = [columnName isEqualToString:MA_Field_PublicationDate] || [columnName isEqualToString:MA_Field_LastUpdate] ? NO : YES;
			sortDescriptor = [[NSSortDescriptor alloc] initWithKey:[specifier valueForKey:@"key"] ascending:ascending selector:NSSelectorFromString([specifier valueForKey:@"selector"])];
		} else {
			sortDescriptor = descriptors[index];
			[descriptors removeObjectAtIndex:index];
		}
		[descriptors insertObject:sortDescriptor atIndex:0];
	}
	prefs.articleSortDescriptors = descriptors;
	[mainArticleView refreshFolder:VNARefreshSortAndRedraw];
}

/* sortIsAscending
 * Returns YES if the sort direction is currently set to ascending.
 */
-(BOOL)sortIsAscending
{
	Preferences * prefs = [Preferences standardPreferences];
	NSMutableArray * descriptors = [NSMutableArray arrayWithArray:prefs.articleSortDescriptors];
	NSSortDescriptor * sortDescriptor = descriptors[0];
	BOOL ascending = sortDescriptor.ascending;
	
	return ascending;
}

/* sortAscending
 * Sort by the direction indicated.
 */
-(void)sortAscending:(BOOL)newAscending
{
	Preferences * prefs = [Preferences standardPreferences];
	NSMutableArray * descriptors = [NSMutableArray arrayWithArray:prefs.articleSortDescriptors];
	NSSortDescriptor * sortDescriptor = descriptors[0];
	
	BOOL existingAscending = sortDescriptor.ascending;
	if ( newAscending != existingAscending ) {
		descriptors[0] = sortDescriptor.reversedSortDescriptor;
		prefs.articleSortDescriptors = descriptors;
		[mainArticleView refreshFolder:VNARefreshSortAndRedraw];
	}
}

/* sortArticles
 * Re-orders the articles in currentArrayOfArticles by the current sort order
 */
-(void)sortArticles
{
    Preferences *preferences = Preferences.standardPreferences;
    @try {
        NSArray *sortDescriptors = preferences.articleSortDescriptors;
        NSArray *sortedArrayOfArticles  = [currentArrayOfArticles sortedArrayUsingDescriptors:sortDescriptors];
        NSAssert([sortedArrayOfArticles count] == [currentArrayOfArticles count], @"Lost articles from currentArrayOfArticles during sort");
        self.currentArrayOfArticles = sortedArrayOfArticles;
    } @catch (NSException *exception) {
        os_log_error(VNA_LOG, "Exception caught: %{public}@", exception.reason);
        [preferences removeObjectForKey:MAPref_ArticleListSortOrders];
        [preferences removeObjectForKey:MAPref_SortColumn];
        preferences.articleSortDescriptors = nil;
        [self setSortColumnIdentifier:[preferences stringForKey:MAPref_SortColumn]];
    }
}

/* displayFirstUnread
 * Instructs the current article view to display the first unread article
 * in the database.
 */
-(void)displayFirstUnread
{
	// mark current article read
	Article * currentArticle = self.selectedArticle;
	if (currentArticle != nil && !currentArticle.isRead) {
		[self markReadByArray:@[currentArticle] readFlag:YES];
	}

	// If there are any unread articles then select the first one in the
	// first folder.
	if ([Database sharedManager].countOfUnread > 0) {
		// Get the first folder with unread articles.
		NSInteger firstFolderWithUnread = self.foldersTree.firstFolderWithUnread;
		if (firstFolderWithUnread == currentFolderId) {
            [self->mainArticleView selectFirstUnreadInFolder];
		} else {
			// Seed in order to select the first unread article.
			firstUnreadArticleRequired = YES;
			// Select the folder in the tree view.
			[self.foldersTree selectFolder:firstFolderWithUnread];
		}
	}
}

/* displayNextUnread
 * Instructs the current article view to display the next unread article
 * in the database.
 */
-(void)displayNextUnread
{
	// mark current article read
	Article * currentArticle = self.selectedArticle;
	if (currentArticle != nil && !currentArticle.isRead) {
		[self markReadByArray:@[currentArticle] readFlag:YES];
	}

	// If there are any unread articles then select the nexst one
	if ([Database sharedManager].countOfUnread > 0) {
		// Search other articles in the same folder, starting from current position
        if (!mainArticleView.viewNextUnreadInFolder) {
			// If nothing found and smart folder, search if we have other fresh articles from same folder
			Folder * currentFolder = [[Database sharedManager] folderFromID:currentFolderId];
			if (currentFolder.type == VNAFolderTypeSmart || currentFolder.type == VNAFolderTypeTrash || currentFolder.type == VNAFolderTypeSearch) {
                if (!mainArticleView.selectFirstUnreadInFolder) {
					[self displayNextFolderWithUnread];
				}
			} else {
				[self displayNextFolderWithUnread];
			}
		}
	}
}

/* displayNextFolderWithUnread
 * Instructs the current article view to display the next folder with unread articles
 * in the database.
 */
-(void)displayNextFolderWithUnread
{
	NSInteger nextFolderWithUnread = [self.foldersTree nextFolderWithUnread:currentFolderId];
	if (nextFolderWithUnread != -1) {
		// Seed in order to select the first unread article.
		firstUnreadArticleRequired = YES;
		[self.foldersTree selectFolder:nextFolderWithUnread];
	}
}

/* displayFolder
 * This is called after notification of folder selection change
 * Call the current article view to display the specified folder if it
 * is different from the current one.
 */
-(void)displayFolder:(NSInteger)newFolderId
{
    // We don't filter when we switch folders.
    self.filterString = @"";

	if (currentFolderId != newFolderId && newFolderId != 0) {
		// Deselect all in current folder.
		// Otherwise, the new folder might attempt to preserve selection.
		// This can happen with smart folders, which have the same articles as other folders.
		[mainArticleView scrollToArticle:nil];

		currentFolderId = newFolderId;
		[self reloadArrayOfArticles];
	}
    [self setFilterBarPlaceholderStringForFolderID:newFolderId];
}

/* selectFolderAndArticle
 * Select a folder and select a specified article within the folder.
 */
-(void)selectFolderAndArticle:(NSInteger)folderId guid:(NSString *)guid
{
	// If we're in the right folder, select the article
	if (folderId == currentFolderId) {
		if (guid != nil) {
			[mainArticleView scrollToArticle:guid];
		}
	} else {
		// We seed guidOfArticleToSelect so that
		// after notification of folder selection change has been processed,
		// it will select the requisite article on our behalf.
		guidOfArticleToSelect = guid;
		[self.foldersTree selectFolder:folderId];
	}
}

/* reloadArrayOfArticles
 * Reload the folderArrayOfArticles from the current folder and applies the
 * current filter.
 */
-(void)reloadArrayOfArticles
{
    Folder *folder = [[Database sharedManager] folderFromID:currentFolderId];
    NSString *filterString = self.filterString;
    dispatch_sync(queue, ^{
        self.folderArrayOfArticles = [folder articlesWithFilter:filterString];
    });
    Article *article = self.selectedArticle;

    // Make sure selectedArticle hasn't changed since reload started.
    if (articleToPreserve != nil && articleToPreserve != article) {
        if (article != nil && !article.isDeleted) {
            articleToPreserve = article;
        } else {
            articleToPreserve = nil;
        }
    }

    [self->mainArticleView refreshFolder:VNARefreshReapplyFilter];

    if (self->guidOfArticleToSelect != nil) {
        [self->mainArticleView scrollToArticle:self->guidOfArticleToSelect];
        self->guidOfArticleToSelect = nil;
    } else if (self->firstUnreadArticleRequired) {
        [self->mainArticleView selectFirstUnreadInFolder];
        self->firstUnreadArticleRequired = NO;
    }

    // To avoid upsetting the current displayed article after a refresh,
    // we check to see if the selected article is the same
    // and if it has been updated
    Article *currentArticle = self.selectedArticle;
    if (currentArticle == article &&
        [[Preferences standardPreferences] boolForKey:MAPref_CheckForUpdatedArticles]
        && currentArticle.isRevised)
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:MA_Notify_ArticleViewChange object:nil];
    }
} // reloadArrayOfArticles

/* refilterArrayOfArticles
 * Reapply the current filter to the article array.
 */
-(void)refilterArrayOfArticles
{
	self.currentArrayOfArticles = [self applyFilter:folderArrayOfArticles];
}

/* applyFilter
 * Apply the active filter to unfilteredArray and return the filtered array.
 * This is done here rather than in the folder management code for simplicity.
 */
-(NSArray<Article *> *)applyFilter:(NSArray<Article *> *)unfilteredArray
{
	NSMutableArray * filteredArray = [NSMutableArray arrayWithArray:unfilteredArray];
	
	NSString * guidOfArticleToPreserve = articleToPreserve.guid;
	
	NSInteger filterMode = [Preferences standardPreferences].filterMode;
	for (NSInteger index = filteredArray.count - 1; index >= 0; --index) {
		Article * article = filteredArray[index];
		if (guidOfArticleToPreserve != nil
			&& article.folderId == articleToPreserve.folderId 
			&& [article.guid isEqualToString:guidOfArticleToPreserve]) {
			guidOfArticleToPreserve = nil;
		} else if ([self filterArticle:article usingMode:filterMode] == false) {
			[filteredArray removeObjectAtIndex:index];
        }
	}
	
	if (guidOfArticleToPreserve != nil) {
		[filteredArray addObject:articleToPreserve];
	}
	articleToPreserve = nil;
	
	return [filteredArray copy];
}

/* markDeletedUndo
 * Undo handler to restore a series of deleted articles.
 */
-(void)markDeletedUndo:(id)anObject
{
	[self markDeletedByArray:(NSArray *)anObject deleteFlag:NO];
}

/* markUndeletedUndo
 * Undo handler to delete a series of articles.
 */
-(void)markUndeletedUndo:(id)anObject
{
	[self markDeletedByArray:(NSArray *)anObject deleteFlag:YES];
}

/* markDeletedByArray
 * Helper function. Takes as an input an array of articles and deletes or restores
 * the articles.
 */
-(void)markDeletedByArray:(NSArray *)articleArray deleteFlag:(BOOL)deleteFlag
{	
	// Set up to undo this action
	NSUndoManager * undoManager = NSApp.mainWindow.undoManager;
	SEL markDeletedUndoAction = deleteFlag ? @selector(markDeletedUndo:) : @selector(markUndeletedUndo:);
	[undoManager registerUndoWithTarget:self selector:markDeletedUndoAction object:articleArray];
    [undoManager setActionName:NSLocalizedStringWithDefaultValue(@"delete.undoAction",
                                                                 nil,
                                                                 NSBundle.mainBundle,
                                                                 @"Delete",
                                                                 @"Name of an undo/redo action in the menu bar's Edit menu.")];
	
	// We will make a new copy of currentArrayOfArticles and folderArrayOfArticles with the selected articles removed.
	NSMutableArray * currentArrayCopy = [NSMutableArray arrayWithArray:currentArrayOfArticles];
	NSMutableArray * folderArrayCopy = [NSMutableArray arrayWithArray:folderArrayOfArticles];
	__block BOOL needReload = NO;
	
	NSString * guidToSelect = nil;

    // if we mark deleted, mark also read and unflagged
	if (deleteFlag) {
	    [self innerMarkReadByRefsArray:articleArray readFlag:YES];
        [self innerMarkFlaggedByArray:articleArray flagged:NO];
		
		Article * firstArticle = articleArray.firstObject;
		// Should always be true
		if (firstArticle != nil) {
			// We want to select the next non-deleted article
			NSUInteger articleIndex = [currentArrayOfArticles indexOfObject:firstArticle];
			if (articleIndex != NSNotFound) {
				NSUInteger count = currentArrayOfArticles.count;
				for (NSUInteger i = articleIndex + 1; i < count; ++i) {
                    Article * nextArticle = currentArrayOfArticles[i];
					if (![articleArray containsObject:nextArticle]) {
						guidToSelect = nextArticle.guid;
						break;
					}
				}
				
				// Otherwise, we want to select the previous article.
				if (guidToSelect == nil && articleIndex > 0) {
                    Article * nextArticle = currentArrayOfArticles[articleIndex - 1];
					guidToSelect = nextArticle.guid;
				}
				
				// Deselect all now, we will select article after refresh
				[mainArticleView scrollToArticle:nil];
			}
		}
	}

	// Iterate over every selected article in the table and set the deleted
	// flag on the article while simultaneously removing it from our copies
	for (Article * theArticle in articleArray) {
		[[Database sharedManager] markArticleDeleted:theArticle isDeleted:deleteFlag];
		if (![currentArrayOfArticles containsObject:theArticle]) {
			needReload = YES;
		} else if (deleteFlag && (currentFolderId != [Database sharedManager].trashFolderId)) {
			[currentArrayCopy removeObject:theArticle];
			[folderArrayCopy removeObject:theArticle];
		} else if (!deleteFlag && (currentFolderId == [Database sharedManager].trashFolderId)) {
			[currentArrayCopy removeObject:theArticle];
			[folderArrayCopy removeObject:theArticle];
		} else {
			needReload = YES;
		}
	}

	self.currentArrayOfArticles = currentArrayCopy;
	self.folderArrayOfArticles = folderArrayCopy;
	if (needReload) {
		[self reloadArrayOfArticles];
	} else {
		[mainArticleView refreshFolder:VNARefreshRedrawList];
		if (currentArrayOfArticles.count > 0u) {
			if (guidToSelect != nil) {
				[mainArticleView scrollToArticle:guidToSelect];
			}
			[mainArticleView ensureSelectedArticle];
		} else {
			[NSApp.mainWindow makeFirstResponder:self.foldersTree.mainView];
		}
	}
}

/* deleteArticlesByArray
 * Physically delete all selected articles in the article list.
 */
-(void)deleteArticlesByArray:(NSArray *)articleArray
{		
	// Make a new copy of currentArrayOfArticles and folderArrayOfArticles with the selected article removed.
	NSMutableArray * currentArrayCopy = [NSMutableArray arrayWithArray:currentArrayOfArticles];
	NSMutableArray * folderArrayCopy = [NSMutableArray arrayWithArray:folderArrayOfArticles];
	
	[self innerMarkReadByRefsArray:articleArray readFlag:YES];
	
	NSString * guidToSelect = nil;
	Article * firstArticle = articleArray.firstObject;
	// Should always be true
	if (firstArticle != nil) {
		// We want to select the next non-deleted article
		NSUInteger articleIndex = [currentArrayOfArticles indexOfObject:firstArticle];
		if (articleIndex != NSNotFound) {
			NSUInteger count = currentArrayOfArticles.count;
			for (NSUInteger i = articleIndex + 1; i < count; ++i) {
                Article * nextArticle = currentArrayOfArticles[i];
				if (![articleArray containsObject:nextArticle]) {
					guidToSelect = nextArticle.guid;
					break;
				}
			}
			
			// Otherwise, we want to select the previous article.
			if (guidToSelect == nil && articleIndex > 0) {
                Article * nextArticle = currentArrayOfArticles[articleIndex - 1];
				guidToSelect = nextArticle.guid;
			}
			
			// Deselect all now, we will select article after refresh
			[mainArticleView scrollToArticle:nil];
		}
	}

	// Iterate over every selected article in the table and remove it from
	// the database.
	for (Article * theArticle in articleArray) {
		if ([[Database sharedManager] deleteArticle:theArticle]) {
			[currentArrayCopy removeObject:theArticle];
			[folderArrayCopy removeObject:theArticle];
		}
	}
	self.currentArrayOfArticles = currentArrayCopy;
	self.folderArrayOfArticles = folderArrayCopy;
	[mainArticleView refreshFolder:VNARefreshRedrawList];

	// Ensure there's a valid selection
    if (currentArrayOfArticles.count > 0u) {
		if (guidToSelect != nil) {
			[mainArticleView scrollToArticle:guidToSelect];
		}
		[mainArticleView ensureSelectedArticle];
    } else {
		[NSApp.mainWindow makeFirstResponder:self.foldersTree.mainView];
    }
}

- (void)changeFiltering:(NSMenuItem *)sender
{
    NSInteger tag = sender.tag;
    Preferences.standardPreferences.filterMode = tag;
    if (tag == VNAFilterAll) {
        self.filterModeLabel = @"";
    } else {
        self.filterModeLabel = sender.title;
    }
}

/* markUnflagUndo
 * Undo handler to un-flag an array of articles.
 */
-(void)markUnflagUndo:(id)anObject
{
	[self markFlaggedByArray:(NSArray *)anObject flagged:NO];
}

/* markFlagUndo
 * Undo handler to flag an array of articles.
 */
-(void)markFlagUndo:(id)anObject
{
	[self markFlaggedByArray:(NSArray *)anObject flagged:YES];
}

/* markFlaggedByArray
 * Mark the specified articles in articleArray as flagged.
 */
-(void)markFlaggedByArray:(NSArray *)articleArray flagged:(BOOL)flagged
{	
	// Set up to undo this action
	NSUndoManager * undoManager = NSApp.mainWindow.undoManager;
	SEL markFlagUndoAction = flagged ? @selector(markUnflagUndo:) : @selector(markFlagUndo:);
	[undoManager registerUndoWithTarget:self selector:markFlagUndoAction object:articleArray];
	[undoManager setActionName:NSLocalizedString(@"Flag", nil)];

    [self innerMarkFlaggedByArray:articleArray flagged:flagged];
	[mainArticleView refreshFolder:VNARefreshRedrawList];
}

/* innerMarkFlaggedByArray
 * Marks all articles in the specified array flagged or unflagged.
 */
-(void)innerMarkFlaggedByArray:(NSArray *)articleArray flagged:(BOOL)flagged
{
	for (Article * theArticle in articleArray) {
		Folder *myFolder = [[Database sharedManager] folderFromID:theArticle.folderId];
		if (myFolder.type == VNAFolderTypeOpenReader) {
			[[OpenReader sharedManager] markStarred:theArticle starredFlag:flagged];
		}
		[[Database sharedManager] markArticleFlagged:theArticle.folderId
                                                guid:theArticle.guid
                                           isFlagged:flagged];
        theArticle.flagged = flagged;
	}
}

/* markUnreadUndo
 * Undo handler to mark an array of articles unread.
 */
-(void)markUnreadUndo:(id)anObject
{
	[self markAllReadByReferencesArray:(NSArray *)anObject readFlag:NO];
}

/* markReadUndo
 * Undo handler to mark an array of articles read.
 */
-(void)markReadUndo:(id)anObject
{
	[self markAllReadByReferencesArray:(NSArray *)anObject readFlag:YES];
}

/* markReadByArray
 * Helper function. Takes as an input an array of articles and marks those articles read or unread.
 */
-(void)markReadByArray:(NSArray *)articleArray readFlag:(BOOL)readFlag
{
	// Set up to undo this action
	NSUndoManager * undoManager = NSApp.mainWindow.undoManager;	
	SEL markReadUndoAction = readFlag ? @selector(markUnreadUndo:) : @selector(markReadUndo:);
	[undoManager registerUndoWithTarget:self selector:markReadUndoAction object:articleArray];
	[undoManager setActionName:NSLocalizedStringWithDefaultValue(@"markRead.undoAction",
																 nil,
																 NSBundle.mainBundle,
																 @"Mark Read",
																 @"Name of an undo/redo action in the menu bar's Edit menu.")];

    [self innerMarkReadByArray:articleArray readFlag:readFlag];

	[mainArticleView refreshFolder:VNARefreshRedrawList];
}

/* innerMarkReadByArray
 * Marks all articles in the specified array read or unread.
 */
-(void)innerMarkReadByArray:(NSArray *)articleArray readFlag:(BOOL)readFlag
{
	for (Article * theArticle in articleArray) {
		NSInteger folderId = theArticle.folderId;
		if (theArticle.isRead != readFlag) {
			if ([[Database sharedManager] folderFromID:folderId].type == VNAFolderTypeOpenReader) {
				[[OpenReader sharedManager] markRead:theArticle readFlag:readFlag];
			} else {
				[[Database sharedManager] markArticleRead:folderId guid:theArticle.guid isRead:readFlag];
				theArticle.read = readFlag;
			}
		}
	}
}

/* innerMarkReadByRefsArray
 * Marks all articles in the specified references array read or unread.
 */
-(void)innerMarkReadByRefsArray:(NSArray *)articleArray readFlag:(BOOL)readFlag
{
	Database * db = [Database sharedManager];

	for (ArticleReference * articleRef in articleArray) {
		NSInteger folderId = articleRef.folderId;
		Folder * folder = [db folderFromID:folderId];
		if (folder.type == VNAFolderTypeOpenReader){
			Article * article = [folder articleFromGuid:articleRef.guid];
			if (article != nil) {
                [[OpenReader sharedManager] markRead:article readFlag:readFlag];
			}
		} else {
			[db markArticleRead:folderId guid:articleRef.guid isRead:readFlag];
		}
	}
}

/* markAllReadUndo
 * Undo the most recent Mark All Read.
 */
-(void)markAllReadUndo:(id)anObject
{
	[self markAllReadByReferencesArray:(NSArray *)anObject readFlag:NO];
}

/* markAllReadRedo
 * Redo the most recent Mark All Read.
 */
-(void)markAllReadRedo:(id)anObject
{
	[self markAllReadByReferencesArray:(NSArray *)anObject readFlag:YES];
}

/* markAllFoldersReadByArray
 * Given an array of folders, mark all the articles in those folders as read.
 */
-(void)markAllFoldersReadByArray:(NSArray *)folderArray
{
    NSArray * refArray = [self wrappedMarkAllFoldersReadInArray:folderArray];
    if (refArray != nil && refArray.count > 0) {
        NSUndoManager * undoManager = NSApp.mainWindow.undoManager;
        [undoManager registerUndoWithTarget:self selector:@selector(markAllReadUndo:) object:refArray];
        [undoManager setActionName:NSLocalizedString(@"Mark All Read", nil)];
    }

    // We need to refresh view if current folder is Group, Smart or Search folder
    Folder * currentFolder = [[Database sharedManager] folderFromID:currentFolderId];
    if (currentFolder != nil && !currentFolder.isRSSFolder && !currentFolder.isOpenReaderFolder) {
        articleToPreserve = self.selectedArticle;
        [self reloadArrayOfArticles];
    } else {
        [mainArticleView refreshFolder:VNARefreshRedrawList];
    }
}

/* wrappedMarkAllFoldersReadInArray
 * Given an array of folders, mark all the articles in those folders as read and
 * return a reference array listing all the articles that were actually marked.
 */
-(NSArray<ArticleReference *> *)wrappedMarkAllFoldersReadInArray:(NSArray *)folderArray
{
	NSMutableArray * refArray = [NSMutableArray array];
	
	for (Folder * folder in folderArray) {
		NSInteger folderId = folder.itemId;
		if (folder.type == VNAFolderTypeGroup) {
			[refArray addObjectsFromArray:[self wrappedMarkAllFoldersReadInArray:[[Database sharedManager] arrayOfFolders:folderId]]];
		} else if (folder.type == VNAFolderTypeRSS) {
			[refArray addObjectsFromArray:[folder arrayOfUnreadArticlesRefs]];
			[[Database sharedManager] markFolderRead:folderId];
		} else if (folder.type == VNAFolderTypeOpenReader) {
			[refArray addObjectsFromArray:[folder arrayOfUnreadArticlesRefs]];
			[[OpenReader sharedManager] markAllReadInFolder:folder];
		} else {
		    // For smart folders, we only mark read articles which should be visible with current filters
            NSString *filterString = self.filterString;
            NSArray * articleArray = [self applyFilter:[folder articlesWithFilter:filterString]];
            [self innerMarkReadByArray:articleArray readFlag:YES];
            for (id article in articleArray) {
                [refArray addObject:[ArticleReference makeReference:(Article *)article]];
            }
		}
	}
	return [refArray copy];
}

/* markAllReadByReferencesArray
 * Given an array of references, mark all those articles read or unread.
 */
-(void)markAllReadByReferencesArray:(NSArray *)refArray readFlag:(BOOL)readFlag
{
	Database * dbManager = [Database sharedManager];
	
	// Set up to undo or redo this action
	NSUndoManager * undoManager = NSApp.mainWindow.undoManager;
	SEL markAllReadUndoAction = readFlag ? @selector(markAllReadUndo:) : @selector(markAllReadRedo:);
	[undoManager registerUndoWithTarget:self selector:markAllReadUndoAction object:refArray];
	[undoManager setActionName:NSLocalizedString(@"Mark All Read", nil)];
	
	for (ArticleReference *ref in refArray) {
		NSInteger folderId = ref.folderId;
		NSString * theGuid = ref.guid;
		Folder * folder = [dbManager folderFromID:folderId];
        if (folder.type == VNAFolderTypeOpenReader) {
        	Article * article = [folder articleFromGuid:theGuid];
        	if (article != nil) {
			    [[OpenReader sharedManager] markRead:article readFlag:readFlag];
			}
        } else {
			[dbManager markArticleRead:folderId guid:theGuid isRead:readFlag];
		}
	}
}

/* addBacktrack
 * Add the specified article to the backtrack queue. The folder is taken from
 * the controller's current folder index.
 */
-(void)addBacktrack:(NSString *)guid
{
	if (!isBacktracking) {
		[backtrackArray addToQueue:currentFolderId guid:guid];
	}
}

/* goForward
 * Move forward through the backtrack queue.
 */
-(void)goForward
{
	NSInteger folderId;
	NSString * guid;
	
	if ([backtrackArray nextItemAtQueue:&folderId guidPointer:&guid]) {
		isBacktracking = YES;
		[self selectFolderAndArticle:folderId guid:guid];
		isBacktracking = NO;
	}
}

/* goBack
 * Move backward through the backtrack queue.
 */
-(void)goBack
{
	NSInteger folderId;
	NSString * guid;
	
	if ([backtrackArray previousItemAtQueue:&folderId guidPointer:&guid]) {
		isBacktracking = YES;
		[self selectFolderAndArticle:folderId guid:guid];
		isBacktracking = NO;
	}
}

/* canGoForward
 * Return TRUE if we can go forward in the backtrack queue.
 */
-(BOOL)canGoForward
{
	return !backtrackArray.atEndOfQueue;
}

/* canGoBack
 * Return TRUE if we can go backward in the backtrack queue.
 */
-(BOOL)canGoBack
{
	return !backtrackArray.atStartOfQueue;
}

/* reportLayout
 * Switch to report layout
 */
- (IBAction)reportLayout:(id)sender
{
    [self setLayout:VNALayoutReport];
    [self.mainArticleView refreshFolder:VNARefreshRedrawList];
}

/* condensedLayout
 * Switch to condensed layout
 */
- (IBAction)condensedLayout:(id)sender
{
    [self setLayout:VNALayoutCondensed];
    [self.mainArticleView refreshFolder:VNARefreshRedrawList];
}

/* unifiedLayout
 * Switch to unified layout.
 */
- (IBAction)unifiedLayout:(id)sender
{
    [self setLayout:VNALayoutUnified];
    [self.mainArticleView refreshFolder:VNARefreshRedrawList];
}

/* handleArticleListStateChange
* Called if a folder content has changed
* but we don't need to add new articles
*/
-(void)handleArticleListStateChange:(NSNotification *)nc
{
    NSInteger folderId = ((NSNumber *)nc.object).integerValue;
    Folder * currentFolder = [[Database sharedManager] folderFromID:currentFolderId];
    if ((folderId == currentFolderId) || (currentFolder.type != VNAFolderTypeRSS && currentFolder.type != VNAFolderTypeOpenReader)) {
        [mainArticleView refreshFolder:VNARefreshRedrawList];
    }
}

/* handleArticleListContentChange
 * called after a refresh
 * or any other event which may have added a removed an article
 * to the current folder
 */
-(void)handleArticleListContentChange:(NSNotification *)note
{
    NSInteger folderId = ((NSNumber *)note.object).integerValue;
    Folder * currentFolder = [[Database sharedManager] folderFromID:currentFolderId];
    if ((folderId == currentFolderId) || (currentFolder.type != VNAFolderTypeRSS && currentFolder.type != VNAFolderTypeOpenReader)) {
        // With automatic refresh and automatic mark read,
        // the article you're current reading can disappear.
        // For example, if you're reading in the Unread Articles smart folder.
        // So make sure we keep this article around.
        articleToPreserve = self.selectedArticle;
        [self reloadArrayOfArticles];
    }
}

- (void)folderNameChanged:(NSNotification *)notification
{
    NSNumber *folderID = notification.object;
    [self setFilterBarPlaceholderStringForFolderID:folderID.integerValue];
}

// MARK: Filter article

- (NSString *)filterString
{
    return self.filterBarSearchField.stringValue;
}

- (void)setFilterString:(NSString *)filterString
{
    self.filterBarSearchField.stringValue = filterString;
}

- (void)setFilterBarPlaceholderStringForFolderID:(NSInteger)folderID
{
    NSInteger currentFolderID = self.currentFolderId;
    if (folderID != currentFolderID) {
        return;
    }

    NSString *placeholderString = @"";
    if (currentFolderID >= 0) {
        Folder *folder = [Database.sharedManager folderFromID:currentFolderID];
        placeholderString = [NSString stringWithFormat:NSLocalizedString(@"Filter in %@", nil),
                                                       folder.name];
    }
    self.filterBarSearchField.placeholderString = placeholderString;
}

/* showHideFilterBar
 * Toggle the filter bar on/off.
 */
- (IBAction)showHideFilterBar:(id)sender
{
    BOOL isVisible = self.filterBarDisclosureView.isDisclosed;
    [self setFilterBarState:!isVisible withAnimation:YES];
    Preferences.standardPreferences.showFilterBar = !isVisible;
}

- (IBAction)hideFilterBar:(id)sender
{
    [self setFilterBarState:NO withAnimation:YES];
    Preferences.standardPreferences.showFilterBar = NO;
}

- (void)searchUsingFilterField:(NSSearchField *)searchField
{
    self.filterString = searchField.stringValue;
    [self.mainArticleView performFindPanelAction:NSFindPanelActionNext];
}

/* setFilterBarState
 * Show or hide the filter bar. The withAnimation flag specifies whether or not we do the
 * animated show/hide. It should be set to NO for actions that are not user initiated as
 * otherwise the background rendering of the control can cause complications.
 */
- (void)setFilterBarState:(BOOL)showFilterBar withAnimation:(BOOL)doAnimate
{
    BOOL isFilterVisible = self.filterBarDisclosureView.isDisclosed;
    if (showFilterBar && !isFilterVisible) {
        [self.filterBarDisclosureView disclose:doAnimate];

        // Hook up the Tab ordering so Tab from the search field goes to the
        // article view.
        self.foldersTree.mainView.nextKeyView = self.filterBarSearchField;
        self.filterBarSearchField.nextKeyView = self.mainArticleView;

        // Set focus only if this was user initiated
        if (doAnimate) {
            [self.view.window makeFirstResponder:self.filterBarSearchField];
        }
    } else if (!showFilterBar && isFilterVisible) {
        [self.filterBarDisclosureView collapse:doAnimate];

        // Fix up the tab ordering
        self.foldersTree.mainView.nextKeyView = self.mainArticleView;

        // Clear the filter, otherwise we end up with no way remove it!
        self.filterString = @"";
        if (doAnimate) {
            [self searchUsingFilterField:self.filterBarSearchField];

            // If the focus was originally on the filter bar then we should
            // move it to the message list
            if ([self.view.window.firstResponder isEqual:self.view.window]) {
                [self.view.window makeFirstResponder:self.mainArticleView];
            }
        }
    }
}

- (BOOL)filterArticle:(Article *)article usingMode:(NSInteger)filterMode {
    switch (filterMode) {
        case VNAFilterUnread:
            return !article.isRead;
        case VNAFilterLastRefresh: {
            return article.status == ArticleStatusNew || article.status == ArticleStatusUpdated;
        }
        case VNAFilterToday:
            return [NSCalendar.currentCalendar isDateInToday:article.lastUpdate];
        case VNAFilterTime48h: {
            NSDate *twoDaysAgo = [NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay
                                                                        value:-2
                                                                       toDate:[NSDate date]
                                                                      options:0];
            return [article.lastUpdate compare:twoDaysAgo] != NSOrderedAscending;
        }
        case VNAFilterFlagged:
            return article.isFlagged;
        case VNAFilterUnreadOrFlagged:
            return (!article.isRead || article.isFlagged);
        default:
            return true;
    }
}

// MARK: Event handling

- (BOOL)vna_canHandleEvent:(NSEvent *)event
{
    if (event.type != NSEventTypeKeyDown && event.characters.length != 1) {
        return [super vna_canHandleEvent:event];
    }
    unichar keyChar = [event.characters characterAtIndex:0];
    if (keyChar == 'f' || keyChar == 'F') {
        return YES;
    }
    return [super vna_canHandleEvent:event];
}

- (BOOL)vna_handleEvent:(NSEvent *)event
{
    if (event.type != NSEventTypeKeyDown && event.characters.length != 1) {
        return [super vna_handleEvent:event];
    }
    unichar keyChar = [event.characters characterAtIndex:0];
    if (keyChar == 'f' || keyChar == 'F') {
        if (self.filterBarDisclosureView.isDisclosed) {
            [self.view.window makeFirstResponder:self.filterBarSearchField];
        } else {
            [self setFilterBarState:YES withAnimation:YES];
            Preferences.standardPreferences.showFilterBar = YES;
        }
        return YES;
    }
    return [super vna_handleEvent:event];
}

// MARK: Key-value observation

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    if (context != VNAArticleControllerObserverContext) {
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
        return;
    }

    if ([keyPath isEqualToString:MAPref_FilterMode]) {
        // Update the list of articles when the user changes the filter.
        @synchronized(mainArticleView) {
            [mainArticleView refreshFolder:VNARefreshReapplyFilter];
        }
    } else if ([keyPath isEqualToString:MAPref_ShowFilterBar]) {
        NSNumber *showFilterBar = change[NSKeyValueChangeNewKey];
        [self setFilterBarState:showFilterBar.boolValue withAnimation:YES];
    }
}

// MARK: NSMenuItemValidation

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL action = menuItem.action;
    if (action == @selector(reportLayout:)) {
        VNALayout layout = Preferences.standardPreferences.layout;
        menuItem.state = (layout == VNALayoutReport) ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    } else if (action == @selector(condensedLayout:)) {
        VNALayout layout = Preferences.standardPreferences.layout;
        menuItem.state = (layout == VNALayoutCondensed) ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    } else if (action == @selector(unifiedLayout:)) {
        VNALayout layout = Preferences.standardPreferences.layout;
        menuItem.state = (layout == VNALayoutUnified) ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    } else if (action == @selector(changeFiltering:)) {
        VNAFilter filterMode = Preferences.standardPreferences.filterMode;
        menuItem.state = (menuItem.tag == filterMode) ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    } else if (action == @selector(showHideFilterBar:)) {
        if (self.filterBarDisclosureView.isDisclosed) {
            menuItem.title = NSLocalizedString(@"Hide Filter Bar", nil);
        } else {
            menuItem.title = NSLocalizedString(@"Show Filter Bar", nil);
        }
        return YES;
    }
    os_log_debug(VNA_LOG, "Unhandled menu-item validation for menu item %@", menuItem);
    return NO;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
    [userDefaults removeObserver:self
                      forKeyPath:MAPref_FilterMode
                         context:VNAArticleControllerObserverContext];
    [userDefaults removeObserver:self
                      forKeyPath:MAPref_ShowFilterBar
                         context:VNAArticleControllerObserverContext];
}

@end
