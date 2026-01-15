
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const GSProConnectionStateNotification; // Notification name

@interface GSProConnector : NSObject <NSStreamDelegate>

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL isConnected;

- (void)connectToServerWithIP:(NSString *)ip port:(NSInteger)port;
- (void)disconnect;
- (BOOL)isConnected;
- (void)sendShotWithBallData:(NSDictionary * _Nullable)ballData
                    clubData:(NSDictionary * _Nullable)clubData
                  shotNumber:(int)shotNumber;
- (NSString *)getConnectionState; 

@end

NS_ASSUME_NONNULL_END
