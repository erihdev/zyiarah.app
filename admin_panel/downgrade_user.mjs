import { initializeApp } from 'firebase/app';
import { getFirestore, doc, updateDoc, deleteDoc } from 'firebase/firestore';

const firebaseConfig = {
  apiKey: "AIzaSyCwyG5_yH1rKd-CBQGwQylw2n8jrPbn17o",
  authDomain: "zyiarah-app.firebaseapp.com",
  projectId: "zyiarah-app",
  storageBucket: "zyiarah-app.firebasestorage.app",
  messagingSenderId: "275681992607",
  appId: "1:275681992607:web:6dc4a0042fab5b69b127aa"
};

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);

const userUid = "wGkJlhcBK9Wg6Kn815yi0hbwRPi2"; // UID for difmashni@gmail.com

const downgradeUser = async () => {
    try {
        console.log(`Starting downgrade for UID: ${userUid} (difmashni@gmail.com)...`);
        
        // 1. Update role in users collection
        await updateDoc(doc(db, 'users', userUid), {
            role: 'client',
            staff_role: null, // Remove any specific admin roles
            updated_at: new Date()
        });
        console.log("✅ Updated role to 'client' in users collection.");

        // 2. Remove from admins collection
        await deleteDoc(doc(db, 'admins', userUid));
        console.log("✅ Removed from admins collection.");

        console.log("\n🚀 User successfully downgraded to Regular Client.");
        process.exit(0);
    } catch (e) {
        console.error("❌ Failed to downgrade user:", e.message);
        process.exit(1);
    }
};

downgradeUser();
