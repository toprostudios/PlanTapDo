// src/components/views/TeamManagerView.tsx
import React, { useState } from 'react';
import { useUIStore } from '../../store/uiStore';
import { useTodoStore } from '../../store/todoStore';
import type { PriorityLevel } from '../../types';
import './TeamManagerView.css';

export const TeamManagerView: React.FC = () => {
  const openSettings = useUIStore((state) => state.openSettings);
  const teamMembers = useTodoStore((state) => state.teamMembers);
  const todos = useTodoStore((state) => state.todos);
  const categories = useTodoStore((state) => state.categories);
  const addTodo = useTodoStore((state) => state.addTodo);
  const assignTodoToMember = useTodoStore((state) => state.assignTodoToMember);
  const addTeamMember = useTodoStore((state) => state.addTeamMember);

  const [departmentFilter, setDepartmentFilter] = useState<string>('all');
  const [selectedMemberId, setSelectedMemberId] = useState<string | null>(null);

  // Quick Dispatch Form State
  const todayIso = new Date().toISOString().split('T')[0];
  const [dispatchTitle, setDispatchTitle] = useState('');
  const [dispatchMemberId, setDispatchMemberId] = useState(teamMembers[0]?.id || '');
  const [dispatchDuration, setDispatchDuration] = useState(45);
  const [dispatchStartTime, setDispatchStartTime] = useState('10:00');
  const [dispatchPriority, setDispatchPriority] = useState<PriorityLevel>('medium');
  const [dispatchLocation, setDispatchLocation] = useState('');

  // New Team Member Form State
  const [showAddMemberForm, setShowAddMemberForm] = useState(false);
  const [newMemberName, setNewMemberName] = useState('');
  const [newMemberRole, setNewMemberRole] = useState('');
  const [newMemberDept, setNewMemberDept] = useState('Engineering');

  const filteredMembers = teamMembers.filter((member) => {
    if (departmentFilter === 'all') return true;
    if (departmentFilter === 'active') return member.status === 'active';
    return member.department.toLowerCase() === departmentFilter.toLowerCase();
  });

  const getCategory = (catId: string) => categories.find((c) => c.id === catId);

  const handleDispatchTask = (e: React.FormEvent) => {
    e.preventDefault();
    if (!dispatchTitle.trim()) return;

    addTodo({
      title: dispatchTitle.trim(),
      categoryId: categories[0]?.id || 'cat-work',
      doDate: todayIso,
      dueDate: todayIso,
      plannedStartTime: dispatchStartTime,
      plannedDuration: Number(dispatchDuration) || 30,
      priority: dispatchPriority,
      location: dispatchLocation.trim() || undefined,
      assigneeId: dispatchMemberId || teamMembers[0]?.id,
    });

    setDispatchTitle('');
    setDispatchLocation('');
    alert(`✅ Task dispatched to ${teamMembers.find((m) => m.id === dispatchMemberId)?.name || 'Team Member'}!`);
  };

  const handleAddTeamMember = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newMemberName.trim()) return;
    addTeamMember({
      name: newMemberName.trim(),
      role: newMemberRole.trim() || 'Team Specialist',
      department: newMemberDept,
      avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=150&q=80',
      status: 'active',
      capacityMinutes: 480,
    });
    setNewMemberName('');
    setNewMemberRole('');
    setShowAddMemberForm(false);
  };

  return (
    <div className="view-page-container animate-fade-in">
      {/* Header Bar with Settings Button */}
      <div className="view-header-bar">
        <div className="view-title-group">
          <h2 className="view-main-title">👥 Team & Manager Workspace View</h2>
          <span className="view-subtitle">
            View multiple team members at once, inspect current in-progress tasks & lined up schedules
          </span>
        </div>

        <div className="view-header-right">
          <button
            className="btn-secondary btn-sm"
            onClick={() => setShowAddMemberForm(!showAddMemberForm)}
          >
            {showAddMemberForm ? 'Cancel' : '➕ Add Team Member'}
          </button>
          <button className="categories-settings-btn btn-primary" onClick={openSettings}>
            ⚙️ Settings
          </button>
        </div>
      </div>

      {showAddMemberForm && (
        <form onSubmit={handleAddTeamMember} className="add-member-form glass-panel animate-fade-in">
          <h4>➕ Add New Team Member</h4>
          <div className="form-grid-3">
            <input
              type="text"
              placeholder="Member Name (e.g. Alex Rivera)"
              value={newMemberName}
              onChange={(e) => setNewMemberName(e.target.value)}
              required
            />
            <input
              type="text"
              placeholder="Role Title (e.g. QA Automation Eng 🧪)"
              value={newMemberRole}
              onChange={(e) => setNewMemberRole(e.target.value)}
              required
            />
            <select value={newMemberDept} onChange={(e) => setNewMemberDept(e.target.value)}>
              <option value="Engineering">Engineering Department</option>
              <option value="Design">Design Department</option>
              <option value="Product">Product Department</option>
              <option value="Infrastructure">Infrastructure Department</option>
            </select>
          </div>
          <button type="submit" className="btn-primary btn-sm">Save Member</button>
        </form>
      )}

      {/* Manager Dispatcher Bar */}
      <div className="manager-dispatcher-card glass-panel">
        <div className="dispatcher-header">
          <h4>⚡ Manager Quick Task Dispatcher</h4>
          <span className="dispatcher-hint">Assign a new task directly to a team member's schedule</span>
        </div>
        <form onSubmit={handleDispatchTask} className="dispatcher-form">
          <input
            type="text"
            className="dispatch-input-title"
            placeholder="Task Title (e.g. Review UI mocks & deploy sprint branch)..."
            value={dispatchTitle}
            onChange={(e) => setDispatchTitle(e.target.value)}
            required
          />

          <select value={dispatchMemberId} onChange={(e) => setDispatchMemberId(e.target.value)}>
            {teamMembers.map((m) => (
              <option key={m.id} value={m.id}>
                👤 {m.name} ({m.role})
              </option>
            ))}
          </select>

          <select value={dispatchPriority} onChange={(e) => setDispatchPriority(e.target.value as PriorityLevel)}>
            <option value="low">🟢 Low Priority</option>
            <option value="medium">🔹 Medium Priority</option>
            <option value="high">⚡ High Priority</option>
            <option value="urgent">🔥 Urgent</option>
          </select>

          <input
            type="time"
            value={dispatchStartTime}
            onChange={(e) => setDispatchStartTime(e.target.value)}
          />

          <select value={dispatchDuration} onChange={(e) => setDispatchDuration(Number(e.target.value))}>
            <option value={15}>15m</option>
            <option value={30}>30m</option>
            <option value={45}>45m</option>
            <option value={60}>60m</option>
            <option value={90}>90m</option>
          </select>

          <button type="submit" className="btn-primary btn-sm dispatch-btn">
            ⚡ Dispatch Task
          </button>
        </form>
      </div>

      {/* Filter Tabs */}
      <div className="team-filter-bar">
        <span className="filter-label">Filter Team:</span>
        <button
          className={`filter-pill ${departmentFilter === 'all' ? 'active' : ''}`}
          onClick={() => setDepartmentFilter('all')}
        >
          All Members ({teamMembers.length})
        </button>
        <button
          className={`filter-pill ${departmentFilter === 'active' ? 'active' : ''}`}
          onClick={() => setDepartmentFilter('active')}
        >
          🔴 Active Now ({teamMembers.filter((m) => m.status === 'active').length})
        </button>
        <button
          className={`filter-pill ${departmentFilter === 'engineering' ? 'active' : ''}`}
          onClick={() => setDepartmentFilter('engineering')}
        >
          💻 Engineering
        </button>
        <button
          className={`filter-pill ${departmentFilter === 'design' ? 'active' : ''}`}
          onClick={() => setDepartmentFilter('design')}
        >
          🎨 Design
        </button>
        <button
          className={`filter-pill ${departmentFilter === 'product' ? 'active' : ''}`}
          onClick={() => setDepartmentFilter('product')}
        >
          📊 Product
        </button>
      </div>

      {/* Multi-Person Side-by-Side Team Matrix View */}
      <div className="team-matrix-grid">
        {filteredMembers.map((member) => {
          // Member's assigned todos
          const memberTodos = todos.filter((t) => t.assigneeId === member.id || (!t.assigneeId && member.id === 'tm-1'));

          // Current Task (In Progress)
          const currentTask = memberTodos.find((t) => t.status === 'in-progress');

          // Lined up tasks (Pending / Scheduled)
          const linedUpTasks = memberTodos
            .filter((t) => t.status === 'todo')
            .sort((a, b) => (a.plannedStartTime || '23:59').localeCompare(b.plannedStartTime || '23:59'));

          // Workload calculation
          const totalPlannedMin = memberTodos.reduce((acc, t) => acc + t.plannedDuration, 0);
          const workloadPct = Math.min(100, Math.round((totalPlannedMin / member.capacityMinutes) * 100));

          return (
            <div
              key={member.id}
              className={`team-member-card glass-panel ${selectedMemberId === member.id ? 'focused' : ''}`}
              onClick={() => setSelectedMemberId(member.id)}
            >
              {/* Member Card Header */}
              <div className="member-card-header">
                <div className="member-avatar-box">
                  <img src={member.avatarUrl} alt={member.name} />
                  <span className={`status-indicator-dot ${member.status}`} />
                </div>

                <div className="member-name-group">
                  <h3 className="member-name">{member.name}</h3>
                  <span className="member-role">{member.role}</span>
                </div>

                <span className="dept-badge">{member.department}</span>
              </div>

              {/* Workload Progress Bar */}
              <div className="workload-section">
                <div className="workload-row-label">
                  <span>Workload Capacity</span>
                  <span>{totalPlannedMin}m / {member.capacityMinutes}m ({workloadPct}%)</span>
                </div>
                <div className="workload-track">
                  <div
                    className="workload-fill"
                    style={{
                      width: `${workloadPct}%`,
                      backgroundColor: workloadPct > 85 ? '#f43f5e' : workloadPct > 60 ? '#f5a623' : '#3ecf8e',
                    }}
                  />
                </div>
              </div>

              {/* Current Task (In Progress) Box */}
              <div className="current-task-box">
                <div className="box-heading">
                  <span className="live-pulsing-badge">🔴 ACTIVE NOW</span>
                  <span className="box-title-label">Current Task</span>
                </div>

                {currentTask ? (
                  <div className="task-detail-highlight" style={{ borderLeftColor: getCategory(currentTask.categoryId)?.color || '#7c6ff7' }}>
                    <span className="task-h-title">{currentTask.title}</span>
                    <div className="task-h-meta">
                      <span>⏰ Started: {currentTask.plannedStartTime || '09:00'} ({currentTask.plannedDuration}m)</span>
                      {currentTask.location && <span className="loc-tag">📍 {currentTask.location}</span>}
                    </div>
                  </div>
                ) : (
                  <div className="task-empty-placeholder">
                    <span>No active task running</span>
                  </div>
                )}
              </div>

              {/* Lined Up Tasks List */}
              <div className="lined-up-section">
                <div className="box-heading">
                  <span>📋 LINED UP TASKS ({linedUpTasks.length})</span>
                </div>

                <div className="lined-up-stack">
                  {linedUpTasks.map((task) => {
                    const cat = getCategory(task.categoryId);

                    return (
                      <div key={task.id} className="lined-up-item-card" style={{ borderLeftColor: cat?.color }}>
                        <div className="item-title-row">
                          <span className="item-title">{task.title}</span>
                          {cat && <span className="item-cat-icon">{cat.icon}</span>}
                        </div>
                        <div className="item-sub-meta">
                          <span>⏰ {task.plannedStartTime || '09:00'} ({task.plannedDuration}m)</span>
                          {task.location && <span>📍 {task.location}</span>}
                          <select
                            className="reassign-select"
                            value={task.assigneeId || member.id}
                            onClick={(e) => e.stopPropagation()}
                            onChange={(e) => assignTodoToMember(task.id, e.target.value)}
                            title="Re-assign task"
                          >
                            {teamMembers.map((m) => (
                              <option key={m.id} value={m.id}>
                                ➡️ {m.name}
                              </option>
                            ))}
                          </select>
                        </div>
                      </div>
                    );
                  })}

                  {linedUpTasks.length === 0 && (
                    <div className="task-empty-placeholder">
                      <span>No lined up tasks</span>
                    </div>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
