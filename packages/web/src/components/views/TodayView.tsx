// src/components/views/TodayView.tsx
import React, { useState } from 'react';
import { useTodoStore } from '../../store/todoStore';
import { TodoCard } from '../todo/TodoCard';
import { CalendarDayGrid } from '../calendar/CalendarDayGrid';
import { KanbanBoardView } from './KanbanBoardView';
import { NaturalLanguageInput } from '../todo/NaturalLanguageInput';
import './TodayView.css';

export type ViewMode = 'list' | 'calendar' | 'kanban';

export const TodayView: React.FC = () => {
  const todos = useTodoStore((state) => state.todos);
  const reorderTodos = useTodoStore((state) => state.reorderTodos);

  // View toggle: List | Calendar | Kanban
  const [viewMode, setViewMode] = useState<ViewMode>('list');

  const todayIso = new Date().toISOString().split('T')[0];

  const todayTodos = todos
    .filter((todo) => todo.doDate === todayIso)
    .sort((a, b) => {
      const timeA = a.plannedStartTime || '23:59';
      const timeB = b.plannedStartTime || '23:59';
      return timeA.localeCompare(timeB);
    });

  const handleDragStart = (e: React.DragEvent, index: number) => {
    e.dataTransfer.setData('text/plain', index.toString());
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
  };

  const handleDrop = (e: React.DragEvent, dropIndex: number) => {
    e.preventDefault();
    const dragIndexStr = e.dataTransfer.getData('text/plain');
    if (!dragIndexStr) return;

    const dragIndex = parseInt(dragIndexStr, 10);
    if (isNaN(dragIndex) || dragIndex === dropIndex) return;

    const updatedList = [...todayTodos];
    const [draggedItem] = updatedList.splice(dragIndex, 1);
    updatedList.splice(dropIndex, 0, draggedItem);

    const reorderedIds = updatedList.map((t) => t.id);
    reorderTodos(reorderedIds);
  };

  return (
    <div className="view-page-container animate-fade-in">
      {/* Header Bar with View Switcher Pill & Prominent Settings Button */}
      <div className="view-header-bar">
        <div className="view-title-group">
          <h2 className="view-main-title">📍 Today's Focus</h2>
          <span className="view-subtitle">
            {new Date().toLocaleDateString(undefined, {
              weekday: 'long',
              month: 'short',
              day: 'numeric',
            })}
          </span>
        </div>

        <div className="view-header-right">
          {/* View Toggle: List View | Calendar View | Kanban Board */}
          <div className="view-toggle-pill-group" aria-label="Toggle Today View Layout">
            <button
              className={`view-toggle-btn ${viewMode === 'list' ? 'active' : ''}`}
              onClick={() => setViewMode('list')}
              title="List View"
            >
              📝 List
            </button>
            <button
              className={`view-toggle-btn ${viewMode === 'calendar' ? 'active' : ''}`}
              onClick={() => setViewMode('calendar')}
              title="Calendar View"
            >
              📅 Calendar
            </button>
            <button
              className={`view-toggle-btn ${viewMode === 'kanban' ? 'active' : ''}`}
              onClick={() => setViewMode('kanban')}
              title="Kanban View"
            >
              📋 Kanban
            </button>
          </div>
        </div>
      </div>

      {/* Todoist-Style Smart Natural Language Quick Add */}
      <NaturalLanguageInput defaultDateIso={todayIso} />

      {/* Dynamic Content View Rendering */}
      {viewMode === 'list' && (
        <div className="today-tasks-list-container glass-panel">
          {todayTodos.length > 0 ? (
            <div className="today-tasks-stack">
              {todayTodos.map((todo, idx) => (
                <div
                  key={todo.id}
                  draggable
                  onDragStart={(e) => handleDragStart(e, idx)}
                  onDragOver={handleDragOver}
                  onDrop={(e) => handleDrop(e, idx)}
                  className="draggable-todo-wrapper"
                >
                  <TodoCard todo={todo} />
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state-card">
              <span className="empty-icon">🎉</span>
              <h3>No tasks scheduled for Today</h3>
              <p>Add a task using smart quick add above or check the Future tab!</p>
            </div>
          )}
        </div>
      )}

      {viewMode === 'calendar' && <CalendarDayGrid dateIso={todayIso} />}

      {viewMode === 'kanban' && <KanbanBoardView dateIso={todayIso} />}
    </div>
  );
};
