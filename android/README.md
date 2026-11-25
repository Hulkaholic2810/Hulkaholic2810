# Pocket Lift Log for Android (test build)

A full-screen WebView around `workout-log.html`, built without the Android SDK.

```
bash android/build-apk.sh      # -> dist/PocketLiftLog-test.apk
```

- Needs a JDK, Python 3 with Pillow, and Maven Central (it downloads the API 16 stub jar and the `dx` dexer).
- `make_apk.py` writes the binary manifest, a one-icon `resources.arsc`, the launcher icon, and the web app
  with its fonts inlined so it works offline.
- Signed with a local test key kept in `android/.cache` (not committed). Builds with the same key install as updates.
- Targets API 29 with a v1 signature, which Android accepts for sideloaded test installs.
