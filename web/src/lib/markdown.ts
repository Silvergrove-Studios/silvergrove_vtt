// The little Markdown rules text and descriptions use, as safe HTML:
// # headings, **bold**, *italic*, - bullets, paragraphs, line breaks, the
// SRDs' tables (`|a|b|` rows under a `|---|---|` line, with the "Table: …"
// line before one as its caption), and pictures — `![caption](ref)`, a
// picture the table knows (`upload:<id>`, `pack:picture`), never an
// address elsewhere. Every character is escaped first, so text can never
// inject markup.

export function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

/** Where a picture's ref is (the page says, from what the table sent): "" when it cannot. */
let resolvePicture: (ref: string) => string = () => '';

export function setPictureResolver(f: (ref: string) => string): void {
  resolvePicture = f;
}

const PICTURE = /!\[([^\]\n]*)\]\(([a-z0-9_.-]+:[A-Za-z0-9_./-]+)\)/g;

/** A picture's address, only ever one of the table's own (a path on it). */
function pictureSrc(ref: string): string {
  const url = resolvePicture(ref);
  return url.startsWith('/') && !url.startsWith('//') ? url : '';
}

function picture(alt: string, ref: string, block: boolean): string {
  const src = pictureSrc(ref);
  if (!src) return `<span class="md-missing">[${alt || 'a picture'}]</span>`;
  const img = `<img class="md-picture" src="${escapeHtml(src)}" alt="${alt}" loading="lazy">`;
  return block ? `<figure class="md-figure">${img}${alt ? `<figcaption>${alt}</figcaption>` : ''}</figure>` : img;
}

function inline(s: string): string {
  // pictures are set aside while bold and italic are found, so neither
  // reaches into a picture's address or caption
  const pics: string[] = [];
  const held = s.replace(PICTURE, (_m, alt: string, ref: string) => {
    pics.push(picture(alt, ref, false));
    return `\u0000${pics.length - 1}\u0000`;
  });
  return held
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|[^*])\*([^*\n]+?)\*/g, '$1<em>$2</em>')
    .replace(/(^|[^_\w])_([^_\n]+?)_(?=[^_\w]|$)/g, '$1<em>$2</em>')
    .replace(/\u0000(\d+)\u0000/g, (_m, i: string) => pics[Number(i)] ?? '');
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
    // a picture on a line of its own: a figure, with its caption
    const pic = /^!\[([^\]\n]*)\]\(([a-z0-9_.-]+:[A-Za-z0-9_./-]+)\)$/.exec(line.trim());
    if (pic) {
      flushPara();
      flushList();
      flushCaption();
      out.push(picture(pic[1], pic[2], true));
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
