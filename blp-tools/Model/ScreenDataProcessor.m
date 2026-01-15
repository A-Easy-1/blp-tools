#import "ScreenDataProcessor.h"
#import "ImageUtilities.h"
#import "SettingsManager.h"
#import "NSubmissionValidator.h"
#import "TrajectoryEstimator.h"
#import "Constants.h"
#import <math.h>

// NOTE: Connectors removed. This class only READS data. DataModel handles SENDING data.

NSString * const ScreenDataProcessorNewCornersNotification = @"ScreenDataProcessorNewCornersNotification";
NSString * const ScreenDataProcessorNewBallDataNotification = @"ScreenDataProcessorNewBallDataNotification";
NSString * const ScreenDataProcessorNewClubDataNotification = @"ScreenDataProcessorNewClubDataNotification";

static double toDouble(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value doubleValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [value doubleValue];
    }
    return 0.0;
}

static int toInt(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value intValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [value intValue];
    }
    return 0;
}

static NSString* validateBallData(NSDictionary *data) {
    NSSet *validSpeedUnits = [NSSet setWithObjects:@"MPH", @"MPS", @"KMH", nil];
    NSSet *validCarryUnits = [NSSet setWithObjects:@"YDS", @"METERS", nil];
    NSSet *validDirection = [NSSet setWithObjects:@"L", @"R", nil];
    
    double ballSpeed = toDouble(data[@"ball-speed"]);
    NSString *ballSpeedUnits = [validSpeedUnits containsObject:data[@"ball-speed-units"]] ? data[@"ball-speed-units"] : @"";
    // double vla = toDouble(data[@"vla"]); // unused local var
    NSString *hlaDirection = [validDirection containsObject:data[@"hla-direction"]] ? data[@"hla-direction"] : @"";
    NSString *carryUnits = [validCarryUnits containsObject:data[@"carry-units"]] ? data[@"carry-units"] : @"";
    int totalSpin = toInt(data[@"total-spin"]);
    int spinAxis = toInt(data[@"spin-axis"]);
    
    // Top level validation logic
    if(ballSpeed == 0)
        return [NSString stringWithFormat:@"invalid: ball-speed = %@", data[@"ball-speed"]];
    if([ballSpeedUnits isEqualToString:@""])
        return [NSString stringWithFormat:@"invalid: ball-speed-units = %@", data[@"ball-speed-units"]];
    if([hlaDirection isEqualToString:@""])
        return [NSString stringWithFormat:@"invalid: hla-direction = %@", data[@"hla-direction"]];
    if([carryUnits isEqualToString:@""])
        return [NSString stringWithFormat:@"invalid: carry-units = %@", data[@"carry-units"]];
    
    if (toInt(data[@"carry"]) == 0 && totalSpin == 0) {
        return @"putt";
    }
    
    if (toInt(data[@"carry"]) != 0 || totalSpin != 0 || spinAxis != 0) {
        return @"shot";
    }
    
    return @"invalid: not putt or shot";
}

static NSString* validateClubData(NSDictionary *data) {
    // Currently permissive validation for club data
    return @"club";
}

static NSDictionary* translateBallResults(NSDictionary* ballResults, bool isPutt) {
    if (!ballResults) return @{};

    NSMutableDictionary *processedResults = [NSMutableDictionary dictionary];

    float ballSpeed = [ballResults[@"ball-speed"] floatValue];
    processedResults[@"Speed"] = @(ballSpeed);
    
    float vla = [ballResults[@"vla"] floatValue];
    processedResults[@"VLA"] = @(vla);
    
    NSString *hlaDirection = ballResults[@"hla-direction"] ?: @"";
    float hla = [ballResults[@"hla"] floatValue];
    if ([@"L" isEqualToString:hlaDirection]) {
        hla *= -1.0;
    } else if (![@"R" isEqualToString:hlaDirection]) {
        NSLog(@"Warning: Unexpected hla-direction value: '%@'", hlaDirection);
    }
    processedResults[@"HLA"] = @(hla);
    
    float carryDistance = [ballResults[@"carry"] floatValue];
    processedResults[@"CarryDistance"] = @(carryDistance);
    
    float totalSpin = [ballResults[@"total-spin"] floatValue];
    processedResults[@"TotalSpin"] = @(totalSpin);
    
    NSString *spinAxisDirection = ballResults[@"spin-axis-direction"] ?: @"";
    float spinAxis = [ballResults[@"spin-axis"] floatValue];
    if ([@"L" isEqualToString:spinAxisDirection]) {
        spinAxis *= -1.0;
    } else if (![@"R" isEqualToString:spinAxisDirection]) {
        NSLog(@"Warning: Unexpected spin-axis-direction value: '%@'", spinAxisDirection);
    }
    processedResults[@"SpinAxis"] = @(spinAxis);
    
    // Populate total distance and offline amounts using Estimator
    processedResults[@"IsPutt"] = @(isPutt);
    [[TrajectoryEstimator shared] processBallData:processedResults];
    
    return [processedResults copy];
}

static NSDictionary* translateClubResults(NSDictionary* clubResults) {
    if (!clubResults) return @{};
    
    NSMutableDictionary *processedResults = [NSMutableDictionary dictionary];

    processedResults[@"Speed"] = @([clubResults[@"club-speed"] floatValue]);

    NSString *aoaDirection = clubResults[@"aoa-direction"] ?: @"";
    float aoa = [clubResults[@"aoa"] floatValue];
    if ([@"DOWN" isEqualToString:aoaDirection]) {
        aoa *= -1.0;
    } else if (![@"UP" isEqualToString:aoaDirection]) {
        NSLog(@"Warning: Unexpected aoa-direction value: '%@'", aoaDirection);
    }
    processedResults[@"AngleOfAttack"] = @(aoa);

    NSString *pathDirection = clubResults[@"path-direction"] ?: @"";
    float path = [clubResults[@"path"] floatValue];
    if ([@"IN-OUT" isEqualToString:pathDirection]) {
        path *= -1.0;
    } else if (![@"OUT-IN" isEqualToString:pathDirection]) {
        NSLog(@"Warning: Unexpected path-direction value: '%@'", pathDirection);
    }
    processedResults[@"Path"] = @(path);
    
    processedResults[@"Efficiency"] = @([clubResults[@"efficiency"] floatValue]);
    
    // Placeholders for data not currently read by OCR
    processedResults[@"FaceToTarget"] = @0.0;
    processedResults[@"Lie"] = @0.0;
    processedResults[@"Loft"] = @0.0;
    processedResults[@"SpeedAtImpact"] = @0.0;
    processedResults[@"VerticalFaceImpact"] = @0.0;
    processedResults[@"ClosureRate"] = @0.0;
    processedResults[@"HorizontalFaceImpact"] = @0.0;

    return [processedResults copy];
}


// --- CLASS EXTENSION / PRIVATE INTERFACE ---
@interface ScreenDataProcessor ()

@property (nonatomic, assign) NSTimeInterval lastDetectionTime;
@property (nonatomic, strong) NSArray<NSValue *> *detectedCorners;
@property (nonatomic, strong) NSDictionary* lastBallData;
@property (nonatomic, strong) NSDictionary* lastClubData;

@property (nonatomic, assign) NSTimeInterval lastClubDetectionTime;

@property (nonatomic, strong) NSubmissionValidator* ballDataValidator;
@property (nonatomic, strong) NSubmissionValidator* clubDataValidator;

@property (nonatomic, assign) NSTimeInterval lastOCRTime;

@end
// -------------------------------------------


@implementation ScreenDataProcessor

- (instancetype)init {
    self = [super init];
    if (self) {
        NSError *error = nil;
        
        NSString *ballPath = [[NSBundle mainBundle] pathForResource:@"annotations-ball" ofType:@"json"];
        _ballDataReader = [[ScreenReader alloc] initWithJSONFile:ballPath type:@"ball-data" error:&error];
        if (error) NSLog(@"Error loading ballDataReader: %@", error);
        
        NSString *clubPath = [[NSBundle mainBundle] pathForResource:@"annotations-club" ofType:@"json"];
        _clubDataReader = [[ScreenReader alloc] initWithJSONFile:clubPath type:@"club-data" error:&error];
        if (error) NSLog(@"Error loading clubDataReader: %@", error);
        
        NSString *screenPath = [[NSBundle mainBundle] pathForResource:@"annotations-screen" ofType:@"json"];
        _screenSelectionReader = [[ScreenReader alloc] initWithJSONFile:screenPath type:@"screen-data" error:&error];
        if (error) NSLog(@"Error loading screenSelectionReader: %@", error);
        
        _lastDetectionTime = 0;
        _lastClubDetectionTime = 0;
        _lastBallData = nil;
        _lastClubData = nil;
        
        _ballDataValidator = [[NSubmissionValidator alloc] initWithRequiredCount:NUM_CONSISTENCY_CHECKS];
        _clubDataValidator = [[NSubmissionValidator alloc] initWithRequiredCount:NUM_CONSISTENCY_CHECKS];
    }
    return self;
}

- (void)processScreenDataFromImage:(UIImage *)rawImage error:(NSError **)error {
    
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    // --- 1. DYNAMIC EFFICIENCY CONTROL ---
    double fps = [[NSUserDefaults standardUserDefaults] doubleForKey:@"camera_fps"];
    if (fps < 2.0) fps = 2.0;
    
    double throttleInterval = 1.0 / fps;
    
    if (currentTime - self.lastOCRTime < throttleInterval) {
        return; // Too soon! Skip this frame to save CPU.
    }
    self.lastOCRTime = currentTime;
    
    // --- 2. INTELLIGENT DETECTION (The "Gatekeeper") ---
    // If we don't have corners, or it's been > 5 seconds, try to find them.
    if (!self.detectedCorners || (currentTime - self.lastDetectionTime) >= 5.0) {
        
        NSArray<NSValue *> *foundCorners = [ImageUtilities detectScreenInImage:rawImage];
        
        if (foundCorners && foundCorners.count == 4) {
            // Success: We found a screen. Lock it in.
            self.detectedCorners = [foundCorners copy];
            self.lastDetectionTime = currentTime;
            
            // Notify UI to draw the green box
            [[NSNotificationCenter defaultCenter] postNotificationName:ScreenDataProcessorNewCornersNotification
                                                                object:nil
                                                              userInfo:@{@"corners": self.detectedCorners}];
        } else {
            // Failure: Screen is blocked or camera moved.
            self.detectedCorners = nil;
            
            // Notify UI to hide the green box
             [[NSNotificationCenter defaultCenter] postNotificationName:ScreenDataProcessorNewCornersNotification
                                                                 object:nil
                                                               userInfo:@{}];
        }
    }
    
    // --- 3. THE STOP SIGN ---
    if (!self.detectedCorners) {
        return;
    }
    
    // 2. Warp Image
    UIImage *warpedImage = [ImageUtilities warpPerspective:rawImage withPoints:self.detectedCorners];
    if (!warpedImage) {
        if (error) {
            *error = [NSError errorWithDomain:@"ScreenDataProcessorErrorDomain"
                                         code:101
                                     userInfo:@{NSLocalizedDescriptionKey: @"Warping image failed"}];
        }
        return;
    }
    
    // 3. Determine Screen Type (Ball vs Club)
    NSDictionary *selectionResults = [self.screenSelectionReader runOCROnImage:warpedImage error:error];
    if (error && *error) return;
    
    NSString *ballPattern = selectionResults[@"ball-screen-pattern"] ?: @"";
    NSString *clubPattern = selectionResults[@"club-screen-pattern"] ?: @"";
    
    bool ballScreenDetected = [ballPattern isEqualToString:@"SPEED"];
    bool clubScreenDetected = [clubPattern isEqualToString:@"SPEED"];
    
    // CASE A: BALL SCREEN DETECTED
    if (ballScreenDetected && !clubScreenDetected) {
        NSDictionary *result = [self.ballDataReader runOCROnImage:warpedImage error:error];
        if (error && *error) return;
        
        NSString* kind = validateBallData(result);
        
        if(![kind isEqualToString:@"shot"] && ![kind isEqualToString:@"putt"] ) {
             // NSLog(@"Invalid shot detected: %@ \n %@", kind, result);
             return;
        }
        
        bool isPutt = [kind isEqualToString:@"putt"];
        NSDictionary* translatedResults = translateBallResults(result, isPutt);
        
        if([self.ballDataValidator validateDictionary:translatedResults]) {
            
            NSDictionary *userInfo = @{@"image": warpedImage, @"data": translatedResults};
            [[NSNotificationCenter defaultCenter] postNotificationName:ScreenDataProcessorNewBallDataNotification
                                                                object:nil
                                                              userInfo:userInfo];
            
            self.lastBallData = [translatedResults copy];
        }
    }
    // CASE B: CLUB SCREEN DETECTED
    else if (!ballScreenDetected && clubScreenDetected) {
        NSDictionary *result = [self.clubDataReader runOCROnImage:warpedImage error:error];
        if (error && *error) return;
        
        NSString* kind = validateClubData(result);
        if([kind isEqualToString:@"invalid"]) {
            // NSLog(@"Invalid club data detected: %@ \n %@", kind, result);
            return;
        }
        
        NSDictionary* translatedResults = translateClubResults(result);
    
        if([self.clubDataValidator validateDictionary:translatedResults]) {
            self.lastClubData = [translatedResults copy];
            self.lastClubDetectionTime = currentTime;
            
            NSDictionary *userInfo = @{@"image": warpedImage, @"data": translatedResults};
            [[NSNotificationCenter defaultCenter] postNotificationName:ScreenDataProcessorNewClubDataNotification
                                                                object:nil
                                                              userInfo:userInfo];
        }
    }
}

@end
