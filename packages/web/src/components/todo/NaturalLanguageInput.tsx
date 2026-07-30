// src/components/todo/NaturalLanguageInput.tsx
import React, { useState } from 'react';
import { useTodoStore } from '../../store/todoStore';
import type { PriorityLevel } from '../../types';
import './NaturalLanguageInput.css';

export const NaturalLanguageInput: React.FC<{ defaultDateIso?: string }> = ({ defaultDateIso }) => {
  const addTodo = useTodoStore((state) => state.addTodo);
  const categories = useTodoStore((state) => state.categories);
  const [rawInput, setRawInput] = useState('');

  const parseSmartInput = (input: string) => {
    let text = input;
    const today = defaultDateIso || new Date().toISOString().split('T')[0];

    // Priority parsing: !urgent, !high, !med, !low, p1, p2, p3, p4
    let priority: PriorityLevel = 'medium';
    if (/\b(!urgent|p1)\b/i.test(text)) {
      priority = 'urgent';
      text = text.replace(/\b(!urgent|p1)\b/gi, '');
    } else if (/\b(!high|p2)\b/i.test(text)) {
      priority = 'high';
      text = text.replace(/\b(!high|p2)\b/gi, '');
    } else if (/\b(!med|!medium|p3)\b/i.test(text)) {
      priority = 'medium';
      text = text.replace(/\b(!med|!medium|p3)\b/gi, '');
    } else if (/\b(!low|p4)\b/i.test(text)) {
      priority = 'low';
      text = text.replace(/\b(!low|p4)\b/gi, '');
    }

    // Location parsing: @Location Name
    let location: string | undefined = undefined;
    const locMatch = text.match(/@([a-zA-Z0-9\s_-]+?)(?=\s+#|\s+!|\s+p\d|\s+\d+m|\s*$)/);
    if (locMatch) {
      location = locMatch[1].trim();
      text = text.replace(locMatch[0], '');
    }

    // Label parsing: #label
    const labels: string[] = [];
    const labelMatches = text.matchAll(/#([a-zA-Z0-9_-]+)/g);
    for (const match of labelMatches) {
      labels.push(match[1]);
    }
    text = text.replace(/#([a-zA-Z0-9_-]+)/g, '');

    // Duration parsing: 30m, 1h, 45m
    let duration = 30;
    const durMatch = text.match(/\b(\d+)(m|h)\b/i);
    if (durMatch) {
      const val = parseInt(durMatch[1], 10);
      duration = durMatch[2].toLowerCase() === 'h' ? val * 60 : val;
      text = text.replace(durMatch[0], '');
    }

    // Time parsing: 7:30am, 14:00, 5pm
    let startTime = '09:00';
    const timeMatch = text.match(/\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b/i);
    if (timeMatch) {
      let h = parseInt(timeMatch[1], 10);
      const m = timeMatch[2] ? parseInt(timeMatch[2], 10) : 0;
      const period = timeMatch[3]?.toLowerCase();
      if (period === 'pm' && h < 12) h += 12;
      if (period === 'am' && h === 12) h = 0;
      startTime = `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
      text = text.replace(timeMatch[0], '');
    }

    // Clean up title text
    const title = text.replace(/\s+/g, ' ').trim() || 'New Task';

    return {
      title,
      doDate: today,
      dueDate: today,
      plannedStartTime: startTime,
      plannedDuration: duration,
      priority,
      location,
      labels,
      categoryId: categories[0]?.id || 'cat-work',
    };
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!rawInput.trim()) return;

    const parsed = parseSmartInput(rawInput);
    addTodo(parsed);
    setRawInput('');
  };

  return (
    <form onSubmit={handleSubmit} className="smart-input-container glass-panel">
      <div className="smart-input-wrapper">
        <span className="smart-input-icon" title="Todoist Smart Quick Add">⚡</span>
        <input
          type="text"
          className="smart-input-field"
          placeholder='Smart Quick Add: e.g. "Product sync tomorrow at 10am #work @HQ Office !high 45m"'
          value={rawInput}
          onChange={(e) => setRawInput(e.target.value)}
        />
        <button type="submit" className="btn-primary btn-sm smart-submit-btn">
          ➕ Quick Add
        </button>
      </div>
      <div className="smart-input-hints">
        <span>Hints: <strong>at 2pm</strong> (time) • <strong>#tag</strong> (labels) • <strong>@HQ Office</strong> (location) • <strong>!urgent / p1</strong> (priority) • <strong>45m / 1h</strong> (duration)</span>
      </div>
    </form>
  );
};
