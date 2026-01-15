#import "MiniGameSettingsStore.h"

@implementation MiniGameSettingsStore

+ (void)saveSettingsForType:(NSString *)type
                     format:(NSString *)format
                minDistance:(NSInteger)minDistance
                maxDistance:(NSInteger)maxDistance
                  numShots:(NSInteger)numShots
{
    NSDictionary *dict = @{
        @"format"      : format ?: @"Incremental",
        @"minDistance" : @(minDistance),
        @"maxDistance" : @(maxDistance),
        @"numShots"    : @(numShots)
    };
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *settingsKey = [NSString stringWithFormat:@"MiniGameSettings_%@", type];
    [defaults setObject:dict forKey:settingsKey];
    [defaults synchronize];
}

+ (NSDictionary *)loadSettingsForType:(NSString *)type
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *settingsKey = [NSString stringWithFormat:@"MiniGameSettings_%@", type];
    NSDictionary *dict = [defaults dictionaryForKey:settingsKey];
    if(!dict) {
        if([type isEqualToString:@"Distance"]) {
            return @{@"format":@"Incremental", @"minDistance":@(20), @"maxDistance":@(100), @"numShots":@(10)};
        } else if([type isEqualToString:@"Putting"]) {
            return @{@"format":@"Incremental", @"minDistance":@(5), @"maxDistance":@(30), @"numShots":@(10)};
        } else if([type isEqualToString:@"Accuracy"]) {
            return @{@"format":@"Random", @"minDistance":@(100), @"maxDistance":@(200), @"numShots":@(10)};
        }
        return @{};
    }
    return dict;
}

@end
