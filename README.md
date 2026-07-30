# 🕒 PlanTapDo — All-in-One Productivity & Time Management Ecosystem

> **PlanTapDo** is a next-generation, high-performance productivity platform combining the best capabilities of **Todoist** (smart task management), **Google Calendar** (drag-and-drop timeline scheduling), **Notion** (rich document notes & Kanban boards), **Toggl Track** (live active time tracking & efficiency analytics), and **Enterprise Team Management**.

Available as a **React Web Application** (`packages/web`) and an **iOS SwiftUI Application** (`ios/TimeToDoApp`).

---

## ⚡ Tech Stack & Architecture

- **Web Application**: React 18, TypeScript, Vite, Zustand State Management (with `localStorage` persistence), CSS Glassmorphism Design Tokens, HTML5 Drag-and-Drop.
- **iOS Application**: SwiftUI (iOS 16+), Combine Framework, `@Published` Observable Object Architecture, Native Xcode Project integration.
- **Backend API Sync**: Express / Node.js WebSocket real-time state synchronization layer.

---

## 🚀 Quick Start & Build Instructions

### Web Application (`packages/web`)
```bash
# Install dependencies
npm install

# Run Web Development Server (Vite)
npm run dev

# Run Production Build & Typecheck
npm run build
```

### iOS Application (`ios/TimeToDoApp`)
```bash
# Open Xcode Project
open ios/TimeToDoApp.xcodeproj

# Swift Typecheck Verification (CLI)
swiftc -typecheck -sdk $(xcrun --sdk macosx --show-sdk-path) ios/TimeToDoApp/*.swift
```

---

## 📊 Feature Matrix & Product Benchmarking

| Feature Category | Feature Description | PlanTapDo | Todoist | Google Calendar | Notion | Toggl Track |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Calendar Timeline** | 1-Day, 3-Day & 7-Day Weekly Views | ✅ | ❌ | ✅ | ❌ | ❌ |
| **Calendar Interactivity** | Drag-and-drop task rescheduling | ✅ | ❌ | ✅ | ❌ | ❌ |
| **Overlap & Capacity** | Overlapping tasks & capacity gauges | ✅ | ❌ | ✅ | ❌ | ❌ |
| **Location Intelligence**| Remembered travel time matrix | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Natural Language** | Todoist-style quick add (`tomorrow at 10am #work @HQ !high 45m`)| ✅ | ✅ | ❌ | ❌ | ❌ |
| **Subtasks & Metadata** | Nested subtasks & descriptive deadlines | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Rich Documents** | Notion-style text canvas per category | ✅ | ❌ | ❌ | ✅ | ❌ |
| **Kanban Board** | Interactive status column view | ✅ | ❌ | ❌ | ✅ | ❌ |
| **Color Swatches** | 8-Color curated palette & custom hex picker | ✅ | ✅ | ✅ | ✅ | ❌ |
| **Time Tracking** | Live `HH:MM:SS` timer & active bar | ✅ | ❌ | ❌ | ❌ | ✅ |
| **Time Analytics** | Efficiency ratio & time reports | ✅ | ❌ | ❌ | ❌ | ✅ |
| **Multi-Account** | Account switcher & profile manager | ✅ | ❌ | ✅ | ❌ | ❌ |
| **Manager View** | Side-by-side multi-person matrix | ✅ | ❌ | ❌ | ❌ | ❌ |

---

## 📖 Complete Feature Guide

1. **Google Calendar Features**:
   - **Multi-Day Views**: Seamlessly toggle between **1-Day**, **3-Day**, and **7-Day Weekly** timeline grids.
   - **Drag-and-Drop**: Drag task cards directly on hourly calendar grids to reschedule start times.
   - **Overlap Support**: Allows multiple overlapping tasks on the timeline grid.
   - **Location Travel Times Memory**: Remembers travel minutes between locations (e.g. `HQ Office ➔ Equinox Gym = 20m`) and automatically inserts travel blocks on timelines.

2. **Todoist Features**:
   - **Smart Natural Language Input**: Instant shorthand parsing (e.g. `"Roadmap sync tomorrow at 10am #work @HQ !high 45m"`).
   - **Subtasks & Checklists**: Nestable subtasks inside any task entry.
   - **Priority & Metadata**: Low, Medium, High, Urgent badges, reminder times, and descriptive non-calendar deadline notes.

3. **Notion Features**:
   - **Category Document Canvas**: Every category acts as a Notion document with gradient cover header, emoji badge, and autosaving text editor.
   - **Slash Block Toolbar**: Quick buttons for `H1`, `H2`, `Task Checkbox`, `Bullet List`, `Quote`, and `Code Block`.
   - **Kanban Board Views**: Switch Today/Future views into interactive status columns (`To Do`, `In Progress`, `Completed`, `Skipped`).
   - **Category Color Swatches**: Palette picker with 8 swatches (`#7c6ff7` Purple, `#3ecf8e` Emerald, `#f5a623` Amber, `#60a5fa` Sky, `#ec4899` Pink, `#f43f5e` Coral, `#eab308` Yellow, `#14b8a6` Teal).

4. **Toggl Track Features**:
   - **Live Active Timer Bar**: Floating top bar showing current running task, category pill, location tag, and live `HH:MM:SS` digital counter.
   - **Time Analytics Modal**: Toggl-style reports modal showing total tracked hours, planned budget, efficiency ratio %, category time breakdowns, and location breakdowns.

5. **User Account & Multi-Account Switcher**:
   - **Account Switcher**: Profile pill in navbar allowing 1-click switching between accounts (*Tony Pro Workspace*, *Personal Account*, *Product Team Workspace*).
   - **Get New Account**: Quick registration form to sign in and generate new user accounts.

6. **Team & Manager Workspace View**:
   - **Multi-Person Side-by-Side View**: Managers can inspect multiple team members simultaneously.
   - **Active Task Monitor**: Live indicator showing what each member is working on right now (`🔴 ACTIVE NOW`).
   - **Lined Up Schedules**: Chronological list of lined-up tasks for each team member.
   - **Manager Quick Task Dispatcher**: Dispatch new tasks or re-assign existing tasks between team members in 1 click.
