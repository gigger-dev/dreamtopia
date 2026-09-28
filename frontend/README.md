# Dreamtopia Flutter app

See [the project setup guide](../README.md) for API setup and all three role workflows.

```sh
flutter pub get
flutter run -d chrome --web-port 8080 --dart-define=API_URL=http://localhost:3000/api
```

Web, Android, and iOS scaffolds are included. Mobile release builds need your signing configuration and an HTTPS backend. Android builds require a compatible JDK (17–25 with the generated Gradle version). Only debug Android builds allow cleartext development traffic. iOS real-device development should use HTTPS; the release configuration does not enable arbitrary insecure transport.
