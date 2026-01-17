#import "LaunchMonitorDataViewController.h"
#import "Theme.h"
#import "ScreenDataProcessor.h"
#import "DataModel.h"
#import "MiniGameEndViewController.h"

NSString *formattedStringFromInteger(NSInteger value) {
    if (value == 0) return @"E";
    else if (value > 0) return [NSString stringWithFormat:@"+%ld", (long)value];
    else return [NSString stringWithFormat:@"%ld", (long)value];
}

@interface LaunchMonitorDataViewController ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, UILabel *> *valueLabels;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UILabel *> *titleLabels;
@property (nonatomic, strong) UIStackView *mainGrid;
@property (nonatomic, strong) UIView *gameContainer;
@property (nonatomic, strong) UIView *separatorLine;
@property (nonatomic, strong) UILabel *miniGameHeaderLabel;
@property (nonatomic, strong) UIStackView *miniGameRow;
@property (nonatomic, strong) UIButton *endGameButton;
@property (nonatomic, strong) NSLayoutConstraint *mainGridBottomConstraint;

@end

@implementation LaunchMonitorDataViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = APP_COLOR_BG;
    self.valueLabels = [NSMutableDictionary dictionary];
    self.titleLabels = [NSMutableDictionary dictionary];

    self.mainGrid = [[UIStackView alloc] init];
    self.mainGrid.axis = UILayoutConstraintAxisVertical;
    self.mainGrid.distribution = UIStackViewDistributionFillEqually;
    self.mainGrid.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.mainGrid];
    
    [self.mainGrid addArrangedSubview:[self createRowWithKeys:@[@"Launch Angle (VLA)", @"Apex", @"Carry", @"Total"]]];
    [self.mainGrid addArrangedSubview:[self createRowWithKeys:@[@"Offline (HLA)", @"Offline (Total)", @"Spin", @"Spin Axis"]]];
    [self.mainGrid addArrangedSubview:[self createRowWithKeys:@[@"Path", @"AOA", @"Club Speed", @"Ball Speed"]]];
    
    [self setupMiniGameUI];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.mainGrid.topAnchor constraintEqualToAnchor:safe.topAnchor constant:20],
        [self.mainGrid.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [self.mainGrid.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20]
    ]];
    
    self.mainGridBottomConstraint = [self.mainGrid.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-20];
    self.mainGridBottomConstraint.active = YES;

    [self setupObservers];
}

- (void)setupMiniGameUI {
    self.gameContainer = [[UIView alloc] init];
    self.gameContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.gameContainer.hidden = YES;
    [self.view addSubview:self.gameContainer];
    
    self.separatorLine = [[UIView alloc] init];
    self.separatorLine.backgroundColor = [UIColor grayColor];
    self.separatorLine.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gameContainer addSubview:self.separatorLine];
    
    self.miniGameHeaderLabel = [[UILabel alloc] init];
    self.miniGameHeaderLabel.text = @"MINI GAME";
    self.miniGameHeaderLabel.font = [UIFont boldSystemFontOfSize:12];
    self.miniGameHeaderLabel.textColor = APP_COLOR_ACCENT;
    self.miniGameHeaderLabel.backgroundColor = APP_COLOR_BG;
    self.miniGameHeaderLabel.textAlignment = NSTextAlignmentCenter;
    self.miniGameHeaderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gameContainer addSubview:self.miniGameHeaderLabel];
    
    self.miniGameRow = [[UIStackView alloc] init];
    self.miniGameRow.axis = UILayoutConstraintAxisHorizontal;
    self.miniGameRow.distribution = UIStackViewDistributionFillEqually;
    self.miniGameRow.alignment = UIStackViewAlignmentCenter;
    self.miniGameRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.miniGameRow.spacing = 10;
    [self.gameContainer addSubview:self.miniGameRow];
    
    [self.miniGameRow addArrangedSubview:[self createMiniGameCell:@"Target"]];
    [self.miniGameRow addArrangedSubview:[self createMiniGameCell:@"Last Score"]];
    [self.miniGameRow addArrangedSubview:[self createMiniGameCell:@"Shots Left"]];
    [self.miniGameRow addArrangedSubview:[self createMiniGameCell:@"Total Score"]];
    
    self.endGameButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.endGameButton setTitle:@"End" forState:UIControlStateNormal];
    [self.endGameButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    self.endGameButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.endGameButton.layer.cornerRadius = 8.0;
    self.endGameButton.layer.borderWidth = 1.0;
    self.endGameButton.layer.borderColor = [UIColor redColor].CGColor;
    self.endGameButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.endGameButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.endGameButton.heightAnchor constraintEqualToConstant:36].active = YES;
    [self.endGameButton addTarget:self action:@selector(endMiniGameTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.miniGameRow addArrangedSubview:self.endGameButton];
    
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.gameContainer.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [self.gameContainer.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [self.gameContainer.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-5],
        [self.gameContainer.heightAnchor constraintEqualToConstant:100],
        [self.separatorLine.topAnchor constraintEqualToAnchor:self.gameContainer.topAnchor constant:5],
        [self.separatorLine.leadingAnchor constraintEqualToAnchor:self.gameContainer.leadingAnchor],
        [self.separatorLine.trailingAnchor constraintEqualToAnchor:self.gameContainer.trailingAnchor],
        [self.separatorLine.heightAnchor constraintEqualToConstant:1],
        [self.miniGameHeaderLabel.centerYAnchor constraintEqualToAnchor:self.separatorLine.centerYAnchor],
        [self.miniGameHeaderLabel.centerXAnchor constraintEqualToAnchor:self.gameContainer.centerXAnchor],
        [self.miniGameHeaderLabel.widthAnchor constraintEqualToConstant:90],
        [self.miniGameRow.topAnchor constraintEqualToAnchor:self.separatorLine.bottomAnchor constant:5],
        [self.miniGameRow.leadingAnchor constraintEqualToAnchor:self.gameContainer.leadingAnchor],
        [self.miniGameRow.trailingAnchor constraintEqualToAnchor:self.gameContainer.trailingAnchor],
        [self.miniGameRow.bottomAnchor constraintEqualToAnchor:self.gameContainer.bottomAnchor constant:-5]
    ]];
}

- (UIStackView *)createRowWithKeys:(NSArray<NSString *> *)keys {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 10;
    for (NSString *key in keys) {
        [row addArrangedSubview:[self createDataCell:key]];
    }
    return row;
}

- (UIView *)createDataCell:(NSString *)title {
    UIView *container = [[UIView alloc] init];
    BOOL isPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    CGFloat titleSize = isPad ? 28.0 : 14.0;
    CGFloat valueSize = isPad ? 80.0 : 32.0;
    
    UILabel *lblTitle = [[UILabel alloc] init];
    lblTitle.text = title;
    lblTitle.textColor = APP_COLOR_ACCENT;
    lblTitle.font = [UIFont systemFontOfSize:titleSize];
    lblTitle.textAlignment = NSTextAlignmentCenter;
    
    UILabel *lblValue = [[UILabel alloc] init];
    lblValue.text = @"--";
    lblValue.textColor = [UIColor whiteColor];
    lblValue.font = [UIFont boldSystemFontOfSize:valueSize];
    lblValue.textAlignment = NSTextAlignmentCenter;
    
    self.valueLabels[title] = lblValue;
    self.titleLabels[title] = lblTitle;
    
    UIStackView *cellStack = [[UIStackView alloc] initWithArrangedSubviews:@[lblTitle, lblValue]];
    cellStack.axis = UILayoutConstraintAxisVertical;
    cellStack.alignment = UIStackViewAlignmentFill;
    cellStack.distribution = UIStackViewDistributionFill;
    cellStack.spacing = isPad ? 0 : 2;
    cellStack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:cellStack];
    [NSLayoutConstraint activateConstraints:@[
        [cellStack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [cellStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [cellStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor]
    ]];
    return container;
}

- (UIView *)createMiniGameCell:(NSString *)title {
    UIView *container = [[UIView alloc] init];
    BOOL isPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    CGFloat titleSize = isPad ? 16.0 : 12.0;
    CGFloat valueSize = isPad ? 32.0 : 20.0;
    UILabel *lblTitle = [[UILabel alloc] init];
    lblTitle.text = title;
    lblTitle.textColor = APP_COLOR_ACCENT;
    lblTitle.font = [UIFont systemFontOfSize:titleSize];
    lblTitle.textAlignment = NSTextAlignmentCenter;
    UILabel *lblValue = [[UILabel alloc] init];
    lblValue.text = @"--";
    lblValue.textColor = [UIColor whiteColor];
    lblValue.font = [UIFont boldSystemFontOfSize:valueSize];
    lblValue.textAlignment = NSTextAlignmentCenter;
    self.valueLabels[title] = lblValue;
    UIStackView *cellStack = [[UIStackView alloc] initWithArrangedSubviews:@[lblTitle, lblValue]];
    cellStack.axis = UILayoutConstraintAxisVertical;
    cellStack.alignment = UIStackViewAlignmentFill;
    cellStack.distribution = UIStackViewDistributionFill;
    cellStack.spacing = 2;
    cellStack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:cellStack];
    [NSLayoutConstraint activateConstraints:@[
        [cellStack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [cellStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [cellStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor]
    ]];
    return container;
}

- (void)setupObservers {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewBallData:) name:ScreenDataProcessorNewBallDataNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewClubData:) name:ScreenDataProcessorNewClubDataNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMiniGameStatusChanged:) name:MiniGameStatusChangedNotification object:nil];
    
    [self setBallData:[DataModel shared].currentShotBallData];
    [self setClubData:[DataModel shared].currentShotClubData];
    [self updateMiniGameData:[[DataModel shared] getMiniGameManager]];
}

- (NSMutableAttributedString *)attributedStringWithValue:(NSString *)value unit:(NSString *)unit {
    NSString *full = [NSString stringWithFormat:@"%@%@", value, unit];
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:full];
    UIFont *baseFont = self.valueLabels[@"Launch Angle (VLA)"].font;
    if (!baseFont) baseFont = [UIFont boldSystemFontOfSize:32];
    UIFont *unitFont = [baseFont fontWithSize:baseFont.pointSize * 0.5];
    NSRange unitRange = NSMakeRange(value.length, unit.length);
    [attr addAttribute:NSFontAttributeName value:unitFont range:unitRange];
    return attr;
}

// --- NEW HELPER: Local Calculation Logic ---
- (NSNumber *)calculateOfflineLocally:(NSDictionary *)data {
    double distance = [data[@"CarryDistance"] doubleValue];
    if (distance < 0.1) return nil;

    double hla = [data[@"HLA"] doubleValue];
    double spinAxis = [data[@"SpinAxis"] doubleValue];

    double hlaRad = hla * (M_PI / 180.0);
    double launchOffline = distance * sin(hlaRad);

    double curveFactor = 0.006;
    double curveOffline = distance * spinAxis * curveFactor;

    return @(launchOffline + curveOffline);
}

- (void)setBallData:(NSDictionary *)data {
    if(!data) return;
    
    bool isPutt = [data[@"IsPutt"] boolValue];
    NSString* distUnit = isPutt ? @"ft" : @"yd";
    
    self.valueLabels[@"Launch Angle (VLA)"].attributedText = [self attributedStringWithValue:[NSString stringWithFormat:@"%@", data[@"VLA"]] unit:@"°"];
    
    float hla = [data[@"HLA"] floatValue];
    NSString *hlaArrow = hla < 0 ? @"←" : (hla > 0 ? @"→" : @"");
    self.valueLabels[@"Offline (HLA)"].attributedText = [self attributedStringWithValue:[NSString stringWithFormat:@"%@%.1f", hlaArrow, fabs(hla)] unit:@"°"];
    
    // --- DISPLAY LOGIC ---
    NSNumber *offlineVal = data[@"CalcOffline"];
    
    // If DataModel hasn't calculated it yet (likely), calculate it here!
    if (!offlineVal) {
        offlineVal = [self calculateOfflineLocally:data];
    }
    
    if (offlineVal) {
        float offYds = [offlineVal floatValue];
        NSString *offArrow = offYds < 0 ? @"←" : (offYds > 0 ? @"→" : @"");
        self.valueLabels[@"Offline (Total)"].attributedText = [self attributedStringWithValue:[NSString stringWithFormat:@"%@%.1f", offArrow, fabs(offYds)] unit:@" yds"];
        self.titleLabels[@"Offline (Total)"].text = @"Offline (Carry)";
    } else {
        self.valueLabels[@"Offline (Total)"].text = @"--";
        self.titleLabels[@"Offline (Total)"].text = @"Offline (Carry)";
    }
    
    self.valueLabels[@"Spin"].attributedText = [self attributedStringWithValue:[NSString stringWithFormat:@"%@", data[@"TotalSpin"]] unit:@" rpm"];
    
    float spinAxis = [data[@"SpinAxis"] floatValue];
    NSString *spinArrow = spinAxis < 0 ? @"←" : (spinAxis > 0 ? @"→" : @"");
    self.valueLabels[@"Spin Axis"].attributedText = [self attributedStringWithValue:[NSString stringWithFormat:@"%@%.1f", spinArrow, fabs(spinAxis)] unit:@"°"];
    
    self.valueLabels[@"Ball Speed"].attributedText = [self attributedStringWithValue:[NSString stringWithFormat:@"%@", data[@"Speed"]] unit:@" mph"];
    
    self.valueLabels[@"Apex"].attributedText = [self attributedStringWithValue:[NSString stringWithFormat:@"%.0f", [data[@"Height"] floatValue] * 3.0] unit:@" ft"];
    
    self.valueLabels[@"Carry"].attributedText = [self attributedStringWithValue:[NSString stringWithFormat:@"%.0f", [data[@"CarryDistance"] floatValue]] unit:[NSString stringWithFormat:@" %@", distUnit]];
    
    if (data[@"TotalDistance"] && [data[@"TotalDistance"] floatValue] > 0) {
        self.valueLabels[@"Total"].attributedText = [self attributedStringWithValue:[NSString stringWithFormat:@"%.0f", [data[@"TotalDistance"] floatValue]] unit:[NSString stringWithFormat:@" %@", distUnit]];
    } else {
         self.valueLabels[@"Total"].text = @"--";
    }
    
    if (isPutt) {
        self.valueLabels[@"Carry"].text = @"--";
        self.valueLabels[@"Apex"].text = @"--";
        self.valueLabels[@"Spin"].text = @"--";
        self.valueLabels[@"Spin Axis"].text = @"--";
        self.valueLabels[@"Offline (Total)"].text = @"--";
        self.titleLabels[@"Offline (Total)"].text = @"Offline (Carry)";
    }
}

- (void)setClubData:(NSDictionary *)data {
    if(!data) return;
    
    self.valueLabels[@"Club Speed"].attributedText = [self attributedStringWithValue:[NSString stringWithFormat:@"%@", data[@"Speed"]] unit:@" mph"];
    
    float path = [data[@"Path"] floatValue];
    NSString *pathArrow = path < 0 ? @"←" : (path > 0 ? @"→" : @"");
    self.valueLabels[@"Path"].attributedText = [self attributedStringWithValue:[NSString stringWithFormat:@"%@%.1f", pathArrow, fabs(path)] unit:@"°"];
    
    float aoa = [data[@"AngleOfAttack"] floatValue];
    NSString *aoaArrow = aoa < 0 ? @"↓" : @"↑";
    self.valueLabels[@"AOA"].attributedText = [self attributedStringWithValue:[NSString stringWithFormat:@"%.1f", fabs(aoa)] unit:[NSString stringWithFormat:@"°%@", aoaArrow]];
}

- (void)handleNewBallData:(NSNotification *)notification {
    NSDictionary *data = notification.userInfo[@"data"];
    if (data) dispatch_async(dispatch_get_main_queue(), ^{ [self setBallData:data]; });
}

- (void)handleNewClubData:(NSNotification *)notification {
    NSDictionary *data = notification.userInfo[@"data"];
    if (data) dispatch_async(dispatch_get_main_queue(), ^{ [self setClubData:data]; });
}

- (void)endMiniGameTapped {
    [[DataModel shared] endMiniGameEarly];
    [self updateMiniGameData:nil];
}

- (void)updateMiniGameData:(MiniGameManager *)mgr {
    BOOL running = (mgr && [mgr getShotsRemaining] > 0);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.gameContainer.hidden = !running;
        
        if (running) {
            self.mainGridBottomConstraint.active = NO;
            self.mainGridBottomConstraint = [self.mainGrid.bottomAnchor constraintEqualToAnchor:self.gameContainer.topAnchor constant:-10];
            self.mainGridBottomConstraint.active = YES;
        } else {
            self.mainGridBottomConstraint.active = NO;
            self.mainGridBottomConstraint = [self.mainGrid.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20];
            self.mainGridBottomConstraint.active = YES;
        }
        
        [UIView animateWithDuration:0.3 animations:^{
            [self.view layoutIfNeeded];
        }];
        
        if (running) {
            NSString* distUnit = [mgr.gameType isEqualToString:@"Putting"] ? @"ft" : @"yd";
            
            self.valueLabels[@"Target"].text = [NSString stringWithFormat:@"%ld%@", (long)[mgr getTargetDistanceForCurrentShot], distUnit];
            
            NSString *par = formattedStringFromInteger([mgr getMostRecentShotToPar]);
            self.valueLabels[@"Last Score"].text = [NSString stringWithFormat:@"%ld (%@)", (long)[mgr getMostRecentShotScore], par];
            
            self.valueLabels[@"Shots Left"].text = [NSString stringWithFormat:@"%ld", (long)[mgr getShotsRemaining]];
            
            NSString *totPar = formattedStringFromInteger([mgr getTotalToPar]);
            self.valueLabels[@"Total Score"].text = [NSString stringWithFormat:@"%ld (%@)", (long)[mgr getTotalScore], totPar];
        }
    });
}

- (void)handleMiniGameStatusChanged:(NSNotification *)n {
    MiniGameManager *mgr = n.userInfo[@"miniGameManager"];
    [self updateMiniGameData:mgr];
    
    if (mgr && [mgr getShotsRemaining] == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MiniGameEndViewController *endVC = [[MiniGameEndViewController alloc] init];
            endVC.finalScoreString = [NSString stringWithFormat:@"%ld (%@)", (long)[mgr getTotalScore], formattedStringFromInteger([mgr getTotalToPar])];
            endVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
            [self presentViewController:endVC animated:YES completion:nil];
        });
    }
}

@end
