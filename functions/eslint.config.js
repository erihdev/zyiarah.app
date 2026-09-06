// إعداد ESLint المسطّح (flat). حلّ محلّ .eslintrc.js الذي توقّف عن العمل حين
// رُفع eslint إلى 10: الإصدارات ≥9 لا تقرأ إلا eslint.config.js، فكان
// `npm run lint` يخرج بخطأ «couldn't find an eslint.config.js file» — أي أن
// الدوال الخادمية كانت بلا فحص أصلاً.
//
// أُسقط eslint-config-google: غير مصان (آخر إصدار 0.14.0)، ولا يدعم flat
// config، والكود لم يوافقه قطّ (١٥١ خطأً تحت eslint 8 — ٥٣ منها max-len و٣٠
// brace-style و١٩ require-jsdoc). إبقاؤه كان يعني إمّا إعادة تنسيق index.js
// كاملاً وإمّا فحصاً أحمر دائماً يتجاهله الجميع. المحفوظ هنا هو ما اختاره
// المستودع لنفسه صراحةً في .eslintrc.js القديم.
"use strict";

const js = require("@eslint/js");
const globals = require("globals");

module.exports = [
  {
    ignores: ["node_modules/**", "coverage/**"],
  },
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2020,
      sourceType: "commonjs",
      globals: {
        ...globals.node,
      },
    },
    rules: {
      // القواعد الثلاث التي أعلنها المستودع لنفسه في .eslintrc.js.
      "no-restricted-globals": ["error", "name", "length"],
      "prefer-arrow-callback": "error",
      "quotes": ["error", "double", {"allowTemplateLiterals": true}],

      // مُعطَّلة عن قصد. مواضعها الأربعة كلها قيم ابتدائية دفاعية في مسارات
      // الدفع والاسترداد وبريد التنبيهات (heading وrows وpayout وgatewayOk):
      // تُسنَد ثم يُعاد إسنادها في كل فرع، فتراها القاعدة زائدة. حذفها لا يُصلح
      // خطأً بل يزيل حارساً — «rows = []» تحديداً يمنع انفجار rows.map لو أضاف
      // تعديلٌ لاحق فرعاً لا يُسنِدها.
      "no-useless-assignment": "off",
    },
  },
  {
    // ملفات الاختبار تُشغَّل بـ node مباشرةً وتستعمل نفس بيئة CommonJS.
    files: ["test/**/*.js"],
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.mocha,
      },
    },
  },
];
