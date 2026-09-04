// Umbra runtime probe. Read-only: enumerates ChatKit/IMCore surface area
// needed for the compatibility map. Prints, changes nothing.

var ALL = null;
function allClasses() {
  if (!ALL) ALL = Object.keys(ObjC.classes);
  return ALL;
}
function match(re) { return allClasses().filter(function (n) { return re.test(n); }).sort(); }

function methodsOf(name, re) {
  try {
    var c = ObjC.classes[name];
    if (!c) return [];
    var m = c.$ownMethods;
    return re ? m.filter(function (x) { return re.test(x); }) : m;
  } catch (e) { return ["<err " + e.message + ">"]; }
}

function section(t) { console.log("\n########## " + t + " ##########"); }
function safe(label, fn) {
  section(label);
  try { fn(); } catch (e) { console.log("!! ERROR: " + e.message); }
}

safe("CONVERSATION LIST CLASSES", function () {
  match(/^CK.*(ConversationList|ChatList)/).forEach(function (n) { console.log(n); });
});
safe("PINNED", function () { match(/^CK.*Pin/).forEach(function (n) { console.log(n); }); });
safe("DATA SOURCE / SNAPSHOT", function () {
  match(/^CK.*(DataSource|Snapshot|Diffable)/).forEach(function (n) { console.log(n); });
});
safe("SEARCH", function () { match(/^CK.*Search/).forEach(function (n) { console.log(n); }); });
safe("FILTER", function () {
  match(/^CK.*(Filter|Unread|Known|Unknown|Junk|Recents)/).forEach(function (n) { console.log(n); });
});

var RE = /(snapshot|conversation|swipe|action|filter|search|pin|reload|update|apply|item|identifier|guid|datasource)/i;
[
  "CKConversationListViewController",
  "CKConversationListCollectionViewController",
  "CKConversationListController",
  "CKConversationList",
  "CKConversationListFilter",
  "CKConversation"
].forEach(function (t) {
  safe("METHODS: " + t, function () {
    if (!ObjC.classes[t]) { console.log("<absent>"); return; }
    methodsOf(t, RE).sort().forEach(function (m) { console.log("  " + m); });
  });
});

safe("IMChat identity + alert state", function () {
  methodsOf("IMChat", /(guid|identifier|groupID|persistentID|ignoreAlerts|muted|alert)/i)
    .sort().forEach(function (m) { console.log("  " + m); });
});

safe("BADGE providers", function () {
  match(/^(CK|IM).*Badge/).forEach(function (n) {
    console.log(n);
    methodsOf(n, /badge|count/i).sort().forEach(function (m) { console.log("    " + m); });
  });
});

safe("SUPERCLASS CHAINS", function () {
  ["CKConversationListViewController", "CKConversationListCollectionViewController",
   "CKConversation", "IMChat"].forEach(function (n) {
    if (!ObjC.classes[n]) return;
    var c = ObjC.classes[n], chain = [], guard = 0;
    while (c && guard++ < 20) { chain.push(c.$className); c = c.$superClass; }
    console.log(chain.join(" -> "));
  });
});

console.log("\n##### PROBE COMPLETE #####");
