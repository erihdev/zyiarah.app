import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword } from 'firebase/auth';
import { getFirestore, collection, getDocs, deleteDoc, doc } from 'firebase/firestore';

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

const clearCollection = async (collectionName) => {
    const collRef = collection(db, collectionName);
    const snapshot = await getDocs(collRef);
    console.log(`Deleting ${snapshot.size} docs from ${collectionName}...`);
    for (const docSnap of snapshot.docs) {
        await deleteDoc(doc(db, collectionName, docSnap.id));
    }
};

const run = async () => {
    try {
        await signInWithEmailAndPassword(auth, 'admin@zyiarah.com', '123456');
        console.log("Cleaning up notification records...");
        await clearCollection('notifications');
        await clearCollection('notification_triggers');
        await clearCollection('notifications_log');
        console.log("✅ Cleanup complete!");
        process.exit(0);
    } catch(e) {
        console.error(e);
        process.exit(1);
    }
};

run();
