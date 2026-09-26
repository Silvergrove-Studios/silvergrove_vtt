import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Waiting } from '../src/lib/waiting';

type Answer = { ok: boolean; why?: string };

// what a form waits for: the table's done or refused, by the req it sent
describe('what a page waits for the table to answer', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });
  const make = (late: () => Answer = () => ({ ok: false, why: 'no answer' })) => new Waiting<Answer>('i', 10000, late);

  it('is settled by the answer to its own req', async () => {
    const w = make();
    const a = w.ask();
    const b = w.ask();
    expect(a.req).not.toBe(b.req);
    expect(w.size).toBe(2);
    expect(w.answer(b.req, { ok: false, why: 'that is not your character' })).toBe(true);
    expect(w.answer(a.req, { ok: true })).toBe(true);
    await expect(a.answer).resolves.toEqual({ ok: true });
    await expect(b.answer).resolves.toEqual({ ok: false, why: 'that is not your character' });
    expect(w.size).toBe(0);
  });

  it('counts ten seconds without an answer as not done, and an answer after that as nothing', async () => {
    const late = vi.fn(() => ({ ok: false, why: 'no answer' }));
    const w = make(late);
    const a = w.ask();
    vi.advanceTimersByTime(9999);
    expect(late).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    await expect(a.answer).resolves.toEqual({ ok: false, why: 'no answer' });
    expect(late).toHaveBeenCalledTimes(1);
    expect(w.answer(a.req, { ok: true })).toBe(false);
  });

  it('takes one answer to each req, and none to a req it never sent', async () => {
    const late = vi.fn(() => ({ ok: false }));
    const w = make(late);
    expect(w.answer('i99', { ok: true })).toBe(false);
    const a = w.ask();
    expect(w.answer(a.req, { ok: true })).toBe(true);
    expect(w.answer(a.req, { ok: false })).toBe(false);
    vi.advanceTimersByTime(20000);
    await expect(a.answer).resolves.toEqual({ ok: true });
    expect(late).not.toHaveBeenCalled();
  });
});
