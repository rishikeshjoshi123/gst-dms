const fs = require('fs')
const path = require('path')

const file = path.join(__dirname, 'src/components/matters/MatterTabs.tsx')
let code = fs.readFileSync(file, 'utf8')

// reduce mt-6 to mt-4
code = code.replace(
  'className="flex flex-col h-[calc(100vh-280px)] mt-6 animate-fade-in"',
  'className="flex flex-col h-[calc(100vh-200px)] mt-4 animate-fade-in"'
)
code = code.replace(
  'className="flex flex-col h-[calc(100vh-280px)] mt-4 animate-fade-in"',
  'className="flex flex-col h-[calc(100vh-200px)] mt-4 animate-fade-in"'
)

fs.writeFileSync(file, code)
