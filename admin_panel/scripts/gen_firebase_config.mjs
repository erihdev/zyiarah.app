// يولّد `admin_panel/src/services/firebase.ts` من `lib/firebase_options.dart`.
//
// الملفُّ الهدف مُستثنى من git (سطر 59 في `.gitignore`)، فكان لا بدّ لكلّ مسارِ
// بناءٍ أن يصنعه بنفسه — وكانت نسخةٌ صوريّة مكتوبةً بخط اليد داخل `ci.yml`:
// تفحص الأنواع ولا تصلح للنشر، وتتباعد عن الملفّ الحقيقيّ بصمت كلّما تغيّر.
//
// والقيمُ ليست سرّاً: إعدادُ Firebase للويب يُشحن داخل الحزمة ويقرؤه أيُّ زائر،
// وهو **مكتوبٌ أصلاً في المستودع** داخل `lib/firebase_options.dart` (كتلة
// `web`) ويستعمله بناءُ فلاتر للويب. فالمصدرُ واحدٌ لا اثنان، والحمايةُ من
// قواعد Firestore لا من إخفاء المفتاح.
//
// الاستعمال: `node scripts/gen_firebase_config.mjs` من داخل `admin_panel/`.

import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const SRC = resolve(here, '../../lib/firebase_options.dart');
const OUT = resolve(here, '../src/services/firebase.ts');

const REQUIRED = [
  'apiKey',
  'appId',
  'messagingSenderId',
  'projectId',
  'authDomain',
  'storageBucket',
];

const dart = readFileSync(SRC, 'utf8');

// كتلةُ الويب وحدها: الأندرويد وiOS يحملان نفس أسماء الحقول بقيمٍ مختلفة،
// فالالتقاطُ من أوّل تطابقٍ في الملفّ كلِّه يأتي بمفتاحِ منصّةٍ أخرى.
const block = dart.match(
    /static const FirebaseOptions web = FirebaseOptions\(([\s\S]*?)\);/);
if (!block) {
  throw new Error(
      `لم يُعثر على كتلة FirebaseOptions web في ${SRC} — تغيّر توليدُ flutterfire؟`);
}

const cfg = {};
for (const [, k, v] of block[1].matchAll(/(\w+):\s*'([^']*)'/g)) cfg[k] = v;

const missing = REQUIRED.filter((k) => !cfg[k]);
if (missing.length) {
  throw new Error(`حقولٌ ناقصة في كتلة الويب: ${missing.join(', ')}`);
}

const keys = [...REQUIRED, ...(cfg.measurementId ? ['measurementId'] : [])];
const body = keys.map((k) => `  ${k}: '${cfg[k]}',`).join('\n');

mkdirSync(dirname(OUT), {recursive: true});
writeFileSync(OUT, `// مُولَّد — لا تُحرّره بيدك.
// المصدر: lib/firebase_options.dart (كتلة web) عبر scripts/gen_firebase_config.mjs
import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getStorage } from 'firebase/storage';
import { getFunctions } from 'firebase/functions';

const app = initializeApp({
${body}
});

export const auth = getAuth(app);
export const db = getFirestore(app);
export const storage = getStorage(app);
export const functions = getFunctions(app);
export default app;
`);

console.log(`✔ ${OUT}\n  projectId=${cfg.projectId} appId=${cfg.appId}`);
