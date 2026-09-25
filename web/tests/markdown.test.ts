import { describe, expect, it } from 'vitest';
import { markdown } from '../src/lib/markdown';

describe('markdown', () => {
  it('formats rules text', () => {
    const html = markdown('# Charmed\nWhile **charmed**, you *cannot* attack.\n\n- One\n- Two');
    expect(html).toContain('<h3>Charmed</h3>');
    expect(html).toContain('<strong>charmed</strong>');
    expect(html).toContain('<em>cannot</em>');
    expect(html).toContain('<ul><li>One</li><li>Two</li></ul>');
  });
  it('keeps paragraphs apart and never lets markup through', () => {
    const html = markdown('First.\nSame paragraph.\n\nSecond <script>alert(1)</script>');
    expect(html).toContain('<p>First.<br>Same paragraph.</p>');
    expect(html).not.toContain('<script>');
    expect(html).toContain('&lt;script&gt;');
  });
  it('numbers steps', () => {
    expect(markdown('1. Do this')).toContain('<span class="n">1.</span> Do this');
  });
});
