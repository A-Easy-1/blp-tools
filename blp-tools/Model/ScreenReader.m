#import "ScreenReader.h"
#import "ImageUtilities.h"
#import <Vision/Vision.h>
#import "ModelManager.h"

@interface ScreenReader ()
@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *configItems;
@property (nonatomic, strong, readonly) NSString *configType;
@end

@implementation ScreenReader

// MARK: - Initializer
- (instancetype)initWithJSONFile:(NSString *)filePath
                            type:(NSString *)configType
                           error:(NSError **)error {
    self = [super init];
    if (self) {
        if (!filePath) {
            NSString *msg = [NSString stringWithFormat:@"[ScreenReader] ERROR: JSON file path is nil. Check Copy Bundle Resources for type: %@", configType];
            NSLog(@"%@", msg);
            if (error) *error = [NSError errorWithDomain:@"ScreenReaderError" code:404 userInfo:@{NSLocalizedDescriptionKey: msg}];
            return nil;
        }

        BOOL success = [self loadConfigFromFile:filePath type:configType error:error];
        if (!success) {
            NSLog(@"[ScreenReader] Failed to load config for type: %@", configType);
            return nil;
        }
    }
    return self;
}

// MARK: - Load Config
- (BOOL)loadConfigFromFile:(NSString *)filePath
                      type:(NSString *)configType
                     error:(NSError **)error {
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) return NO;

    NSData *jsonData = [NSData dataWithContentsOfFile:filePath options:0 error:error];
    if (!jsonData) return NO;
    
    id parsed = [NSJSONSerialization JSONObjectWithData:jsonData
                                                options:NSJSONReadingMutableContainers
                                                  error:error];
    if (!parsed || ![parsed isKindOfClass:[NSArray class]]) return NO;
    
    _configItems = (NSArray<NSDictionary *> *)parsed;
    _configType = configType;
    
    return YES;
}

// MARK: - Run OCR
- (NSDictionary<NSString *, NSString *> *)runOCROnImage:(UIImage *)image
                                                  error:(NSError **)error
{
    if (!image) return @{};

    NSMutableDictionary<NSString *, NSString *> *results = [NSMutableDictionary dictionary];
    if (self.configType) results[@"type"] = self.configType;
    
    for (NSDictionary *item in self.configItems) {
        NSString *name = item[@"name"];
        NSArray *rectArray = item[@"rect"];
        NSArray<NSString *> *customFormat = item[@"format"];
        NSString *modelName = item[@"model"];
        
        if (!name || !rectArray || rectArray.count < 4) continue;
        
        CGFloat x = [rectArray[0] floatValue];
        CGFloat y = [rectArray[1] floatValue];
        CGFloat w = [rectArray[2] floatValue];
        CGFloat h = [rectArray[3] floatValue];
        
        // --- FIX: CASE-INSENSITIVE CHECK & CONTROLLED EXPANSION ---
        // Previous bug: "total-spin" (lowercase) was failing the "Spin" (uppercase) check.
        // We now use localizedCaseInsensitiveContainsString.
        
        if ([name localizedCaseInsensitiveContainsString:@"spin"] &&
            ![name localizedCaseInsensitiveContainsString:@"axis"]) {
            
            // Logic: High spin (10,000+) grows significantly to the Left.
            // Shift Left: 15% of screen width (~135px) to catch leading digits.
            // Expand Right: 5% of screen width to allow slight growth without hitting "Spin Axis".
            
            CGFloat shiftLeft = 0.15;
            CGFloat expandRight = 0.05;
            
            x = fmax(0.0, x - shiftLeft);
            w = w + shiftLeft + expandRight;
        }
        
        CGRect roi = CGRectMake(x, y, w, h);
        UIImage* processedImage = nil;
        
        if(modelName == nil) { // Standard OCR
            NSString *recognized = [ImageUtilities performOCR:image
                                             regionOfInterest:roi
                                                  customWords:customFormat
                                                addSuffixHack:false
                                              recognitionLevel:VNRequestTextRecognitionLevelAccurate
                                               processedImage:&processedImage
                                                        error:error];
            
            // --- DEBUG: SAVING DISABLED ---
            // kept commented out to reduce noise as requested
            /*
            if (processedImage) {
                NSString *debugName = [NSString stringWithFormat:@"debug_roi_%@_%@.png", name, [NSUUID UUID].UUIDString];
                [ImageUtilities saveImageToDocuments:processedImage fileName:debugName];
            }
            */
            // -----------------------------
            
            if (error && *error) return nil;
            
            NSCharacterSet *whitespaceSet = [NSCharacterSet characterSetWithCharactersInString:@"\n\t '"];
            NSString *cleanText = [[recognized componentsSeparatedByCharactersInSet:whitespaceSet] componentsJoinedByString:@""];
            if (!cleanText) cleanText = @"";
            
            if ([cleanText isEqualToString:@""] || [cleanText isEqualToString:@"6"] || [cleanText isEqualToString:@"9"]) {
                recognized = [ImageUtilities performOCR:image
                                       regionOfInterest:roi
                                            customWords:customFormat
                                          addSuffixHack:true
                                       recognitionLevel:VNRequestTextRecognitionLevelAccurate
                                         processedImage:&processedImage
                                                  error:error];
                cleanText = [[recognized componentsSeparatedByCharactersInSet:whitespaceSet] componentsJoinedByString:@""];
                if (!cleanText) cleanText = @"";
                
                if ([cleanText hasSuffix:@"0.5"]) {
                    if (cleanText.length > 3) cleanText = [cleanText substringToIndex:cleanText.length - 3];
                }
                if ([cleanText hasPrefix:@"0.5"]) {
                    if (cleanText.length > 3) cleanText = [cleanText substringFromIndex:3];
                }
            }
            results[name] = cleanText;
            
        } else {
            // CoreML (Unchanged)
            VNCoreMLModel *model = [[ModelManager shared] modelWithName:modelName];
            if (!model) { results[name] = @""; continue; }
            
            float confidence = 0.0f;
            NSString *recognized = [ImageUtilities runInference:image
                                                          model:model
                                               regionOfInterest:roi
                                                      confidenc:&confidence
                                                 processedImage:&processedImage
                                                          error:error];
            results[name] = recognized ?: @"";
        }
    }
    return [results copy];
}

@end
