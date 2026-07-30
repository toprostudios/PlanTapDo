// src/components/layout/AppShell.tsx
import React from 'react';
import { Navbar } from './Navbar';
import { SettingsModal } from '../settings/SettingsModal';
import { UserAccountModal } from '../account/UserAccountModal';
import './AppShell.css';

export const AppShell: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  return (
    <div className="app-shell-root">
      <Navbar />
      <main className="app-main-viewport">{children}</main>
      <SettingsModal />
      <UserAccountModal />
    </div>
  );
};

export default AppShell;
