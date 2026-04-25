import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword } from 'firebase/auth';
import { getFirestore, collection, addDoc, serverTimestamp } from 'firebase/firestore';

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

const run = async () => {
    try {
        console.log("Logging into Firebase...");
        await signInWithEmailAndPassword(auth, 'admin@zyiarah.com', '123456');
        
        console.log("Triggering Push Notification to all users...");
        const notificationsRef = collection(db, 'notifications_log');
        
        await addDoc(notificationsRef, {
            title: "تجربة الإشعارات - تطبيق زيارة 🚀",
            body: "مرحباً بك! الإشعارات الآن تعمل بنجاح وبسرعة البرق.",
            target: "all",
            created_at: serverTimestamp()
        });

        console.log("✅ Successfully sent the trigger to Firestore. Check your phone!");
        process.exit(0);
    } catch(e) {
        console.error("Failed to send push:", e);
        process.exit(1);
    }
};

run();
