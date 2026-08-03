"use client";

/**
 * Firebase Web Push (FCM) — Case 2 of the "New Order" alert: a push that
 * reaches the store even with the tab fully closed, as long as the browser
 * is running. Case 1 (tab open) is the WebSocket in
 * lib/realtime/use-store-orders-socket.ts and needs none of this.
 *
 * Config comes entirely from NEXT_PUBLIC_FIREBASE_* env vars — see
 * .env.local.example. Every value here is a client-embeddable identifier
 * (same category as a Stripe publishable key), never a secret.
 */
import { type FirebaseApp, initializeApp } from "firebase/app";
import { type Messaging, getMessaging, getToken } from "firebase/messaging";

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

const VAPID_KEY = process.env.NEXT_PUBLIC_FIREBASE_VAPID_KEY;

/** True once every required env var is actually filled in (not just present-but-empty). */
export function isPushConfigured(): boolean {
  return Boolean(
    firebaseConfig.apiKey &&
      firebaseConfig.projectId &&
      firebaseConfig.messagingSenderId &&
      firebaseConfig.appId &&
      VAPID_KEY,
  );
}

let app: FirebaseApp | null = null;
let messaging: Messaging | null = null;

function getMessagingInstance(): Messaging | null {
  if (typeof window === "undefined" || !isPushConfigured()) return null;
  if (!app) app = initializeApp(firebaseConfig);
  if (!messaging) messaging = getMessaging(app);
  return messaging;
}

/**
 * Registers this browser for push and returns the FCM token to save server-
 * side, or null if push isn't configured / permission wasn't granted / the
 * browser doesn't support it. Reuses the SAME service worker registration
 * `sw.js` already installed for offline support (see components/pwa/
 * register-sw.tsx) — a second, separate `firebase-messaging-sw.js` would
 * fight it for the page's root scope.
 */
export async function requestFcmToken(): Promise<string | null> {
  if (typeof window === "undefined" || !("serviceWorker" in navigator)) return null;
  const m = getMessagingInstance();
  if (!m) return null;
  try {
    const registration = await navigator.serviceWorker.ready;
    const token = await getToken(m, {
      vapidKey: VAPID_KEY,
      serviceWorkerRegistration: registration,
    });
    return token || null;
  } catch {
    return null;
  }
}
