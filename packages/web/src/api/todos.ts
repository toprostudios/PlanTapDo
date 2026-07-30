import api from './client';

type UUID = string;

export interface Todo {
  id: UUID;
  title: string;
  description?: string;
  due_date?: string;
  planned_duration?: number;
  category: UUID;
  status: string;
  owner: UUID;
  created_at: string;
  updated_at: string;
}

export interface Category {
  id: UUID;
  name: string;
  color_hex: string;
  owner: UUID;
}

export interface TimeSession {
  id: UUID;
  todo: UUID;
  start: string;
  end?: string;
  duration?: number;
}

export interface RepeatRule {
  id: UUID;
  todo: UUID;
  frequency: string;
  interval: number;
  until_date?: string;
}

// --- Todo endpoints ---
export const fetchTodos = () => api.get<Todo[]>('/todos/');
export const createTodo = (data: Partial<Todo>) => api.post<Todo>('/todos/', data);
export const updateTodo = (id: UUID, data: Partial<Todo>) => api.patch<Todo>(`/todos/${id}/`, data);
export const deleteTodo = (id: UUID) => api.delete<void>(`/todos/${id}/`);

// --- Category endpoints ---
export const fetchCategories = () => api.get<Category[]>('/categories/');
export const createCategory = (data: Partial<Category>) => api.post<Category>('/categories/', data);
export const updateCategory = (id: UUID, data: Partial<Category>) => api.patch<Category>(`/categories/${id}/`, data);
export const deleteCategory = (id: UUID) => api.delete<void>(`/categories/${id}/`);

// --- Session endpoints ---
export const fetchSessions = () => api.get<TimeSession[]>('/sessions/');
export const createSession = (data: Partial<TimeSession>) => api.post<TimeSession>('/sessions/', data);
export const updateSession = (id: UUID, data: Partial<TimeSession>) => api.patch<TimeSession>(`/sessions/${id}/`, data);
export const deleteSession = (id: UUID) => api.delete<void>(`/sessions/${id}/`);

// --- Repeat rule endpoints ---
export const fetchRepeatRules = () => api.get<RepeatRule[]>('/repeat-rules/');
export const createRepeatRule = (data: Partial<RepeatRule>) => api.post<RepeatRule>('/repeat-rules/', data);
export const updateRepeatRule = (id: UUID, data: Partial<RepeatRule>) => api.patch<RepeatRule>(`/repeat-rules/${id}/`, data);
export const deleteRepeatRule = (id: UUID) => api.delete<void>(`/repeat-rules/${id}/`);
