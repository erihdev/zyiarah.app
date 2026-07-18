import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (قرار المالك 2026-07-18) ميزتان:
/// 1. نافذة «يشترط وجود سيدة في المنزل» قبل طلب الخدمة الساعية (العاملات):
///    «نعم» يُكمل، «إلغاء» يمنع إكمال الطلب.
/// 2. قسم «العروض» + تحكّم الإدارة في مكان البانر (البانر الرئيسي أم قسم العروض).
void main() {
  final hourly = File('lib/screens/hourly_details_screen.dart').readAsStringSync();
  final admin = File('lib/screens/admin/admin_banners_screen.dart').readAsStringSync();
  final dash = File('lib/screens/client_dashboard.dart').readAsStringSync();
  final router = File('lib/router.dart').readAsStringSync();

  group('نافذة اشتراط وجود سيدة في المنزل', () {
    test('تظهر عند دخول شاشة الخدمة الساعية', () {
      expect(hourly.contains('_confirmWomanPresent'), isTrue);
      expect(hourly.contains('addPostFrameCallback((_) => _confirmWomanPresent())'),
          isTrue);
      expect(hourly.contains('يشترط وجود سيدة في المنزل'), isTrue,
          reason: 'النص يجب أن يطابق طلب المالك حرفياً');
    });

    test('نعم/إلغاء — والإلغاء يمنع إكمال الطلب', () {
      expect(hourly.contains("Text('نعم'"), isTrue);
      expect(hourly.contains("Text('إلغاء'"), isTrue);
      // الرفض/الإغلاق يعيد الشاشة السابقة فلا يُكمل الطلب.
      expect(hourly.contains('if (ok != true && mounted) Navigator.of(context).pop();'),
          isTrue,
          reason: 'بلا هذا يستطيع العميل إكمال الطلب دون الموافقة');
    });
  });

  group('العروض ومكان البانر', () {
    test('الإدارة تختار مكان الظهور وتحفظه', () {
      expect(admin.contains("data?['placement'] ?? 'main'"), isTrue,
          reason: 'الغياب = رئيسي كي تبقى البانرات القائمة على الرئيسية');
      expect(admin.contains("'placement': placement,"), isTrue);
      expect(admin.contains("Text('البانر الرئيسي')"), isTrue);
      expect(admin.contains("Text('قسم العروض')"), isTrue);
    });

    test('الرئيسية تعرض «الرئيسي» فقط، والعروض تعرض «offers»', () {
      // الرئيسية تستبعد offers.
      expect(dash.contains("p == null || p == 'main'"), isTrue,
          reason: 'بلا التصفية تظهر بانرات العروض على الرئيسية أيضاً');
      final offers = File('lib/screens/offers_screen.dart').readAsStringSync();
      expect(offers.contains("['placement'] == 'offers'"), isTrue);
    });

    test('قسم العروض في التنقّل السفلي وله مسار', () {
      expect(dash.contains("label: 'العروض'"), isTrue);
      expect(dash.contains("_openTab('/offers')"), isTrue);
      expect(router.contains("path: '/offers'"), isTrue);
    });
  });
}
