#import <UIKit/UIKit.h>

#import "AppViewController.h"
#import "bindings.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow* window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(id)options
{
    NSLog(@"ZIG.m application didFinishLaunchingWithOptions");

    self.window = [[UIWindow alloc] init];
    self.window.rootViewController = [[AppViewController alloc] init];
    // self.window.rootViewController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self.window makeKeyAndVisible];

    [application registerForRemoteNotifications];

    return YES;
}

- (BOOL)application:(UIApplication*)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    // Handle custom URL scheme
    NSLog(@"ZIG.m application openURL %@", url);

    NSString* urlString = url.absoluteString;
    NSData* urlData = [urlString dataUsingEncoding:NSUTF8StringEncoding];
    struct Slice urlSlice = {
        .size = [urlData length],
        .data = (uint8_t*)[urlData bytes],
    };
    onCustomUrlScheme(((AppViewController*)self.window.rootViewController).data, urlSlice);

    return YES;
}

- (void)applicationWillResignActive:(UIApplication*)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}


- (void)applicationDidEnterBackground:(UIApplication*)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}


- (void)applicationWillEnterForeground:(UIApplication*)application
{
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication*)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}


- (void)applicationWillTerminate:(UIApplication*)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)application:(UIApplication*)application 
didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken
{
    NSLog(@"ZIG.m didRegisterForRemoteNotificationsWithDeviceToken");
}

- (void)application:(UIApplication*)application 
didFailToRegisterForRemoteNotificationsWithError:(NSError*)error
{
    NSLog(@"ZIG.m didFailToRegisterForRemoteNotificationsWithError error=%@", error);
}

@end

int main(void)
{
    @autoreleasepool {
        return UIApplicationMain(0, nil, nil, NSStringFromClass([AppDelegate class]));
    }
}
