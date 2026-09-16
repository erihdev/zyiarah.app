/// رقم للمراسلة عبر wa.me: أرقام فقط بصيغة دولية عارية (بلا + ولا 00).
///
/// أرقام العملاء والسائقين تُحفظ محلياً غالباً («05xxxxxxxx» أو «5xxxxxxxx»)
/// بينما wa.me لا يقبل إلا الصيغة الدولية — فيُلحق رمز السعودية 966 بها.
/// يعيد '' حين لا رقم.
String whatsappNumber(String? raw) {
  if (raw == null) return '';
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.length == 10 && digits.startsWith('05')) {
    return '966${digits.substring(1)}';
  }
  if (digits.length == 9 && digits.startsWith('5')) return '966$digits';
  return digits;
}
