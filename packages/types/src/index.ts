// Shared TypeScript interfaces for the PlanTapDo monorepo
// Add more definitions as the project grows.

export interface User {
  id: string;
  email: string;
  name?: string;
}

export interface Category {
  id: string;
  name: string;
  color?: string;
}

export interface TodoEntry {
  id: string;
  title: string;
  description?: string;
  completed: boolean;
  dueDate?: string; // ISO 8601
  categoryId: string;
  createdAt: string;
  updatedAt: string;
}

export interface TimeSession {
  id: string;
  todoId: string;
  start: string; // ISO timestamp
  end?: string; // ISO timestamp when stopped
}
