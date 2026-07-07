const fs = require('fs')
const path = require('path')

const file = path.join(__dirname, 'src/lib/ai/vertex.ts')
let code = fs.readFileSync(file, 'utf8')

const searchStr = `4. Normalize dates to YYYY-MM-DD or standard readable format if possible.`
const replaceStr = `4. Normalize dates to YYYY-MM-DD or standard readable format if possible.
5. IMPORTANT: Translate all extracted text into English. If the document is in a regional language (e.g. Hindi, Gujarati), translate the summary, description, and events into English.
6. IMPORTANT: For named entities like Client Name, Company Name, Person Names, or Addresses, use TRANSLITERATION into English script rather than translation (e.g., use "Rajesh Enterprises" instead of "King Enterprises").`

code = code.replace(searchStr, replaceStr)
fs.writeFileSync(file, code)
console.log('patched vertex')
