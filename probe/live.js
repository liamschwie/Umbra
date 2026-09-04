// Umbra live probe. Answers the compatibility-map questions with real values.
// PRIVACY: never prints raw identifiers, display names, or message content.
// Identifiers are reduced to <service-prefix>#<8-hex-of-djb2>.

function redact(s) {
  if (s === null || s === undefined) return "<nil>";
  s = "" + s;
  var h = 5381;
  for (var i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0;
  var pfx = "";
  var m = s.match(/^([A-Za-z]+);[-+];/);
  if (m) pfx = m[1] + ";..;";
  else if (/^[A-Za-z]+:/.test(s)) pfx = s.split(":")[0] + ":";
  return pfx + "#" + h.toString(16) + " (len " + s.length + ")";
}

function section(t) { console.log("\n########## " + t + " ##########"); }
function safe(l, f) { section(l); try { f(); } catch (e) { console.log("!! " + e.message); } }

var VC = null;
safe("LOCATE LIVE CONVERSATION LIST CONTROLLER", function () {
  var chosen = null;
  ObjC.choose(ObjC.classes.CKConversationListCollectionViewController, {
    onMatch: function (o) { chosen = o; return "stop"; },
    onComplete: function () {}
  });
  VC = chosen;
  console.log(VC ? "found instance" : "NONE LIVE (open Messages to the list)");
});

safe("SNAPSHOT SHAPE", function () {
  if (!VC) return;
  var snap = VC.generateSnapshot();
  console.log("snapshot class: " + snap.$className);
  console.log("numberOfItems: " + snap.numberOfItems());
  var secs = snap.sectionIdentifiers();
  console.log("sections (" + secs.count() + "):");
  for (var i = 0; i < secs.count(); i++) {
    var s = secs.objectAtIndex_(i);
    console.log("  [" + i + "] " + s + "  (" + s.$className + ")  items=" +
      snap.numberOfItemsInSection_(s));
  }
  var items = snap.itemIdentifiers();
  console.log("item identifier class: " +
    (items.count() ? items.objectAtIndex_(0).$className : "<empty>"));
  console.log("sample items:");
  for (var j = 0; j < Math.min(3, items.count()); j++) {
    console.log("  " + redact(items.objectAtIndex_(j)));
  }
});

safe("IDENTIFIER STABILITY CANDIDATES", function () {
  if (!VC) return;
  var snap = VC.generateSnapshot();
  var items = snap.itemIdentifiers();
  for (var j = 0; j < Math.min(3, items.count()); j++) {
    var id = items.objectAtIndex_(j);
    var conv = VC.conversationForItemIdentifier_(id);
    if (!conv) { console.log("  item -> no conversation"); continue; }
    console.log("--- conversation " + j);
    console.log("  CKConversation.uniqueIdentifier : " + redact(conv.uniqueIdentifier()));
    console.log("  CKConversation.pinningIdentifier: " + redact(conv.pinningIdentifier()));
    try {
      var chat = conv.chat();
      console.log("  IMChat.guid          : " + redact(chat.guid()));
      console.log("  IMChat.chatIdentifier: " + redact(chat.chatIdentifier()));
      console.log("  IMChat.identifier    : " + redact(chat.identifier()));
      console.log("  IMChat.persistentID  : " + redact(chat.persistentID()));
      console.log("  IMChat.groupID       : " + redact(chat.groupID()));
      console.log("  IMChat.isMuted       : " + chat.isMuted());
      console.log("  conv.isPinned        : " + conv.isPinned());
    } catch (e) { console.log("  chat err: " + e.message); }
  }
});

safe("LEADING SWIPE (swipe-right) ACTIONS", function () {
  if (!VC) return;
  var ip = ObjC.classes.NSIndexPath.indexPathForItem_inSection_(0, 0);
  var cfg = VC.leadingSwipeActionsConfigurationForIndexPath_(ip);
  if (!cfg) { console.log("nil config at 0,0"); return; }
  console.log("config class: " + cfg.$className);
  var acts = cfg.actions();
  console.log("action count: " + acts.count());
  for (var i = 0; i < acts.count(); i++) {
    var a = acts.objectAtIndex_(i);
    console.log("  [" + i + "] class=" + a.$className + " title=" + a.title() +
      " style=" + a.style());
  }
  console.log("performsFirstActionWithFullSwipe: " + cfg.performsFirstActionWithFullSwipe());
});

safe("FILTER MODE", function () {
  if (!VC) return;
  console.log("current filterMode: " + VC.filterMode());
  console.log("numberOfConversations: " + VC.numberOfConversations());
  console.log("numberOfPinnedConversations: " + VC.numberOfPinnedConversations());
});

safe("SEARCH SURFACE", function () {
  if (!VC) return;
  var sc = VC.searchController();
  console.log("searchController: " + (sc ? sc.$className : "<nil>"));
  var rc = VC.searchResultsController();
  console.log("searchResultsController: " + (rc ? rc.$className : "<nil>"));
  var mrc = VC.modernSearchResultsController();
  console.log("modernSearchResultsController: " + (mrc ? mrc.$className : "<nil>"));
});

safe("MUTE API on IMChat / IMChatRegistry", function () {
  ["IMChat"].forEach(function (c) {
    ObjC.classes[c].$ownMethods.filter(function (m) {
      return /mute|ignoreAlert|alertsHidden|doNotDisturb|dnd/i.test(m);
    }).sort().forEach(function (m) { console.log("  " + c + " " + m); });
  });
});

safe("BADGE SOURCE", function () {
  var cands = Object.keys(ObjC.classes).filter(function (n) {
    return /^(CK|IM)/.test(n) && /Badge|UnreadCount/i.test(n);
  });
  console.log("classes: " + JSON.stringify(cands));
  ["IMDaemonController", "IMChatRegistry", "CKConversationList"].forEach(function (c) {
    if (!ObjC.classes[c]) return;
    ObjC.classes[c].$ownMethods.filter(function (m) {
      return /badge|unread/i.test(m);
    }).sort().forEach(function (m) { console.log("  " + c + " " + m); });
  });
});

safe("CKConversationList (model) methods", function () {
  ObjC.classes.CKConversationList.$ownMethods.filter(function (m) {
    return /conversation|filter|sort|update|unread/i.test(m);
  }).sort().forEach(function (m) { console.log("  " + m); });
});

console.log("\n##### LIVE PROBE COMPLETE #####");
