"use strict";
// تفضيلات التنبيهات — تشغيل: node test/notify_prefs.test.js
const assert = require("assert");
const {isMarketingBroadcast, excludeOptedOut} = require("../notify_prefs");

let passed = 0;
function t(name, fn) {
  fn();
  passed++;
  console.log("  ok -", name);
}

t("broadcast is marketing unless operational=true", () => {
  assert.strictEqual(isMarketingBroadcast({title: "x", target: "all"}), true);
  assert.strictEqual(isMarketingBroadcast({type: "admin_broadcast"}), true);
  assert.strictEqual(isMarketingBroadcast({operational: true}), false);
  assert.strictEqual(isMarketingBroadcast({operational: "yes"}), true, "string is not true");
  assert.strictEqual(isMarketingBroadcast(null), false);
});

t("excludeOptedOut drops docs whose id is in the set, keeps order", () => {
  const docs = [{id: "a"}, {id: "b"}, {id: "c"}];
  assert.deepStrictEqual(excludeOptedOut(docs, new Set(["b"])).map((d) => d.id), ["a", "c"]);
  assert.deepStrictEqual(excludeOptedOut(docs, new Set()).map((d) => d.id), ["a", "b", "c"]);
  assert.deepStrictEqual(excludeOptedOut(docs, null), docs);
});

console.log(`\n${passed} notify_prefs tests passed.`);
