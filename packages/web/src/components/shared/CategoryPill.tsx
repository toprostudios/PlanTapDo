// src/components/shared/CategoryPill.tsx
import React from 'react';
import { useTodoStore } from '../../store/todoStore';
import './CategoryPill.css';

/**
 * Small pill showing the category color and name.
 * Props:
 *   - categoryId: the id of the category to display
 *   - size?: 'sm' | 'md' (default 'sm')
 */
export const CategoryPill: React.FC<{ categoryId: string; size?: 'sm' | 'md' }> = ({ categoryId, size = 'sm' }) => {
  const category = useTodoStore(state => state.categories.find(c => c.id === categoryId));
  if (!category) return null;
  return (
    <span className={`category-pill ${size}`} style={{ backgroundColor: category.color }}>
      {category.name}
    </span>
  );
};
