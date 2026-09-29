// Builds the GitHub Pages site into site/dist from the repository itself:
// README.md (the documentation) and the latest release tag. The pages
// workflow runs it on every change to those and after every release, so the
// site never drifts from the code.
import { readFileSync, writeFileSync, mkdirSync, cpSync, rmSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Marked } from 'marked';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const dist = join(here, 'dist');
const REPO = 'https://github.com/moukrea/agentline';
const VIDEOS = [
  { id: 'J5fozI2P5Xw', file: 'agentline-overview.mp4', thumb: 'thumb-overview.jpg', title: 'Overview', len: '2 min', text: 'Everything the line shows, and every way to style it, in two minutes.' },
];

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const slug = s => s.toLowerCase().replace(/<[^>]+>/g, '').replace(/[`*_]/g, '').replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-');

function version() {
  if (process.env.AGENTLINE_VERSION) return process.env.AGENTLINE_VERSION;
  try { return execSync('git describe --tags --abbrev=0 --match "v[0-9]*"', { cwd: root }).toString().trim(); } catch { return ''; }
}

// The documentation: README.md from its first section on (the intro and
// the videos are the page's own hero).
function docs() {
  const md = readFileSync(join(root, 'README.md'), 'utf8');
  const body = md.slice(md.indexOf('\n## ') + 1);
  const toc = [];
  const marked = new Marked({ gfm: true });
  marked.use({
    renderer: {
      heading({ tokens, depth }) {
        const text = this.parser.parseInline(tokens);
        const id = slug(text);
        if (depth <= 3) toc.push({ depth, id, text: text.replace(/<[^>]+>/g, '') });
        return `<h${depth} id="${id}"><a class="anchor" href="#${id}" aria-hidden="true">#</a>${text}</h${depth}>\n`;
      },
      link({ href, title, tokens }) {
        const text = this.parser.parseInline(tokens);
        let url = href;
        if (!/^(https?:|mailto:|#)/.test(href)) url = `${REPO}/blob/main/${href.replace(/^\.\//, '')}`;
        const ext = /^https?:/.test(url) ? ' target="_blank" rel="noopener"' : '';
        return `<a href="${esc(url)}"${title ? ` title="${esc(title)}"` : ''}${ext}>${text}</a>`;
      },
      code({ text, lang }) {
        const l = (lang || '').split(/\s/)[0];
        return `<div class="code"><button class="copy" type="button" aria-label="Copy">Copy</button><pre><code${l ? ` class="lang-${esc(l)}"` : ''}>${esc(text)}</code></pre></div>\n`;
      },
    },
  });
  return { html: marked.parse(body), toc };
}

const v = version();
const d = docs();
const tpl = readFileSync(join(here, 'template.html'), 'utf8');
const tocHtml = d.toc.map(x => `<a class="d${x.depth}" href="#${x.id}">${x.text}</a>`).join(''); // already escaped by marked
const videos = VIDEOS.map(x => `
      <figure class="video">
        <div class="frame"><button class="play" type="button" data-src="media/${x.file}" aria-label="Play the ${esc(x.title.toLowerCase())} (${esc(x.len)})"><img src="assets/${x.thumb}" alt="" loading="lazy"><span class="btn" aria-hidden="true"></span></button></div>
        <figcaption><b>${esc(x.title)}</b> <span>${esc(x.len)}</span><br>${esc(x.text)} <a href="https://youtu.be/${x.id}" target="_blank" rel="noopener">Open on YouTube ↗</a></figcaption>
      </figure>`).join('');
const html = tpl
  .replaceAll('{{VERSION}}', esc(v || 'latest'))
  .replaceAll('{{RELEASE_URL}}', v ? `${REPO}/releases/tag/${v}` : `${REPO}/releases`)
  .replaceAll('{{REPO}}', REPO)
  .replace('{{VIDEOS}}', videos)
  .replace('{{TOC}}', tocHtml)
  .replace('{{DOCS}}', d.html)
  ;

rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });
writeFileSync(join(dist, 'index.html'), html);
cpSync(join(here, 'style.css'), join(dist, 'style.css'));
cpSync(join(here, 'site.js'), join(dist, 'site.js'));
cpSync(join(here, 'assets'), join(dist, 'assets'), { recursive: true });
for (const f of ['wordmark-dark.png', 'wordmark-light.png', 'thumb-overview.jpg']) cpSync(join(root, 'docs/media', f), join(dist, 'assets', f));
writeFileSync(join(dist, '.nojekyll'), '');
console.log(`site built: ${dist} (${v || 'no tag'}, ${d.toc.length} headings)`);
