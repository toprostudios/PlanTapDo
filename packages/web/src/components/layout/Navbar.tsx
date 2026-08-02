// src/components/layout/Navbar.tsx
import React from 'react';
import { useUIStore } from '../../store/uiStore';
import { useTodoStore } from '../../store/todoStore';
import type { MainTab } from '../../store/uiStore';
import './Navbar.css';

export const Navbar: React.FC = () => {
  const activeTab = useUIStore((state) => state.activeTab);
  const setActiveTab = useUIStore((state) => state.setActiveTab);
  const theme = useUIStore((state) => state.theme);
  const setTheme = useUIStore((state) => state.setTheme);
  const openSettings = useUIStore((state) => state.openSettings);
  const openAccountModal = useUIStore((state) => state.openAccountModal);
  const userAccount = useTodoStore((state) => state.userAccount);

  const tabs: { id: MainTab; label: string; icon: string }[] = [
    { id: 'today', label: 'Today', icon: '📌' },
    { id: 'future', label: 'Future', icon: '🗓️' },
    { id: 'categories', label: 'Categories', icon: '🏷️' },
    { id: 'team', label: 'Team', icon: '👥' },
  ];

  const cycleTheme = () => {
    if (theme === 'dark') setTheme('light');
    else if (theme === 'light') setTheme('high-contrast');
    else setTheme('dark');
  };

  const getThemeLabel = () => {
    if (theme === 'dark') return '🌙 Dark';
    if (theme === 'light') return '☀️ Light';
    return '⚡ High Contrast';
  };

  return (
    <>
      <header className="navbar-container">
          <div className="brand-logo">
            <img src="/logo.png" alt="PlanTapDo Logo" className="brand-logo-img" style={{ height: '32px', width: '32px', borderRadius: '8px', objectFit: 'contain' }} />
            <span className="brand-name">PlanTapDo</span>
          </div>


        <nav className="navbar-tabs desktop-only-tabs" aria-label="Main Navigation">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              className={`nav-tab-btn ${activeTab === tab.id ? 'active' : ''}`}
              onClick={() => setActiveTab(tab.id)}
            >
              <span className="tab-icon">{tab.icon}</span>
              <span className="tab-label">{tab.label}</span>
              {activeTab === tab.id && <div className="active-indicator" />}
            </button>
          ))}
        </nav>

        <div className="navbar-right">
          {/* User Account Profile Pill */}
          <button
            className="account-nav-pill-btn"
            onClick={openAccountModal}
            title="Manage & Switch User Accounts"
          >
            <span className="acc-nav-avatar">
              {userAccount?.avatarUrl ? (
                <img src={userAccount.avatarUrl} alt={userAccount.name} />
              ) : (
                <span>{userAccount?.name?.charAt(0) || '👤'}</span>
              )}
            </span>
            <span className="acc-nav-name">{userAccount?.name || 'Account'}</span>
            <span className="acc-nav-badge">👑 {userAccount?.tier || 'Pro'}</span>
          </button>

          <button
            className="theme-toggle-btn"
            onClick={cycleTheme}
            title="Switch theme (Dark / Light / High Contrast)"
            aria-label="Toggle theme"
          >
            <span className="theme-toggle-label">{getThemeLabel()}</span>
            <span className="theme-toggle-icon-only">
              {theme === 'dark' ? '🌙' : theme === 'light' ? '☀️' : '⚡'}
            </span>
          </button>

          <button
            className="settings-quick-btn"
            onClick={openSettings}
            title="Open Settings"
            aria-label="Open Settings"
          >
            <span className="settings-btn-label">⚙️ Settings</span>
            <span className="settings-btn-icon-only">⚙️</span>
          </button>
        </div>
      </header>

      {/* Mobile Bottom Navigation Bar for iPhone / Touch Devices */}
      <nav className="mobile-bottom-nav" aria-label="Mobile Navigation">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            className={`mobile-nav-btn ${activeTab === tab.id ? 'active' : ''}`}
            onClick={() => setActiveTab(tab.id)}
          >
            <span className="mobile-tab-icon">{tab.icon}</span>
            <span className="mobile-tab-label">{tab.label}</span>
          </button>
        ))}
      </nav>
    </>
  );
};
