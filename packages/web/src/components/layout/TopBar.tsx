// src/components/layout/TopBar.tsx
import React from 'react';
import { useTodoStore } from '../../store/todoStore';
import { useUIStore } from '../../store/uiStore';
import './TopBar.css';

export const TopBar: React.FC = () => {
  const activeTab = useUIStore((state) => state.activeTab);
  const setActiveTab = useUIStore((state) => state.setActiveTab);
  const openSettings = useUIStore((state) => state.openSettings);
  const refreshTodos = useTodoStore((state) => state.refreshTodos);

  return (
    <header className="top-bar">
      <div className="left-section">
        <span className="app-title">🕒 PlanTapDo</span>
      </div>
      <div className="right-section">
        <div className="view-toggle">
          <button
            className={`pill ${activeTab === 'today' ? 'active' : ''}`}
            onClick={() => setActiveTab('today')}
          >
            Today
          </button>
          <button
            className={`pill ${activeTab === 'future' ? 'active' : ''}`}
            onClick={() => setActiveTab('future')}
          >
            Future
          </button>
          <button
            className={`pill ${activeTab === 'categories' ? 'active' : ''}`}
            onClick={() => setActiveTab('categories')}
          >
            Categories
          </button>
        </div>
        <button className="btn btn-primary" onClick={() => refreshTodos()}>
          ↻ Refresh
        </button>
        <button className="btn btn-primary" onClick={openSettings}>
          ⚙️ Settings
        </button>
      </div>
    </header>
  );
};
