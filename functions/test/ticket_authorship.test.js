"use strict";

// مرآةُ `lib/utils/ticket_authorship.dart` — **جدولُ الحالاتِ يُقرأُ من فحصِ
// الدارت حرفيّاً** فافتراقُ جهةٍ يَسقطُ الفحص (نمطُ `serviceMeta`/`buildGate`).
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const auth = require("../ticket_authorship");

let pass = 0; let fail = 0;
const check = (name, fn) => {
  try {
    fn();
    console.log(`  ok - ${name}`);
    pass++;
  } catch (e) {
    console.log(`  not ok - ${name}: ${e.message}`);
    fail++;
  }
};

/** @return {Array} جدولُ الحالاتِ من فحصِ الدارت. */
function sharedCases() {
  const src = fs.readFileSync(
      path.join(__dirname, "../../test/ticket_authorship_test.dart"), "utf8");
  const b = src.indexOf("TICKET_AUTHORSHIP_CASES_BEGIN");
  const e = src.indexOf("TICKET_AUTHORSHIP_CASES_END");
  if (b < 0 || e < 0) throw new Error("علامتا الجدولِ اختفتا من فحصِ الدارت");
  const seg = src.slice(b, e);
  // الكتلةُ بين `'''` و`'''` — بموازنةِ العلامةِ لا بأوّلِ `[`.
  const i = seg.indexOf("'''");
  const j = seg.indexOf("'''", i + 3);
  if (i < 0 || j < 0) throw new Error("تعذّرَ اقتطاعُ الجدول");
  return JSON.parse(seg.slice(i + 3, j));
}

// الاقتطاعُ قد يَفشلُ (علامةٌ أُزيلت، جدولٌ أُفسِد) — فيُقالُ في **فحصٍ**
// لا باستثناءٍ يَقتلُ العمليّةَ برسالةٍ مدفونةٍ في المكدّس: حارسٌ فشلُه
// غيرُ مقروءٍ يُعالَجُ كعطلٍ في البيئةِ لا كافتراقٍ حقيقيّ.
let cases = [];
check("الجدولُ المشترَكُ قُرِئ فعلاً (لا فحصٌ أجوف)", () => {
  cases = sharedCases();
  assert.ok(cases.length >= 12, `الحالاتُ ${cases.length}`);
});

cases.forEach(([msg, owner, want], i) => {
  check(`حالة ${i + 1}: ${JSON.stringify(msg)} (مالك=${owner}) ⇒ ${want}`,
      () => {
        assert.strictEqual(auth.ticketMessageSender(msg, owner), want);
        assert.strictEqual(
            auth.ticketMessageIsFromTeam(msg, owner), want === "team");
      });
});

// ── الوحدةُ لا تَمَسُّ Firestore (قاعدةُ `refund_engine.js`) ──
check("الوحدةُ لا تُنادي getFirestore/getApp/initializeApp", () => {
  const raw = fs.readFileSync(
      path.join(__dirname, "../ticket_authorship.js"), "utf8");
  const code = raw.split("\n").filter((l) => !l.trim().startsWith("//"))
      .join("\n");
  for (const bad of ["getFirestore(", "getApp(", "initializeApp("]) {
    assert.ok(!code.includes(bad), `الوحدةُ تُنادي ${bad}`);
  }
});

// ── والمُشغّلُ يُمرّرُ مالكَ التذكرةِ، لا الادّعاءَ وحدَه ──
/**
 * جسمُ دالّةٍ بحدِّه الحقيقيّ — لا بعدِّ أحرف. الشريحةُ كانت تَتجاوزُ
 * `sendNotificationOnTicketReply` بـ١٣٤٦ حرفاً، أي أنّ الفحصَ يَقرأُ دالّةً
 * أخرى ويَحكمُ بها. فخُّ الحدِّ مسجَّلٌ في هذا المستودعِ مرّاتٍ.
 * @param {string} src المصدر
 * @param {string} anchor مِرساةُ الدالّة
 * @return {string} الجسم
 */
function fnBody(src, anchor) {
  const i = src.indexOf(anchor);
  assert.ok(i > -1, `المِرساةُ «${anchor}» اختفت`);
  const ends = [
    src.indexOf("\nexports.", i + 10),
    src.indexOf("\nasync function ", i + 10),
    src.indexOf("\nfunction ", i + 10),
  ].filter((x) => x > 0);
  const j = ends.length ? Math.min(...ends) : src.length;
  assert.ok(j - i > 300, `اقتطاعُ «${anchor}» انهار`);
  return src.slice(i, j);
}

check("sendNotificationOnTicketReply يُمرّرُ ticketData.userId", () => {
  const src = fs.readFileSync(path.join(__dirname, "../index.js"), "utf8");
  const seg = fnBody(src, "exports.sendNotificationOnTicketReply");
  assert.ok(
      /ticketAuthorship\.ticketMessageIsFromTeam\(\s*newMessage,\s*ticketData && ticketData\.userId\)/
          .test(seg),
      "المالكُ لا يُمرَّرُ — فالقرارُ يَبقى على الادّعاءِ وحدَه");
});

console.log(`\nticket_authorship tests: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
