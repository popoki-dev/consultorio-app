# Consultório — offline-first clinic app (Flutter)

A medical-office app for one clinic, used by one professional on up to 2 devices.
The UI is in Portuguese (pt-BR) and follows the client's reference design: pastel
headers, cards with dark outlines, and a yellow bottom bar.

## Features (mapped to the client's requirements)

| Requirement | Where |
|---|---|
| Full agenda control | **Agenda** tab: week strip, day list, book/edit/reschedule, mark as done/missed/cancelled, conflict warning, swipe left/right to change day |
| Return forecast | When an appointment is marked done, the app asks for the return date (defaults to the care line's interval) |
| Prescription expiry | Patient → Receitas: one **receituário** holds several medications, each with its own dosage and validity (shortcut to set all at once: 30/60/90/180 days…). Medications of the same patient that expire on the same day make **one** reminder and one notification. A new prescription for the same drug closes the old one |
| Last appointment date | Shown on every patient card and in the patient summary |
| Exam results (text) | Patient → Exames: free-text result, previous results of the same exam, optional "repeat on" date |
| Notifications when dates expire | Local notifications N days before (configurable) and on the due date at 08:00. They work offline and with the app closed. The **Lembretes** tab lists overdue and upcoming items with "Agendar" and "Resolvido" buttons |
| Care lines | A patient can be in **several** care lines (e.g. Hipertensão + Diabetes). The return suggestion uses the shortest interval among them; the Painel counts the patient in each line |
| Care-line epidemiology charts | **Painel** tab: search patients by group (gestantes, crianças < 2 anos), care line, age (shortcuts + range slider), sex and CID-10 (code or disease name) → result donut (% of all patients), group composition by line/sex/age, "Ver pacientes" list, indicators (mean age, gestantes, crianças < 2, visits in 30 days, no-show rate), visits per week/month, top CID-10, pending items |
| Prenatal care (pré-natal) | Patient form → **Gestante**: enter the DUM or the gestational age measured on a date (ultrasound). Patient page shows gestational age, trimester, DPP (DUM + 280 days), progress to 40 weeks and the visit schedule (monthly until 28 weeks, every 2 weeks until 36, weekly after). **Registrar parto / encerrar** closes the pregnancy and offers to register the newborn |
| Child follow-up (puericultura) | Children under 2: age in months and days, next monthly visit and a 1–24 month grid (done / missed / upcoming) |
| Return suggestion | When a visit is marked done, the app suggests the return date and says why: prenatal schedule for gestantes (never skipping a phase change), next month of life for children, otherwise the care line's interval |
| Online + offline | Encrypted local SQLite is the source of truth; Supabase sync runs when online |
| Security / LGPD | SQLCipher-encrypted DB (key in Keystore/Keychain), biometric/PIN lock, no Android cloud backup, RLS on the server, screen protection (no screenshots / blank app-switcher preview), notifications show only patient initials by default, deleted records keep no personal data, JSON export **and restore** |

## Project layout

```
lib/
  main.dart                  bootstrap, providers, notification/sync wiring
  core/                      theme (design tokens), pt-BR date helpers, CID-10 list
  data/models.dart           CareLine, Patient, Appointment, Prescription, Exam, Reminder
  data/care_rules.dart       prenatal and child follow-up calculations, return suggestion (pure, tested)
  data/local_db.dart         SQLCipher schema + dirty-row tracking
  data/app_data.dart         in-memory repository, reminder computation
  services/                  sync, notifications, biometric lock, settings, export, demo data
  ui/widgets.dart            design-system components (AccentPage, WeekStrip, PillBarChart…)
  ui/screens/                agenda, patients, patient detail, forms, reminders, dashboard, settings
android/                     Android project (desugaring, minSdk 23, release signing)
supabase/schema.sql          server tables, triggers, RLS
setup.ps1                    Windows: generates the ios folder and applies its Face ID text
```

## Setup

> **Windows:** keep the project out of OneDrive and out of any path with non-ASCII
> characters (e.g. `C:\dev\consultorio`). Android Gradle fails on Windows with
> non-ASCII project paths, and OneDrive file locking breaks builds.

1. Install Flutter 3.47 or newer (`pubspec.lock` was resolved with 3.47.7), JDK 17
   and the Android SDK (platform 36, build-tools 36, NDK 28.2.13676358). Then run
   `flutter doctor`; the Android toolchain must show ✓.
2. In the project folder, run:
   ```bash
   flutter pub get --enforce-lockfile
   flutter test
   flutter run
   ```
3. In the app, open **Ajustes → Carregar dados de demonstração** to load 63
   fictional patients (including 8 gestantes and 7 young children) for a client demo. **Remover dados de demonstração** deletes them.

### Sync between the 2 devices (optional)

1. Create a Supabase project and run `supabase/schema.sql` in the SQL editor.
2. Authentication → Users → create the doctor's user (email + password).
   Authentication → Providers → turn off public sign-ups.
3. Build with the keys:
   ```powershell
   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
   ```
4. In the app, sign in under **Ajustes → Sincronização**.

Without the keys, the app runs 100% locally.

How sync works: every local write marks the row `dirty`. A sync pulls rows with
`server_updated_at` greater than the last cursor (minus a 5-minute overlap, so a
write that committed late is not skipped), then upserts dirty rows. Each local row
remembers the server version it is based on (`base_updated_at`), so re-pulling a
version the device already knows is a no-op, not a conflict. When the same row
changed on both devices, the newer `updated_at` wins and the losing version is
saved to the local `sync_conflicts` table (kept 90 days). The server enforces the
same rule: the `keep_newest` trigger ignores an upload older than the stored row,
and the app then downloads the newer version. Deletes are soft deletes
(`deleted_at`) with the personal fields blanked, so they propagate without
keeping patient data. Sync runs 3 s after each change, every 5 minutes, and when
the app returns to the foreground.

> **Upgrading an existing Supabase project:** run `supabase/schema.sql` again. It
> is idempotent: it adds the `keep_newest` trigger and the v1.3 columns
> (`patients.care_line_ids`, `prescriptions.group_id`). Update the app on both
> devices: an older version only sees each patient's first care line, and if it
> edits a patient, its single line replaces the list.

### Backups and recovery

Without sync, the device is the only copy. **Ajustes → Dados** shows the date of
the last export and warns after 30 days. **Restaurar backup** merges an exported
file back in: missing or older records are restored, nothing newer is
overwritten, nothing is deleted.

If the database cannot be opened with the key in the Keystore (for example the
key was lost after a device restore), the app keeps the old file as
`consultorio.db.unreadable-<timestamp>`, starts empty and tells the user how to
recover (sync or restore). Any other open error shows an error screen and
touches nothing.

### Release builds

- Android: release builds are signed with the key in `android/key.properties`
  (not in git). Without it, a release build fails on purpose: an APK signed with
  the debug key cannot be updated by one signed with the release key, and
  uninstalling deletes the local database.
  1. Create the key once and **back up the `.jks` and its passwords**. Without
     them, the app installed on the client's phone can never be updated.
     ```bash
     keytool -genkey -v -keystore ~/keys/consultorio-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias consultorio
     ```
  2. `cp android/key.properties.example android/key.properties` and fill it in.
  3. `flutter build apk --release --dart-define=...` (or `appbundle` for Play).

  For a local test only, `CONSULTORIO_DEBUG_SIGNING=1 flutter build apk --release`
  signs with the debug key.
- iOS: needs a Mac with Xcode and an Apple Developer account (US$ 99/year).

## Notes

- Reminders are computed on the device and scheduled as OS notifications, so
  they fire without internet. They are rescheduled whenever data changes. iOS
  limits pending notifications to 64, so the app schedules the nearest 60.
  Tapping a notification opens the **Lembretes** tab.
- `android/gradle.properties` sets `kotlin.jvm.target.validation.mode=warning`: older plugins (`file_picker`, `share_plus`) compile
  Kotlin for JVM 1.8, which otherwise fails the build on AGP 9.
- `file_picker` is pinned to 10.x: 11.x assumes AGP 9 built-in Kotlin, which the
  Flutter template turns off (`android.builtInKotlin=false`).
- The default care lines (Hipertensão, Diabetes, Pré-natal, Puericultura, Saúde
  Mental, Saúde da Mulher, Saúde do Idoso) use fixed IDs, so two devices don't
  create duplicates. Missing defaults are added on upgrade; a line the user deleted
  is not recreated. Edit them in **Ajustes → Linhas de cuidado**.
- The local database checks its columns every time it opens and adds any that are
  missing, so a database from any earlier version opens safely.
