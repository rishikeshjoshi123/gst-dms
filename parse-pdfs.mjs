import fs from 'fs';
import path from 'path';

// Using a basic import to see if pdf-parse is there
try {
  const pdf = await import('pdf-parse');
  
  const baseDir = '/Users/rishikeshjoshi/Downloads/Testing Litigation Docments/Aica Laminates India';
  const dirs = fs.readdirSync(baseDir).filter(f => fs.statSync(path.join(baseDir, f)).isDirectory());
  
  // Pick one typical directory
  const sampleDir = dirs.find(d => d.startsWith('ZD0502250015026'));
  if (sampleDir) {
    const dirPath = path.join(baseDir, sampleDir);
    const files = fs.readdirSync(dirPath).filter(f => f.endsWith('.pdf'));
    
    console.log(`Analyzing files in ${sampleDir}:`);
    for (const file of files) {
      const dataBuffer = fs.readFileSync(path.join(dirPath, file));
      const data = await pdf.default(dataBuffer);
      console.log(`\n========================================`);
      console.log(`FILE: ${file}`);
      console.log(`PAGES: ${data.numpages}`);
      console.log(`CONTENT PREVIEW (first 500 chars):\n${data.text.substring(0, 500).trim()}`);
      
      // Look for specific references
      const matchZD = data.text.match(/ZD[A-Z0-9]+/g);
      if (matchZD) console.log(`Found references: ${[...new Set(matchZD)].join(', ')}`);
    }
  }
} catch (e) {
  console.error("No pdf-parse", e);
}
