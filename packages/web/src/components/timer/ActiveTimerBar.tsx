// src/components/timer/ActiveTimerBar.tsx
import React, { useState, useEffect } from 'react';
import { useTodoStore } from '../../store/todoStore';
import { useUIStore } from '../../store/uiStore';
import './ActiveTimerBar.css';

export const ActiveTimerBar: React.FC = () => {
  const todos = useTodoStore((state) => state.todos);
  const categories = useTodoStore((state) => state.categories);
  const stopTimer = useTodoStore((state) => state.stopTimer);
  const openAnalytics = useUIStore((state) => state.openAnalytics);

  const activeTodo = todos.find((t) => t.status === 'in-progress');
  const runningSession = activeTodo?.sessions.find((s) => !s.stoppedAt);

  const [elapsedSeconds, setElapsedSeconds] = useState(0);

  useEffect(() => {
    if (!runningSession) {
      setElapsedSeconds(0);
      return;
    }

    const startMs = new Date(runningSession.startedAt).getTime();
    const updateElapsed = () => {
      const nowMs = Date.now();
      setElapsedSeconds(Math.max(0, Math.floor((nowMs - startMs) / 1000)));
    };

    updateElapsed();
    const interval = setInterval(updateElapsed, 1000);
    return () => clearInterval(interval);
  }, [runningSession]);

  if (!activeTodo || !runningSession) return null;

  const cat = categories.find((c) => c.id === activeTodo.categoryId);

  const formatTimer = (totalSec: number) => {
    const hrs = Math.floor(totalSec / 3600);
    const mins = Math.floor((totalSec % 3600) / 60);
    const secs = totalSec % 60;
    return `${String(hrs).padStart(2, '0')}:${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  };

  return (
    <div className="toggl-active-timer-bar animate-fade-in">
      <div className="timer-bar-left">
        <span className="live-pulse-dot" />
        <span className="timer-status-tag">TOGGL TRACKING</span>
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
        <button
          className="btn-secondary btn-sm analytics-shortcut-btn"
          onClick={openAnalytics}
          title="Open Toggl Time Analytics Reports"
        >
          📊 Reports
        </button>
        <button
          className="stop-timer-btn"
          onClick={() => stopTimer(activeTodo.id)}
          title="Stop Time Tracking"
        >
          ⏹️ Stop Timer
        </button>
      </div>
    </div>
  );
};
