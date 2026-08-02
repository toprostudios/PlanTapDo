// src/components/layout/Sidebar.tsx
import React from 'react';
import { useUIStore } from '../../store/uiStore';
import { useTodoStore } from '../../store/todoStore';
import type { Category } from '../../types';
import './Sidebar.css';

export const Sidebar: React.FC = () => {
  const activeTab = useUIStore((state) => state.activeTab);
  const setActiveTab = useUIStore((state) => state.setActiveTab);
  const categories = useTodoStore((state) => state.categories);

  return (
    <aside className="sidebar">
      <div className="logo-area" style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
        <img src="/logo.png" alt="PlanTapDo Logo" style={{ height: '32px', width: '32px', borderRadius: '8px', objectFit: 'contain' }} />
        <h1 className="logo" style={{ fontSize: '1.2rem', margin: 0 }}>PlanTapDo</h1>
      </div>

      <nav className="nav-links">
        <button
          className={`nav-btn ${activeTab === 'today' ? 'active' : ''}`}
          onClick={() => setActiveTab('today')}
        >
          📌 Today
        </button>
        <button
          className={`nav-btn ${activeTab === 'future' ? 'active' : ''}`}
          onClick={() => setActiveTab('future')}
        >
          🗓️ Future
        </button>
        <button
          className={`nav-btn ${activeTab === 'categories' ? 'active' : ''}`}
          onClick={() => setActiveTab('categories')}
        >
          🏷️ Categories
        </button>
      </nav>
      <section className="category-section">
        <h2 className="section-title">Categories</h2>
        <ul className="category-list">
          {categories.map((cat: Category) => (
            <li key={cat.id} className="category-item">
              <span
                className="color-dot"
                style={{ backgroundColor: cat.color }}
              />
              <span className="cat-name">{cat.name}</span>
            </li>
          ))}
        </ul>
      </section>
    </aside>
  );
};
