// src/store/uiStore.ts
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';

export type MainTab = 'today' | 'future' | 'categories' | 'team';
export type DisplayStyle = 'list' | 'calendar';
export type AppTheme = 'dark' | 'light' | 'high-contrast';

interface UIState {
  activeTab: MainTab;
  displayStyle: DisplayStyle;
  selectedFutureDate: string; // YYYY-MM-DD
  currentWeekOffset: number; // 0 = current week, 1 = next week, etc.
  theme: AppTheme;
  isSettingsModalOpen: boolean;
  isAnalyticsModalOpen: boolean;
  isAccountModalOpen: boolean;
  editingTodoId?: string;

  // Actions
  setActiveTab: (tab: MainTab) => void;
  setDisplayStyle: (style: DisplayStyle) => void;
  setSelectedFutureDate: (date: string) => void;
  setCurrentWeekOffset: (offset: number | ((prev: number) => number)) => void;
  setTheme: (theme: AppTheme) => void;
  openSettings: () => void;
  closeSettings: () => void;
  openAnalytics: () => void;
  closeAnalytics: () => void;
  openAccountModal: () => void;
  closeAccountModal: () => void;
  setEditingTodoId: (id?: string) => void;

  // Legacy compatibility getters
  view: MainTab;
  setView: (tab: MainTab) => void;
}

const getTomorrowDate = () => {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  return d.toISOString().split('T')[0];
};

export const useUIStore = create<UIState>()(
  persist(
    (set, get) => ({
      activeTab: 'today',
      displayStyle: 'list',
      selectedFutureDate: getTomorrowDate(),
      currentWeekOffset: 0,
      theme: 'dark',
      isSettingsModalOpen: false,
      isAnalyticsModalOpen: false,
      isAccountModalOpen: false,
      editingTodoId: undefined,

      setActiveTab: (tab) => set({ activeTab: tab }),
      setDisplayStyle: (style) => set({ displayStyle: style }),
      setSelectedFutureDate: (date) => set({ selectedFutureDate: date }),
      setCurrentWeekOffset: (updater) =>
        set((state) => ({
          currentWeekOffset: typeof updater === 'function' ? updater(state.currentWeekOffset) : updater,
        })),
      setTheme: (theme) => {
        document.documentElement.setAttribute('data-theme', theme);
        set({ theme });
      },
      openSettings: () => set({ isSettingsModalOpen: true }),
      closeSettings: () => set({ isSettingsModalOpen: false }),
      openAnalytics: () => set({ isAnalyticsModalOpen: true }),
      closeAnalytics: () => set({ isAnalyticsModalOpen: false }),
      openAccountModal: () => set({ isAccountModalOpen: true }),
      closeAccountModal: () => set({ isAccountModalOpen: false }),
      setEditingTodoId: (id) => set({ editingTodoId: id }),

      get view() {
        return get().activeTab;
      },
      setView: (tab) => set({ activeTab: tab }),
    }),
    {
      name: 'timetodo-ui-v2',
      storage: createJSONStorage(() => localStorage),
    }
  )
);

export default useUIStore;
