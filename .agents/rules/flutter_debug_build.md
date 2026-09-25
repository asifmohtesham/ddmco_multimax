# Flutter Debug Build for Sideloading

Whenever building and sideloading a Flutter APK onto a device for testing alongside an existing Play Store installation, you MUST use the debug build command:

`flutter build apk --debug`

**Rationale**:
By default, `flutter build apk` builds a release APK. A release APK might clash with or overwrite the Play Store version of the app if they share the same application ID or signing configuration. Building a debug APK ensures a debug signing key is used, which safely avoids replacing the production app.
