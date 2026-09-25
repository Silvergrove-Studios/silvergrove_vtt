// The little Markdown rules text and descriptions use, as safe HTML:
// # headings, **bold**, *italic*, - bullets, paragraphs, line breaks, and
// the SRDs' tables (`|a|b|` rows under a `|---|---|` line, with the
// "Table: …" line before one as its caption). Every character is escaped
// first, so text can never inject markup.

export function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function inline(s: string): string {
  return s
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|[^*])\*([^*\n]+?)\*/g, '$1<em>$2</em>')
    .replace(/(^|[^_\w])_([^_\n]+?)_(?=[^_\w]|$)/g, '$1<em>$2</em>');
}

/** A table row's cells: `| a | b |` → ["a", "b"]. */
function cells(line: string): string[] {
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);
  return s.split('|').map((c) => c.trim());
}

const isRow = (line: string): boolean => line.trim().startsWith('|');
const isRule = (line: string): boolean => /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/.test(line);

function table(rows: string[], caption: string): string {
  const head = cells(rows[0]);
  const body = rows.slice(isRule(rows[1] ?? '') ? 2 : 1).map(cells);
  const width = Math.max(head.length, ...body.map((r) => r.length));
  const pad = (r: string[]) => [...r, ...Array(Math.max(0, width - r.length)).fill('')];
  // a row with nothing in it (the SRD ends some tables so) says nothing
  const rowsOut = body.filter((r) => r.some((c) => c !== '')).map((r) => `<tr>${pad(r).map((c) => `<td>${inline(c)}</td>`).join('')}</tr>`);
  const headOut = head.some((c) => c !== '') ? `<thead><tr>${pad(head).map((c) => `<th>${inline(c)}</th>`).join('')}</tr></thead>` : '';
  const cap = caption ? `<caption>${inline(caption)}</caption>` : '';
  return `<div class="md-table"><table>${cap}${headOut}<tbody>${rowsOut.join('')}</tbody></table></div>`;
}

export function markdown(md: string): string {
  const lines = escapeHtml(md ?? '').replace(/\r\n/g, '\n').split('\n');
  const out: string[] = [];
  let para: string[] = [];
  let list: string[] = [];
  let caption = '';
  const flushPara = () => {
    if (para.length) out.push(`<p>${inline(para.join('<br>'))}</p>`);
    para = [];
  };
  const flushList = () => {
    if (list.length) out.push(`<ul>${list.map((li) => `<li>${inline(li)}</li>`).join('')}</ul>`);
    list = [];
  };
  const flushCaption = () => {
    if (caption) out.push(`<p class="md-caption">${inline(caption)}</p>`);
    caption = '';
  };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trimEnd();
    // a table: its rows, the rule under the first
    if (isRow(line) && isRule(lines[i + 1] ?? '')) {
      flushPara();
      flushList();
      const rows: string[] = [];
      while (i < lines.length && isRow(lines[i])) rows.push(lines[i++]);
      i--;
      out.push(table(rows, caption));
      caption = '';
      continue;
    }
    const cap = /^Table:\s*(.+)$/.exec(line.trim());
    if (cap) {
      flushPara();
      flushList();
      flushCaption();
      caption = cap[1];
      continue;
    }
    const h = /^(#{1,4})\s+(.*)$/.exec(line);
    const bullet = /^\s*[-*•]\s+(.*)$/.exec(line);
    const numbered = /^\s*(\d+)[.)]\s+(.*)$/.exec(line);
    if (line.trim() !== '') flushCaption();
    if (h) {
      flushPara();
      flushList();
      const level = Math.min(4, h[1].length + 2);
      out.push(`<h${level}>${inline(h[2])}</h${level}>`);
    } else if (bullet) {
      flushPara();
      list.push(bullet[1]);
    } else if (numbered) {
      flushPara();
      flushList();
      out.push(`<p class="numbered"><span class="n">${numbered[1]}.</span> ${inline(numbered[2])}</p>`);
    } else if (line.trim() === '') {
      flushPara();
      flushList();
    } else {
      flushList();
      para.push(line);
    }
  }
  flushPara();
  flushList();
  flushCaption();
  return out.join('');
}
