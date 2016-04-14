//
//  LDPMSeperatedHallViewController.m
//  PreciousMetals
//
//  Created by LiuLiming on 15/6/23.
//  Copyright (c) 2015年 NetEase. All rights reserved.
//

#import "LDPMSeperatedHallViewController.h"
#import "LDPMSeperatedHallDataSource.h"
#import "LDPMHallEditableMarketInfoView.h"
#import "LDPMSeperatorView.h"
#import "LDPMSeperatedHallDataController.h"
#import "LDPMHallCellHeader.h"
#import "LDPMHallGuideBar.h"
#import "LDPMHallUtility.h"
#import "LDPMHallMarketInfoView.h"

@interface LDPMSeperatedHallViewController () < LDPMNewUserActivityViewDelegate,LDPMHallEditableMarketInfoViewDelegate,LDPMHallHotGoodsListDelegate,LDAutoScrollAdViewDataSource, LDAutoScrollAdViewDelegate>

@property (nonatomic, strong) NPMMarketInfoService *marketInfoService;
@property (nonatomic, strong) MSWeakTimer *marketInfoTimer;
@property (nonatomic, weak) LDPMNewUserActivityView *activityView;
@property (nonatomic, assign) BOOL socketAlive;


#pragma mark V2.13 added
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UIView *tableHeaderViewBase;
@property(nonatomic, strong) LDPMHallEditableMarketInfoView *marketInfoView;
@property(nonatomic, strong) LDAutoScrollAdView *autoScrollAdView;
@property(nonatomic, strong) NSLayoutConstraint *adViewSeperatorHeightConstaint;//广告页面下面的空白条高度约束
@property(nonatomic, strong) LDPMHallGuideBar *guideBar;

//暂时用于新手引导、用户活动、新消息、热门交易品等。
@property(nonatomic, strong) LDPMHallDataController *oldDataController;
@property(nonatomic, strong) LDPMSeperatedHallDataSource *dataSource;
@property(nonatomic, strong) NSMutableArray *hotGoodsList;


@end

@implementation LDPMSeperatedHallViewController

#pragma mark - Life cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.view addSubview:self.tableView];
    [self.tableView autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero excludingEdge:ALEdgeTop];
    [self.tableView autoPinToTopLayoutGuideOfViewController:self withInset:0.0];
    
    self.tableView.tableHeaderView = self.tableHeaderViewBase;
    [self.tableHeaderViewBase addSubview:self.autoScrollAdView];
    
    UIView *tmpSeperator = [LDPMSeperatorView emptySeperator];
    [self.tableHeaderViewBase addSubview:tmpSeperator];
    [tmpSeperator autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.autoScrollAdView];
    [tmpSeperator autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [tmpSeperator autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    self.adViewSeperatorHeightConstaint = [tmpSeperator autoSetDimension:ALDimensionHeight toSize:10.];
    
    [self.tableHeaderViewBase addSubview:self.marketInfoView];
    [self.marketInfoView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:tmpSeperator withOffset:0.0];
    [self.marketInfoView autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [self.marketInfoView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    [self.marketInfoView autoSetDimension:ALDimensionHeight toSize:120.];
    
    tmpSeperator = [LDPMSeperatorView emptySeperator];
    [self.tableHeaderViewBase addSubview:tmpSeperator];
    [tmpSeperator autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.marketInfoView];
    [tmpSeperator autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [tmpSeperator autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    [tmpSeperator autoSetDimension:ALDimensionHeight toSize:10.];
    
    [self.view addSubview:self.guideBar];
    [self.guideBar autoSetDimension:ALDimensionHeight toSize:KDefaultHeightOfGuideBar];
    [self.guideBar autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero excludingEdge:ALEdgeTop];
    
    
    // Do any additional setup after loading the view.
    [self setupNavigationBar];
    [self setupPullDownRefresh];
    [self refreshNewUserActivityIcon];
    [self registerCells];
    
    [self.tableView.mj_header beginRefreshing];
    
    self.view.backgroundColor = [UIColor colorWithRed:10./255. green:40./255. blue:72./255. alpha:1.];
    self.tableView.backgroundColor = [NPMColor mainBackgroundColor];
    
    @weakify(self)
    [[LDSocketPushClient defaultClient] addErrorObserver:self usingBlock:^(NSError *error) {
        @strongify(self)
        if (error.code == LDSocketPushClientErrorTypeDisconnected) {
            self.socketAlive = NO;
        }
    }];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(guideViewDidDisappearNotification:) name:LDPMNotificationGuideViewDidDisappear object:nil];
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loginStatusChangedNotification:) name:NPMUserSessionLoginStatusChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAppWillEnterForegroundNotification:) name:UIApplicationWillEnterForegroundNotification object:nil];
    
    [LDPMUserEvent addEvent:EVENT_HOME_NEWPAGE tag:@"新首页展示"];
    
    if (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable) {
        // 注册预览视图的代理和来源视图
        [self registerForPreviewingWithDelegate:(id)self sourceView:self.view];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    
    self.activityView.hidden = NO;
    [self subscribeMessageForGoodsList:self.hotGoodsList];
    [self fetchAllHallSubjectsInfo];
    [self resetHeaderHeight];
    [self.guideBar updateGuideBar];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (![LDPMLaunchGuideViewController needShow]) {
        if ([self.oldDataController shouldAutoShowActivityView]) {
            [self newUserAcvitityIconAction:nil];
        }
        
        if ([self.oldDataController shouldShowGeneralActivity]) {
            [self showGeneralActivity:nil];
        }
    }
    [self startAutoRefreshMarketInfo];
    [self refreshMarketInfo]; // 页面出现时, 手动刷新一次行情
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    
    self.activityView.hidden = YES;
    [self unsubscribeMessageForGoodsList:self.hotGoodsList];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [self pauseAutoRefreshMarketInfo];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_marketInfoTimer invalidate];
    _marketInfoTimer = nil;
}

// If you return nil, a preview presentation will not be performed
- (nullable UIViewController *)previewingContext:(id <UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location NS_AVAILABLE_IOS(9_0)
{
    if (CGRectContainsPoint(self.marketInfoView.frame, location)) {
        //previewingContext.sourceRect = CGRectMake(0, 0, 100,100);//最开始轻按时除了这个框外，都变模糊
        NPMProductViewController *productViewController = [NPMProductViewController new];
        for(LDPMHallMarketInfoView *marketInfoView in [self recursionViewListFromView:self.marketInfoView ofSomeKind:[LDPMHallMarketInfoView class]]) {
            CGRect convertedRect = [marketInfoView convertRect:marketInfoView.bounds toView:self.view];
            if (CGRectContainsPoint(convertedRect, location)) {
                NPMProduct *product = [NPMProduct productWithGoodsId:marketInfoView.marketInfo.goodsId goodsName:marketInfoView.marketInfo.goodsName partnerId:marketInfoView.marketInfo.partnerId];
                for (NPMProduct *obj in self.hotGoodsList) {
                    if ([obj.partnerId isEqualToString:product.partnerId] && [obj.goodsId isEqualToString:product.goodsId]) {
                        product.enableTrade = obj.enableTrade;
                    }
                }
                productViewController.product = product;
                productViewController.marketInfo = marketInfoView.marketInfo;
                
                previewingContext.sourceRect = convertedRect;
                break;
            }
        }
        //productViewController.preferredContentSize = CGSizeMake(0, 300);//预览框的大小
        return productViewController;
    } else {
        return nil;
    }
}

- (void)previewingContext:(id <UIViewControllerPreviewing>)previewingContext commitViewController:(UIViewController *)viewControllerToCommit NS_AVAILABLE_IOS(9_0)
{
    [LDPMUserEvent addEvent:EVENT_HOT_PRODUCT tag:((NPMProductViewController *)viewControllerToCommit).marketInfo.goodsName];
    [LDPMUserEvent addEvent:EVENT_PRODUCT_CHART_ENTRANCE tag:@"首页热门交易品"];
    [self.navigationController pushViewController:viewControllerToCommit animated:YES];
}

- (NSArray *)recursionViewListFromView:(UIView *)aView ofSomeKind:(Class)aClass
{
    NSMutableArray *mutableArray = [NSMutableArray array];
    for (UIView *subView in aView.subviews) {
        if ([subView isKindOfClass:aClass]) {
            [mutableArray addObject:subView];
        } else {
            NSArray *recursionArray = [self recursionViewListFromView:subView ofSomeKind:aClass];
            [mutableArray addObjectsFromArray:recursionArray];
        }
    }
    return [mutableArray copy];
}

- (void)setupNavigationBar
{
    UIImageView *titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"logotitle"]];
    self.navigationItem.titleView = titleView;
}

- (void)setupPullDownRefresh
{
    @weakify(self);
    self.tableView.mj_header = [LDPMTableViewHeader headerWithRefreshingBlock:^{
        @strongify(self)
        
        [self fetchActivitiesWithCompletion:^{
            
        }];
        
        [self refreshAdViewInfo];
        
        [self fetchAllHallSubjectsInfo];
        
        [self refreshMarketInfo];
    }];
}

- (void)registerCells
{
    UINib *emptyCellNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallEmptyCell class]) bundle:nil];
    UINib *newsCellNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallNewsCell class]) bundle:nil];
    UINib *strategyCellNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallStrategyCell class]) bundle:nil];
    UINib *dateCellNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallDateCell class]) bundle:nil];
    UINib *quotationReplayNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallQuotationReplayCell class]) bundle:nil];
    UINib *schoolNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallSchoolCell class]) bundle:nil];
    UINib *attentionRankCell = [UINib nibWithNibName:NSStringFromClass([LDPMHallAttentionRankCell class]) bundle:nil];
    UINib *profitRankCell = [UINib nibWithNibName:NSStringFromClass([LDPMHallProfitRankCell class]) bundle:nil];
    UINib *sectionHeaderCell = [UINib nibWithNibName:NSStringFromClass([LDPMHallSectionHeaderCell class]) bundle:nil];
    UINib *marketInfoLiveCell = [UINib nibWithNibName:NSStringFromClass([LDPMHallMarketInfoLiveCell class]) bundle:nil];
    
    [self.tableView registerNib:emptyCellNib forCellReuseIdentifier:NSStringFromClass([LDPMHallEmptyCell class])];
    [self.tableView registerNib:newsCellNib forCellReuseIdentifier:NSStringFromClass([LDPMHallNewsCell class])];
    [self.tableView registerNib:strategyCellNib forCellReuseIdentifier:NSStringFromClass([LDPMHallStrategyCell class])];
    [self.tableView registerNib:dateCellNib forCellReuseIdentifier:NSStringFromClass([LDPMHallDateCell class])];
    [self.tableView registerNib:quotationReplayNib forCellReuseIdentifier:NSStringFromClass([LDPMHallQuotationReplayCell class])];
    [self.tableView registerNib:schoolNib forCellReuseIdentifier:NSStringFromClass([LDPMHallSchoolCell class])];
    [self.tableView registerClass:[LDPMHallSeperatorCell class] forCellReuseIdentifier:NSStringFromClass([LDPMHallSeperatorCell class])];
    [self.tableView registerNib:attentionRankCell forCellReuseIdentifier:NSStringFromClass([LDPMHallAttentionRankCell class])];
    [self.tableView registerNib:profitRankCell forCellReuseIdentifier:NSStringFromClass([LDPMHallProfitRankCell class])];
    [self.tableView registerNib:sectionHeaderCell forCellReuseIdentifier:NSStringFromClass([LDPMHallSectionHeaderCell class])];
    [self.tableView registerNib:marketInfoLiveCell forCellReuseIdentifier:NSStringFromClass([LDPMHallMarketInfoLiveCell class])];
    
    [LDPMHallLivePostCell ec_registerToTableView:self.tableView];
    [LDPMHallPromotionCell ec_registerToTableView:self.tableView];
    [LDPMErrorCell ec_registerToTableView:self.tableView];
}

#pragma mark - Setters & Getters
- (LDPMHallGuideBar*)guideBar
{
    if (!_guideBar) {
        _guideBar = [[LDPMHallGuideBar alloc] initWithAdjustTableView:self.tableView];
    }
    return _guideBar;
}

- (LDPMHallDataController*)oldDataController
{
    return _oldDataController?:(_oldDataController = [LDPMHallDataController new]);
}

- (NPMMarketInfoService*)marketInfoService
{
    return _marketInfoService?:(_marketInfoService = [NPMMarketInfoService new]);
}

- (NSMutableArray *)hotGoodsList
{
    if (_hotGoodsList == nil) {
        return [LDPMHallHotGoodsListViewController getUserLocalHotGoodsList];
    }
    
    return _hotGoodsList;
}

- (LDPMSeperatedHallDataSource*)dataSource
{
    if (!_dataSource) {
        _dataSource = [LDPMSeperatedHallDataSource new];
        _dataSource.hostTableView = self.tableView;
    }
    return _dataSource;
}

- (UITableView*)tableView
{
    if (!_tableView) {
        _tableView = [[UITableView alloc] init];
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tableView.dataSource = self.dataSource;
        _tableView.delegate = self.dataSource;
    }
    return _tableView;
}

- (UIView*)tableHeaderViewBase
{
    return _tableHeaderViewBase?:(_tableHeaderViewBase = [[UIView alloc] init]);
}

- (LDAutoScrollAdView*)autoScrollAdView
{
    if (!_autoScrollAdView) {
        _autoScrollAdView = [[LDAutoScrollAdView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.width / 320. * 110.) dataSource:self delegate:self];
    }
    return _autoScrollAdView;
}

- (LDPMHallEditableMarketInfoView*)marketInfoView {
    if (!_marketInfoView) {
        _marketInfoView = [[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([LDPMHallEditableMarketInfoView class]) owner:nil options:nil] firstObject];
        _marketInfoView.delegate = self;
        [_marketInfoView updateScrollPageLabel];
    }
    return _marketInfoView;
}

- (void)resetHeaderHeight
{
    //头部高度设置
    [self.tableHeaderViewBase layoutIfNeeded];
    CGFloat height = 0.0;
    for (UIView *view in self.tableHeaderViewBase.subviews) {
        if (CGRectGetMaxY(view.frame) > height) {
            height = CGRectGetMaxY(view.frame);
        }
    }
    CGRect newFrame = self.tableHeaderViewBase.frame;
    newFrame.size.height = height;
    self.tableHeaderViewBase.frame = newFrame;
    self.tableView.tableHeaderView  = self.tableHeaderViewBase;
}

#pragma mark - Fetch data & refresh view

- (void)fetchAllHallSubjectsInfo
{
    @weakify(self)
    [self startBasicActivity];
    [self.dataSource fetchHallSubjectsWithCallback:^(LDPMSeperatedHallDataController *dataController, NSError *error) {
        @strongify(self);
        [self stopBasicActivity];
        if (!error) {
            [self.tableView reloadData];
        }
        [self.tableView.mj_header endRefreshing];
    }];
}

- (void)fetchActivitiesWithCompletion:(void (^)(void))completion
{
    @weakify(self)
    [self.oldDataController fetchHallActivityWithCompletion:^(BOOL success, NSError *httpError, NSError *error, HomePageActivity *activity) {
        @strongify(self)
        [self refreshNewUserActivityIcon];
        if ([self.oldDataController shouldAutoShowActivityView] && ![LDPMLaunchGuideViewController needShow]) {
            [self newUserAcvitityIconAction:nil];
        }
        if ([self.oldDataController shouldShowGeneralActivity] && ![LDPMLaunchGuideViewController needShow]) {
            [self showGeneralActivity:nil];
        }
        
        if (completion) {
            completion();
        }
    }];
}

#pragma mark - Actions

- (void)showActivity:(HomePageActivity *)activity completion:(dispatch_block_t)completion
{
    if (self.activityView) {//已有活动在显示中时不重叠显示
        return;
    }
    
    LDPMNewUserActivityView *activityView = [[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([LDPMNewUserActivityView class]) owner:nil options:nil] firstObject];
    self.activityView = activityView;
    
    NSURL *url = [NSURL URLWithString:activity.imageURI];
    if (url) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:url];
            UIImage *image = [[SDImageCache sharedImageCache] imageFromDiskCacheForKey:key];
            
            if (!image) {
                NSData *data = [NSData dataWithContentsOfURL:url];
                image = [[UIImage alloc] initWithData:data];
                [[SDImageCache sharedImageCache] storeImage:image forKey:key];
            }
            
            if (!self.view.window) {//只有用户处于首页时才显示
                self.activityView = nil;
                return;
            }
            if (!image) {
                self.activityView = nil;
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                activityView.delegate = self;
                [activityView showActivity:activity image:image inView:self.tabBarController.view];
                
                if (completion) {
                    completion();
                }
            });
        });
    }
}

- (void)newUserAcvitityIconAction:(id)sender
{
    [LDPMUserEvent addEvent:EVENT_NEWBIE tag:@"礼包"];
    @weakify(self)
    [self showActivity:[self.oldDataController userActivity] completion:^{
        @strongify(self)
        
        [self.oldDataController setActivityViewHasShown];
    }];
}

- (void)showGeneralActivity:(id)sender
{
    @weakify(self)
    [self showActivity:[self.oldDataController generalActivity] completion:^{
        @strongify(self)
        
        [self.oldDataController markGeneralActivityHasShown];
    }];
}

#pragma mark - Notifications

- (void)handleAppWillEnterForegroundNotification:(NSNotification *)notification
{
    [self fetchActivitiesWithCompletion:nil];
    [self fetchAllHallSubjectsInfo];
}

- (void)guideViewDidDisappearNotification:(NSNotification *)notification
{
    if ([self.oldDataController shouldAutoShowActivityView]) {
        [self newUserAcvitityIconAction:nil];
    }
    if ([self.oldDataController shouldShowGeneralActivity]) {
        [self showGeneralActivity:nil];
    }
}

//- (void)loginStatusChangedNotification:(NSNotification *)notification
//{
//    @weakify(self)
//    [self.oldDataController fetchHallActivityWithCompletion:^(BOOL success, NSError *httpError, NSError *error, HomePageActivity *activity) {
//        @strongify(self);
//        [self refreshNewUserActivityIcon];
//    }];
//    
//    [self updateHallHotGoods:[LDPMHallHotGoodsListViewController getUserLocalHotGoodsList]];
//}

#pragma mark - New user activity

- (void)refreshNewUserActivityIcon
{
    if (self.oldDataController.shouldShowActivityButton) {
        UIImageView *newUserActivityView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"icon_NewUserActivity"]];
        newUserActivityView.userInteractionEnabled = YES;
        UITapGestureRecognizer *tapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(newUserAcvitityIconAction:)];
        [newUserActivityView addGestureRecognizer:tapGR];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:newUserActivityView];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

#pragma mark - Market Info

- (void)startAutoRefreshMarketInfo
{
    self.marketInfoTimer = [MSWeakTimer scheduledTimerWithTimeInterval:5.0
                                                                target:self
                                                              selector:@selector(autoRefreshMarketInfo)
                                                              userInfo:nil
                                                               repeats:YES
                                                         dispatchQueue:dispatch_get_main_queue()];
}

- (void)pauseAutoRefreshMarketInfo
{
    [_marketInfoTimer invalidate];
}

- (void)autoRefreshMarketInfo
{
    if (self.socketAlive) {
        return;
    }
    
    [self refreshMarketInfo];
}

- (void)refreshAdViewInfo
{
    @weakify(self);
    [self.oldDataController fetchAdWithCompletion:^(BOOL success, NSError *httpError, NSError *error, NSArray *adArray) {
        @strongify(self);
        if (adArray.count > 0) {
            if (self.autoScrollAdView.hidden == YES) {
                self.autoScrollAdView.hidden = NO;
                CGRect newFrame = self.autoScrollAdView.frame;
                newFrame.size.height = [UIScreen mainScreen].bounds.size.width * 11./32.;
                self.autoScrollAdView.frame = newFrame;
                self.adViewSeperatorHeightConstaint.constant = 10.;
            }
            
            [self.autoScrollAdView reloadData];
        } else {
            if (self.autoScrollAdView.hidden == NO) {
                self.autoScrollAdView.hidden = YES;
                CGRect newFrame = self.autoScrollAdView.frame;
                newFrame.size.height = 0;
                self.autoScrollAdView.frame = newFrame;
                self.adViewSeperatorHeightConstaint.constant = 0.;
            }
        }
        
        [self resetHeaderHeight];
    }];
}

- (void)refreshMarketInfo
{
    @weakify(self)
    [self.marketInfoService fetchRealTimeMarketInfoForProductList:self.hotGoodsList completion:^(NPMRetCode responseCode, NSError *error, NSDictionary *marketInfoDic) {
        @strongify(self)
        [self.marketInfoView setContentWithGoodsList:self.hotGoodsList marketInfoDic:marketInfoDic];
    }];
}

- (void)unsubscribeMessageForGoodsList:(NSArray *)list
{
    @weakify(self)
    for (NPMProduct *product in list) {
        NSString *topic = [LDPMSocketMessageTopicUtil simplePriceTopicWithPartnerId:product.partnerId goodsId:product.goodsId];
        @strongify(self)
        [[LDSocketPushClient defaultClient] removeObserver:self topic:topic];
    }
}

- (void)subscribeMessageForGoodsList:(NSArray *)list
{
    @weakify(self)
    for (NPMProduct *product in list) {
        NSString *topic = [LDPMSocketMessageTopicUtil simplePriceTopicWithPartnerId:product.partnerId goodsId:product.goodsId];
        [[LDSocketPushClient defaultClient] addObserver:self topic:topic pushType:LDSocketPushTypeGroup usingBlock:^(LDSPMessage *message) {
            @strongify(self)
            if ([message.topic isEqualToString:topic]) {
                id object = [NSJSONSerialization JSONObjectWithData:message.body
                                                            options:NSJSONReadingMutableContainers
                                                              error:NULL];
                NPMRealTimeMarketInfo *marketInfo = [[NPMRealTimeMarketInfo alloc] initWithArray:object];
                if (marketInfo) {
                    [self.marketInfoView setContentWithMarketInfo:marketInfo];
                    
                    self.socketAlive = YES;
                }
            }
        }];
    }
}

#pragma mark - LDAutoScrollAdViewDataSource & Delegate

- (NSInteger)numberOfImageInAutoScrollAdView:(LDAutoScrollAdView *)adView
{
    return self.oldDataController.adArray.count;
}

- (NSURL *)autoScrollAdView:(LDAutoScrollAdView *)adView imageURLForImageAtIndex:(NSInteger)index
{
    AdBanner *ad = self.oldDataController.adArray[index];
    return [NSURL URLWithString:ad.imageURI];
}

- (UIImage *)placeHolderImageForAutoScrollAdView:(LDAutoScrollAdView *)adView
{
    return [UIImage imageNamed:@"news_default"];
}

- (void)autoScrollAdView:(LDAutoScrollAdView *)adView didSelectImageAtIndex:(NSInteger)index
{
    [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:[NSString stringWithFormat:@"轮播图%@", @(index + 1)]];
    AdBanner *ad = self.oldDataController.adArray[index];
    if (ad.uri) {
        [JLRoutes routeURL:[NSURL URLWithString:ad.uri]];
    }
}

#pragma mark - LDPMHallEditableMarketInfoViewDelegate
- (void)marketInfoView:(LDPMHallEditableMarketInfoView *)view didSelectMarketInfo:(NPMRealTimeMarketInfo *)marketInfo {
    [LDPMUserEvent addEvent:EVENT_HOT_PRODUCT tag:marketInfo.goodsName];
    [LDPMUserEvent addEvent:EVENT_PRODUCT_CHART_ENTRANCE tag:@"首页热门交易品"];
    
    NPMProduct *product = [NPMProduct productWithGoodsId:marketInfo.goodsId goodsName:marketInfo.goodsName partnerId:marketInfo.partnerId];
    for (NPMProduct *obj in self.hotGoodsList) {
        if ([obj.partnerId isEqualToString:product.partnerId] && [obj.goodsId isEqualToString:product.goodsId]) {
            product.enableTrade = obj.enableTrade;
        }
    }
    
    NPMProductViewController *productViewController = [NPMProductViewController new];
    productViewController.product = product;
    productViewController.marketInfo = marketInfo;
    productViewController.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:productViewController animated:YES];
}

- (void)marketInfoView:(LDPMHallEditableMarketInfoView *)view gotoHotGoodsListView:(id)sender {
    LDPMHallHotGoodsListViewController *vc = [[UIStoryboard storyboardWithName:@"LDPMHall" bundle:nil] instantiateViewControllerWithIdentifier:@"LDPMHallHotGoodsListViewController"];
    vc.hotGoodsListDelegate = self;
    vc.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - LDPMHallHotGoodsListDelegate

- (void)updateHallHotGoods:(NSMutableArray *)goodsList
{
    [self unsubscribeMessageForGoodsList:self.hotGoodsList];
    [self subscribeMessageForGoodsList:goodsList];
    
    self.hotGoodsList = [NSMutableArray arrayWithArray:goodsList];
    [self.marketInfoView updateScrollViewWithGoodsList:goodsList];
    [self refreshMarketInfo];
}

#pragma mark - LDPMNewUserActivityViewDelegate

- (void)closeActivityView:(LDPMNewUserActivityView *)activityView
{
    if ([activityView.activity.activityEnName isEqualToString:[self.oldDataController userActivity].activityEnName]) {//新手活动缩小到右上角“礼包”
        [LDPMUserEvent addEvent:EVENT_NEWBIE tag:@"关闭"];
        [activityView dismissAnimated:YES];
    } else {//通用活动直接关闭
        [LDPMUserEvent addEvent:EVENT_ACTIVITY tag:@"关闭"];
        [activityView dismiss];
    }
}

- (void)newUserActivityViewDidSelectConfirmButton:(LDPMNewUserActivityView *)activityView
{
    if ([activityView.activity.activityEnName isEqualToString:[self.oldDataController userActivity].activityEnName]) {//新手活动先登录再跳转
        [LDPMUserEvent addEvent:EVENT_NEWBIE tag:@"进入"];
        [NPMLoginAction loginWithSuccessBlock:^{
            [activityView dismiss];
            if (activityView.activity.uri) {
                [JLRoutes routeURL:[NSURL URLWithString:activityView.activity.uri]];
            }
        } andFailureBlock:nil];
    } else {//通用活动直接跳转
        [LDPMUserEvent addEvent:EVENT_ACTIVITY tag:@"进入"];
        [activityView dismiss];
        if (activityView.activity.uri) {
            [JLRoutes routeURL:[NSURL URLWithString:activityView.activity.uri]];
        }
    }
}

#pragma mark - 常驻页面统计

- (NSString *)pageEventParam
{
    return @"@1";
}


@end

