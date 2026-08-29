import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { planVisualReferences, portalReadingOrder } from '../project-portal/plan-visual-references.mjs';
import { planArticles } from '../project-portal/plan-articles.mjs';
import { plainLanguagePlans } from '../project-portal/plain-language-plans.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const plansRoot = path.join(root, 'docs/plans');
const outputRoot = path.join(root, 'project-portal/dist');
const repositoryUrl = 'https://github.com/rishikeshjoshi123/gst-dms';
const sourceBranch = process.env.PORTAL_SOURCE_BRANCH ?? 'dev';

const escapeHtml = (value = '') => String(value)
  .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#039;');

const slugify = (value) => value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');

async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const entryPath = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(entryPath) : [entryPath];
  }));
  return files.flat();
}

function parsePlan(source, file) {
  const match = source.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) return null;
  const metadata = Object.fromEntries(match[1].split('\n').flatMap((line) => {
    const keyValue = line.match(/^([a-z_]+):\s*(.*)$/);
    return keyValue ? [[keyValue[1], keyValue[2].replace(/^['"]|['"]$/g, '')]] : [];
  }));
  const relativePath = path.relative(root, file).replaceAll(path.sep, '/');
  const section = match[2].match(/^## Summary\n\n([\s\S]*?)(?=\n## |$)/m)?.[1] ?? '';
  return {
    ...metadata,
    relativePath,
    slug: relativePath.replace(/^docs\/plans\//, '').replace(/\.md$/, '').replaceAll('/', '-'),
    domain: relativePath.split('/')[2] ?? 'other',
    summary: section.replace(/\n+/g, ' ').trim(),
    body: match[2].replace(/^\n?# .+\n\n/, ''),
  };
}

function renderInline(value) {
  return escapeHtml(value)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noreferrer">$1</a>')
    .replace(/(\*\*|__)(.+?)\1/g, '<strong>$2</strong>');
}

function renderSpecimen(specimenId) {
  const specimens = {
    'civic-ink-primitives': `<figure class="visual-reference"><figcaption><span class="visual-reference-label">Visual reference</span><strong>Civic Ink primitives</strong><span>Semantic tokens and approved component roles keep visual meaning consistent.</span></figcaption><div class="specimen-grid"><div class="token-swatch token-ink"><span>Ink</span><small>Navigation</small></div><div class="token-swatch token-paper"><span>Paper</span><small>Page surface</small></div><div class="token-swatch token-action"><span>Action</span><small>Primary intent</small></div><div class="token-swatch token-attention"><span>Attention</span><small>Review state</small></div></div><div class="specimen-actions" aria-label="Approved action hierarchy example"><span class="specimen-button specimen-button-primary">Primary action</span><span class="specimen-button specimen-button-secondary">Secondary</span><span class="specimen-button specimen-button-quiet">Quiet action</span></div></figure>`,
    'stable-workspace-chrome': `<figure class="visual-reference"><figcaption><span class="visual-reference-label">Visual reference</span><strong>Stable workspace chrome</strong><span>Identity and actions stay anchored while the document body scrolls.</span></figcaption><div class="workspace-specimen"><div class="workspace-specimen-header"><span><b>Apex Auto Components</b><small>MAT-2024-018 · FY 2023–24</small></span><span class="specimen-button specimen-button-primary">Add document</span></div><div class="workspace-specimen-body"><span>Independent scrolling content body</span><span class="specimen-badge">Active</span></div></div></figure>`,
    'matter-workspace-layout': `<figure class="visual-reference"><figcaption><span class="visual-reference-label">Approved layout</span><strong>Matter workspace</strong><span>Stable identity, section navigation, and an evidence-led timeline share one workspace.</span></figcaption><div class="workspace-specimen"><div class="workspace-specimen-header"><span><b>Apex Auto Components</b><small>MAT-2024-018 · Active matter</small></span><span class="specimen-button specimen-button-primary">Add document</span></div><div class="workspace-tabs"><b>Timeline</b><span>Files</span><span>Case Brief</span><span>Notes</span></div><div class="workspace-timeline"><span><i></i>Reply to SCN <small>14 Aug · Filing</small></span><span><i></i>Hearing notice <small>22 Aug · Upcoming</small></span></div></div></figure>`,
    'deadlines-financial-layout': `<figure class="visual-reference"><figcaption><span class="visual-reference-label">Approved layout</span><strong>Deadlines and financials</strong><span>Urgency, verification, and legal position stay explicit without implying legal calculations.</span></figcaption><div class="specimen-summary-grid"><div><small>Next deadline</small><b>Reply to SCN</b><span class="specimen-badge specimen-badge-warning">Setup required</span></div><div><small>Current verified demand</small><b>₹50,000</b><span class="specimen-badge">Source-backed</span></div></div></figure>`,
    'notes-brief-layout': `<figure class="visual-reference"><figcaption><span class="visual-reference-label">Approved layout</span><strong>Cited Case Brief</strong><span>Human-authored case context stays separate from evidence-backed suggestions and review.</span></figcaption><div class="brief-specimen"><div><small>Current posture</small><b>The demand is substantially reduced; a residual appeal remains active.</b><p>Verified source context stays attached to the exact document version.<sup>1</sup></p></div><span class="specimen-badge specimen-badge-warning">1 change to review</span></div></figure>`,
  };
  const specimen = specimens[specimenId];
  if (!specimen) throw new Error(`Unknown portal visual reference: ${specimenId}`);
  return specimen;
}

function renderArticle(plan) {
  const article = planArticles[plan.relativePath];
  if (!article) throw new Error(`Plan is missing its public article: ${plan.relativePath}`);
  const flow = `<figure class="article-flow" aria-labelledby="flow-caption"><figcaption id="flow-caption">${escapeHtml(article.flowCaption)}</figcaption><ol>${article.flow.map((step, index) => `<li><span>${index + 1}</span>${escapeHtml(step)}</li>`).join('')}</ol></figure>`;
  const supportingVisuals = (planVisualReferences[plan.relativePath] ?? []).map((reference) => renderSpecimen(reference.specimenId)).join('');
  const sections = article.sections.map((section, index) => `<section class="story-section" id="${slugify(section.heading)}"><h2>${escapeHtml(section.heading)}</h2>${section.paragraphs.map((paragraph) => `<p>${escapeHtml(paragraph)}</p>`).join('')}${index === 0 ? flow : ''}${index === 1 ? supportingVisuals : ''}</section>`).join('');
  const wordCount = [article.deck, article.intro, ...article.sections.flatMap((section) => [section.heading, ...section.paragraphs])].join(' ').trim().split(/\s+/).length;
  const toc = `<nav class="article-toc" aria-label="In this article"><span>In this article</span><ol>${article.sections.map((section) => `<li><a href="#${slugify(section.heading)}">${escapeHtml(section.heading)}</a></li>`).join('')}</ol></nav>`;
  return {
    html: `<div class="article-introduction"><p class="article-deck">${escapeHtml(article.deck)}</p><p>${escapeHtml(article.intro)}</p></div>${sections}`,
    readingMinutes: Math.max(1, Math.ceil(wordCount / 220)),
    toc,
    wordCount,
  };
}

// Kept for an opt-in canonical renderer if the portal later adds a technical
// edition alongside the editorial articles.
// eslint-disable-next-line @typescript-eslint/no-unused-vars
function renderMarkdown(markdown, visualReferences = []) {
  const lines = markdown.split('\n');
  const html = [];
  const renderedReferences = new Set();
  const headingIdCounts = new Map();
  let index = 0;
  const isTable = (line) => /^\|.*\|\s*$/.test(line);
  const tableCells = (line) => line.trim().slice(1, -1).split('|').map((cell) => renderInline(cell.trim()));

  while (index < lines.length) {
    const line = lines[index];
    if (!line.trim()) { index += 1; continue; }
    if (line.startsWith('```')) {
      const code = []; index += 1;
      while (index < lines.length && !lines[index].startsWith('```')) code.push(lines[index++]);
      index += 1; html.push(`<pre><code>${escapeHtml(code.join('\n'))}</code></pre>`); continue;
    }
    const heading = line.match(/^(#{2,4})\s+(.+)$/);
    if (heading) {
      const baseId = slugify(heading[2]);
      const count = (headingIdCounts.get(baseId) ?? 0) + 1;
      headingIdCounts.set(baseId, count);
      const id = count === 1 ? baseId : `${baseId}-${count}`;
      const level = `h${heading[1].length}`;
      html.push(`<${level} id="${id}">${renderInline(heading[2])}</${level}>`);
      visualReferences.filter((reference) => reference.afterHeading === heading[2]).forEach((reference) => {
        html.push(renderSpecimen(reference.specimenId));
        renderedReferences.add(reference);
      });
      index += 1; continue;
    }
    if (/^---+$/.test(line)) { html.push('<hr>'); index += 1; continue; }
    if (isTable(line) && isTable(lines[index + 1] ?? '') && /^\|\s*:?-+/.test(lines[index + 1])) {
      const headers = tableCells(line); index += 2;
      const rows = [];
      while (index < lines.length && isTable(lines[index])) rows.push(tableCells(lines[index++]));
      html.push(`<table><thead><tr>${headers.map((cell) => `<th>${cell}</th>`).join('')}</tr></thead><tbody>${rows.map((row) => `<tr>${row.map((cell) => `<td>${cell}</td>`).join('')}</tr>`).join('')}</tbody></table>`);
      continue;
    }
    const list = line.match(/^(\s*)([-*]|\d+\.)\s+(.+)$/);
    if (list) {
      const ordered = /\d+\./.test(list[2]); const tag = ordered ? 'ol' : 'ul'; const items = [];
      while (index < lines.length) {
        const item = lines[index].match(/^\s*([-*]|\d+\.)\s+(.+)$/);
        if (!item) break;
        items.push(`<li>${renderInline(item[2])}</li>`); index += 1;
      }
      html.push(`<${tag}>${items.join('')}</${tag}>`); continue;
    }
    if (line.startsWith('> ')) { html.push(`<blockquote>${renderInline(line.slice(2))}</blockquote>`); index += 1; continue; }
    const paragraph = [line.trim()]; index += 1;
    while (index < lines.length && lines[index].trim() && !/^(#{2,4}\s|```|[-*]\s|\d+\.\s|> |---+$)/.test(lines[index]) && !isTable(lines[index])) paragraph.push(lines[index++].trim());
    html.push(`<p>${renderInline(paragraph.join(' '))}</p>`);
  }
  const missingReference = visualReferences.find((reference) => !renderedReferences.has(reference));
  if (missingReference) throw new Error(`Could not insert visual reference after heading: ${missingReference.afterHeading}`);
  return html.join('\n');
}

function layout(title, body, depth = '') {
  const assetPath = depth ? '../' : '';
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="description" content="CaseChain plans, delivery snapshot, and review portal."><title>${escapeHtml(title)} · CaseChain Project Portal</title><link rel="stylesheet" href="${assetPath}assets/site.css"></head>
<body><header class="site-header"><div class="header-inner"><a class="brand" href="${assetPath}index.html">CaseChain <small>Project portal</small></a><div class="header-actions"><a class="header-link" href="${assetPath}index.html#plans">Browse plans</a><a class="header-link" href="${repositoryUrl}" target="_blank" rel="noreferrer">Repository</a><button class="quiet-button" type="button" data-theme-toggle>Use dark appearance</button></div></div></header><main class="page">${body}</main><footer class="site-footer"><div class="footer-inner">CaseChain Project Portal · Public planning and progress snapshot</div></footer><script src="${assetPath}assets/site.js"></script></body></html>`;
}

const domainNames = { 'design-system': 'Design system', features: 'Features', platform: 'Platform', operations: 'Operations' };
const statusOrder = ['in-progress', 'approved', 'proposed', 'completed', 'superseded'];
const statusLabel = (status) => status.replaceAll('-', ' ');

await rm(outputRoot, { recursive: true, force: true });
await mkdir(path.join(outputRoot, 'plans'), { recursive: true });
await mkdir(path.join(outputRoot, 'assets'), { recursive: true });
await cp(path.join(root, 'project-portal/site.css'), path.join(outputRoot, 'assets/site.css'));
await cp(path.join(root, 'project-portal/site.js'), path.join(outputRoot, 'assets/site.js'));

const planFiles = (await walk(plansRoot)).filter((file) => file.endsWith('.md') && !file.endsWith('_template.md'));
const plans = (await Promise.all(planFiles.map(async (file) => parsePlan(await readFile(file, 'utf8'), file)))).filter(Boolean);
const planReadingIndexes = new Map(portalReadingOrder.map((relativePath, index) => [relativePath, index]));
if (planReadingIndexes.size !== portalReadingOrder.length) throw new Error('Duplicate path in portal reading order.');
const unorderedPlan = plans.find((plan) => !planReadingIndexes.has(plan.relativePath));
if (unorderedPlan) throw new Error(`Plan is missing from the portal reading order: ${unorderedPlan.relativePath}`);
const missingEdition = plans.find((plan) => !plainLanguagePlans[plan.relativePath]);
if (missingEdition) throw new Error(`Plan is missing its public-reader edition: ${missingEdition.relativePath}`);
const missingArticle = plans.find((plan) => !planArticles[plan.relativePath]);
if (missingArticle) throw new Error(`Plan is missing its public article: ${missingArticle.relativePath}`);
const invalidArticleLength = plans.find((plan) => {
  const article = planArticles[plan.relativePath];
  const words = [article.deck, article.intro, ...article.sections.flatMap((section) => [section.heading, ...section.paragraphs])].join(' ').trim().split(/\s+/).length;
  return words < 200 || words > 500;
});
if (invalidArticleLength) throw new Error(`Public article must be 200–500 words: ${invalidArticleLength.relativePath}`);
plans.sort((left, right) => planReadingIndexes.get(left.relativePath) - planReadingIndexes.get(right.relativePath));
const count = (status) => plans.filter((plan) => plan.status === status).length;

const metrics = statusOrder.filter((status) => count(status)).map((status) => `<div class="metric"><span class="metric-value">${count(status)}</span><span class="metric-label">${escapeHtml(statusLabel(status))}</span></div>`).join('');
const filterButtons = ['all', ...statusOrder.filter((status) => count(status))].map((status, index) => `<button class="filter-button" type="button" data-plan-filter="${status}" aria-pressed="${index === 0}">${status === 'all' ? 'All plans' : statusLabel(status)}${status === 'all' ? ` (${plans.length})` : ` (${count(status)})`}</button>`).join('');
const cards = plans.map((plan) => `<article class="plan-card" data-plan-status="${escapeHtml(plan.status)}"><a class="plan-card-link" href="plans/${plan.slug}.html"><div class="plan-card-content"><div><span class="badge status-${escapeHtml(plan.status)}">${escapeHtml(statusLabel(plan.status))}</span></div><h3>${escapeHtml(plan.title)}</h3><p>${escapeHtml(plainLanguagePlans[plan.relativePath].overview)}</p><div class="plan-meta"><span>${escapeHtml(domainNames[plan.domain] ?? plan.domain)}</span><span>Updated ${escapeHtml(plan.updated)}</span></div><span class="read-link">Read article →</span></div></a></article>`).join('');

const dashboard = `<section class="portal-hero"><p class="eyebrow">Public review space</p><h1>CaseChain, clearly mapped.</h1><p class="lede">A friendly guide to what we are building, why it matters, and how the pieces fit together. Plan status shows how settled the thinking is—it does not mean every feature has shipped.</p></section>
<section class="section"><div class="section-heading"><div><h2>Plan overview</h2><p>${plans.length} archived plans · source status from plan frontmatter</p></div></div><div class="metric-grid">${metrics}</div></section>
<section class="section" id="plans"><div class="section-heading"><div><h2>Plans</h2><p>Read in the recommended order. Each page is written for people first, with the detailed source plan always one click away.</p></div></div><div class="filter-bar" aria-label="Filter plans by status">${filterButtons}</div><div class="plan-list">${cards}</div><p class="empty-filter" data-empty-filter>No plans match this filter.</p></section>`;
await writeFile(path.join(outputRoot, 'index.html'), layout('Overview', dashboard));

await Promise.all(plans.map(async (plan, index) => {
  const sourceUrl = `${repositoryUrl}/blob/${sourceBranch}/${plan.relativePath}`;
  const article = renderArticle(plan);
  const previous = plans[index - 1];
  const next = plans[index + 1];
  const pagination = `<nav class="article-pagination" aria-label="More plan articles">${previous ? `<a href="${previous.slug}.html"><span>Previous</span><b>${escapeHtml(previous.title)}</b></a>` : '<span></span>'}${next ? `<a class="article-next" href="${next.slug}.html"><span>Next</span><b>${escapeHtml(next.title)}</b></a>` : '<span></span>'}</nav>`;
  const content = `<article class="plan-article"><div class="article-heading"><a class="back-link" href="../index.html#plans">← All plans</a><p class="eyebrow">${escapeHtml(domainNames[plan.domain] ?? plan.domain)}</p><h1>${escapeHtml(plan.title)}</h1><div class="article-meta"><span class="badge status-${escapeHtml(plan.status)}">${escapeHtml(statusLabel(plan.status))}</span><span>Updated ${escapeHtml(plan.updated)}</span><span>${article.wordCount} words · ${article.readingMinutes} min read</span></div></div><div class="article-layout">${article.toc}<div class="article-column"><div class="article-body">${article.html}<aside class="source-note"><h2>Read the original source</h2><p>This article explains the plan for a general reader. The repository keeps the complete technical contract and its change history.</p><a href="${sourceUrl}" target="_blank" rel="noreferrer">Open the canonical plan on GitHub</a></aside></div>${pagination}</div></div></article>`;
  await writeFile(path.join(outputRoot, 'plans', `${plan.slug}.html`), layout(plan.title, content, 'plans'));
}));

console.log(`Built ${plans.length} plan pages in ${path.relative(root, outputRoot)}.`);
