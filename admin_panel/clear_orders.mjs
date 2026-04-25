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

const run = async () => {
    try {
        console.log("Logging into Firebase as Admin...");
        await signInWithEmailAndPassword(auth, 'admin@zyiarah.com', '123456');
        
        console.log("Fetching all orders...");
        const ordersRef = collection(db, 'orders');
        const snapshot = await getDocs(ordersRef);
        
        console.log(`Found ${snapshot.size} orders to delete.`);
        
        let batchCount = 0;
        for (const orderDoc of snapshot.docs) {
            await deleteDoc(doc(db, 'orders', orderDoc.id));
            batchCount++;
            if (batchCount % 10 === 0) {
               console.log(`Deleted ${batchCount} orders so far...`);
            }
        }

        console.log("Resetting order counter...");
        const counterRef = doc(db, 'metadata', 'order_counter');
        await setDoc(counterRef, { last_id: 100 });

        console.log("✅ Successfully deleted all orders and reset the counter!");
        process.exit(0);
    } catch(e) {
        console.error("Failed to delete orders:", e);
        process.exit(1);
    }
};

run();
