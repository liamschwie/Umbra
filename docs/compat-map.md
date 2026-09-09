# Umbra — Compatibility Map

Measured on device, not inferred:

| | |
|---|---|
| Device | iPhone SE 2 (iPhone12,8), arm64e |
| OS | iOS 16.2, build 20C65 |
| Jailbreak | Dopamine 3 (roothide), rootless, ElleKit, jbroot shadows `/`, real root at `/rootfs` |
| Messages | `/rootfs/Applications/MobileSMS.app/MobileSMS`, `com.apple.MobileSMS` |
| Probe method | Frida 17.16.4 attach to live process, read-only |

Raw probe output: `probe/dump16.txt`, `probe/live16.txt`, `probe/swipe16.txt`.
All probes redact identifiers to a hash — no participant data or message
content was read or logged at any point.

---

## The six rows

| Role | Component | Notes |
|---|---|---|
| **Conversation identifier** | `CKConversation.uniqueIdentifier` | Service-independent. See below. |
| **Normal-list snapshots** | `-[CKConversationListCollectionViewController applyConversationListSnapshot:animatingDifferences:completion:]` | Single choke point for every list variant. |
| **Pinned items** | Same snapshot, section `3` | Pinned entries are ordinary items in the same `NSDiffableDataSourceSnapshot`. |
| **Search results** | `-[CKSearchController results]` (getter), plus `-queryResultsForItems:` as a belt | Separate pipeline from the list. See below. |
| **Swipe actions** | `-leadingSwipeActionsConfigurationForIndexPath:` | Leading == swipe-right. **Returns `nil` for pinned.** |
| **Alert state** | `IMChat.muteUntilDate` / `-setMuteUntilDate:` / `isMuted` | `muteUntilDate` is the full state — save and restore this exact value. |

---

## Identifier choice: `uniqueIdentifier`, not `guid`

The probe compared all candidates across an iMessage thread and an SMS thread:

```
conv 0 (iMessage)   conv 1 (SMS)
uniqueIdentifier    len 12          len 12
chatIdentifier      len 12          len 12      (identical to uniqueIdentifier)
identifier          len 12          len 12      (identical)
persistentID        len 12          len 12      (identical)
pinningIdentifier   len 12          len 12      (identical)
guid                iMessage;..;#…  SMS;..;#…   <-- encodes service
groupID             len 36 UUID     len 36 UUID
```

`guid` carries the service prefix and changes when a thread flips between
iMessage and SMS. `uniqueIdentifier` does not. It is also byte-identical to
`pinningIdentifier` — the value Apple itself persists to keep pins alive across
reboots. Adopting it gives Umbra exactly Apple's own persistence semantics for
free, which is the strongest available evidence that it is the right stable key.

Lookup back to a conversation: `CKConversationList.conversationForExistingChatWithPinningIdentifier:`.

**Known limit:** for group chats `uniqueIdentifier` is a `chat…` identifier that
can be reissued if the group is re-created. A hidden group that Messages
re-keys would reappear. `groupID` is more durable for groups but absent for
1:1. Handling both means a two-key scheme; I've deferred that — see Open
questions.

---

## Snapshot shape

`generateSnapshot` returns a plain `NSDiffableDataSourceSnapshot`:

- Section identifiers are boxed integers `0…6`.
- Item identifiers are **`NSString`**, longer than `uniqueIdentifier` (30/25/38
  chars observed) — a composite, one per conversation *per section*. Confirmed
  by `CKConversation.conversationListCollectionViewListItemIdentifier` and
  `…PinnedItemIdentifier` being distinct properties on the same object.
- Observed live: 111 items total — section `3` = 9 (matches
  `numberOfPinnedConversations`), section `5` = 102 (matches the standard list).
- `-itemIdentifierIsFromPinnedSection:` classifies an item without index-path math.
- `-conversationForItemIdentifier:` maps item string → `CKConversation`.

This is why filtering happens here: one hook, identity-keyed, no index paths,
and pinned + standard + every filter mode pass through it because the snapshot
is regenerated per `filterMode`.

## Search pipeline

Raw probe output: `probe/search16.txt` (class/method dump), `probe/flow16.txt`
(live call order).

`CKSearchViewController` is only the container. It holds a `searchControllers`
set, one `CKSearchController` subclass per section, each with its own results:

| Section | Class | `queryResultsForItems:` |
|---|---|---|
| Conversations | `CKConversationSearchController` | overridden |
| Messages | `CKMessagesSearchController` via `CKMessageTypeSearchController` | overridden |
| Photos / Links | `CKPhotosSearchController`, `CKLinkSearchController` | overridden |
| Other sections | section-specific controller | varies; covered by `-results` |

`CKSearchViewController` has **no `setConversations:`** — 0.1.0 hooked that
selector, so search was never filtered at all. Umbra filters raw input at
`queryResultsForItems:` where available and filters final output at the
authoritative `-[CKSearchController results]` getter.

There are two measured result shapes on iOS 16.2:

- A raw `CSSearchableItem` is mapped by the section controller's
  `chatGUIDForSearchableItem:`. Umbra then maps GUID →
  `CKConversationList.conversationForExistingChatWithGUID:` →
  `uniqueIdentifier`.
- Final `CKSpotlightQueryResult` and `CKZKWQueryResult` objects carry both their
  raw `item` and their resolved `conversation`. Umbra uses `conversation`
  directly. `CKSpotlightSearchResult`, used by the legacy path, carries
  `chatGUID` directly.

These shapes are confirmed in the archived iOS 16.2 ChatKit binary's Objective-C
symbols and in the implementation of
`-[CKConversationSearchController queryResultsForItems:]`, which constructs a
`CKSpotlightQueryResult` with the resolved conversation.

**Known degrade:** the search selectors are gated by `UmbraSearchUsable()`,
separately from the list. If they go missing on a future OS the list still
hides, but hidden threads become searchable again. That is a silent weakening
of the guarantee, so it is checked at every OS bump, not assumed.

`queryResultsForItems:` is not the only producer. The `results` getter remains
the load-bearing hook because it is the read point for every section, including
Photos, Links, Attachments, Locations and Passes.

0.1.1-3 passed final result objects to `chatGUIDForSearchableItem:`, whose iOS
16.2 implementation immediately sends `attributeSet` to its argument. Final
`CKSpotlightQueryResult` does not implement that selector, so the old outer catch
returned an empty array and blanked the entire search section. The filter now
unwraps `item`, uses `conversation` when present, catches failures per result,
and keeps unmappable results while Umbra is closed. Therefore an unfamiliar
result type can weaken filtering for that row, but cannot break normal search.

## Empty-state placeholder

Observed sequence during a stock refresh (`probe/flow16.txt`):

```
updateSnapshotAnimatingDifferences:
applyConversationListSnapshot:animatingDifferences:completion:
_updateContentUnavailableConfigurationUsingState:
```

`_updateContentUnavailableConfigurationUsingState:` is what installs and removes
the "No Messages" placeholder. `updateNoMessagesDialog` exists but never fired.
Disassembly corrects what the trace alone appeared to show: the snapshot wrapper
only generates a snapshot and calls `applyConversationListSnapshot:…`; it does
**not** call the empty-state updater. The latter independently reads
`dataSource.snapshot.numberOfItems` and calls
`_setContentUnavailableConfiguration:` with either nil or the empty state.

Umbra therefore refreshes through `updateSnapshotAnimatingDifferences:`. 0.1.0
called `generateSnapshot` + `applyConversationListSnapshot:` by hand, which left
the placeholder from an empty hidden list stranded under the restored list.

Refreshing through the wrapper was necessary but not sufficient because a
diffable snapshot applies asynchronously and availability updates run on a
separate lifecycle path. Umbra now records whether the filtered snapshot being
applied contains conversations, refreshes with ChatKit's completion overload,
and forces `_setContentUnavailableConfiguration:nil` after the snapshot commits.
The empty-state callback and `viewDidLayoutSubviews` repeat that idempotent clear
so a later UIKit callback cannot reinstall the stale view. The phrase handler
also forwards the cleared text to Apple's delegate, resigns the search bar, and
sets the owning `UISearchController.active` to `NO` before flipping modes. That
performs the same dismissal transition as tapping Cancel, so the conversation
list replaces the search-results window automatically.

## Filter modes

`filterMode` is an integer on the controller. The model-side predicate is
`-[CKConversationList conversation:includedInFilterMode:]`, with
`-conversationsForFilterMode:` and `-unreadCountForFilterMode:` alongside.
Filtering the snapshot covers all of them, since each mode regenerates it.

## Swipe actions

Leading (swipe-right) on a standard row, stock:

```
UISwipeActionsConfiguration  count=1  performsFirstActionWithFullSwipe=true
  [0] UIContextualAction 'Mark as Unread'  style=0  bg=set  img=set
```

Trailing, for contrast: `Delete`, `Mute`.

Umbra calls `%orig`, appends one `UIContextualAction` to the returned config's
`actions`, and re-creates the configuration preserving
`performsFirstActionWithFullSwipe`. Appending — never replacing — is what keeps
Apple's actions intact.

**Pinned rows return `nil`.** Apple gives pinned items no swipe actions. Hiding
a pinned conversation therefore cannot go through the swipe path; it goes
through the context menu, `-_topLevelMenuForItemIdentifier:inSection:withCell:`.

## Navigation title gesture

`navigationController` is `CKNavigationController`; its bar is
`CKAvatarNavigationBar`. The double-tap-and-hold gesture attaches there.

## Badge

`IMChatRegistry` exposes `unreadCount` / `setUnreadCount:` /
`_updateUnreadCountForChat:` in-process, but that registry count is not the
authoritative SpringBoard badge publisher. Umbra is injected into MobileSMS
only, while notification badge updates can arrive when MobileSMS is terminated.
Consequently Umbra does **not** claim to exclude hidden conversations from the
application icon badge. The unused `hiddenContributeToBadge` preference was
removed rather than offering an in-process implementation that only worked
while Messages happened to be open.

A real implementation requires a separate, measured design: hidden identifiers
must be made available to the process that publishes the badge, and that process
must be able to map each unread contribution back to a conversation without
exposing message content. Do not implement this by overriding
`CKConversationList.unreadCountForFilterMode:`; that only changes ChatKit UI and
cannot enforce the icon badge while MobileSMS is not running.

Note: `CKModifyBadgeOperation` and `CKModifyBadgeOperationInfo` appear in the
class list but are **CloudKit**, not ChatKit — same `CK` prefix, unrelated.

---

## Verifying the search filter

With Messages open and at least one conversation hidden:

```sh
frida -U -p "$(frida-ps -Ua | awk '/MobileSMS/{print $1}')" \
      -l probe/searchflow.js --runtime=v8 -o probe/flow16b.txt
```

Search for a term that matches a hidden thread. A pass looks like:

```
IN  CKConversationSearchController queryResultsForItems:
    arg=__NSArrayM count=N            <- N > 0
OUT CKConversationSearchController queryResultsForItems:
    ret=__NSArrayM count=M            <- M < N, hidden thread dropped
    chatGUIDForSearchableItem:(first) = #… /23   <- non-nil
```

A non-`NSArray` `ret` means the filter is passing that section through untouched.

The line that matters most in that output is `first=<className>` and the identity
selectors listed under it. **That is the measurement this whole filter turns on**:
which accessor the objects in `-results` actually expose on this OS. Everything
that has gone wrong here has gone wrong by assuming it.

Read the result as:

- **A row resolves to an identifier** → the filter is live for that section, and
  `count` shrinking on a hidden-thread query is the pass condition.
- **A row does not resolve while Umbra is closed** → that row passes through, so
  search keeps working but the row may leak. The `first=` class name tells you
  which result wrapper needs an adapter.
- **A row resolves but is not dropped** → identity mapping is fine and the leak is
  in `UmbraStore` — the identifier recorded at hide time is not the one resolved
  here.

**Check after any change here:** with one conversation hidden, search a term that
hits a photo or a link, and a term that hits a normal thread. Ordinary results
must remain visible while the hidden thread is absent.

## Open questions

1. **iOS 17 is unmeasured.** No iOS 17 device attached. The iOS 17 adapter will
   resolve every selector at runtime and no-op if absent; `probe/` runs on a 17
   device to fill this table in.
2. **Banner/lock-screen/NC suppression is unproven.** The design assumes mute
   suppresses them (the alert decision is made in `imagent` before SpringBoard
   is involved) and that the badge is separate. Needs a real two-device test.
3. **Group-chat identifier durability**, above.
