import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'helpers/sources_in.dart';

/// حارس تثبيت `google_fonts` على المِجَل ٨ — وتوثيقُ السبب كي لا يُعاد بحثُه.
///
/// ═══ لمَ لا تُرقّى إلى ٩ ═══
///
/// `google_fonts 9.0.0` و`go_router 18.0.0` كلاهما «ينتقل إلى `material_ui`
/// و`cupertino_ui`»: مكتبةُ Material تُنتزع من SDK لتصير حزمةً مستقلّة. لكنّ
/// **Flutter 3.47.2 لم يُنجز الانتقال بعد**: `flutter/material.dart` ما زال
/// يُعرّف `TextTheme` خاصّته في `src/material/text_theme.dart` (٨٦٢ سطراً، صنفٌ
/// كامل) ولا يُعيد تصدير `material_ui`. فصار الاسمُ واحداً والصنفان اثنين:
///
///     package:flutter/material.dart   → TextTheme  (SDK)
///     package:material_ui/...         → TextTheme  (الحزمة)
///
/// و`google_fonts 9` مكتوبةٌ على الثاني بالكامل. أثبتتُ ذلك بمسبارٍ على
/// المُحلِّل لا بالاستنتاج:
///
///     mui.TextTheme a = GoogleFonts.tajawalTextTheme();    ✓ يمرّ
///     TextTheme      b = GoogleFonts.tajawalTextTheme();   ✗ يسقط
///     GoogleFonts.tajawalTextTheme(const mui.TextTheme()); ✓ يمرّ
///     GoogleFonts.tajawalTextTheme(const TextTheme());     ✗ يسقط
///
/// فالمُعاد `material_ui.TextTheme`، و`ThemeData.textTheme` في SDK يطلب
/// `TextTheme?` الخاصّ به — **فالجدارُ في المُعاد لا في المُعطى**: حتى لو بُني
/// الأساس بـ`mui.TextTheme` (وهو يمرّ) يسقط إسنادُ الناتج إلى `ThemeData`.
/// فلا يُعبَر إلّا بمحوِّلٍ يدويّ يَنقل خمسة عشر حقلاً صنفاً إلى صنف — شيفرةٌ
/// تُصان مقابل لا شيء.
///
/// ولاحظ أنّ `google_fonts 9` تُعلن `flutter: ">=3.47.0"` و**نحن على 3.47.2**،
/// فـ`pub get` يمرّ بلا شكوى. فالقيد لا يحمي من هذا — والدرسُ المتكرّر هنا:
/// `pub get` يفحص القيود لا الأصناف.
///
/// ═══ ولا مكسب لنا في ٩ ═══
///
/// تغييراتُ ٩٫٠٫٠: الانتقال إلى material_ui، ورفعُ أرضيّة SDK، و`GoogleFontsLite`
/// لتقليم الشيفرة، و**قائمةٌ طويلة من خطوطٍ مضافة**. ونحن نستعمل خطّاً واحداً
/// (Tajawal) **مُحزَّماً أصلاً كأصلٍ محلّي** — `google_fonts` تبحث عن
/// `Tajawal-<Variant>.ttf` في AssetManifest قبل أيّ جلبٍ شبكي. فالخطوطُ الجديدة
/// لا تعنينا، والتقليمُ لا يعنينا، والانتقال يكسرنا. فالقرار: نبقى على ٨.
///
/// ═══ البوّابة ═══
///
/// تُرقّى حين يُعيد `flutter/material.dart` تصدير `material_ui` — أي بعد ترقية
/// Flutter، وهي قرارٌ منفصل بمخاطره (يُثبّت SDK في Codemagic وفي CI). عندها
/// يصير الترقيةُ سطراً واحداً ويسقط هذا الحارس، فتُحذف مع رفع القيد.
///
/// (و`go_router` رُقّيت إلى ١٨ في الدفعة نفسها: تنتقل إلى material_ui كذلك
/// **ولا تكسر شيئاً** — صفر خطأ في التحليل — لأنّ سطحَنا منها
/// `GoRoute`/`context.go`/`push`/`pop`/`redirect`/`GoRouterState` ولا شيء من
/// `ShellRoute`. وإصلاحا ١٨٫٠٫٢ يخصّان `ShellRoute` فلا يمسّاننا.)

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final lock = File('pubspec.lock').readAsStringSync();

  /// النسخة المحلولة لحزمةٍ من pubspec.lock.
  String? locked(String pkg) => RegExp(
        '^  $pkg:\\n(?:.*\\n)*?    version: "([^"]+)"',
        multiLine: true,
      ).firstMatch(lock)?.group(1);

  test('google_fonts مُقيَّدة على المِجَل ٨ بقصد', () {
    final m = RegExp(r'^  google_fonts:\s*\^?(\d+)\.',
        multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull, reason: 'لم يُوجَد قيد google_fonts في pubspec.yaml');
    expect(m!.group(1), '8',
        reason: 'رُفع القيد إلى مِجَلٍ آخر. إن كان ٩ فاقرأ ترويسة هذا الملفّ: '
            'المُعاد من tajawalTextTheme صار material_ui.TextTheme ولا يُسنَد '
            'إلى ThemeData.textTheme في Flutter 3.47.2 — والسؤال ليس كيف '
            'يُسكَت الحارس بل هل رُقّي Flutter.');
    expect(locked('google_fonts')?.startsWith('8.'), isTrue,
        reason: 'المحلول ${locked('google_fonts')} خارج المِجَل ٨');
  });

  test('السبب قائم: SDK ما زال يُعرّف TextTheme خاصّته', () {
    // هذا هو شرطُ البوّابة نفسه، مقروءاً من SDK الحاضر لا من ذاكرتنا. فإن
    // رُقّي Flutter وأُعيد تصدير material_ui سقط هذا الفحص — وهو **الإشارة
    // المقصودة**: حينها تُرقّى google_fonts ويُحذف هذا الملفّ.
    // **نبحث صعوداً ولا نَعُدّ الآباء:** نسختي الأولى أخذت ثلاثةَ آباء من
    // `resolvedExecutable` — وهو في الفحص `.../bin/cache/artifacts/engine/
    // linux-x64/flutter_tester` لا `dart` — فأشارت إلى `.../cache/artifacts`،
    // ولم يُوجَد الملفّ، فعاد الفحصُ مبكّراً **ولم يفحص شيئاً**. كان أخضرَ
    // وخاوياً. والآن: نصعد حتى نجده، ونُسقط الفحص إن لم نجده أصلاً — فالخمولُ
    // أسوأ من السقوط.
    const rel = 'packages/flutter/lib/src/material/text_theme.dart';
    File? textTheme;
    for (var d = File(Platform.resolvedExecutable).parent;
        d.path != d.parent.path;
        d = d.parent) {
      final f = File('${d.path}/$rel');
      if (f.existsSync()) {
        textTheme = f;
        break;
      }
    }
    expect(textTheme, isNotNull,
        reason: 'لم يُعثَر على $rel صعوداً من '
            '${Platform.resolvedExecutable} — الفحصُ بلا موضوع، فأصلِح المسار '
            'ولا تدَعه يمرّ خاوياً');
    expect(textTheme!.readAsStringSync().contains('class TextTheme'), isTrue,
        reason: 'SDK لم يَعُد يُعرّف TextTheme — أي أنّ انتقال material_ui تمّ. '
            'فارفع google_fonts إلى ٩ واحذف هذا الحارس.');
  });

  test('go_router على المِجَل ١٨ ولا نستعمل ShellRoute', () {
    final m = RegExp(r'^  go_router:\s*\^?(\d+)\.',
        multiLine: true).firstMatch(pubspec);
    expect(m?.group(1), '18', reason: 'تغيّر مِجَل go_router');
    expect(locked('go_router')?.startsWith('18.'), isTrue);
    // سطحُنا صغير، وعليه قام الحكمُ بأنّ ١٨ ترقيةٌ بلا مخاطر. فاستعمالُ
    // ShellRoute لاحقاً يُدخلنا في إصلاحَي ١٨٫٠٫٢ (الدلالات والمسارات
    // المدفوعة) — ويلزم إعادةُ تقييمٍ، لا تخطٍّ صامت.
    final dartFiles = sourcesIn('lib', atLeast: 100);
    final users = dartFiles
        .where((f) => f.readAsStringSync().contains('ShellRoute'))
        .map((f) => f.path)
        .toList();
    expect(users, isEmpty,
        reason: 'ظهر استعمالٌ لـShellRoute — أعِد تقييم سلوك go_router 18 '
            '(إصلاحا 18.0.2 يخصّانه)، ثم حدّث هذا الحارس:\n'
            '${users.join('\n')}');
  });
}
