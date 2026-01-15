#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "ScreenReader.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ScreenDataProcessorNewCornersNotification;
extern NSString * const ScreenDataProcessorNewBallDataNotification;
extern NSString * const ScreenDataProcessorNewClubDataNotification;

@interface ScreenDataProcessor : NSObject

@property (nonatomic, strong) ScreenReader *screenSelectionReader;
@property (nonatomic, strong) ScreenReader *ballDataReader;
@property (nonatomic, strong) ScreenReader *clubDataReader;

- (void)processScreenDataFromImage:(UIImage *)rawImage
                             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
