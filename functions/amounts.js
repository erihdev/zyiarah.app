"use strict";

// أيُّ حقلٍ هو «المبلغ»؟ — **سؤالان مختلفان، لكلٍّ ترتيبه، كلٌّ في موضع واحد.**
// (`node test/amounts.test.js` ضمن npm test.) نقيّة بلا db كـpricing وvat.
//
// ═══ السؤالان ═══
//
// **أ) كم كان يجب أن يُدفَع؟** — فحصُ التلاعب قبل تأكيد طلبٍ مدفوع. يقارن
//    المبلغ المخصوم فعلاً بما يستحقّه الطلب، ويمنع دفع ريالٍ لطلبٍ كبير.
//
// **ب) كم نستردّ؟** — المبلغ الكامل المستحقّ للعميل عند الاسترداد.
//
// وهما يتّفقان في الترتيب اليوم، لكنهما **ليسا نفس السؤال**: الأوّل يُقارَن
// بمبلغٍ وصل من البوابة، والثاني يُرسَل إليها. فصلُهما بالاسم يجعل كل تغييرٍ
// في أحدهما قراراً صريحاً لا أثراً جانبيّاً.
//
// ═══ ولماذا الترتيب `final_amount` أوّلاً ═══
//
// `final_amount` هو **السعر الذي اعتمدته الإدارة** — تقابله `total_amount`
// (سعر السلة) في شاشة طلبات المتجر: «المعتمد: X ر.س (السلة: Y)». فتقديم
// الأساسي عليه يقارن بسعرٍ قديم. وتعليق `moyasarWebhook` يقول ذلك صريحاً:
// «وإلا رُفضت دفعة حقيقية عند تعديل السعر».
//
// ═══ والانحراف الذي وُجد (كامنٌ لا حيّ — والتمييز مهمّ) ═══
//
// كان `reconcileOrphanPayments` يرتّب `amount` **أوّلاً**:
//
//     amount ?? final_amount ?? total_amount ?? planPrice ?? 0
//
// بينما `moyasarWebhook` و`tabbyWebhook` يقدّمان `final_amount`. ومقارنتُه
// `paidH >= expectedH` (لا تساوياً)، فالأثر باتجاه واحد:
//
//   تعديلٌ **صاعد** (رسوم توصيل): المتوقَّع أقلّ ⇒ الدفعة تغطّيه ⇒ يُستردّ الطلب.
//   تعديلٌ **هابط** (حذف صنف، خصم): المتوقَّع أكبر من المدفوع ⇒ «amount too low»
//                                   ⇒ **لا يُستردّ** طلبٌ دفع العميل ثمنه.
//
// **وهو كامن اليوم**: لا شيء في المستودع يكتب `final_amount` إطلاقاً (١٢ قراءةً
// في index.js وصفر كتابة)، وطلب المتجر يُنشأ بـ`amount == total_amount`. فكل
// المواضع تحلّ إلى القيمة نفسها. ويصير حيّاً متى ضُبط `final_amount` من خارج
// التطبيق — وهو ما تتوقّعه الشفرة نفسها («بعد تعديل الإدارة») وتعرضه الشاشة.
// فالإصلاح وقائيّ: يُسوّى الترتيب الآن كي لا يصير العطل حيّاً بتعديلٍ يدويّ واحد.
//
// ═══ وما لا يمرّ من هنا ═══
//
// **مبالغ العرض** (سطر الإجمالي في بريد الإدارة، صفوف الإشعار) تبقى كما هي:
// سؤالها «ما نُظهره للقارئ»، وتستعمل `||` فيتخطّى الصفر إلى حقلٍ آخر — وهو
// مقبولٌ في عرضٍ لا يُقارَن به مال. توحيدها هنا يُقحم قرار عرضٍ في وحدة مال.

/** ترتيب الحقول: المعتمد إدارياً، ثم السلة، ثم سعر الباقة، ثم الأساسي. */
const FIELD_ORDER = ["final_amount", "total_amount", "planPrice", "amount"];

/**
 * يقرأ أوّل حقلٍ موجودٍ فعلاً (`??` لا `||`: صفرٌ صريح قيمةٌ لا غياب).
 * @param {object|null|undefined} data بيانات المستند
 * @param {Array<string>} order ترتيب الحقول
 * @return {number}
 */
function _first(data, order) {
  if (!data) return 0;
  for (const f of order) {
    if (data[f] !== undefined && data[f] !== null) return Number(data[f]) || 0;
  }
  return 0;
}

/**
 * **(أ) كم كان يجب أن يُدفَع؟** — لفحص التلاعب قبل التأكيد.
 *
 * [amountField] يسمح للمُنادي بتسمية الحقل الأساسي لمجموعته (طلبات=amount،
 * متجر=total_amount) كما يفعل `moyasarWebhook`؛ ويُدرَج **بعد** الحقول
 * المعتمدة لا قبلها.
 * @param {object|null|undefined} data بيانات مستند الطلب
 * @param {string} [amountField] الحقل الأساسي لمجموعة المُنادي
 * @return {number} بالريال
 */
function expectedAmount(data, amountField) {
  const order = amountField && !FIELD_ORDER.includes(amountField) ?
    [...FIELD_ORDER, amountField] : FIELD_ORDER;
  return _first(data, order);
}

/**
 * **(ب) كم نستردّ؟** — المبلغ الكامل المستحقّ للعميل.
 * @param {object|null|undefined} data بيانات مستند الطلب
 * @return {number} بالريال (قد يكون 0 إن غابت الحقول)
 */
function refundAmount(data) {
  return _first(data, FIELD_ORDER);
}

/**
 * تحويل الريال إلى هللات كما تنتظرها البوابات — تقريبٌ لا قطع.
 * @param {number} sar
 * @return {number}
 */
function toHalalas(sar) {
  return Math.round(Number(sar) * 100);
}

module.exports = {FIELD_ORDER, expectedAmount, refundAmount, toHalalas};
