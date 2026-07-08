# Running the app against Supabase

## One-time: create your secrets file
1. Copy the template:
   ```bash
   cp dart_defines.example.json dart_defines.json
   ```
2. Open `dart_defines.json` and paste your real **Project URL** and **anon/publishable key**
   (Supabase Dashboard → Project Settings → API). This file is git-ignored — never commit it.

## Run from the terminal
```bash
flutter run --dart-define-from-file=dart_defines.json
```

## Run from Android Studio
1. Run menu → **Edit Configurations…**
2. Select your Flutter run config (or create one for `lib/main.dart`).
3. In **Additional run args**, add:
   ```
   --dart-define-from-file=dart_defines.json
   ```
4. Pick your emulator/device and press **Run**.

## Build a release APK
```bash
flutter build apk --release --dart-define-from-file=dart_defines.json
```

> If you launch without these defines, the app shows a "Missing Supabase configuration"
> screen on purpose. See `supabase/README.md` for applying the database migration.
