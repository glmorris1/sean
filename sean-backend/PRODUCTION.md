# GhostTrade Auth Backend Production Setup

This backend is the source of truth for GhostTrade email/password accounts, email verification, saved watchlists, and paper trading/backtesting workspace sync.

## Required Production Pieces

1. Deploy the backend behind HTTPS.
   - This repo includes `render.yaml`, which provisions a Render web service named `ghosttrade-auth` and a Postgres database.
   - The expected production API URL is `https://ghosttrade-auth.onrender.com`.
   - The iOS Release build is configured to use that HTTPS URL.

2. Configure Firebase Auth for real email delivery.
   - Set `NODE_ENV=production`.
   - Set `DATABASE_URL`; Render fills this automatically from the managed Postgres database.
   - Create a Firebase project and enable Email/Password sign-in.
   - Enable Google as a Firebase Authentication sign-in provider.
   - Add the iOS app bundle ID `com.glmorris1.GhostTrade` in Firebase.
   - Download `GoogleService-Info.plist` and add it to the Xcode target.
   - In Xcode, set the URL scheme to the plist's `REVERSED_CLIENT_ID` value so Google can return to the app after browser sign-in.
   - If not using `GoogleService-Info.plist`, set `FIREBASE_WEB_API_KEY`, `GOOGLE_CLIENT_ID`, and `GOOGLE_REVERSED_CLIENT_ID` build settings manually.
   - Set `FIREBASE_PROJECT_ID` in the backend environment so the backend can verify Firebase ID tokens for saved watchlists and paper trading state.
   - SMTP is optional when Firebase Auth is used. It remains available only for the custom backend auth path.

3. Set a secret.
   - Set `APP_SECRET` to a long random value.

4. Disable development codes.
   - Do not set `ALLOW_DEVELOPMENT_CODES=true` in production.
   - In production, the server refuses to start unless Firebase or SMTP email delivery is configured.

5. Configure allowed web origins if the desktop app uses this API.
   - Example: `CORS_ORIGINS=https://glmorris1.github.io`

6. Point iOS Release builds at the deployed API.
   - Release currently points at `https://ghosttrade-auth.onrender.com`.
   - If the Render service name changes, update `AuthBackendDefaults.bundledBackendBaseURL` in the iOS app and the Release `SEAN_API_BASE_URL` build setting.
   - Debug can keep using the LAN backend for testing on local devices.

## Example Production Environment

```env
NODE_ENV=production
PORT=8787
APP_SECRET=replace-with-a-long-random-production-secret
DATABASE_URL=postgres://provided-by-render
CORS_ORIGINS=https://glmorris1.github.io
FIREBASE_PROJECT_ID=ghosttrade-app

# Optional only if not using Firebase Auth emails:
# SMTP_HOST=smtp.resend.com
# SMTP_PORT=465
# SMTP_SECURE=true
# SMTP_USER=resend
# SMTP_PASS=replace-with-provider-secret
# SMTP_FROM=GhostTrade <verify@your-domain.com>
```

## App Store Notes

- The app must not ship with a LAN IP API URL.
- The app must not rely on development verification codes.
- Release builds only allow HTTPS for the auth/sync backend.
- Face ID is local device unlock only; the verified email account remains the durable login for cross-device sync.
- Production uses Postgres. The JSON file store is development-only.
- Firebase sends verification emails; the iOS app never contains SMTP credentials.
- Debug no longer defaults to a LAN backend, so iOS should not ask for local-network permission during login.
