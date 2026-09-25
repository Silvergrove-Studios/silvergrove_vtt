// The WebSocket to the Table: JSON messages with a type `t`, the host's
// Protocol (hexmap/net/protocol.gd). Reconnects by itself — a phone that
// slept, a Wi-Fi hiccup — and says hello and joins again when it does.

export type Msg = { t: string; [k: string]: unknown };
export const PROTOCOL = 2;

export class Connection {
  url: string;
  ws: WebSocket | null = null;
  onmessage: (m: Msg) => void = () => {};
  onstatus: (s: 'connecting' | 'open' | 'closed') => void = () => {};
  /** What to say on every (re)connect: hello, then join. */
  greeting: Msg[] = [];
  private closedByUs = false;
  private retry = 0;
  private timer: ReturnType<typeof setTimeout> | null = null;

  constructor(url: string) {
    this.url = url;
  }

  connect(): void {
    this.closedByUs = false;
    this.onstatus('connecting');
    const ws = new WebSocket(this.url);
    this.ws = ws;
    ws.onopen = () => {
      this.retry = 0;
      this.onstatus('open');
      for (const m of this.greeting) this.send(m);
    };
    ws.onmessage = (ev) => {
      try {
        const m = JSON.parse(String(ev.data));
        if (m && typeof m === 'object' && typeof m.t === 'string') this.onmessage(m as Msg);
      } catch {
        /* not ours */
      }
    };
    ws.onclose = () => {
      this.ws = null;
      this.onstatus('closed');
      if (!this.closedByUs) {
        this.retry = Math.min(this.retry + 1, 6);
        this.timer = setTimeout(() => this.connect(), 500 * 2 ** (this.retry - 1));
      }
    };
    ws.onerror = () => ws.close();
  }

  send(m: Msg): boolean {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return false;
    this.ws.send(JSON.stringify(m));
    return true;
  }

  close(): void {
    this.closedByUs = true;
    if (this.timer) clearTimeout(this.timer);
    this.ws?.close();
  }
}
