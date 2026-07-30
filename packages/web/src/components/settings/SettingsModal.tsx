// src/components/settings/SettingsModal.tsx
import React, { useState } from 'react';
import { useUIStore } from '../../store/uiStore';
import { useTodoStore } from '../../store/todoStore';
import type { AppTheme } from '../../store/uiStore';
import './SettingsModal.css';

export const SettingsModal: React.FC = () => {
  const isOpen = useUIStore((state) => state.isSettingsModalOpen);
  const closeSettings = useUIStore((state) => state.closeSettings);
  const theme = useUIStore((state) => state.theme);
  const setTheme = useUIStore((state) => state.setTheme);
  const resetToSampleData = useTodoStore((state) => state.resetToSampleData);
  const locationTravelTimes = useTodoStore((state) => state.locationTravelTimes) || {};
  const setTravelTimeBetweenLocations = useTodoStore((state) => state.setTravelTimeBetweenLocations);

  const [locA, setLocA] = useState('');
  const [locB, setLocB] = useState('');
  const [transitMin, setTransitMin] = useState(20);

  if (!isOpen) return null;

  const themes: { id: AppTheme; title: string; desc: string; icon: string }[] = [
    { id: 'dark', title: 'Dark Glass', desc: 'Modern sleek dark palette with high-contrast text', icon: '🌙' },
    { id: 'light', title: 'Crisp Light', desc: 'Clean bright layout with vivid accents', icon: '☀️' },
    { id: 'high-contrast', title: 'High Contrast', desc: 'Ultra-visible bold neon theme for maximum accessibility', icon: '⚡' },
  ];

  const handleSaveTravelTime = (e: React.FormEvent) => {
    e.preventDefault();
    if (!locA.trim() || !locB.trim()) return;
    setTravelTimeBetweenLocations(locA.trim(), locB.trim(), Number(transitMin) || 15);
    setLocA('');
    setLocB('');
  };

  return (
    <div className="settings-overlay animate-fade-in" onClick={closeSettings}>
      <div className="settings-dialog glass-panel" onClick={(e) => e.stopPropagation()}>
        <div className="settings-dialog-header">
          <h3>⚙️ Application Settings</h3>
          <button className="settings-close-btn" onClick={closeSettings} title="Close Settings">
            ✕
          </button>
        </div>

        <div className="settings-dialog-body">
          {/* Theme Selection */}
          <div className="settings-section">
            <h4 className="section-heading">🎨 Color Theme & Readability</h4>
            <div className="theme-options-grid">
              {themes.map((t) => (
                <div
                  key={t.id}
                  className={`theme-option-card ${theme === t.id ? 'active' : ''}`}
                  onClick={() => setTheme(t.id)}
                >
                  <div className="theme-card-header">
                    <span className="theme-icon">{t.icon}</span>
                    <span className="theme-title">{t.title}</span>
                  </div>
                  <p className="theme-desc">{t.desc}</p>
                </div>
              ))}
            </div>
          </div>

          {/* Location Travel Times Memory Manager */}
          <div className="settings-section">
            <h4 className="section-heading">🚗 Location Travel Times Memory</h4>
            <p className="section-text">
              Set remembered travel times between any 2 locations. When scheduling tasks at different locations, the calendar automatically calculates transit buffers using these saved times!
            </p>

            <form onSubmit={handleSaveTravelTime} className="travel-time-form">
              <div className="form-row-3">
                <input
                  type="text"
                  placeholder="Location A (e.g. HQ Office)"
                  value={locA}
                  onChange={(e) => setLocA(e.target.value)}
                  required
                />
                <input
                  type="text"
                  placeholder="Location B (e.g. Gym)"
                  value={locB}
                  onChange={(e) => setLocB(e.target.value)}
                  required
                />
                <input
                  type="number"
                  min={5}
                  max={180}
                  value={transitMin}
                  onChange={(e) => setTransitMin(Number(e.target.value))}
                  style={{ width: '90px' }}
                  title="Travel time in minutes"
                  required
                />
                <button type="submit" className="btn-primary btn-sm">
                  Save Transit Time
                </button>
              </div>
            </form>

            <div className="saved-travel-times-list">
              {Object.entries(locationTravelTimes).map(([pairKey, duration]) => {
                const [a, b] = pairKey.split('|');
                return (
                  <div key={pairKey} className="saved-travel-time-chip">
                    <span>🚗 {a} ➔ {b}: <strong>{duration} min</strong></span>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Sample Data & Storage */}
          <div className="settings-section">
            <h4 className="section-heading">💾 Demo & Sample Data</h4>
            <p className="section-text">
              Want to see sample tasks, calendar blocks, and categories? You can reload sample data anytime.
            </p>
            <button
              className="btn-secondary"
              onClick={() => {
                resetToSampleData();
                alert('Sample tasks and categories reloaded successfully!');
              }}
            >
              🔄 Reset / Reload Sample Tasks
            </button>
          </div>
        </div>

        <div className="settings-dialog-footer">
          <button className="btn-primary" onClick={closeSettings}>
            Done
          </button>
        </div>
      </div>
    </div>
  );
};
