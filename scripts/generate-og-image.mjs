import { chromium } from 'playwright';
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const htmlPath = resolve(__dirname, 'og-image.html');
const outputPath = resolve(__dirname, '..', 'site', 'og-image.png');

const browser = await chromium.launch();
const page = await browser.newPage();
await page.setViewportSize({ width: 1200, height: 630 });
await page.goto(`file://${htmlPath}`);
await page.waitForLoadState('networkidle');
await page.screenshot({ path: outputPath, type: 'png' });
await browser.close();

console.log(`OG image saved to ${outputPath}`);
