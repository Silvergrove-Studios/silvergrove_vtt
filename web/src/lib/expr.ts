// The expression language rulesets put in their views (the host's Expr,
// hexmap/core/expr.gd): total, side-effect free, no loops. Values are JSON:
// numbers, strings, booleans, null, lists, objects. Parse once (cached by
// text), evaluate against a context object.
//
//   literals 12 2.5 "text" 'text' true false null [1, "a"]
//   paths @actor.level @tags[0] @stats["dex"] (null when absent)
//   + - * / % ^, unary -, .. (concatenate), == != < <= > >=,
//   and or not, x in list, a ?? b, cond ? a : b,
//   min max abs floor ceil round clamp len num str lower upper title
//   sum has contains starts ends join sign

export type Json = null | boolean | number | string | Json[] | { [k: string]: Json };
type Ast = Json | Ast[] | unknown;

const MAX_DEPTH = 48;
const cache = new Map<string, Expr>();

export class Expr {
  error = '';
  text = '';
  deps: string[] = [];
  private ast: Ast = null;
  private valid = false;

  static parse(source: string): Expr {
    const e = new Expr();
    e.text = source;
    const p = new Parser(source);
    const ast = p.parse();
    e.error = p.error;
    e.valid = p.error === '';
    e.ast = e.valid ? ast : null;
    e.deps = p.paths;
    return e;
  }

  /** Parse (cached) and evaluate. */
  static evaluate(source: string, ctx: Record<string, unknown> = {}): Json {
    let e = cache.get(source);
    if (!e) {
      e = Expr.parse(source);
      if (cache.size > 4096) cache.clear();
      cache.set(source, e);
    }
    return e.eval(ctx);
  }

  /** "" on error rather than null: for labels. */
  static evaluateText(source: string, ctx: Record<string, unknown> = {}): string {
    const v = Expr.evaluate(source, ctx);
    return v === null ? '' : toText(v);
  }

  isValid(): boolean {
    return this.valid;
  }

  eval(ctx: Record<string, unknown> = {}): Json {
    if (!this.valid) return null;
    this.error = '';
    const v = this.ev(this.ast, ctx);
    return v === undefined ? null : (v as Json);
  }

  private fail(msg: string): null {
    if (this.error === '') this.error = msg;
    return null;
  }

  private ev(n: Ast, ctx: Record<string, unknown>): unknown {
    if (!Array.isArray(n)) return n;
    const op = n[0] as string;
    switch (op) {
      case 'lit':
        return n[1];
      case 'path':
        return lookup(ctx, n[1] as string[]);
      case 'index':
        return index(this.ev(n[1], ctx), this.ev(n[2], ctx));
      case 'neg': {
        const v = this.ev(n[1], ctx);
        return isNum(v) ? -v : this.fail(`unary - on ${type(v)}`);
      }
      case 'not':
        return !truthy(this.ev(n[1], ctx));
      case 'and': {
        const a = this.ev(n[1], ctx);
        return !truthy(a) ? a : this.ev(n[2], ctx);
      }
      case 'or': {
        const a = this.ev(n[1], ctx);
        return truthy(a) ? a : this.ev(n[2], ctx);
      }
      case '??': {
        const a = this.ev(n[1], ctx);
        return a !== null && a !== undefined ? a : this.ev(n[2], ctx);
      }
      case '?:':
        return truthy(this.ev(n[1], ctx)) ? this.ev(n[2], ctx) : this.ev(n[3], ctx);
      case 'call':
        return this.call(n[1] as string, (n[2] as Ast[]).map((a) => this.ev(a, ctx)));
      default:
        return this.binary(op, this.ev(n[1], ctx), this.ev(n[2], ctx));
    }
  }

  private binary(op: string, a: unknown, b: unknown): unknown {
    switch (op) {
      case '==':
        return equal(a, b);
      case '!=':
        return !equal(a, b);
      case '..':
        return toText(a) + toText(b);
      case 'in':
        if (Array.isArray(b)) return b.some((item) => equal(item, a));
        if (isObj(b)) return typeof a === 'string' && Object.prototype.hasOwnProperty.call(b, a);
        if (typeof b === 'string' && typeof a === 'string') return b.includes(a);
        return this.fail("'in' needs a list, object or string on the right");
    }
    if (!(isNum(a) && isNum(b))) {
      if (['<', '<=', '>', '>='].includes(op) && typeof a === 'string' && typeof b === 'string') {
        if (op === '<') return a < b;
        if (op === '<=') return a <= b;
        if (op === '>') return a > b;
        return a >= b;
      }
      return this.fail(`${op} on ${type(a)} and ${type(b)}`);
    }
    const x = a;
    const y = b;
    switch (op) {
      case '+':
        return x + y;
      case '-':
        return x - y;
      case '*':
        return x * y;
      case '/':
        return y === 0 ? this.fail('division by zero') : x / y;
      case '%':
        return y === 0 ? this.fail('modulo by zero') : x % y;
      case '^':
        return Math.pow(x, y);
      case '<':
        return x < y;
      case '<=':
        return x <= y;
      case '>':
        return x > y;
      case '>=':
        return x >= y;
    }
    return this.fail(`unknown operator ${op}`);
  }

  private call(fn: string, a: unknown[]): unknown {
    const n = a.length;
    const num1 = n === 1 && isNum(a[0]);
    switch (fn) {
      case '__list':
        return a;
      case 'min':
      case 'max': {
        const vals = n === 1 && Array.isArray(a[0]) ? (a[0] as unknown[]) : a;
        if (vals.length === 0) return null;
        let best: number | null = null;
        for (const v of vals) {
          if (!isNum(v)) return this.fail(`${fn} of a non-number`);
          if (best === null || (fn === 'min' ? v < best : v > best)) best = v;
        }
        return best;
      }
      case 'abs':
        return num1 ? Math.abs(a[0] as number) : this.fail('abs(number)');
      case 'floor':
        return num1 ? Math.floor(a[0] as number) : this.fail('floor(number)');
      case 'ceil':
        return num1 ? Math.ceil(a[0] as number) : this.fail('ceil(number)');
      case 'round':
        return num1 ? roundHalfAway(a[0] as number) : this.fail('round(number)');
      case 'sign':
        return num1 ? Math.sign(a[0] as number) : this.fail('sign(number)');
      case 'clamp':
        if (n === 3 && isNum(a[0]) && isNum(a[1]) && isNum(a[2])) return Math.min(Math.max(a[0], a[1]), a[2]);
        return this.fail('clamp(number, lo, hi)');
      case 'len':
        if (n === 1 && typeof a[0] === 'string') return a[0].length;
        if (n === 1 && Array.isArray(a[0])) return a[0].length;
        if (n === 1 && isObj(a[0])) return Object.keys(a[0] as object).length;
        return this.fail('len(list|object|string)');
      case 'num':
        if (n === 1) {
          if (isNum(a[0])) return a[0];
          if (typeof a[0] === 'string' && a[0].trim() !== '' && !isNaN(Number(a[0]))) return Number(a[0]);
          if (typeof a[0] === 'boolean') return a[0] ? 1 : 0;
        }
        return null;
      case 'str':
        return n === 1 ? toText(a[0]) : this.fail('str(value)');
      case 'lower':
        return n === 1 && typeof a[0] === 'string' ? a[0].toLowerCase() : this.fail('lower(string)');
      case 'upper':
        return n === 1 && typeof a[0] === 'string' ? a[0].toUpperCase() : this.fail('upper(string)');
      case 'title':
        return n === 1 && typeof a[0] === 'string' ? capitalize(a[0]) : this.fail('title(string)');
      case 'sum':
        if (n === 1 && Array.isArray(a[0])) {
          let s = 0;
          for (const v of a[0]) {
            if (!isNum(v)) return this.fail('sum of a non-number');
            s += v;
          }
          return s;
        }
        return this.fail('sum(list)');
      case 'has':
        if (n === 2 && isObj(a[0])) return typeof a[1] === 'string' && Object.prototype.hasOwnProperty.call(a[0], a[1]);
        if (n === 2 && Array.isArray(a[0])) return this.binary('in', a[1], a[0]);
        return this.fail('has(object|list, key)');
      case 'contains':
        return n === 2 && typeof a[0] === 'string' ? a[0].includes(toText(a[1])) : this.fail('contains(string, part)');
      case 'starts':
        return n === 2 && typeof a[0] === 'string' ? a[0].startsWith(toText(a[1])) : this.fail('starts(string, part)');
      case 'ends':
        return n === 2 && typeof a[0] === 'string' ? a[0].endsWith(toText(a[1])) : this.fail('ends(string, part)');
      case 'join':
        if (n === 2 && Array.isArray(a[0]) && typeof a[1] === 'string') return a[0].map(toText).join(a[1]);
        return this.fail('join(list, separator)');
    }
    return this.fail(`unknown function ${fn}`);
  }
}

export function truthy(v: unknown): boolean {
  return !(v === null || v === undefined || v === false);
}

function isNum(v: unknown): v is number {
  return typeof v === 'number';
}

function isObj(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function type(v: unknown): string {
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'boolean') return 'boolean';
  if (isNum(v)) return 'number';
  if (typeof v === 'string') return 'string';
  if (Array.isArray(v)) return 'list';
  return 'object';
}

function roundHalfAway(v: number): number {
  return v < 0 ? -Math.round(-v) : Math.round(v);
}

/** Godot's String.capitalize: "snake_case" and "camelCase" to "Snake Case". */
export function capitalize(s: string): string {
  return s
    .replace(/_/g, ' ')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .split(' ')
    .filter((w) => w !== '')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join(' ');
}

function lookup(ctx: unknown, parts: string[]): unknown {
  let v: unknown = ctx;
  for (const p of parts) {
    v = index(v, p);
    if (v === null || v === undefined) return null;
  }
  return v;
}

function index(base: unknown, key: unknown): unknown {
  if (isObj(base)) {
    if (typeof key === 'string' && Object.prototype.hasOwnProperty.call(base, key)) return base[key];
    if (isNum(key)) {
      const k = String(Math.trunc(key));
      if (Object.prototype.hasOwnProperty.call(base, k)) return base[k];
    }
    return null;
  }
  if (Array.isArray(base)) {
    const i = isNum(key) ? Math.trunc(key) : typeof key === 'string' && /^\d+$/.test(key) ? Number(key) : NaN;
    return i >= 0 && i < base.length ? base[i] : null;
  }
  if (typeof base === 'string' && isNum(key)) {
    const i = Math.trunc(key);
    return i >= 0 && i < base.length ? base[i] : null;
  }
  return null;
}

export function equal(a: unknown, b: unknown): boolean {
  if (isNum(a) && isNum(b)) return approx(a, b);
  if (typeof a === 'boolean' || typeof b === 'boolean') return a === b;
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => equal(x, b[i]));
  if (isObj(a) && isObj(b)) {
    const ka = Object.keys(a);
    if (ka.length !== Object.keys(b).length) return false;
    return ka.every((k) => Object.prototype.hasOwnProperty.call(b, k) && equal(a[k], b[k]));
  }
  if ((a === null || a === undefined) && (b === null || b === undefined)) return true;
  return a === b;
}

function approx(a: number, b: number): boolean {
  if (a === b) return true;
  const tol = Math.max(1e-5 * Math.abs(a), 1e-5);
  return Math.abs(a - b) < tol;
}

/** How a value reads in text: whole numbers without a point, JSON for lists and objects. */
export function toText(v: unknown): string {
  if (v === null || v === undefined) return '';
  if (isNum(v)) {
    if (Number.isInteger(v) || (Math.abs(v - Math.round(v)) < 1e-9 && Math.abs(v) < 1e15)) return String(Math.round(v));
    return String(parseFloat(v.toPrecision(12)));
  }
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'string') return v;
  return JSON.stringify(v);
}

// ---------------------------------------------------------------- parser --

type Tok = { t: 'num' | 'str' | 'id' | 'path' | 'op'; v: string | number };

class Parser {
  src: string;
  toks: Tok[] = [];
  pos = 0;
  error = '';
  paths: string[] = [];
  depth = 0;

  constructor(s: string) {
    this.src = s;
    this.tokenize();
  }

  parse(): Ast {
    if (this.error) return null;
    const ast = this.ternary();
    if (!this.error && this.pos < this.toks.length) this.error = `unexpected '${this.toks[this.pos].v}'`;
    return this.error ? null : ast;
  }

  private tokenize(): void {
    const src = this.src;
    const n = src.length;
    let i = 0;
    const digit = (c: string) => c >= '0' && c <= '9';
    const identStart = (c: string) => c === '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    const identChar = (c: string) => identStart(c) || digit(c);
    while (i < n) {
      const c = src[i];
      if (c === ' ' || c === '\t' || c === '\n' || c === '\r') {
        i++;
        continue;
      }
      if (digit(c) || (c === '.' && i + 1 < n && digit(src[i + 1]))) {
        let j = i;
        while (j < n && (digit(src[j]) || src[j] === '.')) {
          if (src[j] === '.' && j + 1 < n && src[j + 1] === '.') break;
          j++;
        }
        const t = src.slice(i, j);
        if (isNaN(Number(t)) || (t.match(/\./g) ?? []).length > 1) {
          this.error = `bad number '${t}'`;
          return;
        }
        this.toks.push({ t: 'num', v: Number(t) });
        i = j;
        continue;
      }
      if (c === '"' || c === "'") {
        let j = i + 1;
        let s = '';
        while (j < n && src[j] !== c) {
          if (src[j] === '\\' && j + 1 < n) {
            j++;
            s += src[j] === 'n' ? '\n' : src[j] === 't' ? '\t' : src[j];
          } else s += src[j];
          j++;
        }
        if (j >= n) {
          this.error = 'unterminated string';
          return;
        }
        this.toks.push({ t: 'str', v: s });
        i = j + 1;
        continue;
      }
      if (c === '@') {
        let j = i + 1;
        while (j < n && (identChar(src[j]) || src[j] === '.')) j++;
        const p = src.slice(i + 1, j);
        if (p === '' || p.startsWith('.') || p.endsWith('.') || p.includes('..')) {
          this.error = `bad path '@${p}'`;
          return;
        }
        this.toks.push({ t: 'path', v: p });
        i = j;
        continue;
      }
      if (identStart(c)) {
        let j = i;
        while (j < n && identChar(src[j])) j++;
        this.toks.push({ t: 'id', v: src.slice(i, j) });
        i = j;
        continue;
      }
      const two = src.slice(i, i + 2);
      if (['==', '!=', '<=', '>=', '..', '??'].includes(two)) {
        this.toks.push({ t: 'op', v: two });
        i += 2;
        continue;
      }
      if ('+-*/%^<>()[],?:'.includes(c)) {
        this.toks.push({ t: 'op', v: c });
        i++;
        continue;
      }
      if (c === '.' && i + 1 < n && identStart(src[i + 1])) {
        this.toks.push({ t: 'op', v: '.' });
        i++;
        continue;
      }
      this.error = `unexpected character '${c}'`;
      return;
    }
  }

  private peek(kind = '', value: string | null = null): boolean {
    if (this.pos >= this.toks.length) return false;
    const t = this.toks[this.pos];
    return (kind === '' || t.t === kind) && (value === null || t.v === value);
  }

  private take(): Tok {
    return this.toks[this.pos++];
  }

  private expect(value: string): boolean {
    if (this.peek('op', value)) {
      this.pos++;
      return true;
    }
    if (!this.error) this.error = `expected '${value}'` + (this.pos >= this.toks.length ? '' : ` before '${this.toks[this.pos].v}'`);
    return false;
  }

  private enter(): boolean {
    this.depth++;
    if (this.depth > MAX_DEPTH) {
      if (!this.error) this.error = 'expression too deep';
      return false;
    }
    return true;
  }

  private ternary(): Ast {
    if (!this.enter()) return null;
    let c = this.coalesce();
    if (this.peek('op', '?')) {
      this.pos++;
      const a = this.ternary();
      if (!this.expect(':')) {
        this.depth--;
        return null;
      }
      const b = this.ternary();
      c = ['?:', c, a, b];
    }
    this.depth--;
    return c;
  }

  private coalesce(): Ast {
    let a = this.or();
    while (this.peek('op', '??')) {
      this.pos++;
      a = ['??', a, this.or()];
    }
    return a;
  }

  private or(): Ast {
    let a = this.and();
    while (this.peek('id', 'or')) {
      this.pos++;
      a = ['or', a, this.and()];
    }
    return a;
  }

  private and(): Ast {
    let a = this.not();
    while (this.peek('id', 'and')) {
      this.pos++;
      a = ['and', a, this.not()];
    }
    return a;
  }

  private not(): Ast {
    if (this.peek('id', 'not')) {
      this.pos++;
      if (!this.enter()) return null;
      const v = ['not', this.not()];
      this.depth--;
      return v;
    }
    return this.compare();
  }

  private compare(): Ast {
    let a = this.concat();
    for (;;) {
      if (this.peek('id', 'in')) {
        this.pos++;
        a = ['in', a, this.concat()];
      } else if (this.peek('op') && ['==', '!=', '<', '<=', '>', '>='].includes(this.toks[this.pos].v as string)) {
        const op = this.take().v as string;
        a = [op, a, this.concat()];
      } else break;
    }
    return a;
  }

  private concat(): Ast {
    let a = this.additive();
    while (this.peek('op', '..')) {
      this.pos++;
      a = ['..', a, this.additive()];
    }
    return a;
  }

  private additive(): Ast {
    let a = this.term();
    while (this.peek('op', '+') || this.peek('op', '-')) {
      const op = this.take().v as string;
      a = [op, a, this.term()];
    }
    return a;
  }

  private term(): Ast {
    let a = this.unary();
    while (this.peek('op', '*') || this.peek('op', '/') || this.peek('op', '%')) {
      const op = this.take().v as string;
      a = [op, a, this.unary()];
    }
    return a;
  }

  private unary(): Ast {
    if (this.peek('op', '-')) {
      this.pos++;
      if (!this.enter()) return null;
      const v = ['neg', this.unary()];
      this.depth--;
      return v;
    }
    return this.power();
  }

  private power(): Ast {
    let a = this.postfix();
    if (this.peek('op', '^')) {
      this.pos++;
      if (!this.enter()) return null;
      a = ['^', a, this.unary()];
      this.depth--;
    }
    return a;
  }

  private postfix(): Ast {
    let a = this.primary();
    while (this.peek('op', '[') || this.peek('op', '.')) {
      if (this.peek('op', '.')) {
        this.pos++;
        if (this.pos >= this.toks.length || this.toks[this.pos].t !== 'id') {
          this.error = "a field name after '.'";
          return null;
        }
        a = ['index', a, ['lit', String(this.take().v)]];
        continue;
      }
      this.pos++;
      if (!this.enter()) return null;
      const k = this.ternary();
      this.depth--;
      if (!this.expect(']')) return null;
      a = ['index', a, k];
    }
    return a;
  }

  private primary(): Ast {
    if (this.pos >= this.toks.length) {
      if (!this.error) this.error = 'unexpected end';
      return null;
    }
    const t = this.take();
    if (t.t === 'num' || t.t === 'str') return ['lit', t.v];
    if (t.t === 'path') {
      const p = t.v as string;
      if (!this.paths.includes(p)) this.paths.push(p);
      return ['path', p.split('.')];
    }
    if (t.t === 'id') {
      if (t.v === 'true') return ['lit', true];
      if (t.v === 'false') return ['lit', false];
      if (t.v === 'null') return ['lit', null];
      if (this.peek('op', '(')) {
        this.pos++;
        const args: Ast[] = [];
        if (!this.peek('op', ')')) {
          for (;;) {
            if (!this.enter()) return null;
            args.push(this.ternary());
            this.depth--;
            if (this.peek('op', ',')) {
              this.pos++;
              continue;
            }
            break;
          }
        }
        if (!this.expect(')')) return null;
        return ['call', t.v, args];
      }
      this.error = `unknown name '${t.v}' (paths start with @)`;
      return null;
    }
    if (t.t === 'op') {
      if (t.v === '(') {
        if (!this.enter()) return null;
        const inner = this.ternary();
        this.depth--;
        if (!this.expect(')')) return null;
        return inner;
      }
      if (t.v === '[') {
        const items: Ast[] = [];
        if (!this.peek('op', ']')) {
          for (;;) {
            if (!this.enter()) return null;
            items.push(this.ternary());
            this.depth--;
            if (this.peek('op', ',')) {
              this.pos++;
              continue;
            }
            break;
          }
        }
        if (!this.expect(']')) return null;
        return ['call', '__list', items];
      }
    }
    if (!this.error) this.error = `unexpected '${t.v}'`;
    return null;
  }
}
