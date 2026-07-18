import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (قرار المالك 2026-07-18) السائق يصله **بريد** عند إسناد طلب له — إضافةً للدفع
/// والوارد. مُثبَت حيّاً لسائقَين مختلفَين (zzahr9898@gmail.com و driver@zyiarah.com).
void main() {
  final fn = File('functions/index.js').readAsStringSync();

  test('queuePush تحمل عنوان مستلم صريح (للسائق)', () {
    expect(fn.contains('function queuePush(toUid, title, body, type, data, targetRoles, recipientEmail)'),
        isTrue);
    expect(fn.contains('...(recipientEmail ? {recipientEmail} : {})'), isTrue,
        reason: 'بدون تمرير العنوان يقع البريد على العنوان الإداري الافتراضي');
  });

  test('إسناد السائق يُرسل بريداً — منفصلاً عن الوارد/الدفع (بلا تكرار)', () {
    final i = fn.indexOf('exports.notifyDriverOnAssignment');
    final body = fn.substring(i, fn.indexOf('exports.', i + 10));
    // يجلب عنوان السائق ديناميكياً (drivers ثم users) — عام لأي سائق تضيفه الإدارة.
    expect(body.contains("collection(\"drivers\").doc(driverId).get()"), isTrue);
    expect(body.contains("collection(\"users\").doc(driverId).get()"), isTrue,
        reason: 'احتياطي: عنوان السائق قد يكون على مستند users');
    // نوع "email" + toUid=null ⇒ بريد فقط (لا وارد لأن toUid فارغ، ولا دفع للنوع email).
    expect(body.contains('"email",'), isTrue);
    expect(body.contains('driverEmail)'), isTrue);
    // لا يُرسل إلا إن كان له عنوان مسجَّل.
    expect(body.contains('if (driverEmail) {'), isTrue,
        reason: 'سائق بلا بريد لا يُرسَل له — وإلّا وقع على العنوان الإداري');
  });

  test('_pushToUid أُزيلت (كانت تتخطّى من لا توكن له)', () {
    expect(RegExp(r'_pushToUid\(').hasMatch(fn), isFalse,
        reason: 'كل الإشعارات صارت queuePush التي تكتب الوارد دائماً');
  });
}
