// ════════════════════════════════════════════════════════════════════════
// دليلُ النشرِ مقابلَ مساراتِ النشرِ نفسِها (2026-10-05)
//
// `production_deployment_guide.md` هو ما يَتبعُه المالكُ **لحظةَ الإصدار**،
// ولم يَكُنْ يَقرؤه فحصٌ قطّ — فانحرفَ عن الشفرةِ في موضعَين، والثاني أخطرُ:
//
// (أ) كان يَقول «**بلا `--force`** عمداً» وقد صارَ المسارُ يُمرّرُه (محروساً
//     بخطوةِ `Refuse a silent deletion`)، وجدولُ أعطالِه يُحيلُ إلى تلك
//     الفقرةِ لرسالةٍ لم تَعُد تَظهر.
//
// (ب) وكان §5 يَقول عن `android_release.yml` إنّه يَبني AAB «**بلا نشر**»
//     تحتَ عنوانٍ يَقول «مساران لا يصلان المتاجر» — وهو **يَرفعُ إلى Google
//     Play** عبر `upload-google-play` وقد عملَ ثماني مرّات. فمَن يَدفعُ وسماً
//     ظانّاً أنّه بلا أثرٍ يَرفعُ مسوّدةً إلى المتجر. وهذا الادّعاءُ نفسُه
//     كان في `CLAUDE.md` فصُحِّح هناك **وبقي هنا**: «قاعدةٌ عامّةٌ مُنفَّذةٌ
//     في سطحٍ واحد» واقعةً على التوثيق.
//
// فالقاعدةُ: كلُّ ادّعاءٍ في الدليلِ عن مسارِ نشرٍ يُقابَلُ بالملفِّ نفسِه،
// ومجموعةُ الأهدافِ **مُشتَقّةٌ** من `.github/workflows/*_deploy.yml` لا
// مكتوبةً بيد — فهدفٌ خامسٌ يَدخلُ النطاقَ بنفسِه.
// ════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// يَحجبُ أسطرَ تعليقِ YAML — تعليقاتُ المساراتِ تَشرحُ القراراتِ بتسميةِ
/// الأعلامِ (`--force` مثلاً) داخلَ نصِّها، فمسحٌ على الخامِّ يُصدّقُ شرحاً
/// مكانَ شفرة. وهو الفخُّ المسجَّلُ في هذا المستودعِ اثنتَي عشرةَ مرّة.
String _stripYaml(String s) => s
    .split('\n')
    .map((l) => l.trimLeft().startsWith('#') ? ' ' * l.length : l)
    .join('\n');

void main() {
  final guide = File('production_deployment_guide.md').readAsStringSync();
  final wfDir = Directory('.github/workflows');

  /// أهدافُ النشرِ مُشتَقّةً من المجلّد.
  Map<String, String> deployWorkflows() {
    final out = <String, String>{};
    for (final f in wfDir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.endsWith('_deploy.yml')) out[name] = f.readAsStringSync();
    }
    return out;
  }

  test('(أ) الاشتقاقُ وجدَ المساراتِ فعلاً — فلا فحصَ على فراغ', () {
    final wf = deployWorkflows();
    expect(wf.length, greaterThanOrEqualTo(4),
        reason: 'مساراتُ النشرِ لم تُقرأ: ${wf.keys}');
    for (final n in [
      'functions_deploy.yml',
      'admin_deploy.yml',
      'firestore_indexes_deploy.yml',
      'landing_deploy.yml',
    ]) {
      expect(wf.containsKey(n), isTrue, reason: '$n خارجَ الاشتقاق');
    }
  });

  test('(ب) الدليلُ يُسمّي كلَّ مسارِ نشرٍ موجود', () {
    // هدفٌ لا يَذكرُه الدليلُ هو هدفٌ يَنشرُ في الإنتاجِ ولا يَعلمُ به
    // المالكُ — وهو بعينُه ما كان عليه `hosting:web` حتى 2026-10-05.
    for (final name in deployWorkflows().keys) {
      expect(guide.contains(name), isTrue,
          reason: '$name يَنشرُ في الإنتاجِ ولا يَذكرُه دليلُ الإصدار');
    }
  });

  test('(ج) ادّعاءُ `--force` في الدليلِ يُطابقُ المسارَ', () {
    final dep = _stripYaml(deployWorkflows()['functions_deploy.yml']!);
    final hasForce = dep.contains('--force');
    if (hasForce) {
      expect(guide.contains('**بلا `--force`** عمداً'), isFalse,
          reason: 'الدليلُ يَقولُ «بلا --force» والمسارُ يُمرّرُه');
      expect(guide.contains('Refuse a silent deletion'), isTrue,
          reason: 'الدليلُ لا يَذكرُ الحارسَ الذي صارَ يُنفّذُ القرار');
      expect(guide.contains('functions:list'), isTrue,
          reason: 'الدليلُ لا يَشرحُ كيف يُمنَعُ الحذفُ الصامتُ الآن');
    } else {
      expect(guide.contains('بلا `--force`'), isTrue,
          reason: 'المسارُ بلا العلمِ والدليلُ لا يَقولُه');
    }
  });

  test('(د) لا يَقولُ الدليلُ عن مسارٍ يَنشرُ إنّه «بلا نشر»', () {
    // مجموعةُ ما يَرفعُ إلى Google Play مُشتَقّةٌ من المجلّدِ كلِّه.
    final publishers = <String>[];
    for (final f in wfDir.listSync().whereType<File>()) {
      final body = _stripYaml(f.readAsStringSync());
      if (body.contains('upload-google-play')) {
        publishers.add(f.uri.pathSegments.last);
      }
    }
    expect(publishers, contains('android_release.yml'),
        reason: 'اختفى ناشرُ Play — راجِعِ القسمَ ٥ من الدليل');
    for (final n in publishers) {
      final i = guide.indexOf(n);
      expect(i, greaterThan(-1), reason: '$n يَرفعُ إلى Play ولا يَذكرُه الدليل');
      // في فقرتِه: لا «بلا نشر» ولا «لا يصل» — وهو يَنشرُ فعلاً.
      final para = guide.substring(i, (i + 900).clamp(0, guide.length));
      expect(para.contains('بلا نشر'), isFalse,
          reason: '$n يَرفعُ إلى Play والدليلُ يَقولُ «بلا نشر»');
    }
  });

  test('(هـ) وجدولُ الأعطالِ يُسمّي سببَ التوقّفِ الذي حدثَ فعلاً', () {
    // سبعُ تشغيلاتٍ متتاليةٍ فشلت برسالةِ سياسةِ إعادةِ المحاولة، ولم تَكُن
    // في الجدولِ إطلاقاً — فالمالكُ يَبحثُ عن أقربِ سببٍ ويُخطئ.
    // **والعبارةُ وحدَها لا تَكفي:** هي في فقرةِ القرارِ أيضاً، فاختبارُ
    // قضمٍ حذفَها من الجدولِ ومرَّ **أخضرَ** — نفسُ درسِ «العبارةُ المشترَكةُ
    // والعتبةُ العدديّةُ لا تَكفيان» في حارسِ مسارِ الدوالّ. فالمشدودُ هو
    // **صفُّ الجدولِ** بنصِّه: وجودُه هو ما يَمنعُ المالكَ من البحثِ عن أقربِ
    // سببٍ خاطئ.
    final rows = RegExp(r'^\| .*failure policy', multiLine: true)
        .allMatches(guide)
        .length;
    expect(rows, 1,
        reason: 'صفُّ سياسةِ إعادةِ المحاولةِ ليس في جدولِ الأعطال');
    expect(guide.contains('لا يُتوقَّع بعد 2026-10-05'), isTrue,
        reason: 'الصفُّ لا يَقولُ إنّ الرسالةَ لم تَعُد متوقَّعةً — فيُقرأُ '
            'كأنّها عطلٌ قائم');
    expect(guide.contains('cloudscheduler.jobs.update'), isTrue,
        reason: 'فشلُ الأدوارِ المجدولةِ ليس في الجدول');
  });

  test('(و) وما لا يُنشَر من الأتمتةِ مُعلَنٌ في الدليل', () {
    // القواعدُ ومخزنُ الملفّاتِ محجوزانِ بيدٍ بشريّة — وغيابُهما عن الدليلِ
    // يَعني إصلاحاً أمنيّاً يَحسبُه المالكُ منشوراً.
    expect(guide.contains('storage.rules'), isTrue,
        reason: 'مخزنُ الملفّاتِ لا مسارَ له ولا يَذكرُه الدليل');
    expect(guide.contains('STAGE-C'), isTrue,
        reason: 'حجزُ القواعدِ ليس في الدليل');
    for (final name in deployWorkflows().keys) {
      final body = _stripYaml(
          File('.github/workflows/$name').readAsStringSync());
      expect(body.contains('storage:rules'), isFalse,
          reason: '$name صارَ يَنشرُ مخزنَ الملفّاتِ — قرارٌ بشريّ');
      expect(body.contains('firestore:rules'), isFalse,
          reason: '$name صارَ يَنشرُ القواعدَ — حجزُ STAGE-C');
    }
  });
}
