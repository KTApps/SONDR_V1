# Firestore rules tests

Rules are not filters: a query succeeds only if the rules can prove every
matching document is readable. Get that wrong and a reader's whole feed
fails with `permission-denied` instead of quietly omitting rows — which is
the failure these tests exist to catch, because no unit test of the app can
see it.

Run them against the emulator:

```bash
cd test/rules && npm install
npx -y firebase-tools@13.35.1 emulators:exec --only firestore --project demo-sondr \
  "node --test rules.test.mjs"
```

**firebase-tools 13.x on purpose.** The installed CLI (15.x) needs Java 21
and this machine has Java 11, so the emulator will not start under it. The
installed CLI is still what deploys. If a JDK 21 arrives, drop the pin.
