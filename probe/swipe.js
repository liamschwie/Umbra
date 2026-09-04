// Umbra probe 3: swipe config on a populated section + item-identifier mapping.
// PRIVACY: no raw identifiers or names printed.
function h(s) {
  if (!s) return "<nil>";
  s = "" + s; var x = 5381;
  for (var i = 0; i < s.length; i++) x = ((x * 33) ^ s.charCodeAt(i)) >>> 0;
  return "#" + x.toString(16);
}
function safe(l, f) { console.log("\n##### " + l + " #####"); try { f(); } catch (e) { console.log("!! " + e.message); } }

var VC = null;
ObjC.choose(ObjC.classes.CKConversationListCollectionViewController, {
  onMatch: function (o) { VC = o; return "stop"; }, onComplete: function () {}
});
if (!VC) { console.log("no live VC"); }

safe("SWIPE CONFIG — pinned section 3 and list section 5", function () {
  [[3, 0], [5, 0], [5, 1]].forEach(function (p) {
    var ip = ObjC.classes.NSIndexPath.indexPathForItem_inSection_(p[1], p[0]);
    var cfg = VC.leadingSwipeActionsConfigurationForIndexPath_(ip);
    console.log("section " + p[0] + " item " + p[1] + ": " +
      (cfg ? cfg.$className : "<nil>"));
    if (!cfg) return;
    var acts = cfg.actions();
    console.log("   count=" + acts.count() +
      " fullSwipe=" + cfg.performsFirstActionWithFullSwipe());
    for (var i = 0; i < acts.count(); i++) {
      var a = acts.objectAtIndex_(i);
      console.log("   [" + i + "] " + a.$className + " title='" + a.title() +
        "' style=" + a.style() + " bg=" + (a.backgroundColor() ? "set" : "nil") +
        " img=" + (a.image() ? "set" : "nil"));
    }
  });
});

safe("TRAILING SWIPE for comparison — section 5", function () {
  var ip = ObjC.classes.NSIndexPath.indexPathForItem_inSection_(0, 5);
  var sel = "trailingSwipeActionsConfigurationForIndexPath:";
  if (!VC.respondsToSelector_(ObjC.selector(sel))) {
    console.log("VC does not respond to " + sel);
    var t = VC.$ownMethods.filter(function (m) { return /trailing/i.test(m); });
    console.log("trailing-ish methods: " + JSON.stringify(t));
    return;
  }
  var cfg = VC.trailingSwipeActionsConfigurationForIndexPath_(ip);
  console.log("cfg: " + (cfg ? cfg.$className : "<nil>"));
  if (cfg) {
    var acts = cfg.actions();
    for (var i = 0; i < acts.count(); i++)
      console.log("   [" + i + "] '" + acts.objectAtIndex_(i).title() + "'");
  }
});

safe("ITEM IDENTIFIER -> CONVERSATION (pinned + list)", function () {
  var snap = VC.generateSnapshot();
  var secs = snap.sectionIdentifiers();
  for (var i = 0; i < secs.count(); i++) {
    var s = secs.objectAtIndex_(i);
    var n = snap.numberOfItemsInSection_(s);
    if (n === 0) continue;
    var ids = snap.itemIdentifiersInSection_(s);
    var id = ids.objectAtIndex_(0);
    var conv = VC.conversationForItemIdentifier_(id);
    console.log("section " + s + " (n=" + n + "): item=" + h(id) +
      " -> conv=" + (conv ? h(conv.uniqueIdentifier()) : "<nil>") +
      " pinnedItemId=" + (VC.itemIdentifierIsFromPinnedSection_(id) ? "YES" : "no"));
    if (conv) {
      console.log("   conv.conversationListCollectionViewListItemIdentifier   = " +
        h(conv.conversationListCollectionViewListItemIdentifier()));
      console.log("   conv.conversationListCollectionViewPinnedItemIdentifier = " +
        h(conv.conversationListCollectionViewPinnedItemIdentifier()));
    }
  }
});

safe("SECTION ENUM MEANING", function () {
  var snap = VC.generateSnapshot();
  var secs = snap.sectionIdentifiers();
  for (var i = 0; i < secs.count(); i++) {
    var s = secs.objectAtIndex_(i);
    var n = snap.numberOfItemsInSection_(s);
    var kind = "?";
    if (n > 0) {
      var id = snap.itemIdentifiersInSection_(s).objectAtIndex_(0);
      kind = VC.itemIdentifierIsFromPinnedSection_(id) ? "PINNED" : "standard";
    }
    console.log("  section " + s + " items=" + n + " kind=" + kind);
  }
});

safe("APPLY-SNAPSHOT SELECTOR PRESENT", function () {
  ["applyConversationListSnapshot:animatingDifferences:completion:",
   "generateSnapshot", "conversationForItemIdentifier:",
   "leadingSwipeActionsConfigurationForIndexPath:",
   "searchBar:textDidChange:", "performSearch:completion:",
   "filterMode", "dataSource"].forEach(function (s) {
    console.log("  " + (VC.respondsToSelector_(ObjC.selector(s)) ? "YES " : "NO  ") + s);
  });
});

safe("NAV TITLE / SEARCH BAR REACHABLE", function () {
  var ni = VC.navigationItem();
  console.log("navigationItem: " + (ni ? ni.$className : "<nil>"));
  console.log("  title set: " + (ni.title() ? "yes" : "no"));
  console.log("  searchController: " + (ni.searchController() ? ni.searchController().$className : "<nil>"));
  var sc = VC.searchController();
  if (sc) console.log("  searchBar: " + sc.searchBar().$className);
  var nb = VC.navigationController();
  console.log("navigationController: " + (nb ? nb.$className : "<nil>"));
  if (nb) console.log("  navigationBar: " + nb.navigationBar().$className);
});

console.log("\n##### PROBE 3 COMPLETE #####");
