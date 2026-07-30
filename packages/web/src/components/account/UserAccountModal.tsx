// src/components/account/UserAccountModal.tsx
import React, { useState } from 'react';
import { useUIStore } from '../../store/uiStore';
import { useTodoStore } from '../../store/todoStore';
import './UserAccountModal.css';

export const UserAccountModal: React.FC = () => {
  const isOpen = useUIStore((state) => state.isAccountModalOpen);
  const closeAccountModal = useUIStore((state) => state.closeAccountModal);
  const userAccount = useTodoStore((state) => state.userAccount);
  const availableAccounts = useTodoStore((state) => state.availableAccounts);
  const switchAccount = useTodoStore((state) => state.switchAccount);
  const createAndSwitchAccount = useTodoStore((state) => state.createAndSwitchAccount);

  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [showAddForm, setShowAddForm] = useState(false);

  if (!isOpen) return null;

  const handleCreateAccount = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim() || !email.trim()) return;
    createAndSwitchAccount(name.trim(), email.trim());
    setName('');
    setEmail('');
    setShowAddForm(false);
  };

  return (
    <div className="account-overlay animate-fade-in" onClick={closeAccountModal}>
      <div className="account-dialog glass-panel" onClick={(e) => e.stopPropagation()}>
        <div className="account-dialog-header">
          <div className="header-title-group">
            <h3>👤 User Account Management</h3>
            <span className="header-subtitle">Switch accounts, get new accounts & manage cloud sync</span>
          </div>
          <button className="account-close-btn" onClick={closeAccountModal} title="Close Account Modal">
            ✕
          </button>
        </div>

        <div className="account-dialog-body">
          {/* Active Account Profile Card */}
          <div className="active-account-card">
            <div className="active-account-avatar">
              {userAccount.avatarUrl ? (
                <img src={userAccount.avatarUrl} alt={userAccount.name} />
              ) : (
                <span>{userAccount.name.charAt(0).toUpperCase()}</span>
              )}
            </div>

            <div className="active-account-info">
              <div className="info-name-row">
                <span className="info-name">{userAccount.name}</span>
                <span className={`tier-badge ${userAccount.tier.toLowerCase()}`}>
                  👑 {userAccount.tier} Plan
                </span>
              </div>
              <span className="info-email">✉️ {userAccount.email}</span>
              <div className="info-status-row">
                <span className="status-chip cloud-synced">☁️ Cloud Synced</span>
                <span className="status-chip workspaces">📁 {userAccount.workspacesCount} Workspaces</span>
              </div>
            </div>
          </div>

          {/* Switch Account Section */}
          <div className="account-section">
            <div className="section-header-row">
              <h4 className="section-heading">🔄 Switch Accounts</h4>
              <button
                className="btn-secondary btn-sm"
                onClick={() => setShowAddForm(!showAddForm)}
              >
                {showAddForm ? 'Cancel' : '➕ Get / Add Account'}
              </button>
            </div>

            {showAddForm && (
              <form onSubmit={handleCreateAccount} className="add-account-form animate-fade-in">
                <h5>➕ Create & Get New Account</h5>
                <input
                  type="text"
                  placeholder="Full Name (e.g. Tony Stark)"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  required
                />
                <input
                  type="email"
                  placeholder="Email address (e.g. tony@stark.com)"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
                <button type="submit" className="btn-primary btn-sm">
                  Sign In & Get Account
                </button>
              </form>
            )}

            <div className="accounts-list">
              {availableAccounts.map((acc) => {
                const isActive = acc.id === userAccount.id;

                return (
                  <div
                    key={acc.id}
                    className={`account-list-item ${isActive ? 'active' : ''}`}
                    onClick={() => switchAccount(acc.id)}
                  >
                    <div className="item-left">
                      <div className="item-avatar">
                        {acc.avatarUrl ? <img src={acc.avatarUrl} alt={acc.name} /> : <span>{acc.name.charAt(0)}</span>}
                      </div>
                      <div className="item-details">
                        <span className="item-name">{acc.name}</span>
                        <span className="item-email">{acc.email}</span>
                      </div>
                    </div>

                    <div className="item-right">
                      {isActive ? (
                        <span className="active-chip">Active</span>
                      ) : (
                        <button className="btn-secondary btn-sm">Switch</button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        <div className="account-dialog-footer">
          <button className="btn-primary" onClick={closeAccountModal}>
            Done
          </button>
        </div>
      </div>
    </div>
  );
};
