// What of the chat a screen has not read: the lines after the last one it
// read, which this browser keeps for the table and the seat. (The count
// started from nothing on each page load: after a reload a playtest's
// badge said 279.)
import type { Dict } from './game.svelte';

/** The ids of the chat's messages and rolls, oldest first: what the Chat & rolls badge counts. */
export function chatIds(entries: Dict[]): string[] {
  return entries.filter((e) => e && (e.kind === 'chat' || e.kind === 'roll') && e.id != null && e.id !== '').map((e) => String(e.id));
}

/** How many lines came after the last one read: 0 when it is not among them
 * (read long ago, or elsewhere); every one when nothing had been said yet
 * when the count began (""). */
export function unreadAfter(ids: string[], lastRead: string): number {
  if (lastRead === '') return ids.length;
  const i = ids.lastIndexOf(lastRead);
  return i < 0 ? 0 : ids.length - 1 - i;
}

/** Where a page starts counting: the line it read last time, if the chat still
 * has it; else the newest (a browser new to the table has nothing new to it). */
export function startFrom(ids: string[], kept: string): string {
  return kept !== '' && ids.includes(kept) ? kept : (ids[ids.length - 1] ?? '');
}

/** Where this browser keeps it, for a table and a seat (a player's id, or "dm"). */
export function readKey(table: string, seat: string): string {
  return `hexmap.read/${table}/${seat}`;
}

export function loadRead(table: string, seat: string): string {
  try {
    return localStorage.getItem(readKey(table, seat)) ?? '';
  } catch {
    return '';
  }
}

export function saveRead(table: string, seat: string, id: string): void {
  try {
    localStorage.setItem(readKey(table, seat), id);
  } catch {
    /* private mode */
  }
}
