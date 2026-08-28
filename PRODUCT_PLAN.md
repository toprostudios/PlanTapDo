# PlanTapDo Product Plan

This is the single source of truth for product scope, release decisions, and
the App Store plan. Technical deployment and security documents describe how
supporting systems work; they do not define what ships.

## Version 1 decision

Ship PlanTapDo as a **local-only personal planner**. Version 1 has no account
creation, login, cloud sync, password reset, MFA, or server-hosted task data.
Tasks are stored only on the user's device. This keeps the first release
focused on the planning experience and avoids making backend operations a
launch dependency.

## Product promise

PlanTapDo turns a personal task list into a live daily schedule.

- A task can be unscheduled or placed at a date and time; new tasks offer a
  time by default.
- Today offers a list and a vertical calendar. Upcoming offers the same view
  for future dates.
- An overdue, unstarted task moves ahead of the current-time line and pushes
  following work forward.
- Starting work moves that task to the current time. The one task card displays
  the stopwatch and grows when work exceeds its planned duration.
- Calendar task cards have a 15-minute minimum display height while keeping
  their exact planned and tracked duration in storage. Short planned cards
  retain their true start times and can overlap visually. Completed tasks in
  the same 15-minute window are shown together as a comma-separated history
  card.
- Tap once to start or stop a calendar task, double tap to open its details,
  and triple tap to mark it complete. Completing unstarted future work removes
  it; completing work with recorded time preserves its historical block.
- Stopping work preserves the elapsed segment as a normal-colored historical
  block and creates a separate pending task for any remaining planned time.
- The Running Tasks setting controls handoff. When automatic handoff is on,
  starting a second task records the first segment and places its unfinished
  remainder after the new task. When it is off, the current task must stop
  before another one can start.
- A single global Off Time window keeps tasks out of sleep or unavailable
  hours. It supports overnight ranges.
- Recurring tasks create their next occurrence only when that day arrives;
  future calendars are not filled with generated copies.

## Version 1 screens

- **Today:** capture, schedule, start, stop, finish, and review today’s tasks
  in a single-day calendar.
- **Upcoming:** inspect and schedule a future day.
- **Tasks:** categories at the top; an optional expandable all-task list below,
  with uncategorized tasks first and the remaining tasks in chronological order.
- **Settings:** timer handoff preference, completed-task visibility, dark/light
  theme, Off Time, daily and weekly reports, privacy policy, and support.

## Monetization

The app is free to download. Free users can create up to two categories.
Premium unlocks unlimited categories. This is the only paid feature in v1.
Before submission, configure the matching StoreKit product(s) and accurately
show the purchase in App Store Connect metadata and review notes.

## Privacy and App Store scope

- No account or cloud backend is part of the shipping v1 experience.
- The privacy policy must accurately describe on-device task storage and any
  purchase data handled by Apple. It must not claim cloud sync.
- The support URL must provide a real way to contact the developer.
- Publish the versioned sources in `docs/publishable-text/` at the privacy and
  support URLs before archiving. These legal pages do not define product scope.
- Test the complete release build on physical iPhone and iPad hardware before
  submission. Submit truthful screenshots and metadata for the shipped feature
  set.

## Post-v1 roadmap

1. Optional cloud sync and accounts, only after the local planner is validated.
   It requires production operations, reliable migration and conflict handling,
   account deletion, support processes, legal disclosures, and App Review test
   access.
2. Per-profile and per-category Off Time schedules.
3. Additional Premium features only when they clearly improve the core planner.

## Documentation rules

`PRODUCT_PLAN.md` is the only product-plan document. `README.md` is technical
project guidance. `SECURITY.md`, `SECURITY_REVIEW.md`, and `backend/` documents
are operational references for the future backend and do not change v1 scope.
