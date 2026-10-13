// render mermaid เป็น PNG (ฟอนต์ไทย Noto Sans Thai) · ใช้: bun render_mermaid.mjs in.mmd out.png
// ต้องมี playwright + chromium และ mermaid ใน ~/dev/**/node_modules (script หาเอง)
import fs from "node:fs";
import { execSync } from "node:child_process";
const find = (pat) => execSync(`ls -d ${pat} 2>/dev/null | head -1`, { shell: "/bin/bash" }).toString().trim();
// เลือก playwright ตัวที่ browser เวอร์ชันตรงกับที่ติดตั้งไว้ใน ~/.cache/ms-playwright (แต่ละ repo pin คนละเวอร์ชัน)
const cache = `${process.env.HOME}/.cache/ms-playwright`;
const installed = fs.existsSync(cache) ? fs.readdirSync(cache) : [];
const pw = execSync(`ls -d $HOME/dev/*/node_modules/playwright $HOME/dev/*/*/node_modules/playwright 2>/dev/null || true`, { shell: "/bin/bash" })
  .toString().split("\n").filter(Boolean).map((d) => {
    const bj = [`${d}/../playwright-core/browsers.json`, `${d}/node_modules/playwright-core/browsers.json`].find((f) => fs.existsSync(f));
    if (!bj) return null;
    const rev = JSON.parse(fs.readFileSync(bj, "utf8")).browsers.find((b) => b.name === "chromium-headless-shell")?.revision;
    return installed.includes(`chromium_headless_shell-${rev}`) ? `${d}/index.mjs` : null;
  }).find(Boolean);
const mm = find(`$HOME/dev/*/node_modules/mermaid/dist/mermaid.min.js $HOME/dev/*/*/node_modules/mermaid/dist/mermaid.min.js`);
if (!pw || !mm) { console.error("ไม่พบ playwright (ที่ browser ติดตั้งแล้ว) หรือ mermaid ใน ~/dev/**/node_modules · ติดตั้ง browser: bunx playwright install chromium"); process.exit(2); }
const { chromium } = await import(pw);
const [inFile, outFile] = process.argv.slice(2);
const code = fs.readFileSync(inFile, "utf8");
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 1600, height: 1200 } });
await page.setContent(`<html><body style="margin:0;background:#fff"><div id="out"></div></body></html>`);
await page.addScriptTag({ content: fs.readFileSync(mm, "utf8") });
await page.evaluate(async (code) => {
  mermaid.initialize({ startOnLoad: false, theme: "default",
    themeVariables: { fontFamily: "Noto Sans Thai, sans-serif", fontSize: "15px" },
    flowchart: { useMaxWidth: false }, er: { useMaxWidth: false }, sequence: { useMaxWidth: false } });
  const { svg } = await mermaid.render("m" + Date.now(), code);
  document.getElementById("out").innerHTML = `<div id="wrap" style="display:inline-block;padding:16px;background:#fff">${svg}</div>`;
}, code);
await (await page.$("#wrap")).screenshot({ path: outFile });
await browser.close();
console.log(outFile);
