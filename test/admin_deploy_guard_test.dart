import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نشرُ اللوحة الإدارية آليّاً — `.github/workflows/admin_deploy.yml`.
///
/// اللوحةُ كانت تُنشَر باليد وحدها، فتغييراتُها تبقى مدمَجةً وغيرَ ظاهرة
/// للإدارة: نفسُ ثقبِ الدوالّ الذي أغلقه `functions_deploy.yml`. وتقسيمُ
/// محرّك الخرائط (#288) مثالٌ حيّ — مدموجٌ منذ 10-03 ولم يره أحد.
///
/// والجديدُ هنا أنّ `src/services/firebase.ts` **مُستثنى من git**، فكلُّ مسارِ
/// بناءٍ كان يصنعه لنفسه — نسخةٌ صوريّة مكتوبةٌ بخطّ اليد في `ci.yml`. تُفحص
/// بها الأنواعُ ولا تصلح للنشر، وتتباعد عن الحقيقيّ بصمت. فالمولّد الواحد
/// (`scripts/gen_firebase_config.mjs`) هو ما يحرسه هذا الملفّ قبل كلّ شيء.
void main() {
  final String wf =
      File('.github/workflows/admin_deploy.yml').readAsStringSync();
  final String ci = File('.github/workflows/ci.yml').readAsStringSync();
  final String gen =
      File('admin_panel/scripts/gen_firebase_config.mjs').readAsStringSync();

  /// الملفُّ بلا أسطر التعليق — الملفّات تشرح قراراتها بذكر ما تمنعه.
  String codeOf(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('#') && !t.startsWith('//');
      })
      .join('\n');

  group('نشرُ اللوحة آليّاً', () {
    test('يعمل عند الدمج، ومحصورٌ بما يمسّ اللوحة', () {
      expect(wf.contains('branches: [main]'), isTrue);
      expect(wf.contains("- 'admin_panel/**'"), isTrue);
      expect(wf.contains("- 'lib/firebase_options.dart'"), isTrue,
          reason: 'إعدادُ الويب يُولَّد منه، فتغيّرُه يغيّر ما يُنشَر');
      expect(wf.contains('workflow_dispatch:'), isTrue);
      expect(wf.contains('cancel-in-progress: false'), isTrue,
          reason: 'إلغاءُ نشرٍ في منتصفه يترك الاستضافة نصفَ محدّثة');
    });

    test('لا يُنشَر ما لم يُفحَص ويُبنَ — بهذا الترتيب', () {
      final int lint = wf.indexOf('run: npm run lint');
      final int test_ = wf.indexOf('run: npm test');
      final int build = wf.indexOf('run: npm run build');
      final int deploy = wf.indexOf('deploy --only hosting');
      for (final i in [lint, test_, build, deploy]) {
        expect(i, greaterThan(0));
      }
      expect(test_, lessThan(build));
      expect(build, lessThan(deploy),
          reason: 'النشرُ يرفع dist — بناءٌ بعده يعني نشرَ حزمةٍ قديمة');
      expect(lint, lessThan(deploy));
    });

    test('هدفُ الاستضافة محصورٌ بـadmin ومشروعٌ صريح', () {
      expect(wf.contains('--only hosting:admin'), isTrue,
          reason: 'هدفُ web هو صفحةُ الهبوط ولا يُنشر من هنا');
      expect(wf.contains('--project zyiarah-app'), isTrue);
      expect(wf.contains('--non-interactive'), isTrue);
      // الهدفُ معرَّفٌ فعلاً، وإلّا فشل النشر بعد البناء كلِّه.
      final String rc = File('.firebaserc').readAsStringSync();
      expect(rc.contains('"admin"'), isTrue);
    });

    test('المفتاحُ من سرِّ المستودع ويُمحى حتى عند الفشل', () {
      expect(wf.contains(r'${{ secrets.FIREBASE_SERVICE_ACCOUNT }}'), isTrue);
      expect(wf.contains('if: always()'), isTrue);
      expect(wf.contains('rm -f'), isTrue);
      expect(wf.contains('::error::'), isTrue,
          reason: 'سرٌّ ناقصٌ يفشل مبكراً برسالةٍ واضحة');
    });

    test('رمزُ Mapbox الناقص يفشل البناء ولا يمرّ بصمت', () {
      // غيابُه لا يكسر الترجمة — يترك `mapboxgl.accessToken` فارغاً فلا ترسم
      // خريطةُ المناطق في الإنتاج، وهو عطلٌ صامتٌ لا يكشفه شيء.
      expect(wf.contains('MAPBOX_TOKEN'), isTrue);
      expect(wf.contains('VITE_MAPBOX_TOKEN'), isTrue);
      final String picker =
          File('admin_panel/src/components/ZoneMapPicker.tsx').readAsStringSync();
      expect(picker.contains('import.meta.env.VITE_MAPBOX_TOKEN'), isTrue,
          reason: 'اسمُ المتغيّر تغيّر في اللوحة ولم يتغيّر في مسار النشر');
    });
  });

  group('مولّدُ إعداد Firebase — مصدرٌ واحد', () {
    test('المسارانِ كلاهما يستعمل المولّد نفسه', () {
      expect(wf.contains('node scripts/gen_firebase_config.mjs'), isTrue);
      expect(ci.contains('node scripts/gen_firebase_config.mjs'), isTrue,
          reason: 'CI يفحص الأنواع على ما يُنشَر لا على نسخةٍ صوريّة');
    });

    test('لا نسخةَ إعدادٍ مكتوبةً بخطّ اليد في أيّ مسار', () {
      for (final e in {'admin_deploy.yml': wf, 'ci.yml': ci}.entries) {
        expect(codeOf(e.value).contains('initializeApp('), isFalse,
            reason: '${e.key}: إعدادٌ مكتوبٌ داخل المسار يتباعد عن المولّد بصمت');
      }
    });

    test('يقرأ كتلةَ الويب وحدها — لا مفتاحَ منصّةٍ أخرى', () {
      // الأندرويد وiOS يحملان نفس أسماء الحقول بقيمٍ مختلفة في الملفّ نفسه،
      // فالتقاطٌ عامٌّ يأتي بمفتاحٍ خاطئ ولوحةٍ لا تسجّل الدخول.
      expect(gen.contains('FirebaseOptions web = FirebaseOptions'), isTrue,
          reason: 'المرساةُ ليست كتلةَ الويب');
      final String dart = File('lib/firebase_options.dart').readAsStringSync();
      expect(dart.contains('static const FirebaseOptions web = FirebaseOptions('),
          isTrue,
          reason: 'شكلُ ملفّ flutterfire تغيّر — المولّد سيفشل');
    });

    test('يفشل صراحةً بدل أن يكتب إعداداً ناقصاً', () {
      expect(gen.contains('throw new Error'), isTrue);
      for (final k in ['apiKey', 'projectId', 'appId', 'authDomain']) {
        expect(gen.contains("'$k'"), isTrue, reason: '$k ليس بين الحقول اللازمة');
      }
    });

    test('الملفُّ المولَّد يبقى خارج git', () {
      final String ig = File('.gitignore').readAsStringSync();
      expect(ig.contains('admin_panel/src/services/firebase.ts'), isTrue);
      expect(File('admin_panel/src/services/firebase.ts').existsSync(), anything);
    });

    test('يصدّر ما تستورده اللوحة فعلاً', () {
      // استيرادٌ غيرُ مصدَّر = فشلُ ترجمةٍ في CI وفي النشر معاً.
      for (final name in ['auth', 'db', 'storage', 'functions']) {
        expect(gen.contains('export const $name = '), isTrue,
            reason: 'المولّد لا يصدّر `$name`');
      }
      expect(gen.contains('export default app;'), isTrue,
          reason: 'Drivers.tsx يستورد التطبيقَ افتراضيّاً');
    });
  });
}
