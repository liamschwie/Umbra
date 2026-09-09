// Umbra probe 6: armed listeners only — no ObjC.choose, no method invocation.
// Answers: which selector actually carries Conversations search results, and
// in what identity domain (chat GUID vs uniqueIdentifier).
// Identifiers hashed, same as every earlier probe.

function h(s) {
  if (s === null || s === undefined) return "<nil>";
  s = "" + s;
  var x = 5381;
  for (var i = 0; i < s.length; i++) x = ((x * 33) ^ s.charCodeAt(i)) >>> 0;
  return "#" + x.toString(16) + "/" + s.length;
}
function section(t) { console.log("\n########## " + t + " ##########"); }

function hook(cls, sel, onEnter, onLeave) {
  var C = ObjC.classes[cls];
  if (!C) { console.log("  <no class> " + cls); return; }
  var m = C["- " + sel];
  if (!m) { console.log("  <absent> " + cls + " " + sel); return; }
  Interceptor.attach(m.implementation, { onEnter: onEnter, onLeave: onLeave });
}

// What identity does a result object expose? This is the whole question:
// UmbraStore holds uniqueIdentifier, and compat-map.md warns that guid encodes
// service and flips with iMessage<->SMS, so the mapping direction matters.
var IDENT = ["uniqueIdentifier", "guid", "chatGUID", "domainIdentifier",
             "uniqueIdentifier", "identifier", "chatIdentifier"];

function describe(ptr) {
  var a;
  try { a = new ObjC.Object(ptr); } catch (e) { return "<unreadable>"; }
  var out = a.$className;
  try {
    if (!a.respondsToSelector_(ObjC.selector("count"))) return out;
    var n = a.count();
    out += " count=" + n;
    if (n === 0) return out;
    var e0 = a.objectAtIndex_(0);
    out += "\n      first=" + e0.$className;
    IDENT.forEach(function (s) {
      try {
        if (e0.respondsToSelector_(ObjC.selector(s)))
          out += "\n        " + s + " = " + h(e0[s]());
      } catch (e) {}
    });
  } catch (e) { out += " !" + e.message; }
  return out;
}

section("SEARCH RESULT PATHS — type in Messages search now");
[["CKSearchController", "queryResultsForItems:"],
 ["CKSearchController", "setResults:"],
 ["CKConversationSearchController", "queryResultsForItems:"],
 ["CKConversationSearchController", "tokenizedQueryResultsForItems:"],
 ["CKConversationSearchController", "_sortedAndRankedItemsWithItems:"],
 ["CKConversationSearchController", "setIntermediaryResults:"],
 ["CKMessagesSearchController", "queryResultsForItems:"]
].forEach(function (p) {
  var tag = p[0] + " " + p[1];
  hook(p[0], p[1], function (args) {
    this.tag = tag;
    this.self = args[0];
    console.log("\n  IN  " + tag + "\n      arg=" + describe(args[2]));
  }, function (ret) {
    if (ret.isNull()) return;
    console.log("  OUT " + this.tag + "\n      ret=" + describe(ret));
    // Can this controller map a result back to a chat? That accessor is the
    // bridge from a search item to something UmbraStore can be asked about.
    try {
      var s = new ObjC.Object(this.self);
      var r = new ObjC.Object(ret);
      if (s.respondsToSelector_(ObjC.selector("chatGUIDForSearchableItem:")) &&
          r.respondsToSelector_(ObjC.selector("count")) && r.count() > 0) {
        var g = s.chatGUIDForSearchableItem_(r.objectAtIndex_(0));
        console.log("      chatGUIDForSearchableItem:(first) = " +
                    (g && !g.handle.isNull() ? h(g.toString()) : "<nil>"));
      }
    } catch (e) { console.log("      guid map failed: " + e.message); }
  });
});

// The getter is the authoritative read point and the one covertck (the shipped
// iOS 13/14 tweak) filters. It fires constantly during scrolling, so log only
// when the count changes — otherwise the transcript is unreadable.
section("RESULTS GETTER — the load-bearing path");
var lastCount = {};
hook("CKSearchController", "results", function (args) {
  this.self = args[0];
}, function (ret) {
  if (ret.isNull()) return;
  try {
    var r = new ObjC.Object(ret);
    if (!r.respondsToSelector_(ObjC.selector("count"))) return;
    var n = r.count();
    var cls = new ObjC.Object(this.self).$className;
    if (lastCount[cls] === n) return;
    lastCount[cls] = n;
    console.log("\n  GET " + cls + ".results count=" + n);
    if (n === 0) return;
    var e0 = r.objectAtIndex_(0);
    console.log("      first=" + e0.$className);
    var s = new ObjC.Object(this.self);
    if (s.respondsToSelector_(ObjC.selector("chatGUIDForSearchableItem:"))) {
      var g = s.chatGUIDForSearchableItem_(e0);
      console.log("      chatGUIDForSearchableItem: = " +
                  (g && !g.handle.isNull() ? h(g.toString()) : "<nil>"));
    }
  } catch (e) { console.log("      !" + e.message); }
});

console.log("\n##### PROBE 6 ARMED #####");
