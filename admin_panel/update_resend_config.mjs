import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword } from 'firebase/auth';
import { getFirestore, doc, setDoc } from 'firebase/firestore';

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

const email = 'admin@zyiarah.com';
const password = '123456'; // From create_admin.mjs

const updateResendConfig = async () => {
  try {
    console.log('Signing in as admin...');
    await signInWithEmailAndPassword(auth, email, password);
    console.log('Signed in successfully.');

    const resendConfig = {
      host: 'smtp.resend.com',
      port: 465,
      user: 'resend',
      pass: 're_iqeWx2vQ_E22Txe3nnjTrqY4zU3aMX5in',
      fromName: 'Zyiarah | زيارة',
      fromEmail: 'admin@zyiarah.com',
      updatedAt: new Date()
    };

    console.log('Updating system_configs/email_settings...');
    await setDoc(doc(db, 'system_configs', 'email_settings'), resendConfig, { merge: true });
    console.log('Resend configuration updated successfully!');
    process.exit(0);
  } catch (error) {
    console.error('Error updating Resend config:', error);
    process.exit(1);
  }
};

updateResendConfig();
