//
//  AppDelegate.m
//  XQHomeLedger
//
//  Created by luosi on 2026/10/22.
//

#import "AppDelegate.h"
#import "HLKit.h"
#import "HLStore.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UINavigationBarAppearance *nav = [[UINavigationBarAppearance alloc] init];
    [nav configureWithTransparentBackground];
    nav.backgroundColor = [HLKit mist];
    nav.titleTextAttributes = @{NSForegroundColorAttributeName: [HLKit ink], NSFontAttributeName: [HLKit rounded:17 weight:UIFontWeightSemibold]};
    nav.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [HLKit ink], NSFontAttributeName: [HLKit rounded:32 weight:UIFontWeightBold]};
    UINavigationBarAppearance *scrolled = [nav copy];
    [scrolled configureWithDefaultBackground];
    scrolled.titleTextAttributes = nav.titleTextAttributes;
    scrolled.largeTitleTextAttributes = nav.largeTitleTextAttributes;
    [UINavigationBar appearance].standardAppearance = scrolled;
    [UINavigationBar appearance].scrollEdgeAppearance = nav;
    [UINavigationBar appearance].tintColor = [HLKit leafText];
    // Opens the database and clears photo files left by forms that were cancelled.
    [[HLStore shared] sweepFiles];
    return YES;
}

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

@end
