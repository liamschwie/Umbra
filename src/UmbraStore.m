#import "UmbraStore.h"

static NSString *const kHiddenKey = @"com.liam.umbra.hidden";
static NSString *const kAlertKey = @"com.liam.umbra.alertState";
static NSString *const kPrefsDomain = @"com.liam.umbra";

/// Stand-in for "this conversation was not muted before we hid it". NSDate is
/// the stored type and a plist dictionary cannot hold nil, so unmuted is
/// recorded as distantPast and mapped back to nil on read.
static NSDate *UmbraUnmutedSentinel(void) {
    return [NSDate distantPast];
}

@implementation UmbraStore {
    NSMutableSet<NSString *> *_hidden;
    NSMutableDictionary<NSString *, NSDate *> *_alertState;
}

+ (instancetype)shared {
    static UmbraStore *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSArray *h = [d arrayForKey:kHiddenKey];
        _hidden = h ? [NSMutableSet setWithArray:h] : [NSMutableSet set];
        NSDictionary *a = [d dictionaryForKey:kAlertKey];
        _alertState = a ? [a mutableCopy] : [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)_flush {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:_hidden.allObjects forKey:kHiddenKey];
    [d setObject:_alertState forKey:kAlertKey];
}

- (BOOL)isHidden:(NSString *)identifier {
    if (identifier.length == 0) return NO;
    @synchronized (self) { return [_hidden containsObject:identifier]; }
}

- (NSUInteger)hiddenCount {
    @synchronized (self) { return _hidden.count; }
}

- (void)hide:(NSString *)identifier previousMuteUntilDate:(NSDate *)muteUntilDate {
    if (identifier.length == 0) return;
    @synchronized (self) {
        [_hidden addObject:identifier];
        _alertState[identifier] = muteUntilDate ?: UmbraUnmutedSentinel();
        [self _flush];
    }
}

- (NSDate *)unhide:(NSString *)identifier didHaveStoredState:(BOOL *)outWasStored {
    if (outWasStored) *outWasStored = NO;
    if (identifier.length == 0) return nil;
    @synchronized (self) {
        NSDate *saved = _alertState[identifier];
        if (outWasStored) *outWasStored = (saved != nil);
        [_hidden removeObject:identifier];
        [_alertState removeObjectForKey:identifier];
        [self _flush];
        if ([saved isEqualToDate:UmbraUnmutedSentinel()]) return nil;
        return saved;
    }
}

#pragma mark - Preferences

- (BOOL)_boolPref:(NSString *)key default:(BOOL)fallback {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)kPrefsDomain);
    if (!v) return fallback;
    BOOL result = fallback;
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) result = CFBooleanGetValue(v);
    else if (CFGetTypeID(v) == CFNumberGetTypeID()) result = [(__bridge NSNumber *)v boolValue];
    CFRelease(v);
    return result;
}

- (BOOL)requireAuthentication { return [self _boolPref:@"requireAuthentication" default:NO]; }
- (BOOL)exitHiddenModeOnBackground { return [self _boolPref:@"exitHiddenModeOnBackground" default:YES]; }

@end
