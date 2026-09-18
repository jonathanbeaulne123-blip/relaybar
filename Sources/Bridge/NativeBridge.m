#import "NativeBridge.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <objc/message.h>
#import <dlfcn.h>

// Selectors are looked up at runtime. There is deliberately no private-framework
// link dependency. This adapter is never invoked automatically at app startup.
static SEL RBPresentSelector(void) {
    for (NSString *name in @[@"presentSystemModalTouchBar:systemTrayItemIdentifier:",
                             @"presentSystemModalFunctionBar:systemTrayItemIdentifier:"]) {
        SEL selector = NSSelectorFromString(name);
        if ([NSTouchBar respondsToSelector:selector]) return selector;
    }
    return NULL;
}
static SEL RBDismissSelector(void) {
    for (NSString *name in @[@"dismissSystemModalTouchBar:", @"dismissSystemModalFunctionBar:"]) {
        SEL selector = NSSelectorFromString(name);
        if ([NSTouchBar respondsToSelector:selector]) return selector;
    }
    return NULL;
}

typedef void (*RBSetPresence)(NSString *, BOOL);
static NSString *const RBTrayIdentifier = @"local.relaybar.control";

@interface RBBridge () {
    EventHotKeyRef _hotKey;
    EventHandlerRef _hotKeyHandler;
    NSTouchBar *_overlay;
    NSCustomTouchBarItem *_trayItem;
    void *_dfrHandle;
    RBSetPresence _setPresence;
}
- (void)invokeLauncher;
@end

static OSStatus RBHotKeyCallback(EventHandlerCallRef next, EventRef event, void *context) {
    EventHotKeyID identity;
    OSStatus result = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                                       NULL, sizeof(identity), NULL, &identity);
    if (result != noErr || identity.signature != 'RBar' || identity.id != 1) return eventNotHandledErr;
    RBBridge *bridge = (__bridge RBBridge *)context;
    [bridge invokeLauncher];
    return noErr;
}

@implementation RBBridge
- (BOOL)registerLauncherHotKey {
    [self unregisterLauncherHotKey];
    EventTypeSpec specification = { kEventClassKeyboard, kEventHotKeyPressed };
    OSStatus result = InstallEventHandler(GetApplicationEventTarget(), RBHotKeyCallback, 1,
                                         &specification, (__bridge void *)self, &_hotKeyHandler);
    if (result != noErr) return NO;
    EventHotKeyID identity = { 'RBar', 1 };
    result = RegisterEventHotKey(kVK_Space, controlKey | optionKey | cmdKey, identity,
                                GetApplicationEventTarget(), 0, &_hotKey);
    if (result != noErr) { [self unregisterLauncherHotKey]; return NO; }
    return YES;
}
- (void)unregisterLauncherHotKey {
    if (_hotKey) { UnregisterEventHotKey(_hotKey); _hotKey = NULL; }
    if (_hotKeyHandler) { RemoveEventHandler(_hotKeyHandler); _hotKeyHandler = NULL; }
}
- (void)invokeLauncher { if (self.launcherHandler) self.launcherHandler(); }

+ (BOOL)accessibilityTrusted { return AXIsProcessTrusted(); }
+ (void)requestAccessibility {
    NSDictionary *options = @{ (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES };
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}
+ (NSDictionary<NSString *, NSString *> *)selectedTextForPID:(pid_t)pid {
    if (!AXIsProcessTrusted()) return @{ @"error": @"Selected-text capture needs Accessibility permission. You can use the explicit Use clipboard button instead." };
    if (pid <= 0) return @{ @"error": @"No source application is available. Select text in another app, then reopen RelayBar." };
    AXUIElementRef application = AXUIElementCreateApplication(pid);
    AXUIElementSetMessagingTimeout(application, 0.35f);
    CFTypeRef focusedValue = NULL;
    AXError result = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute, &focusedValue);
    CFRelease(application);
    if (result != kAXErrorSuccess || !focusedValue) return @{ @"error": @"The source app did not expose a focused text element. Copy the desired passage yourself, then choose Use clipboard." };
    if (CFGetTypeID(focusedValue) != AXUIElementGetTypeID()) {
        CFRelease(focusedValue);
        return @{ @"error": @"The source app returned an unsupported focused element." };
    }
    AXUIElementRef focused = (AXUIElementRef)focusedValue;
    AXUIElementSetMessagingTimeout(focused, 0.35f);
    CFTypeRef subrole = NULL;
    if (AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute, &subrole) == kAXErrorSuccess && subrole) {
        if (CFGetTypeID(subrole) == CFStringGetTypeID()) {
            NSString *value = (__bridge NSString *)subrole;
            BOOL secure = [value localizedCaseInsensitiveContainsString:@"secure"] ||
                          [value localizedCaseInsensitiveContainsString:@"password"];
            if (secure) {
                CFRelease(subrole); CFRelease(focusedValue);
                return @{ @"error": @"RelayBar refuses to capture secure or password fields." };
            }
        }
        CFRelease(subrole);
    }
    CFTypeRef selection = NULL;
    result = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute, &selection);
    CFRelease(focusedValue);
    if (result != kAXErrorSuccess || !selection) return @{ @"error": @"No selected text was exposed. Select a passage, or use Copy followed by Use clipboard. Whole documents are never read as a fallback." };
    if (CFGetTypeID(selection) != CFStringGetTypeID()) {
        CFRelease(selection);
        return @{ @"error": @"The selection was not plain text." };
    }
    NSString *text = CFBridgingRelease(selection);
    if (text.length == 0) return @{ @"error": @"The selection is empty. Select some text first." };
    // UTF-16 upper bound before Swift validates the user-facing character limit.
    if (text.length > 120000) return @{ @"error": @"The selection is too large. Choose a shorter passage; nothing was truncated." };
    return @{ @"text": text };
}

+ (BOOL)overlayAvailable { return RBPresentSelector() != NULL && RBDismissSelector() != NULL; }
- (BOOL)presentOverlay:(NSTouchBar *)bar {
    if (![RBBridge overlayAvailable]) return NO;
    if (_overlay == bar) return YES;
    [self dismissOverlay];
    @try {
        // The tray icon is optional. The modal bar can still be requested without it.
        SEL add = NSSelectorFromString(@"addSystemTrayItem:");
        SEL remove = NSSelectorFromString(@"removeSystemTrayItem:");
        if ([NSTouchBarItem respondsToSelector:add] && [NSTouchBarItem respondsToSelector:remove]) {
            _trayItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:RBTrayIdentifier];
            _trayItem.view = [NSButton buttonWithTitle:@"RB" target:self action:@selector(invokeLauncher)];
            ((void (*)(id, SEL, id))objc_msgSend)([NSTouchBarItem class], add, _trayItem);
            if (!_dfrHandle) {
                _dfrHandle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY | RTLD_LOCAL);
                if (_dfrHandle) _setPresence = (RBSetPresence)dlsym(_dfrHandle, "DFRElementSetControlStripPresenceForIdentifier");
            }
            if (_setPresence) _setPresence(RBTrayIdentifier, YES);
        }
        _overlay = bar;
        SEL placementSel = NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:");
        if ([NSTouchBar respondsToSelector:placementSel]) {
            ((void (*)(id, SEL, id, long long, id))objc_msgSend)([NSTouchBar class], placementSel, bar, 1, nil);
        } else {
            ((void (*)(id, SEL, id, id))objc_msgSend)([NSTouchBar class], RBPresentSelector(), bar, nil);
        }
        return YES; // Request accepted; not proof of physical hardware rendering.
    } @catch (NSException *exception) {
        [self dismissOverlay];
        return NO;
    }
}
- (void)dismissOverlay {
    @try {
        if (_overlay && RBDismissSelector())
            ((void (*)(id, SEL, id))objc_msgSend)([NSTouchBar class], RBDismissSelector(), _overlay);
        if (_setPresence) _setPresence(RBTrayIdentifier, NO);
        SEL remove = NSSelectorFromString(@"removeSystemTrayItem:");
        if (_trayItem && [NSTouchBarItem respondsToSelector:remove])
            ((void (*)(id, SEL, id))objc_msgSend)([NSTouchBarItem class], remove, _trayItem);
    } @catch (NSException *exception) {
        // Private API failure must not terminate the normal public-API panel.
    }
    _overlay = nil; _trayItem = nil;
}
- (void)dealloc {
    [self unregisterLauncherHotKey];
    [self dismissOverlay];
    if (_dfrHandle) dlclose(_dfrHandle);
}
@end
