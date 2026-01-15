#import "MiniGameSettingsViewController.h"
#import "Theme.h"
#import "MiniGameManager.h"
#import "MiniGameSettingsStore.h"
#import "DataModel.h"

@interface MiniGameSettingsViewController () <UIPickerViewDelegate, UIPickerViewDataSource, UITextFieldDelegate>

// Layout
@property (nonatomic, strong) UIStackView *mainStack;
@property (nonatomic, strong) UIStackView *formStack;

// UI
@property (nonatomic, strong) UITextView *instructionsTextView;
@property (nonatomic, strong) UISegmentedControl *typeSegment;

// Skill Section (Nested Stack for clean hiding)
@property (nonatomic, strong) UIStackView *skillStack;
@property (nonatomic, strong) UILabel *skillLabel;
@property (nonatomic, strong) UITextField *skillField;

// Distances
@property (nonatomic, strong) UITextField *minDistanceField;
@property (nonatomic, strong) UITextField *maxDistanceField;

// Other
@property (nonatomic, strong) UISegmentedControl *formatSegment;
@property (nonatomic, strong) UITextField *numShotsField;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *okButton;

// Pickers
@property (nonatomic, strong) UIPickerView *shotsPicker;
@property (nonatomic, strong) UIPickerView *skillPicker;
@property (nonatomic, strong) NSArray<NSString *> *skillOptions;
@property (nonatomic, strong) NSArray<NSNumber *> *shotsOptions;

@end

@implementation MiniGameSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = APP_COLOR_BG;
    
    [[DataModel shared] setProcessingPaused:YES];
    
    self.shotsOptions = @[@5, @10, @15, @20, @30, @50];
    self.skillOptions = @[@"Tour", @"Scratch", @"5 HCP", @"10 HCP", @"15 HCP", @"20 HCP"];
    
    // Main Container
    self.mainStack = [[UIStackView alloc] init];
    self.mainStack.axis = UILayoutConstraintAxisHorizontal;
    self.mainStack.distribution = UIStackViewDistributionFillEqually;
    self.mainStack.spacing = 15;
    self.mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.mainStack];
    
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.mainStack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [self.mainStack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:10],
        [self.mainStack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-10],
        [self.mainStack.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10]
    ]];
    
    [self setupInstructions];
    [self setupForm];
    [self loadSettingsForCurrentSegment];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    [self.view addGestureRecognizer:tap];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[DataModel shared] setProcessingPaused:NO];
}

// FIX: Helper Method to match Settings Screen styling
- (void)styleSegmentedControl:(UISegmentedControl *)sc {
    sc.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    [sc setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
    [sc setTitleTextAttributes:@{NSForegroundColorAttributeName: APP_COLOR_BG} forState:UIControlStateSelected];
}

- (void)setupInstructions {
    self.instructionsTextView = [[UITextView alloc] init];
    self.instructionsTextView.editable = NO;
    self.instructionsTextView.backgroundColor = [UIColor clearColor];
    self.instructionsTextView.textColor = [UIColor whiteColor];
    self.instructionsTextView.font = [UIFont systemFontOfSize:14]; // Compact font
    [self.mainStack addArrangedSubview:self.instructionsTextView];
    [self updateInstructionsText];
}

- (void)setupForm {
    self.formStack = [[UIStackView alloc] init];
    self.formStack.axis = UILayoutConstraintAxisVertical;
    self.formStack.spacing = 8;
    self.formStack.distribution = UIStackViewDistributionFill;
    self.formStack.alignment = UIStackViewAlignmentFill;
    
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:self.formStack];
    self.formStack.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.formStack.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
        [self.formStack.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [self.formStack.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
        [self.formStack.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
        [self.formStack.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor]
    ]];
    [self.mainStack addArrangedSubview:scrollView];
    
    // 1. Game Mode
    [self addLabel:@"Game Mode:"];
    self.typeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Distance", @"Putting", @"Accuracy"]];
    [self styleSegmentedControl:self.typeSegment]; // APPLY STYLE FIX
    self.typeSegment.selectedSegmentIndex = 0;
    [self.typeSegment addTarget:self action:@selector(typeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.formStack addArrangedSubview:self.typeSegment];
    
    // 2. Skill Level
    self.skillStack = [[UIStackView alloc] init];
    self.skillStack.axis = UILayoutConstraintAxisVertical;
    self.skillStack.spacing = 8;
    self.skillStack.hidden = YES;
    
    self.skillLabel = [self createLabel:@"Skill Level:"];
    [self.skillStack addArrangedSubview:self.skillLabel];
    
    self.skillField = [self createTextField];
    self.skillField.text = @"10 HCP";
    self.skillPicker = [[UIPickerView alloc] init];
    self.skillPicker.delegate = self; self.skillPicker.dataSource = self;
    self.skillField.inputView = self.skillPicker;
    [self.skillStack addArrangedSubview:self.skillField];
    
    [self.formStack addArrangedSubview:self.skillStack];
    
    // 3. Distance Range
    [self addLabel:@"Distance Range Yds (Min - Max):"];
    UIStackView *distRow = [[UIStackView alloc] init];
    distRow.axis = UILayoutConstraintAxisHorizontal;
    distRow.spacing = 10;
    distRow.distribution = UIStackViewDistributionFillEqually;
    self.minDistanceField = [self createTextField];
    self.minDistanceField.keyboardType = UIKeyboardTypeNumberPad;
    self.maxDistanceField = [self createTextField];
    self.maxDistanceField.keyboardType = UIKeyboardTypeNumberPad;
    [distRow addArrangedSubview:self.minDistanceField];
    [distRow addArrangedSubview:self.maxDistanceField];
    [self.formStack addArrangedSubview:distRow];
    
    // 4. Format
    [self addLabel:@"Format:"];
    self.formatSegment = [[UISegmentedControl alloc] initWithItems:@[@"Incremental", @"Random"]];
    [self styleSegmentedControl:self.formatSegment]; // APPLY STYLE FIX
    [self.formStack addArrangedSubview:self.formatSegment];
    
    // 5. Shots
    [self addLabel:@"Number of Shots:"];
    self.numShotsField = [self createTextField];
    self.shotsPicker = [[UIPickerView alloc] init];
    self.shotsPicker.delegate = self; self.shotsPicker.dataSource = self;
    self.numShotsField.inputView = self.shotsPicker;
    [self.formStack addArrangedSubview:self.numShotsField];
    
    // Spacer
    UIView *spacer = [[UIView alloc] init];
    [spacer.heightAnchor constraintEqualToConstant:10].active = YES;
    [self.formStack addArrangedSubview:spacer];
    
    // 6. Buttons
    UIStackView *btnRow = [[UIStackView alloc] init];
    btnRow.axis = UILayoutConstraintAxisHorizontal;
    btnRow.spacing = 15;
    btnRow.distribution = UIStackViewDistributionFillEqually;
    self.cancelButton = [self createStyledButton:@"Cancel" action:@selector(cancelPressed)];
    self.okButton = [self createStyledButton:@"Start Game" action:@selector(okPressed)];
    [btnRow addArrangedSubview:self.cancelButton];
    [btnRow addArrangedSubview:self.okButton];
    [self.formStack addArrangedSubview:btnRow];
    
    UIView *fill = [[UIView alloc] init];
    [self.formStack addArrangedSubview:fill];
}

// --- Dynamic Updates ---

- (void)typeChanged:(id)sender {
    [self loadSettingsForCurrentSegment];
    [self updateSkillVisibility];
    [self updateInstructionsText];
}

- (void)updateSkillVisibility {
    BOOL isAccuracy = (self.typeSegment.selectedSegmentIndex == 2);
    [UIView animateWithDuration:0.25 animations:^{
        self.skillStack.hidden = !isAccuracy;
        self.skillStack.alpha = isAccuracy ? 1.0 : 0.0;
        [self.view layoutIfNeeded];
    }];
}

- (void)updateInstructionsText {
    NSString *mode = [self.typeSegment titleForSegmentAtIndex:self.typeSegment.selectedSegmentIndex];
    NSMutableString *text = [NSMutableString string];
    
    [text appendString:@"MINI GAME RULES\n\n"];
    
    if ([mode isEqualToString:@"Accuracy"]) {
        [text appendFormat:@"MODE: %@\n", mode];
        [text appendString:@"Hit target distance & direction.\n\n"];
        [text appendString:@"SCORING\nScore based on dispersion vs skill level.\n\n"];
        [text appendString:@"SKILL LEVELS (Dispersion Radius @ 150y)\n"];
        [text appendString:@"• Tour (4%): 6y\n• Scratch (6%): 9y\n• 5 HCP (8%): 12y\n"];
        [text appendString:@"• 10 HCP (10%): 15y\n• 15 HCP (12%): 18y\n• 20 HCP (15%): 22.5y"];
    } else {
        [text appendFormat:@"MODE: %@\n", mode];
        if ([mode isEqualToString:@"Putting"]) {
            [text appendString:@"Hit specific Total Putt Distance targets.\n\n"];
        } else {
            [text appendString:@"Hit specific Carry Distance targets.\n\n"];
        }
        
        [text appendString:@"SCORING\n"];
        [text appendString:@"• Birdie: Inside 5% of target\n"];
        [text appendString:@"• Par: Inside 10% of target\n"];
        [text appendString:@"• Bogey: Outside 10% of target\n"];
    }
    
    self.instructionsTextView.text = text;
}

- (void)loadSettingsForCurrentSegment {
    NSString *type = [self.typeSegment titleForSegmentAtIndex:self.typeSegment.selectedSegmentIndex];
    NSDictionary *saved = [MiniGameSettingsStore loadSettingsForType:type];
    
    if (saved.count > 0) {
        self.minDistanceField.text = [NSString stringWithFormat:@"%@", saved[@"minDistance"]];
        self.maxDistanceField.text = [NSString stringWithFormat:@"%@", saved[@"maxDistance"]];
        self.formatSegment.selectedSegmentIndex = [saved[@"format"] isEqualToString:@"Incremental"] ? 0 : 1;
        self.numShotsField.text = [NSString stringWithFormat:@"%@", saved[@"numShots"]];
    } else {
        if ([type isEqualToString:@"Accuracy"]) {
            self.minDistanceField.text = @"100"; self.maxDistanceField.text = @"200";
        } else if ([type isEqualToString:@"Putting"]) {
            self.minDistanceField.text = @"5"; self.maxDistanceField.text = @"30";
        } else {
            self.minDistanceField.text = @"20"; self.maxDistanceField.text = @"100";
        }
        self.numShotsField.text = @"10";
    }
    [self updateSkillVisibility];
    [self updateInstructionsText];
}

- (void)okPressed {
    NSString *type = [self.typeSegment titleForSegmentAtIndex:self.typeSegment.selectedSegmentIndex];
    NSInteger min = [self.minDistanceField.text integerValue];
    NSInteger max = [self.maxDistanceField.text integerValue];
    NSString *fmt = (self.formatSegment.selectedSegmentIndex == 0) ? @"Incremental" : @"Random";
    NSInteger shots = [self.numShotsField.text integerValue];
    NSString *skill = self.skillField.text;
    
    [MiniGameSettingsStore saveSettingsForType:type format:fmt minDistance:min maxDistance:max numShots:shots];
    
    NSDictionary *info = @{
        @"gameType": type,
        @"minDistance": @(min),
        @"maxDistance": @(max),
        @"format": fmt,
        @"numberOfShots": @(shots),
        @"skillLevel": skill
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:MiniGameStartNotification object:nil userInfo:info];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancelPressed { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)dismissKeyboard { [self.view endEditing:YES]; }

// --- UI HELPERS ---
- (void)addLabel:(NSString *)text { [self.formStack addArrangedSubview:[self createLabel:text]]; }

- (UILabel *)createLabel:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.textColor = APP_COLOR_ACCENT;
    l.font = [UIFont boldSystemFontOfSize:13]; // Slightly smaller label
    return l;
}

- (UITextField *)createTextField {
    UITextField *t = [[UITextField alloc] init];
    t.borderStyle = UITextBorderStyleRoundedRect;
    t.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    t.textColor = [UIColor whiteColor];
    [t.heightAnchor constraintEqualToConstant:32].active = YES; // Compact height
    
    UIToolbar *tb = [[UIToolbar alloc] initWithFrame:CGRectMake(0,0,300,44)];
    UIBarButtonItem *d = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboard)];
    tb.items = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil], d];
    t.inputAccessoryView = tb;
    return t;
}

- (UIButton *)createStyledButton:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:APP_COLOR_ACCENT forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    b.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    b.layer.cornerRadius = 8;
    b.layer.borderWidth = 1;
    b.layer.borderColor = APP_COLOR_ACCENT.CGColor;
    [b.heightAnchor constraintEqualToConstant:40].active = YES;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

// Pickers
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView { return 1; }
- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return (pickerView == self.skillPicker) ? self.skillOptions.count : self.shotsOptions.count;
}
- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    return (pickerView == self.skillPicker) ? self.skillOptions[row] : [NSString stringWithFormat:@"%@", self.shotsOptions[row]];
}
- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    if (pickerView == self.skillPicker) self.skillField.text = self.skillOptions[row];
    else self.numShotsField.text = [NSString stringWithFormat:@"%@", self.shotsOptions[row]];
}

@end
