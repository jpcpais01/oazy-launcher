// Oazy's look over Google Flow. Oazy Browser runs this in every document of
// the Flow window before the site's own code, inside a closure that hands it
// OAZY: {id, hosts, on, accent, test, css} (see WebApps.Bootstrap).
//
// The site stays the real app; this only dresses it. It finds the parts that
// matter by what they are (the biggest text box with a button is the prompt,
// big pictures and videos are what you made, a bar along the top is the
// header) and tags them with data-oazy attributes for flow.css. Nothing here
// depends on Google's class names, and nothing moves or removes the page's own
// elements, so when Flow changes the worst case is that a part goes untagged
// and shows as Google drew it. If the page can't be recognised at all only the
// light layer (scrollbars, selection, accent) stays; if this script itself
// fails, all of it comes off.

if (window.top !== window) return;
const host = location.hostname.toLowerCase();
if (!OAZY.hosts.some(h => host === h || host.endsWith('.' + h))) return;

// Set once the document has its <html> (this runs before it exists).
let root = null;
const TAG = 'data-oazy';
let on = !!OAZY.on;
let deep = false;
let style = null;
let observer = null;
let reported = '';
let failures = 0;
let scheduled = 0;
let full = true;
let ticks = 0;
let started = Date.now();
const pending = new Set();
const seen = new WeakSet();

// --- Style ------------------------------------------------------------------------

function accentRgb(hex) {
	const m = /^#?([0-9a-f]{6})$/i.exec(hex || '');
	const n = m ? parseInt(m[1], 16) : 0x38d6c4;
	return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function ensureStyle() {
	if (style && style.isConnected) return;
	if (!style) {
		style = document.createElement('style');
		style.id = 'oazy-look';
		const [r, g, b] = accentRgb(OAZY.accent);
		style.textContent = ':root{--oazy-accent:rgb(' + r + ',' + g + ',' + b + ');--oazy-accent-rgb:' + r + ',' + g + ',' + b + '}\n' + OAZY.css;
	}
	// Last in the document, so it wins ties with the site's own sheets.
	(document.head || root).appendChild(style);
}

function apply() {
	root.classList.toggle('oazy', on);
	root.classList.toggle('oazy-deep', on && deep);
}

// --- Finding our way around -------------------------------------------------------------

function box(el) {
	const r = el.getBoundingClientRect();
	return r.width > 0 && r.height > 0 ? r : null;
}

function visible(el) {
	const r = box(el);
	if (!r) return null;
	const cs = getComputedStyle(el);
	return cs.visibility === 'hidden' || cs.display === 'none' || +cs.opacity === 0 ? null : r;
}

// [r, g, b, a] of a computed colour, or null.
function rgba(c) {
	const m = /rgba?\(([^)]+)\)/.exec(c || '');
	if (!m) return null;
	const p = m[1].split(/[ ,/]+/).filter(Boolean).map(Number);
	return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1];
}

function dark(c) {
	return c && (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255 < 0.22;
}

function tag(el, what) {
	if (el.getAttribute(TAG) !== what) el.setAttribute(TAG, what);
}

function untagAll(what, keep) {
	for (const el of document.querySelectorAll('[' + TAG + '="' + what + '"]')) if (el !== keep) el.removeAttribute(TAG);
}

// The prompt: the largest visible text box that has a button near it.
function findPrompt() {
	let best = null, bestScore = 0;
	for (const el of document.querySelectorAll('textarea, [contenteditable="true"], [contenteditable=""], [role="textbox"], input[type="text"]:not([readonly])')) {
		if (el.closest('[' + TAG + '="dialog"], [role="dialog"]')) continue;
		const r = visible(el);
		if (!r || r.width < 220) continue;
		// Bigger wins, and lower on the screen breaks ties: Flow's prompt sits at the bottom.
		const score = r.width * Math.max(r.height, 24) * (1 + r.top / Math.max(1, innerHeight));
		if (score > bestScore) { best = el; bestScore = score; }
	}
	if (!best) return null;
	const ir = box(best);
	// The dock is the widest ancestor that still hugs the box and holds its buttons.
	let dock = null;
	let el = best.parentElement;
	for (let depth = 0; el && el !== document.body && depth < 7; depth++, el = el.parentElement) {
		const r = box(el);
		if (!r) continue;
		if (r.width > Math.max(ir.width * 1.7, ir.width + 420) || r.height > Math.max(ir.height + 260, 340)) break;
		if (el.querySelector('button, [role="button"]')) dock = el;
	}
	return { input: best, dock: dock || best.parentElement };
}

function findGo(dock) {
	const buttons = Array.from(dock.querySelectorAll('button, [role="button"]')).filter(b => visible(b));
	if (!buttons.length) return null;
	const said = b => ((b.getAttribute('aria-label') || '') + ' ' + (b.title || '') + ' ' + (b.textContent || '')).toLowerCase();
	const send = /\b(create|generate|send|submit|run|make)\b|arrow_forward|arrow_upward|send/;
	const named = buttons.filter(b => send.test(said(b)));
	if (named.length) return named[named.length - 1];
	// Otherwise the last small button, where send buttons live.
	for (let i = buttons.length - 1; i >= 0; i--) {
		const r = box(buttons[i]);
		if (r && r.width <= 72 && r.height <= 72) return buttons[i];
	}
	return null;
}

function findHeader() {
	const cands = Array.from(document.querySelectorAll('header, [role="banner"]'));
	for (const el of cands) {
		const r = visible(el);
		if (r && r.top < 8 && r.width > innerWidth * 0.6 && r.height <= 120) return el;
	}
	// A bar pinned along the top of the window.
	const probe = document.elementsFromPoint(innerWidth / 2, 6);
	for (const el of probe) {
		if (el === root || el === document.body) break;
		const r = box(el);
		if (r && r.top <= 2 && r.width > innerWidth * 0.8 && r.height >= 40 && r.height <= 110) return el;
	}
	return null;
}

function findRail() {
	for (const el of document.querySelectorAll('nav, [role="navigation"]')) {
		const r = visible(el);
		if (r && r.left < 8 && r.width <= 320 && r.height > innerHeight * 0.55) return el;
	}
	return null;
}

const MEDIA_MIN = 120;

function tagMedia(el) {
	const r = box(el);
	if (!r || r.width < MEDIA_MIN || r.height < 80) return false;
	if (!el.hasAttribute('data-oazy-media')) el.setAttribute('data-oazy-media', '');
	// Its tile: the nearest ancestor about its size (the card it's drawn in).
	let tile = null;
	let p = el.parentElement;
	for (let depth = 0; p && depth < 4; depth++, p = p.parentElement) {
		const pr = box(p);
		if (!pr) continue;
		if (pr.width > r.width + 32 || pr.height > r.height + 96) break;
		tile = p;
	}
	// A card is a tile even if it was taken for a panel before its picture loaded.
	const was = tile && tile.getAttribute(TAG);
	if (tile && (!was || was === 'surface' || was === 'float')) tag(tile, 'tile');
	return true;
}

// Big layers and panels: dark full-page backdrops let the glass through,
// smaller dark panels become glass, floating ones frosted glass.
function tagSurface(el, vw, vh) {
	if (el.hasAttribute(TAG) || el.hasAttribute('data-oazy-clear') || el.hasAttribute('data-oazy-media')) return;
	const tagName = el.tagName;
	if (tagName === 'IMG' || tagName === 'VIDEO' || tagName === 'CANVAS' || tagName === 'svg' || tagName === 'BUTTON' || tagName === 'INPUT' || tagName === 'TEXTAREA') return;
	const r = box(el);
	if (!r || r.width < 140 || r.height < 60) return;
	const cs = getComputedStyle(el);
	const bg = rgba(cs.backgroundColor);
	const role = el.getAttribute('role');
	if (role === 'dialog' || el.getAttribute('aria-modal') === 'true') { tag(el, 'dialog'); return; }
	if (role === 'menu' || role === 'listbox') { tag(el, 'menu'); return; }
	if (!bg || bg[3] < 0.85 || !dark(bg) || cs.backgroundImage !== 'none') return;
	const floating = cs.position === 'fixed' || cs.position === 'absolute' || cs.position === 'sticky';
	if (r.width >= vw * 0.85 && r.height >= vh * 0.6 && cs.position !== 'absolute') {
		// A scrim behind a dialog is fixed, full-screen and dims with its alpha:
		// it never matches (alpha < 0.85 above), but a fixed opaque one is a page.
		el.setAttribute('data-oazy-clear', '');
		return;
	}
	if (r.width * r.height < vw * vh * 0.012) return;
	tag(el, floating ? 'float' : 'surface');
}

const SKIP = { SCRIPT: 1, STYLE: 1, LINK: 1, META: 1, NOSCRIPT: 1, TEMPLATE: 1, PATH: 1, path: 1, g: 1, defs: 1 };

function walk(start, vw, vh, budget) {
	const tw = document.createTreeWalker(start, NodeFilter.SHOW_ELEMENT, {
		acceptNode: n => SKIP[n.tagName] ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
	});
	let n = start;
	let used = 0;
	while (n && used++ < budget) {
		// Each element is judged once it's on screen; hidden ones wait for a later look.
		if (!seen.has(n) && n.getClientRects().length) {
			seen.add(n);
			if (n.tagName === 'IMG' || n.tagName === 'VIDEO') tagMedia(n);
			else if (!n.closest('[' + TAG + '="tile"]')) tagSurface(n, vw, vh);
		}
		n = tw.nextNode();
	}
	return used;
}

// --- One pass over the page ---------------------------------------------------------------

function pass() {
	scheduled = 0;
	try {
		ensureStyle();
		if (!document.body) return;
		const vw = innerWidth, vh = innerHeight;
		const found = [];

		const prompt = findPrompt();
		if (prompt) {
			untagAll('prompt', prompt.dock);
			untagAll('prompt-input', prompt.input);
			tag(prompt.dock, 'prompt');
			tag(prompt.input, 'prompt-input');
			const go = findGo(prompt.dock);
			untagAll('go', go);
			if (go) tag(go, 'go');
			found.push('prompt');
		}
		const header = findHeader();
		if (header && !header.contains(prompt && prompt.dock)) { untagAll('header', header); tag(header, 'header'); found.push('header'); }
		const rail = findRail();
		if (rail) { untagAll('rail', rail); tag(rail, 'rail'); found.push('rail'); }

		// New parts of the page since last time (everything, the first time).
		const roots = pending.size && !full ? Array.from(pending) : [document.body];
		pending.clear();
		full = false;
		let budget = 8000;
		for (const r of roots) {
			if (budget <= 0) break;
			if (r.isConnected) budget -= walk(r, vw, vh, budget);
		}
		// Media that loaded or grew since they were first seen.
		for (const m of document.querySelectorAll('img:not([data-oazy-media]), video:not([data-oazy-media])')) tagMedia(m);
		if (document.querySelector('[data-oazy-media]')) found.push('media');

		// Recognised once it has the prompt or media; a page that isn't (the
		// signed-out landing page, an error) keeps only the light layer.
		const known = found.indexOf('prompt') >= 0 || found.indexOf('media') >= 0;
		if (known !== deep) { deep = known; apply(); }
		const bg = getComputedStyle(root).backgroundColor, bodyBg = getComputedStyle(document.body).backgroundColor;
		root.classList.toggle('oazy-opaque', !deep && (rgba(bg) || [0, 0, 0, 0])[3] === 0 && (rgba(bodyBg) || [0, 0, 0, 0])[3] === 0);
		report(known, found.join(','));
	} catch (e) {
		// Our mistake, not the page's: take the look off rather than leave it half done.
		if (++failures >= 3) { on = false; apply(); stop(); }
		if (OAZY.test) console.warn('Oazy look:', e);
	}
}

function report(ok, found) {
	// Say how it went once it settles (the page fills in after load), and again when it changes.
	const key = ok + '|' + found;
	if (key === reported || (!ok && Date.now() - started < 6000)) return;
	reported = key;
	try { window.chrome.webview.postMessage({ oazyApp: OAZY.id, t: 'look', ok: ok, found: found }); } catch (e) { }
}

function schedule(delay) {
	if (scheduled || !on) return;
	scheduled = setTimeout(() => requestAnimationFrame(pass), delay);
}

function start() {
	if (observer) return;
	observer = new MutationObserver(records => {
		for (const r of records) for (const n of r.addedNodes) if (n.nodeType === 1) pending.add(n);
		// The page swapped its head (and our style with it), or changed a lot.
		if (style && !style.isConnected) ensureStyle();
		schedule(pending.size > 40 ? 120 : 350);
	});
	observer.observe(root, { childList: true, subtree: true });
	addEventListener('resize', () => schedule(250));
	addEventListener('load', () => schedule(200));
	// Flow is a single-page app: going between projects swaps the whole view.
	// Every so often look over all of it again, for parts that were hidden.
	setInterval(() => { if (++ticks % 4 === 0) full = true; schedule(0); }, 2500);
	schedule(0);
}

function stop() {
	if (observer) observer.disconnect();
	observer = null;
}

addEventListener('oazy:look', e => {
	if (!root) return;
	on = !!e.detail;
	failures = 0;
	if (on) { ensureStyle(); start(); }
	apply();
	if (on) schedule(0);
});

function boot() {
	root = document.documentElement;
	ensureStyle();
	apply();
	if (on) {
		if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
		else start();
	}
}

if (document.documentElement) boot();
else {
	const wait = new MutationObserver(() => {
		if (!document.documentElement) return;
		wait.disconnect();
		boot();
	});
	wait.observe(document, { childList: true });
}
