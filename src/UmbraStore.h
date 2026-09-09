#import <Foundation/Foundation.h>

/// Persistent hidden-conversation state.
///
/// Two storage domains, deliberately:
///   * The hidden set and saved alert states live in MobileSMS's own
///     NSUserDefaults. Only injected code touches them, so there is no
///     cross-process sandbox question and they survive termination,
///     respring, and reboot for free.
///   * User preferences (authentication and background behavior) live in
///     com.liam.umbra via CFPreferences, because Settings.app writes them.
///
/// Nothing here ever stores message contents or participant information —
/// only opaque conversation identifiers.
@interface UmbraStore : NSObject

+ (instancetype)shared;

- (BOOL)isHidden:(NSString *)identifier;
- (NSUInteger)hiddenCount;

/// Records `identifier` as hidden and remembers `muteUntilDate` (may be nil,
/// meaning "was not muted") so it can be put back on unhide.
- (void)hide:(NSString *)identifier previousMuteUntilDate:(NSDate *)muteUntilDate;

/// Forgets `identifier`. Returns the alert state saved at hide time by way of
/// `outWasStored`, which is NO when we have no record (restore nothing then).
- (NSDate *)unhide:(NSString *)identifier didHaveStoredState:(BOOL *)outWasStored;

// Preferences (com.liam.umbra).
@property (nonatomic, readonly) BOOL requireAuthentication;
@property (nonatomic, readonly) BOOL exitHiddenModeOnBackground;

@end
