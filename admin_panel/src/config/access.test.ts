import { describe, it, expect } from 'vitest';
import { PAGE_ROLES, canAccess } from './access.ts';

// بوّابة أدوار لوحة الإدارة. تعليق access.ts ينصّ على أنها «مُبقاة متزامنة مع
// firestore.rules» — وهذا نوع التزامن الذي ينحرف بصمت: تعديل في القواعد لا
// يكسر شيئاً هنا، فتبقى اللوحة تعرض صفحةً يرفض الخادم كل أفعالها، أو تُخفي
// صفحةً يملكها الدور فعلاً. الفحوص أدناه تثبّت الثوابت التي لا يجوز انحرافها.

const KNOWN_ROLES = [
  'super_admin',
  'admin',
  'orders_manager',
  'accountant_admin',
  'marketing_admin',
] as const;

describe('canAccess — الأساسيات', () => {
  it('بلا دور ⇒ ممنوع (لا يسقط مفتوحاً)', () => {
    expect(canAccess(null, '/orders')).toBe(false);
    expect(canAccess(undefined, '/orders')).toBe(false);
    expect(canAccess('', '/orders')).toBe(false);
  });

  it('مسار غير معروف ⇒ ممنوع لغير السوبر (لا يسقط مفتوحاً)', () => {
    expect(canAccess('orders_manager', '/no-such-page')).toBe(false);
    expect(canAccess('marketing_admin', '/__proto__')).toBe(false);
  });

  it('super_admin وadmin يصلان كل صفحة مُعرَّفة', () => {
    for (const path of Object.keys(PAGE_ROLES)) {
      expect(canAccess('super_admin', path)).toBe(true);
      expect(canAccess('admin', path)).toBe(true);
    }
  });

  it('دور مجهول لا يصل شيئاً', () => {
    for (const path of Object.keys(PAGE_ROLES)) {
      expect(canAccess('driver', path)).toBe(false);
      expect(canAccess('client', path)).toBe(false);
    }
  });
});

describe('PAGE_ROLES — ثوابت الخريطة', () => {
  it('كل صفحة تمنح السوبر والأدمن صراحةً', () => {
    for (const [path, roles] of Object.entries(PAGE_ROLES)) {
      expect(roles, `${path} لا يمنح super_admin`).toContain('super_admin');
      expect(roles, `${path} لا يمنح admin`).toContain('admin');
    }
  });

  it('لا اسم دور خارج القائمة المعروفة — حارس ضد خطأ الطباعة', () => {
    // «orders_manger» بحرف ناقص يمرّ صامتاً ويمنع الدور عن صفحته للأبد.
    for (const [path, roles] of Object.entries(PAGE_ROLES)) {
      for (const r of roles) {
        expect(KNOWN_ROLES, `${path} يذكر دوراً مجهولاً: ${r}`).toContain(r);
      }
    }
  });

  it('لا تكرار داخل قائمة أدوار الصفحة الواحدة', () => {
    for (const [path, roles] of Object.entries(PAGE_ROLES)) {
      expect(new Set(roles).size, `${path} فيه دور مكرّر`).toBe(roles.length);
    }
  });

  it('الصفحة الجذر مفتوحة لكل الأدوار المعروفة', () => {
    for (const r of KNOWN_ROLES) expect(canAccess(r, '/')).toBe(true);
  });
});

describe('فصل الصلاحيات — يطابق ما تفرضه firestore.rules', () => {
  // هذه الأزواج مأخوذة من فحوص القواعد في functions/test/rules.roles.test.js:
  // ما يرفضه الخادم يجب ألّا تعرضه اللوحة، وما يسمح به يجب ألّا تُخفيه.
  it('مدير العمليات: طلبات نعم، رواتب لا، تسويق لا', () => {
    expect(canAccess('orders_manager', '/orders')).toBe(true);
    expect(canAccess('orders_manager', '/payroll')).toBe(false);
    expect(canAccess('orders_manager', '/marketing')).toBe(false);
    expect(canAccess('orders_manager', '/store-products')).toBe(false);
  });

  it('المحاسب: رواتب ومحاسبون نعم، طلبات لا', () => {
    expect(canAccess('accountant_admin', '/payroll')).toBe(true);
    expect(canAccess('accountant_admin', '/accountants')).toBe(true);
    expect(canAccess('accountant_admin', '/orders')).toBe(false);
    expect(canAccess('accountant_admin', '/drivers')).toBe(false);
  });

  it('التسويق: منتجات وتسويق نعم، طلبات ورواتب لا', () => {
    expect(canAccess('marketing_admin', '/store-products')).toBe(true);
    expect(canAccess('marketing_admin', '/marketing')).toBe(true);
    expect(canAccess('marketing_admin', '/orders')).toBe(false);
    expect(canAccess('marketing_admin', '/payroll')).toBe(false);
  });

  it('إدارة المدراء وحذف الحسابات للسوبر والأدمن وحدهما', () => {
    for (const p of ['/admins', '/account-deletion']) {
      expect(canAccess('orders_manager', p)).toBe(false);
      expect(canAccess('accountant_admin', p)).toBe(false);
      expect(canAccess('marketing_admin', p)).toBe(false);
    }
  });
});
