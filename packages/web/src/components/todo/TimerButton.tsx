// src/components/todo/TimerButton.tsx
import React from 'react';
import { useTodoStore } from '../../store/todoStore';
import type { TodoEntry } from '../../types';

interface TimerButtonProps {
  todo: TodoEntry;
}

export const TimerButton: React.FC<TimerButtonProps> = ({ todo }) => {
  const startTimer = useTodoStore((state) => state.startTimer);
  const stopTimer = useTodoStore((state) => state.stopTimer);
  const finishTodo = useTodoStore((state) => state.finishTodo);

  const isRunning = todo.sessions.some((s) => !s.stoppedAt);
  const isInProgress = todo.status === 'in-progress';
  const isDone = todo.status === 'done';

  if (isDone) {
    return <span className="badge badge-success">✓ Done</span>;
  }

  return (
    <div className="timer-button-group" style={{ display: 'inline-flex', gap: '6px', alignItems: 'center' }}>
      {isRunning ? (
        <button
          className="btn btn-warning btn-sm"
          onClick={() => stopTimer(todo.id)}
          title="Pause timer"
        >
          ⏸ Pause
        </button>
      ) : (
        <button
          className="btn btn-primary btn-sm"
          onClick={() => startTimer(todo.id)}
          title={isInProgress ? 'Resume timer' : 'Start timer'}
        >
          ▶ {isInProgress ? 'Resume' : 'Start'}
        </button>
      )}

      <button
        className="btn btn-ghost btn-sm"
        onClick={() => finishTodo(todo.id)}
        title="Mark task as complete"
        style={{ color: 'var(--accent-emerald, #3ecf8e)' }}
      >
        ✓ Done
      </button>
    </div>
  );
};

