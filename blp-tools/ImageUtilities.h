//
//#import <UIKit/UIKit.h>
//#import <CoreML/CoreML.h>
//#import <Vision/Vision.h>
//
//NS_ASSUME_NONNULL_BEGIN
//
//@interface ImageUtilities : NSObject
//
//+ (NSArray<NSValue *> *)orderPoints:(NSArray<NSValue *> *)points;
//
//// Perspective Warp
//+ (UIImage *)warpPerspective:(UIImage *)inputImage
//                  withPoints:(NSArray<NSValue *> *)points;
//
//// Crop
//+ (UIImage *)cropImage:(UIImage *)inputImage toRect:(CGRect)rect;
//
//// OCR
//+ (NSString *)performOCR:(UIImage *)inputImage
//        regionOfInterest:(CGRect)roi
//             customWords:(nullable NSArray<NSString *> *)customWords
//           addSuffixHack:(bool)useSuffixHack
//        recognitionLevel:(VNRequestTextRecognitionLevel)recognitionLevel
//          processedImage:(UIImage **)processedImage
//                   error:(NSError **)error;
//
//// Grayscale Conversion
//+ (UIImage *)convertToGrayscale:(UIImage *)inputImage;
//
//// Draw Rectangle
//+ (UIImage *)drawRectangleOnImage:(UIImage *)inputImage
//                        rectangle:(CGRect)rectangle
//                            color:(UIColor *)color
//                        thickness:(CGFloat)thickness;
//
//// Draw Circle
//+ (UIImage *)drawCircleOnImage:(UIImage *)inputImage
//                        center:(CGPoint)center
//                        radius:(CGFloat)radius
//                         color:(UIColor *)color
//                     thickness:(CGFloat)thickness;
//
//+ (NSString *)saveImageOnDevice:(UIImage *)image
//               withName:(NSString *)name;
//
//
//+ (void)saveImageToDocuments:(UIImage *)image
//                    fileName:(NSString *)fileName;
//
//// Detect Screen (Custom Algorithm)
//+ (NSArray<NSValue *> *)detectScreenInImage:(UIImage *)inputImage;
//
//
//+ (NSString*)runInference:(UIImage *)image
//                    model:(VNCoreMLModel*) model
//         regionOfInterest:(CGRect)roi
//                confidenc:(float*)confidence
//           processedImage:(UIImage **)processedImage
//                    error:(NSError **)error;
//
//@end
//NS_ASSUME_NONNULL_END    // <--- ADD THIS AT THE BOTTOM
//
//


#import <UIKit/UIKit.h>
#import <CoreML/CoreML.h>
#import <Vision/Vision.h>

NS_ASSUME_NONNULL_BEGIN

@interface ImageUtilities : NSObject

+ (NSArray<NSValue *> *)orderPoints:(NSArray<NSValue *> *)points;

// Perspective Warp
+ (UIImage *)warpPerspective:(UIImage *)inputImage
                  withPoints:(NSArray<NSValue *> *)points;

// Crop
+ (UIImage *)cropImage:(UIImage *)inputImage toRect:(CGRect)rect;

// OCR - FIXED POINTERS
+ (NSString *)performOCR:(UIImage *)inputImage
        regionOfInterest:(CGRect)roi
             customWords:(nullable NSArray<NSString *> *)customWords
           addSuffixHack:(bool)useSuffixHack
        recognitionLevel:(VNRequestTextRecognitionLevel)recognitionLevel
          processedImage:(UIImage * _Nullable * _Nullable)processedImage
                   error:(NSError * _Nullable * _Nullable)error;

// Grayscale Conversion
+ (UIImage *)convertToGrayscale:(UIImage *)inputImage;

// Draw Rectangle
+ (UIImage *)drawRectangleOnImage:(UIImage *)inputImage
                        rectangle:(CGRect)rectangle
                            color:(UIColor *)color
                        thickness:(CGFloat)thickness;

// Draw Circle
+ (UIImage *)drawCircleOnImage:(UIImage *)inputImage
                        center:(CGPoint)center
                        radius:(CGFloat)radius
                         color:(UIColor *)color
                     thickness:(CGFloat)thickness;

+ (NSString *)saveImageOnDevice:(UIImage *)image
               withName:(NSString *)name;


+ (void)saveImageToDocuments:(UIImage *)image
                    fileName:(NSString *)fileName;

// Detect Screen (Custom Algorithm)
+ (NSArray<NSValue *> *)detectScreenInImage:(UIImage *)inputImage;

// Inference - FIXED POINTERS
+ (NSString*)runInference:(UIImage *)image
                    model:(VNCoreMLModel*) model
         regionOfInterest:(CGRect)roi
                confidenc:(float * _Nullable)confidence
           processedImage:(UIImage * _Nullable * _Nullable)processedImage
                    error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
