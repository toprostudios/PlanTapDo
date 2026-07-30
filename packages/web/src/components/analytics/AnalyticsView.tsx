// src/components/analytics/AnalyticsView.tsx
import React from 'react';
import { Line } from 'react-chartjs-2';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
} from 'chart.js';

// Register required Chart.js components
ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend
);

/**
 * Premium Analytics view – displays a simple line chart of dummy usage data.
 * In a real app this would be fed from the Amplitude analytics service.
 */
export const AnalyticsView: React.FC = () => {
  // Dummy dataset – replace with real API data later
  const data = {
    labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    datasets: [
      {
        label: 'Active Sessions',
        data: [3, 5, 2, 8, 4, 6, 7],
        fill: true,
        backgroundColor: 'rgba(124, 111, 247, 0.2)', // accent with opacity
        borderColor: 'rgba(124, 111, 247, 1)',
        tension: 0.3,
      },
    ],
  };

  const options = {
    responsive: true,
    plugins: {
      legend: {
        position: 'top' as const,
        labels: { color: 'white' },
      },
      title: {
        display: true,
        text: 'Weekly Activity Overview',
        color: 'white',
        font: { size: 18 },
      },
    },
    scales: {
      x: { ticks: { color: 'white' }, grid: { color: 'rgba(255,255,255,0.1)' } },
      y: { ticks: { color: 'white' }, grid: { color: 'rgba(255,255,255,0.1)' } },
    },
  };

  return (
    <section className="analytics-view glass fade-in" style={{ padding: 'var(--spacing-lg)' }}>
      <Line data={data} options={options} />
    </section>
  );
};
