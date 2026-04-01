import { initializeApp } from 'firebase/app';
import { getAuth, createUserWithEmailAndPassword, signInWithEmailAndPassword } from 'firebase/auth';
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
const password = '123456';

const setupAdmin = async () => {
  let user;
  try {
    const cred = await createUserWithEmailAndPassword(auth, email, password);
    user = cred.user;
    console.log('Account created for:', email);
  } catch (error) {
    if (error.code === 'auth/email-already-in-use') {
      console.log('Account already exists, signing in...');
      const cred = await signInWithEmailAndPassword(auth, email, password);
      user = cred.user;
    } else {
      console.error('Error creating account:', error);
      process.exit(1);
    }
  }

  try {
    await setDoc(doc(db, 'users', user.uid), {
      email: email,
      role: 'admin',
      name: 'System Admin',
      phone: ''
    }, { merge: true });
    
    // Some logic also uses admins collection
    await setDoc(doc(db, 'admins', user.uid), {
      email: email,
      created_at: new Date()
    }, { merge: true });

    console.log('Successfully assigned admin role to:', email);
    process.exit(0);
  } catch (err) {
    console.error('Error updating firestore:', err);
    process.exit(1);
  }
};

setupAdmin();
