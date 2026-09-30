// A clock the screens count down by: a reaction's card has its seconds (the
// table sends how many are left with each view; the page counts on from
// there). Twice a second is enough for whole seconds.
export const clock = $state({ now: typeof performance !== 'undefined' ? performance.now() : 0 });

if (typeof window !== 'undefined' && typeof setInterval !== 'undefined') {
  setInterval(() => (clock.now = performance.now()), 500);
}
