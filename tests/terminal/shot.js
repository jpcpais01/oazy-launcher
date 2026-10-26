// Renders Oazy Terminal's page with the pretend host, for a look without
// Windows: node tests/terminal/shot.js <out dir>
const { chromium } = require('playwright');
const path = require('path');
(async () => {
	const out = process.argv[2] || '.';
	// Lay the page out the way Oazy unpacks it: fonts ship as .woff2.bin (so
	// Godot packs them untouched) and land in ui/fonts as .woff2.
	const fs = require('fs'), os = require('os');
	const ui = fs.mkdtempSync(path.join(os.tmpdir(), 'oazy-term-'));
	fs.cpSync(path.resolve(__dirname, '../../native/terminal/ui'), ui, { recursive: true });
	fs.mkdirSync(path.join(ui, 'fonts'));
	const fonts = path.resolve(__dirname, '../../native/terminal/fonts');
	for (const f of fs.readdirSync(fonts)) if (f.endsWith('.woff2.bin')) fs.copyFileSync(path.join(fonts, f), path.join(ui, 'fonts', f.slice(0, -4)));
	const browser = await chromium.launch({ });
	const page = await browser.newPage({ viewport: { width: 1100, height: 680 }, deviceScaleFactor: 1.5 });
	page.on('console', m => console.log('console:', m.text()));
	page.on('pageerror', e => console.log('PAGE ERROR:', e.message));
	await page.addInitScript({ path: path.join(__dirname, 'mock.js') });
	// A desktop-ish backdrop stands in for the acrylic behind the window.
	await page.addInitScript(() => document.addEventListener('DOMContentLoaded', () => {
		document.documentElement.style.background = 'radial-gradient(120% 90% at 20% 10%, #1d6b78, #0b2733 55%, #061219)';
	}));
	await page.goto('file://' + ui + '/term.html');
	await page.waitForTimeout(800);
	const type = async s => { await page.keyboard.type(s); await page.keyboard.press('Enter'); await page.waitForTimeout(200); };
	await type('demo');
	await page.screenshot({ path: path.join(out, '1-tab.png') });
	await page.keyboard.press('Alt+Shift+Equal');
	await page.waitForTimeout(500);
	await page.keyboard.press('Control+Shift+Digit3');
	await page.waitForTimeout(500);
	await page.keyboard.press('Control+Shift+Digit6');
	await page.waitForTimeout(500);
	await page.keyboard.press('Control+Alt+Digit1');
	await page.waitForTimeout(400);
	await page.screenshot({ path: path.join(out, '2-split.png') });
	await page.keyboard.press('Control+Shift+KeyF');
	await page.keyboard.type('Claude');
	await page.waitForTimeout(400);
	await page.screenshot({ path: path.join(out, '3-find.png') });
	await page.keyboard.press('Escape');
	await page.click('#profiles-btn');
	await page.waitForTimeout(400);
	await page.screenshot({ path: path.join(out, '4-profiles.png') });
	await page.keyboard.press('Escape');
	await page.keyboard.press('Control+Comma');
	await page.waitForTimeout(400);
	await page.screenshot({ path: path.join(out, '5-settings.png') });
	await page.keyboard.press('Escape');
	await page.mouse.click(300, 300, { button: 'right' });
	await page.waitForTimeout(400);
	await page.screenshot({ path: path.join(out, '6-context.png') });
	await browser.close();
})();
