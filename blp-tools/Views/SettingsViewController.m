#import "SettingsViewController.h"
#import "Theme.h"
#import "SettingsManager.h"
#import "GSProConnector.h"
#import "OGSConnector.h"
#import "DataModel.h"

@interface SettingsViewController () <UIPickerViewDataSource, UIPickerViewDelegate, UITextFieldDelegate>

// UI Elements
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStackView;

@property (nonatomic, strong) UIPickerView *stimpPicker;
@property (nonatomic, strong) NSArray<NSNumber *> *stimpValues;
@property (nonatomic, assign) NSInteger selectedStimpIndex;

@property (nonatomic, strong) UITextField *stimpField;
@property (nonatomic, strong) UISegmentedControl *fairwayControl;
@property (nonatomic, strong) UITextField *ipField;

@property (nonatomic, strong) UISegmentedControl *targetControl;
@property (nonatomic, strong) UISlider *fpsSlider;
@property (nonatomic, strong) UILabel *fpsValueLabel;
@property (nonatomic, strong) UIButton *testButton;
@property (nonatomic, strong) UIView *statusLight;

@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = APP_COLOR_BG;
    
    // --- 1. SETUP DATA ---
    NSMutableArray<NSNumber *> *values = [NSMutableArray array];
    for (NSInteger i = 5; i <= 15; i++) { [values addObject:@(i)]; }
    self.stimpValues = [values copy];
    self.selectedStimpIndex = 5;

    // --- 2. LAYOUT SCAFFOLDING ---
    [self setupLayoutScaffolding];
    
    // --- 3. BUILD ROWS ---
    BOOL isPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    CGFloat fontSize = isPad ? 22.0 : 16.0;
    
    // A. Fairway Row
    UILabel *fairwayLabel = [self createLabel:@"Fairway Speed:" size:fontSize];
    self.fairwayControl = [[UISegmentedControl alloc] initWithItems:@[@"slow", @"medium", @"fast", @"links"]];
    [self styleSegmentedControl:self.fairwayControl];
    // REMOVED SCALE TRANSFORM to fix alignment issues
    self.fairwayControl.selectedSegmentIndex = 1;
    [self.fairwayControl addTarget:self action:@selector(fairwayControlChanged:) forControlEvents:UIControlEventValueChanged];
    [self addRowWithLabel:fairwayLabel control:self.fairwayControl];

    // B. Stimp Row
    [self setupStimpInput];
    UILabel *stimpLabel = [self createLabel:@"Putting Stimp:" size:fontSize];
    [self addRowWithLabel:stimpLabel control:self.stimpField];
    
    // C. Target Row
    [self addTargetRowWithFontSize:fontSize];
    
    // D. IP Row
    [self setupIPInput];
    UILabel *ipLabel = [self createLabel:@"Simulator IP:" size:fontSize];
    [self addRowWithLabel:ipLabel control:self.ipField];
    
    // E. FPS Row
    [self addFPSRowWithFontSize:fontSize];
    
    // F. Footer Area
    [self addFooterWithFontSize:fontSize];

    // --- 4. OBSERVERS ---
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    
    // Start Status Timer
    [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refreshStatusLight) userInfo:nil repeats:YES];
    [self refreshStatusLight];
}

// --- STYLING HELPERS ---

- (void)styleTextField:(UITextField *)tf {
    tf.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    tf.textColor = [UIColor whiteColor];
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.layer.cornerRadius = 6.0;
    tf.layer.masksToBounds = YES;
}

- (void)styleButton:(UIButton *)btn {
    [btn setTitleColor:APP_COLOR_ACCENT forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    btn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    btn.layer.cornerRadius = 8.0;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = APP_COLOR_ACCENT.CGColor;
}

- (void)styleSegmentedControl:(UISegmentedControl *)sc {
    sc.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    [sc setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
    [sc setTitleTextAttributes:@{NSForegroundColorAttributeName: APP_COLOR_BG} forState:UIControlStateSelected];
}

// --- LAYOUT ---

- (void)setupLayoutScaffolding {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    self.mainStackView = [[UIStackView alloc] init];
    self.mainStackView.axis = UILayoutConstraintAxisVertical;
    self.mainStackView.alignment = UIStackViewAlignmentFill;
    self.mainStackView.distribution = UIStackViewDistributionFill;
    
    BOOL isPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    self.mainStackView.spacing = isPad ? 50.0 : 25.0;
    
    self.mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.mainStackView];
    
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    CGFloat width = isPad ? 700 : 500;

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        
        [self.mainStackView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:40],
        [self.mainStackView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-40],
        [self.mainStackView.centerXAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.centerXAnchor],
        [self.mainStackView.widthAnchor constraintEqualToConstant:width]
    ]];
    
    if (!isPad) {
        NSLayoutConstraint *widthConstraint = [self.mainStackView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor constant:-40];
        widthConstraint.priority = UILayoutPriorityDefaultHigh;
        widthConstraint.active = YES;
    }
}

- (void)addRowWithLabel:(UIView *)leftView control:(UIView *)rightView {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[leftView, rightView]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFill;
    row.spacing = 20;
    
    [leftView.widthAnchor constraintEqualToAnchor:row.widthAnchor multiplier:0.35].active = YES;
    [self.mainStackView addArrangedSubview:row];
}

- (void)addTargetRowWithFontSize:(CGFloat)fontSize {
    UILabel *label = [self createLabel:@"Target Sim:" size:fontSize];
    
    self.targetControl = [[UISegmentedControl alloc] initWithItems:@[@"OpenGolf", @"GSPro"]];
    [self styleSegmentedControl:self.targetControl];
    // REMOVED SCALE TRANSFORM to fix overlap
    
    BOOL useOGS = [[NSUserDefaults standardUserDefaults] boolForKey:@"use_ogs"];
    self.targetControl.selectedSegmentIndex = useOGS ? 0 : 1;
    [self.targetControl addTarget:self action:@selector(targetControlChanged:) forControlEvents:UIControlEventValueChanged];
    
    self.statusLight = [[UIView alloc] init];
    self.statusLight.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusLight.widthAnchor constraintEqualToConstant:16].active = YES;
    [self.statusLight.heightAnchor constraintEqualToConstant:16].active = YES;
    self.statusLight.layer.cornerRadius = 8;
    self.statusLight.backgroundColor = [UIColor grayColor];
    self.statusLight.layer.borderWidth = 1.0;
    self.statusLight.layer.borderColor = [UIColor whiteColor].CGColor;
    
    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.testButton setTitle:@"Test" forState:UIControlStateNormal];
    [self styleButton:self.testButton];
    
    [self.testButton.widthAnchor constraintEqualToConstant:80].active = YES;
    [self.testButton addTarget:self action:@selector(testConnectionPressed) forControlEvents:UIControlEventTouchUpInside];
    
    UIStackView *rightStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.targetControl, self.statusLight, self.testButton]];
    rightStack.axis = UILayoutConstraintAxisHorizontal;
    rightStack.alignment = UIStackViewAlignmentCenter;
    rightStack.spacing = 20; // Ensure enough space between selector and light
    
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, rightStack]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFill;
    row.spacing = 20;
    
    [self.mainStackView addArrangedSubview:row];
    [label.widthAnchor constraintEqualToAnchor:row.widthAnchor multiplier:0.35].active = YES;
}

- (void)addFPSRowWithFontSize:(CGFloat)fontSize {
    UILabel *label = [self createLabel:@"Camera Capture Speed:" size:fontSize];
    
    self.fpsSlider = [[UISlider alloc] init];
    self.fpsSlider.minimumValue = 2.0;
    self.fpsSlider.maximumValue = 20.0;
    [self.fpsSlider addTarget:self action:@selector(fpsSliderChanged:) forControlEvents:UIControlEventValueChanged];
    
    self.fpsValueLabel = [self createLabel:@"- fps" size:fontSize];
    self.fpsValueLabel.textAlignment = NSTextAlignmentRight;
    [self.fpsValueLabel.widthAnchor constraintEqualToConstant:80].active = YES;
    
    UIStackView *rightStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.fpsSlider, self.fpsValueLabel]];
    rightStack.axis = UILayoutConstraintAxisHorizontal;
    rightStack.spacing = 10;
    
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, rightStack]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFill;
    row.spacing = 20;
    
    [self.mainStackView addArrangedSubview:row];
    [label.widthAnchor constraintEqualToAnchor:row.widthAnchor multiplier:0.35].active = YES;
}

- (void)addFooterWithFontSize:(CGFloat)fontSize {
    UIStackView *footerStack = [[UIStackView alloc] init];
    footerStack.axis = UILayoutConstraintAxisVertical;
    footerStack.alignment = UIStackViewAlignmentCenter;
    footerStack.spacing = 10;
    
    UIButton *supportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [supportButton setTitle:@"Questions & Support" forState:UIControlStateNormal];
    [supportButton setTitleColor:APP_COLOR_ACCENT forState:UIControlStateNormal];
    supportButton.titleLabel.font = [UIFont systemFontOfSize:fontSize];
    [supportButton addTarget:self action:@selector(supportButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    [footerStack addArrangedSubview:supportButton];
    
    UILabel *footerLabel = [self createLabel:@"© 2025 Heapsheeps LLC" size:fontSize - 4];
    footerLabel.textColor = APP_COLOR_DARK_TEXT;
    footerLabel.textAlignment = NSTextAlignmentCenter;
    [footerStack addArrangedSubview:footerLabel];
    
    [self.mainStackView addArrangedSubview:footerStack];
}

- (UILabel *)createLabel:(NSString *)text size:(CGFloat)size {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.textColor = APP_COLOR_TEXT;
    l.font = [UIFont systemFontOfSize:size];
    return l;
}

- (void)setupStimpInput {
    self.stimpField = [[UITextField alloc] init];
    [self styleTextField:self.stimpField];
    self.stimpField.textAlignment = NSTextAlignmentCenter;
    
    self.stimpPicker = [[UIPickerView alloc] init];
    self.stimpPicker.dataSource = self;
    self.stimpPicker.delegate = self;
    self.stimpField.inputView = self.stimpPicker;
    
    UIToolbar *t = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(dismissKeyboard)];
    t.items = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil], done];
    self.stimpField.inputAccessoryView = t;
}

- (void)setupIPInput {
    self.ipField = [[UITextField alloc] init];
    [self styleTextField:self.ipField];
    self.ipField.placeholder = @"192.168.x.x";
    self.ipField.keyboardType = UIKeyboardTypeDecimalPad;
    self.ipField.delegate = self;
    
    UIToolbar *t = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(dismissKeyboard)];
    t.items = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil], done];
    self.ipField.inputAccessoryView = t;
}

// --- LOGIC METHODS ---

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    SettingsManager *mgr = [SettingsManager shared];

    BOOL useOGS = [[NSUserDefaults standardUserDefaults] boolForKey:@"use_ogs"];
    self.targetControl.selectedSegmentIndex = useOGS ? 0 : 1;
    [self updateConnectionLogic:useOGS];

    NSString *savedIP = [[NSUserDefaults standardUserDefaults] stringForKey:@"simulator_ip"];
    if (!savedIP) savedIP = mgr.gsProIP;
    self.ipField.text = savedIP;

    float fps = [[NSUserDefaults standardUserDefaults] floatForKey:@"camera_fps"];
    if (fps < 2.0) { fps = 2.0; [[NSUserDefaults standardUserDefaults] setFloat:fps forKey:@"camera_fps"]; }
    self.fpsSlider.value = fps;
    self.fpsValueLabel.text = [NSString stringWithFormat:@"%.0f fps", fps];
    
    NSInteger stimp = mgr.stimp;
    NSInteger rowIndex = [self.stimpValues indexOfObject:@(stimp)];
    if (rowIndex == NSNotFound) rowIndex = 5;
    self.selectedStimpIndex = rowIndex;
    [self.stimpPicker selectRow:rowIndex inComponent:0 animated:NO];
    self.stimpField.text = [NSString stringWithFormat:@"%@", self.stimpValues[rowIndex]];
    
    self.fairwayControl.selectedSegmentIndex = mgr.fairwaySpeedIndex;
}

- (void)updateConnectionLogic:(BOOL)isOGS {
    if (isOGS) {
        BOOL connected = [[OGSConnector shared] isConnected];
        self.statusLight.backgroundColor = connected ? [UIColor greenColor] : [UIColor redColor];
    } else {
        BOOL connected = NO;
        if ([[GSProConnector shared] respondsToSelector:@selector(isConnected)]) {
            connected = [[GSProConnector shared] isConnected];
        }
        self.statusLight.backgroundColor = connected ? [UIColor greenColor] : [UIColor redColor];
    }
}

- (void)refreshStatusLight {
    BOOL isOGS = (self.targetControl.selectedSegmentIndex == 0);
    [self updateConnectionLogic:isOGS];
}

- (void)targetControlChanged:(UISegmentedControl *)sender {
    BOOL isOGS = (sender.selectedSegmentIndex == 0);
    [[NSUserDefaults standardUserDefaults] setBool:isOGS forKey:@"use_ogs"];
    [self updateConnectionLogic:isOGS];
    
    if (isOGS) {
        [[GSProConnector shared] disconnect];
        NSString *ip = self.ipField.text;
        if (ip.length > 0) [[OGSConnector shared] connectToIP:ip port:3111];
    } else {
        [[OGSConnector shared] disconnect];
        NSString *ip = self.ipField.text;
        if (ip.length > 0) [[GSProConnector shared] connectToServerWithIP:ip port:921];
    }
}

- (void)fpsSliderChanged:(UISlider *)sender {
    int roundedFPS = (int)roundf(sender.value);
    [sender setValue:roundedFPS animated:NO];
    self.fpsValueLabel.text = [NSString stringWithFormat:@"%d fps", roundedFPS];
    [[NSUserDefaults standardUserDefaults] setFloat:(float)roundedFPS forKey:@"camera_fps"];
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.ipField) {
        [[NSUserDefaults standardUserDefaults] setObject:textField.text forKey:@"simulator_ip"];
        [[SettingsManager shared] setGSProIP:textField.text];
        [[SettingsManager shared] saveSettings];
        [self forceReconnect];
    }
}

- (void)forceReconnect {
    BOOL isOGS = (self.targetControl.selectedSegmentIndex == 0);
    [[GSProConnector shared] disconnect];
    [[OGSConnector shared] disconnect];
    NSString *ip = self.ipField.text;
    if (ip.length > 0) {
        if (isOGS) [[OGSConnector shared] connectToIP:ip port:3111];
        else [[GSProConnector shared] connectToServerWithIP:ip port:921];
    }
    [self updateConnectionLogic:isOGS];
}

- (void)testConnectionPressed {
    BOOL isOGS = (self.targetControl.selectedSegmentIndex == 0);
    
    id connector = isOGS ? [OGSConnector shared] : [GSProConnector shared];
    
    if (![connector isConnected]) {
        NSString *ip = self.ipField.text;
        if (isOGS) [[OGSConnector shared] connectToIP:ip port:3111];
        else [[GSProConnector shared] connectToServerWithIP:ip port:921];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([connector isConnected]) { /* OK */ }
        });
    }
    
    NSDictionary *ballData = @{
        @"Speed": @(150),
        @"VLA": @(12.5),
        @"HLA": @(1.5),
        @"TotalSpin": @(2500),
        @"SpinAxis": @(-2.0),
        @"CarryDistance": @(250),
        @"TotalDistance": @(270),
        @"Height": @(32)
    };
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScreenDataProcessorNewBallDataNotification"
                                                        object:nil
                                                      userInfo:@{@"data": ballData}];
    
    NSDictionary *clubData = @{
        @"Speed": @(105),
        @"Path": @(2.3),
        @"AngleOfAttack": @(-1.5)
    };
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ScreenDataProcessorNewClubDataNotification"
                                                            object:nil
                                                          userInfo:@{@"data": clubData}];
    });
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sent" message:@"Test shot data sent." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)fairwayControlChanged:(UISegmentedControl *)sender {
    SettingsManager *mgr = [SettingsManager shared];
    mgr.fairwaySpeedIndex = sender.selectedSegmentIndex;
    [mgr saveSettings];
}

- (void)supportButtonPressed {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://www.heapsheeps.com"] options:@{} completionHandler:nil];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - Picker Delegate
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView { return 1; }
- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component { return self.stimpValues.count; }
- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component { return [self.stimpValues[row] stringValue]; }
- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    self.selectedStimpIndex = row;
    NSInteger selectedStimp = [self.stimpValues[row] integerValue];
    self.stimpField.text = [NSString stringWithFormat:@"%ld", (long)selectedStimp];
    SettingsManager *mgr = [SettingsManager shared];
    mgr.stimp = selectedStimp;
    [mgr saveSettings];
}

#pragma mark - Keyboard Handling
- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary* info = [notification userInfo];
    CGSize kbSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, kbSize.height, 0.0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.scrollView.contentInset = UIEdgeInsetsZero;
    self.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
}

@end
