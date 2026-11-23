name: Build Nebras SofT Pos APK

on:
  push:
    branches: [ main, master ]
    tags: [ 'v*' ]
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      - name: Setup Android & Build APK
        env:
          KEYSTORE_BASE64: ${{ secrets.KEYSTORE_BASE64 }}
          KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
        run: |
          flutter create --org com.nebrassoft --project-name nebras_soft_pos --platforms=android .
          sed -i 's/android:label="[^"]*"/android:label="Nebras SofT Pos"/' android/app/src/main/AndroidManifest.xml

          HAS_KEYSTORE=0
          if [ -n "$KEYSTORE_BASE64" ] && [ -n "$KEYSTORE_PASSWORD" ] && [ -n "$KEY_ALIAS" ]; then
            echo "$KEYSTORE_BASE64" | base64 -d > android/app/nebras-release.jks
            if [ -s "android/app/nebras-release.jks" ]; then
              HAS_KEYSTORE=1
            fi
          fi
          export HAS_KEYSTORE

          python3 - << 'EOF'
          from pathlib import Path
          import os
          import re

          main_p = Path("lib/main.dart")
          if main_p.exists():
              m_code = main_p.read_text(encoding="utf-8")
              m_code = re.sub(
                  r"static\s+Future\s*>\s*evaluateUpdateStatus\s*\(",
                  "static Future> evaluateUpdateStatus(",
                  m_code,
              )
              m_code = re.sub(
                  r"(static\s+Future>\s+evaluateUpdateStatus\s*\(\s*Map<String,\s*String>\s+settings\s*,\s*\)\s*async\s*\{)\s*static\s+Future>\s+evaluateUpdateStatus\s*\(\s*Map<String,\s*String>\s+settings\s*,\s*\)\s*async\s*\{",
                  r"\1",
                  m_code,
              )
              main_p.write_text(m_code, encoding="utf-8")

          manifest_p = Path("android/app/src/main/AndroidManifest.xml")
          if manifest_p.exists():
              mtxt = manifest_p.read_text(encoding="utf-8")

              perms = [
                  '<uses-feature android:name="android.hardware.camera" android:required="false" />',
                  '<uses-permission android:name="android.permission.CAMERA" />',
                  '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />',
                  '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="32" />',
                  '<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />',
                  '<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />',
                  '<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />',
                  '<uses-permission android:name="android.permission.READ_CONTACTS" />',
                  '<uses-permission android:name="android.permission.WRITE_CONTACTS" />',
                  '<uses-permission android:name="android.permission.CALL_PHONE" />',
                  '<uses-permission android:name="android.permission.READ_PHONE_STATE" />',
                  '<uses-permission android:name="android.permission.READ_CALL_LOG" />',
                  '<uses-permission android:name="android.permission.WRITE_CALL_LOG" />',
                  '<uses-permission android:name="android.permission.SEND_SMS" />',
                  '<uses-permission android:name="android.permission.READ_SMS" />',
                  '<uses-permission android:name="android.permission.RECEIVE_SMS" />',
                  '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
                  '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
                  '<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />',
                  '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />',
                  '<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />',
                  '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />',
                  '<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />',
                  '<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" />',
              ]
              missing_perms = [p_line for p_line in perms if p_line not in mtxt]
              if missing_perms:
                  perms_str = "\n    ".join(missing_perms) + "\n"
                  mtxt = re.sub(r"(\s*<application\b)", "\n    " + perms_str + r"\1", mtxt, count=1)
                  manifest_p.write_text(mtxt, encoding="utf-8")

          settings_p = Path("android/settings.gradle.kts")
          if settings_p.exists():
              txt = settings_p.read_text(encoding="utf-8")
              txt = txt.replace('id("org.jetbrains.kotlin.android") version "2.3.20"', 'id("org.jetbrains.kotlin.android") version "2.1.0"')
              if "mavenCentral()" not in txt:
                  txt = txt.replace("gradlePluginPortal()", "gradlePluginPortal()\n        mavenCentral()")

              hook = (
                  "gradle.beforeProject {\n"
                  "    afterEvaluate {\n"
                  "        plugins.withId(\"com.android.library\") {\n"
                  "            extensions.findByType<com.android.build.gradle.LibraryExtension>()?.compileSdk = 36\n"
                  "        }\n"
                  "    }\n"
                  "}\n"
              )
              if "gradle.beforeProject" not in txt:
                  txt = hook + "\n" + txt

              settings_p.write_text(txt, encoding="utf-8")

          gradle_p = Path("android/app/build.gradle.kts")
          if gradle_p.exists():
              gtxt = gradle_p.read_text(encoding="utf-8")
              gtxt = re.sub(r"(compileSdk(?:Version)?)\s*(?:=|\()\s*[^\r\n\)]+\)?", r"\1 = 36", gtxt)
              gtxt = re.sub(r"(targetSdk(?:Version)?)\s*(?:=|\()\s*[^\r\n\)]+\)?", r"\1 = 36", gtxt)

              if os.environ.get("HAS_KEYSTORE") == "1":
                  store_pass = os.environ.get("KEYSTORE_PASSWORD", "").replace('"', '\\"')
                  alias = os.environ.get("KEY_ALIAS", "").replace('"', '\\"')
                  key_pass = (os.environ.get("KEY_PASSWORD") or os.environ.get("KEYSTORE_PASSWORD", "")).replace('"', '\\"')

                  signing_cfg = (
                      "    signingConfigs {\n"
                      "        create(\"release\") {\n"
                      "            storeFile = file(\"nebras-release.jks\")\n"
                      f"            storePassword = \"{store_pass}\"\n"
                      f"            keyAlias = \"{alias}\"\n"
                      f"            keyPassword = \"{key_pass}\"\n"
                      "        }\n"
                      "    }\n"
                  )

                  if "signingConfigs" not in gtxt:
                      gtxt = re.sub(r"(android\s*\{)", r"\1\n" + signing_cfg, gtxt, count=1)

                  if 'signingConfig = signingConfigs.getByName("release")' not in gtxt:
                      gtxt = re.sub(
                          r'(getByName\("release"\)\s*\{)',
                          r'\1\n                signingConfig = signingConfigs.getByName("release")',
                          gtxt,
                          count=1,
                      )

              gradle_p.write_text(gtxt, encoding="utf-8")

          icon_candidates = [
              Path("assets/icon/app_icon.png"),
              Path("assets/app_icon.png"),
              Path("assets/icon.png"),
          ]
          found_icon = next((p for p in icon_candidates if p.exists()), None)
          if found_icon is None and Path("assets").exists():
              for p in Path("assets").rglob("*.png"):
                  if "icon" in p.name.lower() or "logo" in p.name.lower():
                      found_icon = p
                      break

          if found_icon is not None:
              icon_rel = found_icon.as_posix()
              print("Using icon file:", icon_rel)
              Path("flutter_launcher_icons.yaml").write_text(
                  "flutter_launcher_icons:\n"
                  "  android: true\n"
                  "  ios: false\n"
                  f'  image_path: "{icon_rel}"\n'
                  '  adaptive_icon_background: "#0F2C7E"\n'
                  f'  adaptive_icon_foreground: "{icon_rel}"\n',
                  encoding="utf-8",
              )
          else:
              print("No icon file found in assets/")
          EOF

          flutter pub get
          if [ -f "flutter_launcher_icons.yaml" ]; then
            dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
          fi
          flutter build apk --release

      - uses: actions/upload-artifact@v4
        with:
          name: Nebras-SofT-Pos-APK
          path: build/app/outputs/flutter-apk/app-release.apk

      - if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: build/app/outputs/flutter-apk/app-release.apk
          generate_release_notes: true
