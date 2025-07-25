//
//  ArticleBaseView.h
//  Vienna
//
//  Created by Steve on 5/6/06.
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

@import Foundation;

#import "BaseView.h"

@class ArticleView;
@class Article;
@class DisclosureView;
@class FilterView;

@protocol ArticleBaseView <BaseView>
    @property (readonly, nonatomic) BOOL selectFirstUnreadInFolder;
    @property (readonly, nonatomic) BOOL viewNextUnreadInFolder;
	-(void)scrollDownDetailsOrNextUnread;
	-(void)scrollUpDetailsOrGoBack;
	-(void)scrollToArticle:(NSString *)guid;
	-(void)refreshFolder:(NSInteger)refreshFlag;
	@property (nonatomic, readonly) Article *selectedArticle;
	@property (readonly, nonatomic) NSArray *markedArticleRange;
	-(void)saveTableSettings;
	-(void)ensureSelectedArticle;

@property (readonly, nonatomic) DisclosureView *filterBarDisclosureView;
@property (readonly, nonatomic) FilterView *filterBarView;

@end
