#!/usr/bin/env bash
# Genera le cartelle android/ e ios/ (non versionate) e applica le modifiche necessarie.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --project-name d_photo_watch_lab --org dev.dphotowatchlab --platforms=android,ios .
rm -f test/widget_test.dart

MANIFEST=android/app/src/main/AndroidManifest.xml
# Nome visibile dell'app.
sed -i 's#android:label="[^"]*"#android:label="D. Photo Watch Lab"#' "$MANIFEST"
# gal: scrittura in galleria su Android 10 e precedenti.
if ! grep -q 'WRITE_EXTERNAL_STORAGE' "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>\n    <application android:requestLegacyExternalStorage="true"#' "$MANIFEST"
fi
# Scontorno IA (ML Kit): scarica il modello già all'installazione.
if ! grep -q 'mlkit.vision.DEPENDENCIES' "$MANIFEST"; then
  sed -i 's#</application>#    <meta-data android:name="com.google.mlkit.vision.DEPENDENCIES" android:value="subject_segment"/>\n    </application>#' "$MANIFEST"
fi
# Foto grandi: più memoria per l'app.
sed -i 's#<application #<application android:largeHeap="true" #' "$MANIFEST"

# image_picker e gal richiedono minSdk 24.
for f in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$f" ] || continue
  sed -i -E 's/minSdk(Version)? *=? *flutter\.minSdkVersion/minSdk = 24/' "$f"
done

# Il lint "vital" di Android va in crash su alcuni plugin (bug degli
# strumenti Google, NoSuchMethodError in JavaDocParser): lo disattiviamo.
if [ -f android/build.gradle.kts ]; then
  cat >> android/build.gradle.kts <<'GRADLE'

subprojects {
    tasks.configureEach {
        if (name.contains("lintVital")) enabled = false
    }
}
GRADLE
elif [ -f android/build.gradle ]; then
  cat >> android/build.gradle <<'GRADLE'

subprojects {
    tasks.configureEach { t ->
        if (t.name.contains("lintVital")) t.enabled = false
    }
}
GRADLE
fi

# iOS: descrizioni per foto e fotocamera (solo su macOS).
if [ "$(uname)" = "Darwin" ] && [ -f ios/Runner/Info.plist ]; then
  /usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryUsageDescription string 'Per scegliere le foto degli orologi.'" ios/Runner/Info.plist || true
  /usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryAddUsageDescription string 'Per salvare le foto ritoccate.'" ios/Runner/Info.plist || true
  /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string 'Per fotografare gli orologi.'" ios/Runner/Info.plist || true
fi

echo "--- Manifest ---"; cat "$MANIFEST"
echo "--- minSdk ---"; grep -n minSdk android/app/build.gradle* || true

flutter pub get
# Icona dell'app (stile Marchio dom)
dart run flutter_launcher_icons
