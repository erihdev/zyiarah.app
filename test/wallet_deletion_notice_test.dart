import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/wallet_deletion_notice.dart';

void main() {
  final screen = File('lib/screens/profile_screen.dart').readAsStringSync();

  group('عندَ الجهلِ نُحذّر', () {
    test('رصيدٌ معروفٌ قائمٌ ⇒ تحذيرٌ بالرقم', () {
      expect(
          walletDeletionNotice(loaded: true, error: false, balance: 12.5),
          WalletDeletionNotice.balance);
    });

    test('رصيدٌ معروفٌ صفرٌ ⇒ لا شيء', () {
      expect(walletDeletionNotice(loaded: true, error: false, balance: 0),
          WalletDeletionNotice.none);
    });

    test('لم تُحمَّل بعد ⇒ تحذيرٌ بلا رقم — وهذا هو الخلل', () {
      // الرصيدُ 0.0 ابتداءً، فالشرطُ القديمُ `balance > 0` كاذبٌ فيَسكت:
      // عميلةٌ تَفتحُ الحوارَ قبلَ اكتمالِ القراءةِ تَحذفُ حسابَها بلا علم.
      expect(walletDeletionNotice(loaded: false, error: false, balance: 0),
          WalletDeletionNotice.unknown);
    });

    test('فشلت القراءةُ ⇒ تحذيرٌ بلا رقم', () {
      // الشرطُ القديمُ كان يَكتمُ التحذيرَ على الخطأِ **صراحةً**.
      expect(walletDeletionNotice(loaded: true, error: true, balance: 0),
          WalletDeletionNotice.unknown);
      expect(walletDeletionNotice(loaded: true, error: true, balance: 99),
          WalletDeletionNotice.unknown);
    });

    test('الجهلُ يَسبقُ الرقمَ: لم تُحمَّل ورصيدٌ قديمٌ في الذاكرة', () {
      expect(walletDeletionNotice(loaded: false, error: false, balance: 40),
          WalletDeletionNotice.unknown);
    });

    test('سالبٌ لا يُحجَز (دَينٌ لا رصيد)', () {
      expect(walletDeletionNotice(loaded: true, error: false, balance: -5),
          WalletDeletionNotice.none);
    });
  });

  group('الشاشةُ تَستعملُ القاعدةَ', () {
    test('الشرطُ القديمُ أُزيل', () {
      final code = screen.split('\n').where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      }).join('\n');
      expect(code.contains('!_walletError && _walletBalance > 0'), isFalse);
      // وبالمقابل: الشرطُ ما زال مذكوراً في التعليقِ الذي يَشرحُ حذفَه.
      expect(screen.contains('!_walletError && _walletBalance > 0'), isTrue,
          reason: 'لو غابَ من الخامِّ فالتجريدُ حَجبَ شيئاً');
    });

    test('الحالتانِ الظاهرتانِ معروضتان', () {
      expect(screen.contains('WalletDeletionNotice.balance'), isTrue);
      expect(screen.contains('WalletDeletionNotice.unknown'), isTrue);
    });

    test('نصُّ الجهلِ لا يَذكرُ رقماً ولا يَزعمُ وجودَ رصيد', () {
      final i = screen.indexOf('WalletDeletionNotice.unknown');
      expect(i, greaterThan(-1));
      final block = screen.substring(i, i + 1400);
      expect(block.contains('لم نتمكّن من التحقّق من رصيد محفظتك'), isTrue);
      expect(block.contains('إن كان'), isTrue, reason: 'شرطيٌّ لا جزميّ');
      expect(block.contains(r'$_walletBalance'), isFalse,
          reason: 'رقمٌ لا نَعرفُه لا يُعرَض');
    });

    test('تحذيرُ الرصيدِ المعروفِ ما زال يَذكرُ الرقم', () {
      expect(screen.contains('لديك \${_walletBalance.toStringAsFixed(2)} ر.س'),
          isTrue);
    });
  });
}
