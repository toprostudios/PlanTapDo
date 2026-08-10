# PlanTapDo — Product Overview

PlanTapDo is a personal planning app that combines a straightforward to-do list, optional calendar scheduling, and a focused work timer in one native iOS experience.

## Product principles

- Tasks start simple. A title is enough, and no artificial time is assigned.
- Details stay out of the list. Notes and descriptions are available by opening a task.
- Time is optional. Scheduled tasks appear on the calendar; unscheduled tasks remain list items.
- The calendar follows the day vertically and never requires horizontal scrolling.
- The current-time line keeps an overdue, unstarted task in front of the user by pushing it down until work begins.
- Start and Stop are prominent, direct controls tied to the active task.
- Accounts are personal. Account management belongs in Settings, and there is no team-management view.

## Main views

### Today

Capture untimed tasks quickly, complete them, open details, or start focused work. Users can switch between a compact list and the hourly calendar.

### Future

Choose a date without horizontally scrolling the interface, then review its task list or vertical calendar.

### Categories

Create color-coded personal categories and add tasks with optional notes, deadlines, locations, and planned times.

### Settings

Manage the personal account, cloud registration, appearance, and local sample data. Settings is the rightmost tab.

## Cloud service

The Django API provides JWT-authenticated personal accounts, owner-isolated task and category storage, sync endpoints, time-session resources, and authenticated WebSocket updates. The only supported client in this repository is the native iOS app.
