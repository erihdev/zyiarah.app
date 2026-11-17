// يقرأ قائمةَ إصداراتِ القواعدِ من Firebase Rules API ويطبع لكلِّ هدفٍ سطراً:
//   النوع|ملفُّ المستودع|اسمُ مجموعةِ القواعد|وقتُ آخرِ نشر
// بلا شبكةٍ ولا مفاتيح — يُختبَر بملفٍّ محلّيّ.
import {readFileSync} from 'node:fs';

const data = JSON.parse(readFileSync(process.argv[2], 'utf8'));
if (data.error) {
  console.error(`Rules API: ${data.error.status} ${data.error.message}`);
  process.exit(1);
}
const releases = data.releases || [];
const out = [];
for (const r of releases) {
  const id = r.name.split('/releases/')[1] || '';
  if (id === 'cloud.firestore') {
    out.push(['firestore', 'firestore.rules', r.rulesetName, r.updateTime]);
  } else if (id.startsWith('firebase.storage/')) {
    out.push(['storage', 'storage.rules', r.rulesetName, r.updateTime]);
  }
}
if (out.length === 0) {
  console.error('لا إصدارَ قواعدٍ في المشروع — لا شيءَ يُقارَن');
  process.exit(1);
}
// هدفُ تخزينٍ واحدٌ يكفي للمقارنة (السلّةُ الافتراضيّة أوّلاً).
const seen = new Set();
for (const row of out) {
  if (seen.has(row[0])) continue;
  seen.add(row[0]);
  console.log(row.join('|'));
}
