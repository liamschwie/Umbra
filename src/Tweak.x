#import <UIKit/UIKit.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "UmbraStore.h"

// Measured on iOS 16.2 (20C65). Every private selector below is validated at
// runtime before use; when one is missing we leave stock Messages alone.

#define UMBRA_ENTER_PHRASE @"open umbra"
#define UMBRA_LEAVE_PHRASE @"close umbra"

@interface CKConversation : NSObject
@property (nonatomic, readonly) NSString *uniqueIdentifier;
- (id)chat;
@end

@interface IMChat : NSObject
@property (nonatomic, retain) NSDate *muteUntilDate;
- (BOOL)isMuted;
@end

@interface CKConversationList : NSObject
+ (instancetype)sharedConversationList;
- (CKConversation *)conversationForExistingChatWithGUID:(NSString *)guid;
- (CKConversation *)conversationForExistingChatWithChatIdentifier:(NSString *)identifier;
@end

// One base class per search section. Several subclasses override the query
// producer, but all inherit -results. Section-specific implementations carry
// -chatGUIDForSearchableItem:, which bridges each raw searchable item back to
// a chat. Final CKSpotlightQueryResult objects carry their CKConversation.
@interface CKSearchController : NSObject
- (NSString *)chatGUIDForSearchableItem:(id)item;
// Authoritative read point: whatever produced a section's results and however
// they were stored, this is what serves them. It is declared on the base class,
// so hooking it here reaches every section.
- (id)results;
@end

@interface CKConversationSearchController : CKSearchController
@end

// Logos only forward-declares hooked classes, which is not enough to reach
// UIViewController members on `self`. Declared here with the measured shape.
@interface CKConversationListCollectionViewController : UIViewController
- (CKConversation *)conversationForItemIdentifier:(id)itemIdentifier;
- (id)generateSnapshot;
- (id)dataSource;
- (UISearchController *)searchController;
- (void)applyConversationListSnapshot:(id)snapshot
                 animatingDifferences:(BOOL)animating
                           completion:(id)completion;
- (void)updateSnapshotAnimatingDifferences:(BOOL)animating;
- (void)updateSnapshotAnimatingDifferences:(BOOL)animating
                                 completion:(void (^)(void))completion;
- (void)_updateContentUnavailableConfigurationUsingState:(id)state;
@end

#pragma mark - Runtime capability gate

/// Selectors Umbra cannot work without. Probed once; if any is absent on this
/// OS build we disable every behavior and Messages behaves exactly as stock.
static BOOL UmbraRuntimeUsable(void) {
    static BOOL usable = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class listVC = NSClassFromString(@"CKConversationListCollectionViewController");
        Class conv = NSClassFromString(@"CKConversation");
        if (!listVC || !conv) return;
        SEL required[] = {
            @selector(conversationForItemIdentifier:),
            @selector(generateSnapshot),
            // The stock refresh wrapper regenerates and commits the diffable
            // snapshot from ChatKit's current conversation model.
            @selector(updateSnapshotAnimatingDifferences:),
        };
        for (size_t i = 0; i < sizeof(required) / sizeof(*required); i++) {
            if (![listVC instancesRespondToSelector:required[i]]) return;
        }
        if (![conv instancesRespondToSelector:@selector(uniqueIdentifier)]) return;
        if (!NSClassFromString(@"NSDiffableDataSourceSnapshot")) return;
        usable = YES;
    });
    return usable;
}

/// Search is gated separately from the list. If these selectors go missing the
/// list side still works; folding them into UmbraRuntimeUsable would take the
/// whole tweak down instead.
static BOOL UmbraSearchUsable(void) {
    static BOOL usable = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class search = NSClassFromString(@"CKConversationSearchController");
        Class list = NSClassFromString(@"CKConversationList");
        if (!search || !list) return;
        if (![search instancesRespondToSelector:@selector(queryResultsForItems:)]) return;
        if (![search instancesRespondToSelector:@selector(chatGUIDForSearchableItem:)]) return;
        if (![list respondsToSelector:@selector(sharedConversationList)]) return;
        if (![list instancesRespondToSelector:@selector(conversationForExistingChatWithGUID:)]) return;
        usable = YES;
    });
    return usable;
}

#pragma mark - Hidden-mode state (per process, never persisted)

static BOOL gHiddenMode = NO;

/// The list controller that most recently applied a snapshot — i.e. the live
/// one. Weak: filter drill-downs push their own controller and pop it again.
static __weak UIViewController *gListVC = nil;

/// Updated at the snapshot choke point, before ChatKit evaluates its empty
/// state. ChatKit's model still contains every conversation, so its stock
/// availability calculation cannot describe the filtered snapshot by itself.
static BOOL gListHasVisibleConversations = NO;

/// Conversation identity for a snapshot item, or nil when the item is not a
/// conversation (onboarding cells, drop targets, filter banners).
static NSString *UmbraIdentifierForItem(id listVC, id itemIdentifier) {
    if (!itemIdentifier) return nil;
    CKConversation *conv = [listVC conversationForItemIdentifier:itemIdentifier];
    if (![conv respondsToSelector:@selector(uniqueIdentifier)]) return nil;
    NSString *uid = conv.uniqueIdentifier;
    return uid.length ? uid : nil;
}

static IMChat *UmbraChatForConversation(CKConversation *conv) {
    if (![conv respondsToSelector:@selector(chat)]) return nil;
    IMChat *chat = [conv chat];
    if (![chat respondsToSelector:@selector(setMuteUntilDate:)]) return nil;
    return chat;
}

/// Hide: remember identity, save the current alert state, then mute.
static void UmbraHideConversation(CKConversation *conv) {
    NSString *uid = conv.uniqueIdentifier;
    if (uid.length == 0) return;
    IMChat *chat = UmbraChatForConversation(conv);
    NSDate *previous = chat ? chat.muteUntilDate : nil;
    [[UmbraStore shared] hide:uid previousMuteUntilDate:previous];
    // distantFuture is how Messages itself expresses "muted indefinitely".
    if (chat) chat.muteUntilDate = [NSDate distantFuture];
}

/// Unhide: forget identity and put the previous alert state back exactly.
static void UmbraUnhideConversation(CKConversation *conv) {
    NSString *uid = conv.uniqueIdentifier;
    if (uid.length == 0) return;
    BOOL hadState = NO;
    NSDate *restore = [[UmbraStore shared] unhide:uid didHaveStoredState:&hadState];
    if (!hadState) return;
    IMChat *chat = UmbraChatForConversation(conv);
    if (chat) chat.muteUntilDate = restore;  // nil restores "not muted"
}

#pragma mark - Snapshot filtering

/// Removes items from `snapshot` by conversation identity. In normal mode the
/// hidden ones go; in hidden mode everything else goes. Filtering here — the
/// one point every list variant and the pinned section pass through — is what
/// keeps pinned rows, filter modes, and back-navigation consistent without
/// touching index paths.
static id UmbraFilteredSnapshot(id listVC, id snapshot) {
    if (!snapshot) return snapshot;
    if (!gHiddenMode && [[UmbraStore shared] hiddenCount] == 0) return snapshot;

    NSArray *items = [snapshot itemIdentifiers];
    if (items.count == 0) return snapshot;

    UmbraStore *store = [UmbraStore shared];
    NSMutableArray *drop = [NSMutableArray array];
    for (id item in items) {
        NSString *uid = UmbraIdentifierForItem(listVC, item);
        if (!uid) {
            // Not a conversation. Keep it in normal mode; in hidden mode drop
            // it so the hidden list shows conversations only.
            if (gHiddenMode) [drop addObject:item];
            continue;
        }
        BOOL hidden = [store isHidden:uid];
        if (hidden != gHiddenMode) [drop addObject:item];
    }
    if (drop.count == 0) return snapshot;

    id filtered = [snapshot copy];
    [filtered deleteItemsWithIdentifiers:drop];
    return filtered;
}

static BOOL UmbraSnapshotHasConversation(id listVC, id snapshot) {
    if (!snapshot || ![snapshot respondsToSelector:@selector(itemIdentifiers)]) return NO;
    for (id item in [snapshot itemIdentifiers]) {
        if (UmbraIdentifierForItem(listVC, item).length != 0) return YES;
    }
    return NO;
}

#pragma mark - Search filtering

/// Reads a string-valued accessor off `obj` if it has one. The identity a search
/// result carries is version-dependent — `chatGUIDForSearchableItem:` takes a raw
/// *searchable item*, not the *result object* that ends up in -results, and
/// assuming otherwise is what blanked search in 0.1.1-3 — so the accessor is
/// resolved by name at runtime rather than hardcoded.
static id UmbraObjectValue(id obj, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    // respondsToSelector: proves the selector exists, not that it returns an
    // object. Calling objc_msgSend with the wrong prototype is undefined on
    // arm64 — a struct- or scalar-returning method of the same name would hand
    // back a garbage register that isKindOfClass: then dereferences. Ask the
    // runtime for the actual return type first.
    Method m = class_getInstanceMethod([obj class], sel);
    if (!m || method_getTypeEncoding(m)[0] != '@') return nil;
    id value = nil;
    @try {
        id (*get)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        value = get(obj, sel);
    } @catch (__unused NSException *e) {
        return nil;
    }
    return value;
}

static NSString *UmbraStringValue(id obj, NSString *name) {
    id value = UmbraObjectValue(obj, name);
    if (![value isKindOfClass:[NSString class]]) return nil;
    return [value length] ? value : nil;
}

typedef NS_ENUM(NSInteger, UmbraSearchVisibility) {
    UmbraSearchVisibilityUnknown,
    UmbraSearchVisibilityVisible,
    UmbraSearchVisibilityHidden,
};

static UmbraSearchVisibility UmbraVisibilityForConversation(CKConversation *conv) {
    if (![conv respondsToSelector:@selector(uniqueIdentifier)])
        return UmbraSearchVisibilityUnknown;
    NSString *uid = conv.uniqueIdentifier;
    if (uid.length == 0) return UmbraSearchVisibilityUnknown;
    return [[UmbraStore shared] isHidden:uid]
        ? UmbraSearchVisibilityHidden : UmbraSearchVisibilityVisible;
}

/// Resolves either a raw searchable item or a final section result. The former
/// is the contract of -chatGUIDForSearchableItem:; final result classes vary by
/// section and OS. Every speculative private-API call is isolated so one bad
/// result can never turn a working search into an empty section.
static UmbraSearchVisibility UmbraSearchItemVisibility(id controller, id item) {
    UmbraStore *store = [UmbraStore shared];

    // This is the authoritative identity on iOS 16's CKSpotlightQueryResult
    // and CKZKWQueryResult. It also avoids passing a final result to the raw-
    // item accessor below.
    UmbraSearchVisibility directConversation = UmbraVisibilityForConversation(
        UmbraObjectValue(item, @"conversation"));
    if (directConversation != UmbraSearchVisibilityUnknown)
        return directConversation;

    // CKSpotlightQueryResult also retains the CSSearchableItem it wraps. Other
    // result types have no `item` accessor, in which case the object itself is
    // already the best candidate.
    id searchableItem = UmbraObjectValue(item, @"item") ?: item;

    // Some result types carry ChatKit's stable identifier directly. Only a
    // positive membership test is conclusive: a generic `uniqueIdentifier` can
    // instead be the identifier of a Core Spotlight result.
    NSArray<NSString *> *stableNames = @[
        @"chatIdentifier", @"pinningIdentifier", @"uniqueIdentifier"
    ];
    for (NSString *name in stableNames) {
        NSString *outerCandidate = UmbraStringValue(item, name);
        if ([store isHidden:outerCandidate]) return UmbraSearchVisibilityHidden;
        if (searchableItem != item) {
            NSString *innerCandidate = UmbraStringValue(searchableItem, name);
            if ([store isHidden:innerCandidate]) return UmbraSearchVisibilityHidden;
        }
    }

    NSString *guid = UmbraStringValue(item, @"chatGUID")
                   ?: UmbraStringValue(item, @"guid");
    if (guid.length == 0 &&
        [controller respondsToSelector:@selector(chatGUIDForSearchableItem:)]) {
        @try {
            guid = [(CKSearchController *)controller chatGUIDForSearchableItem:searchableItem];
            if (![guid isKindOfClass:[NSString class]]) guid = nil;
        } @catch (__unused NSException *e) {
            guid = nil;
        }
    }

    CKConversationList *list = [NSClassFromString(@"CKConversationList") sharedConversationList];
    if (guid.length != 0 &&
        [list respondsToSelector:@selector(conversationForExistingChatWithGUID:)]) {
        @try {
            UmbraSearchVisibility visibility = UmbraVisibilityForConversation(
                [list conversationForExistingChatWithGUID:guid]);
            if (visibility != UmbraSearchVisibilityUnknown) return visibility;
        } @catch (__unused NSException *e) {}
    }

    // `chatIdentifier` is a separate identity domain on some result classes.
    NSString *chatIdentifier = UmbraStringValue(item, @"chatIdentifier")
                             ?: UmbraStringValue(searchableItem, @"chatIdentifier");
    if (chatIdentifier.length != 0 &&
        [list respondsToSelector:@selector(conversationForExistingChatWithChatIdentifier:)]) {
        @try {
            return UmbraVisibilityForConversation(
                [list conversationForExistingChatWithChatIdentifier:chatIdentifier]);
        } @catch (__unused NSException *e) {}
    }

    return UmbraSearchVisibilityUnknown;
}

static id UmbraFilteredResults(id controller, id results) {
    if (!UmbraSearchUsable()) return results;
    // Unlike the snapshot filter, this one is fail-closed, so an empty hidden
    // set must short-circuit in *both* modes. Falling through in hidden mode
    // with nothing hidden would drop every result in every section, and there
    // is nothing to protect in that state.
    if ([[UmbraStore shared] hiddenCount] == 0) return results;
    // NSArray is the measured shape for every section that carries results. An
    // unfamiliar container passes through unfiltered.
    if (![results isKindOfClass:[NSArray class]]) return results;

    NSArray *items = results;
    if (items.count == 0) return results;

    NSMutableArray *keep = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        UmbraSearchVisibility visibility = UmbraSearchItemVisibility(controller, item);
        BOOL shouldKeep = NO;
        if (visibility == UmbraSearchVisibilityUnknown) {
            // Closed Umbra must preserve ordinary search when a new result type
            // cannot be mapped. Open Umbra stays fail-closed: an unknown result
            // must not expose content from outside the hidden set.
            shouldKeep = !gHiddenMode;
        } else {
            shouldKeep = ((visibility == UmbraSearchVisibilityHidden) == gHiddenMode);
        }
        if (shouldKeep) [keep addObject:item];
    }
    return keep.count == items.count ? results : keep;
}

#pragma mark - Hidden-mode entry / exit

/// iOS 16's private precursor to UIContentUnavailableConfiguration can retain
/// the "No Messages" view produced by an empty hidden snapshot. Once the next
/// filtered snapshot contains a conversation, nil is the only correct content-
/// unavailable configuration. Selector checks keep this harmless on versions
/// that implement the empty state differently.
static void UmbraClearStaleEmptyState(UIViewController *listVC) {
    if (gHiddenMode || !gListHasVisibleConversations || listVC != gListVC) return;
    SEL setters[] = {
        // This is the exact selector used by ChatKit on iOS 16.2. Prefer it to
        // the later public spelling because they are not guaranteed to share
        // backing state on prerelease UIKit implementations.
        NSSelectorFromString(@"_setContentUnavailableConfiguration:"),
        NSSelectorFromString(@"setContentUnavailableConfiguration:"),
    };
    NSString *getters[] = {
        @"_contentUnavailableConfiguration",
        @"contentUnavailableConfiguration",
    };
    for (size_t i = 0; i < sizeof(setters) / sizeof(*setters); i++) {
        SEL setter = setters[i];
        if (![listVC respondsToSelector:setter]) continue;
        // Avoid turning viewDidLayoutSubviews into a layout feedback loop once
        // the stale configuration is already gone.
        if (UmbraObjectValue(listVC, getters[i]) == nil) break;
        @try {
            void (*set)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
            set(listVC, setter, nil);
        } @catch (__unused NSException *e) {}
        break;
    }
}

/// Refresh through Apple's snapshot generator. The completion overload matters:
/// iOS 16.2 does not update content-unavailable state inside this wrapper, and
/// an animated diffable apply commits later. Clearing the stale configuration
/// only before this completion races with that commit.
static void UmbraRefreshList(void) {
    UIViewController *listVC = gListVC;
    SEL completionSelector =
        @selector(updateSnapshotAnimatingDifferences:completion:);
    if ([listVC respondsToSelector:completionSelector]) {
        __weak UIViewController *weakListVC = listVC;
        [(id)listVC updateSnapshotAnimatingDifferences:YES completion:^{
            UIViewController *strongListVC = weakListVC;
            UmbraClearStaleEmptyState(strongListVC);
            // UIKit can schedule its availability update in the same commit.
            // Recheck on the following main-loop turn after those callbacks.
            dispatch_async(dispatch_get_main_queue(), ^{
                UmbraClearStaleEmptyState(weakListVC);
            });
        }];
    } else if ([listVC respondsToSelector:@selector(updateSnapshotAnimatingDifferences:)]) {
        [(id)listVC updateSnapshotAnimatingDifferences:YES];
    }

    // applyConversationListSnapshot: is entered synchronously and updates
    // gListHasVisibleConversations before the diffable data source commits.
    // Clear the already-visible stale placeholder now, then once more after
    // queued state/layout callbacks even if ChatKit skips a redundant apply and
    // therefore never invokes its completion block.
    UmbraClearStaleEmptyState(listVC);
    dispatch_async(dispatch_get_main_queue(), ^{
        UmbraClearStaleEmptyState(listVC);
    });
}

/// The only writer of gHiddenMode. Every flip refreshes, so no path can leave
/// the flag and the visible list disagreeing.
static void UmbraSetHiddenMode(BOOL on) {
    if (gHiddenMode == on) return;
    gHiddenMode = on;
    UmbraRefreshList();
}

/// Biometric gate. Only consulted on the way *in*, and only when the user has
/// turned it on — leaving hidden mode must never be blocked.
static void UmbraEnterHiddenMode(void) {
    if (![[UmbraStore shared] requireAuthentication]) {
        UmbraSetHiddenMode(YES);
        return;
    }
    LAContext *ctx = [[LAContext alloc] init];
    NSError *err = nil;
    LAPolicy policy = LAPolicyDeviceOwnerAuthentication;
    if (![ctx canEvaluatePolicy:policy error:&err]) {
        // No biometrics or passcode configured: fail closed, stay out.
        return;
    }
    [ctx evaluatePolicy:policy
        localizedReason:@"Show hidden conversations"
                  reply:^(BOOL success, NSError *error) {
        if (!success) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            UmbraSetHiddenMode(YES);
        });
    }];
}

/// Normalized phrase match: trimmed, case- and diacritic-insensitive, so the
/// trigger fires on the complete phrase without needing Return.
static BOOL UmbraPhraseMatches(NSString *text, NSString *phrase) {
    if (!text) return NO;
    NSString *normalized = [[text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]]
        stringByFoldingWithOptions:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)
                            locale:[NSLocale currentLocale]];
    return [normalized isEqualToString:phrase];
}

/// Complete the same public UISearchController transition as tapping Cancel.
/// Clearing text and resigning the search bar only stop the query and keyboard;
/// they do not dismiss the results controller or restore the conversation list.
static void UmbraDismissSearch(id listVC, UISearchBar *searchBar) {
    [searchBar resignFirstResponder];
    if (![listVC respondsToSelector:@selector(searchController)]) return;
    UISearchController *searchController = [listVC searchController];
    if (![searchController isKindOfClass:[UISearchController class]]) return;
    if (searchController.isActive) searchController.active = NO;
}

#pragma mark - Conversation list

%hook CKConversationListCollectionViewController

- (void)applyConversationListSnapshot:(id)snapshot
                 animatingDifferences:(BOOL)animating
                           completion:(id)completion {
    if (!UmbraRuntimeUsable()) {
        %orig;
        return;
    }
    // Whoever is applying snapshots is the list the user is looking at.
    gListVC = self;
    id filtered = snapshot;
    @try {
        filtered = UmbraFilteredSnapshot(self, snapshot);
    } @catch (__unused NSException *e) {
        // Never let a filtering failure blank the inbox.
        filtered = snapshot;
    }
    @try {
        gListHasVisibleConversations = UmbraSnapshotHasConversation(self, filtered);
    } @catch (__unused NSException *e) {
        // If the snapshot shape changed, do not interfere with Apple's empty
        // state. The list itself has already fallen back to the stock snapshot.
        gListHasVisibleConversations = NO;
    }
    %orig(filtered, animating, completion);
}

- (void)_updateContentUnavailableConfigurationUsingState:(id)state {
    %orig;
    UmbraClearStaleEmptyState(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    // Last line of defense for updates UIKit schedules after the diffable data
    // source completion. This is a no-op in hidden mode and for a truly empty
    // normal inbox.
    UmbraClearStaleEmptyState(self);
}

- (id)leadingSwipeActionsConfigurationForIndexPath:(NSIndexPath *)indexPath {
    UISwipeActionsConfiguration *config = %orig;
    if (!UmbraRuntimeUsable() || !config) return config;

    id item = nil;
    if ([self respondsToSelector:@selector(dataSource)]) {
        id ds = [self dataSource];
        if ([ds respondsToSelector:@selector(itemIdentifierForIndexPath:)])
            item = [ds itemIdentifierForIndexPath:indexPath];
    }
    if (!item) return config;

    CKConversation *conv = [self conversationForItemIdentifier:item];
    NSString *uid = [conv respondsToSelector:@selector(uniqueIdentifier)] ? conv.uniqueIdentifier : nil;
    if (uid.length == 0) return config;

    BOOL hidden = [[UmbraStore shared] isHidden:uid];
    NSString *title = hidden ? @"Unhide" : @"Hide";
    NSString *symbol = hidden ? @"eye" : @"eye.slash";

    UIContextualAction *action = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:title
                          handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        if (hidden) UmbraUnhideConversation(conv);
        else UmbraHideConversation(conv);
        done(YES);
        // Let the stock diffable data source animate the row out.
        UmbraRefreshList();
    }];
    action.image = [UIImage systemImageNamed:symbol];
    action.backgroundColor = [UIColor systemIndigoColor];

    // Append rather than replace, so Apple's own actions survive intact.
    NSMutableArray *actions = [config.actions mutableCopy];
    [actions addObject:action];
    UISwipeActionsConfiguration *merged =
        [UISwipeActionsConfiguration configurationWithActions:actions];
    merged.performsFirstActionWithFullSwipe = config.performsFirstActionWithFullSwipe;
    return merged;
}

// Pinned rows get no swipe actions from Apple, so Hide reaches them through
// the context menu instead — inserted directly beneath Unpin.
- (id)_topLevelMenuForItemIdentifier:(id)itemIdentifier
                           inSection:(NSInteger)section
                            withCell:(id)cell {
    UIMenu *menu = %orig;
    if (!UmbraRuntimeUsable() || ![menu isKindOfClass:[UIMenu class]]) return menu;

    CKConversation *conv = [self conversationForItemIdentifier:itemIdentifier];
    NSString *uid = [conv respondsToSelector:@selector(uniqueIdentifier)] ? conv.uniqueIdentifier : nil;
    if (uid.length == 0) return menu;

    BOOL hidden = [[UmbraStore shared] isHidden:uid];
    UIAction *action = [UIAction actionWithTitle:(hidden ? @"Unhide" : @"Hide")
                                           image:[UIImage systemImageNamed:(hidden ? @"eye" : @"eye.slash")]
                                      identifier:@"com.liam.umbra.toggle"
                                         handler:^(__unused UIAction *a) {
        if (hidden) UmbraUnhideConversation(conv);
        else UmbraHideConversation(conv);
        UmbraRefreshList();
    }];

    // Stock shape is a top-level menu wrapping one inline submenu whose first
    // action is Pin/Unpin. Insert at index 1: under Pin/Unpin, above Mark as
    // Unread. If that shape ever differs, leave the menu untouched.
    NSArray *top = menu.children;
    if (top.count != 1 || ![top.firstObject isKindOfClass:[UIMenu class]]) return menu;
    UIMenu *inner = top.firstObject;
    NSArray *innerChildren = inner.children;
    if (innerChildren.count < 1) return menu;

    NSMutableArray *rebuilt = [innerChildren mutableCopy];
    [rebuilt insertObject:action atIndex:1];
    UIMenu *newInner = [inner menuByReplacingChildren:rebuilt];
    return [menu menuByReplacingChildren:@[newInner]];
}

#pragma mark Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    if (UmbraRuntimeUsable()) {
        BOOL enter = !gHiddenMode && UmbraPhraseMatches(text, UMBRA_ENTER_PHRASE);
        BOOL leave = gHiddenMode && UmbraPhraseMatches(text, UMBRA_LEAVE_PHRASE);
        if (enter || leave) {
            // Clearing the field does not re-enter this delegate method, so
            // Messages only learns the query is gone if we forward the cleared
            // text ourselves. Swallowing %orig left the search stack still
            // holding the phrase as its live query: results were never torn
            // down, and the list came back from under a half-collapsed search
            // presentation without its content-unavailable state being
            // re-evaluated — stranding the "No Messages" placeholder from an
            // empty hidden list on top of the restored conversations.
            searchBar.text = @"";
            %orig(searchBar, @"");
            UmbraDismissSearch(self, searchBar);
            // Flip after the teardown so our refresh is the last write to the
            // list, not something Apple's search dismissal overwrites.
            if (enter) UmbraEnterHiddenMode();
            else UmbraSetHiddenMode(NO);
            return;
        }
    }
    %orig;
}

- (void)viewDidLoad {
    %orig;
    if (!UmbraRuntimeUsable()) return;

    UINavigationBar *bar = self.navigationController.navigationBar;
    if (!bar) return;

    // "Double-tap and hold": one tap, then a second touch that stays down.
    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(umbra_titleGesture:)];
    gesture.numberOfTapsRequired = 1;
    gesture.minimumPressDuration = 0.45;
    // Do not swallow touches meant for bar button items.
    gesture.cancelsTouchesInView = NO;
    [bar addGestureRecognizer:gesture];
}

%new
- (void)umbra_titleGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    // Only the title area, so this cannot shadow Edit / Compose.
    UINavigationBar *bar = (UINavigationBar *)gesture.view;
    CGPoint point = [gesture locationInView:bar];
    CGFloat inset = bar.bounds.size.width * 0.25;
    if (point.x < inset || point.x > bar.bounds.size.width - inset) return;

    gListVC = self;
    if (gHiddenMode) UmbraSetHiddenMode(NO);
    else UmbraEnterHiddenMode();
}

%end

#pragma mark - Search results must never surface hidden threads

// The Conversations section. Overrides -queryResultsForItems:, so hooking the
// base class alone would miss it.
%hook CKConversationSearchController

- (id)queryResultsForItems:(id)items {
    id filteredItems = items;
    @try {
        filteredItems = UmbraFilteredResults(self, items);
    } @catch (__unused NSException *e) {
        filteredItems = items;
    }
    id results = %orig(filteredItems);
    @try {
        return UmbraFilteredResults(self, results);
    } @catch (__unused NSException *e) {
        return results;
    }
}

%end

// Keep the base producer covered for sections that do not override it. Section
// overrides are still protected by the inherited -results getter below.
// Double-filtering through a super call is harmless: the predicate is
// idempotent.
%hook CKSearchController

- (id)queryResultsForItems:(id)items {
    id filteredItems = items;
    @try {
        filteredItems = UmbraFilteredResults(self, items);
    } @catch (__unused NSException *e) {
        filteredItems = items;
    }
    id results = %orig(filteredItems);
    @try {
        return UmbraFilteredResults(self, results);
    } @catch (__unused NSException *e) {
        return results;
    }
}

// Belt to the -queryResultsForItems: braces, and the load-bearing one.
// -queryResultsForItems: is only one of several producers a section can use
// (CKConversationSearchController also carries -tokenizedQueryResultsForItems:
// and -_sortedAndRankedItemsWithItems:).
//
// Filtering the *getter* rather than -setResults: is deliberate: Apple is free
// to assign the backing ivar directly, and a setter hook never sees that. The
// getter is what every reader actually gets. Corroborated by covertck, the
// shipped iOS 13/14 tweak — its stripped dylib references -results and
// -searchResults and neither -queryResultsForItems: nor -setResults:.
//
// ponytail: re-filters on every read. Fine at the 102-result scale measured in
// compat-map.md; if search scrolling stutters, memoize against the identity of
// the unfiltered array.
- (id)results {
    id results = %orig;
    @try {
        return UmbraFilteredResults(self, results);
    } @catch (__unused NSException *e) {
        return results;
    }
}

%end

#pragma mark - Leave hidden mode when Messages backgrounds

%hook UIApplication

- (void)_applicationDidEnterBackground {
    // Through the single writer, so the list is rebuilt too — clearing the flag
    // on its own left hidden-mode content on screen after the app returned.
    if (gHiddenMode && [[UmbraStore shared] exitHiddenModeOnBackground])
        UmbraSetHiddenMode(NO);
    %orig;
}

%end

%ctor {
    // Only ever run inside Messages.
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (![bundleID isEqualToString:@"com.apple.MobileSMS"]) return;
    %init;
}
