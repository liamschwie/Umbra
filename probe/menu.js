// Umbra probe 4: pinned context-menu structure, so Hide lands between
// Unpin and Mark as Unread. PRIVACY: titles of Apple's own actions only.
var VC = null;
ObjC.choose(ObjC.classes.CKConversationListCollectionViewController, {
  onMatch: function (o) { VC = o; return "stop"; }, onComplete: function () {}
});
if (!VC) throw new Error("no live conversation list");

function dumpMenu(m, indent) {
  var pad = new Array(indent + 1).join("  ");
  console.log(pad + "MENU '" + m.title() + "' class=" + m.$className +
    " options=" + m.options());
  var ch = m.children();
  for (var i = 0; i < ch.count(); i++) {
    var c = ch.objectAtIndex_(i);
    if (c.$className.indexOf("Menu") !== -1 && c.respondsToSelector_(ObjC.selector("children"))) {
      dumpMenu(c, indent + 1);
    } else {
      var img = "nil";
      try {
        var im = c.image();
        if (im) img = im.respondsToSelector_(ObjC.selector("_symbolName")) &&
          im._symbolName() ? ("symbol:" + im._symbolName()) : "image";
      } catch (e) { img = "?"; }
      console.log(pad + "  [" + i + "] '" + c.title() + "' " + c.$className +
        " img=" + img + " attrs=" + c.attributes());
    }
  }
}

function firstItemInSection(sec) {
  var snap = VC.generateSnapshot();
  var ids = snap.itemIdentifiers();
  for (var i = 0; i < ids.count(); i++) {
    var id = ids.objectAtIndex_(i);
    var isPinned = VC.itemIdentifierIsFromPinnedSection_(id);
    if ((sec === "pinned") === isPinned) return id;
  }
  return null;
}

["pinned", "standard"].forEach(function (kind) {
  console.log("\n########## CONTEXT MENU: " + kind + " ##########");
  try {
    var id = firstItemInSection(kind);
    if (!id) { console.log("no item"); return; }
    var secNum = (kind === "pinned") ? 3 : 5;
    var sel = "- _topLevelMenuForItemIdentifier:inSection:withCell:";
    var menu = VC[sel](id, secNum, NULL);
    if (!menu) { console.log("<nil menu>"); return; }
    dumpMenu(menu, 0);
  } catch (e) { console.log("!! " + e.message); }
});

console.log("\n########## SF SYMBOLS USED BY STOCK ACTIONS ##########");
["_pinActionForItemIdentifier:", "_markUnreadSwipeActionForIndexPath:",
 "_dndSwipeActionForIndexPath:", "_deleteSwipeActionForIndexPath:"].forEach(function (s) {
  console.log("  VC responds to " + s + ": " +
    VC.respondsToSelector_(ObjC.selector(s)));
});

console.log("\n##### PROBE 4 COMPLETE #####");
