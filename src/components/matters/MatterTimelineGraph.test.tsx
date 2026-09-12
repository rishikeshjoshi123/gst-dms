import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { matterTimelineNodeAccessibleName } from './MatterTimelineGraphNode'
import type { MatterTimelineGraphNodeLayout } from '@/lib/matters/matter-timeline-graph-layout'

const canvas = readFileSync(new URL('./MatterTimelineGraphCanvas.tsx', import.meta.url), 'utf8')
const node = readFileSync(new URL('./MatterTimelineGraphNode.tsx', import.meta.url), 'utf8')
const reader = readFileSync(new URL('../../lib/matters/workspace-read.ts', import.meta.url), 'utf8')

const layout: MatterTimelineGraphNodeLayout = {
  id: 'reply', position: { x: 10, y: 20 }, width: 184, height: 120, unlinked: true,
  document: {
    id: 'reply', title: 'Reply to notice', documentType: 'Reply', referenceNumber: 'R/42',
    effectiveDate: null, direction: 'outgoing', classificationState: 'canonical',
    contentAvailability: 'metadata_only', attentionState: 'review', revision: 'revision-1',
  },
}

test('graph nodes have complete accessible names and honest missing-source state', () => {
  assert.equal(
    matterTimelineNodeAccessibleName(layout),
    'Reply to notice, Reply, R/42, Date unavailable, outgoing document, Needs review, PDF not attached, Unlinked proceeding',
  )
  assert.match(node, /style=\{\{ width: data\.layout\.width, height: data\.layout\.height \}\}/)
  assert.match(node, /ariaLabel=\{matterTimelineNodeAccessibleName\(data\.layout\)\}/)
  assert.match(node, /isConnectable=\{false\}/)
  assert.doesNotMatch(node, /onConnect|Re-evaluate|delete|gradient|#[0-9a-f]/i)
})

test('graph controls and list alternative use semantic tokens and 44px targets', () => {
  for (const control of ['Fit timeline', 'Zoom in', 'Zoom out', 'Relationship list', 'Chronology']) {
    assert.match(canvas, new RegExp(control))
  }
  assert.match(canvas, /min-h-11/)
  assert.match(canvas, /aria-label="Timeline relationships"/)
  assert.match(canvas, /BackgroundVariant\.Dots/)
  assert.match(canvas, /color="var\(--border-subtle\)"/)
  assert.match(canvas, /gap=\{24\}/)
  assert.match(canvas, /deleteKeyCode=\{null\}/)
  assert.doesNotMatch(canvas, /#[0-9a-f]{3,8}|linear-gradient|MiniMap|animated:/i)
})

test('graph reader composes only secured projections and fails closed at 250', () => {
  const start = reader.indexOf('export async function readMatterTimelineGraph')
  const body = reader.slice(start, reader.indexOf('/** Files reads', start))
  assert.match(body, /readMatterTimelineChronology/)
  assert.match(body, /readMatterTimelineRelationships\(matterId, null\)/)
  assert.match(body, /first\.total > 250/)
  assert.match(body, /page\.sourceRevision !== first\.sourceRevision/)
  assert.doesNotMatch(body, /\.from\(|document_links|document_relationship_candidates|raw_metadata/)
})
