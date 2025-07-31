#import "AppDelegate.h"
#import <ScriptingBridge/ScriptingBridge.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

NSString *const TerminalNotifierBundleID = @"com.halfsane.terminal-notifier";
NSString *const NotificationCenterUIBundleID = @"com.apple.notificationcenterui";

NSString *_fakeBundleIdentifier = nil;

UNNotificationRequest *currentRequest = nil;

// The objectForKeyedSubscript: method takes a key as its argument and returns the value associated with that key
// in the user defaults.
// If the value is a string and it starts with a backslash (\), it removes the backslash and returns the rest of the string.
// Otherwise, it returns the original value.
@implementation NSUserDefaults (SubscriptAndUnescape)
- (id)objectForKeyedSubscript:(id)key;
{
    id obj = [self objectForKey:key];
    if ([obj isKindOfClass:[NSString class]] && [(NSString *)obj hasPrefix:@"\\"]) {
        obj = [(NSString *)obj substringFromIndex:1];
    }
    return obj;
}
@end

@implementation NSBundle (FakeBundleIdentifier)

// Overriding bundleIdentifier works, but overriding NSUserNotificationAlertStyle does not work.
- (NSString *)__bundleIdentifier;
{
    if (self == [NSBundle mainBundle]) {
        return _fakeBundleIdentifier ? _fakeBundleIdentifier : TerminalNotifierBundleID;
    } else {
        return [self __bundleIdentifier];
    }
}

@end

static BOOL InstallFakeBundleIdentifierHook() {
    Class class = objc_getClass("NSBundle");
    if (class) {
        method_exchangeImplementations(class_getInstanceMethod(class, @selector(bundleIdentifier)),
                                       class_getInstanceMethod(class, @selector(__bundleIdentifier)));
        return YES;
    }
    return NO;
}

@implementation AppDelegate

// initializes the user defaults with default values
// If the OS version is Mavericks (10.9), it sets the value of the "sender" key to "com.apple.Terminal".
//  Otherwise, if the OS version is Mountain Lion (10.8) or earlier, it sets the value of an empty key to "message".
+ (void)initializeUserDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // initialize the dictionary with default values depending on OS level
    NSDictionary *appDefaults;
    appDefaults = @{@"sender" : @"com.apple.Terminal"};

    // and set them appropriately
    [defaults registerDefaults:appDefaults];
}

// Called when the application finishes launching
// - Checks for help display
// - Checks for version display
// - Retrieves user input values subtitle, message, remove, list, and sound, use stdin when message is empty
// - When list is set, list all notifications and exit
// - Install a fake bundle identifier hook and sets the _fakeBundleIdentifier variable to the value of the sender key if set
// - When remove is set, remove all remaining notifications and exit
// - Deliver a notification to the user with given options
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
    NSError *error;
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;

    UNNotificationResponse *userNotification = notification.userInfo[NSApplicationLaunchUserNotificationKey];
    if (userNotification) {
        // App is being opened as part of a notification response so handle it
        [self userActivatedNotification:userNotification];

    } else {
        // Checks if the "-help" command line argument is present and prints the help if so
        if ([[[NSProcessInfo processInfo] arguments] indexOfObject:@"-help"] != NSNotFound) {
            [self printHelpBanner];
            exit(0);
        }

        // Checks if "-version" command line argument is present and display version if so
        if ([[[NSProcessInfo processInfo] arguments] indexOfObject:@"-version"] != NSNotFound) {
            [self printVersion];
            exit(0);
        }

        // Checks if the Notification Center is running, and exits the application if it is not.
        NSArray *runningProcesses = [[[NSWorkspace sharedWorkspace] runningApplications] valueForKey:@"bundleIdentifier"];
        if ([runningProcesses indexOfObject:NotificationCenterUIBundleID] == NSNotFound) {
            NSLog(@"[!] Unable to post a notification for the current user (%@), as it has no running NotificationCenter instance", NSUserName());
            exit(1);
        }

        dispatch_group_t group = dispatch_group_create();
        dispatch_group_enter(group);

        UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound;
        [center requestAuthorizationWithOptions:options
                              completionHandler:^(BOOL granted, NSError *_Nullable error) {
                                if (!granted) {
                                    printf("%s\n", [error.localizedDescription UTF8String]);
                                    printf("Unable to continue\n");
                                    exit(1);
                                }
                                dispatch_group_leave(group);
                              }];
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        __block BOOL sound_allowed = YES;

        dispatch_group_enter(group);
        [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
            //NSLog(@"%@", settings);
            if (settings.authorizationStatus != UNAuthorizationStatusAuthorized && settings.authorizationStatus != UNAuthorizationStatusProvisional ) {
                printf("Notifications are not enabled\n");
                printf("Unable to continue\n");
                exit(1);
            }
            if ( settings.alertSetting != UNNotificationSettingEnabled ) {
                printf("Alert notifications not enabled\n");
                printf("Unable to continue\n");
                exit(1);
            }
            if ( settings.alertStyle != UNAlertStyleAlert ) {
                printf("Please enable alert style notifications (vs banner)");
            }
            if ( settings.soundSetting != UNNotificationSettingEnabled ) {
                printf("Please enable sounds for notifications");
                sound_allowed = NO;
            }
            dispatch_group_leave(group);
        }];
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        if ([[[NSProcessInfo processInfo] arguments] indexOfObject:@"-check"] != NSNotFound) {
            exit(0);
        }

        // Prepare configurations values into the defaults map from given inputs
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        NSString *message = defaults[@"message"];
        NSString *remove = defaults[@"remove"];
        NSString *list = defaults[@"list"];
        NSString *sender = defaults[@"sender"];

        // If the message is nil and standard input is being piped to the application,
        // read the piped data and set it as the message.
        if (message == nil && !isatty(STDIN_FILENO)) {
            NSData *inputData = [NSData dataWithData:[[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile]];
            message = [[NSString alloc] initWithData:inputData encoding:NSUTF8StringEncoding];
            if ([message length] == 0) {
                message = nil;
            }
        }

        // If no message or remove or list command found, print help message and exit.
        if (message == nil && remove == nil && list == nil) {
            printf("Nothing found to do\n\n");
            [self printHelpBanner];
            exit(1);
        }

        if (list) {
            // list all notifications
            [self listNotificationWithGroupID:list];
            exit(0);
        }

        // Install the fake bundle ID hook so we can fake the sender. This also
        // needs to be done to be able to remove a message.
        if (sender) {
            @autoreleasepool {
                if (InstallFakeBundleIdentifierHook()) {
                    _fakeBundleIdentifier = sender;
                }
            }
        }

        if (remove) {
            // remove any notifications via group ID before we try to create a new notifications
            [self removeNotificationWithGroupID:remove];
            if (message == nil || ([message length] == 0)) {
                // if we don't have a message also passed in, exit
                exit(0);
            }
        }

        // deliver the notification if a message exists with the given options dictionary to customize it.
        // The dictionary values are set based on corresponding user defaults, and some keys are set
        // based on the command line arguments passed to the application.
        if (message) {
            NSMutableDictionary *options = [NSMutableDictionary dictionary];
            NSString *subtitle = defaults[@"subtitle"];

            bool wait = NO;

            // allow just -sound to support default of "default"
            NSString *sound = nil;
            if ([[[NSProcessInfo processInfo] arguments] containsObject:@"-sound"] == true) {
                if ( sound_allowed ) {
                    sound = @"default";
                    if(defaults[@"sound"]) {
                        sound = defaults[@"sound"];
                    }
                } else {
                    printf("Sound for notifications is not enabled\n");
                }
            }


            if (defaults[@"group"]) {
                options[@"groupID"] = defaults[@"group"];
            }

            if (defaults[@"contentImage"]) {
                NSFileManager *fileManager = [NSFileManager defaultManager];
                NSString *imagePath = defaults[@"contentImage"];
                // verify the file exists
                if ( ! [fileManager fileExistsAtPath:imagePath]){
                    printf("contentImage file doesn't exist at %s", [imagePath UTF8String]);
                    exit(1);
                }
                NSURL *imageFileURL = [NSURL fileURLWithPath:imagePath];
                // isFileReferenceURL
                // https://developer.apple.com/documentation/foundation/nsurl/checkresourceisreachableandreturnerror(_:)?language=objc
                // https://developer.apple.com/documentation/foundation/nsurl/isfilereferenceurl()?language=objc
                // https://developer.apple.com/documentation/foundation/nsurl/isfileurl?language=objc


                // TODO: verify it's a supported file type

                // Copy to a temp file as it will get moved into the notification
                NSString *temporaryDirectoryPath = NSTemporaryDirectory();

                // Generate a unique file name for the temporary copy
                NSString *fileName = [imageFileURL lastPathComponent];
                fileName = [NSString stringWithFormat:@"%@-%@", [NSUUID UUID], fileName];
                NSString *temporaryFilePath = [temporaryDirectoryPath stringByAppendingPathComponent:fileName];

                NSURL *temporaryFileURL = [NSURL fileURLWithPath:temporaryFilePath];

                // Copy the file
                BOOL success = [fileManager copyItemAtURL:imageFileURL toURL:temporaryFileURL error:&error];
                if (error) {
                    NSLog(@"%@", error);
                    exit(1);
                }
                NSLog(@"%@", [temporaryFileURL absoluteURL]);
                options[@"contentImage"] = [temporaryFileURL absoluteString];
            }

            if (defaults[@"activate"]) {
                options[@"bundleID"] = defaults[@"activate"];
            }
            if (defaults[@"execute"]) {
                options[@"command"] = defaults[@"execute"];
            }
            if (defaults[@"open"]) {
                // msteams://... support?
                NSURL *url = [NSURL URLWithString:defaults[@"open"]];
                if ((url && url.scheme && url.host) || [url isFileURL]) {
                    options[@"open"] = defaults[@"open"];
                } else {
                    NSLog(@"'%@' is not a valid URI.", defaults[@"open"]);
                    exit(1);
                }
            }

            if (defaults[@"closeLabel"]) {
                options[@"closeLabel"] = defaults[@"closeLabel"];
                wait = YES;
            }
            if (defaults[@"dropdownLabel"]) {
                options[@"dropdownLabel"] = defaults[@"dropdownLabel"];
            }
            if (defaults[@"actions"]) {
                options[@"actions"] = defaults[@"actions"];
                wait = YES;
            }

            if ([[[NSProcessInfo processInfo] arguments] containsObject:@"-reply"] == true) {
                options[@"reply"] = @"Reply";
                if (defaults[@"reply"]) {
                    options[@"reply"] = defaults[@"reply"];
                }
                wait = YES;
            }

            options[@"output"] = @"outputEvent";
            if ([[[NSProcessInfo processInfo] arguments] containsObject:@"-json"] == true) {
                options[@"output"] = @"json";
            }

            if (defaults[@"timeout"]) {
                // TODO: verify > 0
                options[@"timeout"] = defaults[@"timeout"];
                wait = YES;
            }

            if ([[[NSProcessInfo processInfo] arguments] containsObject:@"-wait"] == true) {
                // TODO: we need to make sure we are getting the close action processed (currently broken)
                wait = YES;
            }

            options[@"uuid"] = [self getUuid];

            // TOOD: broken: terminal-notifier -message "Deploy now on UAT?" -actions Now,"Later today","Tomorrow" -dropdownLabel "When?"
            // TOOD: doesn't display dropdown label

            // TODO: reply AND actions -> doesn't make sense
            // TODO: activate | open | execute AND reply | actions -> doesn't make sense
            // TODO: acitvate | open | execute AND wait -> doesn't make sense
            // TODO: actions AND closeLable -> doesn't make sense

            // TODO: support activate | open | execute upon an action response

            // TODO: single action or no action but closeLabel are basically the same behavior?

            if ( wait ) {
                NSLog(@"will wait");
                options[@"waitForResponse"] = @YES;
            }

            if ([[[NSProcessInfo processInfo] arguments] containsObject:@"-ignoreDnD"] == true) {
                options[@"ignoreDnD"] = @YES;
            }

            [self deliverNotificationWithTitle:defaults[@"title"] ?: @"Terminal" subtitle:subtitle message:message options:options sound:sound];
        }
    }
}

- (void)deliverNotificationWithTitle:(NSString *)title
                            subtitle:(NSString *)subtitle
                             message:(NSString *)message
                             options:(NSMutableDictionary *)options
                               sound:(NSString *)sound;
{
    // First remove earlier notification with the same group ID.
    if (options[@"groupID"]) {
        [self removeNotificationWithGroupID:options[@"groupID"]];
    }

    [self outputJson:options];

    UNMutableNotificationContent *content = [UNMutableNotificationContent new]; // [[UNMutableNotificationContent alloc] init];
    content.title = title;
    content.subtitle = subtitle;
    content.body = message;

    // see https://github.com/w0lfschild/macOS_headers/blob/master/macOS/Frameworks/UserNotifications/UNNotificationContent.h
    if (options[@"appIcon"]) {
        // TODO: doesn't work currently
        NSLog(@"appIcon");
        [content setValue:[self getImageFromURL:options[@"appIcon"]] forKey:@"_identityImage"];
        [content setValue:@(false) forKey:@"_identityImageHasBorder"];
    }
    if (options[@"contentImage"]) {
        NSLog(@"contentImage");
        NSError *error;
        content.attachments = @[ [UNNotificationAttachment attachmentWithIdentifier:@"contentImage"
                                                                                URL:[NSURL URLWithString:options[@"contentImage"]]
                                                                            options:nil
                                                                              error:&error] ];
        if (error) {
            NSLog(@"error: %@", error);
        }
    }

    // Actions
    if (options[@"actions"]) {
        NSLog(@"actions");

        NSMutableArray *actions = [NSMutableArray array];
        // split the actions string
        NSArray *myActions = [options[@"actions"] componentsSeparatedByString:@","];
        // TODO: default behavior: https://developer.apple.com/documentation/usernotifications/unnotificationactionoptionnone?language=objc
        for (NSString *action in myActions) {
            // TODO: add icon support https://developer.apple.com/documentation/usernotifications/unnotificationaction/icon?language=objc
            // https://developer.apple.com/documentation/usernotifications/unnotificationactionicon?language=objc
            // Use the SF Symbols app to look up the names of system symbol images. Download this app from the design resources page at
            // https://developer.apple.com/design/resources/
            // UNNotificationActionIcon *icon = [UNNotificationActionIcon iconWithTemplateImageName:@"search"];
            [actions addObject:[UNNotificationAction actionWithIdentifier:action title:action options:UNNotificationActionOptionForeground]];
        }
        // reassign our new array of actions to options
        options[@"actions"] = myActions;

        UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:@"actionsCategory"
                                                                                  actions:actions
                                                                        intentIdentifiers:@[]
                                                                                  options:UNNotificationCategoryOptionCustomDismissAction];
        [[UNUserNotificationCenter currentNotificationCenter] setNotificationCategories:[NSSet setWithObject:category]];
        content.categoryIdentifier = @"actionsCategory";

        if (options[@"dropdownLabel"]) {
            // TODO: add dropdown label
            NSLog(@"TODO: dropdownLabel");
        }
    } else if (options[@"reply"]) {
        // TODO: customize reply button text/label
        UNTextInputNotificationAction *replyAction = [UNTextInputNotificationAction actionWithIdentifier:@"reply"
                                                                                                   title:@"Reply"
                                                                                                 options:UNNotificationActionOptionForeground
                                                                                    textInputButtonTitle:@"Send"
                                                                                    textInputPlaceholder:options[@"reply"]];
        UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:@"replyCategory"
                                                                                  actions:@[ replyAction ]
                                                                        intentIdentifiers:@[]
                                                                                  options:UNNotificationCategoryOptionCustomDismissAction];
        [[UNUserNotificationCenter currentNotificationCenter] setNotificationCategories:[NSSet setWithObject:category]];
        content.categoryIdentifier = @"replyCategory";
    } else if (options[@"closeLabel"]) {
        // TODO: does this only make sense if we have options???
        // TODO: seems to hide any other actions
        NSLog(@"closeLabel");

        UNNotificationAction *closeAction = [UNNotificationAction actionWithIdentifier:@"close"
                                                                                 title:options[@"closeLabel"]
                                                                               options:UNNotificationActionOptionDestructive];
        UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:@"closeCategory"
                                                                                  actions:@[ closeAction ]
                                                                        intentIdentifiers:@[]
                                                                                  options:UNNotificationCategoryOptionCustomDismissAction];
        [[UNUserNotificationCenter currentNotificationCenter] setNotificationCategories:[NSSet setWithObject:category]];
        content.categoryIdentifier = @"closeCategory";
    }

    // TODO: if open or execute or action should we display the action button?
    // actionButtonTitle

    // Close button

    if (sound != nil) {
        content.sound = [sound isEqualToString:@"default"] ? [UNNotificationSound defaultSound] : [UNNotificationSound soundNamed:sound];
    }

    if (options[@"ignoreDnD"]) {
        [content setValue:@YES forKey:@"_shouldIgnoreDoNotDisturb"];
    }

    content.userInfo = options;

    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:options[@"uuid"] content:content trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                           withCompletionHandler:^(NSError *_Nullable error) {
                                                             if (error) {
                                                                 NSLog(@"addNotificationRequest -> send: %@", error);
                                                             }
                                                             [self delivered:request];
                                                             dispatch_group_leave(group);
                                                           }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}

- (void)userActivatedNotification:(UNNotificationResponse *)response;
{
    NSLog(@"userActivatedNotification");
    UNNotification *notification = response.notification;
    UNNotificationRequest *request = notification.request;
    UNNotificationContent *content = request.content;

    [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[ request.identifier ]];

    NSString *groupID = content.userInfo[@"groupID"];
    NSString *bundleID = content.userInfo[@"bundleID"];
    NSString *command = content.userInfo[@"command"];
    NSString *open = content.userInfo[@"open"];

    NSLog(@"User activated notification:");
    NSLog(@" group ID: %@", groupID);
    NSLog(@"    title: %@", content.title);
    NSLog(@" subtitle: %@", content.subtitle);
    NSLog(@"  message: %@", content.body);
    NSLog(@"bundle ID: %@", bundleID);
    NSLog(@"  command: %@", command);
    NSLog(@"     open: %@", open);

    [self outputJson:content.userInfo];

    BOOL success = YES;
    if (bundleID)
        success &= [self activateAppWithBundleID:bundleID];
    if (command)
        success &= [self executeShellCommand:command];
    if (open)
        success &= [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:open]];

    exit(success ? 0 : 1);
}

- (BOOL)activateAppWithBundleID:(NSString *)bundleID;
{
    id app = [SBApplication applicationWithBundleIdentifier:bundleID];
    if (app) {
        [app activate];
        return YES;

    } else {
        NSLog(@"Unable to find an application with the specified bundle indentifier");
        return NO;
    }
}

- (BOOL)executeShellCommand:(NSString *)command;
{
    NSPipe *pipe = [NSPipe pipe];
    NSFileHandle *fileHandle = [pipe fileHandleForReading];

    NSTask *task = [NSTask new];
    task.launchPath = @"/bin/sh";
    task.arguments = @[ @"-c", command ];
    task.standardOutput = pipe;
    task.standardError = pipe;
    [task launch];

    NSData *data = nil;
    NSMutableData *accumulatedData = [NSMutableData data];
    while ((data = [fileHandle availableData]) && [data length]) {
        [accumulatedData appendData:data];
    }

    [task waitUntilExit];
    NSLog(@"command output:\n%@", [[NSString alloc] initWithData:accumulatedData encoding:NSUTF8StringEncoding]);
    return [task terminationStatus] == 0;
}

// The method will be called on the delegate only if the application is in the foreground. If the method is not implemented or the handler is not called in a
// timely manner then the notification will not be presented. The application can choose to have the notification presented as a sound, badge, alert and/or in
// the notification list. This decision should be based on whether the information in the notification is otherwise visible to the user.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    // Notification arrived while the app was in foreground
    NSLog(@"willPresentNotification");

    // TODO: https://developer.apple.com/documentation/usernotifications/unnotificationpresentationoptions/alert?language=objc
    completionHandler(UNNotificationPresentationOptionAlert);
    // This argument will make the notification appear in foreground
}

// The method will be called on the delegate when the user responded to the notification by opening the application, dismissing the notification or choosing a
// UNNotificationAction. The delegate must be set before the application returns from application:didFinishLaunchingWithOptions:.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)())completionHandler {
    // Notification was tapped
    NSLog(@"didReceiveNotificationResponse");

    UNNotificationRequest *request = response.notification.request;
    if (![request.identifier isEqualToString:[self getUuid]]) {
        return;
    };

    if (response.actionIdentifier) {
        NSLog(@"action: %@", response.actionIdentifier);
    }
    [self outputJson:response.notification.request.content.userInfo];

    if ([response.actionIdentifier isEqualToString:UNNotificationDismissActionIdentifier]) {
        NSDictionary *udict = @{@"activationType" : @"closed", @"activationValue" : @"dismissed"};
        [self outputResponse:udict notification:request];

    } else if ([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
        NSLog(@"TODO: UNNotificationDefaultActionIdentifier");
        NSDictionary *udict = @{@"activationType" : @"closed", @"activationValue" : @"defaultAction"};
        [self outputResponse:udict notification:request];

    } else {
        NSDictionary *categoryActions = @{
            @"actionsCategory" : ^{
                NSArray *actions = request.content.userInfo[@"actions"];
                NSUInteger actionIndex = [actions indexOfObject:response.actionIdentifier];
                NSDictionary *udict = @{
                    @"activationType" : @"actionClicked",
                    @"activationValue" : actions[actionIndex],
                    @"activationValueIndex" : [NSString stringWithFormat:@"%lu", (unsigned long)actionIndex]
                };
                [self outputResponse:udict notification:request];
            },
            @"replyCategory": ^{
                UNTextInputNotificationResponse *text = (UNTextInputNotificationResponse *)response;
                NSDictionary *udict = @{@"activationType" : @"replied", @"activationValue" : text.userText};
                [self outputResponse:udict notification:request];
            },
            @"closeCategory": ^{
                NSLog(@"here 3c");
                NSDictionary *udict = @{@"activationType" : @"closed", @"activationValue" : request.content.userInfo[@"closeLabel"]};
                [self outputResponse:udict notification:request];
            }
        };

        if (request.content.categoryIdentifier) {
            NSLog(@"category: %@", request.content.categoryIdentifier);
        }

        void (^actionBlock)(void) = categoryActions[request.content.categoryIdentifier];
        if (actionBlock) {
            NSLog(@"here 3");
            actionBlock();
        } else {
            NSLog(@"NSUserNotificationActivationTypeNone");
            [self outputResponse:@{@"activationType" : @"none"} notification:request];
        }
    }

    [center removeDeliveredNotificationsWithIdentifiers:@[ request.identifier ]];
    completionHandler();
    exit(0);
}

- (void)delivered:(UNNotificationRequest *)request;
{
    NSLog(@"delivered");
    if (!request.content.userInfo[@"waitForResponse"]) {
        exit(0);
    }

    currentRequest = request;

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

    if (request.content.userInfo[@"timeout"] && [request.content.userInfo[@"timeout"] integerValue] > 0) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          NSLog(@"Timeout started");
          [NSThread sleepForTimeInterval:[request.content.userInfo[@"timeout"] integerValue]];
          [center removeDeliveredNotificationsWithIdentifiers:@[ currentRequest.identifier ]];
          NSDictionary *udict = @{@"activationType" : @"timeout"};
          [self outputResponse:udict notification:request];
          exit(0);
        });
    }
}

- (void)outputResponse:(NSDictionary *)udict notification:(UNNotificationRequest *)request;
{
    NSLog(@"quit");

    if ([request.content.userInfo[@"output"] isEqualToString:@"outputEvent"]) {
        if ([udict[@"activationType"] isEqualToString:@"closed"]) {
            if ([udict[@"activationValue"] isEqualToString:@""]) {
                printf("%s", "@CLOSED");
            } else {
                printf("%s", [udict[@"activationValue"] UTF8String]);
            }
        } else if ([udict[@"activationType"] isEqualToString:@"timeout"]) {
            printf("%s", "@TIMEOUT");
        } else if ([udict[@"activationType"] isEqualToString:@"contentsClicked"]) {
            printf("%s", "@CONTENTCLICKED");
        } else {
            if ([udict[@"activationValue"] isEqualToString:@""]) {
                printf("%s", "@ACTIONCLICKED");
            } else {
                printf("%s", [udict[@"activationValue"] UTF8String]);
            }
        }
        return;
    }

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss Z";

    // Dictionary with several key/value pairs and the above array of arrays
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict addEntriesFromDictionary:udict];
    //[dict setValue:[dateFormatter stringFromDate:notification.date] forKey:@"deliveredAt"];
    [dict setValue:[dateFormatter stringFromDate:[NSDate new]] forKey:@"activationAt"];

    [self outputJson:dict];
}

- (void)removeNotificationWithGroupID:(NSString *)groupID;
{
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *_Nonnull notifications) {
      for (UNNotification *notification in notifications) {
          if ([@"ALL" isEqualToString:groupID] || [notification.request.content.userInfo[@"groupID"] isEqualToString:groupID]) {
              [center removeDeliveredNotificationsWithIdentifiers:@[ notification.request.identifier ]];
          }
      }
      dispatch_group_leave(group);
    }];

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}

// This method lists all notifications delivered to the Notification Center
// that belong to the specified groupID. If the groupID argument is set to "ALL",
// then all notifications are listed. The method iterates through all delivered
// notifications and builds an array of dictionaries, where each dictionary
// represents a single notification and contains information such as its groupID,
// title, subtitle, message, and delivery time. If any notifications are found,
// the information is serialized to JSON format and printed to the console.
- (void)listNotificationWithGroupID:(NSString *)listGroupID;
{
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *_Nonnull notifications) {
      NSMutableArray *lines = [NSMutableArray array];
      for (UNNotification *notification in notifications) {
          NSString *deliveredgroupID = notification.request.content.userInfo[@"groupID"];
          NSString *title = notification.request.content.title;
          NSString *subtitle = notification.request.content.subtitle;
          NSString *message = notification.request.content.body;
          NSString *deliveredAt = [notification.date description];
          if ([@"ALL" isEqualToString:listGroupID] || [deliveredgroupID isEqualToString:listGroupID]) {
              NSMutableDictionary *dict = [NSMutableDictionary dictionary];
              [dict setValue:deliveredgroupID forKey:@"GroupID"];
              [dict setValue:title forKey:@"Title"];
              [dict setValue:subtitle forKey:@"subtitle"];
              [dict setValue:message forKey:@"message"];
              [dict setValue:deliveredAt forKey:@"deliveredAt"];
              [lines addObject:dict];
          }
      }

      if (lines.count > 0) {
          // TODO: switch to using to_json
          NSData *json;
          NSError *error = nil;
          // Dictionary convertable to JSON?
          if ([NSJSONSerialization isValidJSONObject:lines]) {
              // Serialize the dictionary
              json = [NSJSONSerialization dataWithJSONObject:lines options:NSJSONWritingPrettyPrinted error:&error];

              // If no errors, let's view the JSON
              if (json != nil && error == nil) {
                  NSString *jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
                  printf("%s", [jsonString cStringUsingEncoding:NSUTF8StringEncoding]);
              }
          }
      }
      dispatch_group_leave(group);
    }];

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    //    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    //        NSLog(@"done");
    //    });
}

// This method looks for a delivered notification with a UUID that matches the UUID of
// the current notification. When a matching notification is found, it is removed from
// the Notification Center using the removeDeliveredNotification method.
- (void)cleanup;
{
    NSLog(@"bye");

    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);

    NSString *UUID = currentRequest.identifier;
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *_Nonnull notifications) {
      for (UNNotification *nox in notifications) {
          if ([nox.request.identifier isEqualToString:UUID]) {
              [center removeDeliveredNotificationsWithIdentifiers:@[ nox.request.identifier ]];
          }
      }
      dispatch_group_leave(group);
    }];

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}

// Display the default help message
- (void)printHelpBanner;
{
    const char *appName = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"] UTF8String];
    const char *appVersion = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] UTF8String];
    printf("%s (%s) is a command-line tool to send macOS User Notifications from the command line.\n"
           "\n"
           "Usage: %s -[message|list|remove] [VALUE|ID|ID] [options]\n"
           "\n"
           "   Either of these is required (unless message data is piped to the tool):\n"
           "\n"
           "       -help              Display this help banner.\n"
           "       -version           Display terminal-notifier version.\n"
           "       -check             Check Notification enabled status and exit.\n"
           "       -message VALUE     The notification message.\n"
           "       -remove ID         Removes a notification with the specified ‘group’ ID.\n"
           "       -list ID           If the specified ‘group’ ID exists show when it was delivered,\n"
           "                          or use ‘ALL’ as ID to see all notifications.\n"
           "                          The output is a tab-separated list.\n"
           "\n"
           "   Optional:\n"
           "\n"
           "       -title VALUE       The notification title. Defaults to ‘Terminal’.\n"
           "       -subtitle VALUE    The notification subtitle.\n"
           "       -sound NAME        The name of a sound to play when the notification appears. The names are listed\n"
           "                          in Sound Preferences. Use 'default' for the default notification sound.\n"
           "       -group ID          A string which identifies the group the notifications belong to.\n"
           "       -sender ID         The bundle identifier of the application that should be shown as the sender, including its icon.\n"
           "       -contentImage URL  A file:// URL of a image to display attached to the notification\n"
           "       -activate ID       The bundle identifier of the application to activate when the user clicks the notification.\n"
           "       -open URL          The URL of a resource to open when the user clicks the notification.\n"
           "       -execute COMMAND   A shell command to perform when the user clicks the notification.\n"
           "       -actions ACTION[,ACTION] List of actions to display to user.\n"
           "       -reply             Ask for input.\n"
           "       -json              Output action choice or reply in json (vs text).\n"
           "       -timeout SECONDS   Time to wait for a response (with actions, or reply).\n"
           "       -ignoreDnD         Send notification even if Do Not Disturb is enabled.\n"
           "\n"
           "Note that in some circumstances the first character of a message has to be escaped in order to be recognized.\n"
           "An example of this is when using an open bracket, which has to be escaped like so: ‘\\[’.\n"
           "\n"
           "For more information see https://github.com/jklap/terminal-notifier\n",
           appName, appVersion, appName);
}

- (void)printVersion;
{
    const char *appName = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"] UTF8String];
    const char *appVersion = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] UTF8String];
    printf("%s %s\n", appName, appVersion);
}

- (NSString *)getUuid;
{ return [NSString stringWithFormat:@"%ld", self.hash]; }

// This method takes a URL as an argument and returns an NSImage object with the content.
// If the URL has no scheme, the method assumes that it is a file URL and prefixes it with 'file://'.
- (NSImage *)getImageFromURL:(NSString *)url;
{
    NSURL *imageURL = [NSURL URLWithString:url];
    if ([[imageURL scheme] length] == 0) {
        // Prefix 'file://' if no scheme
        imageURL = [NSURL fileURLWithPath:url];
    }
    return [[NSImage alloc] initWithContentsOfURL:imageURL];
}

/**
 * Decode fragment identifier
 *
 * @see http://tools.ietf.org/html/rfc3986#section-2.1
 * @see http://en.wikipedia.org/wiki/URI_scheme
 */
- (NSString *)decodeFragmentInURL:(NSString *)encodedURL fragment:(NSString *)framgent {
    NSString *beforeStr = [@"%23" stringByAppendingString:framgent];
    NSString *afterStr = [@"#" stringByAppendingString:framgent];
    NSString *decodedURL = [encodedURL stringByReplacingOccurrencesOfString:beforeStr withString:afterStr];
    return decodedURL;
}

- (void)outputJson:(NSDictionary *)dict;
{
    NSError *error = nil;
    NSData *json;

    // Dictionary convertable to JSON ?
    if ([NSJSONSerialization isValidJSONObject:dict]) {
        // Serialize the dictionary
        json = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];

        // If no errors, let's view the JSON
        if (json != nil && error == nil) {
            NSString *jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
            NSLog(@"%s", [jsonString cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
}

@end
