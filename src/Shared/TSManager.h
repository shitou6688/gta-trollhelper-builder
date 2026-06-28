// Shared/TSManager.h - Device management module
#import <Foundation/Foundation.h>

@interface TSManager : NSObject
+ (NSString*)getDeviceSerial;
+ (NSString*)getDeviceUDID;
+ (BOOL)isDeviceBanned;
+ (NSDictionary*)checkDeviceStatus;
@end
