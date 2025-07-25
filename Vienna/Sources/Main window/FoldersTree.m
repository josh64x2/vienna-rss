//
//  FoldersTree.m
//  Vienna
//
//  Created by Steve on Sat Jan 24 2004.
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

#import "FoldersTree.h"

#import "AppController.h"
#import "Constants.h"
#import "Preferences.h"
#import "HelperFunctions.h"
#import "StringExtensions.h"
#import "FeedListConstants.h"
#import "FolderView.h"
#import "FeedListCellView.h"
#import "OpenReader.h"
#import "Database.h"
#import "TreeNode.h"
#import "Folder.h"
#import "Vienna-Swift.h"

NSString * const MAPref_FeedListSizeMode = @"FeedListSizeMode";
NSString * const MAPref_ShowFeedsWithUnreadItemsInBold = @"ShowFeedsWithUnreadItemsInBold";

static void *VNAFoldersTreeObserverContext = &VNAFoldersTreeObserverContext;

@interface FoldersTree ()

@property (readonly, nonatomic) NSArray *archiveState;
@property (nonatomic) TreeNode *rootNode;
@property (nonatomic) BOOL blockSelectionHandler;

@property (nullable, weak) NSText *fieldEditor;

-(void)unarchiveState:(NSArray *)stateArray;
-(void)reloadDatabase:(NSArray *)stateArray;
-(BOOL)loadTree:(NSArray *)listOfFolders rootNode:(TreeNode *)node;
-(void)setManualSortOrderForNode:(TreeNode *)node;
-(void)handleDoubleClick:(id)sender;
-(void)handleAutoSortFoldersTreeChange:(NSNotification *)nc;
-(void)handleFolderAdded:(NSNotification *)nc;
-(void)handleFolderNameChange:(NSNotification *)nc;
-(void)handleFolderUpdate:(NSNotification *)nc;
-(void)handleFolderDeleted:(NSNotification *)nc;
-(void)handleShowFolderImagesChange:(NSNotification *)nc;
-(void)reloadFolderItem:(id)node reloadChildren:(BOOL)flag;
-(void)expandToParent:(TreeNode *)node;
-(BOOL)moveFolders:(NSArray *)array withGoogleSync:(BOOL)sync;

@end

@implementation FoldersTree

- (instancetype)init
{
    self = [super init];

	if (self) {
		// Root node is never displayed since we always display from
		// the second level down. It simply provides a convenient way
		// of containing the other nodes.
		_rootNode = [[TreeNode alloc] init:nil atIndex:0 folder:nil canHaveChildren:YES];
		_blockSelectionHandler = NO;
	}

	return self;
}

/* initialiseFoldersTree
 * Do the things to initialize the folder tree from the database
 */
-(void)initialiseFoldersTree
{
	// Allow a second click in a node to edit the node
	self.outlineView.doubleAction = @selector(handleDoubleClick:);
	self.outlineView.target = self;

	// Initially size the outline view column to be the correct width
	[self.outlineView sizeLastColumnToFit];

    NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
    [self updateCellSize:[userDefaults integerForKey:MAPref_FeedListSizeMode]];

	// Register for dragging
	[self.outlineView registerForDraggedTypes:@[VNAPasteboardTypeFolderList, VNAPasteboardTypeRSSSource, VNAPasteboardTypeWebURLsWithTitles, NSPasteboardTypeString]];
	[self.outlineView setVerticalMotionCanBeginDrag:YES];
	
	// Make sure selected row is visible
	[self.outlineView scrollRowToVisible:self.outlineView.selectedRow];

    self.outlineView.accessibilityValueDescription = NSLocalizedString(@"Folders", nil);
	
	self.blockSelectionHandler = YES;
	[self reloadDatabase:[[Preferences standardPreferences] arrayForKey:MAPref_FolderStates]];
	self.blockSelectionHandler = NO;

	// Register for notifications
	NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(handleFolderUpdate:) name:MA_Notify_FoldersUpdated object:nil];
	[nc addObserver:self selector:@selector(handleFolderNameChange:) name:MA_Notify_FolderNameChanged object:nil];
	[nc addObserver:self selector:@selector(handleFolderAdded:) name:MA_Notify_FolderAdded object:nil];
	[nc addObserver:self selector:@selector(handleFolderDeleted:) name:VNADatabaseDidDeleteFolderNotification object:nil];
	[nc addObserver:self selector:@selector(handleShowFolderImagesChange:) name:MA_Notify_ShowFolderImages object:nil];
	[nc addObserver:self selector:@selector(handleAutoSortFoldersTreeChange:) name:MA_Notify_AutoSortFoldersTreeChange object:nil];
    [nc addObserver:self selector:@selector(handleOpenReaderFolderChange:) name:MA_Notify_OpenReaderFolderChange object:nil];

    [userDefaults addObserver:self
                   forKeyPath:MAPref_FeedListSizeMode
                      options:0
                      context:VNAFoldersTreeObserverContext];
    [userDefaults addObserver:self
                   forKeyPath:MAPref_ShowFeedsWithUnreadItemsInBold
                      options:0
                      context:VNAFoldersTreeObserverContext];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];

    NSUserDefaults *userDefaults;
    [userDefaults removeObserver:self
                      forKeyPath:MAPref_FeedListSizeMode
                         context:VNAFoldersTreeObserverContext];
    [userDefaults removeObserver:self
                      forKeyPath:MAPref_ShowFeedsWithUnreadItemsInBold
                         context:VNAFoldersTreeObserverContext];
}

-(void)handleOpenReaderFolderChange:(NSNotification *)nc
{
    // No need to sync with OpenReader server because this is triggered when
    // folder layout has changed at server level. Making a sync call would be redundant.
    [self moveFolders:nc.object withGoogleSync:NO];
}

/* reloadDatabase
 * Refresh the folders tree and restore the specified archived state
 */
-(void)reloadDatabase:(NSArray *)stateArray
{
    [self.rootNode removeChildren];
    if (![self loadTree:[[Database sharedManager] arrayOfFolders:VNAFolderTypeRoot] rootNode:self.rootNode]) {
        // recover from problems by switching back to alphabetical auto sort of folders…
        Preferences *prefs = [Preferences standardPreferences];
        NSInteger selectedSortMethod = prefs.foldersTreeSortMethod;
        prefs.foldersTreeSortMethod = VNAFolderSortByName;
        [self.rootNode removeChildren];
        [self loadTree:[[Database sharedManager] arrayOfFolders:VNAFolderTypeRoot] rootNode:self.rootNode];
        // then restore user choice regarding sort method
        prefs.foldersTreeSortMethod = selectedSortMethod;
    }
    [self.outlineView reloadData];
    [self unarchiveState:stateArray];
}

/* saveFolderSettings
 * Preserve the expanded/collapsed and selection state of the folders list
 * into the user's preferences.
 */
-(void)saveFolderSettings
{
	[[Preferences standardPreferences] setArray:self.archiveState forKey:MAPref_FolderStates];
}

/* archiveState
 * Creates an NSArray of states for every item in the tree that has a non-normal state.
 */
-(NSArray *)archiveState
{
	NSMutableArray * archiveArray = [NSMutableArray arrayWithCapacity:16];
	NSInteger count = self.outlineView.numberOfRows;
	NSInteger index;

	for (index = 0; index < count; ++index) {
		TreeNode * node = (TreeNode *)[self.outlineView itemAtRow:index];
		BOOL isItemExpanded = [self.outlineView isItemExpanded:node];
		BOOL isItemSelected = [self.outlineView isRowSelected:index];

		if (isItemExpanded || isItemSelected) {
			NSDictionary * newDict = [NSMutableDictionary dictionary];
			[newDict setValue:@(node.nodeId) forKey:@"NodeID"];
			[newDict setValue:@(isItemExpanded) forKey:@"ExpandedState"];
			[newDict setValue:@(isItemSelected) forKey:@"SelectedState"];
			[archiveArray addObject:newDict];
		}
	}
	return [archiveArray copy];
}

/* unarchiveState
 * Unarchives an array of states.
 * BUGBUG: Restoring multiple selections is not working.
 */
-(void)unarchiveState:(NSArray *)stateArray
{
	for (NSDictionary * dict in stateArray) {
		NSInteger folderId = [[dict valueForKey:@"NodeID"] integerValue];
		TreeNode * node = [self.rootNode nodeFromID:folderId];
		if (node != nil) {
			BOOL doExpandItem = [[dict valueForKey:@"ExpandedState"] boolValue];
			BOOL doSelectItem = [[dict valueForKey:@"SelectedState"] boolValue];
			if ([self.outlineView isExpandable:node] && doExpandItem) {
				[self.outlineView expandItem:node];
			}
			if (doSelectItem) {
				NSInteger row = [self.outlineView rowForItem:node];
				if (row >= 0) {
					NSIndexSet * indexes = [NSIndexSet indexSetWithIndex:(NSUInteger)row];
					[self.outlineView selectRowIndexes:indexes byExtendingSelection:YES];
				}
			}
		}
	}
	[self.outlineView sizeToFit];
}

/* loadTree
 * Recursive routine that populates the folder list
 */
-(BOOL)loadTree:(NSArray *)listOfFolders rootNode:(TreeNode *)node
{
	Folder * folder;
	if ([Preferences standardPreferences].foldersTreeSortMethod != VNAFolderSortManual) {
		// make sure chaining is coherent…
		NSInteger siblingsCount = listOfFolders.count;
		[[Database sharedManager] setFirstChild:((Folder *)listOfFolders[0]).itemId forFolder:node.nodeId];
		for (NSInteger i=0 ; i < siblingsCount-1 ; i++) {
			NSInteger current = ((Folder *)listOfFolders[i]).itemId;
			NSInteger next = ((Folder *)listOfFolders[i+1]).itemId;
			[[Database sharedManager] setNextSibling:next forFolder:current];
		}
		[[Database sharedManager] setNextSibling:0 forFolder:((Folder *)listOfFolders[siblingsCount-1]).itemId];
		// …then attach the different nodes
		for (folder in listOfFolders) {
			NSInteger itemId = folder.itemId;
			NSArray * listOfSubFolders = [[[Database sharedManager] arrayOfFolders:itemId] sortedArrayUsingSelector:@selector(folderNameCompare:)];
			NSInteger count = listOfSubFolders.count;
			TreeNode * subNode;

			subNode = [[TreeNode alloc] init:node atIndex:-1 folder:folder canHaveChildren:(count > 0)];
			if (count) {
				[self loadTree:listOfSubFolders rootNode:subNode];
			}

		}
	} else {
		NSArray * listOfFolderIds = [listOfFolders valueForKey:@"itemId"];
		NSUInteger index = 0;
		NSInteger nextChildId = (node == self.rootNode) ? [Database sharedManager].firstFolderId : node.folder.firstChildId;
		NSInteger predecessorId = 0;
		while (nextChildId > 0) {
			if ([self.rootNode nodeFromID:nextChildId]) { // already present in our tree ?
				NSLog(@"Duplicate child with id %ld asked under folder with id %ld", (long)nextChildId, (long)node.nodeId);
				return NO;
			}
			NSUInteger  listIndex = [listOfFolderIds indexOfObject:@(nextChildId)];
			if (listIndex == NSNotFound) {
				NSLog(@"Cannot find child with id %ld for folder with id %ld", (long)nextChildId, (long)node.nodeId);
				folder = [[Database sharedManager] folderFromID:nextChildId];
				if (!folder || folder.parentId != node.nodeId) {
					return NO;
				}
				if (predecessorId == 0) {
					if (![[Database sharedManager] setFirstChild:nextChildId forFolder:node.nodeId]) {
						return NO;
					}
				} else {
					if (![[Database sharedManager] setNextSibling:nextChildId forFolder:predecessorId]) {
						return NO;
					}
				}
				NSLog(@"Repositioned folder %@ as child of folder with id %ld", folder, (long)node.nodeId);
			} else {
				folder = listOfFolders[listIndex];
			}
			NSArray * listOfSubFolders = [[Database sharedManager] arrayOfFolders:nextChildId];
			NSUInteger count = listOfSubFolders.count;
			TreeNode * subNode;
			
			subNode = [[TreeNode alloc] init:node atIndex:index folder:folder canHaveChildren:(count > 0)];
			if (count) {
				if (![self loadTree:listOfSubFolders rootNode:subNode]) {
					return NO;
				}
			}
			predecessorId = nextChildId;
			nextChildId = folder.nextSiblingId;
			++index;
		}
		if (index < listOfFolders.count) {
			NSLog(@"Missing children for folder with id %ld, %ld", (long)nextChildId, (long)node.nodeId);
			return NO;
		}
	}
	return YES;
}

/* folders
 * Returns an array that contains the all RSS folders in the database
 * ordered by the order in which they appear in the folders list view.
 */
-(NSArray *)folders:(NSInteger)folderId
{
	NSMutableArray * array = [NSMutableArray array];
	TreeNode * node;

    if (!folderId) {
		node = self.rootNode;
    } else {
		node = [self.rootNode nodeFromID:folderId];
    }
    if (node.folder != nil && (node.folder.type == VNAFolderTypeRSS || node.folder.type == VNAFolderTypeOpenReader)) {
		[array addObject:node.folder];
    }
	node = node.firstChild;
	while (node != nil) {
		[array addObjectsFromArray:[self folders:node.nodeId]];
		node = node.nextSibling;
	}
	return [array copy];
}

/* children
 * Returns an array that contains the children folders in the database
 * ordered by the order in which they appear in the folders list view.
 */
-(NSArray *)children:(NSInteger)folderId
{
	NSMutableArray * array = [NSMutableArray array];
	TreeNode * node;

	if (!folderId) {
		node = self.rootNode;
	} else {
		node = [self.rootNode nodeFromID:folderId];
	}
	node = node.firstChild;
	while (node != nil) {
		[array addObject:node.folder];
		node = node.nextSibling;
	}
	return [array copy];
}

/* updateAlternateMenuTitle
 * Sets the appropriate title for the alternate item in the contextual menu
 * when user changes preferences for opening pages in external browser
 */
-(void)updateAlternateMenuTitle
{
	NSMenuItem * mainMenuItem = menuItemWithAction(@selector(viewSourceHomePageInAlternateBrowser:));
	if (mainMenuItem == nil) {
		return;
	}
	NSString * menuTitle = mainMenuItem.title;
	NSInteger index;
	NSMenu * folderMenu = self.outlineView.menu;
	if (folderMenu != nil) {
		index = [folderMenu indexOfItemWithTarget:nil andAction:@selector(viewSourceHomePageInAlternateBrowser:)];
		if (index >= 0) {
			NSMenuItem * contextualItem = [folderMenu itemAtIndex:index];
			contextualItem.title = menuTitle;
		}
	}
}

/* updateFolder
 * Redraws a folder node and optionally recurses up and redraws all our
 * parent nodes too.
 */
-(void)updateFolder:(NSInteger)folderId recurseToParents:(BOOL)recurseToParents
{
	TreeNode * node = [self.rootNode nodeFromID:folderId];
	if (node != nil) {
		[self.outlineView reloadItem:node];
		if (recurseToParents) {
			while (node.parentNode != self.rootNode) {
				node = node.parentNode;
				[self.outlineView reloadItem:node];
			}
		}
	}
}

/* canDeleteFolderAtRow
 * Returns YES if the folder at the specified row can be deleted, otherwise NO.
 */
-(BOOL)canDeleteFolderAtRow:(NSInteger)row
{
	if (row >= 0) {
		TreeNode * node = [self.outlineView itemAtRow:row];
		if (node != nil) {
			Folder * folder = [[Database sharedManager] folderFromID:node.nodeId];
			return folder && folder.type != VNAFolderTypeSearch && folder.type != VNAFolderTypeTrash && ![Database sharedManager].readOnly && self.outlineView.window.visible;
		}
	}
	return NO;
}

/* selectFolder
 * Move the selection to the specified folder and make sure
 * it's visible in the UI.
 */
-(BOOL)selectFolder:(NSInteger)folderId
{
	TreeNode * node = [self.rootNode nodeFromID:folderId];
	if (!node) {
		return NO;
	}

	// Walk up to our parent
	[self expandToParent:node];
	NSInteger rowIndex = [self.outlineView rowForItem:node];
	if (rowIndex >= 0) {
		self.blockSelectionHandler = YES;
		[self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)rowIndex] byExtendingSelection:NO];
		[self.outlineView scrollRowToVisible:rowIndex];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:MA_Notify_FolderSelectionChange object:node];
		self.blockSelectionHandler = NO;
		return YES;
	}
	return NO;
}

/* expandToParent
 * Expands the parent nodes all the way up to the root to ensure
 * that the node containing 'node' is visible.
 */
-(void)expandToParent:(TreeNode *)node
{
	if (node.parentNode) {
		[self expandToParent:node.parentNode];
		[self.outlineView expandItem:node.parentNode];
	}
}

/* nextFolderWithUnreadAfterNode
 * Finds the ID of the next folder after the specified node that has
 * unread articles.
 */
-(NSInteger)nextFolderWithUnreadAfterNode:(TreeNode *)startingNode
{
    // keep track of parent (or grandparent) of starting node
    TreeNode * parentOfStartingNode = startingNode;
    while (parentOfStartingNode != nil && parentOfStartingNode.parentNode != self.rootNode) {
        parentOfStartingNode = parentOfStartingNode.parentNode;
    }
	TreeNode * node = startingNode;

	while (node != nil) {
		TreeNode * nextNode = nil;
		TreeNode * parentNode = node.parentNode;
		if ((node.folder.childUnreadCount > 0) && [self.outlineView isItemExpanded:node]) {
			nextNode = node.firstChild;
		}
		if (nextNode == nil) {
			nextNode = node.nextSibling;
		}
		while (nextNode == nil && parentNode != nil) {
			nextNode = parentNode.nextSibling;
			parentNode = parentNode.parentNode;
		}
		if (nextNode == nil) {
			nextNode = self.rootNode.firstChild;
		}

		if ((nextNode.folder.childUnreadCount) && ![self.outlineView isItemExpanded:nextNode]) {
			return nextNode.nodeId;
		}
		
		if (nextNode.folder.unreadCount) {
			return nextNode.nodeId;
		}

		// If we've gone full circle and not found
		// anything, we're out of unread articles
		if (nextNode == startingNode
            || (nextNode == parentOfStartingNode && !nextNode.folder.childUnreadCount))
        {
			return startingNode.nodeId;
		}

		node = nextNode;
	}
	return -1;
}

/* firstFolderWithUnread
 * Finds the ID of the first folder that has unread articles.
 */
-(NSInteger)firstFolderWithUnread
{
	// Get the first Node from the root node.
	TreeNode * firstNode = self.rootNode.firstChild;
	
	// Now get the ID of the next unread node after it and return it.
	NSInteger nextNodeID = [self nextFolderWithUnreadAfterNode:firstNode];
	return nextNodeID;
}

/* nextFolderWithUnread
 * Finds the ID of the next folder after currentFolderId that has
 * unread articles.
 */
-(NSInteger)nextFolderWithUnread:(NSInteger)currentFolderId
{
	// Get the current Node from the ID.
	TreeNode * currentNode = [self.rootNode nodeFromID:currentFolderId];
	
	// Now get the ID of the next unread node after it and return it.
	NSInteger nextNodeID = [self nextFolderWithUnreadAfterNode:currentNode];
	return nextNodeID;
}

/* groupParentSelection
 * If the selected folder is a group folder, it returns the ID of the group folder
 * otherwise it returns the ID of the parent folder.
 */
-(NSInteger)groupParentSelection
{
	Folder * folder = [[Database sharedManager] folderFromID:self.actualSelection];
	return folder ? ((folder.type == VNAFolderTypeGroup) ? folder.itemId : folder.parentId) : VNAFolderTypeRoot;
}

/// Returns the node identifier of the selected folder in the folder list.
/// If the user has right-clicked a folder then that folder is returned.
/// Otherwise, the last selected (i.e. highlighted) folder is returned.
- (NSInteger)actualSelection
{
    NSInteger rowIndex = self.outlineView.clickedRow;

    // A rowIndex of -1 means that no row has been clicked. In that case, fall
    // back to the selected row. Note that a user might have selected multiple
    // rows, but only the row that was added last to the selection is returned.
    if (rowIndex == -1) {
        rowIndex = self.outlineView.selectedRow;
    }

    TreeNode *node = [self.outlineView itemAtRow:rowIndex];
	return node.nodeId;
}

/// Returns the total number of folders selected.
- (NSInteger)countOfSelectedFolders
{
    return self.outlineView.numberOfSelectedRows;
}

/// Returns an array of all selected folders, without subfolders. If the user
/// has clicked folders then those are returned, otherwise, selected (i.e.
/// highlighted) folders are returned.
- (NSArray *)selectedFolders
{
    // Check first whether the user has selected a row by right-clicking. The
    // tricky part is that the user can highlight multiple rows first and then
    // either click on any one of the highlighted rows to make them all appear
    // clicked (shown by a border around the selection) or click on a row that
    // is not highlighted, in which case that row will not be highlighted, but
    // still appear clicked.
    //
    // -clickedRow only ever returns the actual clicked row. In that case, the
    // -selectedRowIndexes must be cross-checked to ascertain that the clicked
    // row is part of the selection.
    NSInteger clickedRow = self.outlineView.clickedRow;
    NSIndexSet *selectedRows = self.outlineView.selectedRowIndexes;

    // A row index of -1 means that no row has been clicked.
    if (clickedRow >= 0 && ![selectedRows containsIndex:clickedRow]) {
        TreeNode *node = [self.outlineView itemAtRow:clickedRow];
        Folder *folder = node.folder;
        if (folder) {
            return @[folder];
        } else {
            return @[];
        }
    }

    NSUInteger count = selectedRows.count;
    NSMutableArray *selectedFolders = [NSMutableArray arrayWithCapacity:count];

    if (count > 0) {
        NSUInteger index = selectedRows.firstIndex;
        while (index != NSNotFound) {
            TreeNode *node = [self.outlineView itemAtRow:index];
            Folder *folder = node.folder;
            if (folder) {
                [selectedFolders addObject:folder];
            }
            index = [selectedRows indexGreaterThanIndex:index];
        }
    }

    return [selectedFolders copy];
}

/* setManualSortOrderForNode
 * Writes the order of the current folder hierarchy to the database.
 */
-(void)setManualSortOrderForNode:(TreeNode *)node
{
    if (node == nil) {
		return;
    }
	NSInteger folderId = node.nodeId;
    Database *dbManager = [Database sharedManager];
	
	NSInteger count = node.countOfChildren;
	if (count > 0) {
        [dbManager setFirstChild:[node childByIndex:0].nodeId forFolder:folderId];
		[self setManualSortOrderForNode:[node childByIndex:0]];
		NSInteger index;
		for (index = 1; index < count; ++index) {
			[dbManager setNextSibling:[node childByIndex:index].nodeId forFolder:[node childByIndex:index - 1].nodeId];
			[self setManualSortOrderForNode:[node childByIndex:index]];
		}
		[dbManager setNextSibling:0 forFolder:[node childByIndex:index - 1].nodeId];
	} else {
		[dbManager setFirstChild:0 forFolder:folderId];
    }
}

/* handleAutoSortFoldersTreeChange
 * Respond to the notification when the preference is changed for automatically or manually sorting the folders tree.
 */
-(void)handleAutoSortFoldersTreeChange:(NSNotification *)nc
{
	NSInteger selectedFolderId = self.actualSelection;
	
	if ([Preferences standardPreferences].foldersTreeSortMethod == VNAFolderSortManual) {
        [self setManualSortOrderForNode:self.rootNode];
	}
	
	self.blockSelectionHandler = YES;
	[self reloadDatabase:[[Preferences standardPreferences] arrayForKey:MAPref_FolderStates]];
	self.blockSelectionHandler = NO;
	
	// Make sure selected folder is visible
	[self selectFolder:selectedFolderId];
}

/* handleShowFolderImagesChange
 * Respond to the notification sent when the option to show folder images is changed.
 */
-(void)handleShowFolderImagesChange:(NSNotification *)nc
{
	[self.outlineView reloadData];
}

/* handleDoubleClick
 * Handle the user double-clicking a node.
 */
-(void)handleDoubleClick:(id)sender
{
    TreeNode * node = [self.outlineView itemAtRow:self.outlineView.selectedRow];

	if (node.folder.type == VNAFolderTypeRSS || node.folder.type == VNAFolderTypeOpenReader) {
		NSString * urlString = node.folder.homePage;
        if (urlString && !urlString.vna_isBlank) {
			[APPCONTROLLER openURLFromString:urlString inPreferredBrowser:YES];
        }
	} else if (node.folder.type == VNAFolderTypeSmart) {
		[[NSNotificationCenter defaultCenter] postNotificationName:MA_Notify_EditFolder object:node];
	}
}

/* handleFolderDeleted
 * Called whenever a folder is removed from the database. We need
 * to delete the associated tree nodes then select the next node, or
 * the previous one if we were at the bottom of the list.
 */
-(void)handleFolderDeleted:(NSNotification *)nc
{
	NSInteger currentFolderId = self.controller.currentFolderId;
	NSInteger folderId = ((NSNumber *)nc.object).integerValue;
	TreeNode * thisNode = [self.rootNode nodeFromID:folderId];
	TreeNode * nextNode;

	// First find the next node we'll select
	if (thisNode.nextSibling != nil) {
		nextNode = thisNode.nextSibling;
	} else {
		nextNode = thisNode.parentNode;
		if (nextNode.countOfChildren > 1) {
			nextNode = [nextNode childByIndex:nextNode.countOfChildren - 2];
		}
	}

	// Ask our parent to delete us
	TreeNode * ourParent = thisNode.parentNode;
	[ourParent removeChild:thisNode andChildren:YES];
	[self reloadFolderItem:ourParent reloadChildren:YES];

	// Send the selection notification ourselves because if we're deleting at the end of
	// the folder list, the selection won't actually change and outlineViewSelectionDidChange
	// won't get tripped.
	if (currentFolderId == folderId) {
		self.blockSelectionHandler = YES;
		[self selectFolder:nextNode.nodeId];
		[[NSNotificationCenter defaultCenter] postNotificationName:MA_Notify_FolderSelectionChange object:nextNode];
		self.blockSelectionHandler = NO;
	}
}

/* handleFolderNameChange
 * Called whenever we need to redraw a specific folder, possibly because
 * the unread count changed.
 */
-(void)handleFolderNameChange:(NSNotification *)nc
{
	NSInteger folderId = ((NSNumber *)nc.object).integerValue;
	TreeNode * node = [self.rootNode nodeFromID:folderId];
	TreeNode * parentNode = node.parentNode;

	BOOL moveSelection = (folderId == self.actualSelection);

	if ([Preferences standardPreferences].foldersTreeSortMethod == VNAFolderSortByName) {
		[parentNode sortChildren:VNAFolderSortByName];
	}

	[self reloadFolderItem:parentNode reloadChildren:YES];
	if (moveSelection) {
		NSInteger row = [self.outlineView rowForItem:node];
		if (row >= 0) {
			self.blockSelectionHandler = YES;
			NSIndexSet * indexes = [NSIndexSet indexSetWithIndex:(NSUInteger)row];
			[self.outlineView selectRowIndexes:indexes byExtendingSelection:NO];
			[self.outlineView scrollRowToVisible:row];
			self.blockSelectionHandler = NO;
		}
	}
}

/* handleFolderUpdate
 * Called whenever we need to redraw a specific folder, possibly because
 * the unread count changed.
 */
-(void)handleFolderUpdate:(NSNotification *)nc
{
	NSInteger folderId = ((NSNumber *)nc.object).integerValue;
	if (folderId == 0) {
		[self reloadFolderItem:self.rootNode reloadChildren:YES];
	} else {
		[self updateFolder:folderId recurseToParents:YES];
	}
}

/* handleFolderAdded
 * Called when a new folder is added to the database.
 */
-(void)handleFolderAdded:(NSNotification *)nc
{
	Folder * newFolder = (Folder *)nc.object;
	NSAssert(newFolder, @"Somehow got a NULL folder object here");

	NSInteger parentId = newFolder.parentId;
	TreeNode * node = (parentId == VNAFolderTypeRoot) ? self.rootNode : [self.rootNode nodeFromID:parentId];
	if (!node.canHaveChildren) {
		[node setCanHaveChildren:YES];
	}
	
	NSInteger childIndex = -1;
	if ([Preferences standardPreferences].foldersTreeSortMethod == VNAFolderSortManual) {
		NSInteger nextSiblingId = newFolder.nextSiblingId;
		if (nextSiblingId > 0) {
			TreeNode * nextSibling = [node nodeFromID:nextSiblingId];
			if (nextSibling != nil) {
				childIndex = [node indexOfChild:nextSibling];
			}
		}
	}
	
	TreeNode __unused * newNode = [[TreeNode alloc] init:node atIndex:childIndex folder:newFolder canHaveChildren:NO];
	[self reloadFolderItem:node reloadChildren:YES];
	[self selectFolder:newFolder.itemId];
}

/* reloadFolderItem
 * Wrapper around reloadItem.
 */
-(void)reloadFolderItem:(id)node reloadChildren:(BOOL)flag
{
    if (node == self.rootNode) {
        [self.outlineView reloadData];
    } else {
        [self.outlineView reloadItem:node reloadChildren:flag];
    }
}

/* mainView
 * Return the main view of this class.
 */
-(NSView *)mainView
{
	return self.outlineView;
}

/* renameFolder
 * Begin in-place editing of the selected folder name.
 */
-(void)renameFolder:(NSInteger)folderId
{	
	TreeNode * node = [self.rootNode nodeFromID:folderId];
	NSInteger rowIndex = [self.outlineView rowForItem:node];
		
	if (rowIndex != -1) {
        if (self.fieldEditor && self.fieldEditor.delegate) {
            NSTextField *textField = (NSTextField *)self.fieldEditor.delegate;
            [textField abortEditing];
        }

		[self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)rowIndex] byExtendingSelection:NO];
		NSInteger columnIndex = [self.outlineView columnWithIdentifier:@"folderColumns"];
        VNAFeedListCellView * cellView = [self.outlineView viewAtColumn:columnIndex row:rowIndex makeIfNecessary:NO];
        cellView.textField.editable = YES;
		[self.outlineView editColumn:columnIndex row:rowIndex withEvent:nil select:YES];
	}
}

/* folderViewWillBecomeFirstResponder
 * When outline view becomes first responder, bring the article view to the front,
 * and prevent immediate folder renaming.
 */
-(void)folderViewWillBecomeFirstResponder
{
	[self.controller.browser switchToPrimaryTab];
}

/* copyTableSelection
 * This is the common copy selection code. We build an array of dictionary entries each of
 * which include details of each selected folder in the standard RSS item format defined by
 * Ranchero NetNewsWire. See http://ranchero.com/netnewswire/rssclipboard.php for more details.
 */
-(BOOL)copyTableSelection:(NSArray *)items toPasteboard:(NSPasteboard *)pboard
{
	NSInteger count = items.count;
	NSMutableArray * externalDragData = [NSMutableArray arrayWithCapacity:count];
	NSMutableArray * internalDragData = [NSMutableArray arrayWithCapacity:count];
	NSMutableString * stringDragData = [NSMutableString string];
	NSMutableArray * arrayOfURLs = [NSMutableArray arrayWithCapacity:count];
	NSMutableArray * arrayOfTitles = [NSMutableArray arrayWithCapacity:count];
	NSInteger index;

	// We'll create the types of data on the clipboard.
	[pboard declareTypes:@[VNAPasteboardTypeFolderList, VNAPasteboardTypeRSSSource, VNAPasteboardTypeWebURLsWithTitles, NSPasteboardTypeString] owner:self];

	// Create an array of NSNumber objects containing the selected folder IDs.
	NSInteger countOfItems = 0;
	for (index = 0; index < count; ++index) {
		TreeNode * node = items[index];
		Folder * folder = node.folder;

		if (folder.type == VNAFolderTypeRSS
            || folder.type == VNAFolderTypeOpenReader
            || folder.type == VNAFolderTypeSmart
            || folder.type == VNAFolderTypeGroup
            || folder.type == VNAFolderTypeSearch
            || folder.type == VNAFolderTypeTrash) {
			[internalDragData addObject:@(node.nodeId)];
			++countOfItems;
		}

		if (folder.type == VNAFolderTypeRSS
            || folder.type == VNAFolderTypeOpenReader) {
			NSString * feedURL = folder.feedURL;
			
			NSMutableDictionary * dict = [NSMutableDictionary dictionary];
			[dict setValue:folder.name forKey:@"sourceName"];
			[dict setValue:folder.description forKey:@"sourceDescription"];
			[dict setValue:feedURL forKey:@"sourceRSSURL"];
			[dict setValue:folder.homePage forKey:@"sourceHomeURL"];
			[externalDragData addObject:dict];

			[stringDragData appendFormat:@"%@\n", feedURL];
			
			NSURL * safariURL = [NSURL URLWithString:feedURL];
			if (safariURL != nil && !safariURL.fileURL) {
				if (![@"feed" isEqualToString:safariURL.scheme]) {
					feedURL = [NSString stringWithFormat:@"feed:%@", safariURL.resourceSpecifier];
				}
				[arrayOfURLs addObject:feedURL];
				[arrayOfTitles addObject:folder.name];
			}
		}
	}

	// Copy the data to the pasteboard 
	[pboard setPropertyList:externalDragData forType:VNAPasteboardTypeRSSSource];
	[pboard setString:stringDragData forType:NSPasteboardTypeString];
	[pboard setPropertyList:internalDragData forType:VNAPasteboardTypeFolderList]; 
	[pboard setPropertyList:@[arrayOfURLs, arrayOfTitles] forType:VNAPasteboardTypeWebURLsWithTitles];
	return countOfItems > 0; 
}

/* moveFoldersUndo
 * Undo handler to move folders back.
 */
-(void)moveFoldersUndo:(id)anObject
{
	[self moveFolders:(NSArray *)anObject withGoogleSync:YES];
}

/* moveFolders
 * Reparent folders using the information in the specified array. The array consists of
 * a collection of NSNumber triples: the first number is the ID of the folder to move,
 * the second number is the ID of the parent to which the folder should be moved,
 * the third number is the ID of the folder's new predecessor sibling.
 */
-(BOOL)moveFolders:(NSArray *)array withGoogleSync:(BOOL)sync
{
	NSAssert(([array count] % 3) == 0, @"Incorrect number of items in array passed to moveFolders");
	NSInteger count = array.count;
	__block NSInteger index = 0;

	// Need to create a running undo array
	NSMutableArray * undoArray = [[NSMutableArray alloc] initWithCapacity:count];

	// Internal drag and drop so we're just changing the parent IDs around. One thing
	// we have to watch for is to make sure that we don't re-parent to a subordinate
	// folder.
	Database * dbManager = [Database sharedManager];
	BOOL autoSort = [Preferences standardPreferences].foldersTreeSortMethod != VNAFolderSortManual;

	while (index < count) {
		NSInteger folderId = [array[index++] integerValue];
		NSInteger newParentId = [array[index++] integerValue];
		NSInteger newPredecessorId = [array[index++] integerValue];
		Folder * folder = [dbManager folderFromID:folderId];
		NSInteger oldParentId = folder.parentId;

		TreeNode * node = [self.rootNode nodeFromID:folderId];
		TreeNode * oldParent = [self.rootNode nodeFromID:oldParentId];
		NSInteger oldChildIndex = [oldParent indexOfChild:node];
		NSInteger oldPredecessorId = (oldChildIndex > 0) ? [oldParent childByIndex:(oldChildIndex - 1)].nodeId : 0;
		TreeNode * newParent = [self.rootNode nodeFromID:newParentId];
		TreeNode * newPredecessor = [newParent nodeFromID:newPredecessorId];
		if ((newPredecessor == nil) || (newPredecessor == newParent)) {
			newPredecessorId = 0;
		}
		NSInteger newChildIndex = (newPredecessorId > 0) ? ([newParent indexOfChild:newPredecessor] + 1) : 0;

		if (newParentId == oldParentId) {
			// With automatic sorting, moving under the same parent is impossible.
			if (autoSort) {
				continue;
			}
			// No need to move if destination is the same as origin.
			if (newPredecessorId == oldPredecessorId) {
				continue;
			}
			// Adjust the index for the removal of the old child.
			if (newChildIndex > oldChildIndex) {
				--newChildIndex;
			}

		} else {
			if ([dbManager setParent:newParentId forFolder:folderId]) {
				if (sync && folder.type == VNAFolderTypeOpenReader) {
					OpenReader * myReader = [OpenReader sharedManager];
					// remove old label
					NSString * folderName = [dbManager folderFromID:oldParentId].name;
					[myReader setFolderLabel:folderName forFeed:folder.remoteId set:FALSE];
					// add new label
					folderName = [dbManager folderFromID:newParentId].name;
					if (folderName) {
						[myReader setFolderLabel:folderName forFeed:folder.remoteId set:TRUE];
					}
				}
			} else {
				continue;
			}
			if (!newParent.canHaveChildren) {
				[newParent setCanHaveChildren:YES];
			}
		}

		if (!autoSort) {
			if (oldPredecessorId > 0) {
				if (![dbManager setNextSibling:folder.nextSiblingId forFolder:oldPredecessorId]) {
					continue;
				}
			} else {
				if (![dbManager setFirstChild:folder.nextSiblingId forFolder:oldParentId]) {
					continue;
				}
			}
			if (newPredecessorId > 0) {
				if (![dbManager setNextSibling:[dbManager folderFromID:newPredecessorId].nextSiblingId
									 forFolder:folderId]) {
					continue;
				}
				[dbManager setNextSibling:folderId forFolder:newPredecessorId];
			} else {
				NSInteger oldFirstChildId = (newParent == self.rootNode) ? dbManager.firstFolderId
																		 : newParent.folder.firstChildId;
				if (![dbManager setNextSibling:oldFirstChildId forFolder:folderId]) {
					continue;
				}
				[dbManager setFirstChild:folderId forFolder:newParentId];
			}
		}

		[oldParent removeChild:node andChildren:NO];
		[newParent addChild:node atIndex:newChildIndex];

		// Put at beginning of undoArray in order to undo moves in reverse order.
		[undoArray insertObject:@(folderId) atIndex:0u];
		[undoArray insertObject:@(oldParentId) atIndex:1u];
		[undoArray insertObject:@(oldPredecessorId) atIndex:2u];
	}

	// If undo array is empty, then nothing has been moved.
	if (undoArray.count == 0u) {
		return NO;
	}

	// Set up to undo this action
	NSUndoManager * undoManager = NSApp.mainWindow.undoManager;
	[undoManager registerUndoWithTarget:self selector:@selector(moveFoldersUndo:) object:undoArray];
	[undoManager setActionName:NSLocalizedString(@"Move Folders", nil)];

	// Make the outline control reload its data
	[self.outlineView reloadData];

	// If any parent was a collapsed group, expand it now
	for (index = 0; index < count; index += 2) {
		NSInteger newParentId = [array[++index] integerValue];
		if (newParentId != VNAFolderTypeRoot) {
			TreeNode * parentNode = [self.rootNode nodeFromID:newParentId];
			if (![self.outlineView isItemExpanded:parentNode] && [self.outlineView isExpandable:parentNode]) {
				[self.outlineView expandItem:parentNode];
			}
		}
	}

	// Properly set selection back to the original items. This has to be done after the
	// refresh so that rowForItem returns the new positions.
	NSMutableIndexSet * selIndexSet = [[NSMutableIndexSet alloc] init];
	NSInteger selRowIndex = 9999;
	for (index = 0; index < count; index += 2) {
		NSInteger folderId = [array[index++] integerValue];
		NSInteger rowIndex = [self.outlineView rowForItem:[self.rootNode nodeFromID:folderId]];
		selRowIndex = MIN(selRowIndex, rowIndex);
		[selIndexSet addIndex:rowIndex];
	}
	[self.outlineView scrollRowToVisible:selRowIndex];
	[self.outlineView selectRowIndexes:selIndexSet byExtendingSelection:NO];
	return YES;
} // moveFolders

/* setSearch
 * Set string to filter nodes by name, description, url
 */
-(void)setSearch:(NSString *)f {
    NSString* tf = [f stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (tf.length == 0) {
        self.outlineView.filterPredicate = nil;
        [self.outlineView showResetButton:NO];
        return;
    }

    NSString *match = [NSString stringWithFormat:@"*%@*", tf];
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"folder.name like[cd] %@ OR folder.feedDescription like[cd] %@ OR folder.feedURL like[cd] %@", match, match, match];

    if ([self.outlineView.filterPredicate.predicateFormat isEqualToString:predicate.predicateFormat]) {
        return;
    }

    [self.outlineView showResetButton:YES];
    self.outlineView.filterPredicate = predicate;
}

// MARK: Key-value observing

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    if (context != VNAFoldersTreeObserverContext) {
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
        return;
    }

    NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
    if ([object isNotEqualTo:userDefaults]) {
        return;
    }

    if ([keyPath isEqualToString:MAPref_FeedListSizeMode]) {
        [self updateCellSize:[userDefaults integerForKey:MAPref_FeedListSizeMode]];
    }
    if ([keyPath isEqualToString:MAPref_ShowFeedsWithUnreadItemsInBold]) {
        [self.outlineView reloadDataWhilePreservingSelection];
    }
}

- (void)updateCellSize:(VNAFeedListSizeMode)size
{
    switch (size) {
    case VNAFeedListSizeModeTiny:
    case VNAFeedListSizeModeSmall:
    case VNAFeedListSizeModeMedium:
        self.outlineView.sizeMode = size;
        break;
    default:
        self.outlineView.sizeMode = VNAFeedListSizeModeDefault;
    }

    self.outlineView.rowHeight = [self.outlineView rowHeightForSize:size];
    NSRange rowsRange = NSMakeRange(0, self.outlineView.numberOfRows);
    NSIndexSet *rowIndexes = [NSIndexSet indexSetWithIndexesInRange:rowsRange];
    [self.outlineView noteHeightOfRowsWithIndexesChanged:rowIndexes];
    [self.outlineView reloadDataWhilePreservingSelection];
}

// MARK: - NSOutlineViewDataSource

/* isItemExpandable
 * Tell the outline view if the specified item can be expanded. The answer is
 * yes if we have children, no otherwise.
 */
-(BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    TreeNode * node = (TreeNode *)item;
    if (node == nil) {
        node = self.rootNode;
    }
    return node.canHaveChildren && node.countOfChildren > 0;
}

/* validateDrop
 * Called when something is being dragged over us. We respond with an NSDragOperation value indicating the
 * feedback for the user given where we are.
 */
- (NSDragOperation)outlineView:(NSOutlineView*)olv
                  validateDrop:(id <NSDraggingInfo>)info
                  proposedItem:(id)item
            proposedChildIndex:(NSInteger)index
{
    NSPasteboard * pb = [info draggingPasteboard];
    NSString * type = [pb availableTypeFromArray:@[VNAPasteboardTypeFolderList, VNAPasteboardTypeRSSSource, VNAPasteboardTypeWebURLsWithTitles, NSPasteboardTypeString]];
    NSDragOperation dragType = ([type isEqualToString:VNAPasteboardTypeFolderList]) ? NSDragOperationMove : NSDragOperationCopy;

    TreeNode * node = (TreeNode *)item;
    BOOL isOnDropTypeProposal = index == NSOutlineViewDropOnItemIndex;

    // Can't drop anything onto the trash folder.
    if (isOnDropTypeProposal && node != nil && node.folder.type == VNAFolderTypeTrash) {
        return NSDragOperationNone;
    }

    // Can't drop anything onto the search folder.
    if (isOnDropTypeProposal && node != nil && node.folder.type == VNAFolderTypeSearch) {
        return NSDragOperationNone;
    }

    // Can't drop anything on smart folders.
    if (isOnDropTypeProposal && node != nil && node.folder.type == VNAFolderTypeSmart) {
        return NSDragOperationNone;
    }

    // Can always drop something on a group folder.
    if (isOnDropTypeProposal && node != nil && node.folder.type == VNAFolderTypeGroup) {
        return dragType;
    }

    // For any other folder, can't drop anything ON them.
    if (index == NSOutlineViewDropOnItemIndex) {
        return NSDragOperationNone;
    }
    return NSDragOperationGeneric;
}

/* acceptDrop
 * Accept a drop on or between nodes either from within the folder view or from outside.
 */
- (BOOL)outlineView:(NSOutlineView *)outlineView
         acceptDrop:(id<NSDraggingInfo>)info
               item:(id)item
         childIndex:(NSInteger)index
{
    __block NSInteger childIndex = index;
    NSPasteboard *pb = [info draggingPasteboard];
    NSString *type = [pb availableTypeFromArray:@[VNAPasteboardTypeFolderList, VNAPasteboardTypeRSSSource, VNAPasteboardTypeWebURLsWithTitles, NSPasteboardTypeString]];
    TreeNode *node = item ? (TreeNode *)item : self.rootNode;

    NSInteger parentId = node.nodeId;
    if (childIndex < 0) {
        childIndex = 0;
    }

    // Check the type
    if ([type isEqualToString:NSPasteboardTypeString]) {
        // This is possibly a URL that we'll handle as a potential feed subscription. It's
        // not our call to make though.
        NSInteger predecessorId = (childIndex > 0) ? [node childByIndex:(childIndex - 1)].nodeId : 0;
        [APPCONTROLLER createNewSubscription:[pb stringForType:type] underFolder:parentId afterChild:predecessorId];
        return YES;
    }
    if ([type isEqualToString:VNAPasteboardTypeFolderList]) {
        Database *db = [Database sharedManager];
        NSArray *arrayOfSources = [pb propertyListForType:type];
        NSInteger count = arrayOfSources.count;
        NSInteger index;
        NSInteger predecessorId = (childIndex > 0) ? [node childByIndex:(childIndex - 1)].nodeId : 0;

        // Create an NSArray of triples (folderId, newParentId, predecessorId) that will be passed to moveFolders
        // to do the actual move.
        NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:count * 3];
        NSInteger trashFolderId = db.trashFolderId;
        for (index = 0; index < count; ++index) {
            NSInteger folderId = [arrayOfSources[index] integerValue];

            // Don't allow the trash folder to move under a group folder, because the group folder could get deleted.
            // Also, don't allow perverse moves.  We should probably do additional checking: not only whether the new parent
            // is the folder itself but also whether the new parent is a subfolder.
            if (((folderId == trashFolderId) && (node != self.rootNode)) || (folderId == parentId) || (folderId == predecessorId)) {
                continue;
            }
            [array addObject:@(folderId)];
            [array addObject:@(parentId)];
            [array addObject:@(predecessorId)];
            predecessorId = folderId;
        }

        // Do the move
        BOOL result = [self moveFolders:array withGoogleSync:YES];
        return result;
    }
    if ([type isEqualToString:VNAPasteboardTypeRSSSource]) {
        Database *dbManager = [Database sharedManager];
        NSArray *arrayOfSources = [pb propertyListForType:type];
        NSInteger count = arrayOfSources.count;
        NSInteger index;

        // This is an RSS drag using the protocol defined by Ranchero for NetNewsWire. See
        // http://ranchero.com/netnewswire/rssclipboard.php for more details.
        //
        __block NSInteger folderToSelect = -1;
        for (index = 0; index < count; ++index) {
            NSDictionary *sourceItem = arrayOfSources[index];
            NSString *feedTitle = [sourceItem valueForKey:@"sourceName"];
            NSString *feedHomePage = [sourceItem valueForKey:@"sourceHomeURL"];
            NSString *feedURL = [sourceItem valueForKey:@"sourceRSSURL"];
            NSString *feedDescription = [sourceItem valueForKey:@"sourceDescription"];

            if (feedURL && ![dbManager folderFromFeedURL:feedURL]) {
                NSInteger predecessorId = (childIndex > 0) ? [node childByIndex:(childIndex - 1)].nodeId : 0;
                NSInteger folderId = [dbManager addRSSFolder:feedTitle underParent:parentId afterChild:predecessorId subscriptionURL:feedURL];
                if (feedDescription) {
                    [dbManager setDescription:feedDescription forFolder:folderId];
                }
                if (feedHomePage) {
                    [dbManager setHomePage:feedHomePage forFolder:folderId];
                }
                if (folderId > 0) {
                    folderToSelect = folderId;
                }
                ++childIndex;
            }
        }

        // If parent was a group, expand it now
        if (parentId != VNAFolderTypeRoot) {
            [self.outlineView expandItem:[self.rootNode nodeFromID:parentId]];
        }

        // Select a new folder
        if (folderToSelect > 0) {
            [self selectFolder:folderToSelect];
        }

        return YES;
    }
    if ([type isEqualToString:@"WebURLsWithTitlesPboardType"]) {
        Database *dbManager = [Database sharedManager];
        NSArray *webURLsWithTitles = [pb propertyListForType:type];
        NSArray *arrayOfURLs = webURLsWithTitles[0];
        NSArray *arrayOfTitles = webURLsWithTitles[1];
        NSInteger count = arrayOfURLs.count;
        NSInteger index;

        __block NSInteger folderToSelect = -1;
        for (index = 0; index < count; ++index) {
            NSString *feedTitle = arrayOfTitles[index];
            NSString *feedURL = arrayOfURLs[index];
            NSURL *draggedURL = [NSURL URLWithString:feedURL];
            if (draggedURL.scheme && [draggedURL.scheme isEqualToString:@"feed"]) {
                feedURL = [NSString stringWithFormat:@"http:%@", draggedURL.resourceSpecifier];
            }

            if (![dbManager folderFromFeedURL:feedURL]) {
                NSInteger predecessorId = (childIndex > 0) ? [node childByIndex:(childIndex - 1)].nodeId : 0;
                NSInteger newFolderId = [dbManager addRSSFolder:feedTitle underParent:parentId afterChild:predecessorId subscriptionURL:feedURL];
                if (newFolderId > 0) {
                    folderToSelect = newFolderId;
                }
                ++childIndex;
            }
        }

        // If parent was a group, expand it now
        if (parentId != VNAFolderTypeRoot) {
            [self.outlineView expandItem:[self.rootNode nodeFromID:parentId]];
        }

        // Select a new folder
        if (folderToSelect > 0) {
            [self selectFolder:folderToSelect];
        }

        return YES;
    }
    return NO;
}

/* numberOfChildrenOfItem
 * Returns the number of children belonging to the specified item
 */
- (NSInteger)outlineView:(NSOutlineView *)outlineView
    numberOfChildrenOfItem:(id)item
{
    TreeNode *node = (TreeNode *)item;
    if (!node) {
        node = self.rootNode;
    }
    return node.countOfChildren;
}

/* child
 * Returns the child at the specified offset of the item
 */
- (id)outlineView:(NSOutlineView *)outlineView
            child:(NSInteger)index
           ofItem:(id)item
{
    TreeNode *node = (TreeNode *)item;
    if (!node) {
        node = self.rootNode;
    }
    return [node childByIndex:index];
}

// Collect the selected folders ready for dragging.
- (BOOL)outlineView:(NSOutlineView *)outlineView
         writeItems:(NSArray *)items
       toPasteboard:(NSPasteboard *)pasteboard
{
    return [self copyTableSelection:items toPasteboard:pasteboard];
}

// MARK: - NSOutlineViewDelegate

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item
{
    VNAFeedListSizeMode size = self.outlineView.sizeMode;
    return [self.outlineView rowHeightForSize:size];
}

- (NSView *)outlineView:(NSOutlineView *)outlineView
     viewForTableColumn:(NSTableColumn *)tableColumn
                   item:(id)item
{
    if ([tableColumn isNotEqualTo:outlineView.outlineTableColumn]) {
        return nil;
    }

    VNAFeedListCellView *cellView = [outlineView makeViewWithIdentifier:VNAFeedListCellViewIdentifier owner:self];
    TreeNode *node = (TreeNode *)item;
    if (!node && node == self.rootNode) {
        node = self.rootNode;
    }
    Folder *folder = node.folder;

    // Only show folder images if the user prefers them.
    Preferences *prefs = [Preferences standardPreferences];
    cellView.imageView.image = (prefs.showFolderImages ? folder.image : [folder standardImage]);
    cellView.textField.stringValue = node.nodeName;
    cellView.textField.delegate = self;

    cellView.sizeMode = self.outlineView.sizeMode;

    // Use the auxiliary position of the feed item to show
    // the refresh icon if the feed is being refreshed, or an
    // error icon if the feed failed to refresh last time.
    if (folder.isUpdating) {
        cellView.inProgress = YES;
    } else if (folder.isError) {
        cellView.showError = YES;
        cellView.inProgress = NO;
    } else {
        cellView.showError = NO;
        cellView.inProgress = NO;
    }

    BOOL useEmphasis = [prefs boolForKey:MAPref_ShowFeedsWithUnreadItemsInBold];

    switch (folder.type) {
        case VNAFolderTypeSmart:
        case VNAFolderTypeTrash:
        case VNAFolderTypeSearch:
            cellView.emphasized = NO;
            cellView.canShowUnreadCount = NO;
            break;
        case VNAFolderTypeGroup:
            cellView.emphasized = useEmphasis && folder.childUnreadCount > 0 && ![outlineView isItemExpanded:item];
            cellView.canShowUnreadCount = ![outlineView isItemExpanded:item];
            cellView.unreadCount = folder.childUnreadCount;
            break;
        default:
            cellView.emphasized = useEmphasis && folder.unreadCount > 0;
            cellView.canShowUnreadCount = YES;
            cellView.unreadCount = folder.unreadCount;
    }

    cellView.inactive = folder.isUnsubscribed;

    // The content tint color should only apply to the SF Symbol.
    if (@available(macOS 11, *)) {
        if (folder.type == VNAFolderTypeSmart) {
            cellView.imageView.contentTintColor = NSColor.systemGrayColor;
        } else {
            cellView.imageView.contentTintColor = nil;
        }
    }

    return cellView;
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification
{
    FolderView *folderView = notification.object;
    TreeNode *node = notification.userInfo[@"NSObject"];

    if (!folderView || !node || folderView.numberOfColumns != 1) {
        return;
    }

    if (node.folder.type != VNAFolderTypeGroup) {
        return;
    }

    NSInteger rowIndex = [folderView rowForItem:node];
    VNAFeedListCellView *cellView = [folderView viewAtColumn:0
                                                         row:rowIndex
                                             makeIfNecessary:NO];
    // This block allows the accessor to query whether implicit animations are
    // allowed, in which case it can show animations.
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.allowsImplicitAnimation = YES;
        cellView.canShowUnreadCount = YES;
    }];

    Preferences *preferences = Preferences.standardPreferences;
    BOOL useEmphasis = [preferences boolForKey:MAPref_ShowFeedsWithUnreadItemsInBold];
    cellView.emphasized = useEmphasis && node.folder.childUnreadCount;
}

- (void)outlineViewItemDidExpand:(NSNotification *)notification
{
    FolderView *folderView = notification.object;
    TreeNode *node = notification.userInfo[@"NSObject"];

    if (!folderView || !node || folderView.numberOfColumns != 1) {
        return;
    }

    if (node.folder.type != VNAFolderTypeGroup) {
        return;
    }

    NSInteger rowIndex = [folderView rowForItem:node];
    VNAFeedListCellView *cellView = [folderView viewAtColumn:0
                                                         row:rowIndex
                                             makeIfNecessary:NO];
    // This block allows the accessor to query whether implicit animations are
    // allowed for the current animation context (the default is nil).
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.allowsImplicitAnimation = YES;
        cellView.canShowUnreadCount = NO;
    }];
    cellView.emphasized = NO;
}

/* outlineViewSelectionDidChange
 * Called when the selection in the folder list has changed.
 */
-(void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    if (!self.blockSelectionHandler) {
        TreeNode * node = [self.outlineView itemAtRow:self.outlineView.selectedRow];
        [[NSNotificationCenter defaultCenter] postNotificationName:MA_Notify_FolderSelectionChange object:node];
    }
}

// MARK: - NSTextFieldDelegate

- (void)controlTextDidBeginEditing:(NSNotification *)obj
{
    self.fieldEditor = obj.userInfo[@"NSFieldEditor"];
}

// Called when the user finishes editing a folder name
- (void)controlTextDidEndEditing:(NSNotification *)obj
{
    self.fieldEditor = nil;

    NSText *fieldEditor = obj.userInfo[@"NSFieldEditor"];
    NSString *newValue = [fieldEditor.string copy];
    NSTextField *textField = (NSTextField *)obj.object;
    textField.editable = NO;
    NSInteger rowIndex = [self.outlineView rowForView:textField];
    TreeNode *node = [self.outlineView itemAtRow:rowIndex];
    Folder *folder = node.folder;

    if ([newValue isEqualToString:folder.name]) {
        return;
    }

    if (newValue.vna_isBlank) {
        textField.stringValue = folder.name;
        return;
    }

    // remove the prefix marking it is a cloud (Open Reader) feed
    if (folder.type == VNAFolderTypeOpenReader && [newValue hasPrefix:VNAOpenReaderFolderPrefix]) {
        NSString *tmpName = [newValue substringFromIndex:VNAOpenReaderFolderPrefix.length];
        newValue = tmpName;
    }

    newValue = newValue.vna_trimmed;
    Database *dbManager = [Database sharedManager];
    if ([dbManager folderFromName:newValue] != nil) {
        textField.stringValue = folder.name;
        runOKAlertPanel(NSLocalizedString(@"Cannot rename folder", nil),
                        NSLocalizedString(@"A folder with that name already exists", nil));
        return;
    }

    [dbManager setName:newValue forFolder:folder.itemId];
    if (folder.type == VNAFolderTypeOpenReader) {
        [OpenReader.sharedManager setFolderTitle:newValue forFeed:folder.remoteId];
    }
}

@end
