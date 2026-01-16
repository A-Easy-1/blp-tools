//#import "DebugViewController.h"
//#import "CameraManager.h"
//#import "DataModel.h"
//#import "ImageUtilities.h"
//
//@interface DebugViewController ()
//@property (nonatomic, strong) UIImageView *cameraView;
//@property (nonatomic, strong) NSArray<NSValue *> *corners;
//@end
//
//@implementation DebugViewController
//
//- (void)viewDidLoad {
//    [super viewDidLoad];
//    self.view.backgroundColor = [UIColor blackColor];
//
//    // UIImageView for displaying the latest processed frame
//    self.cameraView = [[UIImageView alloc] initWithFrame:self.view.bounds];
//    self.cameraView.contentMode = UIViewContentModeScaleAspectFit;
//    self.cameraView.clipsToBounds = YES;
//    [self.view addSubview:self.cameraView];
//
//    // Listen for new frames and new corners
//    [[NSNotificationCenter defaultCenter] addObserver:self
//                                             selector:@selector(updateFrame:)
//                                                 name:CameraManagerNewFrameNotification
//                                               object:nil];
//    
//    [[NSNotificationCenter defaultCenter] addObserver:self
//                                             selector:@selector(updateCorners:)
//                                                 name:ScreenDataProcessorNewCornersNotification
//                                               object:nil];
//    
//    self.corners = [[DataModel shared].screenCorners copy];
//}
//
//- (void)viewWillAppear:(BOOL)animated {
//    [super viewWillAppear:animated];
//    [self updateFrame:nil];
//}
//
//- (void)updateFrame:(NSNotification *)notification {
//    UIImage *latestFrame = notification.userInfo[@"frame"];
//    if (!latestFrame)
//        return;
//    
//    // Draw the detected corners on the frame
//    UIImage *processedImage = [self drawPolygonOnImage:latestFrame corners:self.corners];
//
//    // Update UI on main thread
//    dispatch_async(dispatch_get_main_queue(), ^{
//        self.cameraView.image = processedImage;
//    });
//}
//
//- (void)updateCorners:(NSNotification *)notification {
//    NSArray *corners = notification.userInfo[@"corners"];
//    if (!corners)
//        return;
//    
//    self.corners = [corners copy];
//}
//
//// Draws detected corners onto the frame
//- (UIImage *)drawPolygonOnImage:(UIImage *)image corners:(NSArray<NSValue *> *)corners {
//    if (!image || corners.count < 4) return image;
//
//    // Use 'false' for opacity to avoid black background issues
//    UIGraphicsBeginImageContextWithOptions(image.size, false, 0);
//    [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
//
//    CGContextRef context = UIGraphicsGetCurrentContext();
//    CGContextSetStrokeColorWithColor(context, [UIColor greenColor].CGColor);
//    CGContextSetLineWidth(context, 5.0);
//
//    CGPoint p1 = [corners[0] CGPointValue];
//    CGPoint p2 = [corners[1] CGPointValue];
//    CGPoint p3 = [corners[2] CGPointValue];
//    CGPoint p4 = [corners[3] CGPointValue];
//    
//    // --- FIX: REMOVED COORDINATE FLIP ---
//    // The camera image is now "Upright", so we use the coordinates directly.
//    
//    CGContextMoveToPoint(   context, p1.x, p1.y);
//    CGContextAddLineToPoint(context, p2.x, p2.y);
//    CGContextAddLineToPoint(context, p3.x, p3.y);
//    CGContextAddLineToPoint(context, p4.x, p4.y);
//    CGContextClosePath(context);
//    CGContextStrokePath(context);
//
//    UIImage *output = UIGraphicsGetImageFromCurrentImageContext();
//    UIGraphicsEndImageContext();
//    return output;
//}
//
//- (void)dealloc {
//    [[NSNotificationCenter defaultCenter] removeObserver:self];
//}
//
//@end


#import "DebugViewController.h"
#import "CameraManager.h"
#import "DataModel.h"
#import "ImageUtilities.h"

@interface DebugViewController ()
@property (nonatomic, strong) UIImageView *cameraView;
@property (nonatomic, strong) NSArray<NSValue *> *corners;
@end

@implementation DebugViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.cameraView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.cameraView.contentMode = UIViewContentModeScaleAspectFit;
    self.cameraView.clipsToBounds = YES;
    [self.view addSubview:self.cameraView];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateFrame:)
                                                 name:CameraManagerNewFrameNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateCorners:)
                                                 name:ScreenDataProcessorNewCornersNotification
                                               object:nil];
    
    self.corners = [[DataModel shared].screenCorners copy];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateFrame:nil];
}

- (void)updateFrame:(NSNotification *)notification {
    UIImage *latestFrame = notification.userInfo[@"frame"];
    if (!latestFrame) return;
    
    // Draw corners directly (no flip required as CameraManager is now upright)
    UIImage *processedImage = [self drawPolygonOnImage:latestFrame corners:self.corners];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.cameraView.image = processedImage;
    });
}

- (void)updateCorners:(NSNotification *)notification {
    NSArray *corners = notification.userInfo[@"corners"];
    if (!corners) return;
    
    self.corners = [corners copy];
}

- (UIImage *)drawPolygonOnImage:(UIImage *)image corners:(NSArray<NSValue *> *)corners {
    if (!image || corners.count < 4) return image;

    UIGraphicsBeginImageContextWithOptions(image.size, false, 0);
    [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];

    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(context, [UIColor greenColor].CGColor);
    CGContextSetLineWidth(context, 5.0);

    // Direct mapping (No coordinate flipping needed)
    CGPoint p1 = [corners[0] CGPointValue];
    CGPoint p2 = [corners[1] CGPointValue];
    CGPoint p3 = [corners[2] CGPointValue];
    CGPoint p4 = [corners[3] CGPointValue];
    
    CGContextMoveToPoint(   context, p1.x, p1.y);
    CGContextAddLineToPoint(context, p2.x, p2.y);
    CGContextAddLineToPoint(context, p3.x, p3.y);
    CGContextAddLineToPoint(context, p4.x, p4.y);
    CGContextClosePath(context);
    CGContextStrokePath(context);

    UIImage *output = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return output;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
