// src/components/todo/CalendarView.tsx
import React from 'react';
import { useTodoStore } from '../../store/todoStore';
import type { TodoEntry } from '../../types';
import './CalendarView.css';

export const CalendarView: React.FC = () => {
  const schedule = useTodoStore((state) => state.pushedSchedule);
  const moveTodo = useTodoStore((state) => state.moveTodoOnCalendar);

  return (
    <div className="calendar-view glass fade-in">
      {Object.entries(schedule).map(([date, todos]) => (
        <div key={date} className="day-column" data-date={date}>
          <div className="day-header">{date}</div>
          <div className="day-todos">
            {todos.map((todo: TodoEntry) => (
              <div
                key={todo.id}
                className="draggable-todo glass"
                onClick={() => moveTodo(todo.id, date, todo.plannedStartTime)}
              >
                {todo.title}
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
};
