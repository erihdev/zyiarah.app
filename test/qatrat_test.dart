import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/qatrat.dart';

/// **سعرُ صرفِ النقاطِ في موضعٍ واحد، والرقمُ المعروضُ من الخادم.**
///
/// `50` كان مكتوباً بيدٍ في خمسةِ مواضع: شرطُ الخادمِ الأدنى، وقِسمةُ الخادمِ
/// (`pointsToRedeem / 50.0`)، وشرطُ الزرِّ في الشاشة، وتقريبُها لأقربِ
/// مضاعَف، وشريطُ التقدّم. وهو شكلُ قصّةِ الضريبةِ نفسُها (٢٧ موضعاً،
/// ٥٪ ← ١٥٪، وموضعٌ منسيٌّ يُنتج رقماً خاطئاً بصمت). التوحيدُ **وقائيّ**
/// وهذا الملفُّ يَقولُه صراحةً بدل أن يُلبِسَه ثوبَ عطلٍ حيّ.
///
/// **وما لم يكن وقائيّاً:** `redeemQatratPoints` الخادميّة تُعيد
/// `{success, newBalance, newPoints}`، وكانت الخدمةُ في Dart تُعيد `bool`
/// فتُهمل الرقمَين، وتُعيد الشاشةُ حسابَ المبلغِ بنفسِها
/// (`earned = toRedeem / 50.0`) وتَعرضُه للعميلة. فالرقمُ الذي تَقرؤه في
/// «تم استبدال ١٠٠ نقطة بـ٢٫٠٠ ر.س» لم يكن قادماً من الإيداعِ أصلاً — ولو
/// تَباعدَ سعرُ الصرفِ يوماً لبُشِّرت بمبلغٍ لم يُودَع. الشاشةُ الآن تَعرضُ
/// الفرقَ الذي أحدثَه الخادمُ فعلاً، وإن غابَ الرقمُ تقولُ نجاحاً بلا رقمٍ
/// مُختلَق (كما تفعل مع «—» في بقيّةِ البطاقة).
void main() {
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();

  group('الحسابُ خاصّيّةً', () {
    test('الثوابتُ متّسقة', () {
      expect(kQatratPerSar, 50);
      expect(kQatratRedeemMin, kQatratPerSar);
    });

    test('qatratRedeemable: صفرٌ تحت الحدّ، وأكبرُ مضاعَفٍ فوقه', () {
      for (var p = 0; p <= 600; p++) {
        final r = qatratRedeemable(p);
        if (p < kQatratRedeemMin) {
          expect(r, 0, reason: 'p=$p');
        } else {
          expect(r % kQatratPerSar, 0, reason: 'p=$p ليس مضاعَفاً');
          expect(r, lessThanOrEqualTo(p), reason: 'p=$p يَستبدلُ أكثرَ مما يملك');
          expect(p - r, lessThan(kQatratPerSar), reason: 'p=$p يَترك مضاعَفاً');
        }
      }
    });

    test('qatratToNextRedeem: المتبقّي، وصفرٌ بعد بلوغِ الحدّ', () {
      for (var p = 0; p <= 200; p++) {
        final n = qatratToNextRedeem(p);
        if (p >= kQatratRedeemMin) {
          expect(n, 0, reason: 'p=$p');
        } else {
          expect(n, kQatratRedeemMin - p, reason: 'p=$p');
          expect(n, greaterThan(0));
        }
      }
      // الحدُّ نفسُه: ٥٠ نقطةً تُستبدَل ولا «ينقصكِ».
      expect(qatratToNextRedeem(50), 0);
      expect(qatratRedeemable(50), 50);
      expect(qatratRedeemable(49), 0);
      expect(qatratToNextRedeem(49), 1);
    });

    test('سالبٌ أو صفرٌ لا يُنتج استبدالاً', () {
      for (final p in [-1, -50, 0]) {
        expect(qatratRedeemable(p), 0, reason: 'p=$p');
      }
    });
  });

  group('حارسُ المصدر', () {
    final screen = read('lib/screens/profile_screen.dart');
    final service = read('lib/services/zyiarah_wallet_service.dart');
    final idx = read('functions/index.js');

    // الشاشةُ والخدمةُ تَذكُران `toRedeem / 50.0` في تعليقَيهما لتَشرحا ما
    // كان — فالفحصُ على المصدرِ بعد تجريدِ أسطرِ التعليق، ثمّ نؤكّد أنّ
    // المصطلحَ في الخامِّ كي لا يُفرِغَ التجريدُ الفحصَ من موضوعه. (سقطَ
    // هذا الحارسُ على توثيقِ الإصلاحِ نفسِه أوّلَ مرّة.)
    String code(String src) => src
        .split('\n')
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
        })
        .join('\n');

    test('لا ٥٠ مكتوبةً بيدٍ في الشاشةِ ولا في الخدمة', () {
      expect(screen.contains('/ 50.0'), isTrue,
          reason: 'التعليقُ الذي يَشرحُ القاعدةَ حُذف — فالتجريدُ بلا موضوع');
      for (final entry in {
        'الشاشة': code(screen),
        'الخدمة': code(service),
      }.entries) {
        for (final lit in [
          '_qatratPoints < 50',
          '~/ 50) * 50',
          '/ 50.0',
          '50 - _qatratPoints',
          'pointsToRedeem < 50',
        ]) {
          expect(entry.value.contains(lit), isFalse,
              reason: '${entry.key}: «$lit» عادت — موضعُها lib/utils/qatrat.dart');
        }
      }
      expect(screen, contains('qatratRedeemable('));
      expect(screen, contains('qatratToNextRedeem('));
      expect(service, contains('kQatratRedeemMin'));
    });

    test('الشاشةُ تَعرضُ ما أودعَه الخادمُ لا حسابَها', () {
      expect(screen, contains('result.newBalance'),
          reason: 'الرقمُ المعروضُ ما زال محلّيّاً');
      expect(screen, contains('result.pointsRedeemed'));
      // وغيابُ الرقمِ = نصٌّ بلا رقمٍ لا رقمٌ مُختلَق.
      expect(screen, contains('credited == null'));
      expect(screen.contains("final earned ="), isFalse,
          reason: 'الحسابُ المحلّيُّ للمبلغِ عاد');
    });

    test('الخدمةُ تُعيد الرقمَين لا bool', () {
      expect(service, contains('Future<QatratRedeemResult?> redeemQatratPoints'));
      expect(service, contains("d['newBalance']"));
      expect(service, contains("d['newPoints']"));
      expect(service.contains('Future<bool> redeemQatratPoints'), isFalse);
    });

    test('والخادمُ ما زال يُعيدُهما — وإلّا فالقراءةُ بلا مصدر', () {
      expect(idx, contains('return {newBalance:'),
          reason: 'الدالّةُ الخادميّةُ لم تَعد تُعيد newBalance');
      expect(idx, contains('newPoints:'));
      // وسعرُ الصرفِ الخادميُّ هو نفسُه (٥٠ نقطة = ١ ر.س): لو تَغيّر هناك
      // وحدَه لانحرفَ عن kQatratPerSar بلا أن يَكسِرَ شيئاً.
      expect(idx, contains('pointsToRedeem / 50.0'),
          reason: 'سعرُ الصرفِ الخادميُّ تغيّر — حدِّث kQatratPerSar معه '
              '(هذا الفحصُ هو الرابطُ الوحيدُ بين الجهتَين)');
      expect(kQatratPerSar, 50);
    });
  });
}
