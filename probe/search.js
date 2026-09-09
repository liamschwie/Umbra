// Umbra probe 5: the search pipeline + the empty-state ("No Messages") dialog.
// Read-only class/method enumeration first; the live hooks below only log.
// Identifiers are hashed the same way as the earlier probes.

function h(s) {
  if (s === null || s === undefined) return "<nil>";
  s = "" + s;
  var x = 5381;
  for (var i = 0; i < s.length; i++) x = ((x * 33) ^ s.charCodeAt(i)) >>> 0;
  return "#" + x.toString(16) + " (len " + s.length + ")";
}
function section(t) { console.log("\n########## " + t + " ##########"); }
function safe(label, fn) { section(label); try { fn(); } catch (e) { console.log("!! ERROR: " + e.message); } }
function own(name, re) {
  var c = ObjC.classes[name];
  if (!c) { console.log("<absent>"); return []; }
  var m = c.$ownMethods.slice().sort();
  return re ? m.filter(function (x) { return re.test(x); }) : m;
}

var SEARCH_CLASSES = [
  "CKSearchViewController",
  "CKSearchController",
  "CKConversationSearchController",
  "CKConversationSearchResultsController",
  "CKMessagesSearchController",
  "CKContactsSearchManager"
];

SEARCH_CLASSES.forEach(function (n) {
  safe("METHODS: " + n, function () {
    own(n).forEach(function (m) { console.log("  " + m); });
  });
});

safe("IVARS: CKSearchViewController", function () {
  var c = ObjC.classes["CKSearchViewController"];
  if (!c) { console.log("<absent>"); return; }
  console.log(Object.keys(c.$ivars).join("\n"));
});

// Enumeration only. Live call flow is probe/searchflow.js — an earlier version
// of this script invoked updateSnapshotAnimatingDifferences: directly and took
// MobileSMS down with it, so nothing here calls into the app.

console.log("\n##### PROBE 5 COMPLETE #####");
