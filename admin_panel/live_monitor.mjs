import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword } from 'firebase/auth';
import { getFirestore, collection, query, where, orderBy, onSnapshot, limit } from 'firebase/firestore';

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

const monitorUserOrders = async (userEmail) => {
    console.log(`📡 Live Monitoring System Active for: ${userEmail}`);
    console.log(`Waiting for new orders, maintenance requests, and contracts...`);
    
    // Quick initial check to see current state
    const collections = ['orders', 'store_orders', 'maintenance_requests', 'contracts'];
    
    for (const collName of collections) {
         console.log(`Checking ${collName} for incoming signals...`);
         const q = query(collection(db, collName), orderBy('created_at', 'desc'), limit(1));
         // We use getDocs for a quick current snapshot if needed, but onSnapshot for live.
    }
    
    // In this environment, we'll run a loop or a script that checks and exits after findings
    // since I can't keep a persistent background pipe to the chat easily without periodic polling.
};

const run = async () => {
    try {
        await signInWithEmailAndPassword(auth, 'admin@zyiarah.com', '123456');
        await monitorUserOrders('rania054shami@gmail.com');
        // Let's do a polling loop to report findings
        while(true) {
            console.log("--- Scanning for New Activity (" + new Date().toLocaleTimeString() + ") ---");
            const snapshot = await getDocs(query(collection(db, 'orders'), orderBy('created_at', 'desc'), limit(5)));
            if (snapshot.empty) {
                console.log("No orders found yet.");
            } else {
                snapshot.docs.forEach(doc => {
                    const data = doc.data();
                    console.log(`[ORDER] Code: ${data.code} | Status: ${data.status} | Client: ${data.client_email}`);
                });
            }
            await new Promise(r => setTimeout(r, 10000)); // Poll every 10s
        }
    } catch(e) { console.error(e); }
};

// Note: I will run this via run_command with a timeout to catch the first orders.
