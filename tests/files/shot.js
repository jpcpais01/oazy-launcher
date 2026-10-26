// Renders Oazy Files' page with the pretend host, for a look without
// Windows: node tests/files/shot.js <out dir>
const { chromium } = require('playwright');
const path = require('path');

// Stand-ins for Windows' icons and thumbnails: pictures get a gradient
// "photo", everything else a coloured tile.
function fakeIcon(url) {
	const u = new URL(url);
	const p = decodeURIComponent(u.searchParams.get('p') || '');
	const th = u.searchParams.get('th') === '1';
	const ext = (p.match(/\.[^.\\]+$/) || [''])[0].toLowerCase();
	let h = 0;
	for (const c of p) h = (h * 31 + c.charCodeAt(0)) % 360;
	if (th && /\.(jpg|jpeg|png|mp4)$/.test(ext)) {
		const wide = ext === '.mp4' || h % 3 === 0;
		const w = wide ? 160 : 120, ht = wide ? 90 : 120;
		return '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + ht + '"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="hsl(' + h + ',70%,62%)"/><stop offset="1" stop-color="hsl(' + ((h + 60) % 360) + ',60%,28%)"/></linearGradient></defs>' +
			'<rect width="100%" height="100%" fill="url(#g)"/><circle cx="' + (w * 0.7) + '" cy="' + (ht * 0.32) + '" r="' + (ht * 0.13) + '" fill="#fff" opacity=".85"/><path d="M0 ' + ht + ' L' + (w * 0.35) + ' ' + (ht * 0.45) + ' L' + (w * 0.6) + ' ' + (ht * 0.75) + ' L' + (w * 0.75) + ' ' + (ht * 0.6) + ' L' + w + ' ' + ht + 'Z" fill="rgba(0,0,0,.35)"/>' +
			(ext === '.mp4' ? '<circle cx="' + w / 2 + '" cy="' + ht / 2 + '" r="14" fill="rgba(0,0,0,.45)"/><path d="M' + (w / 2 - 5) + ' ' + (ht / 2 - 8) + 'l13 8-13 8z" fill="#fff"/>' : '') + '</svg>';
	}
	const look = {
		'.exe': ['#5aa7f0', '#1d4f9e', 'APP'], '.zip': ['#ffd27a', '#c98a1c', 'ZIP'], '.pdf': ['#ff8a7a', '#c9392b', 'PDF'], '.txt': ['#e7edf2', '#9aa7b4', 'TXT'],
		'.docx': ['#6ea8ff', '#2b5cc4', 'W'], '.xlsx': ['#5fd39a', '#1f7a45', 'X'], '.flac': ['#ff9fd2', '#c4448a', '♪'], '.json': ['#6fe3cf', '#1f9a8a', '{ }'],
		'.md': ['#c6d0d9', '#5d6d7c', 'MD'], '.gd': ['#7fb5ff', '#3a5fa8', 'GD'], '.godot': ['#7fb5ff', '#3a5fa8', 'G'], '.ttf': ['#d7c2ff', '#7d4fd6', 'Aa'],
	}[ext] || ['#c6d0d9', '#6d7a88', ext.slice(1, 4).toUpperCase()];
	return '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="' + look[0] + '"/><stop offset="1" stop-color="' + look[1] + '"/></linearGradient></defs>' +
		'<path d="M14 5h24l13 13v38a3 3 0 0 1-3 3H14a3 3 0 0 1-3-3V8a3 3 0 0 1 3-3z" fill="#f4f7fa"/><path d="M38 5v10a3 3 0 0 0 3 3h10z" fill="#c9d3dc"/>' +
		'<rect x="16" y="28" width="30" height="22" rx="4" fill="url(#g)"/><text x="31" y="43.5" text-anchor="middle" font-family="Segoe UI,Arial" font-weight="700" font-size="' + (look[2].length > 2 ? 9 : 11) + '" fill="#fff">' + look[2] + '</text></svg>';
}

(async () => {
	const out = process.argv[2] || '.';
	const browser = await chromium.launch({});
	const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1.5 });
	page.on('console', m => console.log('console:', m.text()));
	page.on('pageerror', e => console.log('PAGE ERROR:', e.message));
	await page.route('https://oazy-icons.example/**', r => r.fulfill({ status: 200, contentType: 'image/svg+xml', body: fakeIcon(r.request().url()) }));
	await page.addInitScript({ path: path.join(__dirname, 'mock.js') });
	await page.addInitScript(() => {
		window.__oazyTabs = ['C:\\Users\\joao\\Downloads', ''];
		document.addEventListener('DOMContentLoaded', () => {
			document.documentElement.style.background = 'radial-gradient(120% 90% at 20% 10%, #1d6b78, #0b2733 55%, #061219)';
		});
	});
	await page.goto('file://' + path.resolve(__dirname, '../../native/files/ui/files.html'));
	await page.waitForTimeout(900);
	const shot = async (name) => { await page.waitForTimeout(450); await page.screenshot({ path: path.join(out, name) }); };
	// Downloads in icons, a few picked.
	await page.click('.item:nth-child(3)');
	await page.click('.item:nth-child(5)', { modifiers: ['Control'] });
	await shot('1-grid.png');
	// Details view with the details pane.
	await page.keyboard.press('Escape');
	await page.click('#viewseg button[data-view=list]');
	await page.click('#details-btn');
	await page.click('.item:nth-child(4)');
	await shot('2-list-details.png');
	await page.click('#details-btn');
	await page.click('#viewseg button[data-view=grid]');
	// Right-click menu on a file.
	await page.click('.item:nth-child(6)', { button: 'right' });
	await shot('3-menu.png');
	await page.keyboard.press('Escape');
	// Pictures, thumbnails.
	await page.click('.side-item[title$="Pictures"]');
	await shot('4-pictures.png');
	// Search.
	await page.click('#search-in');
	await page.keyboard.type('IMG_2028');
	await page.waitForTimeout(600);
	await shot('5-search.png');
	await page.keyboard.press('Escape');
	// Home tab.
	await page.click('.tab:nth-child(2)');
	await shot('6-home.png');
	// Rename and new folder in the repo.
	await page.click('.tab:nth-child(1)');
	await page.click('#addr-in', { force: true }).catch(() => {});
	await page.keyboard.press('Control+L');
	await page.keyboard.type('C:\\Users\\joao\\oazy-launcher');
	await page.keyboard.press('Enter');
	await page.waitForTimeout(400);
	await page.keyboard.press('Control+Shift+N');
	await shot('7-new-folder.png');
	await page.keyboard.press('Enter');
	await page.click('#settings-btn');
	await shot('8-settings.png');
	await browser.close();
})();
