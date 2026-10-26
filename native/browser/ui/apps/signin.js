// Google's sign-in pages in Oazy's sign-in window (and a web app's window).
// Runs in every document before the page's own code, inside a closure that
// hands it OAZY: {id, hosts, on, accent, test, css} (see WebApps.Bootstrap).
//
// The window asks Google for its dark pages (prefers-color-scheme). Once the
// page really is dark, its full-window backgrounds become a dark tint so it
// sits on the window's glass, and the card holding the form (wide windows only) turns
// into tinted glass. Everything is found by size and colour, not Google's
// class names; if the page isn't dark or can't be read, it shows as Google
// drew it, on a solid backdrop.

if (window.top !== window) return;
const host = location.hostname.toLowerCase();
if (!OAZY.hosts.some(h => host === h || host.endsWith('.' + h))) return;

let root = null;
let style = null;
let on = !!OAZY.on;
let scheduled = 0;
let observer = null;
const started = Date.now();

function accentRgb(hex) {
	const m = /^#?([0-9a-f]{6})$/i.exec(hex || '');
	const n = m ? parseInt(m[1], 16) : 0x38d6c4;
	return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function ensureStyle() {
	if (style && style.isConnected) return;
	if (!style) {
		style = document.createElement('style');
		style.id = 'oazy-signin';
		const [r, g, b] = accentRgb(OAZY.accent);
		style.textContent = ':root{--oazy-accent-rgb:' + r + ',' + g + ',' + b + '}\n' + OAZY.css;
	}
	(document.head || root).appendChild(style);
}

function rgba(c) {
	const m = /rgba?\(([^)]+)\)/.exec(c || '');
	if (!m) return null;
	const p = m[1].split(/[ ,/]+/).filter(Boolean).map(Number);
	return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1];
}

const lum = c => (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255;

// Dark when the text is light and nothing big behind it is light.
function pageIsDark() {
	if (!document.body) return false;
	const text = rgba(getComputedStyle(document.body).color);
	return !!text && lum(text) > 0.6;
}

function scan() {
	scheduled = 0;
	if (!root || !document.body) return;
	ensureStyle();
	const dark = on && pageIsDark();
	root.classList.toggle('oazy-signin', dark);
	if (!dark) return;
	const vw = innerWidth, vh = innerHeight;
	const form = document.querySelector('input[type=email], input[type=password], input[type=text], form, [role=main], main');
	for (const el of document.body.querySelectorAll('*')) {
		if (el.hasAttribute('data-oazy-clear') || el.hasAttribute('data-oazy-card')) continue;
		const cs = getComputedStyle(el);
		const bg = rgba(cs.backgroundColor);
		if (!bg || bg[3] < 0.5) continue;
		const r = el.getBoundingClientRect();
		if (r.width < 200 || r.height < 160) continue;
		// Light layers stay: clearing them would leave dark text on dark glass.
		if (lum(bg) > 0.4) continue;
		// Full-width layers are backdrops (narrow windows draw the form on one).
		if (r.width >= vw * 0.9 && r.height >= Math.min(vh * 0.5, 360)) el.setAttribute('data-oazy-clear', '');
		else if (form && el.contains(form) && r.width >= 320 && r.width < vw * 0.97) el.setAttribute('data-oazy-card', '');
	}
}

function schedule() {
	if (!scheduled) scheduled = setTimeout(scan, 120);
}

function start() {
	root = document.documentElement;
	ensureStyle();
	observer = new MutationObserver(() => {
		// The page builds itself for a while (and again at each step); after
		// that, only new parts get looked at.
		schedule();
	});
	observer.observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'style'] });
	matchMedia('(prefers-color-scheme: dark)').addEventListener('change', schedule);
	addEventListener('resize', schedule);
	schedule();
	// A few late looks while fonts and styles arrive.
	for (const t of [400, 1200, 2500]) setTimeout(schedule, t);
}

addEventListener('oazy:look', e => {
	on = !!e.detail;
	schedule();
});

if (document.documentElement) start();
else {
	const wait = new MutationObserver(() => {
		if (!document.documentElement) return;
		wait.disconnect();
		start();
	});
	wait.observe(document, { childList: true });
}
