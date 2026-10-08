import 'dart:io';

import 'strip_comments.dart';

/// حِملُ كتابةٍ واحدٍ على `notifications_log` من شفرةِ دارت.
typedef NotifLogWrite = ({String file, Map<String, String> fields});

/// **كلُّ كاتبٍ لـ`notifications_log` في `lib/`، بحقولِه.**
///
/// نطاقٌ مُشتَقٌّ لا قائمةٌ مكتوبةٌ بيد: كاتبٌ رابعٌ يَدخلُ نطاقَ أيِّ حارسٍ
/// يَستعملُ هذه الدالّةَ بنفسِه. ويُستعمَلُ في حارسَين (جمهورُ البثّ، وحضورُ
/// حقلِ الترتيب) فيُسكَنُ هنا مرّةً — نسختانِ تَنحرِفان.
///
/// الاقتطاعُ بموازنةِ المعقوفةِ من `({` الحِملِ نفسِه، لا «أقربُ ذكرٍ
/// للمجموعةِ قبلَ الموضع»: أوّلُ صياغةٍ فعلت ذلك فنسبَت `'target': _target`
/// في **سجلِّ التدقيقِ** (`logAction(details: {...})`) إلى الكتابةِ التي
/// تَسبقُه — إبلاغٌ خاطئٌ لا ثغرة. والحقولُ تُقرأُ على **العمقِ الأوّلِ
/// وحدَه**، فخريطةٌ متداخلةٌ لا تُخلَطُ بحقلِ المستند.
List<NotifLogWrite> notificationsLogWrites({String root = 'lib'}) {
  final out = <NotifLogWrite>[];
  for (final e in Directory(root).listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final String src = stripComments(e.readAsStringSync());
    int from = 0;
    while (true) {
      final int c = src.indexOf("collection('notifications_log')", from);
      if (c < 0) break;
      from = c + 1;
      // أوّلُ `({` بعدَ النداء — حِملُ `add`/`set`/`update`. وبُعدُه عنه
      // محدودٌ كي لا يُلتقَطَ حِملُ كتابةٍ أخرى بعدَ **قراءةٍ** من المجموعة.
      final int brace = src.indexOf('({', c);
      if (brace < 0 || brace - c > 90) continue;
      int depth = 0;
      int end = -1;
      for (int k = brace + 1; k < src.length; k++) {
        if (src[k] == '{') depth++;
        if (src[k] == '}') {
          depth--;
          if (depth == 0) {
            end = k;
            break;
          }
        }
      }
      if (end < 0) continue;
      // `brace` يُشيرُ إلى `(` و`brace + 1` إلى `{` — فبدايةُ الحِملِ
      // `brace + 2`. أوّلُ صياغةٍ أخذَت `brace + 1` فصارَ العمقُ واحداً عند
      // كلِّ حقلٍ عُلويٍّ فقُرئَت **صفرُ حقولٍ** لكلِّ كاتب — عُقمٌ تَكشفُه
      // أرضيّةُ الحقولِ في الحارسَين.
      final String payload = src.substring(brace + 2, end);
      final fields = <String, String>{};
      int d = 0;
      for (final m in RegExp(r"'([A-Za-z_][A-Za-z0-9_]*)':\s*([^,\n]+)|[{}\[\]]")
          .allMatches(payload)) {
        final String t = m.group(0)!;
        if (t == '{' || t == '[') {
          d++;
          continue;
        }
        if (t == '}' || t == ']') {
          d--;
          continue;
        }
        if (d == 0) fields[m.group(1)!] = m.group(2)!.trim();
      }
      out.add((file: e.path, fields: fields));
    }
  }
  return out;
}
