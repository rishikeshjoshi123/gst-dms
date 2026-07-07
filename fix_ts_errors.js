const fs = require('fs')
const path = require('path')

// 1. Fix inbox.ts
const inboxFile = path.join(__dirname, 'src/lib/actions/inbox.ts')
let inboxCode = fs.readFileSync(inboxFile, 'utf8')

// Fix the status filter in reevaluateStagedDocuments
inboxCode = inboxCode.replace(
  ".eq('status', 'needs_review')",
  ".eq('status', 'ready_to_assign')"
)

// Fix the chaining attributes type
inboxCode = inboxCode.replace(
  'if (!aiResult.chaining_attributes) {',
  'if (!aiResult.chaining_attributes) {'
)
inboxCode = inboxCode.replace(
  'aiResult.chaining_attributes = {};',
  'aiResult.chaining_attributes = {} as any;'
)

fs.writeFileSync(inboxFile, inboxCode)

// 2. Fix chaining.ts
const chainingFile = path.join(__dirname, 'src/lib/actions/chaining.ts')
let chainingCode = fs.readFileSync(chainingFile, 'utf8')

chainingCode = chainingCode.replace(
  'if (!aiResult.chaining_attributes) aiResult.chaining_attributes = {}',
  'if (!aiResult.chaining_attributes) aiResult.chaining_attributes = {} as any'
)

fs.writeFileSync(chainingFile, chainingCode)

