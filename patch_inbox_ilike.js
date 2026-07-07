const fs = require('fs')
const path = require('path')

const file = path.join(__dirname, 'src/lib/actions/inbox.ts')
let code = fs.readFileSync(file, 'utf8')

const searchStr = `.eq('name', metadata.client_name)`
const replaceStr = `.ilike('name', \`%\${metadata.client_name}%\`)`

code = code.replace(searchStr, replaceStr)
fs.writeFileSync(file, code)
console.log('patched')
