importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

self.firebaseConfig = {
  apiKey: 'AIzaSyBSgfa6M7eLlL9YpcWhM_ZHUMrqulHHPmg',
  authDomain: 'speedfeast-marchent.firebaseapp.com',
  projectId: 'speedfeast-marchent',
  storageBucket: 'speedfeast-marchent.firebasestorage.app',
  messagingSenderId: '46671696841',
  appId: '1:46671696841:web:328ce6d0ec425a6bba0e18',
  measurementId: 'G-QYSQ3SMP0W',
};

let messaging = null;

function hasFirebaseConfig(firebaseConfig) {
  return firebaseConfig &&
    firebaseConfig.apiKey &&
    firebaseConfig.appId &&
    firebaseConfig.messagingSenderId &&
    firebaseConfig.projectId;
}

if (hasFirebaseConfig(self.firebaseConfig)) {
  firebase.initializeApp(self.firebaseConfig);

  messaging = firebase.messaging();
  messaging.onBackgroundMessage((payload) => {
    const title = payload.notification?.title || 'SpeedFeast Merchant';
    const options = {
      body: payload.notification?.body || 'You have a new notification.',
      icon: '/icons/Icon-192.png',
      data: payload.data || {},
    };

    self.registration.showNotification(title, options);
  });
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const notificationData = event.notification.data || {};
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          client.postMessage({
            type: 'merchant_notification_click',
            data: notificationData,
          });
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow('/');
      return null;
    })
  );
});
