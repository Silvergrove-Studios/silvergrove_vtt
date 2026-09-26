<!--
  A picture into a note (the team: journals with pictures): chosen from
  the phone or the computer, made smaller here, kept by the table, and put
  where the cursor is in the text as ![caption](upload:<id>) — the note
  shows it wherever it is read.
-->
<script lang="ts">
  import { notice, uploadPicture } from '../lib/game.svelte';
  import { prepare, withPicture } from '../lib/pictures';

  let {
    target,
    onvalue,
    label = 'Add a picture',
  }: { target: HTMLTextAreaElement | undefined; onvalue: (text: string) => void; label?: string } = $props();

  let busy = $state(false);
  let input: HTMLInputElement | undefined = $state();

  async function picked(e: Event): Promise<void> {
    const f = (e.currentTarget as HTMLInputElement).files?.[0] ?? null;
    (e.currentTarget as HTMLInputElement).value = '';
    if (!f) return;
    if (f.size > 40 * 1024 * 1024) {
      notice('That picture is too big to open here', 'error');
      return;
    }
    const at = target?.selectionStart ?? target?.value.length ?? 0;
    busy = true;
    try {
      const r = await uploadPicture('picture', await prepare(f, 'picture'));
      if (!r.ref) {
        notice(r.why ?? 'The table did not keep it', 'error');
        return;
      }
      const put = withPicture(target?.value ?? '', at, r.ref);
      if (target) {
        target.value = put.text;
        target.focus();
        target.setSelectionRange(put.cursor, put.cursor);
      }
      onvalue(put.text);
    } catch (err) {
      notice(`That picture could not be used: ${String((err as Error)?.message ?? err)}`, 'error');
    } finally {
      busy = false;
    }
  }
</script>

<button type="button" class="quiet add-picture" disabled={busy || !target} onclick={() => input?.click()}>{busy ? 'Sending the picture…' : `＋ ${label}`}</button>
<input bind:this={input} class="file" type="file" accept="image/*" aria-label={label} onchange={picked} />

<style>
  .add-picture {
    align-self: flex-start;
  }
  .file {
    display: none;
  }
</style>
