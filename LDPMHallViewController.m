//
//  LDPMHallViewController.m
//  PreciousMetals
//
//  Created by LiuLiming on 15/6/23.
//  Copyright (c) 2015年 NetEase. All rights reserved.
//

#import "LDPMHallViewController.h"
#import "LDPMHallGuideBar.h"
#import "LDPMHallMarketInfoLiveCell.h"
#import "LDPMSeperatedHallDataController.h"
#import "LDPMHallSectionModel.h"
#import "LDPMHallMarketInfoLiveModel.h"
#import "LDPMHallSectionHeaderCell.h"
#import "LDPMHallSectionModel.h"
#import "LDPMHallMarketInfoView.h"

NSString * const LDPMHomeTabBarDidSelectHallNotification = @"LDPMHomeTabBarDidSelectHallNotification";

NSTimeInterval const LDPMNotificationCellShowingTimeInterval = 900.;

@interface LDPMHallViewController () <UITableViewDataSource, UITableViewDelegate, LDAutoScrollAdViewDataSource, LDAutoScrollAdViewDelegate, LDPMHallMarketInfoCellDelegate, LDPMNewUserActivityViewDelegate, LDPMHallCalendarViewDelegate, LDPMHallNotificationCellDelegate, LDPMHallHotGoodsListDelegate, LDPMHallNewMessageViewDelegate>

@property (nonatomic, strong) LDPMHallDataController *dataController;
@property (nonatomic, strong) NPMMarketInfoService *marketInfoService;
@property (strong, nonatomic) IBOutlet UITableView *tableView;

@property (strong, nonatomic) IBOutlet LDPMHallNotificationCell *notificationCell;
@property (strong, nonatomic) IBOutlet LDPMHallAdCell *adCell;
@property (strong, nonatomic) IBOutlet LDPMProfitUserCell *topProfitCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *moreProductCell;
@property (weak, nonatomic) IBOutlet UILabel *scrollPageLabel;

@property (strong, nonatomic) IBOutlet LDPMHallMarketInfoCell *marketInfoCell;
@property (nonatomic, strong) LDPMHallNoDataCell *noDataCell;

@property (nonatomic, readonly) LDPMSegmentedControl *segmentedControl;
@property (nonatomic, readonly) LDPMHallCalendarView *calendarView;
@property (nonatomic, readonly) LDPMHallNewMessageView *messageView;
@property (nonatomic, strong) LDPMHallSectionHeaderView *sectionHeaderView;

@property (nonatomic, strong) MSWeakTimer *marketInfoTimer;
@property (nonatomic, strong) MSWeakTimer *notificationCellTimer;
@property (nonatomic, strong) MSWeakTimer *financeNewsTimer;

@property (nonatomic, assign) BOOL shouldShowErrorViewForNews;
@property (nonatomic, assign) BOOL shouldShowErrorViewForFinanceNews;

@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;

@property (nonatomic,weak) LDPMNewUserActivityView *activityView;

@property (nonatomic,assign) BOOL socketAlive;

@property (strong, nonatomic) NSMutableArray *hotGoodsList;

@property (nonatomic, assign) BOOL hasNewMessage;
@property (nonatomic, strong) LDPMHallGuideBar *guideBar;
@property (nonatomic, strong) LDPMHallSectionHeaderCell *marketInfoLiveHeaderCell;
@property (nonatomic, strong) LDPMHallSectionModel *marketInfoLiveHeaderModel;
@property (nonatomic, weak) LDPMHallMarketInfoLiveCell *marketInfoLiveCell;
@property (nonatomic, strong) LDPMSeperatedHallDataController *hallDataController;
@property (nonatomic, strong) NSArray *marketInfoLiveModelArray;

@end

@implementation LDPMHallViewController

#pragma mark - Life cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.view addSubview:self.guideBar];
    [self.guideBar autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero excludingEdge:ALEdgeTop];
    [self.guideBar autoSetDimension:ALDimensionHeight toSize:44.];
    
    // Do any additional setup after loading the view.
    self.dataController = [LDPMHallDataController new];
    self.hallDataController = [LDPMSeperatedHallDataController new];
    self.marketInfoService = [NPMMarketInfoService new];
    [self setupNavigationBar];
    [self setupPullDownRefresh];
    [self setupPullUpRefresh];
    [self refreshNewUserActivityIcon];
    [self registerCells];
    [self setupSectionHeader];
    
    self.tableView.backgroundColor = [NPMColor mainBackgroundColor];
    
    [self.tableView.mj_header beginRefreshing];
    
    self.view.backgroundColor = [UIColor colorWithRed:10./255. green:40./255. blue:72./255. alpha:1.];
    NSLayoutConstraint *topMargin = [NSLayoutConstraint constraintWithItem:self.topLayoutGuide attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.tableView attribute:NSLayoutAttributeTop multiplier:1.0 constant:0.0];
    topMargin.priority = UILayoutPriorityDefaultHigh;
    [self.view addConstraint:topMargin];
    
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(homeTabBarDidSelectHallNotification:) name:LDPMHomeTabBarDidSelectHallNotification object:nil];

    [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:@"老首页展示"];

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
    [self.calendarView updateView];
    [self subscribeMessageForGoodsList:self.hotGoodsList];
    [self subscribeMarkInfoLive];
    [self.guideBar updateGuideBar];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (![LDPMLaunchGuideViewController needShow]) {
        if ([self.dataController shouldShowNotificationCell]) {
            [self prepareForHidingNotificationCell];
        }
        if ([self.dataController shouldAutoShowActivityView]) {
            [self newUserAcvitityIconAction:nil];
        }
        
        if ([self.dataController shouldShowGeneralActivity]) {
            [self showGeneralActivity:nil];
        }
    }
    [self startAutoRefreshMarketInfo];
    [self refreshMarketInfo]; // 页面出现时, 手动刷新一次行情
    [self startAutoFetchFinanceNews];
    
    @weakify(self)
    [self.dataController subscribeSocketForNewReportWithCompletion:^(BOOL hasNewReport, NSString *hintMessage) {
        @strongify(self)
        if (self.segmentedControl.selectedSegmentIndex == 0 && hasNewReport) {
            self.hasNewMessage = YES;
            [self.tableView beginUpdates];
            self.messageView.title = hintMessage;
            [self.tableView endUpdates];
            [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:@"消息提示出现"];
        }
    }];
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
    [self pauseAutoFetchFinanceNews];
    [self.dataController unsubscribeSocketForNewReport];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_marketInfoTimer invalidate];
    _marketInfoTimer = nil;
    [_notificationCellTimer invalidate];
    _notificationCellTimer = nil;
    
    [self unsubscribeMarkInfoLive];
}

// If you return nil, a preview presentation will not be performed
- (nullable UIViewController *)previewingContext:(id <UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location NS_AVAILABLE_IOS(9_0)
{
    if (CGRectContainsPoint(self.marketInfoCell.frame, location)) {
        //previewingContext.sourceRect = CGRectMake(0, 0, 100,100);//最开始轻按时除了这个框外，都变模糊
        NPMProductViewController *productViewController = [NPMProductViewController new];
        for(LDPMHallMarketInfoView *marketInfoView in [self recursionViewListFromView:self.marketInfoCell ofSomeKind:[LDPMHallMarketInfoView class]]) {
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
        @strongify(self);
        
        [self fetchActivitiesWithCompletion:^{
            
        }];
        
        [self.dataController fetchAdWithCompletion:^(BOOL success, NSError *httpError, NSError *error, NSArray *adArray) {
            @strongify(self);
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:1 inSection:0];
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            [self.adCell.adView reloadData];
        }];
        
        [self.dataController fetchTopProfitWithCompletion:^(BOOL success, NSError *httpError, NSError *error, NSArray *topProfitArray) {
            @strongify(self);
            self.topProfitCell.profitUserArray = topProfitArray;
        }];
        
        [self.marketInfoService fetchRealTimeMarketInfoForProductList:self.hotGoodsList completion:^(NPMRetCode responseCode, NSError *error, NSDictionary *marketInfoDic) {
            @strongify(self);
            [self.marketInfoCell setContentWithGoodsList:self.hotGoodsList marketInfoDic:marketInfoDic];
        }];
        
        [self.hallDataController fetchHallSubjects:@[LDPMHallSubjectTypeMarketInfoLiveID] withCallback:^(LDPMSeperatedHallDataController *dataController, NSError *error) {
            self.marketInfoLiveCell.model = [self.marketInfoLiveModelArray firstObject];
        }];
        
        if (self.segmentedControl.selectedSegmentIndex == 0) {
            [self fetchLatestNewsWithCompletion:^{
                @strongify(self);
                [self.tableView.mj_header endRefreshing];
                
            }];
        } else {
            [self.calendarView updateView];
            [self fetchLatestFinanceNewsInDate:self.calendarView.selectedDate completion:^{
                @strongify(self);
                [self.tableView.mj_header endRefreshing];
            }];
        }
        
        [self refreshMarketInfo];
    }];
}

- (void)setupPullUpRefresh
{
    @weakify(self);
    self.tableView.mj_footer = [LDPMTableViewFooter footerWithRefreshingBlock:^{
        @strongify(self);
        if (self.segmentedControl.selectedSegmentIndex == 0) {
            if (self.dataController.newsArray.count > 0 && !self.dataController.newsReachEnd) {
                [self fetchMoreNewsWithCompletion:^{
                    [self.tableView.mj_footer endRefreshing];
                }];
            } else {
                [self.tableView.mj_footer endRefreshing];
            }
        }
    }];
}

- (void)registerCells
{
    UINib *emptyCellNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallEmptyCell class]) bundle:nil];
    UINib *newsCellNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallNewsCell class]) bundle:nil];
    UINib *strategyCellNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallStrategyCell class]) bundle:nil];
    UINib *financeCellNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallFinanceCell class]) bundle:nil];
    UINib *dateCellNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallDateCell class]) bundle:nil];
    UINib *marketInfoLiveCellNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallMarketInfoLiveCell class]) bundle:nil];
    UINib *marketInfoLiveHeaderCellNib = [UINib nibWithNibName:NSStringFromClass([LDPMHallSectionHeaderCell class]) bundle:nil];
    
    [self.tableView registerNib:emptyCellNib forCellReuseIdentifier:NSStringFromClass([LDPMHallEmptyCell class])];
    [self.tableView registerNib:newsCellNib forCellReuseIdentifier:NSStringFromClass([LDPMHallNewsCell class])];
    [self.tableView registerNib:strategyCellNib forCellReuseIdentifier:NSStringFromClass([LDPMHallStrategyCell class])];
    [self.tableView registerNib:financeCellNib forCellReuseIdentifier:NSStringFromClass([LDPMHallFinanceCell class])];
    [self.tableView registerNib:dateCellNib forCellReuseIdentifier:NSStringFromClass([LDPMHallDateCell class])];
    [self.tableView registerNib:marketInfoLiveCellNib forCellReuseIdentifier:NSStringFromClass([LDPMHallMarketInfoLiveCell class])];
    [self.tableView registerNib:marketInfoLiveHeaderCellNib forCellReuseIdentifier:NSStringFromClass([LDPMHallSectionHeaderCell class])];
    
    [LDPMHallLivePostCell ec_registerToTableView:self.tableView];
    [LDPMHallPromotionCell ec_registerToTableView:self.tableView];
    [LDPMErrorCell ec_registerToTableView:self.tableView];
}

- (void)setupSectionHeader
{
    [self.sectionHeaderView setupSegmentedControl];
    [self.segmentedControl addTarget:self action:@selector(segmentedControlAction:) forControlEvents:UIControlEventValueChanged];
    
    self.messageView.delegate = self;
    
    self.calendarView.delegate = self;
    [self.calendarView performSelector:@selector(selectTodayAtFirstShow) withObject:nil afterDelay:0.0];
    self.calendarView.hidden = YES;
}

#pragma mark - Setters & Getters

- (LDPMHallGuideBar*)guideBar
{
    if (!_guideBar) {
        _guideBar = [[LDPMHallGuideBar alloc] initWithAdjustTableView:self.tableView];
    }
    return _guideBar;
}

- (NSMutableArray *)hotGoodsList
{
    if (_hotGoodsList == nil) {
        return [LDPMHallHotGoodsListViewController getUserLocalHotGoodsList];
    }

    return _hotGoodsList;
}

- (LDPMHallNoDataCell *)noDataCell
{
    if (!_noDataCell) {
        _noDataCell = [[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([LDPMHallNoDataCell class]) owner:nil options:nil] firstObject];
    }
    return _noDataCell;
}

- (LDAutoScrollAdView *)createAdView
{
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    LDAutoScrollAdView *adView = [[LDAutoScrollAdView alloc] initWithFrame:CGRectMake(0, 0, screenWidth, screenWidth / 320. * 110.) dataSource:self delegate:self];
    return adView;
}

- (LDPMHallSectionHeaderView *)sectionHeaderView
{
    if (!_sectionHeaderView) {
        _sectionHeaderView = [[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([LDPMHallSectionHeaderView class]) owner:nil options:nil] firstObject];
    }
    return _sectionHeaderView;
}

- (LDPMSegmentedControl *)segmentedControl
{
    return self.sectionHeaderView.segmentedControl;
}

- (LDPMHallCalendarView *)calendarView
{
    return self.sectionHeaderView.calendarView;
}

- (LDPMHallNewMessageView *)messageView
{
    return self.sectionHeaderView.messageView;
}

- (LDPMHallSectionHeaderCell *)marketInfoLiveHeaderCell
{
    if (_marketInfoLiveHeaderCell == nil) {
        _marketInfoLiveHeaderCell = [[[NSBundle mainBundle] loadNibNamed:@"LDPMHallSectionHeaderCell" owner:nil options:nil] firstObject];
    }
    return _marketInfoLiveHeaderCell;
}

- (LDPMHallSectionModel *)marketInfoLiveHeaderModel
{
    if (_marketInfoLiveHeaderModel == nil) {
        _marketInfoLiveHeaderModel = [LDPMHallSectionModel new];
        _marketInfoLiveHeaderModel.sectioName = @"行情播报";
        _marketInfoLiveHeaderModel.bMoreFlag = NO;
    }
    return _marketInfoLiveHeaderModel;
}

- (LDPMHallMarketInfoLiveCell *)marketInfoLiveCell
{
    if (_marketInfoLiveCell == nil) {
        _marketInfoLiveCell = [[[NSBundle mainBundle] loadNibNamed:@"LDPMHallMarketInfoLiveCell" owner:nil options:nil] firstObject];
    }
    return _marketInfoLiveCell;
}

- (NSArray *)marketInfoLiveModelArray
{
    NSArray *models = nil;
    
    for (LDPMHallSectionModel *sectionModel in self.hallDataController.hallSubjects) {
        if (sectionModel.type == LDPMHallSubjectTypeMarketInfoLive) {
            models = sectionModel.modelArray;
            break;
        }
    }
    return models;
}

#pragma mark - Fetch data & refresh view

- (void)fetchLatestNewsWithCompletion:(void (^)(void))completion
{
    self.shouldShowErrorViewForNews = NO;
    [self.activityIndicator startAnimating];
    @weakify(self);
    [self.dataController fetchLatestNewsWithCompletion:^(BOOL success, NSError *httpError, NSError *error, NSArray *newsArray) {
        @strongify(self);
        [self.activityIndicator stopAnimating];
        if (!success) {
            if (httpError && [self.dataController newsArray].count == 0) {
                self.shouldShowErrorViewForNews = YES;
            }
            [self showToast:error.localizedDescription];
        }
        if (success) {
            self.hasNewMessage = NO;
        }
        self.tableView.mj_footer.hidden = NO;
        [self.tableView reloadData];
        if (completion) {
            completion();
        }
    }];
}

- (void)fetchMoreNewsWithCompletion:(void (^)(void))completion
{
    @weakify(self);
    [self.dataController fetchMoreNewsWithCompletion:^(BOOL success, NSError *httpError, NSError *error, NSArray *newsArray) {
        @strongify(self);
        if (!success) {
            [self showToast:error.localizedDescription];
        }
        [self.tableView reloadData];
        if (completion) {
            completion();
        }
    }];
}

- (void)fetchLatestFinanceNewsInDate:(NSDate *)date completion:(void (^)(void))completion
{
    self.shouldShowErrorViewForFinanceNews = NO;
    [self.activityIndicator startAnimating];
    @weakify(self);
    [self.dataController fetchLatestFinanceNewsInDate:date completion:^(BOOL success, NSError *httpError, NSError *error, NSArray *newsArray) {
        @strongify(self);
        [self.activityIndicator stopAnimating];
        if (!success) {
            if (httpError && [self.dataController financeNewsArrayInDate:date].count == 0) {
                self.shouldShowErrorViewForFinanceNews = YES;
            }
            [self showToast:error.localizedDescription];
        }
        [self.tableView reloadData];
        if (completion) {
            completion();
        }
    }];
}

- (void)fetchActivitiesWithCompletion:(void (^)(void))completion
{
    @weakify(self)
    [self.dataController fetchHallActivityWithCompletion:^(BOOL success, NSError *httpError, NSError *error, HomePageActivity *activity) {
        @strongify(self)
        [self refreshNewUserActivityIcon];
        if ([self.dataController shouldAutoShowActivityView] && ![LDPMLaunchGuideViewController needShow]) {
            [self newUserAcvitityIconAction:nil];
        }
        if ([self.dataController shouldShowGeneralActivity] && ![LDPMLaunchGuideViewController needShow]) {
            [self showGeneralActivity:nil];
        }
        if ([self.dataController shouldShowNotificationCell]) {
            [self prepareForHidingNotificationCell];
        }
        [self reloadNotificationCell];
        
        if (completion) {
            completion();
        }
    }];
}

- (void)checkNewReport
{
    @weakify(self)
    [self.dataController checkNewReportWithCompletion:^(BOOL success, NSError *httpError, NSError *error, BOOL hasNewReport) {
        @strongify(self)
        if (hasNewReport) {
            if (self.segmentedControl.selectedSegmentIndex == 0 && hasNewReport) {
                self.hasNewMessage = YES;
                [self.tableView beginUpdates];
                [self.messageView setDefaultTitle];
                [self.tableView endUpdates];
                [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:@"消息提示出现"];
            }
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
    [self showActivity:[self.dataController userActivity] completion:^{
        @strongify(self)
        
        [self.dataController setActivityViewHasShown];
    }];
}

- (void)showGeneralActivity:(id)sender
{
    @weakify(self)
    [self showActivity:[self.dataController generalActivity] completion:^{
        @strongify(self)
        
        [self.dataController markGeneralActivityHasShown];
    }];
}

- (void)segmentedControlAction:(LDPMSegmentedControl *)segmentedControl
{
    @weakify(self)
    [self.tableView reloadData];
    if (self.segmentedControl.selectedSegmentIndex == 0) {
        [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:@"重要消息"];
        self.messageView.hidden = NO;
        self.calendarView.hidden = YES;
        [self fetchLatestNewsWithCompletion:^{
            @strongify(self)
            [self scrollTableViewToFirstNews];
        }];
    } else {
        [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:@"财经日历"];
        self.messageView.hidden = YES;
        self.calendarView.hidden = NO;
        [self.calendarView updateView];
        [self fetchLatestFinanceNewsInDate:self.calendarView.selectedDate completion:^{
            @strongify(self);
            [self scrollTableViewToFirstNews];
            [self.calendarView updateIndicatorPosition];
        }];
    }
}

- (IBAction)moreProductAction:(id)sender
{
    [self gotoLDPMHallHotGoodsListViewController];
    [LDPMUserEvent addEvent:EVENT_HOT_PRODUCT tag:@"编辑"];
}

#pragma mark - Notifications

- (void)handleAppWillEnterForegroundNotification:(NSNotification *)notification
{
    [self.calendarView updateView];
    [self fetchActivitiesWithCompletion:nil];
    if (self.segmentedControl.selectedSegmentIndex == 0) {
        [self checkNewReport];
    }
}

- (void)homeTabBarDidSelectHallNotification:(NSNotification *)notification
{
    if (self.segmentedControl.selectedSegmentIndex == 0) {
        [self checkNewReport];
    }
}

- (void)guideViewDidDisappearNotification:(NSNotification *)notification
{
    if ([self.dataController shouldAutoShowActivityView]) {
        [self newUserAcvitityIconAction:nil];
    }
    if ([self.dataController shouldShowGeneralActivity]) {
        [self showGeneralActivity:nil];
    }
    if ([self.dataController shouldShowNotificationCell]) {
        [self prepareForHidingNotificationCell];
    }
}

//- (void)loginStatusChangedNotification:(NSNotification *)notification
//{
//    @weakify(self)
//    [self.dataController fetchHallActivityWithCompletion:^(BOOL success, NSError *httpError, NSError *error, HomePageActivity *activity) {
//        @strongify(self);
//        [self refreshNewUserActivityIcon];
//        if (![self.dataController shouldShowNotificationCell]) {
//            [self.dataController notificationCellHasShown];
//        } else {
//            [self prepareForHidingNotificationCell];
//        }
//        [self reloadNotificationCell];
//    }];
//    
//    [self updateHallHotGoods:[LDPMHallHotGoodsListViewController getUserLocalHotGoodsList]];
//}

- (void)reloadNotificationCell
{
    [self.notificationCell setText:self.dataController.userActivity.title buttonTitle:[self.dataController buttonTitleForNotificationCell]];
    [self.tableView beginUpdates];
    self.notificationCell.hidden = ![self.dataController shouldShowNotificationCell];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    [self.tableView endUpdates];
}

#pragma mark - New user activity

- (void)refreshNewUserActivityIcon
{
    if (self.dataController.shouldShowActivityButton) {
        UIImageView *newUserActivityView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"icon_NewUserActivity"]];
        newUserActivityView.userInteractionEnabled = YES;
        UITapGestureRecognizer *tapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(newUserAcvitityIconAction:)];
        [newUserActivityView addGestureRecognizer:tapGR];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:newUserActivityView];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}


#pragma mark - Live Room

- (void)goToLiveRoomFromNews:(HomePageNews *)news
{
    NSString *roomId =  news.sourceId;
    if (roomId.length) {
        [self startMaskActivity:NSLocalizedString(@"Wait For Loading", nil)];
        [[LDPMLiveRoomListStore sharedStore] getLiveRoomWithRoomId:roomId forceLogin:YES completion:^(BOOL success, LDPMLiveRoom *liveRoom, NSError *error, NSError *httpError) {
            if (success) {
                if (liveRoom) {
                    LDPMLiveRoomDetailViewController *liveRoomViewController  = [[LDPMLiveRoomDetailViewController alloc] initWithLiveRoom:liveRoom];
                    liveRoomViewController.hidesBottomBarWhenPushed = YES;
                    [self.navigationController pushViewController:liveRoomViewController animated:YES];
                } else if (error.localizedDescription) {
                    [self showToast:error.localizedDescription];
                }
            } else if (error.localizedDescription) {
                [self showToast:httpError.localizedDescription];
            }
            
            [self stopMaskActivity];
        }];
    }
}

#pragma mark - Notification Cell

- (void)prepareForHidingNotificationCell
{
    if (self.notificationCellTimer) {
        return;
    }
    self.notificationCellTimer = [MSWeakTimer scheduledTimerWithTimeInterval:LDPMNotificationCellShowingTimeInterval target:self selector:@selector(hideNotificationCell) userInfo:nil repeats:NO dispatchQueue:dispatch_get_main_queue()];
}

- (void)hideNotificationCell
{
    [self.dataController notificationCellHasShown];
    [UIView animateWithDuration:1 delay:0.2 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    } completion:^(BOOL finished) {
    }];
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

- (void)refreshMarketInfo
{
    @weakify(self)
    [self.marketInfoService fetchRealTimeMarketInfoForProductList:self.hotGoodsList completion:^(NPMRetCode responseCode, NSError *error, NSDictionary *marketInfoDic) {
        @strongify(self)
        [self.marketInfoCell setContentWithGoodsList:self.hotGoodsList marketInfoDic:marketInfoDic];
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
                    [self.marketInfoCell setContentWithMarketInfo:marketInfo];///
                    
                    self.socketAlive = YES;
                }
            }
        }];
    }
}

#pragma mark MarketInfoLive Subscribe & Unsubscribe

- (void)subscribeMarkInfoLive {
    __weak typeof(self) weakSelf = self;
    NSString *topic = [LDPMSocketMessageTopicUtil hallMarketInfoLiveTopic];
    [[LDSocketPushClient defaultClient] addObserver:self topic:topic pushType:LDSocketPushTypeGroup usingBlock:^(LDSPMessage *message) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if ([message.topic isEqualToString:topic]) {
            id object = [NSJSONSerialization JSONObjectWithData:message.body
                                                        options:NSJSONReadingMutableContainers
                                                          error:NULL];
            LDPMHallMarketInfoLiveModel *liveModel = [LDPMHallMarketInfoLiveModel createModelWithJSONDictionary:object];
            if (liveModel) {
                [strongSelf updateMarketInfoLiveModel:@[liveModel]];
            }
        }
    }];
}

- (void)unsubscribeMarkInfoLive {
    NSString *topic = [LDPMSocketMessageTopicUtil hallMarketInfoLiveTopic];
    [[LDSocketPushClient defaultClient] removeObserver:self topic:topic];
}

- (void)updateMarketInfoLiveModel:(NSArray *)liveModelArray
{
    //更新行情播报
    self.marketInfoLiveCell.model = [liveModelArray firstObject];
}

#pragma mark - Auto Fetch Finance News

- (void)startAutoFetchFinanceNews
{
    self.financeNewsTimer = [MSWeakTimer scheduledTimerWithTimeInterval:5.0
                                                                 target:self
                                                               selector:@selector(autoFetchFinanceNews)
                                                               userInfo:nil
                                                                repeats:YES
                                                          dispatchQueue:dispatch_get_main_queue()];
}

- (void)pauseAutoFetchFinanceNews
{
    [_financeNewsTimer invalidate];
}

- (void)autoFetchFinanceNews
{
    if (self.segmentedControl.selectedSegmentIndex != 1) {
        return;
    }
    [self.dataController fetchLatestFinanceNewsInDate:self.calendarView.selectedDate completion:^(BOOL success, NSError *httpError, NSError *error, NSArray *newsArray) {
        if (self.segmentedControl.selectedSegmentIndex == 1) {
            [self.tableView reloadData];
        }
    }];
}


#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) {
        return self.dataController.cellTypeArrayInFirstSection.count;
    } else if (section == 1) {
        if (self.segmentedControl.selectedSegmentIndex == 0) {
            return MAX(1, [self.dataController newsArrayWithDateTag].count);
        } else {
            return MAX(1, [self.dataController financeNewsArrayInDate:self.calendarView.selectedDate].count);
        }
    }
    
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;
    NSInteger section = indexPath.section;
    NSInteger row = indexPath.row;
    if (section == 0) {
        enum LDPMHallCellType cellType = [self.dataController.cellTypeArrayInFirstSection[row] integerValue];
        switch (cellType) {
            case LDPMHallCellTypeNotification:
                self.notificationCell.hidden = ![self.dataController shouldShowNotificationCell];
                cell = self.notificationCell;
                self.notificationCell.delegate = self;
                [self.notificationCell setText:self.dataController.userActivity.title buttonTitle:[self.dataController buttonTitleForNotificationCell]];
                break;
                
            case LDPMHallCellTypeAd:
                if ([self.dataController shouldShowAdView]) {
                    cell = self.adCell;
                    if (!self.adCell.adView) {
                        LDAutoScrollAdView *adView = [self createAdView];
                        [self.adCell.contentView addSubview:adView];
                        self.adCell.adView = adView;
                        [adView reloadData];
                    }
                } else {
                    cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([LDPMHallEmptyCell class])];
                    [self.adCell.adView removeFromSuperview];
                }
                
                break;
                
            case LDPMHallCellTypeTopProfit:
                cell = self.topProfitCell;
                
                break;
                
            case LDPMHallCellTypeMoreProduct:
                cell = self.moreProductCell;
                break;
                
            case LDPMHallCellTypeMarketInfo:
                cell = self.marketInfoCell;
                self.marketInfoCell.delegate = self;
                [self.marketInfoCell updateScrollPageLabel];
                break;
                
            case LDPMHallCellTypeMarketInfoLiveHeader:
                cell = self.marketInfoLiveHeaderCell;
                self.marketInfoLiveHeaderCell.sectionModel = self.marketInfoLiveHeaderModel;
                break;
                
            case LDPMHallCellTypeMarketInfoLive:
                cell = self.marketInfoLiveCell;
                self.marketInfoLiveCell.model = [self.marketInfoLiveModelArray firstObject];
                break;
                
            case LDPMHallCellTypeBottomEmpty:
                cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([LDPMHallEmptyCell class])];
                break;
                
            default:
                cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([LDPMHallEmptyCell class])];
                break;
        }
    } else {
        self.tableView.mj_footer.hidden = (self.segmentedControl.selectedSegmentIndex == 1);
        if (self.segmentedControl.selectedSegmentIndex == 0) {
            if ([self.dataController newsArrayWithDateTag].count) {
                id newsOrDate = [self.dataController newsArrayWithDateTag][row];
                if ([newsOrDate isKindOfClass:[NSDate class]]) {
                    cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([LDPMHallDateCell class])];
                    [(LDPMHallDateCell *)cell setDate:(NSDate *)newsOrDate];
                } else {
                    HomePageNews *news = newsOrDate;
                    if (news.type == LDPMHallTimeLineTypeNews) {
                        cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([LDPMHallNewsCell class])];
                        [(LDPMHallNewsCell *)cell setContentWithNews:news];
                    } else if (news.type == LDPMHallTimeLineTypeStrategy) {
                        cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([LDPMHallStrategyCell class])];
                        [(LDPMHallStrategyCell *)cell setContentWithNews:news];
                    }
                    else if (news.type == LDPMHallTimeLineTypeLivePost) {
                        cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([LDPMHallLivePostCell class])];
                        [(LDPMHallLivePostCell *)cell setContentWithNews:news];
                    } else {
                        cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([LDPMHallPromotionCell class])];
                        [(LDPMHallPromotionCell *)cell setContentWithNews:news];
                    }
                }
                
            } else {
                self.tableView.mj_footer.hidden = YES;
                if (self.shouldShowErrorViewForNews) {
                    LDPMErrorTable *errorTable = [LDPMErrorTable errorTableWithImage:[UIImage imageNamed:@"network_error_icon"]
                                                                                text:@"网络不给力，请检查网络后刷新"
                                                                           retryText:@"刷新"];
                    LDPMErrorCell *errorCell = [[LDPMErrorCell ec_dequeueFromTableView:tableView] ld_configCellWithData:errorTable];
                    @weakify(self);
                    errorCell.retryBlock = ^{
                        @strongify(self);
                        [self fetchLatestNewsWithCompletion:^{
                            [self scrollTableViewToFirstNews];
                        }];
                    };
                    return errorCell;
                } else {
                    return self.noDataCell;
                }
            }
        } else {
            if ([self.dataController financeNewsArrayInDate:self.calendarView.selectedDate].count) {
                HomePageCalendarNews *news = [self.dataController financeNewsArrayInDate:self.calendarView.selectedDate][row];
                cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([LDPMHallFinanceCell class])];
                [(LDPMHallFinanceCell *)cell setContentWithNews:news];
            } else {
                if (self.shouldShowErrorViewForFinanceNews) {
                    LDPMErrorTable *errorTable = [LDPMErrorTable errorTableWithImage:[UIImage imageNamed:@"network_error_icon"]
                                                                                text:@"网络不给力，请检查网络后刷新"
                                                                           retryText:@"刷新"];
                    LDPMErrorCell *errorCell = [[LDPMErrorCell ec_dequeueFromTableView:tableView] ld_configCellWithData:errorTable];
                    @weakify(self);
                    errorCell.retryBlock = ^{
                        @strongify(self);
                        [self fetchLatestFinanceNewsInDate:self.calendarView.selectedDate completion:^{
                            [self scrollTableViewToFirstNews];
                        }];
                    };
                    return errorCell;
                } else {
                    return self.noDataCell;
                }
            }
        }
    }
    
//    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger section = indexPath.section;
    NSInteger row = indexPath.row;
    if (section == 0) {
        enum LDPMHallCellType cellType = [self.dataController.cellTypeArrayInFirstSection[row] integerValue];
        if (cellType == LDPMHallCellTypeNotification && !self.dataController.shouldShowNotificationCell) {
            return 0;
        }
        if (cellType == LDPMHallCellTypeAd && !self.dataController.shouldShowAdView) {
            return 0;
        }
        if (cellType == LDPMHallCellTypeTopProfit && ![self.dataController shouldShowTopProfit]) {
            return 0;
        }
        if (cellType == LDPMHallCellTypeMarketInfoLiveHeader && self.marketInfoLiveModelArray.count < 1) {
            return 0;
        }
        if (cellType == LDPMHallCellTypeMarketInfoLive && self.marketInfoLiveModelArray.count < 1) {
            return 0;
        }
        if (cellType == LDPMHallCellTypeBottomEmpty && self.marketInfoLiveModelArray.count < 1) {
            return 0;
        }
        return [self.dataController heightForCellInFirstSection:cellType];
    } else {
        if (self.segmentedControl.selectedSegmentIndex == 0) {
            if ([self.dataController newsArrayWithDateTag].count) {
                id newsOrDate = [self.dataController newsArrayWithDateTag][row];
                if ([newsOrDate isKindOfClass:[NSDate class]]) {
                    return [tableView fd_heightForCellWithIdentifier:NSStringFromClass([LDPMHallDateCell class]) cacheByIndexPath:indexPath configuration:^(id cell) {
                        [(LDPMHallDateCell *)cell setDate:(NSDate *)newsOrDate];
                    }];
                } else {
                    HomePageNews *news = newsOrDate;
                    if (news.type == LDPMHallTimeLineTypeNews) {
                        return [tableView fd_heightForCellWithIdentifier:NSStringFromClass([LDPMHallNewsCell class]) cacheByIndexPath:indexPath configuration:^(id cell) {
                            [cell setContentWithNews:news];
                        }];
                    } else if (news.type == LDPMHallTimeLineTypeStrategy) {
                        return [tableView fd_heightForCellWithIdentifier:NSStringFromClass([LDPMHallStrategyCell class]) cacheByIndexPath:indexPath configuration:^(id cell) {
                            [cell setContentWithNews:news];
                        }];
                    }
                    else if (news.type == LDPMHallTimeLineTypeLivePost) {
                        return [tableView fd_heightForCellWithIdentifier:NSStringFromClass([LDPMHallLivePostCell class]) cacheByIndexPath:indexPath configuration:^(LDPMHallLivePostCell *cell) {
                                [cell setContentWithNews:news];
                            }];
                    } else {
                        CGFloat height = [tableView fd_heightForCellWithIdentifier:NSStringFromClass([LDPMHallPromotionCell class]) cacheByIndexPath:indexPath configuration:^(LDPMHallPromotionCell *cell) {
                            [cell setContentWithNews:news];
                        }];
                        return height;
                    }
                }
            } else {
                return CGRectGetHeight(tableView.frame)/2.0;
            }
        } else {
            if ([self.dataController financeNewsArrayInDate:self.calendarView.selectedDate].count) {
                HomePageCalendarNews *news = [self.dataController financeNewsArrayInDate:self.calendarView.selectedDate][row];
                
                return [tableView fd_heightForCellWithIdentifier:NSStringFromClass([LDPMHallFinanceCell class]) cacheByIndexPath:indexPath configuration:^(LDPMHallFinanceCell *cell) {
                    [cell setContentWithNews:news];
                }];
            } else {
                return CGRectGetHeight(tableView.frame)/2.0;
            }
        }
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (section == 1) {
        return self.sectionHeaderView;
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section == 1) {
        if (self.segmentedControl.selectedSegmentIndex == 0) {
            if (self.hasNewMessage) {
                return 38. + 32.;
            } else {
                return 38.;
            }
        } else {
            return 38. + 84.;
        }
    }
    return 0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger section = indexPath.section;
    NSInteger row = indexPath.row;
    if (section == 0) {
        NSArray *cellArray = [self.dataController cellTypeArrayInFirstSection];
        if ([[cellArray objectAtIndex:indexPath.row] integerValue] == LDPMHallCellTypeMarketInfoLive) {
            LDPMHallMarketInfoLiveModel *model = [self.marketInfoLiveModelArray firstObject];
            if (model.jumpUrl) {
                [JLRoutes routeURL:[NSURL URLWithString:model.jumpUrl]];
            }
        }
    } else {
        if (self.segmentedControl.selectedSegmentIndex == 0) {
            if ([self.dataController newsArrayWithDateTag].count > 0) {
                id newsOrDate = [self.dataController newsArrayWithDateTag][row];
                if ([newsOrDate isKindOfClass:[HomePageNews class]]) {
                    HomePageNews *news = newsOrDate;
                    switch (news.type) {
                        case LDPMHallTimeLineTypeNews:
                            [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:@"资讯"];
                            break;
                            
                        case LDPMHallTimeLineTypeStrategy:
                            [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:@"分析"];
                            break;
                        case LDPMHallTimeLineTypeLivePost:
                            [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:@"直播"];
                            break;
                            
                        case LDPMHallTimeLineTypePromotion:
                            [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:@"活动"];
                            break;
                            
                        case LDPMHallTimeLineTypeReport:
                            [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:@"实时"];
                            break;
                            
                        case LDPMHallTimeLineTypeNotice:
                            [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:@"公告"];
                            
                        default:
                            break;
                    }
                    if (news.url) {
                        if (news.type == LDPMHallTimeLineTypeLivePost) {
                            [self goToLiveRoomFromNews:news];
                        } else {
                            [JLRoutes routeURL:[NSURL URLWithString:news.url]];
                        }
                    }
                }
            }
        }
    }
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset
{
    if (scrollView == self.tableView) {
        if (velocity.y < 0) {
            [self.navigationController setNavigationBarHidden:NO animated:YES];
        }
        if (velocity.y > 0) {
            [self.navigationController setNavigationBarHidden:YES animated:YES];
        }
    }
}

- (void)scrollTableViewToFirstNews
{
    CGRect listTopRect = [self.tableView rectForSection:1];
    listTopRect.size.height = 10.;
    [self.tableView scrollRectToVisible:listTopRect animated:YES];
}

#pragma mark - LDPMNewUserActivityViewDelegate

- (void)closeActivityView:(LDPMNewUserActivityView *)activityView
{
    if ([activityView.activity.activityEnName isEqualToString:[self.dataController userActivity].activityEnName]) {//新手活动缩小到右上角“礼包”
        [LDPMUserEvent addEvent:EVENT_NEWBIE tag:@"关闭"];
        [activityView dismissAnimated:YES];
    } else {//通用活动直接关闭
        [LDPMUserEvent addEvent:EVENT_ACTIVITY tag:@"关闭"];
        [activityView dismiss];
    }
}

- (void)newUserActivityViewDidSelectConfirmButton:(LDPMNewUserActivityView *)activityView
{
    if ([activityView.activity.activityEnName isEqualToString:[self.dataController userActivity].activityEnName]) {//新手活动先登录再跳转
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

#pragma mark - LDPMNotificationCellDelegate

- (void)hallNotificationCellDidSelectButton:(LDPMHallNotificationCell *)cell
{
    if (![self.dataController activity_hasLogin]) {
        [LDPMUserEvent addEvent:EVENT_YELLOW_BAR tag:@"登录"];
        [NPMLoginAction loginWithSuccessBlock:nil andFailureBlock:nil];
        return;
    }
    [self hideNotificationCell];
    if (![self.dataController activity_hasParticipated]) {
        [LDPMUserEvent addEvent:EVENT_YELLOW_BAR tag:@"领取"];
        [self newUserAcvitityIconAction:nil];
    } else {
        [LDPMUserEvent addEvent:EVENT_YELLOW_BAR tag:@"开户"];
        
        [FAOpenAccountStatusRoutes routesWithPartnerId:NPMPartnerIDNanJiaoSuo fromViewController:self];
    }
}

#pragma mark - LDAutoScrollAdViewDataSource & Delegate

- (NSInteger)numberOfImageInAutoScrollAdView:(LDAutoScrollAdView *)adView
{
    return self.dataController.adArray.count;
}

- (NSURL *)autoScrollAdView:(LDAutoScrollAdView *)adView imageURLForImageAtIndex:(NSInteger)index
{
    AdBanner *ad = self.dataController.adArray[index];
    return [NSURL URLWithString:ad.imageURI];
}

- (UIImage *)placeHolderImageForAutoScrollAdView:(LDAutoScrollAdView *)adView
{
    return [UIImage imageNamed:@"news_default"];
}

- (void)autoScrollAdView:(LDAutoScrollAdView *)adView didSelectImageAtIndex:(NSInteger)index
{
    [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:[NSString stringWithFormat:@"轮播图%@", @(index + 1)]];
    AdBanner *ad = self.dataController.adArray[index];
    if (ad.uri) {
        [JLRoutes routeURL:[NSURL URLWithString:ad.uri]];
    }
}

#pragma mark - LDPMHallMarketInfoCellDelegate

- (void)updateScrollPageLabel:(NSString *)string
{
    self.scrollPageLabel.text = string;
}

- (void)marketInfoCell:(LDPMHallMarketInfoCell *)cell didSelectMarketInfo:(NPMRealTimeMarketInfo *)marketInfo
{
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

- (void)gotoLDPMHallHotGoodsListViewController
{
    LDPMHallHotGoodsListViewController *vc = [[UIStoryboard storyboardWithName:@"LDPMHall" bundle:nil] instantiateViewControllerWithIdentifier:@"LDPMHallHotGoodsListViewController"];
    vc.hotGoodsListDelegate = self;
    vc.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - LDPMHallCalendarCellDelegate

- (void)calendarView:(LDPMHallCalendarView *)calendarView didSelectDate:(NSDate *)date
{
    @weakify(self)
    [LDPMUserEvent addEvent:EVENT_CALENDAR tag:@"切换日期"];
    [self fetchLatestFinanceNewsInDate:date completion:^{
        @strongify(self);
        [self scrollTableViewToFirstNews];
        [self.calendarView updateIndicatorPosition];
    }];
}

#pragma mark - LDPMHallHotGoodsListDelegate

- (void)updateHallHotGoods:(NSMutableArray *)goodsList
{
    [self unsubscribeMessageForGoodsList:self.hotGoodsList];
    [self subscribeMessageForGoodsList:goodsList];
    
    self.hotGoodsList = [NSMutableArray arrayWithArray:goodsList];
    [self.marketInfoCell updateCellScrollViewWithGoodsList:goodsList];
    [self refreshMarketInfo];
}

#pragma mark - LDPMHallNewMessageViewDelegate

- (void)messageViewDidSelected:(LDPMHallNewMessageView *)messageView
{
    [LDPMUserEvent addEvent:EVENT_HOME_PAGE tag:@"消息提示点击"];
    if (self.segmentedControl.selectedSegmentIndex == 0) {
        @weakify(self)
        [self fetchLatestNewsWithCompletion:^{
            @strongify(self)
            [self scrollTableViewToFirstNews];
        }];
    }
}

#pragma mark - 常驻页面统计

- (NSString *)pageEventParam
{
    return @"@1";
}

@end
