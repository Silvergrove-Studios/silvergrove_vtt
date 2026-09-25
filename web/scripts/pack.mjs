// The built web clients (dist/) as one zip at the project's root,
// webclient.zip, which the Hexmap host serves and the exports carry as it
// is (a folder of fonts and images would be imported by Godot instead).
// Entries are stored in a fixed order with a fixed date, so an unchanged
// build makes an unchanged zip.
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { zipSync } from 'fflate';

const here = fileURLToPath(new URL('.', import.meta.url));
const dist = join(here, '..', 'dist');
const out = join(here, '..', '..', 'webclient.zip');

function walk(dir) {
  return readdirSync(dir)
    .sort()
    .flatMap((name) => {
      const p = join(dir, name);
      return statSync(p).isDirectory() ? walk(p) : [p];
    });
}

const files = {};
const mtime = new Date('2026-01-01T00:00:00Z');
for (const p of walk(dist)) {
  const rel = relative(dist, p).split(sep).join('/');
  // already-compressed files are stored as they are
  const level = /\.(woff2?|png|jpe?g|webp|gif)$/i.test(rel) ? 0 : 9;
  files[rel] = [readFileSync(p), { level, mtime }];
}
const zip = zipSync(files);
writeFileSync(out, zip);
console.log(`webclient.zip: ${Object.keys(files).length} files, ${(zip.length / 1024).toFixed(0)} KB`);
