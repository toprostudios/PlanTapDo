// src/components/analytics/TimeAnalyticsModal.tsx
import React from 'react';
import { useUIStore } from '../../store/uiStore';
import { useTodoStore } from '../../store/todoStore';
import './TimeAnalyticsModal.css';

export const TimeAnalyticsModal: React.FC = () => {
  const isOpen = useUIStore((state) => state.isAnalyticsModalOpen);
  const closeAnalytics = useUIStore((state) => state.closeAnalytics);
  const todos = useTodoStore((state) => state.todos);
  const categories = useTodoStore((state) => state.categories);

  if (!isOpen) return null;

  // Calculate total tracked time in seconds per session across all todos
  let totalTrackedSeconds = 0;
  let totalPlannedMinutes = 0;

  const categoryTimeMap: Record<string, number> = {}; // catId -> seconds
  const locationTimeMap: Record<string, number> = {}; // location -> seconds

  todos.forEach((todo) => {
    totalPlannedMinutes += todo.plannedDuration;
    const catId = todo.categoryId;
    const loc = todo.location?.trim() || 'Unspecified';

    todo.sessions.forEach((s) => {
      const startMs = new Date(s.startedAt).getTime();
      const stopMs = s.stoppedAt ? new Date(s.stoppedAt).getTime() : Date.now();
      const durationSec = Math.max(0, Math.floor((stopMs - startMs) / 1000));

      totalTrackedSeconds += durationSec;
      categoryTimeMap[catId] = (categoryTimeMap[catId] || 0) + durationSec;
      locationTimeMap[loc] = (locationTimeMap[loc] || 0) + durationSec;
    });
  });

  const totalTrackedHours = (totalTrackedSeconds / 3600).toFixed(1);
  const totalPlannedHours = (totalPlannedMinutes / 60).toFixed(1);
  const efficiencyPct = totalPlannedMinutes > 0
    ? Math.min(100, Math.round(((totalTrackedSeconds / 60) / totalPlannedMinutes) * 100))
    : 0;

  const formatHoursStr = (sec: number) => {
    const h = (sec / 3600).toFixed(1);
    return `${h} hrs`;
  };

  return (
    <div className="analytics-overlay animate-fade-in" onClick={closeAnalytics}>
      <div className="analytics-dialog glass-panel" onClick={(e) => e.stopPropagation()}>
        <div className="analytics-dialog-header">
          <div className="header-title-group">
            <h3>📊 Toggl Track Time Analytics & Reports</h3>
            <span className="header-subtitle">Detailed time distribution by category, location & productivity ratio</span>
          </div>
          <button className="analytics-close-btn" onClick={closeAnalytics} title="Close Analytics">
            ✕
          </button>
        </div>

        <div className="analytics-dialog-body">
          {/* Top Key Metrics Cards */}
          <div className="metrics-cards-grid">
            <div className="metric-card">
              <span className="metric-icon">⏱️</span>
              <div className="metric-details">
                <span className="metric-value">{totalTrackedHours} hrs</span>
                <span className="metric-label">Total Tracked Time</span>
              </div>
            </div>

            <div className="metric-card">
              <span className="metric-icon">🎯</span>
              <div className="metric-details">
                <span className="metric-value">{totalPlannedHours} hrs</span>
                <span className="metric-label">Planned Time Budget</span>
              </div>
            </div>

            <div className="metric-card">
              <span className="metric-icon">📈</span>
              <div className="metric-details">
                <span className="metric-value">{efficiencyPct}%</span>
                <span className="metric-label">Efficiency Ratio</span>
              </div>
            </div>
          </div>

          {/* Time Distribution by Category */}
          <div className="analytics-section">
            <h4 className="section-heading">🏷️ Tracked Time by Category</h4>
            <div className="breakdown-bars-stack">
              {categories.map((cat) => {
                const sec = categoryTimeMap[cat.id] || 0;
                const pct = totalTrackedSeconds > 0 ? Math.round((sec / totalTrackedSeconds) * 100) : 0;

                return (
                  <div key={cat.id} className="breakdown-row">
                    <div className="breakdown-row-label">
                      <span>{cat.icon} {cat.name}</span>
                      <span className="breakdown-row-val">{formatHoursStr(sec)} ({pct}%)</span>
                    </div>
                    <div className="progress-track">
                      <div
                        className="progress-fill"
                        style={{ width: `${pct}%`, backgroundColor: cat.color }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Time Distribution by Location */}
          <div className="analytics-section">
            <h4 className="section-heading">📍 Tracked Time by Location</h4>
            <div className="breakdown-bars-stack">
              {Object.entries(locationTimeMap).map(([locName, sec]) => {
                const pct = totalTrackedSeconds > 0 ? Math.round((sec / totalTrackedSeconds) * 100) : 0;

                return (
                  <div key={locName} className="breakdown-row">
                    <div className="breakdown-row-label">
                      <span>📍 {locName}</span>
                      <span className="breakdown-row-val">{formatHoursStr(sec)} ({pct}%)</span>
                    </div>
                    <div className="progress-track">
                      <div
                        className="progress-fill"
                        style={{ width: `${pct}%`, backgroundColor: '#3ecf8e' }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        <div className="analytics-dialog-footer">
          <button className="btn-primary" onClick={closeAnalytics}>
            Close Reports
          </button>
        </div>
      </div>
    </div>
  );
};
