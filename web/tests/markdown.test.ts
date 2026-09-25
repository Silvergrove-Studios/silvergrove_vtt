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
  it('draws the SRD tables, with the "Table:" line as the caption', () => {
    const html = markdown('Choose one.\n\nTable: Skills\n\n|Skill|Ability|\n|---|---|\n|Acrobatics|Dexterity|\n|**Arcana**|Intelligence|\n\nAfter.');
    expect(html).toContain('<p>Choose one.</p>');
    expect(html).toContain('<caption>Skills</caption>');
    expect(html).toContain('<thead><tr><th>Skill</th><th>Ability</th></tr></thead>');
    expect(html).toContain('<tr><td>Acrobatics</td><td>Dexterity</td></tr>');
    expect(html).toContain('<td><strong>Arcana</strong></td>');
    expect(html).toContain('<p>After.</p>');
    expect(html).not.toContain('|');
  });
  it('drops an empty header and empty rows, and pads short rows', () => {
    const html = markdown('|||\n|---|---|\n|Primary Ability|Strength or Dexterity|\n|Hit Point Die|\n|||');
    expect(html).not.toContain('<thead>');
    expect(html).toContain('<tr><td>Primary Ability</td><td>Strength or Dexterity</td></tr>');
    expect(html).toContain('<tr><td>Hit Point Die</td><td></td></tr>');
    expect((html.match(/<tr>/g) ?? []).length).toBe(2);
  });
  it('leaves a lone "Table:" line as a caption and pipes in prose alone', () => {
    expect(markdown('Table: Nothing follows')).toContain('<p class="md-caption">Nothing follows</p>');
    expect(markdown('a | b')).toContain('<p>a | b</p>');
  });
});
