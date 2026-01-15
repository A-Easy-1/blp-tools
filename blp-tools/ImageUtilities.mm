#import "ImageUtilities.h"
#import <CoreImage/CoreImage.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#pragma clang diagnostic ignored "-Wquoted-include-in-framework-header"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wnullability-completeness"
#undef NO //Conflicts with opencv c++ defines
#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>
#import <opencv2/imgproc/types_c.h>
#pragma clang diagnostic pop

// ------------------------------------------------------------------
// C++ Helper Functions
// ------------------------------------------------------------------

cv::Mat loadImageFromAssets(NSString *imageName) {
    UIImage *uiImage = [UIImage imageNamed:imageName];
    if (!uiImage) {
        NSLog(@"Failed to load image from assets: %@", imageName);
        return cv::Mat();
    }
    cv::Mat cvImage;
    UIImageToMat(uiImage, cvImage);
    cv::cvtColor(cvImage, cvImage, cv::COLOR_RGBA2BGR);
    return cvImage;
}

cv::Mat concatImagesHorizontally(cv::Mat img1, cv::Mat img2) {
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

// --- CRASH FIX: Safe Deep Copy ---
// Prevents EXC_BAD_ACCESS by detaching image from camera buffer
+ (UIImage *)safeDeepCopy:(UIImage *)image {
    if (!image) return nil;
    // Use 'false' for opaque because NO is undefined in Obj-C++
    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale);
    [image drawAtPoint:CGPointZero];
    UIImage *copy = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return copy;
}

// Robust Point Ordering (Y-sort then X-sort)
+ (NSArray<NSValue *> *)orderPoints:(NSArray<NSValue *> *)points {
    if (points.count != 4) {
        NSLog(@"Error: Exactly 4 points are required for ordering.");
        return nil;
    }

    // 1. Sort by Y (Top vs Bottom)
    NSArray *sortedByY = [points sortedArrayUsingComparator:^NSComparisonResult(NSValue *v1, NSValue *v2) {
        if ([v1 CGPointValue].y < [v2 CGPointValue].y) return NSOrderedAscending;
        return NSOrderedDescending;
    }];

    NSMutableArray *topPoints = [NSMutableArray arrayWithObjects:sortedByY[0], sortedByY[1], nil];
    NSMutableArray *bottomPoints = [NSMutableArray arrayWithObjects:sortedByY[2], sortedByY[3], nil];

    // 2. Sort Top by X (Left vs Right)
    [topPoints sortUsingComparator:^NSComparisonResult(NSValue *v1, NSValue *v2) {
        return [v1 CGPointValue].x < [v2 CGPointValue].x ? NSOrderedAscending : NSOrderedDescending;
    }];

    // 3. Sort Bottom by X (Left vs Right)
    [bottomPoints sortUsingComparator:^NSComparisonResult(NSValue *v1, NSValue *v2) {
        return [v1 CGPointValue].x < [v2 CGPointValue].x ? NSOrderedAscending : NSOrderedDescending;
    }];

    return @[topPoints[0], topPoints[1], bottomPoints[1], bottomPoints[0]]; // TL, TR, BR, BL
}

#pragma mark - Perspective Warp

+ (UIImage *)warpPerspective:(UIImage *)inputImage withPoints:(NSArray<NSValue *> *)points {
    if (points.count != 4) return nil;
    
    NSArray<NSValue *> *orderedPointsNS = [ImageUtilities orderPoints:points];
    
    std::vector<cv::Point2f> orderedPoints;
    for (NSValue *value in orderedPointsNS) {
        CGPoint cgPoint = [value CGPointValue];
        orderedPoints.push_back(cv::Point2f(cgPoint.x, cgPoint.y));
    }

    float width = 900.0;
    float height = 450.0;
    std::vector<cv::Point2f> dstPoints = {
        cv::Point2f(0, 0), cv::Point2f(width, 0), cv::Point2f(width, height), cv::Point2f(0, height)
    };

    cv::Mat transformMatrix = cv::getPerspectiveTransform(orderedPoints, dstPoints);
    
    cv::Mat inputMat;
    UIImageToMat(inputImage, inputMat);
    if (inputMat.empty()) return nil;

    cv::Mat warpedMat;
    cv::warpPerspective(inputMat, warpedMat, transformMatrix, cv::Size(width, height));

    return MatToUIImage(warpedMat);
}

#pragma mark - Crop & Save

+ (UIImage *)cropImage:(UIImage *)inputImage toRect:(CGRect)rect {
    CGImageRef croppedImageRef = CGImageCreateWithImageInRect(inputImage.CGImage, rect);
    UIImage *croppedImage = [UIImage imageWithCGImage:croppedImageRef];
    CGImageRelease(croppedImageRef);
    return croppedImage;
}

+ (void)saveImageToDocuments:(UIImage *)image fileName:(NSString *)fileName {
    if (!image) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSData *imageData = UIImagePNGRepresentation(image);
        NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *filePath = [documentsPath stringByAppendingPathComponent:fileName];
        [imageData writeToFile:filePath atomically:YES];
    });
}

#pragma mark - Image Processing (OpenCV)

+ (UIImage *)processImageForOCR:(UIImage *)inputImage
               regionOfInterest:(CGRect)roi
                      tightCrop:(bool)tightCrop
                  addSuffixHack:(bool)useSuffixHack
{
    cv::Mat matImage;
    UIImageToMat(inputImage, matImage);
    if (matImage.empty()) return inputImage;

    cv::Rect roiRect(roi.origin.x * matImage.cols,
                     roi.origin.y * matImage.rows,
                     roi.size.width * matImage.cols,
                     roi.size.height * matImage.rows);
    
    // Safety Bounds
    roiRect.x = std::max(0, roiRect.x);
    roiRect.y = std::max(0, roiRect.y);
    roiRect.width = std::min(matImage.cols - roiRect.x, roiRect.width);
    roiRect.height = std::min(matImage.rows - roiRect.y, roiRect.height);
    
    if (roiRect.width <= 0 || roiRect.height <= 0) return inputImage;
    
    cv::Mat roiMat = matImage(roiRect);
    cv::Mat grayMat;
    cv::cvtColor(roiMat, grayMat, cv::COLOR_BGR2GRAY);

    cv::Mat normalizedMat;
    cv::normalize(grayMat, normalizedMat, 0, 255, cv::NORM_MINMAX);

    // Tight Crop Logic
    if(tightCrop) {
        cv::Mat thresholdMat;
        cv::threshold(normalizedMat, thresholdMat, 75, 255, cv::THRESH_BINARY);
        cv::Mat invertedMat;
        cv::bitwise_not(thresholdMat, invertedMat);
        
        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(invertedMat, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

        if (!contours.empty()) {
            double largestArea = 0.0;
            int largestContourIndex = 0;
            for (size_t i = 0; i < contours.size(); i++) {
                double area = cv::contourArea(contours[i]);
                if (area > largestArea) {
                    largestArea = area;
                    largestContourIndex = i;
                }
            }
            cv::Rect boundingBox = cv::boundingRect(contours[largestContourIndex]);
            
            int margin = 5;
            boundingBox.x = std::max(0, boundingBox.x - margin);
            boundingBox.y = std::max(0, boundingBox.y - margin);
            boundingBox.width = std::min(roiMat.cols - boundingBox.x, boundingBox.width + 2 * margin);
            boundingBox.height = std::min(roiMat.rows - boundingBox.y, boundingBox.height + 2 * margin);
            
            cv::Mat croppedMat = normalizedMat(boundingBox);
            normalizedMat = croppedMat.clone();
        }
    }
    
    cv::cvtColor(normalizedMat, roiMat, cv::COLOR_GRAY2BGR);
    
    if(useSuffixHack) {
        static cv::Mat suffixImage;
        if(suffixImage.empty()) suffixImage = loadImageFromAssets(@"decimal-suffix-helper2.png");
        
        if (!suffixImage.empty()) {
            cv::Mat temp = concatImagesHorizontally(suffixImage, roiMat);
            roiMat = concatImagesHorizontally(temp, suffixImage);
        }
    }
    
    return MatToUIImage(roiMat);
}

#pragma mark - OCR & ML

+ (NSString *)performOCR:(UIImage *)inputImage
        regionOfInterest:(CGRect)roi
             customWords:(nullable NSArray<NSString *> *)customWords
           addSuffixHack:(bool)useSuffixHack
        recognitionLevel:(VNRequestTextRecognitionLevel)recognitionLevel
          processedImage:(UIImage **)processedResult
                   error:(NSError **)error
{
    UIImage* processedImage = [ImageUtilities processImageForOCR:inputImage regionOfInterest:roi tightCrop:false addSuffixHack:useSuffixHack];
    
    // SAFETY: Deep copy
    UIImage *safeImage = [ImageUtilities safeDeepCopy:processedImage];
    if(processedResult) *processedResult = safeImage;
    
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:safeImage.CGImage options:@{}];
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
    request.recognitionLevel = recognitionLevel;
    
    if (customWords.count > 0) {
        request.customWords = customWords;
        request.usesLanguageCorrection = 1;
    } else {
        request.usesLanguageCorrection = 0;
    }
    
    request.minimumTextHeight = 0.5;
    request.recognitionLanguages = @[@"en-US"];
    
    [handler performRequests:@[request] error:error];
    if (*error) return nil;
    
    NSMutableString *recognizedText = [NSMutableString string];
    for (VNRecognizedTextObservation *observation in request.results) {
        [recognizedText appendString:[observation topCandidates:1].firstObject.string];
        [recognizedText appendString:@"\n"];
    }
    
    return [recognizedText copy];
}

+ (NSString*)runInference:(UIImage *)image
                    model:(VNCoreMLModel*) model
         regionOfInterest:(CGRect)roi
                confidenc:(float*)confidence
           processedImage:(UIImage **)processedResult
                    error:(NSError **)error {
    
    UIImage* processedImage = [ImageUtilities processImageForOCR:image regionOfInterest:roi tightCrop:false addSuffixHack:false];
    UIImage *safeImage = [ImageUtilities safeDeepCopy:processedImage];
    
    if(processedResult) *processedResult = safeImage;
    
    VNCoreMLRequest *request = [[VNCoreMLRequest alloc] initWithModel:model];
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:safeImage.CGImage options:@{}];
    BOOL success = [handler performRequests:@[request] error:error];
    
    if ((!success || error) && *error) return nil;

    if (request.results.count > 0) {
        id firstResult = request.results.firstObject;
        if ([firstResult isKindOfClass:[VNClassificationObservation class]]) {
            VNClassificationObservation *topResult = (VNClassificationObservation *)firstResult;
            if (confidence) *confidence = topResult.confidence;
            return topResult.identifier;
        }
    }
    return nil;
}

#pragma mark - Screen Detection

+ (NSArray<NSValue *> *)detectScreenInImage:(UIImage *)inputImage {
    cv::Mat imageMat;
    UIImageToMat(inputImage, imageMat);
    if (imageMat.empty()) return nil;

    cv::Mat grayMat;
    cv::cvtColor(imageMat, grayMat, cv::COLOR_BGR2GRAY);

    cv::Mat normalizedMat;
    cv::normalize(grayMat, normalizedMat, 0, 255, cv::NORM_MINMAX);

    cv::Mat threshMat;
    cv::threshold(normalizedMat, threshMat, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);

    cv::Mat openedMat;
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(11, 11));
    cv::morphologyEx(threshMat, openedMat, cv::MORPH_OPEN, kernel);

    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(openedMat, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

    for (const std::vector<cv::Point> &contour : contours) {
        double epsilon = 0.02 * cv::arcLength(contour, true);
        std::vector<cv::Point> approxPolygon;
        cv::approxPolyDP(contour, approxPolygon, epsilon, true);

        if (approxPolygon.size() == 4) {
            NSMutableArray<NSValue *> *polygonPoints = [NSMutableArray array];
            for (const cv::Point &point : approxPolygon) {
                [polygonPoints addObject:[NSValue valueWithCGPoint:CGPointMake(point.x, point.y)]];
            }
            return polygonPoints;
        }
    }
    return nil;
}

#pragma mark - Restored Drawing Helpers

+ (UIImage *)convertToGrayscale:(UIImage *)inputImage {
    CIImage *ciImage = [[CIImage alloc] initWithImage:inputImage];
    CIFilter *grayscaleFilter = [CIFilter filterWithName:@"CIColorControls"];
    [grayscaleFilter setValue:ciImage forKey:kCIInputImageKey];
    [grayscaleFilter setValue:@0.0 forKey:@"inputSaturation"];
    
    CIImage *outputCIImage = grayscaleFilter.outputImage;
    if (!outputCIImage) return nil;
    
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:outputCIImage fromRect:outputCIImage.extent];
    UIImage *outputImage = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    return outputImage;
}

+ (UIImage *)drawRectangleOnImage:(UIImage *)inputImage
                        rectangle:(CGRect)rectangle
                            color:(UIColor *)color
                        thickness:(CGFloat)thickness {
    // FIX: Use 'false' for C++ compatibility
    UIGraphicsBeginImageContextWithOptions(inputImage.size, false, inputImage.scale);
    [inputImage drawAtPoint:CGPointZero];
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, thickness);
    CGContextStrokeRect(context, rectangle);
    
    UIImage *outputImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return outputImage;
}

+ (UIImage *)drawCircleOnImage:(UIImage *)inputImage
                        center:(CGPoint)center
                        radius:(CGFloat)radius
                         color:(UIColor *)color
                     thickness:(CGFloat)thickness {
    // FIX: Use 'false' for C++ compatibility
    UIGraphicsBeginImageContextWithOptions(inputImage.size, false, inputImage.scale);
    [inputImage drawAtPoint:CGPointZero];
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, thickness);
    CGContextStrokeEllipseInRect(context, CGRectMake(center.x - radius, center.y - radius, radius * 2, radius * 2));
    
    UIImage *outputImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return outputImage;
}

@end
