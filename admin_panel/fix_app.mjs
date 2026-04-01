import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword, createUserWithEmailAndPassword } from 'firebase/auth';
import { getFirestore, doc, setDoc, getDocs, collection } from 'firebase/firestore';

const firebaseConfig = {
  apiKey: "AIzaSyCwyG5_yH1rKd-CBQGwQylw2n8jrPbn17o",
  authDomain: "zyiarah-app.firebaseapp.com",
  projectId: "zyiarah-app",
  storageBucket: "zyiarah-app.firebasestorage.app",
  messagingSenderId: "275681992607",
  appId: "1:275681992607:web:6dc4a0042fab5b69b127aa"
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

const fixRoles = async () => {
    const emails = ['admin@zyiarah.com', 'difmashni@gmail.com'];
    for (const email of emails) {
        try {
            console.log(`Checking auth for ${email}...`);
            let uid;
            try {
                const cred = await signInWithEmailAndPassword(auth, email, '123456');
                uid = cred.user.uid;
            } catch (err) {
                console.log(`Could not sign in ${email}, trying to create account...`);
                // If it fails (invalid credential, wrong password, or doesn't exist), just create a new one!
                // Wait, if it exists but wrong password, createUser will fail.
                // It's safer to just forcefully create it if it doesn't exist.
                try {
                   const cred = await createUserWithEmailAndPassword(auth, email, '123456');
                   uid = cred.user.uid;
                } catch(cer) {
                   console.log(`Account ${email} exists but password mismatch. We can't fix it if we don't know the password... unless we use admin SDK. Moving on.`);
                   continue;
                }
            }
            
            // Force exact role string
            await setDoc(doc(db, 'users', uid), {
                email: email,
                role: 'admin',
                name: 'المدير العام',
                is_verified: true
            }, { merge: true });

            await setDoc(doc(db, 'admins', uid), {
                email: email,
                created_at: new Date()
            }, { merge: true });
            
            console.log(`Successfully forced Admin role for ${email} (UID: ${uid})`);
        } catch(e) {
            console.error(`Could not fix role for ${email}:`, e.code || e.message);
        }
    }
};

const seedServices = async () => {
    try {
        const servicesRef = collection(db, 'services');
        const defaultServices = [
            {
                id: 'hourly_cleaning',
                title: 'التنظيف بالساعة',
                subtitle: 'نظافة سريعة وفعّالة لمنزلك..',
                priceText: 'تبدأ من 50 ر.س / ساعة',
                iconName: 'cleaning_services',
                route: '/hourly_details',
                order_index: 0,
                is_active: true,
                base_price: 50
            },
            {
                id: 'monthly_cleaning',
                title: 'التعاقد الشهري',
                subtitle: 'حلول نظافة مستدامة..',
                priceText: 'باقات شهرية تبدأ من 1500 ر.س',
                iconName: 'calendar_month',
                route: '/monthly_details',
                order_index: 1,
                is_active: true,
                base_price: 1500
            },
            {
                id: 'sofa_rug_cleaning',
                title: 'تنظيف الكنب والزل',
                subtitle: 'غسيل عميق بأفضل المواد..',
                priceText: 'تبدأ من 15 ر.س للمتر',
                iconName: 'dry_cleaning',
                route: '/sofa_rug_details',
                order_index: 2,
                is_active: true,
                base_price: 15
            },
            {
                id: 'company_cleaning',
                title: 'تنظيف الشركات والفنادق',
                subtitle: 'حلول نظافة احترافية لقطاع الأعمال..',
                priceText: 'يرجى التواصل معنا لتقديم عرض سعر',
                iconName: 'business',
                route: '/business_details',
                order_index: 3,
                is_active: true,
                base_price: 0
            }
        ];

        for (const s of defaultServices) {
            const { id, ...data } = s;
            await setDoc(doc(servicesRef, id), data, { merge: true });
        }
        console.log("Successfully restored all missing services!");
    } catch(e) {
        console.error("Error seeding services:", e);
    }
};

const run = async () => {
    console.log("Starting master fix script...");
    await fixRoles();
    await seedServices();
    process.exit(0);
};

run();
