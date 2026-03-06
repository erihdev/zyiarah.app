const express = require('express');
const cors = require('cors');
const admin = require('firebase-admin');
const dotenv = require('dotenv');

dotenv.config();

// We need a service account key to initialize the Firebase Admin SDK
// You must download it from Firebase Console -> Project Settings -> Service Accounts -> Generate New Private Key
// and save it as "serviceAccountKey.json" in this folder.
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const app = express();
app.use(cors());
app.use(express.json());

// Endpoint to send push notifications
app.post('/api/send-notification', async (req, res) => {
    try {
        const { title, body, target } = req.body;

        if (!title || !body) {
            return res.status(400).json({ success: false, error: 'Missing title or body' });
        }

        const payload = {
            notification: {
                title: title,
                body: body,
            },
            data: {
                click_action: 'FLUTTER_NOTIFICATION_CLICK'
            }
        };

        console.log(`Sending notification to target: ${target}`);

        if (target === 'all') {
            await admin.messaging().send({ ...payload, topic: 'all_users' });
            await admin.messaging().send({ ...payload, topic: 'clients' });
            await admin.messaging().send({ ...payload, topic: 'drivers' });
        } else if (target === 'clients') {
            await admin.messaging().send({ ...payload, topic: 'clients' });
        } else if (target === 'drivers') {
            await admin.messaging().send({ ...payload, topic: 'drivers' });
        }

        res.status(200).json({ success: true, message: 'Notification sent successfully!' });
    } catch (error) {
        console.error('Error sending push notification:', error);
        res.status(500).json({ success: false, error: error.message });
    }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Zyiarah Notification Backend running on port ${PORT}`);
});
