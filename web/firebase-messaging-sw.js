importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "QUl6YVN5QnRNekxqb19qRmlMbVBVeXRDQzJKMGJ4aENaZ1VpSnAw",
  authDomain: "abasto-sv.firebaseapp.com",
  projectId: "abasto-sv",
  storageBucket: "abasto-sv.firebasestorage.app",
  messagingSenderId: "467568058533",
  appId: "1:467568058533:web:a36598ccf13196df232d4c"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || payload.data?.title || "Abasto";
  const body = payload.notification?.body || payload.data?.body || "Tienes una nueva actualización";

  if (self.registration && self.registration.setAppBadge) {
    self.registration.setAppBadge(1).catch(() => {});
  }

  return self.registration.showNotification(title, {
    body: body,
    icon: "/icons/Icon-192.png",
    badge: "/icons/Icon-192.png",
    tag: payload.data?.order_id ? `order-${payload.data.order_id}` : "abasto-notification",
    renotify: true,
    data: payload.data || {}
  });
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  if (self.registration && self.registration.clearAppBadge) {
    self.registration.clearAppBadge().catch(() => {});
  }
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ("focus" in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow("/");
    })
  );
});