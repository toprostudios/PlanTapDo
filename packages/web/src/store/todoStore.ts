// src/store/todoStore.ts
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import { v4 as uuidv4 } from 'uuid';
import type { AppState, TodoEntry, Category, TimeSession, TodoStatus, Subtask, UserAccount, TeamMember } from '../types';
import { setWsMessageHandler } from '../websocket';
import * as api from '../api/todos';

const getTodayIso = () => new Date().toISOString().split('T')[0];
const getFutureIso = (daysAhead: number) => {
  const d = new Date();
  d.setDate(d.getDate() + daysAhead);
  return d.toISOString().split('T')[0];
};

export function makeLocationKey(locA: string, locB: string): string {
  const normA = locA.trim().toLowerCase();
  const normB = locB.trim().toLowerCase();
  return normA < normB ? `${normA}|${normB}` : `${normB}|${normA}`;
}

const DEFAULT_ACCOUNTS: UserAccount[] = [
  {
    id: 'acc-pro',
    name: 'Tony Pro Workspace',
    email: 'tony@plantapdo.app',
    avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=150&q=80',
    tier: 'Pro',
    isCloudSynced: true,
    workspacesCount: 4,
  },
  {
    id: 'acc-personal',
    name: 'Personal Account',
    email: 'tony.personal@plantapdo.app',
    tier: 'Free',
    isCloudSynced: true,
    workspacesCount: 1,
  },
  {
    id: 'acc-team',
    name: 'Product Team Workspace',
    email: 'team@plantapdo.app',
    tier: 'Enterprise',
    isCloudSynced: true,
    workspacesCount: 12,
  },
];

const DEFAULT_TEAM_MEMBERS: TeamMember[] = [
  {
    id: 'tm-1',
    name: 'Alex Vance',
    role: 'Lead UI/UX Designer 🎨',
    avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=150&q=80',
    department: 'Design',
    status: 'active',
    capacityMinutes: 360,
  },
  {
    id: 'tm-2',
    name: 'Sarah Chen',
    role: 'Senior Frontend Architect 💻',
    avatarUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=150&q=80',
    department: 'Engineering',
    status: 'active',
    capacityMinutes: 480,
  },
  {
    id: 'tm-3',
    name: 'Marcus Brody',
    role: 'Group Product Manager 📊',
    avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=150&q=80',
    department: 'Product',
    status: 'active',
    capacityMinutes: 300,
  },
  {
    id: 'tm-4',
    name: 'Elena Rostova',
    role: 'DevOps & Infra Lead ⚙️',
    avatarUrl: 'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=150&q=80',
    department: 'Infrastructure',
    status: 'break',
    capacityMinutes: 240,
  },
];

const DEFAULT_CATEGORIES: Category[] = [
  {
    id: 'cat-work',
    name: 'Work & Projects',
    color: '#7c6ff7',
    icon: '💼',
    notes: `# 💼 Work & Projects Notion Workspace\n\nWelcome to your Notion-style project notebook. Use this space for free-form brainstorming, sprint notes, and meeting agendas.\n\n## 🎯 Q3 Objectives & Key Results\n- [x] Finalize high-contrast design system\n- [ ] Ship multi-day calendar timeline views\n- [ ] Review sprint velocity and backlog items\n\n## 📝 Project Meeting Notes\n> "Simplicity is prerequisite for reliability." — Edsger W. Dijkstra\n\nFeel free to type notes, checklist items, and project ideas here!`,
  },
  {
    id: 'cat-personal',
    name: 'Personal & Life',
    color: '#3ecf8e',
    icon: '🏡',
    notes: `# 🏡 Personal & Life Document\n\nKeep track of home projects, personal goals, and weekly routines.\n\n## 🛒 Weekly Checklist\n- [ ] Organic groceries & meal prep\n- [ ] Clean home studio & desk workspace\n- [ ] Schedule weekend family call`,
  },
  {
    id: 'cat-health',
    name: 'Health & Fitness',
    color: '#f5a623',
    icon: '🏋️',
    notes: `# 🏋️ Health & Fitness Log\n\n## 🏃 Workout Schedule\n- Monday: Upper Body Strength + 15m Cardio\n- Wednesday: Core & Treadmill Intervals\n- Friday: Leg Day & Mobility Warmup`,
  },
  {
    id: 'cat-learning',
    name: 'Learning & Skills',
    color: '#60a5fa',
    icon: '📚',
    notes: `# 📚 Learning & Skills Notebook\n\n## 📖 Currently Reading\n- Clean Architecture by Robert C. Martin\n- Key concepts: Dependency Inversion, Use Case Layering`,
  },
];

const DEFAULT_LOCATION_TRAVEL_TIMES: Record<string, number> = {
  [makeLocationKey('HQ Office (3rd Floor)', 'Equinox Gym')]: 20,
  [makeLocationKey('Equinox Gym', 'Home Studio')]: 15,
  [makeLocationKey('Home Studio', 'Coffee Shop')]: 10,
  [makeLocationKey('Home Studio', 'Whole Foods Market')]: 25,
};

const getSampleTodos = (): TodoEntry[] => {
  const today = getTodayIso();
  const tomorrow = getFutureIso(1);
  const dayAfter = getFutureIso(2);
  const nextWeek = getFutureIso(5);

  return [
    {
      id: 'todo-1',
      title: 'Review Q3 Product Roadmap & Deliverables',
      description: 'Go over feature specs, sprint capacity, and design reviews with the team.',
      categoryId: 'cat-work',
      plannedDuration: 45,
      doDate: today,
      dueDate: today,
      dueTime: '17:00',
      descriptiveDeadline: 'Before EOD client sync',
      plannedStartTime: '09:00',
      assigneeId: 'tm-3',
      priority: 'high',
      location: 'HQ Office (3rd Floor)',
      labels: ['product', 'roadmap', 'high-priority'],
      reminder: '15 minutes before',
      status: 'in-progress',
      sessions: [
        { id: 'sess-1', todoId: 'todo-1', startedAt: new Date(Date.now() - 15 * 60000).toISOString() },
      ],
      subtasks: [
        { id: 'sub-1', title: 'Check sprint backlog estimates', completed: true },
        { id: 'sub-2', title: 'Verify design mockup deliverables', completed: false },
        { id: 'sub-3', title: 'Draft release timeline email', completed: false },
      ],
      sortOrder: 1,
    },
    {
      id: 'todo-2',
      title: 'Morning Gym & Cardio Session',
      description: '30 min strength training followed by 15 min high-intensity treadmill intervals.',
      categoryId: 'cat-health',
      plannedDuration: 60,
      doDate: today,
      dueDate: today,
      dueTime: '10:00',
      descriptiveDeadline: 'Before morning standup',
      plannedStartTime: '07:30',
      assigneeId: 'tm-1',
      priority: 'medium',
      location: 'Equinox Gym',
      labels: ['health', 'fitness'],
      reminder: '30 minutes before',
      status: 'done',
      completedAt: new Date().toISOString(),
      sessions: [
        {
          id: 'sess-2',
          todoId: 'todo-2',
          startedAt: new Date(Date.now() - 120 * 60000).toISOString(),
          stoppedAt: new Date(Date.now() - 60 * 60000).toISOString(),
        },
      ],
      subtasks: [
        { id: 'sub-4', title: 'Stretching & warm up', completed: true },
        { id: 'sub-5', title: '30m strength workout', completed: true },
      ],
      sortOrder: 2,
    },
    {
      id: 'todo-3',
      title: 'Design Review & System Architecture Refresh',
      description: 'Refactor UI design tokens for high contrast and modern dark/light themes.',
      categoryId: 'cat-work',
      plannedDuration: 90,
      doDate: today,
      dueDate: today,
      dueTime: '16:00',
      descriptiveDeadline: 'Before design review call',
      plannedStartTime: '11:00',
      assigneeId: 'tm-2',
      priority: 'urgent',
      location: 'Home Studio',
      labels: ['ui-ux', 'architecture', 'design'],
      reminder: '10 minutes before',
      status: 'todo',
      sessions: [],
      subtasks: [
        { id: 'sub-6', title: 'Audit high-contrast tokens', completed: false },
        { id: 'sub-7', title: 'Test 3-day and weekly view modes', completed: false },
      ],
      sortOrder: 3,
    },
    {
      id: 'todo-4',
      title: 'Read 2 Chapters of Clean Architecture',
      description: 'Take notes on dependency inversion and boundary interfaces.',
      categoryId: 'cat-learning',
      plannedDuration: 30,
      doDate: tomorrow,
      dueDate: tomorrow,
      dueTime: '21:00',
      descriptiveDeadline: 'Before bedtime',
      plannedStartTime: '10:00',
      assigneeId: 'tm-2',
      priority: 'low',
      location: 'Coffee Shop',
      labels: ['reading', 'learning'],
      reminder: '1 hour before',
      status: 'todo',
      sessions: [],
      subtasks: [],
      sortOrder: 4,
    },
    {
      id: 'todo-5',
      title: 'Weekly Grocery & Household Supplies',
      description: 'Buy organic produce, meal prep ingredients, and cleaning supplies.',
      categoryId: 'cat-personal',
      plannedDuration: 45,
      doDate: dayAfter,
      dueDate: dayAfter,
      dueTime: '18:00',
      descriptiveDeadline: 'Before dinner',
      plannedStartTime: '14:00',
      assigneeId: 'tm-1',
      priority: 'medium',
      location: 'Whole Foods Market',
      labels: ['groceries', 'errands'],
      reminder: '30 minutes before',
      status: 'todo',
      sessions: [],
      subtasks: [],
      sortOrder: 5,
    },
    {
      id: 'todo-6',
      title: 'Sprint Retrospective & Team Sync',
      description: 'Discuss wins, blockers, and process improvements for next sprint.',
      categoryId: 'cat-work',
      plannedDuration: 60,
      doDate: nextWeek,
      dueDate: nextWeek,
      dueTime: '15:00',
      descriptiveDeadline: 'Before sprint end',
      plannedStartTime: '14:00',
      assigneeId: 'tm-4',
      priority: 'high',
      location: 'HQ Office (3rd Floor)',
      labels: ['sprint', 'retro', 'team'],
      reminder: '15 minutes before',
      status: 'todo',
      sessions: [],
      subtasks: [],
      sortOrder: 6,
    },
  ];
};

export const useTodoStore = create<AppState>()(
  persist(
    (set, get) => ({
      userAccount: DEFAULT_ACCOUNTS[0],
      availableAccounts: DEFAULT_ACCOUNTS,
      teamMembers: DEFAULT_TEAM_MEMBERS,
      todos: getSampleTodos(),
      categories: DEFAULT_CATEGORIES,
      locationTravelTimes: DEFAULT_LOCATION_TRAVEL_TIMES,
      activeSessionId: 'sess-1',
      loading: false,
      error: null,

      get pushedSchedule() {
        const map: Record<string, TodoEntry[]> = {};
        for (const todo of get().todos) {
          if (!map[todo.doDate]) map[todo.doDate] = [];
          map[todo.doDate].push(todo);
        }
        for (const date in map) {
          map[date].sort((a, b) => {
            const timeA = a.plannedStartTime || '23:59';
            const timeB = b.plannedStartTime || '23:59';
            return timeA.localeCompare(timeB);
          });
        }
        return map;
      },

      // Team actions
      addTeamMember: (member) => {
        const newMember: TeamMember = {
          ...member,
          id: uuidv4(),
        };
        set((state) => ({ teamMembers: [...state.teamMembers, newMember] }));
      },

      assignTodoToMember: (todoId, memberId) => {
        set((state) => ({
          todos: state.todos.map((t) => (t.id === todoId ? { ...t, assigneeId: memberId } : t)),
        }));
      },

      // Account actions
      switchAccount: (accountId) => {
        const target = get().availableAccounts.find((a) => a.id === accountId);
        if (target) {
          set({ userAccount: target });
        }
      },

      createAndSwitchAccount: (name, email) => {
        if (!name.trim() || !email.trim()) return;
        const newAcc: UserAccount = {
          id: uuidv4(),
          name: name.trim(),
          email: email.trim(),
          tier: 'Pro',
          isCloudSynced: true,
          workspacesCount: 1,
        };
        set((state) => ({
          availableAccounts: [...state.availableAccounts, newAcc],
          userAccount: newAcc,
        }));
      },

      // Category actions
      addCategory: (cat) => {
        const newCat: Category = {
          ...cat,
          id: uuidv4(),
          notes: `# ${cat.icon || '🏷️'} ${cat.name} Document\n\nStart typing notes, checklists, or project details...`,
        };
        set((state) => ({ categories: [...state.categories, newCat] }));
      },

      updateCategoryNotes: (id, notes) => {
        set((state) => ({
          categories: state.categories.map((c) => (c.id === id ? { ...c, notes } : c)),
        }));
      },

      deleteCategory: (id) => {
        set((state) => ({
          categories: state.categories.filter((c) => c.id !== id),
          todos: state.todos.filter((t) => t.categoryId !== id),
        }));
      },

      // Location travel time memory action
      setTravelTimeBetweenLocations: (locA: string, locB: string, durationMinutes: number) => {
        if (!locA.trim() || !locB.trim() || locA.trim().toLowerCase() === locB.trim().toLowerCase()) return;
        const key = makeLocationKey(locA, locB);
        set((state) => ({
          locationTravelTimes: {
            ...state.locationTravelTimes,
            [key]: durationMinutes,
          },
        }));
      },

      getTravelTimeBetweenLocations: (locA: string, locB: string) => {
        const key = makeLocationKey(locA, locB);
        const map = get().locationTravelTimes || {};
        return map[key] || 15;
      },

      // Todo actions
      addTodo: (todoInput) => {
        const id = uuidv4();
        const newTodo: TodoEntry = {
          id,
          title: todoInput.title,
          description: todoInput.description || '',
          categoryId: todoInput.categoryId,
          plannedDuration: todoInput.plannedDuration || 30,
          doDate: todoInput.doDate || getTodayIso(),
          dueDate: todoInput.dueDate || todoInput.doDate || getTodayIso(),
          dueTime: todoInput.dueTime,
          descriptiveDeadline: todoInput.descriptiveDeadline,
          plannedStartTime: todoInput.plannedStartTime || '09:00',
          assigneeId: todoInput.assigneeId,
          priority: todoInput.priority || 'medium',
          location: todoInput.location,
          labels: todoInput.labels || [],
          reminder: todoInput.reminder,
          recurrence: todoInput.recurrence,
          status: 'todo',
          sessions: [],
          subtasks: todoInput.subtasks || [],
          sortOrder: Date.now(),
        };
        set((state) => ({ todos: [...state.todos, newTodo] }));
      },

      updateTodo: (id, patch) => {
        set((state) => ({
          todos: state.todos.map((t) => (t.id === id ? { ...t, ...patch } : t)),
        }));
      },

      deleteTodo: (id) => {
        set((state) => ({ todos: state.todos.filter((t) => t.id !== id) }));
      },

      duplicateTodo: (id) => {
        const target = get().todos.find((t) => t.id === id);
        if (!target) return;
        const duplicate: TodoEntry = {
          ...target,
          id: uuidv4(),
          title: `${target.title} (Copy)`,
          status: 'todo',
          sessions: [],
          subtasks: (target.subtasks || []).map((st) => ({ ...st, id: uuidv4(), completed: false })),
          sortOrder: Date.now(),
        };
        set((state) => ({ todos: [...state.todos, duplicate] }));
      },

      // Subtask actions
      addSubtask: (todoId, title) => {
        if (!title.trim()) return;
        const newSubtask: Subtask = {
          id: uuidv4(),
          title: title.trim(),
          completed: false,
        };
        set((state) => ({
          todos: state.todos.map((t) =>
            t.id === todoId
              ? { ...t, subtasks: [...(t.subtasks || []), newSubtask] }
              : t
          ),
        }));
      },

      toggleSubtask: (todoId, subtaskId) => {
        set((state) => ({
          todos: state.todos.map((t) => {
            if (t.id === todoId && t.subtasks) {
              const updatedSubtasks = t.subtasks.map((st) =>
                st.id === subtaskId ? { ...st, completed: !st.completed } : st
              );
              return { ...t, subtasks: updatedSubtasks };
            }
            return t;
          }),
        }));
      },

      deleteSubtask: (todoId, subtaskId) => {
        set((state) => ({
          todos: state.todos.map((t) => {
            if (t.id === todoId && t.subtasks) {
              return { ...t, subtasks: t.subtasks.filter((st) => st.id !== subtaskId) };
            }
            return t;
          }),
        }));
      },

      startTimer: (todoId) => {
        const now = new Date().toISOString();
        const sessionId = uuidv4();
        const activeId = get().activeSessionId;
        if (activeId) {
          const runningTodo = get().todos.find((t) =>
            t.sessions.some((s) => s.id === activeId && !s.stoppedAt)
          );
          if (runningTodo) {
            get().stopTimer(runningTodo.id);
          }
        }
        set((state) => {
          const updated = state.todos.map((t) => {
            if (t.id === todoId) {
              const newSession: TimeSession = { id: sessionId, todoId, startedAt: now };
              return { ...t, status: 'in-progress' as TodoStatus, sessions: [...t.sessions, newSession] };
            }
            return t;
          });
          return { todos: updated, activeSessionId: sessionId };
        });
      },

      stopTimer: (todoId) => {
        const now = new Date().toISOString();
        set((state) => {
          const updated = state.todos.map((t) => {
            if (t.id === todoId) {
              const updatedSessions = t.sessions.map((s) => (!s.stoppedAt ? { ...s, stoppedAt: now } : s));
              return { ...t, status: 'todo' as TodoStatus, sessions: updatedSessions };
            }
            return t;
          });
          return { todos: updated, activeSessionId: undefined };
        });
      },

      finishTodo: (todoId) => {
        const now = new Date().toISOString();
        set((state) => {
          const updated = state.todos.map((t) => {
            if (t.id === todoId) {
              const closedSessions = t.sessions.map((s) => (!s.stoppedAt ? { ...s, stoppedAt: now } : s));
              return { ...t, status: 'done' as TodoStatus, completedAt: now, sessions: closedSessions };
            }
            return t;
          });
          return { todos: updated, activeSessionId: undefined };
        });
      },

      moveTodoOnCalendar: (todoId, doDate, plannedStartTime) => {
        set((state) => ({
          todos: state.todos.map((t) => (t.id === todoId ? { ...t, doDate, plannedStartTime } : t)),
        }));
      },

      reorderTodos: (orderedIds) => {
        set((state) => {
          const map = new Map(state.todos.map((t) => [t.id, t]));
          const reordered = orderedIds.map((id) => map.get(id)!).filter(Boolean);
          const remaining = state.todos.filter((t) => !orderedIds.includes(t.id));
          return { todos: [...reordered, ...remaining] };
        });
      },

      refreshTodos: async () => {
        set({ loading: true, error: null });
        try {
          const fetched = await api.fetchTodos();
          if (Array.isArray(fetched) && fetched.length > 0) {
            set({ todos: fetched as any, loading: false });
          } else {
            set({ loading: false });
          }
        } catch {
          set({ loading: false });
        }
      },

      resetToSampleData: () => {
        set({
          userAccount: DEFAULT_ACCOUNTS[0],
          availableAccounts: DEFAULT_ACCOUNTS,
          teamMembers: DEFAULT_TEAM_MEMBERS,
          todos: getSampleTodos(),
          categories: DEFAULT_CATEGORIES,
          locationTravelTimes: DEFAULT_LOCATION_TRAVEL_TIMES,
          activeSessionId: 'sess-1',
        });
      },
    }),
    {
      name: 'timetodo-store-v2',
      storage: createJSONStorage(() => localStorage),
    }
  )
);

export default useTodoStore;

// WebSocket setup
setWsMessageHandler(async () => {
  await useTodoStore.getState().refreshTodos();
});
