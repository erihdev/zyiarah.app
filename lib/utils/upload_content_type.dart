/// **نوعُ المحتوى يُصرَّحُ عند الرفعِ — وإلّا صارت قاعدةُ المخزنِ تَكسرُ الرفع.**
///
/// `storage.rules` تَحصرُ `banners/` و`products/` و`worker_photos/` و
/// `order_feedback/` في `contentType.matches('image/.*')` — وهو ما يَمنعُ
/// استعمالَ مخزنِ المشروعِ **استضافةً مجّانيّةً لأيِّ ملف** (صفحةُ تصيّدٍ أو
/// برمجيّةٌ خبيثةٌ على نطاقِ جوجل مربوطةٌ بدلونا)، لأنّ القواعدَ لا تَستطيعُ
/// قراءةَ Firestore فلا تَعرفُ الدورَ.
///
/// لكنّ `putData` **بلا بياناتٍ وصفيّةٍ يَرفعُ `application/octet-stream`**
/// (بخلافِ `putFile` الذي يَستنبطُ من الامتداد) — فثلاثةُ مواضعَ كانت
/// سَتُرفَضُ بالقاعدةِ الجديدة. فالنوعُ يُصرَّحُ صراحةً في كلِّ موضع، وهذه
/// القاعدةُ الواحدةُ تُشتَقُّه من الامتداد.
library;

/// نوعُ المحتوى لصورةٍ باسمِ [fileName] — `image/jpeg` افتراضاً.
String imageContentTypeFor(String fileName) {
  final String n = fileName.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.gif')) return 'image/gif';
  if (n.endsWith('.heic') || n.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}
