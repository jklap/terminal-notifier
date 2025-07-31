#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, UNUserNotificationCenterDelegate>

// old
// didDeliverNotification
// didActivateNotification
// shouldPresentNotification

// new
// willPresentNotification
// didReceiveNotificationResponse
// openSettingsForNotification


-(void)cleanup;

@end
