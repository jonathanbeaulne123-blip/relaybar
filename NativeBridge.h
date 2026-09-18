#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Public-API facilities and one explicitly opt-in private-API adapter.
// No key event injection, screen capture, chat scraping, or network access.
@interface RBBridge : NSObject
@property(nonatomic, copy, nullable) void (^launcherHandler)(void);
- (BOOL)registerLauncherHotKey;
- (void)unregisterLauncherHotKey;
+ (BOOL)accessibilityTrusted;
+ (void)requestAccessibility;
+ (NSDictionary<NSString *, NSString *> *)selectedTextForPID:(pid_t)pid NS_SWIFT_NAME(selectedText(forPID:));
+ (BOOL)overlayAvailable;
- (BOOL)presentOverlay:(NSTouchBar *)bar;
- (void)dismissOverlay;
@end

NS_ASSUME_NONNULL_END
