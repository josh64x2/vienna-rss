//
//  TreeNode.h
//  Vienna
//
//  Created by Steve on Sat Jan 31 2004.
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

#define PROGRESS_INDICATOR_DIMENSION	16

@interface TreeNode : NSObject

- (instancetype)init:(TreeNode *)parentNode
             atIndex:(NSInteger)insertIndex
              folder:(Folder *)folder
     canHaveChildren:(BOOL)childflag NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

// Accessor functions
@property (nonatomic) TreeNode *parentNode;
@property (nonatomic, readonly) TreeNode *nextSibling;
@property (nonatomic, readonly) TreeNode *firstChild;
-(void)addChild:(TreeNode *)child atIndex:(NSInteger)insertIndex;
-(void)removeChildren;
-(void)removeChild:(TreeNode *)child andChildren:(BOOL)removeChildrenFlag;
-(void)sortChildren:(NSInteger)sortMethod;
@property (readonly, nonatomic) NSString *nodeName;
-(TreeNode *)childByName:(NSString *)childName;
-(TreeNode *)childByIndex:(NSInteger)index;
-(NSInteger)indexOfChild:(TreeNode *)node;
-(TreeNode *)nodeFromID:(NSInteger)n;
@property (nonatomic) Folder *folder;
@property (nonatomic) NSInteger nodeId;
@property (nonatomic, readonly) NSUInteger countOfChildren;
@property (nonatomic) BOOL canHaveChildren;
-(NSComparisonResult)folderNameCompare:(TreeNode *)otherObject;

@end
