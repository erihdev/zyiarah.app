import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (دمج من لوحة الويب — قرار المالك 2026-07-21) وضع الصيانة: زر في إعدادات التطبيق
/// يكتب maintenance_mode، وAuthWrapper يفرضه على **العملاء فقط** (fail-open) عبر
/// شاشة صيانة. الإدارة والسائقون لا يتأثّرون كي يديروا/يوقفوا الصيانة.
void main() {
  final settings =
      File('lib/screens/admin/admin_settings_screen.dart').readAsStringSync();
  final main = File('lib/main.dart').readAsStringSync();

  test('الإعدادات تقرأ وتكتب maintenance_mode', () {
    expect(settings.contains("'maintenance_mode': _maintenanceMode"), isTrue);
    expect(
        settings
            .contains("_maintenanceMode = data['maintenance_mode'] == true"),
        isTrue);
  });

  test('AuthWrapper يفرض الصيانة على العملاء فقط (fail-open + شاشة صيانة)', () {
    expect(main.contains('_MaintenanceScreen'), isTrue,
        reason: 'شاشة الصيانة للعميل');
    expect(main.contains("data['maintenance_mode'] == true"), isTrue);
    // fail-open: العميل يرى ClientDashboard افتراضياً؛ الصيانة فقط عند العلم.
    expect(main.contains('return const ClientDashboard();'), isTrue);
    // الإدارة قبل فرع العميل فلا تُقفل بالصيانة.
    expect(main.contains('return const AdminDashboardScreen();'), isTrue);
  });

  // ── القرارُ واحدٌ، لا نسختان (2026-10-05) ───────────────────────────────
  //
  // كان في `main.dart` **موضعانِ** يَقرّران الصيانة: `_maintenanceGate` في
  // `MaterialApp.builder` (فوقَ كلِّ الشاشات)، و`StreamBuilder` ثانٍ داخلَ
  // فرعِ العميلِ في `AuthWrapper` على المستندِ نفسِه. والثاني **لا يُرى
  // خَرْجُه أبداً** — الخارجيّةُ تُغلِّفُ ناتجَه — فكلُّ ما كان يُنتجُه
  // مُستمِعُ Firestore ثانٍ لكلِّ عميلةٍ مسجَّلة.
  //
  // **والنسختانِ كانتا تَختلفان**، وهو الأهمّ: البوّابةُ تُغلِقُ على
  // `role == 'client'` بعينِه وتَقولُ «دورٌ غيرُ معروفٍ ⇒ لا يُقفل
  // (fail-open)»، والكتلةُ المحذوفةُ تُغلِقُ على العَلَمِ وحدَه — فدورٌ غيرُ
  // معروفٍ (لا `null`) كان يُقفَلُ خلافاً للقرارِ الموثَّقِ على بُعدِ خمسينَ
  // سطراً. والفحصُ القائمُ أعلاه مرَّ أخضرَ على ذلك كلِّه: يَطلبُ **حضورَ**
  // النصوصِ لا **وحدةَ** الموضع.
  group('قرارُ الصيانةِ موضعٌ واحد', () {
    /// `main.dart` بلا أسطرِ التعليق: الشرحُ أدناه يُسمّي ما يَبحثُ عنه
    /// الفحصُ، فمسحُ الخامِّ يُسقطُه على توثيقِه هو.
    String code() => main
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('مُستمِعٌ واحدٌ على main_settings، وفي البوّابةِ وحدَها', () {
      final c = code();
      final listens = RegExp(r"doc\('main_settings'\)")
          .allMatches(c)
          .length;
      expect(listens, 1,
          reason: 'عددُ قراءاتِ main_settings في main.dart = $listens — '
              'نسخةٌ ثانيةٌ من القرارِ تَكلِّفُ مُستمِعاً ولا تُرى');
      final decisions =
          RegExp(r"\['maintenance_mode'\] == true").allMatches(c).length;
      expect(decisions, 1,
          reason: 'القرارُ مكتوبٌ $decisions مرّات — والنسختانِ تَفترقان');
    });

    test('والقرارُ في MaterialApp.builder فوقَ كلِّ الشاشات', () {
      final c = code();
      final iBuilder = c.indexOf('builder: (context, child)');
      final iGate = c.indexOf('_maintenanceGate(context, child)');
      expect(iBuilder, greaterThan(-1), reason: 'بوّابةُ MaterialApp اختفت');
      expect(iGate, greaterThan(iBuilder),
          reason: 'البوّابةُ لم تُعَد مُطبَّقةً في builder — فلا تَغطّي شيئاً');
    });

    test('وفرعُ العميلِ يَعودُ باللوحةِ مباشرةً — لا مُستمِعَ ثانياً', () {
      final c = code();
      final iAdmin = c.indexOf('return const AdminDashboardScreen();');
      expect(iAdmin, greaterThan(-1));
      final after = c.substring(iAdmin);
      expect(after.contains('return const ClientDashboard();'), isTrue);
      expect(after.contains("doc('main_settings')"), isFalse,
          reason: 'عادَ المُستمِعُ الثاني إلى فرعِ العميل');
    });

    test('وفروعُ fail-open الأربعةُ باقيةٌ في البوّابة', () {
      final c = code();
      final iGate = c.indexOf('Widget _maintenanceGate(');
      expect(iGate, greaterThan(-1));
      final gate = c.substring(iGate);
      // الضيف، وتعذُّرُ التهيئة، وتحميلُ الدور، والدورُ غيرُ المعروف.
      expect(gate.contains('currentUser == null'), isTrue,
          reason: 'الضيفُ يُقفَل — وقاعدةُ system_configs تَرفضُ قراءتَه أصلاً');
      expect(gate.contains('} catch (_) {'), isTrue,
          reason: 'تعذُّرُ التهيئةِ يُسقطُ التطبيقَ بدلَ أن يَمرّ');
      expect(gate.contains('up.isLoading'), isTrue,
          reason: 'يُقفَلُ أثناءَ تحميلِ الدور');
      expect(gate.contains("up.role == 'client'"), isTrue,
          reason: 'القفلُ على العَلَمِ وحدَه ⇒ يُقفَلُ دورٌ غيرُ معروفٍ '
              'خلافاً للقرارِ الموثَّق');
      expect(gate.contains('firstEventTimeout()'), isTrue,
          reason: 'بثٌّ بذاكرةٍ باردةٍ لا يَرمي — يَنتظرُ للأبد');
    });

    test('والمضادّة: شرحُ الحذفِ ما زال في الخامّ', () {
      // الفحوصُ أعلاه تَقرأُ المُجرَّد؛ لو أفرطَ التجريدُ لَما وجدَ شيئاً.
      expect(main.contains('StreamBuilder'), isTrue,
          reason: 'اختفى شرحُ النسخةِ المحذوفةِ — فتُعادُ بلا علمٍ بسببِ زوالِها');
      expect(main.contains('fail-open'), isTrue);
    });
  });
}
