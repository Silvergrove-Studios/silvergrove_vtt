// A look inside a running page: what it knows (for working on the web client).
import { chromium } from 'playwright-core';
import { readFileSync } from 'node:fs';
const [infoPath, which, expr] = process.argv.slice(2);
const info = JSON.parse(readFileSync(infoPath, 'utf8'));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await (await browser.newContext()).newPage();
await page.goto(which === 'dm' ? info.dm : info.player);
await page.waitForTimeout(2500);
console.log(JSON.stringify(await page.evaluate(expr), null, 1));
await browser.close();
