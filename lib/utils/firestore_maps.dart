/// تطبيع الخرائط المتداخلة القادمة من Firestore.
///
/// **العطل الذي يمنعه:** `doc.data()` يُرجع `Map<String, dynamic>`، لكن الخرائط
/// **المتداخلة** بداخله تصل بنوع `Map<Object?, Object?>` (القناة الأصلية على
/// أندرويد، وتحويلات dartify على الويب في بعض الإصدارات). فالتحويل الصلب:
///
///     data['schedule'] as Map<String, dynamic>?   // يرمي TypeError
///
/// ينفجر لحظة وجود الحقل — وهكذا صار زرّ «تعديل المنطقة» ميتاً بلا أي رسالة لأي
/// منطقة حُفظ لها جدول فتح: الاستثناء يقع قبل `showDialog` فلا يُفتح شيء.
///
/// القاعدة: أي خريطة متداخلة من Firestore تمرّ من هنا، لا عبر `as`.
library;

/// يحوّل [v] إلى `Map<String, dynamic>` بمفاتيح نصّية **بعمق كامل**
/// (يشمل الخرائط داخل الخرائط وداخل القوائم). يُرجع null لغير الخرائط.
Map<String, dynamic>? stringKeyedMap(dynamic v) {
  if (v is! Map) return null;
  return v.map((k, val) => MapEntry('$k', _deep(val)));
}

dynamic _deep(dynamic v) {
  if (v is Map) return v.map((k, val) => MapEntry('$k', _deep(val)));
  if (v is List) return v.map(_deep).toList();
  return v;
}
