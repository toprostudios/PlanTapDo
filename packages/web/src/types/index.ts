// src/types/index.ts

export type TodoStatus = 'todo' | 'in-progress' | 'done' | 'skipped';
export type PriorityLevel = 'low' | 'medium' | 'high' | 'urgent';

export interface UserAccount {
  id: string;
  name: string;
  email: string;
  avatarUrl?: string;
  tier: 'Free' | 'Pro' | 'Enterprise';
  isCloudSynced: boolean;
  workspacesCount: number;
}

export interface TeamMember {
  id: string;
  name: string;
  role: string;
  avatarUrl: string;
  department: string;
  status: 'active' | 'break' | 'offline';
  capacityMinutes: number;
}

export interface RecurrenceRule {
  frequency: 'daily' | 'weekly' | 'monthly';
  interval: number; // every N days/weeks/months
  daysOfWeek?: number[]; // 0-6 (Sun=0) for weekly
  endDate?: string; // ISO date
  count?: number; // max occurrences
}

export interface TimeSession {
  id: string;
  todoId: string;
  startedAt: string; // ISO datetime
  stoppedAt?: string; // ISO datetime, undefined if running
}

export interface Subtask {
  id: string;
  title: string;
  completed: boolean;
}

export interface TodoEntry {
  id: string;
  title: string;
  description?: string;
  categoryId: string;

  // Planning fields
  plannedDuration: number; // minutes
  dueDate: string; // YYYY-MM-DD
  dueTime?: string; // HH:MM
  descriptiveDeadline?: string; // descriptive deadline note (no effect on calendar view)
  doDate: string; // YYYY-MM-DD
  plannedStartTime?: string; // HH:MM
  assigneeId?: string; // ID of assigned team member

  // Metadata fields
  priority?: PriorityLevel;
  labels?: string[];
  reminder?: string;
  location?: string;

  recurrence?: RecurrenceRule;

  // Status & tracking
  status: TodoStatus;
  completedAt?: string; // ISO datetime
  sessions: TimeSession[]; // all start/stop pairs
  subtasks?: Subtask[];
  sortOrder: number; // for list view ordering
}

export interface Category {
  id: string;
  name: string;
  color: string; // hex code
  icon?: string; // optional emoji
  notes?: string; // Notion-type text document content
}

export interface AppState {
  userAccount: UserAccount;
  availableAccounts: UserAccount[];
  teamMembers: TeamMember[];
  todos: TodoEntry[];
  categories: Category[];
  activeSessionId?: string;
  loading: boolean;
  error: string | null;

  // Saved location travel times matrix (key: "locationa|locationb", value: durationInMinutes)
  locationTravelTimes: Record<string, number>;

  // Computed / schedule helper
  pushedSchedule: Record<string, TodoEntry[]>;

  // Team & Manager actions
  addTeamMember: (member: Omit<TeamMember, 'id'>) => void;
  assignTodoToMember: (todoId: string, memberId?: string) => void;

  // Account actions
  switchAccount: (accountId: string) => void;
  createAndSwitchAccount: (name: string, email: string) => void;

  // Category actions
  addCategory: (cat: Omit<Category, 'id'>) => void;
  updateCategoryNotes: (id: string, notes: string) => void;
  deleteCategory: (id: string) => void;

  // Todo actions
  addTodo: (todo: Omit<TodoEntry, 'id' | 'status' | 'sessions' | 'sortOrder'>) => void;
  updateTodo: (id: string, patch: Partial<TodoEntry>) => void;
  deleteTodo: (id: string) => void;
  duplicateTodo: (id: string) => void;

  // Subtask actions
  addSubtask: (todoId: string, title: string) => void;
  toggleSubtask: (todoId: string, subtaskId: string) => void;
  deleteSubtask: (todoId: string, subtaskId: string) => void;

  // Location travel time memory action
  setTravelTimeBetweenLocations: (locA: string, locB: string, durationMinutes: number) => void;
  getTravelTimeBetweenLocations: (locA: string, locB: string) => number;

  startTimer: (todoId: string) => void;
  stopTimer: (todoId: string) => void;
  finishTodo: (todoId: string) => void;
  moveTodoOnCalendar: (todoId: string, doDate: string, plannedStartTime?: string) => void;
  reorderTodos: (orderedIds: string[]) => void;
  refreshTodos: () => Promise<void>;
  resetToSampleData: () => void;
}
