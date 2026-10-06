import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/strip_comments.dart';

/// **دليلُ الإصدارِ وثيقةٌ يُتَّبَعُ لا تُقرَأ — فأرقامُه ودعاواهُ تُشَدُّ.**
///
/// `claude_md_accuracy_test` يَشدُّ دقّةَ `CLAUDE.md` وحدَه، والقاعدةُ عامّةٌ:
/// **وثيقةٌ تَذكرُ رقماً من الشفرةِ تَبيتُ**. و`production_deployment_guide.md`
/// هو ما يَفتحُه المالكُ لحظةَ الإصدار، فبياتُه أغلى: وُجدت فيه ثلاثُ دعاوى
/// خاطئةٍ في 2026-10-06، أخطرُها **تُعطّلُ مراجعةَ أبل**:
///
///   • «الرقمُ الاختباريُّ … يتخطّى الـOTP — يلزم مراجعي أبل للدخول» — ولا
///     OTP في التطبيقِ إطلاقاً: مسارُ الجوّالِ حُذِفَ من الجذرِ في 2026-10-04
///     وحقلُ الدخولِ **بريدٌ إلكترونيٌّ** وكلمةُ مرور. فمراجعٌ يَتبعُ السطرَ
///     لا يَدخلُ، والنتيجةُ رفضٌ بسببِ وثيقةٍ لا بسببِ تطبيق.
///   • «٤٣٢ فحصاً» و«٦٤ فحص وحدة + ٤٢ فحص محاكي» — الأعدادُ الحقيقيّةُ أضعافُ
///     ذلك (١٣٦٩ و٣٢٩ و١٣٠).
///   • «عشرُ تغييراتٍ أمنيّةٍ تنتظر» — نسخةٌ ثانيةٌ من عددٍ يَسكنُ `CLAUDE.md`،
///     انحرفت عنه.
///
/// والعلاجُ قاعدتانِ: **ما يُمكِنُ اشتقاقُه يُشتَقُّ** (عددُ ملفّاتِ الفحص)،
/// و**ما لا يُعرَفُ إلّا بالتشغيلِ لا يُدوَّنُ** (عددُ الفحوصِ نفسُه — كثيرٌ
/// منها يُسجَّلُ في حلقات، فأيُّ رقمٍ يَبيتُ بالبناء)، و**العددُ لا يُنسَخُ**
/// بين وثيقتَين.
void main() {
  final guide = File('production_deployment_guide.md').readAsStringSync();

  group('دقّةُ دليلِ الإصدار', () {
    test('(أ) عددُ ملفّاتِ فحصِ دارت مُشتَقٌّ ومطابق', () {
      final n = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('_test.dart'))
          .length;
      expect(n, greaterThanOrEqualTo(100),
          reason: 'عددُ ملفّاتِ الفحصِ انهارَ — اشتقاقٌ فاشلٌ لا مستودعٌ أصغر');
      expect(guide, contains(_ar(n)),
          reason: 'الدليلُ يَذكرُ عدداً غيرَ $n لملفّاتِ فحصِ دارت');
    });

    test('(ب) عددُ ملفّاتِ فحصِ الدوالِّ مُشتَقٌّ من package.json', () {
      final pkg = jsonDecode(
          File('functions/package.json').readAsStringSync()) as Map;
      final scripts = pkg['scripts'] as Map;
      int files(String key) =>
          RegExp(r'node (test/[\w.]+\.js)').allMatches('${scripts[key]}').length;
      final unit = files('test');
      final emu = files('test:emulator');
      expect(unit, greaterThanOrEqualTo(20));
      expect(emu, greaterThanOrEqualTo(4));
      expect(guide, contains(_ar(unit)),
          reason: 'الدليلُ يَذكرُ عدداً غيرَ $unit لملفّاتِ فحصِ الوحدة');
      expect(guide, contains(_ar(emu)),
          reason: 'الدليلُ يَذكرُ عدداً غيرَ $emu لملفّاتِ المُحاكي');
    });

    test('(ج) لا عددَ فحوصٍ مدوَّنٌ في جدولِ CI — يَبيتُ بالبناء', () {
      final i = guide.indexOf('## 2. حرّاس ما قبل الدمج');
      final j = guide.indexOf('## 3.', i);
      expect(i, greaterThan(0));
      expect(j, greaterThan(i));
      final table = guide.substring(i, j);
      // «فحصاً/فحص وحدة/فحص محاكي» مسبوقاً برقمٍ عربيٍّ-هنديٍّ = عدُّ فحوصٍ
      // لا عدُّ ملفّات.
      final bad = RegExp(r'[٠-٩]+\s*فحص(اً| وحدة| محاكي)?(?!\s*ملفّ)')
          .allMatches(table)
          .map((m) => m.group(0))
          .where((t) => !t!.contains('ملفّ'))
          .toList();
      expect(bad, isEmpty,
          reason: 'عددُ فحوصٍ مدوَّنٌ في الجدول: $bad — يُعرَفُ بالتشغيلِ '
              'وحدَه فيَبيتُ. اكتُب عددَ الملفّاتِ (مُشتَقّاً) أو لا شيء');
    });

    test('(د) دعوى الـOTP زالت، والحقيقةُ مكتوبة', () {
      // النصُّ القديمُ يَبقى في **شرحِ** الإزالةِ لا في التوجيه، فالفحصُ على
      // التوجيهِ نفسِه: لا سطرَ يَأمرُ المراجعَ بتخطّي OTP.
      final smoke = guide.substring(guide.indexOf('## 3.'),
          guide.indexOf('## 4.'));
      expect(RegExp(r'^- \*\*الرقم الاختباري\*\*', multiLine: true)
          .hasMatch(smoke), isFalse,
          reason: 'عادَ توجيهُ «الرقمُ الاختباريُّ يتخطّى الـOTP» — ومراجعُ '
              'أبل يَتبعُه فلا يَدخل');
      expect(smoke, contains('الدخولُ بالبريدِ الإلكترونيِّ'),
          reason: 'الحقيقةُ غيرُ مكتوبةٍ — فالمراجعُ بلا توجيهٍ صحيح');
      // والشاهدُ من الشفرةِ: حقلُ الدخولِ بريدٌ، ولا نداءَ OTP للمصادقة.
      final login = stripComments(
          File('lib/screens/login_screen.dart').readAsStringSync());
      expect(login, contains('TextInputType.emailAddress'),
          reason: 'شاشةُ الدخولِ لم تَعُد بالبريد — يُراجَعُ نصُّ الدليل');
      final auth = stripComments(
          File('lib/services/firebase_service.dart').readAsStringSync());
      for (final gone in ['verifyOTP', 'verifyPhoneNumber', '_phoneToEmail']) {
        expect(auth.contains(gone), isFalse,
            reason: 'عادَ $gone — فدعوى «لا OTP» في الدليلِ تُراجَع');
      }
      // ومضادّةٌ: الاسمُ ما زال في النصِّ الخامِّ (تعليقُ القرار)، فتجريدٌ
      // مُفرِطٌ لا يُجوِّفُ الفحصَ.
      expect(File('lib/services/firebase_service.dart').readAsStringSync(),
          contains('OTP'),
          reason: 'تعليقُ القرارِ زالَ من الملفّ — فالفحصُ بلا ما يُميّزُه');
    });

    test('(و) لا تاريخَ «آخر تحديث» مكتوبٌ — git يَقولُه بلا أن يَبيت', () {
      // **شكلُ الدعوى لا ذِكرُها**: الفحصُ سقطَ على شرحي الذي يَقتبسُ
      // التاريخَ القديمَ — سابعَ عشَرَ مرّةٍ في هذا المستودع. والدعوى
      // **مُغلَّظةٌ** (`**آخر تحديث: …**`) والاقتباسُ عارٍ بين «…».
      expect(RegExp(r'\*\*آخر تحديث:\s*[٠-٩0-9]{4}-').hasMatch(guide), isFalse,
          reason: 'تاريخٌ مكتوبٌ بيدٍ في وثيقةٍ تُعدَّلُ كثيراً: كان يقولُ '
              '2026-09-21 بعد عشراتِ التعديلات. `git log` هو المصدر');
      // مضادّةٌ: العبارةُ ما زالت في النصِّ (شرحُ الإزالة)، فتضييقُ النمطِ
      // لم يَجعلْه بلا موضوع.
      expect(guide, contains('آخر تحديث'),
          reason: 'شرحُ القرارِ زالَ — فالفحصُ بلا ما يُميّزُه');
      expect(guide, contains('git log -1 -- production_deployment_guide.md'),
          reason: 'لا إحالةَ إلى المصدرِ الذي لا يَبيت');
    });

    test('(ز) README ليس قالبَ Flutter، ودعاواهُ مُشتَقّة', () {
      final readme = File('README.md').readAsStringSync();
      // كان القالبَ العاريَ («A new Flutter project») لتطبيقٍ تجاريٍّ بثلاثةِ
      // أسطحٍ وأربعةِ أهدافِ نشر — أكثرُ ملفٍّ يُقرأُ ولا يَقولُ شيئاً صحيحاً.
      for (final boilerplate in [
        'A new Flutter project',
        'This project is a starting point for a Flutter application',
      ]) {
        expect(readme.contains(boilerplate), isFalse,
            reason: 'README عادَ إلى قالبِ Flutter: «$boilerplate»');
      }
      // الأسطحُ الأربعةُ التي يَسمّيها موجودةٌ فعلاً
      for (final dir in ['lib', 'admin_panel', 'functions', 'landing_page']) {
        expect(readme, contains('`$dir/`'),
            reason: 'README لا يُسمّي $dir/');
        expect(Directory(dir).existsSync(), isTrue,
            reason: '$dir/ غيرُ موجودٍ — فالجدولُ يَكذِب');
      }
      // عددُ أهدافِ النشرِ **مُشتَقٌّ** لا مكتوب
      final targets = Directory('.github/workflows')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_deploy.yml'))
          .length;
      expect(targets, greaterThanOrEqualTo(3));
      expect(readme, contains(_arWord(targets)),
          reason: 'README يَذكرُ عدداً غيرَ $targets لأهدافِ النشر');
      // **كلُّ مسارٍ يُسمّيه README موجودٌ فعلاً** — والفحصُ يَستخرجُ المساراتِ
      // من النصِّ لا يُثبّتُها بيدِه: قضمةٌ غيّرت اسمَ المُولِّدِ في README
      // ومرَّت أخضرَ لأنّ الفحصَ كان يَسألُ عن ملفٍّ **كتبتُه أنا** لا عن
      // المسارِ المُدَّعى. «الدعوى تُتحقَّق» لا «ملفٌّ ما موجود».
      final claimed = RegExp(r'`([A-Za-z0-9_./-]+\.(?:mjs|yml|ts|dart|md))`')
          .allMatches(readme)
          .map((m) => m.group(1)!)
          .where((p) => p.contains('/') || p.endsWith('.md'))
          .toSet();
      expect(claimed.length, greaterThanOrEqualTo(4),
          reason: 'استخراجُ المساراتِ من README انهارَ — فحصٌ أجوف');
      for (final path in claimed) {
        expect(File(path).existsSync(), isTrue,
            reason: 'README يُحيلُ إلى مسارٍ لا وجودَ له: $path');
      }
      expect(File('.gitignore').readAsStringSync(),
          contains('admin_panel/src/services/firebase.ts'),
          reason: 'README يَقولُ إنّه مُستثنى من git وهو ليس كذلك');
    });

    test('(ح) لا وثيقةَ تَعرِضُ ميزةً أُزيلت من الجذرِ كأنّها قائمة', () {
      // أربعةُ قراراتٍ أُزيلت من الجذرِ ويَحرُسُها فحصٌ في الشفرة — والوثائقُ
      // كانت تَقولُ عكسَها: `ZIYARAH_BLUEPRINT.md` يَرسمُ **COD** طريقةَ دفعٍ
      // و**EDFAPAY** بوّابةً و«قبولَ السائقِ للطلب» خطوةً في دورةِ الحياة،
      // و`store_listing.md` يُعطي مراجعَ أبل **رمزَ تحقّقٍ ثابتاً** لمسارِ
      // دخولٍ لا وجودَ له. والوثيقةُ التي يُبنى عليها أخطرُ من شفرةٍ خاطئة:
      // لا فحصَ يَكشفُها، ومَن يَقرؤها يَبني أو يُراجِعُ على غيرِ الواقع.
      //
      // فالقاعدةُ: المصطلحُ يُذكَرُ **في سياقِ الإزالةِ** لا في سياقِ الوصف —
      // ويُميَّزُ بوجودِ كلمةٍ من «أُزيل/حُذِف/لا … في التطبيق/تصحيح» في
      // السطرِ نفسِه أو في السطرَين قبلَه.
      const removed = {
        'COD': 'الدفعُ عند التسليمِ — test/no_cod_test.dart',
        'EDFAPAY': 'بوّابةٌ لا وجودَ لها — البوّابةُ ميسر',
        'يقبل الطلب': 'لا قبول/رفضَ من السائق — قرارُ مالك',
        'رمز التحقق الثابت': 'لا OTP في التطبيق',
      };
      const removalWords = [
        'أُزيل', 'أُزيلت', 'حُذِف', 'حُذِفَ', 'تصحيح', 'كان يَرسمُ',
        'كان هذا السطرُ', 'لا وجودَ له', 'لا OTP', 'أُغلِق', 'بتاريخِه',
      ];
      final docs = Directory('.')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(docs.length, greaterThanOrEqualTo(5),
          reason: 'مسحُ الوثائقِ انهارَ — نطاقٌ أجوف');
      // **وثيقةٌ تُعلِنُ نفسَها تاريخيّةً لا تَدّعي الحاضر** — فتُستثنى
      // كاملةً، لكنْ بقائمةٍ مُسمّاةٍ ولكلٍّ سببُه، **ويُتحقَّقُ أنّ الإعلانَ
      // في رأسِها فعلاً** (وإلّا كان الاستثناءُ بابَ إسكات).
      const declaredHistorical = {
        './CLAUDE.md': 'سجلُّ القراراتِ نفسُه — يَذكرُ المُزالَ ليَشرحَ إزالتَه',
        './ZIYARAH_QA_AUDIT.md': 'تقريرُ تدقيقٍ بتاريخِه — ١٣٠٠ سطرٍ من مقتطفاتِ '
            'شفرةٍ قديمة، وتعليقُ كلِّ سطرٍ خطأٌ لا تصحيح',
        './ZIYARAH_BLUEPRINT.md': 'مخطّطٌ قديمٌ صُحِّحَ ما فيه عن الدفعِ '
            'والسائقِ، وبقيّتُه غيرُ مُراجَعةٍ سطراً سطراً — ورأسُه يَقولُ ذلك',
      };
      for (final entry in declaredHistorical.keys) {
        final f = File(entry);
        expect(f.existsSync(), isTrue, reason: 'مُستثنًى لا وجودَ له: $entry');
        if (entry == './CLAUDE.md') continue; // لا رأسَ إعلانٍ له، وهو الأصل
        final head = f.readAsLinesSync().take(20).join(' ');
        expect(
            removalWords.any(head.contains) ||
                head.contains('بتاريخِه') ||
                head.contains('تصحيح'),
            isTrue,
            reason: '$entry مُستثنًى بلا إعلانٍ في رأسِه — بابُ إسكات');
      }
      final offenders = <String>[];
      for (final f in docs) {
        if (declaredHistorical.containsKey(f.path)) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          for (final term in removed.keys) {
            if (!lines[i].contains(term)) continue;
            final window = lines
                .sublist((i - 2).clamp(0, lines.length), i + 1)
                .join(' ');
            if (removalWords.any(window.contains)) continue;
            offenders.add('${f.path}:${i + 1} «$term» — ${removed[term]}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'وثيقةٌ تَعرِضُ ميزةً مُزالةً كأنّها قائمة:\n'
              '${offenders.join('\n')}');

      // **ونافذةُ «كلمةِ الإزالةِ» لا تَكفي لرمزٍ له قيمة**: قضمةٌ أعادت
      // التوجيهَ وأبقت شرحي في السطرِ نفسِه فمرَّت أخضرَ. فالقيمةُ نفسُها
      // مُحرَّمةٌ بصيغتِها — رمزُ تحقّقٍ مقرونٌ بأرقام — أيّاً كان ما حولَه،
      // لأنّ **شكلَها هو التوجيه**: مَن يَقرؤها يُدخِلُها. «القدرةُ لا الاسم».
      for (final f in docs) {
        final text = f.readAsStringSync();
        // `\s*` وحدَها لا تَكفي: علامةُ التغليظِ `**` تَقعُ بين النقطتَين
        // والأرقامِ (`:** 123456`) — فأيُّ ستّةِ محارفَ غيرِ رقميّةٍ تَمُرّ.
        final m = RegExp(r'رمز التحقق[^\n]{0,40}[:：][^0-9٠-٩]{0,6}[0-9٠-٩]{4,}')
            .firstMatch(text);
        expect(m, isNull,
            reason: '${f.path}: رمزُ تحقّقٍ بقيمةٍ مكتوبةٍ «${m?.group(0)}» — '
                'ولا OTP في التطبيقِ أصلاً، فمَن يُدخِلُه لا يَدخُل');
      }
    });

    test('(هـ) لا عددَ محجوزاتِ STAGE-C مكتوبٌ في الدليل — نسخةٌ تَنحرِف', () {
      final i = guide.indexOf('## 1-و.');
      final j = guide.indexOf('## 2.', i);
      final sect = guide.substring(i, j);
      expect(RegExp(r'\*\*(عشر|إحدى عشرة|اثنتا عشرة|تسع)[^*]*تغييرات')
          .hasMatch(sect), isFalse,
          reason: 'عددُ المحجوزاتِ عادَ إلى الدليل — وهو يَسكنُ CLAUDE.md، '
              'ونسختانِ تَنحرِفان (وقد انحرفَتا)');
      expect(sect, contains('CLAUDE.md'),
          reason: 'الدليلُ لا يُحيلُ إلى سجلِّ المحجوزات');
      // والحجزُ نفسُه ما زال في القواعدِ — وإلّا فالقسمُ كلُّه بلا موضوع.
      expect(File('firestore.rules').readAsStringSync(), contains('STAGE-C'),
          reason: 'علاماتُ STAGE-C زالت من القواعد — يُراجَعُ القسم');
    });
  });
}

/// العددُ بالكلماتِ العربيّةِ كما يُكتَبُ في النصِّ الجاري (لا بالأرقام).
String _arWord(int n) => const {
      3: 'ثلاثةُ',
      4: 'أربعةُ',
      5: 'خمسةُ',
      6: 'ستّةُ',
    }[n] ??
    (throw StateError('لا كلمةَ لعددِ $n — أضِفها'));

/// الرقمُ بالأرقامِ العربيّةِ-الهنديّةِ كما تُكتَبُ في الوثيقة.
String _ar(int n) => n
    .toString()
    .split('')
    .map((d) => String.fromCharCode(0x0660 + int.parse(d)))
    .join();
