#import "ImageUtilities.h"
#import <CoreImage/CoreImage.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

// ------------------------------------------------------------------
// OpenCV / C++ Imports & Configuration
// ------------------------------------------------------------------
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#pragma clang diagnostic ignored "-Wquoted-include-in-framework-header"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Fix conflict between OpenCV 'NO' and iOS 'NO'
#ifdef NO
#undef NO
#endif

#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>
#import <opencv2/imgproc/types_c.h>
#pragma clang diagnostic pop

// ------------------------------------------------------------------
// C++ Helper Functions (Internal)
// ------------------------------------------------------------------

cv::Mat loadImageFromAssets(NSString *imageName) {
    UIImage *uiImage = [UIImage imageNamed:imageName];
    if (!uiImage) return cv::Mat();
    cv::Mat cvImage;
    UIImageToMat(uiImage, cvImage);
    if (cvImage.channels() == 4) {
        cv::cvtColor(cvImage, cvImage, cv::COLOR_RGBA2BGR);
    }
    return cvImage;
}

cv::Mat concatImagesHorizontally(cv::Mat img1, cv::Mat img2) {
    if (img1.empty()) return img2;
    if (img2.empty()) return img1;
    
    if (img1.rows != img2.rows) {
        int newHeight = std::min(img1.rows, img2.rows);
        double scale1 = (double)newHeight / img1.rows;
        double scale2 = (double)newHeight / img2.rows;
        cv::resize(img1, img1, cv::Size(img1.cols * scale1, newHeight));
        cv::resize(img2, img2, cv::Size(img2.cols * scale2, newHeight));
    }
    cv::Mat result;
    cv::hconcat(img1, img2, result);
    return result;
}

// ------------------------------------------------------------------
// Implementation
// ------------------------------------------------------------------

@implementation ImageUtilities

// ==================================================================
// 1. SAFETY CORE (Prevents EXC_BAD_ACCESS)
// ==================================================================

+ (UIImage *)safeDeepCopy:(UIImage *)image {
    if (!image) return nil;
    @try {
        // Drawing the image into a new context forces a deep memory copy,
        // detaching it from the volatile camera buffer.
        // Use 'false' instead of 'NO' to avoid C++ conflict.
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale);
        [image drawAtPoint:CGPointZero];
        UIImage *copy = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return copy;
    } @catch (NSException *exception) {
        NSLog(@"[ImageUtilities] Deep Copy Failed: %@", exception);
        return nil;
    }
}

// ==================================================================
// 2. GEOMETRY / CROPPING
// ==================================================================

+ (UIImage *)cropImage:(UIImage *)image toRect:(CGRect)rect {
    if (!image) return nil;
    if (rect.size.width <= 0 || rect.size.height <= 0) return nil;
    
    CGImageRef imageRef = CGImageCreateWithImageInRect(image.CGImage, rect);
    UIImage *result = [UIImage imageWithCGImage:imageRef scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(imageRef);
    return result;
}

+ (NSArray<NSValue *> *)orderPoints:(NSArray<NSValue *> *)points {
    if (points.count != 4) return points;

    NSArray *sortedByY = [points sortedArrayUsingComparator:^NSComparisonResult(NSValue *v1, NSValue *v2) {
        if ([v1 CGPointValue].y < [v2 CGPointValue].y) return NSOrderedAscending;
        return NSOrderedDescending;
    }];

    NSMutableArray *topPoints = [NSMutableArray arrayWithObjects:sortedByY[0], sortedByY[1], nil];
    NSMutableArray *bottomPoints = [NSMutableArray arrayWithObjects:sortedByY[2], sortedByY[3], nil];

    [topPoints sortUsingComparator:^NSComparisonResult(NSValue *v1, NSValue *v2) {
        return [v1 CGPointValue].x < [v2 CGPointValue].x ? NSOrderedAscending : NSOrderedDescending;
    }];

    [bottomPoints sortUsingComparator:^NSComparisonResult(NSValue *v1, NSValue *v2) {
        return [v1 CGPointValue].x < [v2 CGPointValue].x ? NSOrderedAscending : NSOrderedDescending;
    }];

    return @[topPoints[0], topPoints[1], bottomPoints[1], bottomPoints[0]];
}

// ==================================================================
// 3. OPENCV OPERATIONS (Protected)
// ==================================================================

+ (UIImage *)warpPerspective:(UIImage *)inputImage withPoints:(NSArray<NSValue *> *)points {
    if (!inputImage || points.count != 4) return nil;

    // SAFETY CHECK: Deep copy before OpenCV touches it
    UIImage *safeInput = [self safeDeepCopy:inputImage];
    if (!safeInput) return nil;

    try {
        NSArray *ordered = [self orderPoints:points];
        
        std::vector<cv::Point2f> src;
        for (NSValue *val in ordered) {
            CGPoint p = [val CGPointValue];
            src.push_back(cv::Point2f(p.x, p.y));
        }

        float w = 900.0f;
        float h = 500.0f;
        
        std::vector<cv::Point2f> dst;
        dst.push_back(cv::Point2f(0, 0));
        dst.push_back(cv::Point2f(w, 0));
        dst.push_back(cv::Point2f(w, h));
        dst.push_back(cv::Point2f(0, h));

        cv::Mat mat;
        UIImageToMat(safeInput, mat);
        if (mat.empty()) return nil;

        cv::Mat M = cv::getPerspectiveTransform(src, dst);
        cv::Mat warped;
        cv::warpPerspective(mat, warped, M, cv::Size(w, h));

        return MatToUIImage(warped);
    } catch (...) {
        NSLog(@"[ImageUtilities] C++ Exception in warpPerspective");
        return nil;
    }
}

+ (NSArray<NSValue *> *)detectScreenInImage:(UIImage *)inputImage {
    if (!inputImage) return nil;
    
    // SAFETY CHECK: Deep copy is critical here!
    // The camera buffer is volatile; we must detach the image data.
    UIImage *safeInput = [self safeDeepCopy:inputImage];
    if (!safeInput) return nil;

    try {
        cv::Mat img;
        UIImageToMat(safeInput, img);
        if (img.empty()) return nil;

        cv::Mat gray, blur, thresh;
        cv::cvtColor(img, gray, cv::COLOR_BGR2GRAY);
        cv::GaussianBlur(gray, blur, cv::Size(5, 5), 0);
        cv::threshold(blur, thresh, 0, 255, cv::THRESH_BINARY + cv::THRESH_OTSU);

        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(thresh, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

        double maxArea = 0;
        std::vector<cv::Point> bestContour;

        for (const auto &c : contours) {
            double area = cv::contourArea(c);
            if (area > maxArea && area > 5000) {
                double peri = cv::arcLength(c, true);
                std::vector<cv::Point> approx;
                cv::approxPolyDP(c, approx, 0.02 * peri, true);
                
                if (approx.size() == 4) {
                    maxArea = area;
                    bestContour = approx;
                }
            }
        }

        if (bestContour.size() == 4) {
            NSMutableArray *points = [NSMutableArray array];
            for (const auto &p : bestContour) {
                [points addObject:[NSValue valueWithCGPoint:CGPointMake(p.x, p.y)]];
            }
            return points;
        }
    } catch (...) {
        NSLog(@"[ImageUtilities] C++ Exception in detectScreen");
    }
    return nil;
}

+ (UIImage *)processImageForOCR:(UIImage *)inputImage
               regionOfInterest:(CGRect)roi
                      tightCrop:(bool)tightCrop
                  addSuffixHack:(bool)useSuffixHack {
    
    if (!inputImage) return nil;
    
    try {
        cv::Mat mat;
        UIImageToMat(inputImage, mat);
        if (mat.empty()) return inputImage;

        int x = roi.origin.x * mat.cols;
        int y = roi.origin.y * mat.rows;
        int w = roi.size.width * mat.cols;
        int h = roi.size.height * mat.rows;

        x = std::max(0, x);
        y = std::max(0, y);
        w = std::min(mat.cols - x, w);
        h = std::min(mat.rows - y, h);

        if (w <= 0 || h <= 0) return inputImage;

        cv::Rect roiRect(x, y, w, h);
        cv::Mat roiMat = mat(roiRect).clone();

        cv::Mat gray;
        cv::cvtColor(roiMat, gray, cv::COLOR_BGR2GRAY);
        
        cv::Mat normalized;
        cv::normalize(gray, normalized, 0, 255, cv::NORM_MINMAX);
        
        cv::cvtColor(normalized, roiMat, cv::COLOR_GRAY2BGR);

        if (useSuffixHack) {
            static cv::Mat suffixMat;
            if (suffixMat.empty()) {
                suffixMat = loadImageFromAssets(@"decimal-suffix-helper2.png");
            }
            if (!suffixMat.empty()) {
                roiMat = concatImagesHorizontally(roiMat, suffixMat);
            }
        }

        return MatToUIImage(roiMat);
    } catch (...) {
        NSLog(@"[ImageUtilities] Exception in processImageForOCR");
        return inputImage;
    }
}

// ==================================================================
// 4. VISION / COREML
// ==================================================================

+ (NSString *)performOCR:(UIImage *)inputImage
        regionOfInterest:(CGRect)roi
             customWords:(nullable NSArray<NSString *> *)customWords
           addSuffixHack:(bool)useSuffixHack
        recognitionLevel:(VNRequestTextRecognitionLevel)recognitionLevel
          processedImage:(UIImage **)processedResult
                   error:(NSError **)error {
    
    UIImage *safeImage = [self safeDeepCopy:inputImage];
    if (!safeImage) return nil;

    UIImage *preparedImage = [self processImageForOCR:safeImage
                                     regionOfInterest:roi
                                            tightCrop:false
                                        addSuffixHack:useSuffixHack];
    
    if (processedResult) {
        *processedResult = preparedImage;
    }
    
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
    request.recognitionLevel = recognitionLevel;
    request.usesLanguageCorrection = (customWords.count > 0);
    request.customWords = customWords;
    request.recognitionLanguages = @[@"en-US"];
    request.minimumTextHeight = 0.5;
    
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:preparedImage.CGImage options:@{}];
    
    [handler performRequests:@[request] error:error];
    if (error && *error) return nil;
    
    NSMutableString *fullText = [NSMutableString string];
    for (VNRecognizedTextObservation *obs in request.results) {
        NSArray *candidates = [obs topCandidates:1];
        if (candidates.count > 0) {
            VNRecognizedText *top = candidates.firstObject;
            [fullText appendString:top.string];
        }
    }
    
    return [fullText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)runInference:(UIImage *)image
                     model:(VNCoreMLModel *)model
          regionOfInterest:(CGRect)roi
                confidenc:(float *)confidence
            processedImage:(UIImage **)processedResult
                     error:(NSError **)error {
    
    UIImage *safeImage = [self safeDeepCopy:image];
    if (!safeImage) return nil;

    UIImage *cropped = [self processImageForOCR:safeImage
                               regionOfInterest:roi
                                      tightCrop:false
                                  addSuffixHack:false];
    
    if (processedResult) *processedResult = cropped;

    VNCoreMLRequest *request = [[VNCoreMLRequest alloc] initWithModel:model];
    request.imageCropAndScaleOption = VNImageCropAndScaleOptionScaleFill;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cropped.CGImage options:@{}];
    
    BOOL success = [handler performRequests:@[request] error:error];
    if (!success) return nil;

    if (request.results.count > 0) {
        VNObservation *obs = request.results.firstObject;
        if ([obs isKindOfClass:[VNClassificationObservation class]]) {
            VNClassificationObservation *classObs = (VNClassificationObservation *)obs;
            if (confidence) *confidence = classObs.confidence;
            return classObs.identifier;
        }
    }
    return nil;
}

// ==================================================================
// 5. DEBUG DRAWING
// ==================================================================

+ (UIImage *)drawRectangleOnImage:(UIImage *)image rectangle:(CGRect)rect color:(UIColor *)color thickness:(CGFloat)thickness {
    if (!image) return nil;
    
    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale);
    [image drawAtPoint:CGPointZero];
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, thickness);
    CGContextStrokeRect(context, rect);
    
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)drawCircleOnImage:(UIImage *)image center:(CGPoint)center radius:(CGFloat)radius color:(UIColor *)color thickness:(CGFloat)thickness {
    if (!image) return nil;
    
    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale);
    [image drawAtPoint:CGPointZero];
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, thickness);
    
    CGRect circleRect = CGRectMake(center.x - radius, center.y - radius, radius * 2, radius * 2);
    CGContextStrokeEllipseInRect(context, circleRect);
    
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (void)saveImageToDocuments:(UIImage *)image fileName:(NSString *)fileName {
    if (!image || !fileName) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *filePath = [[paths firstObject] stringByAppendingPathComponent:fileName];
        [UIImagePNGRepresentation(image) writeToFile:filePath atomically:YES];
        NSLog(@"[ImageUtilities] Saved debug image: %@", fileName);
    });
}

@end
