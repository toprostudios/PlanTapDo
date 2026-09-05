# PlanTapDo project status

**Status date:** September 3, 2026  
**Working version:** Version 1.1 (build 1), local-only iPhone and iPad planner

## Archived release

PlanTapDo **1.0 (build 2)** is the definitive approved version. Its preserved
Xcode archive is at
`/Users/tony/Library/Developer/Xcode/Archives/2026-08-31/PlanTapDo 1.0 (Build 2) — Definitive.xcarchive`.
All subsequent work belongs to version 1.1.

## Completed in the repository

- Core planner: tasks, scheduling, calendar, timers, recurrence, categories,
  Off Time, reports, appearance settings, and local notifications.
- Local-first storage: app state is stored in Application Support with complete
  file protection and excluded from device backups.
- Version 1 scope: no reachable sign-in, account, cloud-sync, analytics, or
  server-hosted task-data flow in the shipping UI. Release has no configured
  API URL and no local-network usage declaration.
- StoreKit 2: entitlement refresh, purchases, restore purchases, localized
  StoreKit pricing, and a compliant PlanTapDo Advanced paywall. Free users can
  create two categories; Advanced unlocks unlimited categories.
- StoreKit configuration: the local test catalog and the App Store Connect
  product metadata checklist are in `ios/PlanTapDo/`.
- Privacy materials: the app privacy manifest and publishable Privacy Policy,
  Terms of Use, and Support text reflect the local-only product and its
  monthly and annual subscription choices.
- The public Privacy Policy (`https://toproindustry.site/plantapdo/privacy`),
  Terms of Use (`https://toproindustry.site/plantapdo/terms`), and Support
  (`https://toproindustry.site/plantapdo/support`) pages are live at the app's
  configured URLs.

## Remaining for the 1.1 update

1. Test the complete Release build on a physical iPhone and iPad, including
   the changed scheduler, recurring-task, and Advanced-paywall flows.
2. Keep the public legal and support pages synchronized with any intended
   changes in `docs/publishable-text/`. The repository cannot determine
   whether a live page needs publishing.
3. Create a signed 1.1 archive and upload a build number that has not already
   been uploaded for version 1.1. Increment `CURRENT_PROJECT_VERSION` only
   when another 1.1 build is needed.
4. Update the 1.1 App Store metadata, screenshots, and review notes for the
   shipped UI.

The monthly and annual subscriptions were already created and reviewed with
1.0. Do not recreate, reconfigure, or resubmit them solely for this update.

## Verification record

- The local StoreKit catalog is valid JSON.
- `Info.plist` and `PrivacyInfo.xcprivacy` pass plist validation.
- The Xcode project enumerates the `PlanTapDo` scheme and its two targets.
- An unsigned Release compile could not be completed in this workspace because
  the host Xcode asset compiler requires an unavailable simulator service.
  This is an environment limitation, not a source-code verdict; use physical
  hardware for required release verification.

## Deliberately out of scope for v1

The `backend/` directory and inactive account/cloud source files are retained
for a future product phase. They are not a deployment dependency or a privacy
claim for the shipping local-only app. Their separate security/deployment
materials must not be read as a v1 release certification.
