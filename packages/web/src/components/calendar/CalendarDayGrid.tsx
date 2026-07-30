// src/components/calendar/CalendarDayGrid.tsx
import React, { useState, useEffect, useMemo } from 'react';
import { useTodoStore } from '../../store/todoStore';
import type { TodoEntry } from '../../types';
import { addDays, parseISO, format, startOfWeek } from 'date-fns';
import './CalendarDayGrid.css';

interface CalendarDayGridProps {
  dateIso: string;
}

export type CalendarSpan = 1 | 3 | 7;

const HOURS = Array.from({ length: 16 }, (_, i) => i + 7); // 7 AM to 10 PM (22:00)

interface TransportBlock {
  id: string;
  fromLocation: string;
  toLocation: string;
  topPx: number;
  heightPx: number;
  durationMinutes: number;
}

export const CalendarDayGrid: React.FC<CalendarDayGridProps> = ({ dateIso }) => {
  const todos = useTodoStore((state) => state.todos);
  const categories = useTodoStore((state) => state.categories);
  const startTimer = useTodoStore((state) => state.startTimer);
  const stopTimer = useTodoStore((state) => state.stopTimer);
  const updateTodo = useTodoStore((state) => state.updateTodo);
  const getTravelTimeBetweenLocations = useTodoStore((state) => state.getTravelTimeBetweenLocations);

  // Mode: 1 Day, 3 Days, or 7 Days (Weekly)
  const [calendarSpan, setCalendarSpan] = useState<CalendarSpan>(1);

  // Current time state updated every 10 seconds
  const [now, setNow] = useState(new Date());
  const [draggingTodoId, setDraggingTodoId] = useState<string | null>(null);

  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 10000);
    return () => clearInterval(timer);
  }, []);

  const todayIso = new Date().toISOString().split('T')[0];

  // Compute array of dates based on calendarSpan (1 Day, 3 Days, 7 Days)
  const visibleDates = useMemo(() => {
    const baseDate = parseISO(dateIso);
    if (calendarSpan === 1) {
      return [dateIso];
    } else if (calendarSpan === 3) {
      return [0, 1, 2].map((offset) => format(addDays(baseDate, offset), 'yyyy-MM-dd'));
    } else {
      // 7 Days (Weekly View starting Monday)
      const monday = startOfWeek(baseDate, { weekStartsOn: 1 });
      return Array.from({ length: 7 }, (_, i) => format(addDays(monday, i), 'yyyy-MM-dd'));
    }
  }, [dateIso, calendarSpan]);

  // Calculate current time position in pixels (64px per hour, starting 7 AM)
  const currentHour = now.getHours();
  const currentMin = now.getMinutes();
  const currentTimePx = (currentHour - 7) * 64 + (currentMin / 60) * 64;
  const isCurrentTimeInHours = currentHour >= 7 && currentHour <= 22;

  const getCategory = (catId: string) => categories.find((c) => c.id === catId);

  const formatHourLabel = (hour: number) => {
    const period = hour >= 12 ? 'PM' : 'AM';
    const displayHour = hour % 12 === 0 ? 12 : hour % 12;
    return `${displayHour}:00 ${period}`;
  };

  /**
   * Automatic Transport Time Calculation (Remembered Account Location Travel Times Matrix):
   * Uses saved travel times between Location A and Location B.
   */
  const computeTransportBlocksForDay = (targetDateIso: string): TransportBlock[] => {
    const dayTodos = todos
      .filter((t) => t.doDate === targetDateIso && t.plannedStartTime)
      .sort((a, b) => (a.plannedStartTime || '23:59').localeCompare(b.plannedStartTime || '23:59'));

    const transportBlocks: TransportBlock[] = [];

    for (let i = 0; i < dayTodos.length - 1; i++) {
      const taskA = dayTodos[i];
      const taskB = dayTodos[i + 1];

      const locA = taskA.location?.trim();
      const locB = taskB.location?.trim();

      if (locA && locB && locA.toLowerCase() !== locB.toLowerCase()) {
        const [hA, mA] = taskA.plannedStartTime!.split(':').map(Number);
        const endMinA = hA * 60 + mA + taskA.plannedDuration;

        const [hB, mB] = taskB.plannedStartTime!.split(':').map(Number);
        const startMinB = hB * 60 + mB;

        if (startMinB >= endMinA) {
          // Retrieve remembered set travel time between locA & locB
          const rememberedTravelTime = getTravelTimeBetweenLocations ? getTravelTimeBetweenLocations(locA, locB) : 15;
          const transportDuration = Math.max(10, Math.min(60, rememberedTravelTime));

          const topPx = ((endMinA / 60) - 7) * 64;
          const heightPx = Math.max(24, (transportDuration / 60) * 64);

          transportBlocks.push({
            id: `transport-${taskA.id}-${taskB.id}`,
            fromLocation: locA,
            toLocation: locB,
            topPx,
            heightPx,
            durationMinutes: transportDuration,
          });
        }
      }
    }

    return transportBlocks;
  };

  /**
   * Overlap Layout Computation per Day Column
   */
  const computeDayOverlapLayouts = (targetDateIso: string) => {
    const dayTodos = todos.filter((t) => t.doDate === targetDateIso);
    const sorted = dayTodos.map((t) => {
      const [h, m] = (t.plannedStartTime || '09:00').split(':').map(Number);
      const startMin = h * 60 + m;
      const endMin = startMin + t.plannedDuration;
      return { todo: t, startMin, endMin };
    });

    const layouts: Record<string, { colIndex: number; totalCols: number }> = {};

    sorted.forEach(({ todo, startMin, endMin }) => {
      const overlaps = sorted.filter(
        (other) => other.todo.id !== todo.id && startMin < other.endMin && endMin > other.startMin
      );

      if (overlaps.length === 0) {
        layouts[todo.id] = { colIndex: 0, totalCols: 1 };
      } else {
        const cluster = [todo, ...overlaps.map((o) => o.todo)].sort((a, b) => a.id.localeCompare(b.id));
        const colIndex = cluster.findIndex((t) => t.id === todo.id);
        layouts[todo.id] = { colIndex: Math.max(0, colIndex), totalCols: cluster.length };
      }
    });

    return layouts;
  };

  /**
   * Auto-push & Time Compression algorithm per task
   */
  const getPushedMetrics = (todo: TodoEntry, targetDateIso: string) => {
    const [h, m] = (todo.plannedStartTime || '09:00').split(':').map(Number);
    const plannedStartHour = Math.max(7, Math.min(22, h));
    const plannedStartPx = (plannedStartHour - 7) * 64 + (m / 60) * 64;
    const plannedDurationPx = (todo.plannedDuration / 60) * 64;
    const plannedEndPx = plannedStartPx + plannedDurationPx;

    const isTargetToday = targetDateIso === todayIso;
    const isUnstarted = todo.status === 'todo';
    const isRunning = todo.status === 'in-progress';
    const isCompleted = todo.status === 'done';

    let topPx = plannedStartPx;
    let heightPx = Math.max(48, plannedDurationPx);
    let isPushed = false;
    let compressedMinutes = todo.plannedDuration;

    if (isTargetToday && isUnstarted && currentTimePx > plannedStartPx) {
      isPushed = true;
      topPx = Math.min(currentTimePx, plannedEndPx - 15);
      const remainingPx = Math.max(20, plannedEndPx - topPx);
      heightPx = remainingPx;
      compressedMinutes = Math.max(5, Math.round((remainingPx / 64) * 60));
    } else if (isRunning) {
      const runningSession = todo.sessions.find((s) => !s.stoppedAt);
      if (runningSession) {
        const elapsedMin = Math.max(0, (now.getTime() - new Date(runningSession.startedAt).getTime()) / 60000);
        compressedMinutes = Math.max(todo.plannedDuration, Math.round(elapsedMin));
        heightPx = Math.max(plannedDurationPx, (compressedMinutes / 60) * 64);
      }
    }

    return {
      top: `${topPx}px`,
      height: `${heightPx}px`,
      isPushed,
      compressedMinutes,
      isCompleted,
      isRunning,
    };
  };

  // Drag and Drop handlers
  const handleDragStart = (e: React.DragEvent, id: string) => {
    e.dataTransfer.setData('text/plain', id);
    e.dataTransfer.effectAllowed = 'move';
    setDraggingTodoId(id);
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
  };

  const handleDropOnDay = (e: React.DragEvent, targetDateIso: string) => {
    e.preventDefault();
    setDraggingTodoId(null);

    const todoId = e.dataTransfer.getData('text/plain');
    if (!todoId) return;

    const rect = e.currentTarget.getBoundingClientRect();
    const offsetY = Math.max(0, e.clientY - rect.top);

    // 64px per hour, starting 7 AM. Snap to 15-minute intervals.
    const totalMinutesFrom7 = (offsetY / 64) * 60;
    const snappedMinutesFrom7 = Math.round(totalMinutesFrom7 / 15) * 15;

    const hour = Math.max(7, Math.min(22, 7 + Math.floor(snappedMinutesFrom7 / 60)));
    const min = snappedMinutesFrom7 % 60;

    const newTime = `${String(hour).padStart(2, '0')}:${String(min).padStart(2, '0')}`;
    updateTodo(todoId, { plannedStartTime: newTime, doDate: targetDateIso });
  };

  const formatTimeStr = (dateObj: Date) => {
    return dateObj.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  const getPriorityEmoji = (priority?: string) => {
    switch (priority) {
      case 'urgent': return '🔥 URGENT';
      case 'high': return '⚡ HIGH';
      case 'medium': return '🔹 MED';
      case 'low': return '🟢 LOW';
      default: return null;
    }
  };

  return (
    <div className="calendar-day-grid-container glass-panel animate-fade-in">
      {/* Header bar with View Mode Switcher: 1 Day | 3 Days | Week */}
      <div className="day-grid-header">
        <div className="time-col-header">Time</div>
        <div className="events-col-header">
          <div className="header-title-box">
            <span>Calendar Timeline</span>
            <span className="task-count-badge">
              {todos.filter((t) => visibleDates.includes(t.doDate)).length} tasks
            </span>
          </div>

          {/* Calendar View Mode Switcher Pill */}
          <div className="calendar-span-toggle-group" aria-label="Calendar view span">
            <button
              className={`span-pill ${calendarSpan === 1 ? 'active' : ''}`}
              onClick={() => setCalendarSpan(1)}
              title="1 Day View"
            >
              1 Day
            </button>
            <button
              className={`span-pill ${calendarSpan === 3 ? 'active' : ''}`}
              onClick={() => setCalendarSpan(3)}
              title="3 Day View"
            >
              3 Days
            </button>
            <button
              className={`span-pill ${calendarSpan === 7 ? 'active' : ''}`}
              onClick={() => setCalendarSpan(7)}
              title="Weekly View (7 Days)"
            >
              📅 Week
            </button>
          </div>
        </div>
      </div>

      <div className="day-grid-body">
        {/* Hour Scale Labels */}
        <div className="time-scale-column">
          {HOURS.map((hour) => (
            <div key={hour} className="time-slot-label">
              <span>{formatHourLabel(hour)}</span>
            </div>
          ))}
        </div>

        {/* Multi-Day Timeline Columns */}
        <div className={`multi-day-columns-container span-${calendarSpan}`}>
          {visibleDates.map((colDateIso) => {
            const dayTodos = todos.filter((t) => t.doDate === colDateIso);
            const overlapLayouts = computeDayOverlapLayouts(colDateIso);
            const transportBlocks = computeTransportBlocksForDay(colDateIso);
            const isColToday = colDateIso === todayIso;

            const formattedColHeader = format(parseISO(colDateIso), 'EEE, MMM d');

            return (
              <div
                key={colDateIso}
                className={`day-timeline-column ${isColToday ? 'is-today-col' : ''}`}
                onDragOver={handleDragOver}
                onDrop={(e) => handleDropOnDay(e, colDateIso)}
              >
                {/* Column Day Header */}
                <div className="day-column-subheading">
                  <span className="col-header-date">{formattedColHeader}</span>
                  {isColToday && <span className="today-chip">TODAY</span>}
                </div>

                {/* Hour Grid Lines */}
                {HOURS.map((hour) => (
                  <div key={hour} className="grid-hour-line" />
                ))}

                {/* Current Time Bar Indicator Line */}
                {isColToday && isCurrentTimeInHours && (
                  <div className="current-time-bar-indicator" style={{ top: `${currentTimePx}px` }}>
                    <div className="time-bar-tag">NOW {formatTimeStr(now)} 📍</div>
                    <div className="time-bar-line" />
                  </div>
                )}

                {/* Render Automatic Transport Time Blocks (using remembered set travel times) */}
                {transportBlocks.map((tb) => (
                  <div
                    key={tb.id}
                    className="transport-time-block"
                    style={{
                      top: `${tb.topPx}px`,
                      height: `${tb.heightPx}px`,
                    }}
                    title={`Remembered Travel Time: ${tb.fromLocation} ➔ ${tb.toLocation} (${tb.durationMinutes}m)`}
                  >
                    <span className="transport-icon">🚗</span>
                    <span className="transport-text">
                      Travel ({tb.durationMinutes}m): {tb.fromLocation} ➔ {tb.toLocation}
                    </span>
                  </div>
                ))}

                {/* Render Todo Cards for this Day Column */}
                {dayTodos.map((todo) => {
                  const cat = getCategory(todo.categoryId);
                  const metrics = getPushedMetrics(todo, colDateIso);
                  const layout = overlapLayouts[todo.id] || { colIndex: 0, totalCols: 1 };

                  const colWidth = 100 / layout.totalCols;
                  const leftPct = layout.colIndex * colWidth;
                  const priorityLabel = getPriorityEmoji(todo.priority);

                  return (
                    <div
                      key={todo.id}
                      draggable
                      onDragStart={(e) => handleDragStart(e, todo.id)}
                      className={`calendar-todo-block ${metrics.isCompleted ? 'completed' : ''} ${metrics.isRunning ? 'running' : ''} ${metrics.isPushed ? 'pushed' : ''} ${draggingTodoId === todo.id ? 'is-dragging' : ''}`}
                      style={{
                        top: metrics.top,
                        height: metrics.height,
                        left: `calc(${leftPct}% + 6px)`,
                        width: `calc(${colWidth}% - 12px)`,
                        borderLeftColor: cat?.color || 'var(--accent-primary)',
                      }}
                    >
                      <div className="todo-block-header">
                        <div className="title-area">
                          <span className="drag-handle" title="Drag to adjust time or day">⋮⋮</span>
                          {cat && <span className="cat-icon">{cat.icon}</span>}
                          <span className="todo-title-text">{todo.title}</span>
                        </div>

                        {/* Start / Stop Button directly on card */}
                        <div className="actions-area">
                          {!metrics.isCompleted ? (
                            metrics.isRunning ? (
                              <button
                                className="timer-action-btn stop"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  stopTimer(todo.id);
                                }}
                                title="Stop Timer"
                              >
                                ⏹️ Stop
                              </button>
                            ) : (
                              <button
                                className="timer-action-btn start"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  startTimer(todo.id);
                                }}
                                title="Start Timer"
                              >
                                ▶️ Start
                              </button>
                            )
                          ) : (
                            <span className="completed-badge">✅ Done</span>
                          )}
                        </div>
                      </div>

                      {/* Card Details & Metadata */}
                      <div className="todo-block-meta">
                        <span className="meta-time">
                          ⏰ {todo.plannedStartTime || '09:00'}{' '}
                          {metrics.isPushed ? (
                            <strong className="pushed-warning">
                              (Pushed & compressed to {metrics.compressedMinutes}m)
                            </strong>
                          ) : (
                            `(${metrics.compressedMinutes} min)`
                          )}
                        </span>

                        {priorityLabel && <span className="priority-pill">{priorityLabel}</span>}
                        {todo.location && <span className="location-pill">📍 {todo.location}</span>}
                        {todo.descriptiveDeadline && (
                          <span className="deadline-descriptive-pill" title="Descriptive deadline (no effect on calendar view)">
                            📝 {todo.descriptiveDeadline}
                          </span>
                        )}
                        {todo.reminder && <span className="reminder-pill">🔔 {todo.reminder}</span>}
                      </div>

                      {/* Labels / Tags */}
                      {todo.labels && todo.labels.length > 0 && (
                        <div className="todo-labels-row">
                          {todo.labels.map((lbl) => (
                            <span key={lbl} className="label-tag">#{lbl}</span>
                          ))}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
