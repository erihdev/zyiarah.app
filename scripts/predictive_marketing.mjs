/**
 * NAES Strategic Growth Orchestrator (SGO)
 * Predictive Marketing Agent (V1)
 * Analyzes order density and auto-triggers hyper-local marketing campaigns.
 */
import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword } from 'firebase/auth';
import { getFirestore, collection, getDocs, query, where, addDoc, serverTimestamp } from 'firebase/firestore';

// CONFIGURATION
const firebaseConfig = {
    apiKey: process.env.FIREBASE_API_KEY || "AIzaSyCwyG5_yH1rKd-CBQGwQylw2n8jrPbn17o",
    authDomain: process.env.FIREBASE_AUTH_DOMAIN || "zyiarah-app.firebaseapp.com",
    projectId: process.env.FIREBASE_PROJECT_ID || "zyiarah-app",
    storageBucket: process.env.FIREBASE_STORAGE_BUCKET || "zyiarah-app.firebasestorage.app",
    messagingSenderId: process.env.FIREBASE_MESSAGING_SENDER_ID || "275681992607",
    appId: process.env.FIREBASE_APP_ID || "1:275681992607:web:6dc4a0042fab5b69b127aa"
};

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);
const auth = getAuth(app);

async function authenticateAdmin() {
    const adminEmail = process.env.ADMIN_EMAIL || 'admin@zyiarah.com';
    const adminPassword = process.env.ADMIN_PASSWORD || '123456';
    try {
        console.log(`🔐 Authenticating as ${adminEmail}...`);
        await signInWithEmailAndPassword(auth, adminEmail, adminPassword);
        console.log('✅ Authentication successful!');
    } catch (error) {
        console.error('❌ Authentication failed:', error.message);
        throw error;
    }
}

// THRESHOLDS
const OCCUPANCY_THRESHOLD = 5; // Minimum orders per week to be "Healthy"

/**
 * Identifies underperforming zones based on current order history.
 */
async function analyzeZonePerformance() {
    console.log("🕵️ Analyzing Zyiarah Zone Performance...");
    
    const oneWeekAgo = new Date();
    oneWeekAgo.setDate(oneWeekAgo.getDate() - 7);

    const ordersQuery = query(
        collection(db, 'orders'),
        where('created_at', '>=', oneWeekAgo)
    );

    const snapshot = await getDocs(ordersQuery);
    const zoneUsage = {};

    snapshot.forEach(doc => {
        const zone = doc.data().zone_name || 'Generic';
        zoneUsage[zone] = (zoneUsage[zone] || 0) + 1;
    });

    console.log("📈 Order Density (Last 7 Days):", zoneUsage);
    return zoneUsage;
}

/**
 * Triggers a hyper-local marketing campaign via n8n/Firebase.
 */
async function triggerNeuralMarketing() {
    console.log("🚀 Starting Predictive CRM Cycle...");

    try {
        await authenticateAdmin();
        const usage = await analyzeZonePerformance();
        
        // Potential zones to monitor (In production, these come from 'zones' collection)
        const targetZones = ['Al-Olaya', 'Al-Malqa', 'Al-Yasmeen', 'Al-Rawdah'];

        for (const zone of targetZones) {
            const count = usage[zone] || 0;
            
            if (count < OCCUPANCY_THRESHOLD) {
                console.log(`⚠️ Alert: Zone [${zone}] has low occupancy (${count} orders/week).`);
                console.log(`📡 Triggering Predictive Flash Sale Campaign for [${zone}]...`);

                // 1. Create a dynamic promo code for this zone
                const promoCode = `SAVE${zone.toUpperCase().substring(0, 3)}${Math.floor(Math.random() * 100)}`;
                
                // 2. Log campaign to Firestore (n8n or Cloud Functions can listen to this to send Pushes)
                await addDoc(collection(db, 'marketing_campaigns'), {
                    'zone': zone,
                    'promo_code': promoCode,
                    'discount_percent': 20,
                    'reason': 'low_occupancy_prediction',
                    'triggered_at': serverTimestamp(),
                    'status': 'scheduled',
                    'target_count': count
                });
                
                console.log(`✅ Campaign deployed: ${promoCode} for users in ${zone}.`);
            } else {
                console.log(`✨ Zone [${zone}] is performing healthy.`);
            }
        }

    } catch (e) {
        console.error("❌ Strategic error in Predictive Marketing Agent:", e);
    }
}

triggerNeuralMarketing().then(() => process.exit(0));
