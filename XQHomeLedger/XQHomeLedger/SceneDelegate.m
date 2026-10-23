//
//  SceneDelegate.m
//  XQHomeLedger
//
//  Created by luosi on 2026/10/22.
//

#import "SceneDelegate.h"
#import "HLKit.h"
#import "HLDockController.h"
#import "HLInsights.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    self.window.tintColor = [HLKit leafText];
    self.window.backgroundColor = [HLKit mist];
    self.window.rootViewController = [[HLDockController alloc] init];
    [self.window makeKeyAndVisible];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged) name:HLLanguageChangedNotification object:nil];
}

/// Screens read their strings when built, so a fresh tree applies the new language everywhere.
- (void)languageChanged {
    UIViewController *old = self.window.rootViewController;
    void (^swap)(void) = ^{
        self.window.rootViewController = [[HLDockController alloc] init];
        // Reminder titles stay as saved; future ones use the new language.
        [HLInsights rescheduleAll];
    };
    if (old.presentedViewController) [old dismissViewControllerAnimated:NO completion:swap];
    else swap();
}

@end
