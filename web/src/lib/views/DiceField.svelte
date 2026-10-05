<!--
  Real dice typed in (a card's `dice` field): a box a die, each its die's
  faces (d20, d8…), the total as it's typed. A face that can't grow another
  digit moves on to the next box (eight d6s are eight taps); Backspace in an
  empty box goes back. A face its die can't show is marked, not taken.
-->
<script lang="ts">
  import { diceTotal, faceDone, faceOf, maxDigits, sidesOf, startingDice, type DiceValue } from '../dice';
  import type { Dict } from './viewlib';

  let { field, value = $bindable() }: { field: Dict; value: any } = $props();

  const sides = $derived(sidesOf(field));
  // what each box shows, as typed (a face typed wrong stays, to be put right)
  // svelte-ignore state_referenced_locally
  let texts = $state<string[]>(startingDice(field, value).map((f) => (f === null ? '' : String(f))));
  let boxes: HTMLInputElement[] = $state([]);
  const total = $derived(diceTotal(field, value));
  const plus = $derived(Number(field?.plus ?? 0) || 0);

  // each box's face (a d10's 0 its 10), or the number typed when its die can't
  // show it (the check says so), or null while it's empty
  function parsed(): DiceValue {
    return sides.map((s, k) => {
      const typed = texts[k] ?? '';
      return /^\d+$/.test(typed) ? (faceOf(typed, s) ?? Number(typed)) : null;
    });
  }

  // the boxes follow the value when it comes from elsewhere: a new card in this
  // place starts from its own dice (the DM's damage card came up after the d20's
  // showing the d20's face), not the last card's
  $effect.pre(() => {
    const want = startingDice(field, value);
    if (texts.length !== sides.length || JSON.stringify(want) !== JSON.stringify(parsed())) texts = want.map((f) => (f === null ? '' : String(f)));
  });

  function put(i: number, text: string): void {
    const t = text.replace(/[^0-9]/g, '').slice(0, maxDigits(sides[i]));
    texts[i] = t;
    value = parsed();
    if (faceDone(t, sides[i]) && i + 1 < sides.length) boxes[i + 1]?.focus();
  }

  function key(i: number, e: KeyboardEvent): void {
    if (e.key === 'Backspace' && (texts[i] ?? '') === '' && i > 0) {
      e.preventDefault();
      boxes[i - 1]?.focus();
    }
  }
</script>

<div class="dice" role="group" aria-label={String(field.label ?? 'Dice')}>
  <div class="boxes">
    {#each sides as s, i (i)}
      <input
        bind:this={boxes[i]}
        class="die"
        class:bad={(texts[i] ?? '') !== '' && faceOf(texts[i], s) === null}
        type="text"
        inputmode="numeric"
        pattern="[0-9]*"
        autocomplete="off"
        maxlength={maxDigits(s)}
        placeholder={`d${s}`}
        aria-label={`d${s}${sides.length > 1 ? ` (${i + 1} of ${sides.length})` : ''}`}
        value={texts[i] ?? ''}
        oninput={(e) => put(i, (e.currentTarget as HTMLInputElement).value)}
        onkeydown={(e) => key(i, e)}
      />
    {/each}
  </div>
  <span class="total" aria-live="polite">
    {#if total !== null}= {total}{:else if plus !== 0}{plus > 0 ? '+' : '−'}{Math.abs(plus)}{/if}
  </span>
</div>

<style>
  .dice {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px 10px;
  }
  .boxes {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .die {
    width: 3.2em;
    min-height: 40px;
    text-align: center;
    font-variant-numeric: tabular-nums;
    font-size: 1.1rem;
  }
  .die.bad {
    border-color: var(--danger, #d9534f);
    color: var(--danger, #d9534f);
  }
  .total {
    font-family: var(--font-display);
    font-size: 1.3rem;
    font-weight: 600;
    color: var(--accent);
    font-variant-numeric: tabular-nums;
  }
</style>
