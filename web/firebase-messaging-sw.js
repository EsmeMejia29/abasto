importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js');

const firebaseConfig = {
  apiKey: "AIzaSyBtMzLjo_jFiLmPUytCC2J0bxhCZgUiJp0",
  authDomain: "abasto-sv.firebaseapp.com",
  projectId: "abasto-sv",
  storageBucket: "abasto-sv.firebasestorage.app",
  messagingSenderId: "467568058533",
  appId: "1:467568058533:web:a36598ccf13196df232d4c",
  measurementId: "G-NW0GVX6129"
};

firebase.initializeApp(firebaseConfig);

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Notificación en segundo plano:', payload);
  const notificationTitle = payload.notification ? payload.notification.title : 'Abasto';
  const notificationOptions = {
    body: payload.notification ? payload.notification.body : '',
    icon: '/icons/Icon-192.png',
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});