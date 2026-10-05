# Fingerprint + QR Attendance System

University attendance with a portable fingerprint device (ESP32 + R307) and one
Android app for students, lecturers and admins.

```
QR registration → Fingerprint enrollment → Fingerprint verification
→ Automatic attendance → Mobile app (BLE) → Database → Excel/CSV report
```

| Folder      | What                                   | Tech |
|-------------|----------------------------------------|------|
| `mobile/`   | The app (one APK, role-based screens)  | Flutter |
| `backend/`  | Database schema, security rules, RPCs  | Supabase (PostgreSQL) |
| `firmware/` | Fingerprint device                      | ESP32 + Arduino (PlatformIO) |
| `docs/`     | BLE protocol between device and app     | |

## Who does what

**Student (installs the APK)**
1. Create account → scan the course QR shown in class → enter reg. no, name, batch.
2. Open **My QR** and show it to the lecturer to enroll their fingerprint.
3. In class, place their finger on the device. The app shows attendance % per course.

**Lecturer**
1. Home → **Courses** → create a course → show its join QR in class.
2. **Register student** → scan student's QR → confirm details → 3 finger captures.
3. **Start attendance** → device loads the class → students scan → **End session and sync**.
4. **Records** shows sessions and students below 80%; **Export** produces Excel or CSV.

**Admin**: everything a lecturer can do, plus all courses and **Users**, where they
promote accounts to lecturer.

---

## 1. Set up the database (Supabase, free tier is fine)

1. Create a project at <https://supabase.com>.
2. **SQL Editor** → paste all of [`backend/supabase/schema.sql`](backend/supabase/schema.sql) → **Run**.
3. **Project Settings → API**: copy the **Project URL** and the **publishable key**
   (or legacy *anon* key). Both are safe to ship inside the APK. Row Level Security
   protects the data.
4. **Authentication → Providers → Email**: for testing you can turn off *Confirm email*.
   For real use, keep it on.
5. Sign up in the app, then in SQL Editor make yourself admin (see
   [`backend/supabase/seed.sql`](backend/supabase/seed.sql)):
   ```sql
   update public.profiles set role = 'admin' where email = 'you@eng.ruh.ac.lk';
   ```

## 2. Run the app

Requirements: Flutter 3.44+ and Android Studio (for the Android SDK).

```bash
cd mobile
cp env.example.json env.json      # fill in SUPABASE_URL and SUPABASE_KEY
flutter pub get
flutter run --dart-define-from-file=env.json
```

`ALLOWED_EMAIL_DOMAIN` in `env.json` (e.g. `eng.ruh.ac.lk`) restricts sign-ups to
university emails.

**No hardware yet?** Home → Connect device → **Use demo device**. It follows the same
protocol and adds "Simulate finger" buttons, so you can test enrollment and live
sessions end-to-end.

## 3. Build the APK to share with students

1. Create a signing key once and **keep it safe**. Without the same key, students
   can't install updates over the old version.
   ```bash
   keytool -genkey -v -keystore attendance-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias attendance
   ```
2. Create `mobile/android/key.properties` (already git-ignored):
   ```properties
   storePassword=...
   keyPassword=...
   keyAlias=attendance
   storeFile=C:/path/to/attendance-release.jks
   ```
3. Build:
   ```bash
   flutter build apk --release --dart-define-from-file=env.json
   ```
   Output: `mobile/build/app/outputs/flutter-apk/app-release.apk` (one universal APK).
   For smaller downloads, use `--split-per-abi`. Most phones need the `arm64-v8a` file.
4. Share the APK (Google Drive, LMS, WhatsApp). Students allow **Install unknown apps**
   for their browser or file manager the first time.
5. For updates, bump `version:` in `mobile/pubspec.yaml` (e.g. `1.0.1+2`) and rebuild
   with the **same key**.

> iPhone users can't install an APK. Options: an iOS build through TestFlight (needs an
> Apple developer account). Students only *view* attendance in the app; marking is done
> on the device, so iPhone students can still attend.

## 4. Build the fingerprint device

**Parts:** ESP32 DevKit, R307 (or AS608) sensor, 18650 cell + TP4056 charger + boost to
5 V, optional green/red LED + buzzer.

| R307 wire | ESP32 |
|-----------|-------|
| VCC (red) | 5 V (R307) / 3.3 V (AS608) |
| GND (black) | GND |
| TX (green/yellow) | GPIO16 |
| RX (white) | GPIO17 |

LED OK → GPIO25, LED error → GPIO26, buzzer → GPIO27 (change in `firmware/src/config.h`).

```bash
pip install platformio
cd firmware
pio run -t upload
pio device monitor     # shows "FP-Scanner-XXXX ready"
```

## Design notes for 1000+ students

- **Templates live in the database, not on the sensor.** A sensor holds 200–1000
  templates, so before each session the app loads only that course's students
  (about 1 minute for 200). Any device works in any hall.
- **Offline-first.** Every mark is saved on the phone (SQLite) and uploaded in batches.
  No signal in the hall means a delayed upload, not lost data.
- **The device keeps its own log.** If Bluetooth drops mid-lecture, the device keeps
  recording and the app collects the missed scans when it reconnects.
- **Throughput:** about 2 s per student. For a class of 200, use 2–3 devices or start
  scanning as students enter.
- **Security:** Row Level Security means students only see their own records, and only
  staff can read fingerprint templates. The `register_student` function stops a student
  from claiming someone else's registration number once it's linked.

## Project layout

```
mobile/lib/
  main.dart                 app start, role-based routing
  config.dart  theme.dart  models.dart
  services/
    api.dart                all Supabase queries
    device_service.dart     BLE + demo device
    session_controller.dart live session state (survives restarts)
    sync_service.dart       offline upload queue
    export_service.dart     Excel / CSV builder
  screens/auth/             sign in / create account
  screens/staff/            home, connect, register → enroll, session, records, export, courses, users
  screens/student/          registration, home (attendance %), My QR
firmware/src/
  main.cpp                  BLE protocol, enroll / verify modes, scan log
  r307.cpp / r307.h         sensor driver (incl. template upload/download)
backend/supabase/
  schema.sql                tables, RLS policies, RPCs, report views
```
