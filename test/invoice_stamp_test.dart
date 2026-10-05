import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/invoice_view.dart';
import 'package:zyiarah/utils/invoice_stamp.dart';

/// **لحظةُ إصدارِ الفاتورةِ الضريبيّة** — ما كان مكسوراً، وما يَحرسه هذا الملفّ.
///
/// خمسةٌ من ستّةِ مواضعَ تبني رمزَ ZATCA كانت تُمرّر `timestamp: DateTime.now()`
/// — لحظةَ **توليدِ الملفّ** — و`zyiarah_pdf_service` كان يَطبعُ «التاريخ /
/// Date» من `DateTime.now()` هو أيضاً. وفي المسارِ السعيدِ الفرقُ ثوانٍ، لكنّ
/// للفاتورةِ **مسارَي إعادةِ توليدٍ مُنفَّذَين** (`invoice_pdf_status:
/// 'retrying'`): زرُّ العميلةِ في شاشةِ النجاح، وزرُّ الأدمنِ في سجلِّ
/// الفواتير. فإعادةُ توليدِ فاتورةٍ فشلت قبل أيّام كانت تَطبعُ **تاريخَ
/// اليوم** على فاتورةٍ ضريبيّةٍ مبسّطةٍ لطلبٍ دُفع قبل أيّام، ويَحملُ
/// رمزُها (Tag 3) التاريخَ الخاطئَ نفسَه — وهو تاريخُ التوريدِ الذي تَقرؤه
/// الهيئةُ من الرمز.
///
/// وفي شاشةِ الأدمنِ كانت `InvoiceView` المحمِّلةُ للصفِّ **تَحملُ**
/// `issuedAt` الصحيحَ، و`DateTime.now()` يُمرَّر بجوارِها حرفيّاً.
///
/// وتعليقُ `InvoiceView.qrData()` يقول إنّه «الرمزُ **نفسُه** الذي يُطبع في
/// PDF» — فبطاقةُ الشاشةِ (من `issuedAt`) ونسخةُ PDF (من `now`) كانتا
/// تَحملان **رمزَين مختلفَين** لفاتورةٍ واحدة، والتعليقُ يَنفي ذلك.
void main() {
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();

  /// `Timestamp.toDate()` يُعيد `DateTime` **محلّياً** لا UTC، فمقارنةُ
  /// `DateTime.utc(...)` تَفشلُ على العَلَم وحدَه واللحظةُ واحدة. نُقارن
  /// اللحظةَ — وهي ما يَعنينا (الرمزُ يُحوّل إلى UTC بنفسه).
  Matcher sameMoment(DateTime t) => predicate<DateTime>(
      (d) => d.isAtSameMomentAs(t), 'نفسُ اللحظة ${t.toIso8601String()}');

  /// يَحذفُ أسطرَ التعليقِ الكاملةَ — فالوحدةُ تَذكرُ `timestamp:
  /// DateTime.now()` في توثيقِها لتَشرحَ القاعدة، وأوّلُ صياغةٍ لهذا الحارسِ
  /// سقطت على توثيقِ نفسِها. ثمّ نؤكّد أنّ المصطلحَ ما زال في الخامِ كي لا
  /// يُفرِغَ التجريدُ الفحصَ من موضوعه.
  String stripComments(String src) => src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  /// يُفكّ TLV/Base64 إلى خريطةِ وسمٍ ← قيمة.
  Map<int, String> decodeTlv(String b64) {
    final bytes = base64.decode(b64);
    final out = <int, String>{};
    var i = 0;
    while (i + 1 < bytes.length) {
      final tag = bytes[i];
      final len = bytes[i + 1];
      out[tag] = utf8.decode(bytes.sublist(i + 2, i + 2 + len));
      i += 2 + len;
    }
    return out;
  }

  group('قاعدةُ لحظةِ الإصدار', () {
    test('paid_at أوّلاً، ثمّ created_at، ثمّ الآن', () {
      final paid = DateTime.utc(2026, 9, 1, 10);
      final created = DateTime.utc(2026, 8, 30, 8);
      final now = DateTime.utc(2026, 10, 5);
      expect(
          invoiceIssuedAt({
            'paid_at': Timestamp.fromDate(paid),
            'created_at': Timestamp.fromDate(created),
          }, now: now),
          sameMoment(paid));
      expect(
          invoiceIssuedAt({'created_at': Timestamp.fromDate(created)},
              now: now),
          sameMoment(created));
      expect(invoiceIssuedAt(const {}, now: now), sameMoment(now));
    });

    test('قيمةٌ ليست Timestamp تُتخطّى (لا تُفسَّر خطأً)', () {
      final now = DateTime.utc(2026, 10, 5);
      final created = DateTime.utc(2026, 8, 30);
      expect(
          invoiceIssuedAt({
            'paid_at': '2026-09-01T10:00:00Z',
            'created_at': Timestamp.fromDate(created),
          }, now: now),
          sameMoment(created),
          reason: 'نصٌّ في paid_at يجب أن يَسقطَ إلى created_at لا أن يُقبَل');
      expect(invoiceIssuedAt({'paid_at': 0, 'created_at': null}, now: now),
          sameMoment(now));
    });

    test('InvoiceView تَسألُ القاعدةَ نفسَها — لا نسخةً ثانية', () {
      final paid = DateTime.utc(2026, 9, 1, 10);
      final v = InvoiceView.fromOrder('ZY1', {
        'amount': 230.0,
        'paid_at': Timestamp.fromDate(paid),
      }, now: DateTime.utc(2026, 10, 5));
      expect(v.issuedAt, sameMoment(paid));
    });
  });

  group('الرمزُ مبنيٌّ على اللحظةِ المُمرَّرة', () {
    test('Tag 3 هو issuedAt بصيغةِ ISO 8601 بـZulu — لا لحظةُ التوليد', () {
      final issued = DateTime.utc(2026, 9, 1, 7, 30, 15);
      final tlv = decodeTlv(invoiceQrFor(issuedAt: issued, total: 230.0));
      expect(tlv[3], '2026-09-01T07:30:15Z');
      // وتوقيتٌ محلّيٌّ يُحوَّل إلى UTC لا يُطبَع كما هو.
      final local = DateTime(2026, 9, 1, 10, 30, 15);
      final tlv2 = decodeTlv(invoiceQrFor(issuedAt: local, total: 230.0));
      expect(tlv2[3], '${local.toUtc().toIso8601String().split('.').first}Z');
      expect(tlv2[3]!.endsWith('Z'), isTrue);
      expect(tlv2[3]!.contains('.'), isFalse, reason: 'بلا كسورِ ثانية');
    });

    test('الوسومُ الخمسةُ كاملةٌ وبالترتيب، والضريبةُ مُستخرَجةٌ من الشامل', () {
      final tlv = decodeTlv(
          invoiceQrFor(issuedAt: DateTime.utc(2026, 9, 1), total: 230.0));
      expect(tlv.keys.toList(), [1, 2, 3, 4, 5]);
      expect(tlv[2], '310885360200003');
      expect(tlv[4], '230.00');
      expect(tlv[5], '30.00', reason: '230 شامل ⇒ ضريبة 30 (لا 34.50)');
    });

    test('بطاقةُ الشاشةِ ونسخةُ PDF تَحملان الرمزَ نفسَه — ما كان التعليقُ '
        'يَزعُمه ولا يَصدُق', () {
      final paid = DateTime.utc(2026, 9, 1, 10);
      final data = {'amount': 230.0, 'paid_at': Timestamp.fromDate(paid)};
      final v = InvoiceView.fromOrder('ZY1', data);
      // ما يُبنى في مسارِ إعادةِ التوليد (من الوثيقة) = ما تَعرضُه البطاقة.
      final pdfSide = invoiceQrFor(
          issuedAt: invoiceIssuedAt(data), total: 230.0);
      expect(v.qrData(), pdfSide);
      // ولو بُني من «الآن» لاختلفا — وهذا ما كان.
      final wrong =
          invoiceQrFor(issuedAt: DateTime.utc(2026, 10, 5), total: 230.0);
      expect(v.qrData(), isNot(wrong));
    });
  });

  group('حارسُ المصدر', () {
    final qrSites = <String>[];
    final pdfSites = <String>[];

    setUpAll(() {
      for (final f in Directory('$repo/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        final rel = f.path.substring(repo.length + 1);
        if (src.contains('generateZatcaQrCode(')) qrSites.add(rel);
        if (src.contains('generateAndUploadInvoice(')) pdfSites.add(rel);
      }
    });

    test('generateZatcaQrCode يُنادى من بوّابةٍ واحدةٍ فقط في lib/', () {
      // قبلها: ستّةُ مواضعَ تُنادِيه مباشرةً، خمسةٌ منها بـ`DateTime.now()`.
      expect(qrSites..sort(),
          ['lib/services/zatca_service.dart', 'lib/utils/invoice_stamp.dart'],
          reason: 'موضعٌ يُنادي المولِّدَ مباشرةً — مرَّ بـinvoiceQrFor كي لا '
              'يُمرَّرَ DateTime.now() بالسهو:\n$qrSites');
    });

    test('لا موضعَ في lib/ يُمرّر timestamp: DateTime.now() إلى المولِّد', () {
      var documented = false;
      for (final f in Directory('$repo/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final raw = f.readAsStringSync();
        final rel = f.path.substring(repo.length + 1);
        if (raw.contains('timestamp: DateTime.now()')) documented = true;
        expect(stripComments(raw).contains('timestamp: DateTime.now()'), isFalse,
            reason: '$rel ما زال يَختمُ لحظةَ التوليد');
      }
      // التجريدُ لم يُفرِغ الفحص: المصطلحُ موجودٌ في الخامِ (توثيقُ الوحدة).
      expect(documented, isTrue,
          reason: 'المصطلحُ اختفى من المستودعِ كلِّه — راجِع صياغةَ الفحص');
    });

    test('كلُّ نداءٍ لـgenerateAndUploadInvoice يُمرّر issuedAt', () {
      expect(pdfSites.length, greaterThanOrEqualTo(5),
          reason: 'عددُ مواضعِ التوليدِ ${pdfSites.length} — أقلُّ من '
              'المتوقَّع، هل صار الحارسُ بلا موضوع؟');
      for (final rel in pdfSites) {
        if (rel == 'lib/services/zyiarah_pdf_service.dart') continue;
        final src = read(rel);
        final calls = 'generateAndUploadInvoice('.allMatches(src).length;
        expect('issuedAt:'.allMatches(src).length,
            greaterThanOrEqualTo(calls),
            reason: '$rel يُولّد فاتورةً بلا لحظةِ إصدار');
      }
    });

    test('مُولِّدُ PDF يَطبعُ issuedAt ولا يَلمسُ DateTime.now() للتاريخ', () {
      final pdf = read('lib/services/zyiarah_pdf_service.dart');
      expect(pdf, contains('required DateTime issuedAt'));
      expect(pdf, contains("intl.DateFormat('yyyy-MM-dd HH:mm').format(issuedAt)"));
      expect(pdf.contains("Date: \${DateTime.now()"), isFalse,
          reason: 'تاريخُ الفاتورةِ عاد إلى لحظةِ التوليد');
    });

    test('مسارا إعادةِ التوليدِ يَشتقّان اللحظةَ من الوثيقةِ لا من الآن', () {
      // هذان الموضعان هما حيث العطلُ كان حيّاً.
      final success = read('lib/screens/order_success_screen.dart');
      expect(success, contains('invoiceIssuedAt(data)'),
          reason: 'إعادةُ توليدِ العميلةِ تَطبعُ تاريخَ اليومِ مرّةً أخرى');
      final admin = read('lib/screens/admin/admin_invoices_screen.dart');
      expect(admin, contains('issuedAt: v.issuedAt'),
          reason: 'سجلُّ الأدمنِ يَحملُ اللحظةَ الصحيحةَ ويُهملُها مرّةً أخرى');
    });
  });
}
