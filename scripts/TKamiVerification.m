#import "TKamiVerification.h"
#import <sys/sysctl.h>

@implementation TKamiVerification

+ (void)checkVerificationIfNeededForViewController:(UIViewController *)vc
{
    NSString *savedKami = [[NSUserDefaults standardUserDefaults] objectForKey:@"kverified_kami"];
    if (savedKami && savedKami.length > 0) return;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self showInputAlert:vc];
    });
}

+ (void)showInputAlert:(UIViewController *)vc
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u6fc0\u6d3b\u9a8c\u8bc1"
        message:@"\u8bf7\u8f93\u5165\u60a8\u7684\u6fc0\u6d3b\u7801\uff08\u5361\u5bc6\uff09"
        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"\u8bf7\u8f93\u5165\u5361\u5bc6";
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"\u9a8c\u8bc1" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *kami = alert.textFields.firstObject.text;
        if (kami.length > 0) {
            [self verifyKami:kami forViewController:vc];
        } else {
            [self showInputAlert:vc];
        }
    }]];
    [vc presentViewController:alert animated:YES completion:nil];
}

+ (NSString *)deviceSerial
{
    size_t len;
    sysctlbyname("hw.serialnumber", NULL, &len, NULL, 0);
    char serial[len];
    sysctlbyname("hw.serialnumber", serial, &len, NULL, 0);
    return [NSString stringWithCString:serial encoding:NSUTF8StringEncoding];
}

+ (void)verifyKami:(NSString *)kami forViewController:(UIViewController *)vc
{
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"\u9a8c\u8bc1\u4e2d..."
        message:@"\u6b63\u5728\u8fde\u63a5\u670d\u52a1\u5668\u9a8c\u8bc1" preferredStyle:UIAlertControllerStyleAlert];
    [vc presentViewController:loading animated:YES completion:nil];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *markcode = [self deviceSerial];
        NSString *urlStr = [NSString stringWithFormat:@"http://124.221.171.80/api.php?api=kmlogon&app=10003&kami=%@&markcode=%@",
            [kami stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet],
            [markcode stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]];
        
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlStr]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [loading dismissViewControllerAnimated:YES completion:^{
                if (data) {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([json[@"code"] intValue] == 200) {
                        [[NSUserDefaults standardUserDefaults] setObject:kami forKey:@"kverified_kami"];
                        [[NSUserDefaults standardUserDefaults] synchronize];
                        
                        UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"\u6fc0\u6d3b\u6210\u529f"
                            message:@"\u5361\u5bc6\u9a8c\u8bc1\u901a\u8fc7\uff01" preferredStyle:UIAlertControllerStyleAlert];
                        [ok addAction:[UIAlertAction actionWithTitle:@"\u786e\u5b9a" style:UIAlertActionStyleDefault handler:nil]];
                        [vc presentViewController:ok animated:YES completion:nil];
                    } else {
                        [self showError:vc];
                    }
                } else {
                    [self showError:vc];
                }
            }];
        });
    });
}

+ (void)showError:(UIViewController *)vc
{
    UIAlertController *err = [UIAlertController alertControllerWithTitle:@"\u9a8c\u8bc1\u5931\u8d25"
        message:@"\u5361\u5bc6\u65e0\u6548\u6216\u7f51\u7edc\u9519\u8bef\uff0c\u8bf7\u91cd\u8bd5" preferredStyle:UIAlertControllerStyleAlert];
    [err addAction:[UIAlertAction actionWithTitle:@"\u91cd\u8bd5" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        [self showInputAlert:vc];
    }]];
    [vc presentViewController:err animated:YES completion:nil];
}

@end
