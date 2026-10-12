// Renders an HTML scene frame by frame through Chrome's DevTools protocol.
// Used by make.sh. usage: node render.mjs <scene.html> <outdir> <seconds> <fps>
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
const [,, scene, outdir, secs, fps] = process.argv;
const N = Math.round(+secs * +fps);
mkdirSync(outdir, { recursive: true });
const port = 9300 + Math.floor(Math.random() * 500);
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', `--remote-debugging-port=${port}`, '--hide-scrollbars', '--disable-gpu',
  '--window-size=900,1200', `--user-data-dir=/tmp/cdp-${port}`, 'about:blank'], { stdio: 'ignore' });
const sleep = ms => new Promise(r => setTimeout(r, ms));
let targets;
for (let i = 0; i < 50; i++) { try { targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); break; } catch { await sleep(200); } }
const page = targets.find(t => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r));
let id = 0; const pending = new Map();
ws.addEventListener('message', ev => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 900, height: 1200, deviceScaleFactor: 1, mobile: false });
await send('Page.navigate', { url: 'file://' + resolve(scene) });
await sleep(800);
for (let f = 0; f < N; f++) {
  await send('Runtime.evaluate', { expression: `setFrame(${f / N}, ${+secs})` });
  const r = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 900, height: 1200, scale: 1 } });
  writeFileSync(`${outdir}/f${String(f).padStart(4, '0')}.png`, Buffer.from(r.result.data, 'base64'));
}
ws.close(); chrome.kill();
console.log('frames', N);
