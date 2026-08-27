# PlanTapDo App Store readiness

Assessment date: 2026-08-24

## Verdict

**Code and unsigned bundle: ready for a signed staging build.**

**App Store submission: not yet a go.** The repository-level blockers found in
this sweep have been addressed, but the production service, public legal pages,
iPad evidence, signed Apple validation, and App Store Connect record still need
to be completed. Do not submit the current default Release configuration: its
API, privacy-policy, and support URLs are intentionally blank.

## Addressed in the final sweep

- Added permanent in-app cloud-account deletion under Account settings. The API
  requires the current password and, when enabled, a TOTP or recovery code, then
  deletes the user and all related categories, tasks, timer sessions, travel
  times, authentication challenges, and device sessions.
- Added Privacy Policy and Support links to Settings, supplied through validated
  HTTPS Release build settings, along with the visible app version and build.
- Replaced the pre-rounded icon artwork with an opaque, full-bleed 1024 x 1024
  square asset so iOS applies the platform mask. The original artwork is retained
  as `ios/PlanTapDo/AppIconOriginal.png`.
- Confirmed that the privacy manifest is packaged and declares no tracking,
  UserDefaults required-reason access, and linked email, user ID, and task content
  used only for app functionality.
- Confirmed that onboarding, StoreKit, and subscription code are excluded from
  the shipping target. Version 1.0 is a free app and does not need IAP metadata.
- Confirmed version 1.0 (build 1), bundle ID `com.plantapdo.app`, iOS 16 minimum,
  ARM64, iPhone and iPad support, standard HTTPS-only Release sync, and exempt
  encryption declaration.

## Verified

- Django API suite: 55 passed.
- Production-settings suite: 8 passed.
- Migration drift: none.
- iOS model regression suite: 16 passed earlier in the stabilization sweep.
  The final rerun compiled the app and test bundle, but this Mac's Xcode simulator
  test worker stalled before launching XCTest. The final app itself compiled,
  installed, launched, and navigated normally; this is still a reason to require
  a clean TestFlight pass before submission.
- Final iOS simulator build: succeeded without asset-catalog warnings.
- Final unsigned Release archive: succeeded with Xcode's store bundle validator.
- Archived bundle contains the ARM64 executable, dSYM, app icons, expanded
  production URL keys, and `PrivacyInfo.xcprivacy`.
- Visual smoke: launch, Today list/calendar, Upcoming, Categories, Settings,
  cloud-account entry, and portrait/landscape layouts passed on iPhone iOS 26.5.

## Submission blockers

1. **Deploy production.** Provision Supabase, Redis, SMTP, RLS keys, TLS, backups,
   WAF/rate limits, and monitoring; pass the deployment verification kit; and
   exercise signup, verification, login, sync, offline edits/deletes, password
   reset, MFA, session revocation, and account deletion against staging.
2. **Publish the legal/support pages.** The privacy policy must describe data
   collection, use, sharing, retention, and deletion. The support URL must contain
   a real contact method. Supply both URLs and the public API root when archiving.
3. **Test iPad.** The binary targets both iPhone and iPad, but only an iPhone
   simulator was installed for this sweep. Run the full flow on a current iPad
   runtime and provide iPad screenshots. If iPad is not a 1.0 goal, explicitly
   change the device family before the signed archive instead of submitting an
   untested iPad app.
4. **Complete App Store Connect.** Add description, subtitle, keywords, category,
   copyright, privacy-policy URL, support URL, app-privacy responses, the current
   age-rating questionnaire, territories/pricing, and 1-10 truthful screenshots
   for every supported device family.
5. **Prepare review access.** Provide a stable preverified reviewer account and
   concise review notes explaining cloud sync, email verification, MFA, account
   deletion, and that subscription/paywall code is not present in version 1.0.
6. **Create and validate a signed archive.** Use the real production URLs,
   automatic distribution signing, Organizer's Validate App, upload to App Store
   Connect, and complete an internal TestFlight pass on a physical iPhone and iPad.
   Increment `CURRENT_PROJECT_VERSION` for every later upload.

## Release archive command

```bash
xcodebuild -project ios/PlanTapDo.xcodeproj \
  -scheme PlanTapDo \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath build/PlanTapDo.xcarchive \
  'API_BASE_URL=https://api.example.com/api/' \
  'PRIVACY_POLICY_URL=https://www.example.com/privacy' \
  'SUPPORT_URL=https://www.example.com/support' \
  archive
```

Replace every example value with a live PlanTapDo endpoint. Do not upload an
archive that displays the configuration warning in Settings or cannot create,
sync, and delete a reviewer account over the public service.

## Current Apple references

- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Account deletion: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- App privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Privacy policy management: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- Age ratings: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating
- Screenshots: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- App icons: https://developer.apple.com/design/human-interface-guidelines/app-icons
- SDK submission requirements: https://developer.apple.com/news/?id=ueeok6yw
