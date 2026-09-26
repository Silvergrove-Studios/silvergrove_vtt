// What the widgets of a view need from the page they are on: where an
// intent goes (and a pick, for one that wants a target on the map), where
// compendium pages come from, and where pictures are.
import { getContext, setContext } from 'svelte';
import type { Dict } from './viewlib';

export interface ViewUi {
  intent(payload: Dict): void;
  /** An intent whose answer the page waits for, a form's: done, or refused and why. Without it a form's intent goes as any other. */
  submit?(payload: Dict): Promise<{ ok: boolean; why?: string }>;
  pick(payload: Dict): void;
  comp(collection: string, req: Dict): Promise<Dict>;
  picture(ref: string): string;
}

const KEY = Symbol('view-ui');

export function provideViewUi(ui: ViewUi): void {
  setContext(KEY, ui);
}

export function viewUi(): ViewUi {
  return (
    getContext<ViewUi>(KEY) ?? {
      intent: () => {},
      pick: () => {},
      comp: async () => ({ error: 'no compendium here' }),
      picture: () => '',
    }
  );
}
