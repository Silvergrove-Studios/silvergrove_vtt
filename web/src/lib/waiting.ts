// What a page waits for the table to answer, by the `req` it sent with it:
// settled by the answer, or at a time limit by whatever `late` says then.

export class Waiting<T> {
  private waiting = new Map<string, { settle: (v: T) => void; timer: ReturnType<typeof setTimeout> }>();
  private seq = 0;
  private prefix: string;
  private ms: number;
  private late: () => T;

  constructor(prefix: string, ms: number, late: () => T) {
    this.prefix = prefix;
    this.ms = ms;
    this.late = late;
  }

  /** A new `req` to send, and the answer it will get. */
  ask(): { req: string; answer: Promise<T> } {
    const req = `${this.prefix}${++this.seq}`;
    const answer = new Promise<T>((settle) => {
      const timer = setTimeout(() => this.answer(req, this.late()), this.ms);
      this.waiting.set(req, { settle, timer });
    });
    return { req, answer };
  }

  /** The table's answer to `req`; false when nothing waits for it (answered already, too late, or never asked here). */
  answer(req: string, v: T): boolean {
    const w = this.waiting.get(req);
    if (!w) return false;
    this.waiting.delete(req);
    clearTimeout(w.timer);
    w.settle(v);
    return true;
  }

  /** How many answers are still awaited. */
  get size(): number {
    return this.waiting.size;
  }
}
