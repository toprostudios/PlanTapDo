// src/components/todo/TodoCard.tsx
import React, { useState } from 'react';
import { useTodoStore } from '../../store/todoStore';
import type { TodoEntry } from '../../types';
import './TodoCard.css';

interface TodoCardProps {
  todo: TodoEntry;
}

export const TodoCard: React.FC<TodoCardProps> = ({ todo }) => {
  const categories = useTodoStore((state) => state.categories);
  const startTimer = useTodoStore((state) => state.startTimer);
  const stopTimer = useTodoStore((state) => state.stopTimer);
  const finishTodo = useTodoStore((state) => state.finishTodo);
  const deleteTodo = useTodoStore((state) => state.deleteTodo);
  const addSubtask = useTodoStore((state) => state.addSubtask);
  const toggleSubtask = useTodoStore((state) => state.toggleSubtask);
  const deleteSubtask = useTodoStore((state) => state.deleteSubtask);

  const [newSubtaskTitle, setNewSubtaskTitle] = useState('');
  const [showSubtasks, setShowSubtasks] = useState(true);

  const category = categories.find((c) => c.id === todo.categoryId);
  const isCompleted = todo.status === 'done';
  const isRunning = todo.status === 'in-progress';

  const subtasks = todo.subtasks || [];
  const completedSubtasks = subtasks.filter((st) => st.completed).length;

  const handleAddSubtask = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newSubtaskTitle.trim()) return;
    addSubtask(todo.id, newSubtaskTitle.trim());
    setNewSubtaskTitle('');
  };

  const getPriorityBadge = (p?: string) => {
    switch (p) {
      case 'urgent': return <span className="meta-pill priority urgent">🔥 URGENT</span>;
      case 'high': return <span className="meta-pill priority high">⚡ HIGH</span>;
      case 'medium': return <span className="meta-pill priority medium">🔹 MED</span>;
      case 'low': return <span className="meta-pill priority low">🟢 LOW</span>;
      default: return null;
    }
  };

  return (
    <div
      className={`todo-card-item glass-panel ${isCompleted ? 'completed' : ''} ${isRunning ? 'running' : ''}`}
      style={{
        borderLeftColor: category?.color || 'var(--accent-primary)',
      }}
    >
      <div className="card-top-wrapper">
        <div className="card-left-section">
          <button
            className="complete-toggle-btn"
            onClick={() => finishTodo(todo.id)}
            title={isCompleted ? 'Completed' : 'Mark as Complete'}
            aria-label="Mark complete"
          >
            {isCompleted ? '✅' : '⭕'}
          </button>

          <div className="card-main-info">
            <div className="card-header-row">
              <h4 className="todo-item-title">{todo.title}</h4>
              {category && (
                <span className="todo-cat-pill" style={{ backgroundColor: `${category.color}22`, color: category.color, borderColor: category.color }}>
                  <span>{category.icon}</span>
                  <span>{category.name}</span>
                </span>
              )}
            </div>

            {todo.description && <p className="todo-item-desc">{todo.description}</p>}

            <div className="todo-meta-badges">
              <span className="meta-pill">⏰ {todo.plannedStartTime || '09:00'} ({todo.plannedDuration} min)</span>
              {getPriorityBadge(todo.priority)}

              {todo.location && <span className="meta-pill location">📍 {todo.location}</span>}

              {todo.descriptiveDeadline && (
                <span className="meta-pill deadline" title="Descriptive deadline (no effect on calendar view)">
                  📝 Deadline: {todo.descriptiveDeadline}
                </span>
              )}

              {todo.dueDate && (
                <span className="meta-pill deadline">
                  🎯 Due {todo.dueDate} {todo.dueTime ? `at ${todo.dueTime}` : ''}
                </span>
              )}

              {todo.reminder && <span className="meta-pill reminder">🔔 {todo.reminder}</span>}

              {subtasks.length > 0 && (
                <button
                  className="subtask-progress-badge"
                  onClick={() => setShowSubtasks(!showSubtasks)}
                >
                  📋 {completedSubtasks}/{subtasks.length} Subtasks
                </button>
              )}
            </div>

            {todo.labels && todo.labels.length > 0 && (
              <div className="card-labels-row">
                {todo.labels.map((lbl) => (
                  <span key={lbl} className="card-label-tag">#{lbl}</span>
                ))}
              </div>
            )}
          </div>
        </div>

        <div className="card-right-section">
          {!isCompleted && (
            <button
              className={`card-timer-btn ${isRunning ? 'running' : ''}`}
              onClick={() => (isRunning ? stopTimer(todo.id) : startTimer(todo.id))}
              title={isRunning ? 'Pause Timer' : 'Start Timer'}
            >
              {isRunning ? '⏱️ Running...' : '▶️ Start Timer'}
            </button>
          )}

          <button
            className="card-delete-btn"
            onClick={() => deleteTodo(todo.id)}
            title="Delete Task"
            aria-label="Delete task"
          >
            🗑️
          </button>
        </div>
      </div>

      {/* Subtasks Checklist Section */}
      <div className="subtasks-container">
        {showSubtasks && subtasks.length > 0 && (
          <div className="subtasks-list">
            {subtasks.map((st) => (
              <div key={st.id} className={`subtask-item ${st.completed ? 'completed' : ''}`}>
                <label className="subtask-label">
                  <input
                    type="checkbox"
                    checked={st.completed}
                    onChange={() => toggleSubtask(todo.id, st.id)}
                    className="subtask-checkbox"
                  />
                  <span className="subtask-title-text">{st.title}</span>
                </label>
                <button
                  className="delete-subtask-btn"
                  onClick={() => deleteSubtask(todo.id, st.id)}
                  title="Remove subtask"
                >
                  ✕
                </button>
              </div>
            ))}
          </div>
        )}

        {/* Inline Add Subtask Input Form */}
        <form onSubmit={handleAddSubtask} className="add-subtask-form">
          <input
            type="text"
            className="add-subtask-input"
            placeholder="+ Add a subtask..."
            value={newSubtaskTitle}
            onChange={(e) => setNewSubtaskTitle(e.target.value)}
          />
          {newSubtaskTitle.trim() && (
            <button type="submit" className="add-subtask-btn">
              Add
            </button>
          )}
        </form>
      </div>
    </div>
  );
};
