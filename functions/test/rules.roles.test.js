// Emulator rules test: verifies the deployed role-model fix — staff are separated
// by their real sub-role (staff_role) instead of every staff = super_admin.
// Run: firestore emulator on :8080, then `node test/rules.roles.test.js`.
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {setDoc, doc, updateDoc, getDoc} = require("firebase/firestore");

(async () => {
  const testEnv = await initializeTestEnvironment({
    projectId: "demo-zyiarah-roles",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  // Seed users + a couple of target docs with rules disabled.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    // staff created the buggy way: role='admin', real role in staff_role
    await setDoc(doc(db, "users/ordersMgr"), {role: "admin", staff_role: "orders_manager"});
    await setDoc(doc(db, "users/marketer"), {role: "admin", staff_role: "marketing_admin"});
    await setDoc(doc(db, "users/accountant"), {role: "admin", staff_role: "accountant_admin"});
    // bootstrapped super admin: role='admin', NO staff_role
    await setDoc(doc(db, "users/superA"), {role: "admin"});
    // a plain client
    await setDoc(doc(db, "users/client1"), {role: "client"});
    // عميلٌ له كودُ إحالةٍ مكتوبٌ سلفاً، وآخرُ بلا كود (أوّلُ توليد).
    await setDoc(doc(db, "users/refOwner"), {role: "client", referral_code: "AAAA1111"});
    await setDoc(doc(db, "users/refNew"), {role: "client"});
    // target docs
    await setDoc(doc(db, "system_configs/hourly_settings"), {max_orders_per_day: 10});
    await setDoc(doc(db, "products/p1"), {name: "x", price: 10});
    await setDoc(doc(db, "orders/o1"), {client_id: "someone", status: "pending", amount: 100});
    await setDoc(doc(db, "payroll_records/r1"), {amount: 100});
    await setDoc(doc(db, "store_orders/s1"), {client_id: "someone", is_paid: true, amount: 50});
  });

  const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();
  // مع ادّعاءِ بريدٍ في الرمز — قواعدُ `users` تُقارِنُ `email` بـ
  // `request.auth.token.email`.
  const asUserEmail = (uid, email) =>
    testEnv.authenticatedContext(uid, {email}).firestore();
  let pass = 0; let fail = 0;
  const check = async (name, promise, shouldSucceed) => {
    try {
      await (shouldSucceed ? assertSucceeds(promise) : assertFails(promise));
      console.log(`  ✓ ${name}`); pass++;
    } catch (e) {
      console.error(`  ✗ ${name} — ${e.message}`); fail++;
    }
  };

  console.log("Role separation via staff_role (deployed rules):");

  // orders_manager: manages orders, NOT super (system_configs), NOT marketing (products)
  await check("orders_mgr CAN update orders",
      updateDoc(doc(asUser("ordersMgr"), "orders/o1"), {status: "scheduled"}), true);
  await check("orders_mgr CANNOT write system_configs (super only)",
      updateDoc(doc(asUser("ordersMgr"), "system_configs/hourly_settings"), {max_orders_per_day: 99}), false);
  await check("orders_mgr CANNOT write products (marketing only)",
      updateDoc(doc(asUser("ordersMgr"), "products/p1"), {price: 5}), false);

  // marketing_admin: manages products, NOT orders
  await check("marketing CAN write products",
      updateDoc(doc(asUser("marketer"), "products/p1"), {price: 7}), true);
  await check("marketing CANNOT update orders (orders_mgr only)",
      updateDoc(doc(asUser("marketer"), "orders/o1"), {status: "completed"}), false);

  // accountant_admin: reads payroll, NOT orders, NOT products
  await check("accountant CAN read payroll",
      getDoc(doc(asUser("accountant"), "payroll_records/r1")), true);
  await check("accountant CANNOT update orders",
      updateDoc(doc(asUser("accountant"), "orders/o1"), {status: "completed"}), false);
  // سجل الفواتير الإلكترونية يجمع فواتير المتجر أيضاً — قراءة فقط.
  await check("accountant CAN read store_orders (invoice log)",
      getDoc(doc(asUser("accountant"), "store_orders/s1")), true);
  await check("accountant CANNOT update store_orders",
      updateDoc(doc(asUser("accountant"), "store_orders/s1"), {status: "processing"}), false);
  await check("marketing CANNOT read store_orders",
      getDoc(doc(asUser("marketer"), "store_orders/s1")), false);

  // bootstrapped super admin (no staff_role): can do everything
  await check("super CAN write system_configs",
      updateDoc(doc(asUser("superA"), "system_configs/hourly_settings"), {max_orders_per_day: 20}), true);
  await check("super CAN write products",
      updateDoc(doc(asUser("superA"), "products/p1"), {price: 9}), true);

  // plain client: none of the above
  await check("client CANNOT write products",
      updateDoc(doc(asUser("client1"), "products/p1"), {price: 1}), false);
  await check("client CANNOT write system_configs",
      updateDoc(doc(asUser("client1"), "system_configs/hourly_settings"), {max_orders_per_day: 1}), false);

  // ── الإحالة: الكودُ يُكتب مرّةً، والرابطُ خادميٌّ بحت ──────────────────
  //
  // `applyReferralCode` يحلّ المُحيلَ بـ
  // `where('referral_code','==',code).limit(1)`. فمن يستطيع **تغيير** كوده
  // يضبطه على كود غيره فتُرجِع الاستعلامةُ أحدَ المستندَين، وقد تُنسب إحالةٌ
  // ومكافأتُها (50 ر.س) إلى غير صاحبها. والتوليدُ الأوّل يجب أن يبقى ممكناً:
  // `getOrCreateReferralCode` يكتبه من العميل.
  await check("client CAN write referral_code when absent (first generation)",
      updateDoc(doc(asUser("refNew"), "users/refNew"), {referral_code: "BBBB2222"}), true);

  // ── بريدُ السجلِّ يَجبُ أن يُطابقَ بريدَ المصادقة ──────────────────────
  //
  // `isAllowedEmailRecipient` يُجيزُ وجهةَ بريدٍ بالاستعلامِ
  // `users.where('email','==',…)`، وحارسُ المُرسِلِ كان يُقارِنُ الحقلَ
  // نفسَه بـ`recipientEmail` ليُجيزَ «عميلٌ يُرسلُ لبريدِه هو». فمن يَكتبُ
  // بريدَه `victim@x.com` يَجتازُ الحارسَين، ويُرسِلُ الخادمُ بريداً من
  // `no-reply@zyiarah.com` بعنوانٍ ونصٍّ من اختيارِه إلى أيِّ عنوان:
  // مُرحِّلٌ مفتوحٌ بنطاقِ الشركة.
  await check("email: client writes a foreign email on own doc -> DENIED",
      updateDoc(doc(asUserEmail("client1", "me@zyiarah.com"), "users/client1"),
          {email: "victim@example.com"}), false);
  await check("email: client writes her own auth email -> ALLOWED",
      updateDoc(doc(asUserEmail("client1", "me@zyiarah.com"), "users/client1"),
          {email: "me@zyiarah.com"}), true);
  // والمسارُ الشرعيُّ كما يَكتبُه التطبيقُ عند التسجيل (الجوّال مع البريد).
  await check("email: the signup update (phone + auth email) -> ALLOWED",
      updateDoc(doc(asUserEmail("client1", "me@zyiarah.com"), "users/client1"),
          {phone: "0501234567", email: "me@zyiarah.com"}), true);
  // ولا يُكسَرُ تعديلُ حقولٍ أخرى بلا لمسِ البريد.
  await check("email: unrelated profile field, email untouched -> ALLOWED",
      updateDoc(doc(asUser("client1"), "users/client1"), {name: "عميلة"}), true);
  await check("client CANNOT change an existing referral_code",
      updateDoc(doc(asUser("refOwner"), "users/refOwner"), {referral_code: "AAAA1111X"}), false);
  await check("client CANNOT hijack another user's code onto their own doc",
      updateDoc(doc(asUser("refNew"), "users/refNew"), {referral_code: "AAAA1111"}), false);
  await check("client CANNOT self-set referred_by",
      updateDoc(doc(asUser("client1"), "users/client1"), {referred_by: "refOwner"}), false);
  await check("client CANNOT self-set used_referral_code",
      updateDoc(doc(asUser("client1"), "users/client1"), {used_referral_code: "AAAA1111"}), false);
  // ولا يُمنع ما كان مسموحاً: حقولُ الملفّ العاديّة.
  await check("client CAN still edit their own name",
      updateDoc(doc(asUser("client1"), "users/client1"), {name: "سارة"}), true);

  await testEnv.cleanup();
  console.log(`\nRole test: ${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
