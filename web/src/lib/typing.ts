// "Leo is typing…" under the chat. In a playtest the DM and a player
// crossed messages many times, each answering what the other had said
// before; a screen now tells the table, now and then, that its chat box
// holds something being written, and the others say who.

/** How long a screen that said it was typing is shown so, unless it says so again. */
export const TYPING_SHOWN_MS = 5000;

/** When this screen tells the table it is typing: as the chat box's text
 *  changes and holds something, at most once every `gap` ms. */
export class TypingSignal {
  private last = -Infinity;
  private readonly send: () => void;
  private readonly gap: number;
  private readonly now: () => number;

  constructor(send: () => void, gap = 3000, now: () => number = () => Date.now()) {
    this.send = send;
    this.gap = gap;
    this.now = now;
  }

  /** The box's text changed: whether the table was told. */
  input(text: string): boolean {
    if (!String(text ?? '').trim()) return false;
    const t = this.now();
    if (t - this.last < this.gap) return false;
    this.last = t;
    this.send();
    return true;
  }

  /** The message went: the next one is news at once. */
  sent(): void {
    this.last = -Infinity;
  }
}

/** Who is typing, as the chat says it ("the DM" starts it as "The DM"). */
export function typingWords(names: string[]): string {
  const list = names.filter((n) => String(n ?? '').trim() !== '');
  let s = '';
  if (list.length === 1) s = `${list[0]} is typing…`;
  else if (list.length === 2) s = `${list[0]} and ${list[1]} are typing…`;
  else if (list.length > 2) s = `${list.slice(0, -1).join(', ')} and ${list[list.length - 1]} are typing…`;
  return s.charAt(0).toUpperCase() + s.slice(1);
}
