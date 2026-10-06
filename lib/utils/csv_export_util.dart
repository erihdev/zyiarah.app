import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

/// **تقريرُ المحاسبِ: نصٌّ يَكتبُه العميلُ ويُفتَحُ في جدولِ المالك.**
///
/// زرُّ «تصدير للتقرير المحاسبي» في `admin_orders_screen` يُحوّلُ مستنداتِ
/// `orders` إلى CSV ويَنسخُه إلى الحافظة، فيَلصقُه المالكُ في Excel أو
/// Sheets. وحقولُ الطلبِ تَحملُ ما تَكتبُه العميلةُ: `client_name`،
/// `client_phone`، الملاحظات، `rating_comment`. فهذه هي عائلةُ **حقنِ HTML
/// في بريدِ التنبيهِ الإداريّ** بعينِها، في جدولِ بياناتٍ بدلَ بريد: محتوى
/// العميلةِ يُعرَضُ على المالكِ في أداةٍ يَثِقُ بها.
///
/// وكان فيها ثلاثةٌ:
///
/// **١. حقنُ صيغةٍ (CSV formula injection).** خليّةٌ نصُّها يَبدأُ بـ`=` أو
/// `+` أو `-` أو `@` (أو جدولةٍ/رجوعِ سطر) تُعامَلُ **صيغةً** في Excel و
/// Sheets. والاقتباسُ **لا يَحمي**: `"=1+1"` يُحلَّلُ نصّاً `=1+1` ثمّ
/// يُقيَّمُ عند الاستيراد. فعميلةٌ تَضَعُ اسمَها
/// `=HYPERLINK("http://…","اضغط")` تَزرعُ رابطاً في تقريرِ المالك. والعلاجُ
/// المعياريُّ بادئةُ `'` تُبطِلُ التقييمَ وتَبقى الخليّةُ مقروءةً.
///
/// **٢. تهريبُ الاقتباسِ كان في فرعٍ واحدٍ من ستّة.** `value.toString()`
/// وحدَه كان يُضاعِفُ `"`، أمّا فرعُ القائمةِ (`join(' | ')`) فلا — واسمُ
/// منتجٍ فيه علامةُ اقتباسٍ يَكسِرُ الصفَّ كلَّه. والتهريبُ الآن **مرّةً
/// واحدةً بعد** بناءِ النصِّ، فلا فرعَ يَنساه.
///
/// **٣. و`Map` كانت تُصدَّرُ نصّاً حرفيّاً «Map Data»** — أي أنّ
/// `service_meta` (تفصيلُ الخدمةِ: القطعُ والمساحاتُ والأسعار) و`location`
/// و`price_*` تَخرُجُ من **التقريرِ المحاسبيِّ** فارغةَ المعنى. صارت JSON.
///
/// **ومرفوعٌ إلى المالكِ لا مُغيَّرٌ هنا:** الناتجُ يُنسَخُ إلى الحافظةِ لا
/// يُكتَبُ ملفّاً، ولصقُ نصٍّ مفصولٍ بفواصلَ في **Excel** لا يُوزّعُ الأعمدةَ
/// (Excel يُوزّعُ على الجدولةِ لا الفاصلة؛ وSheets يَعرضُ «تقسيم إلى أعمدة»).
/// فإمّا حفظُه ملفَّ `.csv` أو جعلُه مفصولاً بجدولةٍ — وذاك تغييرُ صيغةٍ
/// يَمَسُّ سيرَ عملِ المالك، لا إصلاحُ عطل.
class ZyiarahExportUtil {
  /// المحارفُ التي تُفتتحُ بها الصيغةُ في الجداول.
  static const _formulaStarts = <String>['=', '+', '-', '@', '\t', '\r'];

  /// خليّةٌ واحدةٌ: تهريبُ الاقتباسِ **ثمّ** إبطالُ الصيغةِ، في موضعٍ واحد.
  static String csvCell(String raw) {
    var v = raw;
    // بادئةٌ تُبطِلُ التقييمَ: `'` لا تُعرَضُ في الخليّةِ وتُلغي الصيغة.
    if (v.isNotEmpty && _formulaStarts.contains(v[0])) v = "'$v";
    return '"${v.replaceAll('"', '""')}"';
  }

  /// نصُّ قيمةِ Firestore للعرضِ — **قبلَ** التهريب.
  static String csvValue(Object? value) {
    if (value == null) return '';
    if (value is Timestamp) return value.toDate().toLocal().toString();
    if (value is GeoPoint) return 'Lat: ${value.latitude} Lng: ${value.longitude}';
    if (value is DocumentReference) return value.path;
    if (value is List) {
      // قائمةٌ من قيمٍ بسيطةٍ تُقرأُ أفضلَ مفصولةً، وقائمةٌ فيها خرائطُ
      // (`items`, `scheduled_visits`) كانت تُنتجُ `{a: 1, b: 2}` بأقواسٍ
      // وفواصلَ لا تُقرأُ ولا تُحلَّل — فتلك JSON.
      final simple = value.every((e) =>
          e == null || e is num || e is String || e is bool);
      if (simple) return value.map((e) => '${e ?? ''}').join(' | ');
      return jsonEncode(value.map(_jsonSafe).toList());
    }
    if (value is Map) return jsonEncode(_jsonSafe(value));
    return value.toString();
  }

  /// `jsonEncode` لا يَعرفُ أنواعَ Firestore، فتُحوَّلُ أوّلاً.
  static Object? _jsonSafe(Object? v) {
    if (v is Timestamp) return v.toDate().toLocal().toIso8601String();
    if (v is GeoPoint) return {'lat': v.latitude, 'lng': v.longitude};
    if (v is DocumentReference) return v.path;
    if (v is Map) {
      return v.map((k, val) => MapEntry('$k', _jsonSafe(val as Object?)));
    }
    if (v is List) return v.map(_jsonSafe).toList();
    return v;
  }

  /// تحويلُ مستنداتِ Firestore إلى CSV.
  static String convertToCsv(List<DocumentSnapshot> docs) {
    if (docs.isEmpty) return '';

    final headers = <String>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) headers.addAll(data.keys);
    }
    final headerList = headers.toList()..sort();

    final csv = StringBuffer();
    // الترويسةُ تُهرَّبُ كذلك: اسمُ حقلٍ فيه فاصلةٌ كان يُزيحُ كلَّ الأعمدة.
    csv.writeln(headerList.map(csvCell).join(','));

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      csv.writeln(
          headerList.map((h) => csvCell(csvValue(data[h]))).join(','));
    }
    return csv.toString();
  }
}
