import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/csv_export_util.dart';
import 'helpers/strip_comments.dart';

/// **تقريرُ المحاسبِ: نصٌّ تَكتبُه العميلةُ ويُفتَحُ في جدولِ المالك.**
///
/// زرُّ «تصدير للتقرير المحاسبي» في `admin_orders_screen` يُحوّلُ مستنداتِ
/// `orders` إلى CSV ويَنسخُها إلى الحافظة، فيَلصقُها المالكُ في جدولٍ. وحقولُ
/// الطلبِ تَحملُ ما تَكتبُه العميلةُ (`client_name`، الملاحظات،
/// `rating_comment`) — فهي عائلةُ **حقنِ HTML في بريدِ التنبيهِ الإداريّ**
/// بعينِها، في جدولِ بياناتٍ بدلَ بريد.
///
/// وثلاثةٌ كانت فيها: **حقنُ صيغةٍ** (خليّةٌ تَبدأُ بـ`=`/`+`/`-`/`@` تُقيَّمُ
/// في Excel وSheets، **والاقتباسُ لا يَحمي**)، و**تهريبُ الاقتباسِ في فرعٍ
/// واحدٍ من ستّة** (فرعُ القائمةِ بلا تهريبٍ يَكسِرُ الصفَّ)، و**`Map`
/// تُصدَّرُ «Map Data»** فيَخرُجُ `service_meta` — تفصيلُ الخدمةِ والأسعارِ —
/// فارغَ المعنى من تقريرٍ محاسبيّ.
void main() {
  group('حقنُ الصيغةِ يُبطَل', () {
    test('كلُّ مفتاحِ صيغةٍ يُسبَقُ بعلامةٍ تُبطِلُه', () {
      for (final bad in ['=', '+', '-', '@', '\t', '\r']) {
        final cell = ZyiarahExportUtil.csvCell('${bad}SUM(A1:A9)');
        expect(cell.startsWith('"\''), isTrue,
            reason: 'خليّةٌ تَبدأُ بـ«$bad» تُقيَّمُ صيغةً: $cell');
      }
    });

    test('والهجمةُ الحقيقيّةُ: اسمٌ بصيغةِ رابط', () {
      const attack = '=HYPERLINK("http://evil","اضغط لتأكيد الطلب")';
      final cell = ZyiarahExportUtil.csvCell(attack);
      expect(cell.startsWith('"\'='), isTrue,
          reason: 'الصيغةُ لم تُبطَل — المالكُ يَرى رابطاً زرعَته العميلة');
      // ومع ذلك يَبقى النصُّ مقروءاً كما كتبَته (لا حذفَ ولا تشويه).
      expect(cell.contains('HYPERLINK'), isTrue);
    });

    test('ونصٌّ عاديٌّ لا يُمَسّ — ولا الأرقامُ ولا العربيّة', () {
      expect(ZyiarahExportUtil.csvCell('نورة'), '"نورة"');
      expect(ZyiarahExportUtil.csvCell('230'), '"230"');
      expect(ZyiarahExportUtil.csvCell(''), '""');
    });
  });

  group('التهريبُ موضعٌ واحدٌ لا فرعٌ', () {
    test('الاقتباسُ يُضاعَفُ أيّاً كان نوعُ القيمة', () {
      // فرعُ القائمةِ كان بلا تهريبٍ: اسمُ منتجٍ فيه `"` يَكسِرُ الصفّ.
      final listCell = ZyiarahExportUtil.csvCell(
          ZyiarahExportUtil.csvValue(['منظّف 20"', 'ممسحة']));
      expect(listCell, '"منظّف 20"" | ممسحة"');
      final strCell =
          ZyiarahExportUtil.csvCell(ZyiarahExportUtil.csvValue('قال "نعم"'));
      expect(strCell, '"قال ""نعم"""');
    });

    test('وفاصلةٌ أو سطرٌ جديدٌ داخلَ القيمةِ لا يَكسِرُ الصفَّ', () {
      final cell = ZyiarahExportUtil.csvCell(
          ZyiarahExportUtil.csvValue('حي الروضة, شارع 5\nالدور الثاني'));
      expect(cell.startsWith('"'), isTrue);
      expect(cell.endsWith('"'), isTrue);
      // محصورٌ باقتباسٍ، فالفاصلةُ والسطرُ داخلَه مشروعانِ في CSV.
      expect(cell.contains(','), isTrue);
    });
  });

  group('لا قيمةَ تَضيعُ من تقريرٍ محاسبيّ', () {
    test('`Map` صارت JSON بدلَ «Map Data»', () {
      final v = ZyiarahExportUtil.csvValue({
        'kind': 'sofa_rug',
        'pieces': [
          {'length': 2, 'width': 1.5, 'price_per_unit': 20},
        ],
      });
      expect(v.contains('Map Data'), isFalse,
          reason: 'تفصيلُ الخدمةِ يَخرُجُ فارغَ المعنى من تقريرٍ محاسبيّ');
      final back = jsonDecode(v) as Map<String, dynamic>;
      expect(back['kind'], 'sofa_rug');
      expect((back['pieces'] as List).first['price_per_unit'], 20);
    });

    test('وقائمةٌ من خرائطَ JSON، وقائمةٌ بسيطةٌ تَبقى مقروءةً', () {
      final items = ZyiarahExportUtil.csvValue([
        {'name': 'منظّف', 'quantity': 2},
      ]);
      expect(jsonDecode(items), isA<List<dynamic>>());
      expect(ZyiarahExportUtil.csvValue(['الرياض', 'جازان']), 'الرياض | جازان');
    });

    test('والغيابُ فراغٌ لا «null»', () {
      expect(ZyiarahExportUtil.csvValue(null), '');
      expect(ZyiarahExportUtil.csvCell(ZyiarahExportUtil.csvValue(null)), '""');
    });
  });

  group('والترويسةُ مُهرَّبةٌ كالصفوف', () {
    test('اسمُ حقلٍ فيه فاصلةٌ لا يُزيحُ الأعمدة', () {
      final src = stripComments(
          File('lib/utils/csv_export_util.dart').readAsStringSync());
      expect(src, contains('headerList.map(csvCell).join'),
          reason: 'الترويسةُ تُكتَبُ خامّةً — اسمُ حقلٍ فيه فاصلةٌ يُزيحُ '
              'كلَّ الأعمدةِ عن قيمِها');
      expect(src.contains("headerList.join(',')"), isFalse,
          reason: 'عادت الترويسةُ الخامّة');
      // ولا فرعَ يُهرِّبُ بنفسِه: التهريبُ في `csvCell` وحدَها.
      // **و`r"…"` لا يَقبلُ اقتباساً مُهرَّباً** (النصُّ يَنتهي عند أوّلِ
      // `"`), فالنمطُ بثلاثيٍّ — زلّةٌ أسقطت أوّلَ صياغةٍ عند الترجمة.
      const escape = r"""replaceAll('"', '""')""";
      expect(src.split(escape).length - 1, 1,
          reason: 'نسخةٌ ثانيةٌ من التهريبِ تَنحرِف');
    });

    test('ومُصدِّرُ الشاشةِ ما زال يُنادي القاعدةَ', () {
      final screen = stripComments(
          File('lib/screens/admin/admin_orders_screen.dart')
              .readAsStringSync());
      expect(screen, contains('ZyiarahExportUtil.convertToCsv'),
          reason: 'التصديرُ لا يَمُرُّ بالقاعدة');
    });

    test('ومضادَّةُ فرطِ الحجب: شرحُ القرارِ ما زال في الخامّ', () {
      final raw = File('lib/utils/csv_export_util.dart').readAsStringSync();
      for (final t in ['Map Data', 'formula injection', 'HYPERLINK']) {
        expect(raw, contains(t),
            reason: 'زالَ شرحُ العطلِ القديمِ، فلا يَعرفُ قارئٌ ما يُحرَس');
      }
    });
  });
}
