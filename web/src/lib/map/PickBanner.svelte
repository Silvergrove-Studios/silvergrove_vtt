<!--
  What a waiting pick says over the map, and the creatures it can take as
  buttons, by name and map label, to choose without tapping the canvas: a
  screen reader can't tap one, and a playtest's agents, playing through the
  page's structure, fought line of sight far harder than people did. One
  creature is chosen and Done; several (Bless) are chosen and unchosen;
  darts (Magic Missile's) go one to a press, the same creature again for
  another. After them, those it can't take, each saying why and not to be
  pressed ("Marcus Vell — can't see: a wall is in the way": a playtest's
  Haste found the fighter missing from the list, and nothing said why).
  "No target: just roll" sends the intent with none: the rolls are made and
  nothing applied (theatre of the mind).
-->
<script lang="ts">
  import type { PickChoice } from './pick';

  interface Props {
    /** what the pick asks */
    words: string;
    /** the creatures it can take, nearest first, then those it can't, each with why ([] for a space or an area) */
    choices: PickChoice[];
    /** those chosen so far: for darts, one entry a dart */
    picked: string[];
    /** how many it takes */
    many: number;
    /** what each of several is when one creature may have more ("dart"), else '' */
    each: string;
    /** what has been chosen, in words */
    status: string;
    /** "No target: just roll" is offered */
    noTarget: boolean;
    onChoose: (target: string) => void;
    onUnchoose: (target: string) => void;
    onDone: () => void;
    onCancel: () => void;
    onNoTarget: () => void;
  }

  let { words, choices, picked, many, each, status, noTarget, onChoose, onUnchoose, onDone, onCancel, onNoTarget }: Props = $props();
  const times = (target: string) => picked.filter((x) => x === target).length;
  const can = $derived(choices.filter((c) => !c.why));
</script>

<div class="pickbanner" role="group" aria-label="Choose the target">
  <p class="words" role="status">{words}</p>
  {#if choices.length}
    <ul class="choices" aria-label="Creatures">
      {#each choices as c (c.target)}
        {@const n = times(c.target)}
        <li>
          {#if c.why}
            <!-- (one it can't take: said, and not to be pressed) -->
            <button type="button" class="choice off" disabled>
              {c.name}{#if c.label}<span class="label">{` (${c.label})`}</span>{/if}{#if c.party}<span class="tag">{' · party'}</span>{/if}{#if c.hidden}<span class="tag">{' · hidden'}</span>{/if}<span class="why">{` — ${c.why}`}</span>
            </button>
          {:else}
            <!-- (its name as said: "Goblin Warrior (GW1)", with "party", "hidden", "×2" after) -->
            <button type="button" class="choice" class:on={n > 0} aria-pressed={n > 0} onclick={() => onChoose(c.target)}>
              {c.name}{#if c.label}<span class="label">{` (${c.label})`}</span>{/if}{#if c.party}<span class="tag">{' · party'}</span>{/if}{#if c.hidden}<span class="tag">{' · hidden'}</span>{/if}{#if each && n > 0}<span class="n">{` ×${n}`}</span>{/if}
            </button>
            {#if each && n > 0}
              <button type="button" class="less" aria-label={`One ${each} fewer at ${c.name}`} onclick={() => onUnchoose(c.target)}>−</button>
            {/if}
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
  {#if status}<p class="status">{status}</p>{/if}
  <div class="actions">
    {#if noTarget}<button type="button" class="plain" onclick={onNoTarget}>No target: just roll</button>{/if}
    <button type="button" class="plain" onclick={onCancel}>Cancel</button>
    {#if can.length || many > 1}
      <button type="button" class="done" disabled={picked.length === 0} onclick={onDone}>Done</button>
    {/if}
  </div>
</div>

<style>
  .pickbanner {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .words,
  .status {
    margin: 0;
    line-height: 1.3;
  }
  .status {
    font-weight: 500;
    font-size: 0.92rem;
  }
  .choices {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .choices li {
    display: flex;
    align-items: center;
    gap: 2px;
  }
  .choice,
  .less,
  .plain,
  .done {
    border: 1px solid rgba(0, 0, 0, 0.55);
    border-radius: 999px;
    padding: 4px 11px;
    background: rgba(0, 0, 0, 0.8);
    color: #fff;
    font: inherit;
    font-weight: 600;
    cursor: pointer;
    min-height: 32px;
  }
  .choice {
    white-space: nowrap;
  }
  .choice.on {
    background: #fff;
    color: #1b1600;
    box-shadow: inset 0 0 0 2px #1b1600;
  }
  /* one it can't take: set apart (a light pill, a dashed edge) and still
     readable, saying why; not to be pressed */
  .choice.off,
  .choice.off:disabled {
    opacity: 1;
    background: rgba(255, 255, 255, 0.5);
    color: #3b3100;
    border: 1px dashed rgba(27, 22, 0, 0.55);
    cursor: default;
    font-weight: 600;
    white-space: normal;
    text-align: left;
  }
  .why {
    font-weight: 500;
    font-style: italic;
  }
  .label {
    font-variant-numeric: tabular-nums;
    opacity: 0.8;
    font-size: 0.85em;
  }
  .tag {
    font-weight: 500;
    font-size: 0.78em;
    opacity: 0.75;
  }
  .n {
    font-variant-numeric: tabular-nums;
  }
  .less {
    padding: 4px 9px;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 6px;
  }
  .plain {
    background: rgba(255, 255, 255, 0.35);
    color: #1b1600;
  }
  .done {
    background: #1b1600;
  }
  .done:disabled {
    opacity: 0.45;
    cursor: default;
  }
</style>
