'use strict';
// The browser chrome. The native side (oazy_browser.cs) owns the tabs and
// every page; this file draws them and sends back what you click and type.

const wv = window.chrome && window.chrome.webview;
const send = (t, o) => {
	const msg = Object.assign({ t }, o || {});
	if (wv) wv.postMessage(msg);
	else if (window.__mockHost) window.__mockHost(msg);
};
const $ = id => document.getElementById(id);
const body = document.body;

const S = {
	tabs: [], active: 0, nav: { kind: 'ntp', url: '', display: '' },
	dl: { items: [], active: 0, progress: 0 },
	engine: 'google', engines: [], restore: true, version: '', nativeDrag: false,
};

// --- Static icons ---------------------------------------------------------------

$('newtab').innerHTML = icon('plus', 18);
$('back').innerHTML = icon('back', 18);
$('forward').innerHTML = icon('forward', 18);
$('reload').innerHTML = icon('reload', 17);
$('star').innerHTML = icon('star', 16);
$('menu-btn').innerHTML = icon('menu', 18);
$('win-min').innerHTML = icon('min', 15);
$('win-max').innerHTML = icon('max', 13);
$('win-close').innerHTML = icon('close', 15);
$('find-prev').innerHTML = icon('back', 15);
$('find-next').innerHTML = icon('forward', 15);
$('find-close').innerHTML = icon('close', 15);
document.querySelector('.find-glyph').innerHTML = icon('search', 14);
$('dl').innerHTML = icon('download', 18) +
	'<svg class="ring" viewBox="0 0 28 28"><circle class="bg" cx="14" cy="14" r="12"/><circle class="fg" cx="14" cy="14" r="12"/></svg><i class="dot"></i>';
const RING = 2 * Math.PI * 12;

// --- Messages from the browser ---------------------------------------------------

if (wv) wv.addEventListener('message', e => onMessage(e.data));

function onMessage(m) {
	switch (m.t) {
		case 'init':
			S.engine = m.engine; S.engines = m.engines || []; S.restore = m.restore; S.version = m.version; S.nativeDrag = m.nativeDrag;
			body.classList.toggle('solid', !m.glass);
			setAccent(m.accent);
			renderNav();
			break;
		case 'tabs':
			S.tabs = m.tabs; S.active = m.active;
			renderTabs();
			if (findOpen && $('find-q').value) send('find', { q: $('find-q').value });
			break;
		case 'nav': S.nav = m; renderNav(); break;
		case 'downloads': S.dl = m; renderDlButton(); if (panel === 'downloads') renderDownloads(); break;
		case 'dlStarted':
			bump();
			break;
		case 'dlDone':
			$('dl').classList.add('fresh');
			chip('Downloaded ' + m.name);
			break;
		case 'suggest': onSuggest(m); break;
		case 'snapshot': if (snapResolve) { snapResolve(m.url); snapResolve = null; } break;
		case 'win':
			body.classList.toggle('maximized', !!m.max);
			body.classList.toggle('full', !!m.full);
			$('win-max').innerHTML = icon(m.max ? 'restore' : 'max', 13);
			$('win-max').title = m.max ? 'Restore' : 'Maximise';
			break;
		case 'active':
			body.classList.toggle('inactive', !m.on);
			if (!m.on && panel && !opening) closePanel();
			break;
		case 'focusOmnibox': focusOmnibox(); break;
		case 'typeOmnibox':
			focusOmnibox();
			if (m.text) { addr.value = m.text; onAddrInput({ inputType: 'insertText' }); }
			break;
		case 'openPanel': if (m.name) openPanel(m.name); else closePanel(); break;
		case 'openFind': openFind(); break;
		case 'find': renderFind(m); break;
		case 'history': renderHistory(m.items || []); break;
		case 'toast': chip(m.text); break;
		case 'engine': S.engine = m.engine; renderNav(); if (panel === 'menu') renderMenu(); break;
	}
}

function setAccent(hex) {
	const m = /^#?([0-9a-f]{6})$/i.exec(hex || '');
	if (!m) return;
	const n = parseInt(m[1], 16);
	document.documentElement.style.setProperty('--accent', '#' + m[1]);
	document.documentElement.style.setProperty('--accent-rgb', (n >> 16) + ', ' + ((n >> 8) & 255) + ', ' + (n & 255));
}

function engineName() {
	const e = S.engines.find(x => x.id === S.engine);
	return e ? e.name : 'Google';
}

// --- Window -------------------------------------------------------------------------

$('win-min').onclick = () => send('cmd', { cmd: 'minimize' });
$('win-max').onclick = () => send('cmd', { cmd: 'maximize' });
$('win-close').onclick = () => send('cmd', { cmd: 'close' });

// Where the runtime supports app-region these never fire (Windows drags the
// window itself); older runtimes get the same behaviour from here.
for (const el of [$('strip'), $('drag')]) {
	el.addEventListener('mousedown', e => {
		if (e.button !== 0 || e.target !== el || e.detail > 1) return;
		send('drag');
	});
	el.addEventListener('dblclick', e => { if (e.target === el) send('cmd', { cmd: 'maximize' }); });
}

// --- Tabs -------------------------------------------------------------------------------

const tabsBox = $('tabs');
const tabEls = new Map();
let lockedWidth = 0;
let dragging = false;

function renderTabs() {
	const ids = new Set(S.tabs.map(t => t.id));
	for (const [id, el] of tabEls) {
		if (ids.has(id)) continue;
		tabEls.delete(id);
		if (el.classList.contains('closing')) setTimeout(() => el.remove(), 180);
		else el.remove();
	}
	let prev = null;
	for (const t of S.tabs) {
		let el = tabEls.get(t.id);
		if (!el) {
			el = makeTab(t.id);
			tabEls.set(t.id, el);
			el.classList.add('new');
			setTimeout(() => el.classList.remove('new'), 300);
		}
		updateTab(el, t);
		const want = prev ? prev.nextSibling : tabsBox.firstChild;
		if (el !== want && !dragging) tabsBox.insertBefore(el, want);
		prev = el;
	}
	layoutTabs();
}

function makeTab(id) {
	const el = document.createElement('div');
	el.className = 'tab';
	el.setAttribute('role', 'tab');
	el.innerHTML = '<div class="fav"></div><div class="title"></div><button class="audio"></button><button class="x" title="Close tab (Ctrl+W)">' + icon('close', 14) + '</button>';
	el.addEventListener('mousedown', e => onTabDown(e, id));
	el.addEventListener('auxclick', e => { if (e.button === 1) closeTab(id); });
	el.addEventListener('contextmenu', e => { e.preventDefault(); openTabMenu(id, e.clientX, e.clientY); });
	el.addEventListener('mouseenter', () => { if (el.previousElementSibling) el.previousElementSibling.classList.add('before-hover'); });
	el.addEventListener('mouseleave', () => { if (el.previousElementSibling) el.previousElementSibling.classList.remove('before-hover'); });
	el.querySelector('.x').addEventListener('mousedown', e => e.stopPropagation());
	el.querySelector('.x').addEventListener('click', e => { e.stopPropagation(); closeTab(id); });
	el.querySelector('.audio').addEventListener('mousedown', e => e.stopPropagation());
	el.querySelector('.audio').addEventListener('click', e => { e.stopPropagation(); send('tabMenu', { id, cmd: 'mute' }); });
	return el;
}

function updateTab(el, t) {
	const key = [t.title, t.icon, t.loading, t.audio, t.muted, t.ntp, t.crashed, t.id === S.active].join('|');
	el.classList.toggle('active', t.id === S.active);
	if (el._key === key) return;
	el._key = key;
	el.title = t.title;
	el.querySelector('.title').textContent = t.title;
	el.classList.toggle('has-audio', !!(t.audio || t.muted));
	el.classList.toggle('crashed', !!t.crashed);
	el.querySelector('.audio').innerHTML = icon(t.muted ? 'muted' : 'speaker', 14);
	el.querySelector('.audio').title = t.muted ? 'Unmute site' : 'Mute site';
	const fav = el.querySelector('.fav');
	if (t.crashed) fav.innerHTML = icon('sad', 16);
	else if (t.loading && !t.ntp) fav.innerHTML = '<i class="spin"></i>';
	else if (t.ntp) fav.innerHTML = '<span style="color:var(--accent)">' + icon('sparkle', 15) + '</span>';
	else if (t.icon) {
		fav.innerHTML = '<img alt="">';
		const img = fav.firstChild;
		img.onerror = () => { fav.innerHTML = icon('globe', 15); };
		img.src = t.icon;
	}
	else fav.innerHTML = icon('globe', 15);
}

function layoutTabs() {
	const n = S.tabs.length;
	if (!n) return;
	const free = $('strip').clientWidth - 8 - 34 - 56 - $('wincontrols').offsetWidth;
	const w = lockedWidth || Math.max(36, Math.min(236, Math.floor(free / n) - 2));
	for (const el of tabEls.values()) {
		if (el.classList.contains('closing')) continue;
		el.style.width = w + 'px';
		el.classList.toggle('tiny', w < 78);
	}
	let before = null;
	for (const el of tabsBox.children) {
		el.classList.remove('before-active');
		if (el.classList.contains('active') && before) before.classList.add('before-active');
		before = el;
	}
}

function closeTab(id) {
	const el = tabEls.get(id);
	// Keep the other tabs where they are while you close several in a row.
	if (el && tabsBox.matches(':hover')) lockedWidth = el.offsetWidth;
	if (el) el.classList.add('closing');
	send('closeTab', { id });
}

tabsBox.addEventListener('mouseleave', () => {
	if (!lockedWidth) return;
	lockedWidth = 0;
	layoutTabs();
});
window.addEventListener('resize', () => { layoutTabs(); positionPanels(); });
// The page is sized by the browser; never let focus scroll it out of place.
// When the page takes focus the address bar lets go for real, so it shows the
// page's address again instead of what it had before.
window.addEventListener('blur', () => { if (document.activeElement === addr) addr.blur(); });
window.addEventListener('scroll', () => { if (window.scrollY || window.scrollX) window.scrollTo(0, 0); });

function onTabDown(e, id) {
	if (e.button === 1) { e.preventDefault(); return; }
	if (e.button !== 0) return;
	if (id !== S.active) send('activate', { id });
	const el = tabEls.get(id);
	const startX = e.clientX;
	let moved = false;
	let to = S.tabs.findIndex(t => t.id === id);
	const from = to;
	const move = ev => {
		const dx = ev.clientX - startX;
		if (!moved && Math.abs(dx) < 6) return;
		if (!moved) { moved = true; dragging = true; el.classList.add('dragging'); }
		const w = el.offsetWidth + 2;
		const first = tabsBox.firstElementChild.getBoundingClientRect().left;
		const last = tabsBox.lastElementChild.getBoundingClientRect().right;
		const r = el.getBoundingClientRect();
		const clamped = Math.max(first - (r.left - (el._dx || 0)), Math.min(last - (r.right - (el._dx || 0)), dx));
		el._dx = clamped;
		el.style.transform = 'translateX(' + clamped + 'px)';
		to = Math.max(0, Math.min(S.tabs.length - 1, from + Math.round(clamped / w)));
		S.tabs.forEach((t, i) => {
			if (t.id === id) return;
			const o = tabEls.get(t.id);
			let shift = 0;
			if (from < to && i > from && i <= to) shift = -w;
			if (from > to && i >= to && i < from) shift = w;
			o.style.transform = shift ? 'translateX(' + shift + 'px)' : '';
		});
	};
	const up = () => {
		window.removeEventListener('mousemove', move);
		if (!moved) return;
		dragging = false;
		el._dx = 0;
		el.classList.remove('dragging');
		for (const o of tabEls.values()) { o.style.transition = 'none'; o.style.transform = ''; }
		if (to !== from) {
			const [t] = S.tabs.splice(from, 1);
			S.tabs.splice(to, 0, t);
			renderTabs();
			send('moveTab', { id, to });
		}
		requestAnimationFrame(() => { for (const o of tabEls.values()) o.style.transition = ''; });
	};
	window.addEventListener('mousemove', move);
	window.addEventListener('mouseup', up, { once: true });
}

$('newtab').onclick = () => send('newTab');
$('strip').addEventListener('dblclick', e => { if (e.target === tabsBox) send('newTab'); });

// --- Navigation buttons -------------------------------------------------------------------

$('back').onclick = () => send('cmd', { cmd: 'back' });
$('forward').onclick = () => send('cmd', { cmd: 'forward' });
$('reload').onclick = e => send('cmd', { cmd: S.nav.loading ? 'stop' : (e.shiftKey || e.ctrlKey ? 'hardReload' : 'reload') });
$('star').onclick = () => send('cmd', { cmd: 'pin' });
$('zoom-chip').onclick = () => send('cmd', { cmd: 'zoomReset' });
for (const id of ['back', 'forward', 'reload', 'dl', 'menu-btn']) $(id).addEventListener('mouseenter', snapPrefetch);

function renderNav() {
	const n = S.nav;
	$('back').disabled = !n.back;
	$('forward').disabled = !n.fwd;
	$('reload').innerHTML = icon(n.loading ? 'stop' : 'reload', n.loading ? 16 : 17);
	$('reload').title = n.loading ? 'Stop (Esc)' : 'Reload (Ctrl+R)';
	$('progress').classList.toggle('on', !!n.loading && n.kind !== 'ntp');
	omni.classList.toggle('ntp', n.kind === 'ntp');
	const site = $('site');
	site.className = n.kind;
	if (n.kind === 'https') { site.innerHTML = icon('lock', 15); site.title = 'Connection is secure'; }
	else if (n.kind === 'http') { site.innerHTML = icon('warn', 14) + '<span>Not secure</span>'; site.title = 'This site doesn’t use a secure connection'; }
	else if (n.kind === 'file') { site.innerHTML = icon('file', 15); site.title = 'File on this PC'; }
	else if (n.kind === 'ntp') { site.innerHTML = icon('search', 15); site.title = ''; }
	else { site.innerHTML = icon('globe', 15); site.title = ''; }
	$('star').classList.toggle('on', !!n.pinned);
	$('star').title = n.pinned ? 'Unpin from new tab page (Ctrl+D)' : 'Pin to new tab page (Ctrl+D)';
	const zc = $('zoom-chip');
	zc.classList.toggle('show', !!n.zoom && n.zoom !== 100);
	zc.textContent = n.zoom + '%';
	addr.placeholder = 'Search ' + engineName() + ' or type a URL';
	if (!editing && document.activeElement !== addr) showUrl();
	if (panel === 'menu') renderMenu();
}

// --- Address bar ---------------------------------------------------------------------------

const addr = $('addr');
const omni = $('omni');
let editing = false;
let lastTyped = '';
let inline = null;      // {text, url} when we filled in the rest of a site you've visited
let sugItems = [];
let sugSel = 0;

function showUrl() {
	const n = S.nav;
	addr.value = n.url || '';
	const d = n.display || '';
	const pretty = $('addr-pretty');
	if (d && (n.kind === 'https' || n.kind === 'http')) {
		const cut = d.indexOf('/');
		pretty.innerHTML = cut < 0 ? '<b>' + esc(d) + '</b>' : '<b>' + esc(d.slice(0, cut)) + '</b>' + esc(d.slice(cut));
		omni.classList.add('pretty');
	} else {
		omni.classList.remove('pretty');
	}
}

function focusOmnibox() {
	addr.focus({ preventScroll: true });
	addr.select();
}

addr.addEventListener('mousedown', e => {
	if (document.activeElement === addr) return;
	// First click selects everything, like every browser.
	e.preventDefault();
	focusOmnibox();
});
addr.addEventListener('focus', () => {
	omni.classList.add('focus');
	if (!editing) addr.value = S.nav.url || '';
	snapPrefetch();
});
addr.addEventListener('blur', () => {
	omni.classList.remove('focus');
	editing = false;
	inline = null;
	if (panel === 'suggest') closePanel();
	renderNav();
});
addr.addEventListener('input', e => onAddrInput(e));
addr.addEventListener('paste', () => setTimeout(() => onAddrInput({ inputType: 'insertFromPaste' }), 0));

function onAddrInput(e) {
	editing = true;
	// While you type it's a search box, not the page's padlock.
	const site = $('site');
	if (site.className !== 'typing') { site.className = 'typing'; site.innerHTML = icon('search', 15); site.title = ''; }
	const q = addr.value;
	inline = null;
	if (!q.trim()) {
		lastTyped = '';
		if (panel === 'suggest') closePanel();
		return;
	}
	lastTyped = q;
	allowInline = !!(e && e.inputType && e.inputType.indexOf('insert') === 0) && addr.selectionStart === q.length;
	// Something to show straight away; the browser fills in the rest.
	onSuggest({ q, local: [], remote: [], url: null, pending: true });
	send('suggest', { q });
}
let allowInline = false;

addr.addEventListener('keydown', e => {
	if (e.key === 'Enter') {
		e.preventDefault();
		go(e.altKey || (e.ctrlKey && e.shiftKey), e.ctrlKey && !e.shiftKey);
	} else if (e.key === 'Escape') {
		e.preventDefault();
		if (panel === 'suggest') { closePanel(); if (inline) { addr.value = lastTyped; inline = null; } return; }
		editing = false;
		renderNav();
		showUrl();
		addr.select();
		if (!omni.classList.contains('ntp')) send('focusContent');
	} else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
		if (panel !== 'suggest' || !sugItems.length) return;
		e.preventDefault();
		sugSel = (sugSel + (e.key === 'ArrowDown' ? 1 : -1) + sugItems.length) % sugItems.length;
		inline = null;
		const it = sugItems[sugSel];
		addr.value = it.kind === 'search' || it.kind === 'typed' ? it.text : (it.url || it.text);
		markSel();
	} else if (e.key === 'Delete' && e.shiftKey && panel === 'suggest') {
		const it = sugItems[sugSel];
		if (it && it.kind === 'history') { e.preventDefault(); send('historyRemove', { url: it.url }); sugItems.splice(sugSel, 1); drawSuggest(); }
	}
});

function go(newTab, wrapCom) {
	let text = addr.value.trim();
	if (!text) return;
	const it = panel === 'suggest' ? sugItems[sugSel] : null;
	let msg;
	if (inline && addr.value === inline.text) msg = { url: inline.url };
	else if (wrapCom && /^[\w-]+$/.test(text)) msg = { text: 'www.' + text + '.com' };
	else if (it && it.url && sugSel > 0) msg = { url: it.url };
	else msg = { text };
	msg.newTab = !!newTab;
	editing = false;
	inline = null;
	closePanel();
	addr.blur();
	send('navigate', msg);
}

function onSuggest(m) {
	if (m.q !== lastTyped || document.activeElement !== addr) return;
	const q = m.q.trim();
	const items = [];
	const looksUrl = m.url ? !/[?&]q(uery)?=/.test(m.url) || /^https?:\/\//i.test(q) : /^[^\s]+\.[a-z]{2,}(\/.*)?$/i.test(q) || /^https?:\/\//i.test(q);
	items.push(looksUrl
		? { kind: 'typed', text: q, url: m.url || '', icon: 'globe', sub: 'Go to site' }
		: { kind: 'typed', text: q, url: '', icon: 'search', sub: engineName() + ' search' });
	const seen = new Set([q.toLowerCase()]);
	for (const h of (m.local || []).slice(0, 4)) {
		if (seen.has(h.url)) continue;
		seen.add(h.url);
		items.push({ kind: 'history', text: h.text || bareHost(h.url), url: h.url, img: h.icon, sub: h.url.replace(/^https?:\/\/(www\.)?/, '').replace(/\/$/, '') });
	}
	for (const r of (m.remote || [])) {
		if (seen.has(r.text.toLowerCase())) continue;
		seen.add(r.text.toLowerCase());
		items.push({ kind: 'search', text: r.text, url: r.url, icon: 'search' });
	}
	if (m.pending && sugItems.length && panel === 'suggest') {
		// Keep showing what we had while the new list is on its way.
		sugItems[0] = items[0];
	} else {
		sugItems = items;
	}
	sugSel = 0;
	// Finish the address of a site you've been to as you type it.
	if (allowInline && !m.pending && addr.value === lastTyped && addr.selectionStart === lastTyped.length) {
		const typed = lastTyped.toLowerCase().replace(/^https?:\/\//, '');
		for (const h of m.local || []) {
			const host = h.url.replace(/^https?:\/\//i, '').replace(/^www\./i, '');
			const hostOnly = host.split('/')[0];
			if (typed.length >= 1 && hostOnly.toLowerCase().indexOf(typed) === 0 && hostOnly.length > typed.length) {
				const full = lastTyped + hostOnly.slice(typed.length);
				addr.value = full;
				addr.setSelectionRange(lastTyped.length, full.length);
				inline = { text: full, url: h.url.match(/^https?:\/\/[^/]+/i)[0] + '/' };
				break;
			}
		}
	}
	drawSuggest();
	if (panel !== 'suggest') openPanel('suggest');
}

function drawSuggest() {
	const box = $('suggest');
	const q = lastTyped.trim().toLowerCase();
	box.innerHTML = sugItems.map((it, i) => {
		let text = esc(it.text);
		if (it.kind === 'search' && q && it.text.toLowerCase().indexOf(q) === 0) text = esc(it.text.slice(0, q.length)) + '<mark>' + esc(it.text.slice(q.length)) + '</mark>';
		const ic = it.img ? '<img src="' + esc(it.img) + '" alt="" onerror="this.outerHTML=icon(\'clock\',16)">' : icon(it.kind === 'history' ? 'clock' : it.icon, 16);
		const sub = it.sub ? '<span class="sg-sub">' + esc(it.sub) + '</span>' : '';
		return '<div class="sg' + (i === sugSel ? ' sel' : '') + '" data-i="' + i + '"><span class="sg-ic">' + ic + '</span><span class="sg-text">' + text + '</span>' + sub +
			(i === 0 ? '<span class="sg-key">Enter</span>' : '') + '</div>';
	}).join('');
}

function markSel() {
	for (const el of $('suggest').children) el.classList.toggle('sel', +el.dataset.i === sugSel);
}

$('suggest').addEventListener('mousedown', e => {
	e.preventDefault();  // keep the address bar focused
	const row = e.target.closest('.sg');
	if (!row) return;
	sugSel = +row.dataset.i;
	const it = sugItems[sugSel];
	if (it.kind === 'typed') go(e.button === 1 || e.ctrlKey);
	else {
		addr.value = it.url;
		editing = false;
		closePanel();
		addr.blur();
		send('navigate', { url: it.url, newTab: e.button === 1 || e.ctrlKey });
	}
});
$('suggest').addEventListener('mousemove', e => {
	const row = e.target.closest('.sg');
	if (row && +row.dataset.i !== sugSel) { sugSel = +row.dataset.i; markSel(); }
});

function chip(text) {
	const c = $('chip');
	c.textContent = text;
	c.classList.add('show');
	clearTimeout(chip.t);
	chip.t = setTimeout(() => c.classList.remove('show'), 2600);
}

// --- Panels over the page ---------------------------------------------------------------------
// While a panel is open this page is stretched over the whole window by the
// browser, and a still of the page fills the space below the toolbar.

let panel = '';
let opening = false;
let snapReq = null, snapAt = 0, snapResolve = null;
let panelToken = 0;

function snapPrefetch() {
	const now = performance.now();
	if (!snapReq || now - snapAt > 1500) {
		snapAt = now;
		snapReq = new Promise(res => {
			snapResolve = res;
			send('snapshot');
			setTimeout(() => res(null), 700);
		});
	}
	return snapReq;
}

function loadImage(img, url) {
	return new Promise(res => {
		if (!url) { img.removeAttribute('src'); res(); return; }
		img.onload = img.onerror = () => res();
		img.src = url;
		if (img.decode) img.decode().then(res, res);
	});
}

async function openPanel(name) {
	const token = ++panelToken;
	if (panel === name) return;
	for (const p of document.querySelectorAll('#overlay .panel')) p.classList.toggle('show', p.id === name);
	const wasOpen = !!panel;
	panel = name;
	body.classList.toggle('light-veil', name === 'suggest');
	if (name === 'menu') renderMenu();
	if (name === 'downloads') { renderDownloads(); $('dl').classList.remove('fresh'); }
	if (name === 'history') { renderHistory(null); send('history', { q: '' }); }
	positionPanels();
	if (!wasOpen) {
		opening = true;
		const url = await snapPrefetch();
		if (token !== panelToken) return;
		await loadImage($('snap'), url);
		if (token !== panelToken) return;
		snapReq = null;
		document.documentElement.style.setProperty('--chrome-h', $('top').offsetHeight + 'px');
		body.classList.add('overlay');
		send('overlay', { on: true });
		setTimeout(() => { opening = false; }, 400);
		requestAnimationFrame(() => requestAnimationFrame(() => { if (token === panelToken) body.classList.add('open'); }));
	}
	if (name === 'history') setTimeout(() => { const i = $('hist-q'); if (i) i.focus(); }, 60);
}

function closePanel() {
	if (!panel) return;
	const token = ++panelToken;
	panel = '';
	body.classList.remove('open');
	setTimeout(() => {
		if (token !== panelToken) return;
		for (const p of document.querySelectorAll('#overlay .panel')) p.classList.remove('show');
		body.classList.remove('overlay');
		send('overlay', { on: false });
		$('snap').removeAttribute('src');
	}, 150);
}

function positionPanels() {
	const top = $('top').offsetHeight;
	const o = omni.getBoundingClientRect();
	const sg = $('suggest');
	sg.style.left = o.left + 'px';
	sg.style.width = o.width + 'px';
	sg.style.top = (o.bottom - top - 1) + 'px';
	const right = (id, btn) => {
		const r = $(btn).getBoundingClientRect();
		const p = $(id);
		p.style.right = Math.max(8, window.innerWidth - r.right - 2) + 'px';
		p.style.top = (r.bottom - top + 6) + 'px';
	};
	right('menu', 'menu-btn');
	right('downloads', 'dl');
	const h = $('history');
	h.style.left = '50%';
	h.style.marginLeft = (-Math.min(560, window.innerWidth - 40) / 2) + 'px';
	h.style.top = '14px';
}

$('veil').addEventListener('mousedown', e => { e.preventDefault(); closePanel(); });
document.addEventListener('keydown', e => {
	if (e.key === 'Escape' && panel && panel !== 'suggest') { e.preventDefault(); closePanel(); }
});
// Clicking the toolbar while something is open closes it first.
$('top').addEventListener('mousedown', e => {
	if (!panel || panel === 'suggest') return;
	if (e.target.closest('#menu-btn') || e.target.closest('#dl')) return;
	closePanel();
}, true);

$('menu-btn').onclick = () => { if (panel === 'menu') closePanel(); else openPanel('menu'); };
$('dl').onclick = () => { if (panel === 'downloads') closePanel(); else openPanel('downloads'); };

// --- Menu -----------------------------------------------------------------------------------

let clearArmed = false;

function mi(ic, label, key, cmd, cls) {
	return '<div class="mi ' + (cls || '') + '" data-cmd="' + cmd + '">' + icon(ic, 17) + '<span>' + esc(label) + '</span>' + (key ? '<span class="key">' + key + '</span>' : '') + '</div>';
}

function renderMenu() {
	const z = S.nav.zoom || 100;
	const engines = S.engines.map(e => '<button data-engine="' + e.id + '" class="' + (e.id === S.engine ? 'on' : '') + '">' + esc(e.name) + '</button>').join('');
	$('menu').innerHTML =
		mi('tab', 'New tab', 'Ctrl+T', 'newTab') +
		mi('window', 'New window', 'Ctrl+N', 'newWindow') +
		'<div class="sep"></div>' +
		mi('history', 'History', 'Ctrl+H', 'panel:history') +
		mi('download', 'Downloads', 'Ctrl+J', 'panel:downloads') +
		'<div class="sep"></div>' +
		'<div class="menu-row"><span class="label">' + icon('search', 17) + 'Zoom</span>' +
		'<button class="icon-btn small" data-cmd="zoomOut" data-keep="1" title="Zoom out (Ctrl+-)">' + icon('zoomOut', 15) + '</button>' +
		'<span class="zoom-val">' + z + '%</span>' +
		'<button class="icon-btn small" data-cmd="zoomIn" data-keep="1" title="Zoom in (Ctrl++)">' + icon('zoomIn', 15) + '</button>' +
		'<button class="icon-btn small" data-cmd="fullscreen" title="Full screen (F11)">' + icon('fullscreen', 15) + '</button></div>' +
		mi('find', 'Find on page', 'Ctrl+F', 'find') +
		mi('print', 'Print…', 'Ctrl+P', 'print') +
		'<div class="sep"></div>' +
		'<div class="menu-caption">Search with</div><div class="seg">' + engines + '</div>' +
		'<div class="mi" data-cmd="toggleRestore" data-keep="1">' + icon('retry', 17) + '<span>Reopen tabs on start</span><span class="key"><i class="switch' + (S.restore ? ' on' : '') + '"></i></span></div>' +
		mi('trash', clearArmed ? 'Click again to clear everything' : 'Clear browsing data', '', 'clearData', 'danger' + (clearArmed ? ' armed' : '')) +
		mi('code', 'Developer tools', 'F12', 'devtools') +
		'<div class="sep"></div>' +
		'<div class="menu-foot"><span class="brand">Oazy Browser</span><span>Chromium ' + esc((S.version || '').split(' ')[0]) + '</span></div>';
}

$('menu').addEventListener('click', e => {
	const eng = e.target.closest('[data-engine]');
	if (eng) {
		S.engine = eng.dataset.engine;
		send('cmd', { cmd: 'engine', value: S.engine });
		renderMenu();
		return;
	}
	const el = e.target.closest('[data-cmd]');
	if (!el) return;
	const cmd = el.dataset.cmd;
	if (cmd.indexOf('panel:') === 0) { closePanelThen(() => openPanel(cmd.slice(6))); return; }
	if (cmd === 'find') { closePanel(); openFind(); return; }
	if (cmd === 'toggleRestore') {
		S.restore = !S.restore;
		send('cmd', { cmd: 'restore', value: S.restore });
		renderMenu();
		return;
	}
	if (cmd === 'clearData' && !clearArmed) {
		clearArmed = true;
		renderMenu();
		setTimeout(() => { clearArmed = false; if (panel === 'menu') renderMenu(); }, 3500);
		return;
	}
	clearArmed = false;
	send('cmd', { cmd });
	if (!el.dataset.keep) closePanel();
});

function closePanelThen(fn) {
	closePanel();
	setTimeout(fn, 170);
}

// --- Downloads ----------------------------------------------------------------------------------

function bump() {
	const b = $('dl');
	b.classList.remove('bump');
	void b.offsetWidth;
	b.classList.add('bump');
}

function renderDlButton() {
	const d = S.dl;
	const b = $('dl');
	const fg = b.querySelector('.fg');
	b.classList.toggle('busy', d.active > 0);
	const ring = b.querySelector('.ring');
	ring.style.display = d.active > 0 ? '' : 'none';
	ring.classList.toggle('indeterminate', d.progress < 0);
	fg.style.strokeDasharray = RING;
	fg.style.strokeDashoffset = d.progress < 0 ? RING * 0.72 : RING * (1 - Math.max(0.02, d.progress));
	b.title = d.active > 0 ? 'Downloading ' + d.active + (d.active === 1 ? ' file' : ' files') + ' (Ctrl+J)' : 'Downloads (Ctrl+J)';
}

function fmtBytes(n) {
	if (!n || n < 0) return '0 B';
	const u = ['B', 'KB', 'MB', 'GB', 'TB'];
	let i = 0;
	while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
	return (i >= 2 ? n.toFixed(n < 10 ? 1 : 0) : Math.round(n)) + ' ' + u[i];
}

const EXT_COLORS = {
	exe: '#4f8cff', msi: '#4f8cff', zip: '#e8a93b', rar: '#e8a93b', '7z': '#e8a93b', pdf: '#ff6b6b',
	png: '#9b7bff', jpg: '#9b7bff', jpeg: '#9b7bff', gif: '#9b7bff', webp: '#9b7bff', svg: '#9b7bff',
	mp4: '#ff6fb5', mkv: '#ff6fb5', mov: '#ff6fb5', webm: '#ff6fb5', mp3: '#3ddc97', wav: '#3ddc97', flac: '#3ddc97',
	doc: '#4fa3ff', docx: '#4fa3ff', xls: '#3dbf7d', xlsx: '#3dbf7d', ppt: '#ff8f5a', pptx: '#ff8f5a', txt: '#8b93a7',
};

function renderDownloads() {
	const items = S.dl.items || [];
	const list = items.map(d => {
		const ext = (d.name.split('.').pop() || '').toLowerCase();
		const color = EXT_COLORS[ext] || 'var(--accent)';
		const pct = d.total > 0 ? Math.min(100, d.received / d.total * 100) : 0;
		let sub = '', actions = '';
		if (d.state === 'progress') {
			sub = fmtBytes(d.received) + (d.total > 0 ? ' of ' + fmtBytes(d.total) : '') + (d.speed > 0 ? ' · ' + fmtBytes(d.speed) + '/s' : '');
			if (d.speed > 0 && d.total > d.received) {
				const secs = (d.total - d.received) / d.speed;
				sub += ' · ' + (secs < 60 ? Math.ceil(secs) + ' s left' : Math.ceil(secs / 60) + ' min left');
			}
			actions = btn('pause', 'Pause', 'pause') + btn('close', 'Cancel', 'cancel');
		} else if (d.state === 'paused') {
			sub = 'Paused · ' + fmtBytes(d.received) + (d.total > 0 ? ' of ' + fmtBytes(d.total) : '');
			actions = btn('play', 'Resume', 'resume') + btn('close', 'Cancel', 'cancel');
		} else if (d.state === 'done') {
			sub = fmtBytes(d.total) + ' · ' + bareHost(d.url);
			actions = btn('folder', 'Show in folder', 'show') + btn('close', 'Remove from list', 'remove');
		} else {
			sub = d.state === 'gone' ? 'Deleted' : d.state === 'cancelled' ? 'Cancelled' : 'Failed';
			actions = (d.url ? btn('retry', 'Try again', 'retry') : '') + btn('close', 'Remove from list', 'remove');
		}
		const bar = d.state === 'progress' || d.state === 'paused' ? '<div class="dl-bar"><i style="width:' + (d.total > 0 ? pct : 30) + '%"></i></div>' : '';
		return '<div class="dl ' + d.state + '" data-dl="' + d.id + '">' +
			'<div class="dl-ic" style="background:linear-gradient(160deg,' + color + ',color-mix(in srgb,' + color + ' 55%,#000))">' + esc(ext.slice(0, 4) || 'file') + '</div>' +
			'<div class="dl-body"><div class="dl-name" title="' + esc(d.name) + '">' + esc(d.name) + '</div><div class="dl-sub">' + esc(sub) + '</div>' + bar + '</div>' +
			'<div class="dl-actions">' + actions + '</div></div>';
	}).join('');
	$('downloads').innerHTML =
		'<div class="panel-head"><h3>Downloads</h3>' +
		'<button class="text-btn" data-act="folder">Open folder</button>' +
		(items.some(d => d.state !== 'progress' && d.state !== 'paused') ? '<button class="text-btn" data-act="clear">Clear</button>' : '') + '</div>' +
		(items.length ? '<div class="dl-list">' + list + '</div>' : '<div class="empty">' + icon('download', 30) + 'Files you download show up here</div>');
}

function btn(ic, title, act) {
	return '<button class="icon-btn small" title="' + title + '" data-act="' + act + '">' + icon(ic, 15) + '</button>';
}

$('downloads').addEventListener('click', e => {
	const a = e.target.closest('[data-act]');
	const row = e.target.closest('[data-dl]');
	if (a) {
		const act = a.dataset.act;
		if (act === 'folder') { send('cmd', { cmd: 'downloadsFolder' }); closePanel(); return; }
		if (act === 'clear') { send('download', { dl: 0, action: 'clear' }); return; }
		send('download', { dl: +row.dataset.dl, action: act });
		return;
	}
	if (row && row.classList.contains('done')) {
		send('download', { dl: +row.dataset.dl, action: 'open' });
		closePanel();
	}
});

// --- History ------------------------------------------------------------------------------------

let histQ = '';

function renderHistory(items) {
	const h = $('history');
	if (!h.querySelector('.hist-list')) {
		h.innerHTML = '<div class="panel-head"><h3>History</h3><button class="text-btn" data-hact="clear">Clear browsing data</button></div>' +
			'<label class="search-box">' + icon('search', 15) + '<input id="hist-q" type="text" placeholder="Search history" spellcheck="false"></label>' +
			'<div class="hist-list"></div>';
		$('hist-q').addEventListener('input', () => {
			histQ = $('hist-q').value;
			clearTimeout(renderHistory.t);
			renderHistory.t = setTimeout(() => send('history', { q: histQ }), 140);
		});
	}
	if (items === null) return;
	const list = h.querySelector('.hist-list');
	if (!items.length) {
		list.innerHTML = '<div class="empty">' + icon('history', 30) + (histQ ? 'Nothing matches “' + esc(histQ) + '”' : 'Sites you visit show up here') + '</div>';
		return;
	}
	const today = new Date(); today.setHours(0, 0, 0, 0);
	let lastDay = '';
	let html = '';
	for (const it of items) {
		const d = new Date(it.at * 1000);
		const day = new Date(d); day.setHours(0, 0, 0, 0);
		const diff = Math.round((today - day) / 86400000);
		const label = diff === 0 ? 'Today' : diff === 1 ? 'Yesterday' : d.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
		if (label !== lastDay) { html += '<div class="hist-day">' + esc(label) + '</div>'; lastDay = label; }
		const host = bareHost(it.url);
		html += '<div class="hist" data-url="' + esc(it.url) + '">' + siteIcon(it.icon, host) +
			'<span class="t">' + esc(it.title || host) + '</span><span class="h">' + esc(host) + '</span>' +
			'<span class="time">' + d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' }) + '</span>' +
			'<button class="icon-btn small" data-hact="remove" title="Remove from history">' + icon('close', 14) + '</button></div>';
	}
	list.innerHTML = html;
}

function siteIcon(src, host) {
	const hue = hostHue(host);
	if (src) return '<span class="site-ic"><img src="' + esc(src) + '" alt="" onerror="this.parentNode.style.background=\'hsl(' + hue + ',45%,45%)\';this.outerHTML=\'' + esc((host[0] || '?').toUpperCase()) + '\'"></span>';
	return '<span class="site-ic" style="background:hsl(' + hue + ',45%,45%)">' + esc((host[0] || '?').toUpperCase()) + '</span>';
}

$('history').addEventListener('click', e => {
	const act = e.target.closest('[data-hact]');
	const row = e.target.closest('.hist');
	if (act && act.dataset.hact === 'clear') { closePanelThen(() => { clearArmed = true; openPanel('menu'); setTimeout(() => { clearArmed = false; }, 3500); }); return; }
	if (act && act.dataset.hact === 'remove' && row) { send('historyRemove', { url: row.dataset.url, q: histQ }); return; }
	if (row) {
		send('cmd', { cmd: 'openUrl', url: row.dataset.url, newTab: e.ctrlKey });
		closePanel();
	}
});
$('history').addEventListener('auxclick', e => {
	const row = e.target.closest('.hist');
	if (e.button === 1 && row) send('cmd', { cmd: 'openUrl', url: row.dataset.url, newTab: true });
});

// --- Tab context menu --------------------------------------------------------------------------

let menuTab = 0;

function openTabMenu(id, x, y) {
	menuTab = id;
	const t = S.tabs.find(t => t.id === id);
	if (!t) return;
	const idx = S.tabs.indexOf(t);
	$('tabmenu').innerHTML =
		mi('reload', 'Reload', '', 'reload') +
		mi('duplicate', 'Duplicate', '', 'duplicate') +
		mi(t.muted ? 'speaker' : 'muted', t.muted ? 'Unmute site' : 'Mute site', '', 'mute') +
		(S.tabs.length > 1 ? mi('external', 'Move to new window', '', 'window') : '') +
		'<div class="sep"></div>' +
		mi('close', 'Close', 'Ctrl+W', 'close') +
		(S.tabs.length > 1 ? mi('close', 'Close other tabs', '', 'closeOthers') : '') +
		(idx < S.tabs.length - 1 ? mi('close', 'Close tabs to the right', '', 'closeRight') : '');
	const p = $('tabmenu');
	const top = $('top').offsetHeight;
	p.style.left = Math.min(x, window.innerWidth - 262) + 'px';
	p.style.top = (y - top + 4) + 'px';
	openPanel('tabmenu');
}

$('tabmenu').addEventListener('click', e => {
	const el = e.target.closest('[data-cmd]');
	if (!el) return;
	send('tabMenu', { id: menuTab, cmd: el.dataset.cmd });
	closePanel();
});

// --- Find in page -------------------------------------------------------------------------------

let findOpen = false;
const findQ = $('find-q');

function openFind() {
	if (!findOpen) {
		findOpen = true;
		body.classList.add('find');
		send('find', { action: 'open' });
	}
	findQ.focus({ preventScroll: true });
	findQ.select();
	if (findQ.value) send('find', { q: findQ.value });
}

function closeFind() {
	if (!findOpen) return;
	findOpen = false;
	body.classList.remove('find');
	$('find-count').textContent = '';
	send('find', { action: 'close' });
}

findQ.addEventListener('input', () => send('find', { q: findQ.value }));
findQ.addEventListener('keydown', e => {
	if (e.key === 'Enter') { e.preventDefault(); send('find', { action: e.shiftKey ? 'prev' : 'next' }); }
	else if (e.key === 'Escape') { e.preventDefault(); closeFind(); }
});
$('find-next').onclick = () => send('find', { action: 'next' });
$('find-prev').onclick = () => send('find', { action: 'prev' });
$('find-close').onclick = closeFind;

function renderFind(m) {
	const c = $('find-count');
	if (!findQ.value) { c.textContent = ''; c.classList.remove('none'); return; }
	c.textContent = m.count > 0 ? (m.index + 1) + ' of ' + m.count : 'No results';
	c.classList.toggle('none', m.count === 0);
}

// --- Go -------------------------------------------------------------------------------------------

renderNav();
renderDlButton();
send('ready');
