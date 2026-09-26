// Pictures the people at the table add (the team, after the character
// maker): a token's, a journal's. Made smaller here before they go — a
// token's cut to the square the player chose, 512 across; a journal's
// 1600 on its longer side — and encoded again (WebP, else JPEG), which
// also leaves a phone photo's location and camera notes behind. The Table
// checks and keeps them; a kept one is `upload:<id>`, at /upload/<id>.webp.

export const TOKEN_SIZE = 512;
export const PICTURE_SIZE = 1600;

/** A square part of an image, in its own pixels. */
export interface Crop {
  x: number;
  y: number;
  size: number;
}

export function isUpload(ref: string): boolean {
  return /^upload:[0-9a-f]{32}$/.test(ref);
}

/** Where an uploaded picture is (a ref that is not one: ""). */
export function uploadUrl(ref: string): string {
  return isUpload(ref) ? `/upload/${ref.slice(7)}.webp` : '';
}

/** The square in the middle of a w × h image. */
export function middleSquare(w: number, h: number): Crop {
  const size = Math.min(w, h);
  return { x: (w - size) / 2, y: (h - size) / 2, size };
}

/** The size a picture is sent at: no larger than `max` on its longer side. */
export function fitted(w: number, h: number, max: number): [number, number] {
  const k = Math.min(1, max / Math.max(w, h, 1));
  return [Math.max(1, Math.round(w * k)), Math.max(1, Math.round(h * k))];
}

/** A picture file as the browser can draw it (its orientation as the photo says). */
export async function loadBitmap(file: Blob): Promise<ImageBitmap> {
  try {
    return await createImageBitmap(file, { imageOrientation: 'from-image' });
  } catch {
    return await createImageBitmap(file);
  }
}

function toBlob(cv: HTMLCanvasElement, type: string, quality: number): Promise<Blob | null> {
  return new Promise((resolve) => cv.toBlob(resolve, type, quality));
}

function toBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).replace(/^data:[^,]*,/, ''));
    r.onerror = () => reject(r.error);
    r.readAsDataURL(blob);
  });
}

/** A picture made ready to send: base64 of a WebP (or JPEG where the
 * browser cannot write WebP), a token's cut to `crop` (or the middle). */
export async function prepare(file: Blob, kind: 'token' | 'picture', crop?: Crop): Promise<string> {
  const bmp = await loadBitmap(file);
  let sx = 0;
  let sy = 0;
  let sw = bmp.width;
  let sh = bmp.height;
  if (kind === 'token') {
    const c = crop ?? middleSquare(bmp.width, bmp.height);
    sx = c.x;
    sy = c.y;
    sw = sh = c.size;
  }
  const [w, h] = fitted(sw, sh, kind === 'token' ? TOKEN_SIZE : PICTURE_SIZE);
  const cv = document.createElement('canvas');
  cv.width = w;
  cv.height = h;
  const g = cv.getContext('2d')!;
  g.imageSmoothingQuality = 'high';
  g.drawImage(bmp, sx, sy, sw, sh, 0, 0, w, h);
  bmp.close?.();
  let blob = await toBlob(cv, 'image/webp', 0.86);
  if (!blob || blob.type !== 'image/webp') blob = await toBlob(cv, 'image/jpeg', 0.88);
  if (!blob) throw new Error('this browser could not make the picture smaller');
  return toBase64(blob);
}

/** Put a picture into a note's text where the cursor is, on a line of its
 * own: the new text, and where the cursor goes after it. */
export function withPicture(text: string, at: number, ref: string, caption = ''): { text: string; cursor: number } {
  const i = Math.max(0, Math.min(at, text.length));
  const before = text.slice(0, i);
  const after = text.slice(i);
  const lead = before === '' || before.endsWith('\n\n') ? '' : before.endsWith('\n') ? '\n' : '\n\n';
  const trail = after === '' || after.startsWith('\n\n') ? '' : after.startsWith('\n') ? '\n' : '\n\n';
  const snippet = `${lead}![${caption.replace(/[[\]\n]/g, ' ').trim()}](${ref})${trail}`;
  return { text: before + snippet + after, cursor: before.length + snippet.length };
}
