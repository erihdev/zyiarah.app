import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (دمج من لوحة الويب — قرار المالك 2026-07-21) دُمج إلى أدمن التطبيق (الأساس):
/// حظر/رفع حظر عميل (admin_users — يفرضه user_provider عبر status=='banned')،
/// ورفض طلب حذف حساب (admin_deletions — status='rejected' بدل الحذف الإجباري).
void main() {
  final users =
      File('lib/screens/admin/admin_users_screen.dart').readAsStringSync();
  final del =
      File('lib/screens/admin/admin_deletions_screen.dart').readAsStringSync();

  test('حظر/رفع حظر العميل يكتب status ويسجّل تدقيقاً + شارة الحالة الحقيقية', () {
    expect(users.contains("'status': isBanned ? 'active' : 'banned'"), isTrue,
        reason: 'الحظر بلا حذف — يفرضه التطبيق عبر status==banned');
    expect(users.contains('BAN_USER'), isTrue, reason: 'سجل تدقيق');
    // الشارة تعرض الحالة الحقيقية لا «عميل نشط» ثابتاً.
    expect(users.contains("user['status'] == 'banned'"), isTrue);
    expect(users.contains('محظور'), isTrue);
  });

  test('رفض طلب حذف الحساب يضبط status=rejected (لا حذف)', () {
    expect(del.contains("update({'status': 'rejected'})"), isTrue,
        reason: 'رفض الطلب بدل الحذف الإجباري');
    expect(del.contains('_rejectButton'), isTrue);
  });
}
