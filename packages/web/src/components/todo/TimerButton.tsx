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

  const isRunning = todo.status === 'in-progress';
  const isDone = todo.status === 'done';

  if (isDone) return <span className="badge">Done</span>;

  return (
    <div className="timer-button-group" style={{ display: 'inline-flex', gap: '6px' }}>
      <button
        className={`btn ${isRunning ? 'btn-warning' : 'btn-primary'}`}
        onClick={() => (isRunning ? stopTimer(todo.id) : startTimer(todo.id))}
      >
        {isRunning ? 'Stop' : 'Start'}
      </button>
      <button className="btn btn-ghost" onClick={() => finishTodo(todo.id)}>
        Finish
      </button>
    </div>
  );
};
