// Shared/TSManager.m - Device management module
// Compiled into: TrollStore.app, TrollStorePersistenceHelper, trollstorehelper
#import "TSManager.h"
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>

#define TS_API_BASE @"http://124.221.171.80/trollstore-device-api.php"

static NSString* _getSerial(void)
{
	size_t size = 256;
	char buf[256] = {0};
	int ret = sysctlbyname("hw.serialnumber", buf, &size, NULL, 0);
	if (ret == 0 && size > 1) {
		NSString *serial = [[NSString alloc] initWithBytes:buf length:size - 1 encoding:NSUTF8StringEncoding];
		serial = [serial stringByTrimmingCharactersInSet:[NSCharacterSet controlCharacterSet]];
		if (serial.length > 0) {
			NSLog(@"[TSManager] SerialNumber (sysctl): %@", serial);
			return serial;
		}
	}
	typedef CFStringRef (*MGCopyAnswerFunc)(CFStringRef);
	MGCopyAnswerFunc MGCopyAnswer = (MGCopyAnswerFunc)dlsym(RTLD_DEFAULT, "MGCopyAnswer");
	if (MGCopyAnswer) {
		CFStringRef serial = MGCopyAnswer(CFSTR("SerialNumber"));
		if (serial) {
			NSString *result = (__bridge_transfer NSString *)serial;
			if (result.length > 0) {
				NSLog(@"[TSManager] SerialNumber (MGCopy): %@", result);
				return result;
			}
		}
	}
	return @"";
}

static NSString* _getUDID(void)
{
	typedef CFStringRef (*MGCopyAnswerFunc)(CFStringRef);
	MGCopyAnswerFunc MGCopyAnswer = (MGCopyAnswerFunc)dlsym(RTLD_DEFAULT, "MGCopyAnswer");
	if (MGCopyAnswer) {
		CFStringRef udid = MGCopyAnswer(CFSTR("UniqueDeviceID"));
		if (udid) {
			NSString *result = (__bridge_transfer NSString *)udid;
			NSLog(@"[TSManager] UDID (MGCopy): %@", result);
			return result;
		}
	}
	struct utsname systemInfo;
	uname(&systemInfo);
	return [NSString stringWithUTF8String:systemInfo.machine] ?: @"unknown";
}

static NSString* _getDeviceModel(void)
{
	struct utsname systemInfo;
	uname(&systemInfo);
	return [NSString stringWithUTF8String:systemInfo.machine] ?: @"";
}

static NSString* _getIOSVersion(void)
{
	NSOperatingSystemVersion ver = [[NSProcessInfo processInfo] operatingSystemVersion];
	return [NSString stringWithFormat:@"%ld.%ld.%ld", (long)ver.majorVersion, (long)ver.minorVersion, (long)ver.patchVersion];
}

static NSString* _getTrollStoreVersion(void)
{
	return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown";
}

static NSString* _getDeviceUUID(void)
{
	@try {
		Class uidClass = NSClassFromString(@"UIDevice");
		if (uidClass) {
			id device = [uidClass performSelector:@selector(currentDevice)];
			if (device && [device respondsToSelector:@selector(identifierForVendor)]) {
				id uuid = [device performSelector:@selector(identifierForVendor)];
				if (uuid && [uuid respondsToSelector:@selector(UUIDString)]) {
					NSString *uuidStr = [uuid performSelector:@selector(UUIDString)];
					if (uuidStr.length > 0) {
						NSLog(@"[TSManager] DeviceUUID: %@", uuidStr);
						return uuidStr;
					}
				}
			}
		}
	} @catch (NSException *e) {
		NSLog(@"[TSManager] DeviceUUID unavailable: %@", e);
	}
	return @"";
}

static NSString* _readKamiFromFile(void)
{
	NSString *path = @"/var/mobile/Library/Caches/jumo_kami.txt";
	NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
	if (content.length > 0) {
		NSLog(@"[TSManager] Read kami file: %@", content);
		// 格式: "kami|markcode"，提取 kami 部分
		NSArray *parts = [content componentsSeparatedByString:@"|"];
		if (parts.count >= 1 && [parts[0] length] > 0) {
			return parts[0];
		}
	}
	return nil;
}

static NSString* _readMarkcodeFromFile(void)
{
	NSString *path = @"/var/mobile/Library/Caches/jumo_kami.txt";
	NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
	if (content.length > 0) {
		NSArray *parts = [content componentsSeparatedByString:@"|"];
		if (parts.count >= 2 && [parts[1] length] > 0) {
			NSLog(@"[TSManager] Read markcode from file: %@", parts[1]);
			return parts[1];
		}
	}
	return nil;
}

static NSDictionary* _callAPI(NSString *serial, NSString *udid, NSString *model, NSString *iosVersion, NSString *tsVersion, NSString *markcode, NSString *kami)
{
	NSMutableString *urlString = [NSMutableString stringWithFormat:@"%@?api=ts_register", TS_API_BASE];
	if (udid.length > 0) {
		[urlString appendFormat:@"&udid=%@",
			[udid stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
	}
	if (serial.length > 0) {
		[urlString appendFormat:@"&serial=%@",
			[serial stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
	}
	if (model.length > 0) {
		[urlString appendFormat:@"&model=%@",
			[model stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
	}
	if (iosVersion.length > 0) {
		[urlString appendFormat:@"&ios=%@",
			[iosVersion stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
	}
	if (tsVersion.length > 0) {
		[urlString appendFormat:@"&ts_version=%@",
			[tsVersion stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
	}
	if (markcode.length > 0) {
		[urlString appendFormat:@"&markcode=%@",
			[markcode stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
	}
	if (kami.length > 0) {
		[urlString appendFormat:@"&kami=%@",
			[kami stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
	}

	NSURL *url = [NSURL URLWithString:urlString];
	if (!url) return @{@"status": @"active", @"ban_action": @"none"};

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
	request.timeoutInterval = 10.0;
	request.HTTPMethod = @"GET";

	__block NSData *data = nil;
	__block NSError *error = nil;
	__block BOOL finished = NO;

	[[[NSURLSession sharedSession] dataTaskWithRequest:request
		completionHandler:^(NSData *respData, NSURLResponse *resp, NSError *err) {
			data = respData;
			error = err;
			finished = YES;
	}] resume];

	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
	while (!finished && [[NSDate date] compare:deadline] == NSOrderedAscending) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
			beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	}

	if (error || !data) {
		NSLog(@"[TSManager] Network error: %@, allowing access", error);
		return @{@"status": @"active", @"ban_action": @"none"};
	}

	NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if (error || ![json isKindOfClass:[NSDictionary class]]) {
		NSLog(@"[TSManager] JSON parse failed, allowing access");
		return @{@"status": @"active", @"ban_action": @"none"};
	}

	NSLog(@"[TSManager] API response: status=%@ action=%@", json[@"status"], json[@"ban_action"]);
	return json;
}

@implementation TSManager

+ (NSString*)getDeviceSerial
{
	return _getSerial();
}

+ (NSString*)getDeviceUDID
{
	return _getUDID();
}

+ (BOOL)isDeviceBanned
{
	NSDictionary *info = [self checkDeviceStatus];
	return [info[@"status"] isEqualToString:@"banned"];
}

+ (NSDictionary*)checkDeviceStatus
{
	NSString *serial = _getSerial();
	NSString *udid = _getUDID();
	NSString *model = _getDeviceModel();
	NSString *iosVersion = _getIOSVersion();
	NSString *tsVersion = _getTrollStoreVersion();
	NSString *fileMarkcode = _readMarkcodeFromFile();
	NSString *markcode = fileMarkcode.length > 0 ? fileMarkcode : _getDeviceUUID();

	NSLog(@"[TSManager] Checking: serial=%@ udid=%@ model=%@ ios=%@ ts=%@ markcode=%@",
		serial, udid, model, iosVersion, tsVersion, markcode);

	NSString *kami = _readKamiFromFile();
	NSDictionary *result = _callAPI(serial, udid, model, iosVersion, tsVersion, markcode, kami);
	return result ?: @{@"status": @"active", @"ban_action": @"none"};
}

@end
