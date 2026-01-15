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
        // SAFETY CHECK: If the file path is nil (file missing in bundle), fail gracefully.
        if (!filePath) {
            NSString *msg = [NSString stringWithFormat:@"[ScreenReader] ERROR: JSON file path is nil. Check Copy Bundle Resources for type: %@", configType];
            NSLog(@"%@", msg);
            if (error) {
                *error = [NSError errorWithDomain:@"ScreenReaderError" code:404 userInfo:@{NSLocalizedDescriptionKey: msg}];
            }
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
    
    // 1. Double check path existence
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ScreenReaderError" code:404 userInfo:@{NSLocalizedDescriptionKey: @"File does not exist at path"}];
        }
        return NO;
    }

    // 2. Read raw data
    NSData *jsonData = [NSData dataWithContentsOfFile:filePath options:0 error:error];
    if (!jsonData) {
        return NO;
    }
    
    // 3. Parse JSON
    id parsed = [NSJSONSerialization JSONObjectWithData:jsonData
                                                options:NSJSONReadingMutableContainers
                                                  error:error];
    if (!parsed || ![parsed isKindOfClass:[NSArray class]]) {
        NSLog(@"[ScreenReader] JSON format invalid (expected Array) for %@", configType);
        return NO;
    }
    
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
    
    if (self.configType) {
        results[@"type"] = self.configType;
    }
    
    for (NSDictionary *item in self.configItems) {
        NSString *name = item[@"name"];
        NSArray *rectArray = item[@"rect"];
        NSArray<NSString *> *customFormat = item[@"format"];
        NSString *modelName = item[@"model"];
        
        if (!name || !rectArray || rectArray.count < 4) {
            continue;
        }
        
        // rect is [x, y, w, h] in normalized coords (0..1)
        CGFloat x = [rectArray[0] floatValue];
        CGFloat y = [rectArray[1] floatValue];
        CGFloat w = [rectArray[2] floatValue];
        CGFloat h = [rectArray[3] floatValue];
        
        CGRect roi = CGRectMake(x, y, w, h);
        
        UIImage* processedImage = nil;
        
        if(modelName == nil) { // Use standard OCR
            
            NSString *recognized = [ImageUtilities performOCR:image
                                             regionOfInterest:roi
                                                  customWords:customFormat
                                                addSuffixHack:false
                                              recognitionLevel:VNRequestTextRecognitionLevelAccurate
                                               processedImage:&processedImage
                                                        error:error];
            
            if (error && *error) return nil;
            
            NSCharacterSet *whitespaceSet = [NSCharacterSet characterSetWithCharactersInString:@"\n\t '"];
            NSString *cleanText = [[recognized componentsSeparatedByCharactersInSet:whitespaceSet] componentsJoinedByString:@""];
            
            if (!cleanText) cleanText = @"";
            
            // Retry logic for difficult numbers
            if ([cleanText isEqualToString:@""] || [cleanText isEqualToString:@"6"] || [cleanText isEqualToString:@"9"]) {
                recognized = [ImageUtilities performOCR:image
                                       regionOfInterest:roi
                                            customWords:customFormat
                                          addSuffixHack:true
                                       recognitionLevel:VNRequestTextRecognitionLevelAccurate
                                         processedImage:&processedImage
                                                  error:error];
                if (error && *error) return nil;
                
                cleanText = [[recognized componentsSeparatedByCharactersInSet:whitespaceSet] componentsJoinedByString:@""];
                if (!cleanText) cleanText = @"";
                
                // Strip suffix artifacts if present
                if ([cleanText hasSuffix:@"0.5"]) {
                    if (cleanText.length > 3) cleanText = [cleanText substringToIndex:cleanText.length - 3];
                }
                if ([cleanText hasPrefix:@"0.5"]) {
                    if (cleanText.length > 3) cleanText = [cleanText substringFromIndex:3];
                }
            }
            
            results[name] = cleanText;
            
        } else {
            // Use CoreML Model
            VNCoreMLModel *model = [[ModelManager shared] modelWithName:modelName];
            if (!model) {
                // Log but don't crash
                // NSLog(@"Model not found: %@", modelName);
                results[name] = @"";
                continue;
            }
            
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
