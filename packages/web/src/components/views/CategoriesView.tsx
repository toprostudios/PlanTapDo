// src/components/views/CategoriesView.tsx
import React, { useState } from 'react';
import { useTodoStore } from '../../store/todoStore';
import type { PriorityLevel } from '../../types';
import './CategoriesView.css';

const COLOR_SWATCHES = [
  '#7c6ff7', // Purple
  '#3ecf8e', // Emerald Green
  '#f5a623', // Amber
  '#60a5fa', // Sky Blue
  '#ec4899', // Pink
  '#f43f5e', // Coral Red
  '#eab308', // Yellow
  '#14b8a6', // Teal
];

export const CategoriesView: React.FC = () => {
  const categories = useTodoStore((state) => state.categories);
  const addCategory = useTodoStore((state) => state.addCategory);
  const updateCategoryNotes = useTodoStore((state) => state.updateCategoryNotes);
  const deleteCategory = useTodoStore((state) => state.deleteCategory);
  const addTodo = useTodoStore((state) => state.addTodo);
  const todos = useTodoStore((state) => state.todos);

  // Active selected category for Notion-type document view
  const [selectedCatId, setSelectedCatId] = useState<string>(categories[0]?.id || 'cat-work');

  // Selected category object
  const activeCat = categories.find((c) => c.id === selectedCatId) || categories[0];

  // Mode: 'notion' (Notion Document Text View) vs 'add-task' (Task Entry Form)
  const [activeSubTab, setActiveSubTab] = useState<'notion' | 'add-task'>('notion');

  // Task creation state
  const todayIso = new Date().toISOString().split('T')[0];
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [doDate, setDoDate] = useState(todayIso);
  const [dueDate, setDueDate] = useState(todayIso);
  const [dueTime, setDueTime] = useState('18:00');
  const [descriptiveDeadline, setDescriptiveDeadline] = useState('');
  const [plannedDuration, setPlannedDuration] = useState(30);
  const [plannedStartTime, setPlannedStartTime] = useState('09:00');
  const [priority, setPriority] = useState<PriorityLevel>('medium');
  const [location, setLocation] = useState('');
  const [reminder, setReminder] = useState('15 minutes before');
  const [labelsStr, setLabelsStr] = useState('');

  // Category creation state
  const [newCatName, setNewCatName] = useState('');
  const [newCatColor, setNewCatColor] = useState('#7c6ff7');
  const [newCatIcon, setNewCatIcon] = useState('🔖');
  const [showCatForm, setShowCatForm] = useState(false);

  // Success message feedback
  const [successMsg, setSuccessMsg] = useState('');

  const handleNotesChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    if (activeCat) {
      updateCategoryNotes(activeCat.id, e.target.value);
    }
  };

  const insertNotionBlock = (blockPrefix: string) => {
    if (!activeCat) return;
    const currentNotes = activeCat.notes || '';
    const updatedNotes = currentNotes ? `${currentNotes}\n${blockPrefix}` : blockPrefix;
    updateCategoryNotes(activeCat.id, updatedNotes);
  };

  const handleCreateTodo = (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;

    const labels = labelsStr
      .split(',')
      .map((l) => l.trim().replace(/^#/, ''))
      .filter(Boolean);

    addTodo({
      title: title.trim(),
      description: description.trim(),
      categoryId: activeCat?.id || 'cat-work',
      doDate,
      dueDate,
      dueTime,
      descriptiveDeadline: descriptiveDeadline.trim() || undefined,
      plannedDuration: Number(plannedDuration) || 30,
      plannedStartTime,
      priority,
      location: location.trim() || undefined,
      reminder: reminder.trim() || undefined,
      labels,
    });

    // Reset form
    setTitle('');
    setDescription('');
    setDescriptiveDeadline('');
    setLocation('');
    setLabelsStr('');
    setSuccessMsg('✅ Task created successfully!');
    setTimeout(() => setSuccessMsg(''), 3000);
  };

  const handleCreateCategory = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newCatName.trim()) return;
    addCategory({
      name: newCatName.trim(),
      color: newCatColor,
      icon: newCatIcon || '🏷️',
    });
    setNewCatName('');
    setShowCatForm(false);
  };

  return (
    <div className="view-page-container animate-fade-in">
      {/* Header Bar with Settings Button */}
      <div className="view-header-bar">
        <div className="view-title-group">
          <h2 className="view-main-title">🏷️ Categories & Notion Document Canvas</h2>
          <span className="view-subtitle">Customize category colors, icon badges, and Notion-style text views</span>
        </div>

      </div>

      <div className="categories-layout-grid">
        {/* Left Column: Category Manager */}
        <div className="categories-manager-card glass-panel">
          <div className="card-header">
            <h3>Categories List</h3>
            <button
              className="btn-secondary btn-sm"
              onClick={() => setShowCatForm(!showCatForm)}
            >
              {showCatForm ? 'Cancel' : '➕ Add Category'}
            </button>
          </div>

          {showCatForm && (
            <form onSubmit={handleCreateCategory} className="add-cat-form">
              <input
                type="text"
                placeholder="Category Name..."
                value={newCatName}
                onChange={(e) => setNewCatName(e.target.value)}
                required
              />

              <div className="color-swatch-row">
                <span className="form-sublabel">Category Color:</span>
                <div className="swatches-grid">
                  {COLOR_SWATCHES.map((swatch) => (
                    <button
                      key={swatch}
                      type="button"
                      className={`swatch-btn ${newCatColor === swatch ? 'active' : ''}`}
                      style={{ backgroundColor: swatch }}
                      onClick={() => setNewCatColor(swatch)}
                      title={`Select color ${swatch}`}
                    />
                  ))}
                  <input
                    type="color"
                    className="custom-color-input"
                    value={newCatColor}
                    onChange={(e) => setNewCatColor(e.target.value)}
                    title="Custom color picker"
                  />
                </div>
              </div>

              <div className="cat-form-row">
                <input
                  type="text"
                  placeholder="Emoji (e.g. 🎯)"
                  value={newCatIcon}
                  onChange={(e) => setNewCatIcon(e.target.value)}
                  maxLength={2}
                  style={{ width: '80px' }}
                />
                <button type="submit" className="btn-primary btn-sm">Save Category</button>
              </div>
            </form>
          )}

          <div className="category-items-list">
            {categories.map((cat) => {
              const count = todos.filter((t) => t.categoryId === cat.id).length;
              const isSelected = activeCat?.id === cat.id;

              return (
                <div
                  key={cat.id}
                  className={`category-badge-card ${isSelected ? 'selected-active' : ''}`}
                  onClick={() => setSelectedCatId(cat.id)}
                  style={{
                    borderLeftColor: cat.color,
                    boxShadow: isSelected ? `0 0 12px ${cat.color}66` : undefined,
                  }}
                >
                  <div className="cat-badge-left">
                    <span className="cat-badge-dot" style={{ backgroundColor: cat.color }} />
                    <span className="cat-badge-icon">{cat.icon}</span>
                    <span className="cat-badge-name">{cat.name}</span>
                  </div>
                  <div className="cat-badge-right">
                    <span className="cat-badge-count" style={{ borderColor: `${cat.color}66`, color: cat.color }}>
                      {count} tasks
                    </span>
                    {categories.length > 1 && (
                      <button
                        className="cat-delete-btn"
                        onClick={(e) => {
                          e.stopPropagation();
                          deleteCategory(cat.id);
                        }}
                        title="Delete Category"
                      >
                        🗑️
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Right Column: Notion-Type Text Document View & Task Entry Switcher */}
        <div className="category-detail-panel glass-panel">
          {/* Sub-tab Navigation */}
          <div className="panel-subtab-header">
            <div className="subtab-pills">
              <button
                className={`subtab-btn ${activeSubTab === 'notion' ? 'active' : ''}`}
                onClick={() => setActiveSubTab('notion')}
              >
                📝 Notion Document Canvas
              </button>
              <button
                className={`subtab-btn ${activeSubTab === 'add-task' ? 'active' : ''}`}
                onClick={() => setActiveSubTab('add-task')}
              >
                ➕ Create Task in {activeCat?.name}
              </button>
            </div>
          </div>

          {activeSubTab === 'notion' && activeCat && (
            <div className="notion-editor-container animate-fade-in">
              {/* Notion Cover Header styled with category custom color */}
              <div
                className="notion-cover-banner"
                style={{ background: `linear-gradient(135deg, ${activeCat.color}44, var(--bg-surface-elevated))` }}
              >
                <div className="notion-icon-badge" style={{ borderColor: activeCat.color, color: activeCat.color }}>
                  {activeCat.icon || '📝'}
                </div>
              </div>

              <div className="notion-page-header">
                <h1 className="notion-page-title" style={{ color: activeCat.color }}>
                  {activeCat.icon} {activeCat.name} Document
                </h1>
                <span className="notion-page-meta">Autosaved Notion-type text view • Type markdown, notes & checklists</span>
              </div>

              {/* Notion Slash Command Toolbar */}
              <div className="notion-toolbar">
                <span className="toolbar-label">Quick Blocks:</span>
                <button type="button" onClick={() => insertNotionBlock('# ')} className="notion-tool-btn">H1</button>
                <button type="button" onClick={() => insertNotionBlock('## ')} className="notion-tool-btn">H2</button>
                <button type="button" onClick={() => insertNotionBlock('- [ ] ')} className="notion-tool-btn">☑️ Task</button>
                <button type="button" onClick={() => insertNotionBlock('- ')} className="notion-tool-btn">• Bullet</button>
                <button type="button" onClick={() => insertNotionBlock('> ')} className="notion-tool-btn">💬 Quote</button>
                <button type="button" onClick={() => insertNotionBlock('```\n\n```')} className="notion-tool-btn">💻 Code</button>
              </div>

              {/* Notion Text Editor Canvas */}
              <div className="notion-editor-body">
                <textarea
                  className="notion-textarea"
                  placeholder="Type '/' for commands or start writing notes, project specs, checklists..."
                  value={activeCat.notes || ''}
                  onChange={handleNotesChange}
                />
              </div>
            </div>
          )}

          {activeSubTab === 'add-task' && (
            <div className="task-entry-card-content animate-fade-in">
              <div className="card-header">
                <h3>➕ Create Task for {activeCat?.name}</h3>
                <span className="form-hint">Set scheduled date, descriptive deadlines, location, priority & reminders</span>
              </div>

              {successMsg && <div className="form-success-banner">{successMsg}</div>}

              <form onSubmit={handleCreateTodo} className="task-creation-form">
                <div className="form-group">
                  <label htmlFor="task-title">Task Title *</label>
                  <input
                    id="task-title"
                    type="text"
                    placeholder="e.g. Quarterly Roadmap Sync"
                    value={title}
                    onChange={(e) => setTitle(e.target.value)}
                    required
                  />
                </div>

                <div className="form-group">
                  <label htmlFor="task-desc">Description (Optional)</label>
                  <textarea
                    id="task-desc"
                    placeholder="Add notes, context, or links..."
                    value={description}
                    onChange={(e) => setDescription(e.target.value)}
                    rows={2}
                  />
                </div>

                <div className="form-grid-row">
                  <div className="form-group">
                    <label htmlFor="do-date">Scheduled Date (Do Date)</label>
                    <input
                      id="do-date"
                      type="date"
                      value={doDate}
                      onChange={(e) => setDoDate(e.target.value)}
                      required
                    />
                  </div>

                  <div className="form-group">
                    <label htmlFor="start-time">Planned Start Time</label>
                    <input
                      id="start-time"
                      type="time"
                      value={plannedStartTime}
                      onChange={(e) => setPlannedStartTime(e.target.value)}
                      required
                    />
                  </div>
                </div>

                <div className="form-grid-row">
                  <div className="form-group">
                    <label htmlFor="due-date">Deadline Date</label>
                    <input
                      id="due-date"
                      type="date"
                      value={dueDate}
                      onChange={(e) => setDueDate(e.target.value)}
                    />
                  </div>

                  <div className="form-group">
                    <label htmlFor="due-time">Deadline Time</label>
                    <input
                      id="due-time"
                      type="time"
                      value={dueTime}
                      onChange={(e) => setDueTime(e.target.value)}
                    />
                  </div>
                </div>

                <div className="form-grid-row">
                  <div className="form-group">
                    <label htmlFor="descriptive-deadline">Descriptive Deadline (No effect on calendar position)</label>
                    <input
                      id="descriptive-deadline"
                      type="text"
                      placeholder="e.g. Before client sync / By EOD"
                      value={descriptiveDeadline}
                      onChange={(e) => setDescriptiveDeadline(e.target.value)}
                    />
                  </div>

                  <div className="form-group">
                    <label htmlFor="priority-level">Priority Level</label>
                    <select
                      id="priority-level"
                      value={priority}
                      onChange={(e) => setPriority(e.target.value as PriorityLevel)}
                    >
                      <option value="low">🟢 Low Priority</option>
                      <option value="medium">🔹 Medium Priority</option>
                      <option value="high">⚡ High Priority</option>
                      <option value="urgent">🔥 Urgent Priority</option>
                    </select>
                  </div>
                </div>

                <div className="form-grid-row">
                  <div className="form-group">
                    <label htmlFor="task-location">Location (Auto-adds transit time between different locations)</label>
                    <input
                      id="task-location"
                      type="text"
                      placeholder="e.g. HQ Office, Gym, Home"
                      value={location}
                      onChange={(e) => setLocation(e.target.value)}
                    />
                  </div>

                  <div className="form-group">
                    <label htmlFor="task-reminder">Reminder</label>
                    <select
                      id="task-reminder"
                      value={reminder}
                      onChange={(e) => setReminder(e.target.value)}
                    >
                      <option value="5 minutes before">5 minutes before</option>
                      <option value="15 minutes before">15 minutes before</option>
                      <option value="30 minutes before">30 minutes before</option>
                      <option value="1 hour before">1 hour before</option>
                    </select>
                  </div>
                </div>

                <div className="form-group">
                  <label htmlFor="task-labels">Labels / Tags (Comma separated)</label>
                  <input
                    id="task-labels"
                    type="text"
                    placeholder="e.g. roadmap, product, review"
                    value={labelsStr}
                    onChange={(e) => setLabelsStr(e.target.value)}
                  />
                </div>

                <div className="form-group">
                  <label>Duration (Minutes)</label>
                  <div className="duration-quick-presets">
                    {[15, 30, 45, 60, 90, 120].map((dur) => (
                      <button
                        key={dur}
                        type="button"
                        className={`duration-preset-btn ${plannedDuration === dur ? 'active' : ''}`}
                        onClick={() => setPlannedDuration(dur)}
                      >
                        {dur >= 60 ? `${dur / 60}h` : `${dur}m`}
                      </button>
                    ))}
                    <input
                      type="number"
                      min={5}
                      max={480}
                      value={plannedDuration}
                      onChange={(e) => setPlannedDuration(Number(e.target.value))}
                      style={{ width: '90px' }}
                      placeholder="Min"
                    />
                  </div>
                </div>

                <button type="submit" className="btn-primary create-submit-btn" style={{ backgroundColor: activeCat?.color }}>
                  ➕ Create Task
                </button>
              </form>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
