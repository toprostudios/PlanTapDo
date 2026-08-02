// src/App.tsx
import { useEffect } from 'react';
import { useUIStore } from './store/uiStore';
import { useTodoStore } from './store/todoStore';
import { AppShell } from './components/layout/AppShell';
import { TodayView } from './components/views/TodayView';
import { FutureView } from './components/views/FutureView';
import { CategoriesView } from './components/views/CategoriesView';
import { TeamManagerView } from './components/views/TeamManagerView';
import { ActiveTimerBar } from './components/timer/ActiveTimerBar';
import { TimeAnalyticsModal } from './components/analytics/TimeAnalyticsModal';

export function App() {
  const activeTab = useUIStore((state) => state.activeTab);
  const theme = useUIStore((state) => state.theme);
  const refreshTodos = useTodoStore((state) => state.refreshTodos);

  useEffect(() => {
    // Set theme attribute on document root
    document.documentElement.setAttribute('data-theme', theme);
    // Refresh todos or load initial state
    refreshTodos();

    // Support URL hash routing (#preview, #today, #future, #categories, #team)
    const handleHashChange = () => {
      const hash = window.location.hash.replace('#', '').toLowerCase();
      if (hash === 'today' || hash === 'future' || hash === 'categories' || hash === 'team') {
        useUIStore.getState().setActiveTab(hash);
      } else if (hash === 'preview') {
        // #preview routes directly to today view
        useUIStore.getState().setActiveTab('today');
      }
    };

    handleHashChange();
    window.addEventListener('hashchange', handleHashChange);
    return () => window.removeEventListener('hashchange', handleHashChange);
  }, [theme, refreshTodos]);

  return (
    <AppShell>
      <ActiveTimerBar />
      {activeTab === 'today' && <TodayView />}
      {activeTab === 'future' && <FutureView />}
      {activeTab === 'categories' && <CategoriesView />}
      {activeTab === 'team' && <TeamManagerView />}
      <TimeAnalyticsModal />
    </AppShell>
  );
}

export default App;
