import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword } from 'firebase/auth';
import { getFirestore, collection, getDocs, deleteDoc, doc, setDoc } from 'firebase/firestore';

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
    console.log(`Fetching all documents in ${collectionName}...`);
    const collRef = collection(db, collectionName);
    const snapshot = await getDocs(collRef);
    console.log(`Found ${snapshot.size} documents in ${collectionName} to delete.`);
    
    for (const docSnap of snapshot.docs) {
        await deleteDoc(doc(db, collectionName, docSnap.id));
    }
    console.log(`✅ Cleared ${collectionName}`);
};

const run = async () => {
    try {
        console.log("Logging into Firebase as Admin...");
        await signInWithEmailAndPassword(auth, 'admin@zyiarah.com', '123456');
        
        await clearCollection('maintenance_requests');
        await clearCollection('contracts');

        console.log("✅ Successfully deleted all maintenance and contracts!");
        process.exit(0);
    } catch(e) {
        console.error("Failed to delete collections:", e);
        process.exit(1);
    }
};

run();
