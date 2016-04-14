//
//  NPMWatchListViewController.m
//  PreciousMetals
//
//  Created by ypchen on 10/15/14.
//  Copyright (c) 2014 NetEase. All rights reserved.
//

#import "NPMWatchListViewController.h"
#import "NPMWatchListCell.h"
#import "NPMMarketSearchViewController.h"
#import "NPMMarketInfoService.h"
#import "NPMWatchItem.h"
#import "NPMProduct.h"
#import "NPMProductViewController.h"
#import "Reachability.h"
#import "NPMDateFormatter.h"
#import "ReactiveCocoa.h"
#import "MJRefresh.h"
#import "NPMPartnerService.h"
#import "LDSocketPushClient.h"
#import "LDPMSocketMessageTopicUtil.h"
#import "LDSPMessage.h"
#import "NPMRealTimeMarketInfo.h"
#import "LDPMTableViewHeader.h"

extern NSString *const NPMUserSessionLoginStatusChangedNotification;
static NSString *const CellIdentify = @"NPMWatchListCell";
static CGFloat addWatchListViewHeightOriginalConstant = 50.0f;

#define TableHeaderViewEdtingYES     @"TableHeaderViewEdtingYES"
#define TableHeaderViewEdtingNO      @"TableHeaderViewEdtingNO"

@interface NPMWatchListViewController ()<NPMMarketSearchViewControllerDelegate, UITableViewDataSource, UITableViewDelegate,NPMWatchListCellDelegate>

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *addWatchListViewHeight;

@property (weak, nonatomic) IBOutlet UIView *addWatchListView;

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *goodsNameLeadingLayoutConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *latestPriceTrailingLayoutConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *InDecreaseTrailingLayoutConstraint;

@property (strong, nonatomic) NSDictionary *tableHeaderViewLayout;

@property (weak, nonatomic) IBOutlet UILabel *latestPriceLabel;
@property (weak, nonatomic) IBOutlet UILabel *amountOfInDecreaseLabel;
@property (strong, nonatomic) NSDictionary *tableHeaderViewTitles;

@property (nonatomic, strong) UIButton *editButton;
@property (nonatomic, strong) UIButton *refreshBtn;
@property (nonatomic, strong) UIBarButtonItem *refreshBtnItem;
@property (nonatomic, strong) UIBarButtonItem *negativeSpacer;
@property (nonatomic, strong) NPMMarketInfoService *marketInfoService;
@property (nonatomic, strong) NSMutableDictionary *marketInfoDic;

@property (nonatomic, assign) LDTaskID taskId;

@property (nonatomic, strong) RACSubject *timerSubject;
@property (nonatomic, strong) RACSignal *timerSignal;
@property (nonatomic, assign) BOOL startTimer;

@property (nonatomic, assign) BOOL timerAvailable;

@property (nonatomic, strong) NSArray *availableExchangeIds;

@property (nonatomic,assign) BOOL socketAlive;

@end

@implementation NPMWatchListViewController

+ (instancetype)createViewController
{
    UIStoryboard *mystoryboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];

    return [mystoryboard instantiateViewControllerWithIdentifier:NSStringFromClass(self)];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.taskId = 0;
    self.availableExchangeIds = @[NPMPartnerIDShangJiaoSuo, NPMPartnerIDNanJiaoSuo, NPMPartnerIDGuangGuiZhongXin, NPMPartnerIDShanghaiStockExchange, NPMPartnerIDShenzhenStockExchange, NPMPartnerIDOuterDisc];
    
    [self setupNavigationBarView];
    [self setAddWatchListViewForEditing];
    [self setEditButtonRACCommad];
    [self initializeTableView];

    self.watchListService = [NPMWatchListService new];
    self.marketInfoService = [NPMMarketInfoService new];

    [self setupPullDownwardsRefresh];
    [self setupFiveSecondsRefreshAfterNetworkComplete];
    
    @weakify(self)
    [[LDSocketPushClient defaultClient] addErrorObserver:self usingBlock:^(NSError *error) {
        @strongify(self)
        if (error.code == LDSocketPushClientErrorTypeDisconnected) {
            self.socketAlive = NO;
        }
    }];
    
    if (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable) {
        // 注册预览视图的代理和来源视图
        [self registerForPreviewingWithDelegate:(id)self sourceView:self.view];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loginStatusChanged:) name:NPMUserSessionLoginStatusChangedNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    
    //先停止之前可能存在的计时器再发送计时开始的信号
    self.timerAvailable = YES;
    [self sendTimerSignal:NO];
    [self sendTimerSignal:YES];
    //马上刷新数据
    [self refreshDataWithNotify:NO];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    NSArray *visibleCells = [self.tableView visibleCells];
    
    for (NPMWatchListCell *cell in visibleCells) {
        [self subscribeMessageForCell:cell];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    self.timerAvailable = NO;
    [self sendTimerSignal:NO];
    
    for (NPMWatchItem *item in self.dataSource) {
        NSString *topic = [LDPMSocketMessageTopicUtil simplePriceTopicWithPartnerId:item.partnerId goodsId:item.goodsId];
        [[LDSocketPushClient defaultClient] removeObserver:self topic:topic];
    }
}
// If you return nil, a preview presentation will not be performed
- (nullable UIViewController *)previewingContext:(id <UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location NS_AVAILABLE_IOS(9_0)
{
    if(CGRectContainsPoint(self.tableView.frame, location)) {
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
        NPMWatchItem *item = [_dataSource objectAtIndex:indexPath.row];
        NPMRealTimeMarketInfo *marketInfo = self.marketInfoDic[EMPTY_STRING_IF_NIL(item.productCode)];
        NPMProductViewController *productViewController = [[NPMProductViewController alloc] initWithNibName:NSStringFromClass([NPMProductViewController class]) bundle:nil];
        productViewController.product = [NPMProduct productWithWatchItem:item];
        productViewController.marketInfo = marketInfo;
        
        previewingContext.sourceRect = [self.tableView cellForRowAtIndexPath:indexPath].frame;
        return productViewController;
    } else {
        return nil;
    }
}

- (void)previewingContext:(id <UIViewControllerPreviewing>)previewingContext commitViewController:(UIViewController *)viewControllerToCommit NS_AVAILABLE_IOS(9_0)
{
    [LDPMUserEvent addEvent:EVENT_PRODUCT_CHART_ENTRANCE tag:@"自选列表"];
    [self.navigationController pushViewController:viewControllerToCommit animated:YES];
}


//- (void)viewDidDisappear:(BOOL)animated
//{
//    [super viewDidDisappear:animated];
//}

/**
 *  创建导航栏界面和按钮
 */
- (void)setupNavigationBarView
{
    self.title = @"自选";
    self.editButton = [NPMUIFactory naviButtonWithTitle:@"编辑" target:self selector:nil];
    [self.editButton setTitleColor:[NPMColor whiteTextColor] forState:UIControlStateNormal];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.editButton];
    
    UIButton *refreshBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    refreshBtn.size = CGSizeMake(44, 44);
    [refreshBtn setImage:[UIImage imageNamed:@"refresh"] forState:UIControlStateNormal];
    [refreshBtn setImage:[UIImage imageNamed:@"refresh_h"] forState:UIControlStateHighlighted];
    self.refreshBtn = refreshBtn;
    @weakify(self);
    self.refreshBtn.rac_command = [[RACCommand alloc] initWithSignalBlock:^RACSignal *(id input) {
        @strongify(self);
        [self.tableView.mj_header beginRefreshing];
        [self refreshDataWithNotify:YES];
        
        return [RACSignal empty];
    }];
    self.refreshBtnItem = [[UIBarButtonItem alloc] initWithCustomView:self.refreshBtn];
    self.negativeSpacer = [[UIBarButtonItem alloc]
                           initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                           target:nil action:nil];
    self.negativeSpacer.width = -12;
    self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:self.negativeSpacer, self.refreshBtnItem, nil];
}

/**
 *  初始化tableView的headerView和footView
 */
- (void)initializeTableView
{
    self.tableView.backgroundColor = [UIColor whiteColor];
    self.tableView.tableHeaderView.backgroundColor = [NPMColor mainBackgroundColor];
    UIView *footView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 46)];
    UILabel *hintLabel = [NPMUIFactory labelWithFontsize:15 textColor:[UIColor colorWithRGB:0xafafaf]];
    hintLabel.size = footView.size;
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.text = @"以上信息1秒钟刷新一次，下拉可手动刷新";
    [footView addSubview:hintLabel];
    self.tableView.tableFooterView = footView;
    //tableHeaderViewLayout元素分别对应交易品名称的leading，最新价的trailing，涨跌幅的trailing
    if ([UIDevice screenWidth] > 375) {
        self.tableHeaderViewLayout = @{TableHeaderViewEdtingNO:@[@(13), @(15), @(22)], TableHeaderViewEdtingYES:@[@(50), @(14), @(18)]};
        self.goodsNameLeadingLayoutConstraint.constant = [[self.tableHeaderViewLayout[TableHeaderViewEdtingNO] objectAtIndex:0] floatValue];
        self.latestPriceTrailingLayoutConstraint.constant = [[self.tableHeaderViewLayout[TableHeaderViewEdtingNO] objectAtIndex:1] floatValue];
        self.InDecreaseTrailingLayoutConstraint.constant = [[self.tableHeaderViewLayout[TableHeaderViewEdtingNO] objectAtIndex:2] floatValue];
    } else if ([UIDevice screenWidth] > 320) {
        self.tableHeaderViewLayout = @{TableHeaderViewEdtingNO:@[@(13), @(18), @(16)], TableHeaderViewEdtingYES:@[@(50), @(13), @(16)]};
    } else {
        self.tableHeaderViewLayout = @{TableHeaderViewEdtingNO:@[@(13), @(15), @(11)], TableHeaderViewEdtingYES:@[@(50), @(13), @(9)]};
        self.goodsNameLeadingLayoutConstraint.constant = [[self.tableHeaderViewLayout[TableHeaderViewEdtingNO] objectAtIndex:0] floatValue];
        self.latestPriceTrailingLayoutConstraint.constant = [[self.tableHeaderViewLayout[TableHeaderViewEdtingNO] objectAtIndex:1] floatValue];
        self.InDecreaseTrailingLayoutConstraint.constant = [[self.tableHeaderViewLayout[TableHeaderViewEdtingNO] objectAtIndex:2] floatValue];
    }
    
    self.tableHeaderViewTitles = @{TableHeaderViewEdtingNO:@[@"最新价", @"涨跌幅"], TableHeaderViewEdtingYES:@[@"", @"置顶"]};
}

/**
 *  在编辑状态显示添加自选按钮，在正常状态不显示
 */
- (void)setAddWatchListViewForEditing
{
    @weakify(self);
    [RACObserve(self.tableView, editing) subscribeNext:^(NSNumber *editing) {
        @strongify(self);
        self.addWatchListViewHeight.constant = [editing boolValue] ? addWatchListViewHeightOriginalConstant : 0.0f;
        self.addWatchListView.hidden = [editing boolValue] ? NO : YES;
    }];
    UITapGestureRecognizer *tapAddWatchListGR = [UITapGestureRecognizer new];
    [self.addWatchListView addGestureRecognizer:tapAddWatchListGR];
    [[tapAddWatchListGR rac_gestureSignal] subscribeNext:^(id x) {
        @strongify(self);
        UIStoryboard *mystoryboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
        NPMMarketSearchViewController *searchVc = [mystoryboard instantiateViewControllerWithIdentifier:@"SearchViewController"];
        searchVc.watchListService = self.watchListService;
        searchVc.delegate = self;
        [self.navigationController pushViewController:searchVc animated:YES];
    }];
}

/**
 *  创建下拉刷新
 */
- (void)setupPullDownwardsRefresh
{
    @weakify(self);
    self.tableView.mj_header = [LDPMTableViewHeader headerWithRefreshingBlock:^{
        @strongify(self);
        [self refreshDataWithNotify:YES];
    }];

    [self.tableView.mj_header beginRefreshing];
   }

#pragma mark Auto Refresh In 5s

/**
 *  设置编辑按钮的点击事件响应
 */
- (void)setEditButtonRACCommad
{
    @weakify(self);
    self.editButton.rac_command = [[RACCommand alloc] initWithSignalBlock:^RACSignal *(id input) {
        @strongify(self);
        if (self.tableView.editing) {
            [self.tableView setEditing:NO];
            [self.editButton setTitle:@"编辑" forState:UIControlStateNormal];
            [self.editButton setTitleColor:[NPMColor whiteTextColor] forState:UIControlStateNormal];
            //先停止之前可能存在的计时器再发送计时开始的信号
            self.timerAvailable = YES;
            [self sendTimerSignal:NO];
            [self sendTimerSignal:YES];
            self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:self.negativeSpacer, self.refreshBtnItem, nil];
            self.goodsNameLeadingLayoutConstraint.constant = [[self.tableHeaderViewLayout[TableHeaderViewEdtingNO] objectAtIndex:0] floatValue];
            self.latestPriceTrailingLayoutConstraint.constant = [[self.tableHeaderViewLayout[TableHeaderViewEdtingNO] objectAtIndex:1] floatValue];
            self.InDecreaseTrailingLayoutConstraint.constant = [[self.tableHeaderViewLayout[TableHeaderViewEdtingNO] objectAtIndex:2] floatValue];
            self.latestPriceLabel.text = [self.tableHeaderViewTitles[TableHeaderViewEdtingNO] firstObject];
            self.amountOfInDecreaseLabel.text = [self.tableHeaderViewTitles[TableHeaderViewEdtingNO] lastObject];
        } else {
            [LDPMUserEvent addEvent:EVENT_WATCHLIST_EDIT];
            [self.tableView setEditing:YES];
            [self.editButton setTitle:@"完成" forState:UIControlStateNormal];
            [self.editButton setTitleColor:[NPMColor whiteTextColor] forState:UIControlStateNormal];
            //停止可能存在的计时器
            self.timerAvailable = NO;
            [self sendTimerSignal:NO];
            self.navigationItem.rightBarButtonItems = nil;
            self.goodsNameLeadingLayoutConstraint.constant = [[self.tableHeaderViewLayout[TableHeaderViewEdtingYES] objectAtIndex:0] floatValue];
            self.latestPriceTrailingLayoutConstraint.constant = [[self.tableHeaderViewLayout[TableHeaderViewEdtingYES] objectAtIndex:1] floatValue];
            self.InDecreaseTrailingLayoutConstraint.constant = [[self.tableHeaderViewLayout[TableHeaderViewEdtingYES] objectAtIndex:2] floatValue];
            self.latestPriceLabel.text = [self.tableHeaderViewTitles[TableHeaderViewEdtingYES] firstObject];
            self.amountOfInDecreaseLabel.text = [self.tableHeaderViewTitles[TableHeaderViewEdtingYES] lastObject];
        }
        [self.tableView reloadData];
        return [RACSignal empty];
    }];
}

/**
 *  在网络获取数据后开始5秒计时并重新访问数据
 */
- (void)setupFiveSecondsRefreshAfterNetworkComplete
{
    @weakify(self);
    self.timerSubject = [RACSubject subject];
    [self.timerSubject subscribeNext:^(NSNumber *start) {
        @strongify(self);
        if (self.startTimer == YES && self.timerAvailable) {
            self.timerSignal = [[[RACSignal interval:5.0f onScheduler:[RACScheduler mainThreadScheduler]] take:1] takeUntil:[RACObserve(self, startTimer) ignore:@(YES)]];
            [self.timerSignal subscribeNext:^(NSDate *date) {
                @strongify(self)
                [self autoRefreshData];
            }];
        }
    }];
}

/**
 *  向5秒刷新计时器发送开始和停止的信号
 *
 *  @param start 如果start为YES，开始5秒计时，如果为NO，停止5秒计时
 */
- (void)sendTimerSignal:(BOOL)start
{
    self.startTimer = start;
    [self.timerSubject sendNext:[NSNumber numberWithBool:start]];
}

- (void)setWatchListOutletsDisplay:(BOOL)type
{
    [self.tableView.tableFooterView setHidden:!type];
    [self.tableView setHidden:!type];

    if (!type && ![self errorPage]) {//不要重复添加errorPage
        @weakify(self);
        [self showNetErrorHint:@"网络不给力，请检查网络后刷新" retryBlock:^() {
            @strongify(self);
            [self refreshDataWithNotify:YES];
        }];
    } else if ([self errorPage] && type) {
        [self clearNetErrorHint];
    }
}

#pragma mark - Http request

- (void)autoRefreshData
{
    if (self.socketAlive) {
        return;
    }
    
    [self requestMarketInfoWithNotify:NO];
}

- (void)refreshDataWithNotify:(BOOL)notify
{
    if (self.taskId > 0) {
        return;
    }
    
    @weakify(self);
    //[self startActivity:NSLocalizedString(@"Wait For Loading", @"努力加载中，请稍候...")];
    self.taskId = [self.watchListService fetchWatchListWithCompletion:^(NPMRetCode responseCode, NSError *error, NSArray *watchList) {
        @strongify(self);
        
        if (error) {
        } else {
            self.dataSource = [self filterProductList:watchList];
            self.tableView.tableFooterView.hidden = ([self.dataSource count] == 0);
            [self.tableView reloadData];
            [self requestMarketInfoWithNotify:notify];
            [self.tableView.mj_header endRefreshing];
        }
        
        //[weakSelf stopActivity];
        self.taskId = 0;
    }];
}

- (NSMutableArray *)filterProductList:(NSArray *)productList
{
    NSMutableArray *products = [NSMutableArray new];
    for (NPMProduct *product in productList) {
        if (product.partnerId == nil) {
            continue;
        }
        if ([self.availableExchangeIds containsObject:product.partnerId]) {
            [products addObjectNoNil:product];
        }
    }
    return [NSMutableArray arrayWithArray:products];
}

- (void)startRefreshAnimation
{
    if ([self.refreshBtn.layer animationForKey:@"rotate"]) {
    } else {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        animation.toValue = [NSNumber numberWithFloat:M_PI * 2.0];
        animation.duration = 1.0;
        animation.cumulative = YES;
        animation.repeatCount = NSIntegerMax;
        [self.refreshBtn.layer addAnimation:animation forKey:@"rotate"];
    }
}

- (void)stopRefreshAnimation
{
    @weakify(self);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        @strongify(self);
        
        self.refreshBtn.userInteractionEnabled = YES;
        [self.refreshBtn.layer removeAnimationForKey:@"rotate"];
        [self.tableView.mj_header endRefreshing];
    });
}

- (void)requestMarketInfoWithNotify:(BOOL)notify
{
    
    Reachability *r = [Reachability reachabilityForInternetConnection];
    switch ([r currentReachabilityStatus]) {
        case NotReachable:// 没有网络连接
            [self setWatchListOutletsDisplay:NO];
            [self.tableView.mj_header endRefreshing];
            return;
        case ReachableViaWWAN:// 使用3G网络
        case ReachableViaWiFi:// 使用WiFi网络
            [self setWatchListOutletsDisplay:YES];
            break;
        default:
            break;
    }
    
    if (self.tableView.editing == NO) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        spinner.frame = self.refreshBtn.frame;
        [spinner startAnimating];
        self.refreshBtnItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
        self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:self.negativeSpacer, self.refreshBtnItem, nil];
    }
    
    @weakify(self);
    [self.marketInfoService fetchRealTimeMarketInfoForProductList:self.dataSource completion:^(NPMRetCode responseCode, NSError *error, NSDictionary *marketInfoDic) {
        @strongify(self);
        
        //先停止之前可能存在的计时器再发送计时开始的信号
        if (self.tableView.editing == NO) {
            dispatch_time_t delayInNanoSeconds = dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC);
            dispatch_after(delayInNanoSeconds, dispatch_get_main_queue(), ^{
                [self sendTimerSignal:NO];
                [self sendTimerSignal:YES];
                self.refreshBtnItem = [[UIBarButtonItem alloc] initWithCustomView:self.refreshBtn];
                self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:self.negativeSpacer, self.refreshBtnItem, nil];
            });
        }
        self.marketInfoDic = [NSMutableDictionary dictionaryWithDictionary:marketInfoDic];
        [self.tableView reloadData];

        if (notify) {
            if (responseCode == NPMRetCodeSuccess) {
                static NSDateFormatter *formatter = nil;

                if (formatter == nil) {
                    formatter = [NSDateFormatter new];
                    formatter.dateFormat = @"HH:mm:ss";
                }

                CGFloat offset = 0;
                [self showToast:[NSString stringWithFormat:@"更新成功 %@", [formatter stringFromDate:[NSDate date]]] offset:offset];
            } else {
                NSString *errorDesc = error.localizedDescription.length > 0 ? error.localizedDescription : NSLocalizedString(@"Refresh Failed", @"刷新失败");
                [self showToast:errorDesc];
            }
        }
    }];
}

- (void)requestUnWatch:(NPMWatchItem *)item
{
    [self.watchListService unWatchItem:item completion:^(NPMRetCode responseCode, NSError *error) {
    }];
}

- (void)loginStatusChanged:(NSNotification *)notification
{
    [self refreshDataWithNotify:NO];
}

- (void)productListViewControllerDone:(NPMMarketSearchViewController *)viewController
{
    [self refreshDataWithNotify:NO];
}

- (void)unsubscribeMessageForCell:(NPMWatchListCell *)cell
{
     [[LDSocketPushClient defaultClient] removeObserver:self topic:[LDPMSocketMessageTopicUtil simplePriceTopicWithPartnerId:cell.watchItem.partnerId goodsId:cell.watchItem.goodsId]];
}

- (void)subscribeMessageForCell:(NPMWatchListCell *)cell
{
    @weakify(self)
    [[LDSocketPushClient defaultClient] addObserver:self topic:[LDPMSocketMessageTopicUtil simplePriceTopicWithPartnerId:cell.watchItem.partnerId goodsId:cell.watchItem.goodsId] pushType:LDSocketPushTypeGroup usingBlock:^(LDSPMessage *message) {
        @strongify(self)
        id object = [NSJSONSerialization JSONObjectWithData:message.body
                                                    options:NSJSONReadingMutableContainers
                                                      error:NULL];
        NPMRealTimeMarketInfo *marketInfo = [[NPMRealTimeMarketInfo alloc] initWithArray:object];
        if (marketInfo) {
            self.marketInfoDic[EMPTY_STRING_IF_NIL(marketInfo.productCode)] = marketInfo;
            cell.marketInfo = marketInfo;
            self.socketAlive = YES;
        }
    }];
}

- (void)requestMoveTop:(NSIndexPath *)indexPath cellItem:(NPMWatchItem*)watchItem
{
    @weakify(self);
    [self.watchListService topWatchItem:watchItem completion:^(NPMRetCode responseCode, NSError *error) {
        @strongify(self);
        [self refreshDataWithNotify:NO];
    }];
}


#pragma mark - UITableViewDataSource && UITableViewDelegate

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _dataSource.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [NPMWatchListCell cellHeight];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NPMWatchListCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentify forIndexPath:indexPath];

    [self unsubscribeMessageForCell:cell];
    
    cell.watchItem = self.dataSource[indexPath.row];
    cell.refreshDelegate = self;
    NPMRealTimeMarketInfo *marketInfo = self.marketInfoDic[EMPTY_STRING_IF_NIL(cell.watchItem.productCode)];
    cell.marketInfo = marketInfo;
    cell.parentVC = self;
    cell.firstCell = (indexPath.row == 0);
    cell.lastCell = (indexPath.row == ([self.dataSource count] - 1));
    
    [self subscribeMessageForCell:cell];
    
    return cell;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NPMWatchItem *item = self.dataSource[indexPath.row];
        [self requestUnWatch:item];
        [self.dataSource removeObjectAtIndex:indexPath.row];
        [[LDSocketPushClient defaultClient] removeObserver:self topic:[LDPMSocketMessageTopicUtil simplePriceTopicWithPartnerId:item.partnerId goodsId:item.goodsId]];

        // fix: IOS7删除最后一个cell动画不同步bug（删除前先隐藏cell）
        double iosVersion = [[[UIDevice currentDevice] systemVersion] floatValue];

        if (iosVersion >= 7.0 && iosVersion <= 8.0) {
            [tableView cellForRowAtIndexPath:indexPath].alpha = 0.0;
        }

        [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObjects:indexPath, nil] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [LDPMUserEvent addEvent:EVENT_PRODUCT_CHART_ENTRANCE tag:@"自选列表"];
    
    NPMWatchItem *item = [_dataSource objectAtIndex:indexPath.row];
    NPMRealTimeMarketInfo *marketInfo = self.marketInfoDic[EMPTY_STRING_IF_NIL(item.productCode)];
    NPMProductViewController *productViewController = [[NPMProductViewController alloc] initWithNibName:NSStringFromClass([NPMProductViewController class]) bundle:nil];

    productViewController.product = [NPMProduct productWithWatchItem:item];
    productViewController.marketInfo = marketInfo;
    productViewController.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:productViewController animated:YES];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return self.tableView.editing;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return @"删除";
}

#pragma mark - NPMWatchListCellDelegate
- (void)watchCell:(NPMWatchListCell*)cell moveTopPressed:(id)sender
{
    NSIndexPath *originPath = [self.tableView indexPathForCell:cell];
    NPMWatchItem *originItem = [cell.watchItem copy];
    NSIndexPath *destinationPath = [NSIndexPath indexPathForRow:0 inSection:0];
    NSObject *cellToMove = [self.dataSource objectAtIndex:originPath.row];
    [self.tableView beginUpdates];
    [self.dataSource removeObjectAtIndex:originPath.row];
    [self.dataSource insertObject:cellToMove atIndex:destinationPath.row];
    [self requestMoveTop:originPath cellItem:originItem];
    
    [self.tableView moveRowAtIndexPath:originPath toIndexPath:destinationPath];
    [self.tableView endUpdates];
}

#pragma mark - 常驻页面统计

- (NSString *)pageEventParam
{
    return @"@1";
}


@end
