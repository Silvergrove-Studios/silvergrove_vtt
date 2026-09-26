import { describe, expect, it } from 'vitest';
import { Expr, capitalize, toText } from '../src/lib/expr';

const ev = (s: string, ctx: Record<string, unknown> = {}) => Expr.evaluate(s, ctx);

describe('Expr, as the host has it', () => {
  it('does arithmetic and precedence', () => {
    expect(ev('1 + 2 * 3')).toBe(7);
    expect(ev('-2 ^ 2')).toBe(-4);
    expect(ev('2 ^ 3 ^ 2')).toBe(512);
    expect(ev('7 % 3')).toBe(1);
    expect(ev('1 / 0')).toBe(null);
  });
  it('joins two lists with +', () => {
    const ctx = { mine: ['stealth'], theirs: ['insight', 'religion'] };
    expect(ev('@mine + @theirs', ctx)).toEqual(['stealth', 'insight', 'religion']);
    expect(ev('(@none ?? []) + @theirs', ctx)).toEqual(['insight', 'religion']);
    expect(ev('@mine + 1', ctx)).toBe(null);
  });
  it('reads paths, null when absent', () => {
    const ctx = { actor: { level: 3, name: 'Wren' }, tags: ['a', 'b'], stats: { dex: 14 }, pools: { hp_x: { max: 9 } }, id: 'x' };
    expect(ev('@actor.level * 2 + 1', ctx)).toBe(7);
    expect(ev('@tags[1]', ctx)).toBe('b');
    expect(ev('@stats["dex"]', ctx)).toBe(14);
    expect(ev('@pools["hp_" .. @id].max', ctx)).toBe(9);
    expect(ev('@nothing.here', ctx)).toBe(null);
    expect(ev('@nothing ?? 5', ctx)).toBe(5);
  });
  it('formats text like the host', () => {
    expect(ev("'Level ' .. 3")).toBe('Level 3');
    expect(ev("'AC ' .. 12.0")).toBe('AC 12');
    expect(toText(2.5)).toBe('2.5');
    expect(toText(0.1 + 0.2)).toBe('0.3');
    expect(ev("str(true) .. str(null)")).toBe('true');
  });
  it('compares, chooses and tests membership', () => {
    expect(ev('@a == 1.0', { a: 1 })).toBe(true);
    expect(ev('"x" in ["x", "y"]')).toBe(true);
    expect(ev('"ell" in "hello"')).toBe(true);
    expect(ev('@k in @o', { k: 'a', o: { a: 1 } })).toBe(true);
    expect(ev('@n > 2 ? "big" : "small"', { n: 3 })).toBe('big');
    expect(ev('not @x and 1', { x: null })).toBe(1);
    expect(ev('0 or 5')).toBe(0);
    expect(ev('@item.rank == 2 ? "◆ " : (@item.rank == 1 ? "● " : "○ ")', { item: { rank: 1 } })).toBe('● ');
  });
  it('calls its functions', () => {
    expect(ev('min(3, 1, 2)')).toBe(1);
    expect(ev('max([4, 9])')).toBe(9);
    expect(ev('round(2.5)')).toBe(3);
    expect(ev('round(-2.5)')).toBe(-3);
    expect(ev('len(@l)', { l: [1, 2] })).toBe(2);
    expect(ev('upper("dex")')).toBe('DEX');
    expect(ev('join(@l, ", ")', { l: ['a', 'b'] })).toBe('a, b');
    expect(ev('title("magic_items")')).toBe('Magic Items');
    expect(ev('has(@o, "a")', { o: { a: 1 } })).toBe(true);
    expect(ev('num("12")')).toBe(12);
    expect(ev('clamp(15, 0, 10)')).toBe(10);
    expect(ev('sum([1, 2, 3])')).toBe(6);
  });
  it('reports errors and never throws', () => {
    const e = Expr.parse('1 +');
    expect(e.isValid()).toBe(false);
    expect(Expr.parse('foo').error).toContain('unknown name');
    expect(Expr.parse('"open').error).toContain('unterminated');
    expect(ev('"a" - 1')).toBe(null);
    expect(Expr.parse('@actor.level + @x').deps).toEqual(['actor.level', 'x']);
  });
  it('capitalizes like Godot', () => {
    expect(capitalize('weapon_properties')).toBe('Weapon Properties');
    expect(capitalize('camelCase')).toBe('Camel Case');
  });
});
