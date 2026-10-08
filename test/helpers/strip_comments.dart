/// مُجرِّدُ التعليقاتِ المشترَكُ للحُرّاس — نسخةٌ واحدةٌ صحيحةٌ بدلَ ثلاثٍ.
///
/// كُتِبَ مرّةً في كلِّ حارسٍ ثمّ انحرفت النسخُ: صياغةُ «السطرُ يَبدأُ بـ`//`»
/// عمياءُ عن `{/* … */}` في JSX، وصياغةُ «من `/*` إلى `*/`» ابتلعت ملفّاً
/// كاملاً لأنّ `image/*` وردت **داخلَ تعليقِ سطر**. فالنسخةُ هنا واحدةٌ
/// ومُختبَرةٌ، ونسخةٌ رابعةٌ في حارسٍ جديدٍ تَنحرِفُ مثلَها.
library;

/// **حجبُ التعليقاتِ بحالةٍ واحدةٍ تَفهمُ السطرَ والكتلةَ والنصَّ معاً.**
///
/// ثلاثُ صياغاتٍ سقطت قبلَ هذه، وكلٌّ بفخٍّ مسجَّلٍ في هذا المستودع:
///   • «السطرُ يَبدأُ بـ`//`» عاجزٌ عن `{/* … */}` في JSX، فأسطُرُه التاليةُ
///     نصٌّ عارٍ بلا علامة (نفسُ فخِّ تعليقاتِ XML).
///   • ومُجرِّدُ كتلٍ يَمسحُ من `/*` إلى `*/` **وحدَه** يَبتلعُ الملفَّ كلَّه
///     متى ورد `/*` داخلَ تعليقِ سطرٍ — وقد حدثَ: `// … في `image/*`.` في
///     `admin_store_screen` لا `*/` بعدَها، فبَلغَ الحجبُ آخرَ الملفّ وقرأ
///     الفحصُ «الحقلُ لا يَمُرُّ بالقاعدة» وهو يَمُرّ.
///   • والمسحُ الذي يُحجَبُ فيه النصُّ كذلك يُعمي الفحصَ عن الحروفِ الحرفيّةِ
///     التي يَشدُّها (رسائلُ الخطأِ، أسماءُ الحقول).
///   • و**النصُّ القالبيُّ (`` ` ``) ليس من دلائلِ دارت فكان مُغفَلاً** —
///     والأثرُ أسوأُ من إغفالِ نصّ: `` `https://…` `` في `Settings.tsx`
///     و`ZoneMapPicker.tsx` يُحجَبُ من `//` إلى آخرِ السطر، فيَذهبُ معه
///     `${…}` بقوسَيه **وقوسُ غلقِ `href={`** — فتَنكسِرُ موازنةُ الأقواسِ
///     لكلِّ ما بعدَه في الملفّ، وكلُّ حارسٍ يَقتطِعُ جسمَ دالّةٍ بالموازنةِ
///     يَقرأُ مدًى خاطئاً بلا أن يَسقُط. و`${…}` شفرةٌ لا نصّ، فما فيها من
///     نصوصٍ وقوالبَ متداخلةٍ يُتخطّى بالتعاود (`Orders.tsx` يَحملُ قالباً
///     داخلَ `${…}` فعلاً).
/// فالقاعدةُ: نصٌّ **يُحفَظُ**، وتعليقُ سطرٍ وكتلةٍ يُمسَحانِ، والحالةُ واحدة.
String stripComments(String raw) {
  final out = StringBuffer();
  var i = 0;
  while (i < raw.length) {
    final c = raw[i];
    // نصٌّ: يُنسَخُ كما هو (الفحوصُ تَشدُّ حروفَه)
    if (c == "'" || c == '"') {
      final triple = raw.startsWith(c * 3, i);
      final q = triple ? c * 3 : c;
      out.write(q);
      i += q.length;
      while (i < raw.length) {
        if (raw[i] == r'\' && i + 1 < raw.length) {
          out.write(raw.substring(i, i + 2));
          i += 2;
          continue;
        }
        if (raw.startsWith(q, i)) {
          out.write(q);
          i += q.length;
          break;
        }
        out.write(raw[i]);
        i++;
      }
      continue;
    }
    // نصٌّ قالبيٌّ: يُنسَخُ كما هو، و`${…}` يُتخطّى بالتعاود (أقواسٌ متداخلة،
    // ونصوصٌ وقوالبُ داخلَها) — وإلّا أُفسِدَت موازنةُ الأقواسِ كما في الترويسة.
    if (c == '`') {
      final end = _templateEnd(raw, i);
      out.write(raw.substring(i, end));
      i = end;
      continue;
    }
    if (raw.startsWith('//', i)) {
      final nl = raw.indexOf('\n', i);
      i = nl < 0 ? raw.length : nl; // نُبقي السطرَ الجديد
      continue;
    }
    if (raw.startsWith('/*', i)) {
      final end = raw.indexOf('*/', i + 2);
      final span = end < 0 ? raw.substring(i) : raw.substring(i, end + 2);
      out.write(span.replaceAll(RegExp(r'[^\n]'), ' ')); // المواضعُ لا تَنزاح
      if (end < 0) break;
      i = end + 2;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// من موضعِ `` ` `` إلى ما بعدَ `` ` `` المقابل.
int _templateEnd(String raw, int i) {
  var j = i + 1;
  while (j < raw.length) {
    if (raw[j] == r'\') {
      j += 2;
      continue;
    }
    if (raw[j] == '`') return j + 1;
    if (raw.startsWith(r'${', j)) {
      j = _braceEnd(raw, j + 1);
      continue;
    }
    j++;
  }
  return raw.length;
}

/// من موضعِ `{` إلى ما بعدَ `}` المقابل، بتخطّي النصوصِ والقوالبِ داخلَه.
int _braceEnd(String raw, int i) {
  var depth = 0;
  var j = i;
  while (j < raw.length) {
    final ch = raw[j];
    if (ch == r'\') {
      j += 2;
      continue;
    }
    if (ch == '`') {
      j = _templateEnd(raw, j);
      continue;
    }
    if (ch == "'" || ch == '"') {
      j = _quoteEnd(raw, j);
      continue;
    }
    if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) return j + 1;
    }
    j++;
  }
  return raw.length;
}

int _quoteEnd(String raw, int i) {
  final q = raw[i];
  var j = i + 1;
  while (j < raw.length) {
    if (raw[j] == r'\') {
      j += 2;
      continue;
    }
    if (raw[j] == q) return j + 1;
    j++;
  }
  return raw.length;
}
