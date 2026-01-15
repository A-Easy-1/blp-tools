#import "MiniGameEndViewController.h"
#import "Theme.h"

@interface MiniGameEndViewController ()

@property (nonatomic, strong) UILabel *scoreLabel;
@property (nonatomic, strong) UIButton *replayButton;
@property (nonatomic, strong) UIButton *exitButton;

@end

@implementation MiniGameEndViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Use a semi-transparent dark background so the modal stands out
    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    
    // Container view for the content
    UIView *containerView = [[UIView alloc] init];
    containerView.backgroundColor = APP_COLOR_BG;
    containerView.layer.cornerRadius = 10.0;
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:containerView];
    
    // Center container view in the modal view
    [NSLayoutConstraint activateConstraints:@[
        [containerView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [containerView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [containerView.widthAnchor constraintEqualToConstant:400],
        [containerView.heightAnchor constraintEqualToConstant:400]
    ]];
    
    // Score label: "Final score: <score>"
    UILabel *scoreLabel = [[UILabel alloc] init];
    scoreLabel.translatesAutoresizingMaskIntoConstraints = NO;
    scoreLabel.textAlignment = NSTextAlignmentCenter;
    scoreLabel.font = [UIFont boldSystemFontOfSize:24];
    scoreLabel.text = [NSString stringWithFormat:@"Final score: %@", self.finalScoreString];
    scoreLabel.textColor = [UIColor whiteColor]; // Ensure readable on dark BG
    [containerView addSubview:scoreLabel];
    
    // Create the "Finish" button
    UIButton *actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [actionButton setTitle:@"Finish" forState:UIControlStateNormal];
    
    // STYLE: Consistent Dark BG + Green Border
    [actionButton setTitleColor:APP_COLOR_ACCENT forState:UIControlStateNormal];
    [actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    actionButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    actionButton.layer.cornerRadius = 8.0;
    actionButton.layer.borderWidth = 1.0;
    actionButton.layer.borderColor = APP_COLOR_ACCENT.CGColor;
    actionButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    
    [actionButton addTarget:self action:@selector(finishButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [containerView addSubview:actionButton];
    
    // Layout constraints for score label and button
    [NSLayoutConstraint activateConstraints:@[
        // Score label
        [scoreLabel.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:20],
        [scoreLabel.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:20],
        [scoreLabel.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-20],
        
        // Button (Reduced Size: 30% smaller)
        [actionButton.topAnchor constraintEqualToAnchor:scoreLabel.bottomAnchor constant:30],
        [actionButton.centerXAnchor constraintEqualToAnchor:containerView.centerXAnchor],
        [actionButton.widthAnchor constraintEqualToConstant:80], // Reduced from 100
        [actionButton.heightAnchor constraintEqualToConstant:36] // Reduced from 44
    ]];
}

- (void)finishButtonTapped {
    [self dismissViewControllerAnimated:YES completion:^{
    }];
}

@end
