// src/components/views/KanbanBoardView.tsx
import React, { useState } from 'react';
import { useTodoStore } from '../../store/todoStore';
import type { TodoStatus } from '../../types';
import './KanbanBoardView.css';

interface KanbanBoardViewProps {
  dateIso?: string;
}

const KANBAN_COLUMNS: { id: TodoStatus; title: string; icon: string; color: string }[] = [
  { id: 'todo', title: 'To Do', icon: '📝', color: '#7c6ff7' },
  { id: 'in-progress', title: 'In Progress', icon: '⚡', color: '#f5a623' },
  { id: 'done', title: 'Completed', icon: '✅', color: '#3ecf8e' },
  { id: 'skipped', title: 'Skipped', icon: '⏭️', color: '#94a3b8' },
];

export const KanbanBoardView: React.FC<KanbanBoardViewProps> = ({ dateIso }) => {
  const todos = useTodoStore((state) => state.todos);
  const categories = useTodoStore((state) => state.categories);
  const updateTodo = useTodoStore((state) => state.updateTodo);
  const startTimer = useTodoStore((state) => state.startTimer);
  const stopTimer = useTodoStore((state) => state.stopTimer);

  const [draggingTodoId, setDraggingTodoId] = useState<string | null>(null);

  const filteredTodos = dateIso
    ? todos.filter((t) => t.doDate === dateIso)
    : todos;

  const handleDragStart = (e: React.DragEvent, id: string) => {
    e.dataTransfer.setData('text/plain', id);
    e.dataTransfer.effectAllowed = 'move';
    setDraggingTodoId(id);
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
  };

  const handleDropOnColumn = (e: React.DragEvent, targetStatus: TodoStatus) => {
    e.preventDefault();
    setDraggingTodoId(null);
    const todoId = e.dataTransfer.getData('text/plain');
    if (!todoId) return;

    if (targetStatus === 'in-progress') {
      startTimer(todoId);
    } else if (targetStatus === 'todo') {
      stopTimer(todoId);
      updateTodo(todoId, { status: 'todo' });
    } else {
      updateTodo(todoId, { status: targetStatus });
    }
  };

  const getCategory = (catId: string) => categories.find((c) => c.id === catId);

  return (
    <div className="kanban-board-container glass-panel animate-fade-in">
      <div className="kanban-columns-grid">
        {KANBAN_COLUMNS.map((col) => {
          const colTodos = filteredTodos.filter((t) => t.status === col.id);

          return (
            <div
              key={col.id}
              className="kanban-column"
              onDragOver={handleDragOver}
              onDrop={(e) => handleDropOnColumn(e, col.id)}
            >
              {/* Column Header */}
              <div className="kanban-column-header" style={{ borderTopColor: col.color }}>
                <div className="col-header-title">
                  <span>{col.icon}</span>
                  <span>{col.title}</span>
                </div>
                <span className="col-count-badge" style={{ backgroundColor: `${col.color}22`, color: col.color }}>
                  {colTodos.length}
                </span>
              </div>

              {/* Column Cards Container */}
              <div className="kanban-cards-list">
                {colTodos.map((todo) => {
                  const cat = getCategory(todo.categoryId);

                  return (
                    <div
                      key={todo.id}
                      draggable
                      onDragStart={(e) => handleDragStart(e, todo.id)}
                      className={`kanban-card ${draggingTodoId === todo.id ? 'is-dragging' : ''}`}
                      style={{ borderLeftColor: cat?.color || col.color }}
                    >
                      <div className="kanban-card-top">
                        <span className="kanban-card-title">{todo.title}</span>
                        {cat && (
                          <span className="cat-chip-pill" style={{ backgroundColor: `${cat.color}22`, color: cat.color }}>
                            {cat.icon} {cat.name}
                          </span>
                        )}
                      </div>

                      {todo.description && <p className="kanban-card-desc">{todo.description}</p>}

                      <div className="kanban-card-meta">
                        <span className="meta-item">⏰ {todo.plannedStartTime || '09:00'} ({todo.plannedDuration}m)</span>
                        {todo.location && <span className="meta-item location">📍 {todo.location}</span>}
                        {todo.descriptiveDeadline && (
                          <span className="meta-item deadline">📝 {todo.descriptiveDeadline}</span>
                        )}
                      </div>

                      {/* Quick Status Buttons */}
                      <div className="kanban-card-actions">
                        {col.id !== 'in-progress' && (
                          <button className="kanban-act-btn start" onClick={() => startTimer(todo.id)}>
                            ▶️ Start
                          </button>
                        )}
                        {col.id === 'in-progress' && (
                          <button className="kanban-act-btn stop" onClick={() => stopTimer(todo.id)}>
                            ⏹️ Stop
                          </button>
                        )}
                        {col.id !== 'done' && (
                          <button className="kanban-act-btn done" onClick={() => updateTodo(todo.id, { status: 'done' })}>
                            ✅ Complete
                          </button>
                        )}
                      </div>
                    </div>
                  );
                })}

                {colTodos.length === 0 && (
                  <div className="kanban-empty-column-placeholder">
                    <span>Drop tasks here</span>
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
