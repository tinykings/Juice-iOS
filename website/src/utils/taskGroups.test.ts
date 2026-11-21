import { describe, expect, it } from 'vitest';
import { Task } from '@/types/task';
import { buildTaskGroups, getTaskDateLabel } from './taskGroups';

const now = new Date(2026, 2, 10, 9, 30);

function task(id: string, dueDate: string, title = id): Task {
  return {
    id,
    title,
    notes: '',
    dueDate,
    completed: false,
    completedAt: null,
    createdAt: '2026-03-01T12:00:00.000Z',
    pinned: false,
    isRecurring: false,
    recurrenceType: null,
    tags: [],
  };
}

const ids = (tasks: Task[]) => tasks.map(t => t.id);

describe('buildTaskGroups', () => {
  it('puts only tasks dated before today in Overdue, oldest first', () => {
    const groups = buildTaskGroups(
      [task('older', '2026-03-05'), task('yesterday', '2026-03-09'), task('today', '2026-03-10')],
      [task('undated', '')],
      now
    );

    const overdue = groups.find(g => g.isOverdue);
    expect(ids(overdue!.tasks)).toEqual(['older', 'yesterday']);
    expect(groups.flatMap(g => (g.isOverdue ? [] : g.tasks)).map(t => t.id)).toContain('undated');
  });

  it('has no Overdue group when only undated tasks are open', () => {
    const groups = buildTaskGroups([], [task('undated', '')], now);

    expect(groups.some(g => g.isOverdue)).toBe(false);
    expect(ids(groups.find(g => g.isFuture)!.tasks)).toEqual(['undated']);
  });

  it('orders Overdue, Today, Future, Tomorrow and later days, then months', () => {
    const groups = buildTaskGroups(
      [task('late', '2026-03-01'), task('later', '2026-05-02'), task('soon', '2026-03-11')],
      [task('undated', '')],
      now
    );

    expect(groups.map(g => g.label)).toEqual([
      'Overdue',
      'Today',
      'Future',
      'Tomorrow',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
      'Monday',
      'Tuesday',
      'May 2026',
    ]);
  });

  it('keeps Future between Today and Tomorrow even when empty', () => {
    const labels = buildTaskGroups([], [], now).map(g => g.label);

    expect(labels.slice(0, 3)).toEqual(['Today', 'Future', 'Tomorrow']);
  });

  it('marks Today and Future for the UI, and Future has no date to add to', () => {
    const groups = buildTaskGroups([], [], now);

    expect(groups.find(g => g.label === 'Today')).toMatchObject({ isToday: true });
    const future = groups.find(g => g.label === 'Future')!;
    expect(future.isFuture).toBe(true);
    expect(future.date).toBeUndefined();
    expect(future.isOverdue).toBeFalsy();
  });

  it('sorts Future by time, then title', () => {
    const groups = buildTaskGroups(
      [],
      [task('b', '', 'Bravo'), task('a', '', 'Alpha'), task('timed', '', 'Zulu @8am')],
      now
    );

    expect(ids(groups.find(g => g.isFuture)!.tasks)).toEqual(['timed', 'a', 'b']);
  });
});

describe('getTaskDateLabel', () => {
  it('shows no date label for undated tasks in Future', () => {
    const future = buildTaskGroups([], [task('undated', '')], now).find(g => g.isFuture)!;

    expect(getTaskDateLabel(future.tasks[0], future, now)).toBeUndefined();
  });

  it('shows the date for overdue tasks', () => {
    const overdue = buildTaskGroups([task('late', '2026-03-01')], [], now).find(g => g.isOverdue)!;

    expect(getTaskDateLabel(overdue.tasks[0], overdue, now)).toBe('Mar 1');
  });
});
