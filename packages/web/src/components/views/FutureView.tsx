// src/components/views/FutureView.tsx
import React, { useState } from 'react';
import { useTodoStore } from '../../store/todoStore';
import { useUIStore } from '../../store/uiStore';
import { TodoCard } from '../todo/TodoCard';
import { CalendarDayGrid } from '../calendar/CalendarDayGrid';
import { KanbanBoardView } from './KanbanBoardView';
import { NaturalLanguageInput } from '../todo/NaturalLanguageInput';
import { addDays, format, startOfWeek, addWeeks, parseISO } from 'date-fns';
import './FutureView.css';

export type ViewMode = 'list' | 'calendar' | 'kanban';

export const FutureView: React.FC = () => {
  const todos = useTodoStore((state) => state.todos);
  const openSettings = useUIStore((state) => state.openSettings);

  const tomorrowIso = format(addDays(new Date(), 1), 'yyyy-MM-dd');
  const [selectedDateIso, setSelectedDateIso] = useState<string>(tomorrowIso);
  const [weekOffset, setWeekOffset] = useState<number>(0);
  const [viewMode, setViewMode] = useState<ViewMode>('list');

  // Compute week days array based on current weekOffset
  const baseDate = addWeeks(new Date(), weekOffset);
  const mondayOfOffsetWeek = startOfWeek(baseDate, { weekStartsOn: 1 });
  const weekDays = Array.from({ length: 7 }, (_, i) => addDays(mondayOfOffsetWeek, i));

  const dayTodos = todos
    .filter((t) => t.doDate === selectedDateIso)
    .sort((a, b) => {
      const timeA = a.plannedStartTime || '23:59';
      const timeB = b.plannedStartTime || '23:59';
      return timeA.localeCompare(timeB);
    });

  const selectedDateObj = parseISO(selectedDateIso);

  return (
    <div className="view-page-container animate-fade-in">
      {/* Header Bar with View Switcher & Settings Button */}
      <div className="view-header-bar">
        <div className="view-title-group">
          <h2 className="view-main-title">🗓️ Future Schedule</h2>
          <span className="view-subtitle">
            {format(selectedDateObj, 'EEEE, MMMM d, yyyy')}
          </span>
        </div>

        <div className="view-header-right">
          {/* View Mode Toggle Pill Group */}
          <div className="view-toggle-pill-group" aria-label="Toggle Future View Layout">
            <button
              className={`view-toggle-btn ${viewMode === 'list' ? 'active' : ''}`}
              onClick={() => setViewMode('list')}
              title="List View"
            >
              📝 List View
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
              title="Kanban Board View"
            >
              📋 Kanban Board
            </button>
          </div>

          <button className="view-settings-btn btn-primary" onClick={openSettings} title="Open Settings">
            ⚙️ Settings
          </button>
        </div>
      </div>

      {/* Week Navigator */}
      <div className="future-week-navigator glass-panel">
        <button
          className="week-nav-arrow-btn"
          onClick={() => setWeekOffset((prev) => prev - 1)}
          title="Previous Week"
        >
          ◄ Previous Week
        </button>

        <div className="week-days-scroll-row">
          {weekDays.map((dayDate) => {
            const dateIsoStr = format(dayDate, 'yyyy-MM-dd');
            const isSelected = dateIsoStr === selectedDateIso;
            const count = todos.filter((t) => t.doDate === dateIsoStr).length;

            return (
              <button
                key={dateIsoStr}
                className={`week-day-card ${isSelected ? 'selected' : ''}`}
                onClick={() => setSelectedDateIso(dateIsoStr)}
              >
                <span className="day-name">{format(dayDate, 'EEE')}</span>
                <span className="day-number">{format(dayDate, 'd')}</span>
                {count > 0 && <span className="day-task-count-dot">{count}</span>}
              </button>
            );
          })}
        </div>

        <button
          className="week-nav-arrow-btn"
          onClick={() => setWeekOffset((prev) => prev + 1)}
          title="Next Week"
        >
          Next Week ►
        </button>
      </div>

      {/* Smart Quick Add Input */}
      <NaturalLanguageInput defaultDateIso={selectedDateIso} />

      {/* View Renderings */}
      {viewMode === 'list' && (
        <div className="future-tasks-list-container glass-panel">
          {dayTodos.length > 0 ? (
            <div className="future-tasks-stack">
              {dayTodos.map((todo) => (
                <TodoCard key={todo.id} todo={todo} />
              ))}
            </div>
          ) : (
            <div className="empty-state-card">
              <span className="empty-icon">📅</span>
              <h3>No tasks scheduled for {format(selectedDateObj, 'MMMM d')}</h3>
              <p>Type a task using smart quick add or select another day on the calendar!</p>
            </div>
          )}
        </div>
      )}

      {viewMode === 'calendar' && <CalendarDayGrid dateIso={selectedDateIso} />}

      {viewMode === 'kanban' && <KanbanBoardView dateIso={selectedDateIso} />}
    </div>
  );
};
