// src/components/timer/ActiveTimerBar.tsx
import React, { useState, useEffect } from 'react';
import { useTodoStore } from '../../store/todoStore';
import { useUIStore } from '../../store/uiStore';
import './ActiveTimerBar.css';

export const ActiveTimerBar: React.FC = () => {
  const todos = useTodoStore((state) => state.todos);
  const categories = useTodoStore((state) => state.categories);
  const startTimer = useTodoStore((state) => state.startTimer);
  const stopTimer = useTodoStore((state) => state.stopTimer);
  const finishTodo = useTodoStore((state) => state.finishTodo);
  const openAnalytics = useUIStore((state) => state.openAnalytics);

  const runningTodo = todos.find((t) => t.sessions.some((s) => !s.stoppedAt));
  const pausedTodo = !runningTodo ? todos.find((t) => t.status === 'in-progress') : undefined;

  const activeTodo = runningTodo || pausedTodo;
  const runningSession = runningTodo?.sessions.find((s) => !s.stoppedAt);

  const [elapsedSeconds, setElapsedSeconds] = useState(0);

  useEffect(() => {
    if (!activeTodo) {
      setElapsedSeconds(0);
      return;
    }

    // Calculate total accumulated seconds across completed sessions
    const completedSeconds = (activeTodo.sessions || []).reduce((acc, s) => {
      if (s.startedAt && s.stoppedAt) {
        const diff = Math.max(0, Math.floor((new Date(s.stoppedAt).getTime() - new Date(s.startedAt).getTime()) / 1000));
        return acc + diff;
      }
      return acc;
    }, 0);

    if (!runningSession) {
      setElapsedSeconds(completedSeconds);
      return;
    }

    const startMs = new Date(runningSession.startedAt).getTime();
    const updateElapsed = () => {
      const liveCurrentMs = Math.max(0, Math.floor((Date.now() - startMs) / 1000));
      setElapsedSeconds(completedSeconds + liveCurrentMs);
    };

    updateElapsed();
    const interval = setInterval(updateElapsed, 1000);
    return () => clearInterval(interval);
  }, [activeTodo, runningSession]);

  if (!activeTodo) return null;

  const cat = categories.find((c) => c.id === activeTodo.categoryId);
  const isRunning = Boolean(runningSession);

  const formatTimer = (totalSec: number) => {
    const hrs = Math.floor(totalSec / 3600);
    const mins = Math.floor((totalSec % 3600) / 60);
    const secs = totalSec % 60;
    return `${String(hrs).padStart(2, '0')}:${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  };

  return (
    <div className={`toggl-active-timer-bar animate-fade-in ${!isRunning ? 'paused-mode' : ''}`}>
      <div className="timer-bar-left">
        <span className={`live-pulse-dot ${!isRunning ? 'paused' : ''}`} />
        <span className="timer-status-tag">
          {isRunning ? 'TOGGL TRACKING' : 'IN PROGRESS (PAUSED)'}
        </span>
        <span className="timer-task-title">{activeTodo.title}</span>
        {cat && (
          <span className="timer-cat-pill" style={{ backgroundColor: `${cat.color}22`, color: cat.color }}>
            {cat.icon} {cat.name}
          </span>
        )}
        {activeTodo.location && (
          <span className="timer-loc-pill">📍 {activeTodo.location}</span>
        )}
      </div>

      <div className="timer-bar-right">
        <div className="timer-clock-digits">{formatTimer(elapsedSeconds)}</div>

        {isRunning ? (
          <button
            className="stop-timer-btn warning-mode"
            onClick={() => stopTimer(activeTodo.id)}
            title="Pause Timer"
          >
            ⏸️ Pause
          </button>
        ) : (
          <button
            className="stop-timer-btn start-mode"
            onClick={() => startTimer(activeTodo.id)}
            title="Resume Timer"
            style={{ backgroundColor: '#7c6ff7', color: '#fff' }}
          >
            ▶️ Resume
          </button>
        )}

        <button
          className="stop-timer-btn done-mode"
          onClick={() => finishTodo(activeTodo.id)}
          title="Mark Task as Done"
          style={{ backgroundColor: '#3ecf8e', color: '#fff' }}
        >
          ✓ Done
        </button>

        <button
          className="btn-secondary btn-sm analytics-shortcut-btn"
          onClick={openAnalytics}
          title="Open Toggl Time Analytics Reports"
        >
          📊 Reports
        </button>
      </div>
    </div>
  );
};

