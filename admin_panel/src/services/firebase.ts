import { initializeApp } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
import { getAuth } from 'firebase/auth';
import { getFunctions } from 'firebase/functions';
import { getStorage } from 'firebase/storage';

// TODO: Replace with your actual Firebase project configuration
// You can find this in your Firebase Console -> Project Settings -> General -> Web Apps
const firebaseConfig = {
    apiKey: "AIzaSyCwyG5_yH1rKd-CBQGwQylw2n8jrPbn17o",
    authDomain: "zyiarah-app.firebaseapp.com",
    projectId: "zyiarah-app",
    storageBucket: "zyiarah-app.firebasestorage.app",
    messagingSenderId: "275681992607",
    appId: "1:275681992607:web:6dc4a0042fab5b69b127aa",
    measurementId: "G-K82D1GDJNF"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);

// Initialize Firebase services
export const db = getFirestore(app);
export const auth = getAuth(app);
export const functions = getFunctions(app);
export const storage = getStorage(app);

export default app;
