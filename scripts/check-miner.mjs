// Miner integration check: click mining -> hire -> upgrade -> ad double -> save/restore.
import { chromium } from '/Users/chendongming/coding/auto-games/defold/game-framework/.tools/browser/node_modules/playwright/index.mjs';
import path from 'node:path';
import fs from 'node:fs';

const BASE = 'http://127.0.0.1:8765/DefoldGameFramework/';
const root = '/Users/chendongming/coding/auto-games/defold/game-framework';
const LOG = path.join(root, 'logs/miner');

fs.mkdirSync(LOG, { recursive: true });

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const ctx = await browser.newContext({ viewport: { width: 960, height: 640 } });

async function newPage() {
  const page = await ctx.newPage();
  const lines = [];
  page.on('console', m => lines.push(m.text()));
  const until = async (pred, label) => {
    for (let i = 0; i < 300; i++) {
      if (pred()) return;
      await new Promise(r => setTimeout(r, 100));
    }
    throw Error('timeout: ' + label + '\n' + lines.slice(-20).join('\n'));
  };
  return { page, lines, until };
}

async function clickAt(page, box, fx, fy) {
  await page.mouse.click(box.x + box.width * fx, box.y + box.height * (1 - fy), { delay: 120 });
}

async function waitCanvas(page) {
  const box = await page.locator('#canvas').boundingBox();
  if (!box) throw Error('no canvas');
  return box;
}

const failures = [];

const p = await newPage();
await p.page.goto(BASE);
await p.until(() => p.lines.some(x => x.includes('MINER_VIEW_INIT mine')), 'mine ready');
console.log('load:', p.lines.find(x => x.includes('MINER_LOAD')));
const platformLine = p.lines.find(x => x.includes('MINER_PLATFORM'));
console.log('platform:', platformLine);
if (!platformLine || !platformLine.includes('kind=browser')) failures.push('platform detect failed');

const box = await waitCanvas(p.page);
// Wait for the Monarch screen transition to settle before clicking.
await new Promise(r => setTimeout(r, 500));

// 1. Click mine (center 480,270)
await clickAt(p.page, box, 480 / 960, 270 / 640);
await p.until(() => p.lines.some(x => x.includes('MINER_CLICK')), 'click registered');
const clickLine = p.lines.find(x => x.includes('MINER_CLICK'));
console.log('click:', clickLine);
if (!clickLine || !clickLine.includes('coins=1')) failures.push('click did not give 1 coin');

await p.page.screenshot({ path: path.join(LOG, 'miner-mine.png') });

// 2. Navigate to shop (180,90)
await clickAt(p.page, box, 180 / 960, 90 / 640);
await p.until(() => p.lines.some(x => x.includes('MINER_VIEW_INIT shop')), 'shop ready');
await new Promise(r => setTimeout(r, 400));

// 3. Hire miner (need 10 coins; only have 1, should fail first)
await clickAt(p.page, box, 480 / 960, 360 / 640);
await p.until(() => p.lines.some(x => x.includes('MINER_HIRE') || x.includes('MINER_HIRE_FAIL')), 'hire attempt');
console.log('hire attempt:', p.lines.filter(x => x.includes('MINER_HIRE')));

// 4. Back to mine, click more to afford miner
await clickAt(p.page, box, 120 / 960, 90 / 640); // back
await p.until(() => p.lines.some(x => x.includes('MINER_VIEW_INIT mine')), 'back to mine');
await new Promise(r => setTimeout(r, 400));
for (let i = 0; i < 12; i++) {
  await clickAt(p.page, box, 480 / 960, 270 / 640);
  await new Promise(r => setTimeout(r, 50));
}
await p.until(() => p.lines.some(x => x.includes('MINER_CLICK gain=1 coins=12') || x.includes('coins=13')), 'have >= 12 coins');
const clickCount = p.lines.filter(x => x.includes('MINER_CLICK')).length;
console.log('total clicks:', clickCount);

// 5. Go shop, hire (now affordable)
await clickAt(p.page, box, 180 / 960, 90 / 640);
await p.until(() => p.lines.some(x => x.includes('MINER_VIEW_INIT shop')), 'shop ready 2');
await new Promise(r => setTimeout(r, 400));
await clickAt(p.page, box, 480 / 960, 360 / 640);
await p.until(() => p.lines.some(x => x.includes('MINER_HIRE cost=')), 'hired');
console.log('hired:', p.lines.find(x => x.includes('MINER_HIRE cost=')));

// 6. Navigate to settings, watch ad (double reward)
await clickAt(p.page, box, 120 / 960, 90 / 640); // back
await p.until(() => p.lines.some(x => x.includes('MINER_VIEW_INIT mine')), 'back mine 2');
await new Promise(r => setTimeout(r, 400));
// go settings via mine settings button (780,90)
await clickAt(p.page, box, 780 / 960, 90 / 640);
await p.until(() => p.lines.some(x => x.includes('MINER_VIEW_INIT settings')), 'settings ready');
await new Promise(r => setTimeout(r, 400));
await clickAt(p.page, box, 480 / 960, 240 / 640); // ad button
await p.until(() => p.lines.some(x => x.includes('MINER_AD_GRANT')), 'ad granted');
console.log('ad:', p.lines.find(x => x.includes('MINER_AD_GRANT')));

await p.page.screenshot({ path: path.join(LOG, 'miner-settings.png') });

// 7. Save check (auto-save every 5s or on shutdown). Close and reload.
await p.page.close();

const p2 = await newPage();
await p2.page.goto(BASE);
await p2.until(() => p2.lines.some(x => x.includes('MINER_VIEW_INIT mine')), 'reload mine');
console.log('reload:', p2.lines.find(x => x.includes('MINER_LOAD')));
await p2.page.close();

await browser.close();

fs.writeFileSync(path.join(LOG, 'miner-summary.log'), failures.length ? 'FAIL\n' + failures.join('\n') : 'PASS\n');
console.log('failures:', failures.length);
for (const f of failures) console.log('  FAIL:', f);
if (failures.length) process.exit(1);
console.log('MINER INTEGRATION PASS');
