// src/components/todo/TodoListView.tsx
import React from 'react';
import { useTodoStore } from '../../store/todoStore';
import { TodoCard } from './TodoCard';
import './TodoListView.css';

/**
 * List view that displays all todos with loading and error handling.
 */
export const TodoListView: React.FC = () => {
  const todos = useTodoStore(state => state.todos);
  const loading = useTodoStore(state => state.loading);
  const error = useTodoStore(state => state.error);

  // sort by dueDate then plannedStartTime for a deterministic order
  const sorted = [...todos].sort((a, b) => {
    if (a.dueDate !== b.dueDate) return a.dueDate.localeCompare(b.dueDate);
    if (a.plannedStartTime && b.plannedStartTime) {
      return a.plannedStartTime.localeCompare(b.plannedStartTime);
    }
    return a.sortOrder - b.sortOrder;
  });

  if (loading) {
    return (
      <section className="todo-list-view">
        <div className="spinner" style={{ color: 'var(--accent)', fontSize: '1.5rem' }}>Loading…</div>
      </section>
    );
  }

  if (error) {
    return (
      <section className="todo-list-view">
        <div className="error" style={{ color: 'var(--danger)', padding: 'var(--spacing-md)' }}>
          Error loading todos: {error}
        </div>
      </section>
    );
  }

  return (
    <section className="todo-list-view">
      {sorted.map(todo => (
        <TodoCard key={todo.id} todo={todo} />
      ))}
    </section>
  );
};
