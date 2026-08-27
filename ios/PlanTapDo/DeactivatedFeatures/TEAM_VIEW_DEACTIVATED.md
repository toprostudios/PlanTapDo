# Team view — deactivated

The Team review UI and its local Pro Team Review demo are intentionally inactive.

- All Team entry points have been removed from the active app navigation, Account screen, and Weekly Reports.
- The preserved SwiftUI implementation and demo fixtures are wrapped in `#if TEAM_VIEW_ENABLED`; no active Xcode build configuration defines that flag, so they are excluded from builds.
- The legacy Pro Team Review account is filtered from selectable accounts. Existing local demo data is retained rather than deleted.
- There is no Team schema, migration, or Supabase deployment artifact in `backend/supabase`; nothing Team-related is deployed there.

To restore the feature in the future, deliberately define `TEAM_VIEW_ENABLED`, re-add the intended entry points, and review the data model and backend design before shipping.
