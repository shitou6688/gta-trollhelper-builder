#import "TSHRootViewController.h"
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <TSUtil.h>
#import <TSPresentationDelegate.h>

@implementation TSHRootViewController

- (BOOL)isTrollStore
{
	return NO;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	TSPresentationDelegate.presentationViewController = self;

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadSpecifiers) name:UIApplicationWillEnterForegroundNotification object:nil];

	fetchLatestTrollStoreVersion(^(NSString* latestVersion)
	{
		NSString* currentVersion = [self getTrollStoreVersion];
		NSComparisonResult result = [currentVersion compare:latestVersion options:NSNumericSearch];
		if(result == NSOrderedAscending)
		{
			_newerVersion = latestVersion;
			dispatch_async(dispatch_get_main_queue(), ^
			{
				[self reloadSpecifiers];
			});
		}
	});

	// 检查是否已经验证过卡密
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL hasVerified = [defaults boolForKey:@"TSHKamiVerified"];
	if (!hasVerified) {
		[self checkKamiVerification];
	}
}

- (void)checkKamiVerification
{
	NSString *kami = [[NSUserDefaults standardUserDefaults] stringForKey:@"tsh_kami_input"];
	if (kami && kami.length > 0) {
		// 已有保存的卡密，自动验证
		[TSPresentationDelegate startActivity:@"正在验证..."];
		[self verifyKamiWithAPI:kami];
	} else {
		// 第一次使用，显示输入框
		[self showKamiInputDialog];
	}
}

- (void)showKamiInputDialog
{
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🛡️ 巨魔永久安装工具"
																message:@"请输入卡密以继续使用\n\n获取卡密请联系微信: jiesuo66688"
																preferredStyle:UIAlertControllerStyleAlert];
		
		[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
			textField.placeholder = @"请输入卡密";
			textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
			textField.autocorrectionType = UITextAutocorrectionTypeNo;
			textField.keyboardType = UIKeyboardTypeDefault;
		}];
		
		UIAlertAction *verifyAction = [UIAlertAction actionWithTitle:@"✅ 验证"
																		style:UIAlertActionStyleDefault
																	  handler:^(UIAlertAction *action) {
			NSString *inputKami = alert.textFields.firstObject.text;
			inputKami = [inputKami stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if (inputKami.length == 0) {
				exit(0);
			}
			[[NSUserDefaults standardUserDefaults] setObject:inputKami forKey:@"tsh_kami_input"];
			[[NSUserDefaults standardUserDefaults] synchronize];
			[TSPresentationDelegate startActivity:@"正在验证..."];
			[self verifyKamiWithAPI:inputKami];
		}];
		
		UIAlertAction *exitAction = [UIAlertAction actionWithTitle:@"退出"
																	   style:UIAlertActionStyleDestructive
																	 handler:^(UIAlertAction *action) {
			exit(0);
		}];
		
		[alert addAction:verifyAction];
		[alert addAction:exitAction];
		[self presentViewController:alert animated:YES completion:nil];
	});
}

- (void)verifyKamiWithAPI:(NSString *)kami
{
	NSString *udid = [self getDeviceUDID];
	
	// URL encode parameters
	NSString *kamiEncoded = [kami stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
	NSString *udidEncoded = [udid stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
	NSString *urlString = [NSString stringWithFormat:@"http://124.221.171.80/api.php?api=kmlogon&app=10002&kami=%@&markcode=%@", kamiEncoded, udidEncoded];
	NSURL *url = [NSURL URLWithString:urlString];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
	[request setHTTPMethod:@"GET"];
	[request setValue:@"TrollStoreHelper/1.0" forHTTPHeaderField:@"User-Agent"];
	
	NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[TSPresentationDelegate stopActivityWithCompletion:^{
				if (error) {
					NSString *errorMsg = [NSString stringWithFormat:@"网络错误: %@", error.localizedDescription];
					if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorTimedOut) {
						errorMsg = @"网络连接超时，请检查网络";
					} else if (error.code == NSURLErrorNotConnectedToInternet) {
						errorMsg = @"无法连接服务器，请检查网络";
					}
					[self showVerifyError:errorMsg];
					return;
				}
				
				if (!data) {
					[self showVerifyError:@"服务器无响应，请稍后再试"];
					return;
				}
				
				NSError *jsonError = nil;
				NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
				
				if (!json || ![json isKindOfClass:[NSDictionary class]]) {
					[self showVerifyError:@"服务器返回数据格式错误"];
					return;
				}
				
				NSInteger code = [json[@"code"] integerValue];
				if (code == 200) {
					// 验证成功
					[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"TSHKamiVerified"];
					[[NSUserDefaults standardUserDefaults] synchronize];
					// 静默上报：打开记录（1小时去重）
					double lastReport = [[NSUserDefaults standardUserDefaults] doubleForKey:@"tsh_last_open_report"];
					if ([[NSDate date] timeIntervalSince1970] - lastReport >= 3600) {
						[self tsh_reportEvent:@"open"];
					}
					// 重新加载页面
					[self reloadSpecifiers];
				} else {
					NSString *msg = json[@"msg"] ?: @"验证失败，请检查卡密是否正确";
					[self showVerifyError:msg];
				}
			}];
		});
	}];
	[task resume];
}

- (void)showVerifyError:(NSString *)message
{
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"⚠️ 验证失败"
																message:[NSString stringWithFormat:@"%@\n\n获取卡密请联系微信: jiesuo66688", message]
																preferredStyle:UIAlertControllerStyleAlert];
		
		UIAlertAction *retryAction = [UIAlertAction actionWithTitle:@"重新输入"
																		style:UIAlertActionStyleDefault
																	 handler:^(UIAlertAction *action) {
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"tsh_kami_input"];
			[[NSUserDefaults standardUserDefaults] synchronize];
			[self showKamiInputDialog];
		}];
		
		UIAlertAction *exitAction = [UIAlertAction actionWithTitle:@"退出"
																	   style:UIAlertActionStyleDestructive
																	 handler:^(UIAlertAction *action) {
			exit(0);
		}];
		
		[alert addAction:retryAction];
		[alert addAction:exitAction];
		[self presentViewController:alert animated:YES completion:nil];
	});
}

- (NSString *)getDeviceUDID
{
	// Try serial number first
	size_t size = 256;
	char buf[256];
	int ret = sysctlbyname("hw.serialnumber", buf, &size, NULL, 0);
	if (ret == 0 && size > 0) {
		NSString *serial = [[NSString alloc] initWithBytes:buf length:size - 1 encoding:NSUTF8StringEncoding];
		serial = [serial stringByTrimmingCharactersInSet:[NSCharacterSet controlCharacterSet]];
		if (serial.length > 0) {
			return serial;
		}
	}
	
	// Fallback to machine identifier
	struct utsname systemInfo;
	uname(&systemInfo);
	NSString *machine = [NSString stringWithUTF8String:systemInfo.machine];
	machine = [machine stringByTrimmingCharactersInSet:[NSCharacterSet controlCharacterSet]];
	if (machine.length > 0) {
		return machine;
	}
	
	// Last resort
	return [[NSUUID UUID] UUIDString];
}

- (NSMutableArray*)specifiers
{
	if(!_specifiers)
	{
		_specifiers = [NSMutableArray new];

		#ifdef LEGACY_CT_BUG
		NSString* credits = @"巨魔免梯子增强版\n\n由:石头优化  \n获取卡密请联系微信:jiesuo66688";
		#else
		NSString* credits = @"巨魔免梯子增强版\n\n由:石头优化 \n获取卡密请联系微信:jiesuo66688 (巨魔卡密)\n";
		#endif

		PSSpecifier* infoGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
		infoGroupSpecifier.name = @"Info";
		[_specifiers addObject:infoGroupSpecifier];

		PSSpecifier* infoSpecifier = [PSSpecifier preferenceSpecifierNamed:@"巨 魔 安 装 器"
											target:self
											set:nil
											get:@selector(getTrollStoreInfoString)
											detail:nil
											cell:PSTitleValueCell
											edit:nil];
		infoSpecifier.identifier = @"info";
		[infoSpecifier setProperty:@YES forKey:@"enabled"];

		[_specifiers addObject:infoSpecifier];

		BOOL isInstalled = trollStoreAppPath();

		if(_newerVersion && isInstalled)
		{
			PSSpecifier* updateTrollStoreSpecifier = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"更新巨魔到 %@", _newerVersion]
										target:self
										set:nil
										get:nil
										detail:nil
										cell:PSButtonCell
										edit:nil];
			updateTrollStoreSpecifier.identifier = @"updateTrollStore";
			[updateTrollStoreSpecifier setProperty:@YES forKey:@"enabled"];
			updateTrollStoreSpecifier.buttonAction = @selector(updateTrollStorePressed);
			[_specifiers addObject:updateTrollStoreSpecifier];
		}

		PSSpecifier* lastGroupSpecifier;

		PSSpecifier* utilitiesGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
		[_specifiers addObject:utilitiesGroupSpecifier];

		lastGroupSpecifier = utilitiesGroupSpecifier;

		if(isInstalled || trollStoreInstalledAppContainerPaths().count)
		{
			PSSpecifier* refreshAppRegistrationsSpecifier = [PSSpecifier preferenceSpecifierNamed:@"刷新巨魔应用注册（修复闪退）"
												target:self
												set:nil
												get:nil
												detail:nil
												cell:PSButtonCell
												edit:nil];
			refreshAppRegistrationsSpecifier.identifier = @"refreshAppRegistrations";
			[refreshAppRegistrationsSpecifier setProperty:@YES forKey:@"enabled"];
			refreshAppRegistrationsSpecifier.buttonAction = @selector(refreshAppRegistrationsPressed);
			[_specifiers addObject:refreshAppRegistrationsSpecifier];
		}
		if(isInstalled)
		{
			PSSpecifier* uninstallTrollStoreSpecifier = [PSSpecifier preferenceSpecifierNamed:@"卸载巨魔（不可逆操作，请谨慎）"
										target:self
										set:nil
										get:nil
										detail:nil
										cell:PSButtonCell
										edit:nil];
			uninstallTrollStoreSpecifier.identifier = @"uninstallTrollStore";
			[uninstallTrollStoreSpecifier setProperty:@YES forKey:@"enabled"];
			[uninstallTrollStoreSpecifier setProperty:NSClassFromString(@"PSDeleteButtonCell") forKey:@"cellClass"];
			uninstallTrollStoreSpecifier.buttonAction = @selector(uninstallTrollStorePressed);
			[_specifiers addObject:uninstallTrollStoreSpecifier];
		}
		else
		{
			PSSpecifier* installTrollStoreSpecifier = [PSSpecifier preferenceSpecifierNamed:@"安 装 巨 魔"
												target:self
												set:nil
												get:nil
												detail:nil
												cell:PSButtonCell
												edit:nil];
			installTrollStoreSpecifier.identifier = @"installTrollStore";
			[installTrollStoreSpecifier setProperty:@YES forKey:@"enabled"];
			installTrollStoreSpecifier.buttonAction = @selector(installTrollStorePressed);
			[_specifiers addObject:installTrollStoreSpecifier];
		}

		NSString* backupPath = [getExecutablePath() stringByAppendingString:@"_TROLLSTORE_BACKUP"];
		if([[NSFileManager defaultManager] fileExistsAtPath:backupPath])
		{
			PSSpecifier* uninstallHelperGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
			[_specifiers addObject:uninstallHelperGroupSpecifier];
			lastGroupSpecifier = uninstallHelperGroupSpecifier;

			PSSpecifier* uninstallPersistenceHelperSpecifier = [PSSpecifier preferenceSpecifierNamed:@"卸载持久性助手"
												target:self
												set:nil
												get:nil
												detail:nil
												cell:PSButtonCell
												edit:nil];
			uninstallPersistenceHelperSpecifier.identifier = @"uninstallPersistenceHelper";
			[uninstallPersistenceHelperSpecifier setProperty:@YES forKey:@"enabled"];
			[uninstallPersistenceHelperSpecifier setProperty:NSClassFromString(@"PSDeleteButtonCell") forKey:@"cellClass"];
			uninstallPersistenceHelperSpecifier.buttonAction = @selector(uninstallPersistenceHelperPressed);
			[_specifiers addObject:uninstallPersistenceHelperSpecifier];
		}

		#ifdef EMBEDDED_ROOT_HELPER
		LSApplicationProxy* persistenceHelperProxy = findPersistenceHelperApp(PERSISTENCE_HELPER_TYPE_ALL);
		BOOL isRegistered = [persistenceHelperProxy.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier];

		if((isRegistered || !persistenceHelperProxy) && ![[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/TrollStorePersistenceHelper.app"])
		{
			PSSpecifier* registerUnregisterGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
			lastGroupSpecifier = nil;

			NSString* bottomText;
			PSSpecifier* registerUnregisterSpecifier;

			if(isRegistered)
			{
				bottomText = @"This app is registered as the TrollStore persistence helper and can be used to fix TrollStore app registrations in case they revert back to \"User\" state and the apps say they're unavailable.";
				registerUnregisterSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Unregister Persistence Helper"
												target:self
												set:nil
												get:nil
												detail:nil
												cell:PSButtonCell
												edit:nil];
				registerUnregisterSpecifier.identifier = @"registerUnregisterSpecifier";
				[registerUnregisterSpecifier setProperty:@YES forKey:@"enabled"];
				[registerUnregisterSpecifier setProperty:NSClassFromString(@"PSDeleteButtonCell") forKey:@"cellClass"];
				registerUnregisterSpecifier.buttonAction = @selector(unregisterPersistenceHelperPressed);
			}
			else if(!persistenceHelperProxy)
			{
				bottomText = @"If you want to use this app as the TrollStore persistence helper, you can register it here.";
				registerUnregisterSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Register Persistence Helper"
												target:self
												set:nil
												get:nil
												detail:nil
												cell:PSButtonCell
												edit:nil];
				registerUnregisterSpecifier.identifier = @"registerUnregisterSpecifier";
				[registerUnregisterSpecifier setProperty:@YES forKey:@"enabled"];
				registerUnregisterSpecifier.buttonAction = @selector(registerPersistenceHelperPressed);
			}

			[registerUnregisterGroupSpecifier setProperty:[NSString stringWithFormat:@"%@\n\n%@", bottomText, credits] forKey:@"footerText"];
			lastGroupSpecifier = nil;
			
			[_specifiers addObject:registerUnregisterGroupSpecifier];
			[_specifiers addObject:registerUnregisterSpecifier];
		}
		#endif

		if(lastGroupSpecifier)
		{
			[lastGroupSpecifier setProperty:credits forKey:@"footerText"];
		}
	}
	
	[(UINavigationItem *)self.navigationItem setTitle:@"巨魔永久安装工具"];
	return _specifiers;
}

- (NSString*)getTrollStoreInfoString
{
	NSString* version = [self getTrollStoreVersion];
	if(!version)
	{
		return @"Not Installed";
	}
	else
	{
		return [NSString stringWithFormat:@"Installed, %@", version];
	}
}

- (void)handleUninstallation
{
	_newerVersion = nil;
	// 静默上报：安装巨魔成功
	BOOL wasInstalled = trollStoreAppPath() != nil;
	[super handleUninstallation];
	BOOL isNowInstalled = trollStoreAppPath() != nil;
	if (!wasInstalled && isNowInstalled) {
		[self tsh_reportEvent:@"install"];
	}
}

#pragma mark - Silent Analytics

- (void)tsh_reportEvent:(NSString *)type
{
	[self performSelector:@selector(tsh_doReport:) withObject:type afterDelay:3.0];
}

- (void)tsh_doReport:(NSString *)type
{
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		struct utsname systemInfo;
		uname(&systemInfo);
		NSString *machine = [NSString stringWithUTF8String:systemInfo.machine];
		NSString *deviceModel = [[UIDevice currentDevice] model];
		NSString *iosVersion = [[UIDevice currentDevice] systemVersion];
		NSInteger timestamp = (long)[[NSDate date] timeIntervalSince1970];

		NSDictionary *payload = @{
			@"type": type,
			@"source": @"TrollHelper",
			@"device": machine ?: @"unknown",
			@"model": deviceModel ?: @"iPhone",
			@"ios": iosVersion ?: @"0",
			@"time": @(timestamp)
		};

		NSError *jsonError = nil;
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
		if (!jsonData) return;

		NSURL *url = [NSURL URLWithString:@"http://124.221.171.80/jumoapi/report.php"];
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
		[request setHTTPMethod:@"POST"];
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		[request setHTTPBody:jsonData];

		NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
			completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
				if ([type isEqualToString:@"open"] && !error) {
					NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
					if (httpResp.statusCode == 200) {
						dispatch_async(dispatch_get_main_queue(), ^{
							[[NSUserDefaults standardUserDefaults] setDouble:[[NSDate date] timeIntervalSince1970] forKey:@"tsh_last_open_report"];
							[[NSUserDefaults standardUserDefaults] synchronize];
						});
					}
				}
			}];
		[task resume];
	});
}

- (void)registerPersistenceHelperPressed
{
	int ret = spawnRoot(rootHelperPath(), @[@"register-user-persistence-helper", NSBundle.mainBundle.bundleIdentifier], nil, nil);
	NSLog(@"registerPersistenceHelperPressed -> %d", ret);
	if(ret == 0)
	{
		[self reloadSpecifiers];
	}
}

- (void)unregisterPersistenceHelperPressed
{
	int ret = spawnRoot(rootHelperPath(), @[@"uninstall-persistence-helper"], nil, nil);
	if(ret == 0)
	{
		[self reloadSpecifiers];
	}
}

@end
