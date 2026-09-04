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
| **Search results** | `UISearchController` + `CKSearchViewController` (`modernSearchResultsController`); `-performSearch:completion:`; `-searchBar:textDidChange:` | Separate pipeline from the list. |
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
`_updateUnreadCountForChat:` in-process. Whether suppressing hidden threads
here actually moves the SpringBoard badge is **unverified** — the badge may be
set by `imagent` out of process. Flagged as a test, not an assumption.

Note: `CKModifyBadgeOperation` and `CKModifyBadgeOperationInfo` appear in the
class list but are **CloudKit**, not ChatKit — same `CK` prefix, unrelated.

---

## Open questions

1. **iOS 17 is unmeasured.** No iOS 17 device attached. The iOS 17 adapter will
   resolve every selector at runtime and no-op if absent; `probe/` runs on a 17
   device to fill this table in.
2. **Banner/lock-screen/NC suppression is unproven.** The design assumes mute
   suppresses them (the alert decision is made in `imagent` before SpringBoard
   is involved) and that the badge is separate. Needs a real two-device test.
3. **Group-chat identifier durability**, above.
