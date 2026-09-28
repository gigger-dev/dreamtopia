# Verification

Verified locally on 24 September 2026 with Node.js 22.19, PostgreSQL 16, and Flutter 3.47.5 / Dart 3.13.4.

| Check | Result |
|---|---|
| NestJS TypeScript type check | Passed |
| NestJS production build | Passed |
| Domain and authorization tests | 7 passed |
| PostgreSQL service integration tests | 6 passed |
| Flutter static analysis | No issues |
| Flutter widget tests | 6 passed |
| Flutter JavaScript web build | Passed |

Integration tests exercised concurrent seat reservation, cancellation credit restoration, instructor acceptance, blocked slots, studio overlap, payment-proof ownership/reuse, discounts, attendance, teaching counts, and preferred timeslot responses. The disposable database was removed afterward.

Widget tests covered sign-in validation, payment-proof requirements, calendar rendering at 390 and 1440 pixels, and admin/instructor screens.

The Flutter build was compiled with a placeholder API URL; configure `API_URL` for your running backend and rebuild before publishing. WebAssembly is not enabled because the selected secure-storage web plugin uses browser APIs supported by the JavaScript build. The build also reports a Cupertino font-family warning; this app's controls use Material icons.

Android and iOS platform scaffolds are included, but native binaries, signing, actual mobile devices, live banking reconciliation, and external notification providers were not tested. Tests cover the API service layer and authorization guard; a full device-to-live-server acceptance test remains part of deployment setup.
