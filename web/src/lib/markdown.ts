// The little Markdown rules text and descriptions use, as safe HTML:
// # headings, **bold**, *italic*, - bullets, paragraphs, line breaks. Every
// character is escaped first, so text can never inject markup.

export function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function inline(s: string): string {
  return s
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|[^*])\*([^*\n]+?)\*/g, '$1<em>$2</em>')
    .replace(/(^|[^_\w])_([^_\n]+?)_(?=[^_\w]|$)/g, '$1<em>$2</em>');
}

export function markdown(md: string): string {
  const lines = escapeHtml(md ?? '').replace(/\r\n/g, '\n').split('\n');
  const out: string[] = [];
  let para: string[] = [];
  let list: string[] = [];
  const flushPara = () => {
    if (para.length) out.push(`<p>${inline(para.join('<br>'))}</p>`);
    para = [];
  };
  const flushList = () => {
    if (list.length) out.push(`<ul>${list.map((li) => `<li>${inline(li)}</li>`).join('')}</ul>`);
    list = [];
  };
  for (const raw of lines) {
    const line = raw.trimEnd();
    const h = /^(#{1,4})\s+(.*)$/.exec(line);
    const bullet = /^\s*[-*•]\s+(.*)$/.exec(line);
    const numbered = /^\s*(\d+)[.)]\s+(.*)$/.exec(line);
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
  return out.join('');
}
