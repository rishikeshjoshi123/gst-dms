import assert from 'node:assert/strict'
import test from 'node:test'

import {
  filterTasks,
  isTaskId,
  isTaskWorkspaceTab,
  mentionedUserIdsInBody,
  notesOriginHref,
  primaryTaskCommand,
  taskDetailReadState,
  taskDetailsHref,
  taskHref,
} from './task-model'
import type { TaskDetail, TaskListItem } from '@/lib/actions/tasks'

function task(overrides: Partial<TaskListItem> = {}): TaskListItem {
  return {
    task_id: '00000000-0000-4000-8000-000000000001',
    client_id: '00000000-0000-4000-8000-000000000002',
    matter_id: '00000000-0000-4000-8000-000000000003',
    document_id: null,
    title: 'Verify invoice set',
    priority: 'normal',
    status: 'open',
    assignee_user_id: null,
    due_date: null,
    due_time: null,
    due_timezone: null,
    revision: 1,
    created_at: '2026-09-01T00:00:00Z',
    updated_at: '2026-09-01T00:00:00Z',
    origin_available: true,
    ...overrides,
  }
}

test('active and assignment filters use current Task projection fields', () => {
  const currentUserId = '00000000-0000-4000-8000-000000000009'
  const tasks = [
    task({ assignee_user_id: currentUserId }),
    task({ task_id: '00000000-0000-4000-8000-000000000011', status: 'completed', assignee_user_id: currentUserId }),
    task({ task_id: '00000000-0000-4000-8000-000000000012', status: 'in_progress' }),
  ]

  assert.deepEqual(filterTasks(tasks, {
    query: '', status: 'active', assignment: 'mine', currentUserId, labels: ['', '', ''],
  }).map((item) => item.task_id), [tasks[0].task_id])
})

test('Task and Notes deep links encode opaque identifiers', () => {
  assert.equal(taskDetailsHref('task id'), '/tasks?task=task%20id&tab=details')
  assert.equal(taskHref('task id', 'comments'), '/tasks?task=task%20id&tab=comments')
  assert.equal(notesOriginHref('note/id'), '/notes?note=note%2Fid')
  assert.equal(isTaskId('00000000-0000-4000-8000-000000000001'), true)
  assert.equal(isTaskId('forged-task-id'), false)
})

test('Task tabs and selected mentions remain explicit URL and recipient state', () => {
  assert.equal(isTaskWorkspaceTab('details'), true)
  assert.equal(isTaskWorkspaceTab('comments'), true)
  assert.equal(isTaskWorkspaceTab('history'), false)
  assert.deepEqual(mentionedUserIdsInBody('Please check @Meera Shah and @Meera Shah.', [
    { id: 'meera', label: 'Meera Shah' },
    { id: 'ananya', label: 'Ananya Kapoor' },
    { id: 'meera', label: 'Meera Shah' },
  ]), ['meera'])
  assert.deepEqual(mentionedUserIdsInBody('The label was removed.', [
    { id: 'meera', label: 'Meera Shah' },
  ]), [])
})

test('only supported current-state commands are offered as primary actions', () => {
  assert.equal(primaryTaskCommand('open')?.command, 'start')
  assert.equal(primaryTaskCommand('in_progress')?.command, 'complete')
  assert.equal(primaryTaskCommand('completed')?.command, 'reopen')
  assert.equal(primaryTaskCommand('suspended'), null)
})

test('reader failures remain distinct from valid empty and inaccessible results', () => {
  const detail = task() as unknown as TaskDetail
  assert.equal(taskDetailReadState({ selectedId: null, detail: null, loading: false, readerError: false }), 'idle')
  assert.equal(taskDetailReadState({ selectedId: detail.task_id, detail: null, loading: false, readerError: false }), 'unavailable')
  assert.equal(taskDetailReadState({ selectedId: detail.task_id, detail: null, loading: false, readerError: true }), 'error')
  assert.equal(taskDetailReadState({ selectedId: detail.task_id, detail, loading: false, readerError: false }), 'ready')
  assert.equal(taskDetailReadState({ selectedId: detail.task_id, detail: null, loading: true, readerError: true }), 'loading')
})
