// Oazy Terminal's page: tabs, split panes and xterm.js terminals, talking to
// oazy_terminal.cs. Terminal traffic is plain strings ("o<id>:" output in,
// "i<id>:" keys out, "a<id>:<n>" output drawn); the rest is JSON objects.
'use strict';

const wv = (window.chrome && window.chrome.webview) || window.__oazyMock || null;
const $ = id => document.getElementById(id);
const body = document.body;

function send(t, extra) {
	if (wv) wv.postMessage(Object.assign({ t: t }, extra || {}));
}
function sendRaw(s) {
	if (wv) wv.postMessage(s);
}

const S = { profiles: [], defaultProfile: '', glass: true, nativeDrag: false, build: 22631, selftest: false, maximized: false };
const DEFAULTS = {
	fontSize: 14, fontFamily: 'JetBrains Mono', lineHeight: 1.2, cursorStyle: 'bar', cursorBlink: true,
	glass: 0.62, shiftEnter: true, copyOnSelect: false, defaultProfile: '',
};
let prefs = Object.assign({}, DEFAULTS);
const FONTS = ['JetBrains Mono', 'Cascadia Code', 'Cascadia Mono', 'Consolas'];
const FALLBACK = '"Cascadia Mono", Consolas, "Segoe UI Emoji", "Segoe UI Symbol", monospace';

// Oazy's colours: aqua-leaning, soft on glass, every pair readable.
const THEME = {
	background: 'rgba(0,0,0,0)',
	foreground: '#e3e9ee',
	cursor: '#38d6c4',
	cursorAccent: '#06131a',
	selectionBackground: 'rgba(56,214,196,0.30)',
	selectionInactiveBackground: 'rgba(255,255,255,0.12)',
	scrollbarSliderBackground: 'rgba(255,255,255,0.12)',
	scrollbarSliderHoverBackground: 'rgba(255,255,255,0.22)',
	scrollbarSliderActiveBackground: 'rgba(255,255,255,0.3)',
	overviewRulerBorder: 'rgba(0,0,0,0)',
	black: '#1a242d', red: '#ff6b81', green: '#5fe3a1', yellow: '#ffd27a',
	blue: '#6cb2ff', magenta: '#c79bff', cyan: '#45dccb', white: '#c6d0d9',
	brightBlack: '#5d6d7c', brightRed: '#ff8ea0', brightGreen: '#8ff2c2', brightYellow: '#ffe2a6',
	brightBlue: '#9dccff', brightMagenta: '#dcbfff', brightCyan: '#86efe2', brightWhite: '#ffffff',
};

$('newtab').innerHTML = icon('plus', 16);
$('profiles-btn').innerHTML = icon('chevron', 14);
$('settings-btn').innerHTML = icon('settings', 16);
$('win-min').innerHTML = icon('min', 15);
$('win-max').innerHTML = icon('max', 13);
$('win-close').innerHTML = icon('close', 15);
$('findbar').querySelector('.find-glyph').innerHTML = icon('search', 15);
$('find-prev').innerHTML = icon('up', 15);
$('find-next').innerHTML = icon('down', 15);
$('find-close').innerHTML = icon('close', 14);

// --- State ------------------------------------------------------------------------

let nextId = 1;
const panes = new Map();
const tabs = [];
let active = null;
let fontsReady = null;

// A tab holds a tree of panes: a leaf is {pane}, a split is
// {dir: 'v' (side by side) | 'h' (stacked), ratio, a, b}.

function profileById(id) {
	return S.profiles.find(p => p.id === id) || null;
}

function defaultProfile() {
	return profileById(prefs.defaultProfile) ? prefs.defaultProfile : (profileById(S.defaultProfile) ? S.defaultProfile : (S.profiles[0] ? S.profiles[0].id : ''));
}

function profileIcon(p) {
	const prof = profileById(p.launch.profile);
	if (p.launch.run && /claude/i.test(p.launch.run + ' ' + p.launch.title)) return 'claude';
	return prof ? prof.icon : 'cmd';
}

// --- Terminals --------------------------------------------------------------------

function termOptions() {
	return {
		fontFamily: '"' + prefs.fontFamily + '", ' + FALLBACK,
		fontSize: prefs.fontSize,
		lineHeight: prefs.lineHeight,
		letterSpacing: 0,
		fontWeight: 400,
		fontWeightBold: 700,
		cursorStyle: prefs.cursorStyle,
		cursorBlink: prefs.cursorBlink,
		cursorInactiveStyle: 'outline',
		cursorWidth: 2,
		allowTransparency: true,
		allowProposedApi: true,
		scrollback: 10000,
		smoothScrollDuration: 90,
		fastScrollSensitivity: 5,
		drawBoldTextInBrightColors: false,
		minimumContrastRatio: 1,
		rescaleOverlappingGlyphs: true,
		customGlyphs: true,
		macOptionIsMeta: true,
		windowsPty: { backend: 'conpty', buildNumber: S.build },
		theme: THEME,
		linkHandler: {
			activate: (e, uri) => openLink(e, uri),
			allowNonHttpProtocols: false,
		},
		overviewRuler: { width: 8 },
	};
}

function makePane(launch) {
	const id = nextId++;
	const el = document.createElement('div');
	el.className = 'pane pop';
	const host = document.createElement('div');
	host.className = 'host';
	el.appendChild(host);
	const p = {
		id: id, el: el, host: host, launch: Object.assign({ profile: '', cwd: '', run: '', title: '' }, launch || {}),
		term: null, fit: null, search: null, title: '', exited: false, started: false, tab: null,
	};
	if (!p.launch.run && !profileById(p.launch.profile)) p.launch.profile = defaultProfile();
	panes.set(id, p);
	el.addEventListener('mousedown', () => focusPane(p, false), true);
	el.addEventListener('mouseup', () => {
		if (prefs.copyOnSelect && p.term && p.term.hasSelection()) copyText(p.term.getSelection(), false);
	});
	setTimeout(() => el.classList.remove('pop'), 300);
	return p;
}

function openTerm(p) {
	if (p.term) return;
	const term = new Terminal(termOptions());
	p.term = term;
	p.fit = new FitAddon.FitAddon();
	term.loadAddon(p.fit);
	p.search = new SearchAddon.SearchAddon({ highlightLimit: 2000 });
	term.loadAddon(p.search);
	term.loadAddon(new Unicode11Addon.Unicode11Addon());
	term.unicode.activeVersion = '11';
	term.loadAddon(new WebLinksAddon.WebLinksAddon((e, uri) => openLink(e, uri)));
	term.open(p.host);
	term.attachCustomKeyEventHandler(e => onTermKey(p, e));
	term.onData(d => input(p, d));
	term.onBinary(d => input(p, d));
	term.onResize(sz => queueResize(p, sz.cols, sz.rows));
	term.onTitleChange(t => { p.title = cleanTitle(t); renderTab(p.tab); if (p.tab === active) pushTitle(); });
	term.onBell(() => bell(p));
	p.search.onDidChangeResults(r => { if (find.pane === p) showCount(r); });
	try { p.fit.fit(); } catch (e) { }
}

function spawn(p) {
	if (!p.term) return;
	p.exited = false;
	p.started = true;
	send('spawn', { id: p.id, profile: p.launch.profile, run: p.launch.run, cwd: p.launch.cwd, cols: p.term.cols, rows: p.term.rows });
}

function input(p, d) {
	if (p.exited) {
		// Enter brings an ended shell back.
		if (d === '\r') restart(p);
		return;
	}
	if (!p.started) return;
	sendRaw('i' + p.id + ':' + d);
}

function restart(p) {
	p.term.reset();
	p.tab && p.tab.el.classList.remove('exited');
	spawn(p);
	renderTab(p.tab);
}

const resizeTimers = new Map();
function queueResize(p, cols, rows) {
	if (!p.started || p.exited) return;
	clearTimeout(resizeTimers.get(p.id));
	// While a window is being dragged bigger, tell the shell once it settles.
	resizeTimers.set(p.id, setTimeout(() => send('resize', { id: p.id, cols: cols, rows: rows }), 40));
}

function output(id, data) {
	const p = panes.get(id);
	if (!p || !p.term) {
		sendRaw('a' + id + ':' + data.length);
		return;
	}
	const n = data.length;
	p.term.write(data, () => sendRaw('a' + id + ':' + n));
}

function cleanTitle(t) {
	t = String(t || '').trim();
	// Shells like to title themselves with their own exe path.
	if (/^[a-z]:\\.*\.exe$/i.test(t)) return '';
	return t;
}

function paneTitle(p) {
	if (!p) return '';
	if (p.title) return p.title;
	if (p.launch.title) return p.launch.title;
	const prof = profileById(p.launch.profile);
	return prof ? prof.name : 'Terminal';
}

function bell(p) {
	if (p.tab !== active || !document.hasFocus()) {
		p.tab.belled = true;
		renderTab(p.tab);
	}
	send('bell');
}

function openLink(e, uri) {
	if (!/^https?:\/\//i.test(uri)) return;
	send('open', { url: uri });
}

// --- Tabs ---------------------------------------------------------------------------

function newTab(launch, at) {
	const view = document.createElement('div');
	view.className = 'tabview';
	$('stage').appendChild(view);
	const p = makePane(launch);
	const tab = { root: { pane: p }, focused: p, view: view, el: null, belled: false };
	p.tab = tab;
	view.appendChild(p.el);
	if (at == null || at < 0 || at > tabs.length) tabs.push(tab);
	else tabs.splice(at, 0, tab);
	buildTabEl(tab);
	activate(tab);
	whenFonts(() => {
		layout(tab);
		openTerm(p);
		spawn(p);
		focusPane(p, true);
	});
	return tab;
}

function buildTabEl(tab) {
	const el = document.createElement('div');
	el.className = 'tab new';
	el.setAttribute('role', 'tab');
	el.innerHTML = '<span class="mark"></span><span class="title"></span><span class="panes"></span><button class="x" title="Close tab (Ctrl+Shift+W)">' + icon('close', 13) + '</button>';
	tab.el = el;
	el.querySelector('.x').addEventListener('click', e => { e.stopPropagation(); closeTab(tab); });
	el.addEventListener('mousedown', e => {
		if (e.button === 1) { e.preventDefault(); closeTab(tab); return; }
		if (e.button !== 0 || e.target.closest('.x')) return;
		activate(tab);
		startTabDrag(tab, e);
	});
	setTimeout(() => el.classList.remove('new'), 300);
	renderTabs();
}

function renderTabs() {
	const box = $('tabs');
	for (const t of tabs) if (t.el.parentNode !== box || t.el !== box.children[tabs.indexOf(t)]) box.insertBefore(t.el, box.children[tabs.indexOf(t)] || null);
	for (const t of tabs) {
		renderTab(t);
		t.el.classList.toggle('before-active', tabs[tabs.indexOf(t) + 1] === active);
	}
	box.style.flexBasis = (tabs.length * 222) + 'px';
	const tiny = tabs.length > 0 && box.clientWidth / tabs.length < 90;
	for (const t of tabs) t.el.classList.toggle('tiny', tiny);
}

function renderTab(tab) {
	if (!tab || !tab.el) return;
	const p = tab.focused;
	const all = leaves(tab.root);
	const kind = profileIcon(p);
	const mark = tab.el.querySelector('.mark');
	if (mark.dataset.kind !== kind) {
		mark.dataset.kind = kind;
		mark.innerHTML = profileMark(kind, 18) + '<i class="bell"></i>';
	}
	tab.el.querySelector('.title').textContent = paneTitle(p);
	tab.el.title = paneTitle(p);
	const count = tab.el.querySelector('.panes');
	count.textContent = all.length > 1 ? all.length : '';
	count.style.display = all.length > 1 ? '' : 'none';
	tab.el.classList.toggle('active', tab === active);
	tab.el.classList.toggle('exited', all.every(x => x.exited));
	tab.el.classList.toggle('belled', !!tab.belled && tab !== active);
}

function activate(tab) {
	if (!tab) return;
	const prev = active;
	active = tab;
	tab.belled = false;
	for (const t of tabs) t.view.classList.toggle('active', t === tab);
	renderTabs();
	if (prev !== tab) {
		closeFind();
		whenFonts(() => { layout(tab); focusPane(tab.focused, true); });
	}
	pushTitle();
}

function closeTab(tab) {
	const i = tabs.indexOf(tab);
	if (i < 0) return;
	for (const p of leaves(tab.root)) disposePane(p);
	tabs.splice(i, 1);
	tab.el.remove();
	tab.view.remove();
	if (tabs.length === 0) {
		send('cmd', { cmd: 'forceClose' });
		return;
	}
	if (active === tab) activate(tabs[Math.min(i, tabs.length - 1)]);
	else renderTabs();
}

function cycleTab(dir) {
	if (tabs.length < 2) return;
	activate(tabs[(tabs.indexOf(active) + dir + tabs.length) % tabs.length]);
}

function pushTitle() {
	if (!active) return;
	const p = active.focused;
	send('title', { text: p.launch.title || paneTitle(p) });
}

// Drag a tab sideways to reorder.
function startTabDrag(tab, e) {
	const x0 = e.clientX;
	let dragging = false;
	const move = ev => {
		if (!dragging && Math.abs(ev.clientX - x0) < 6) return;
		if (!dragging) { dragging = true; tab.el.classList.add('dragging'); }
		let to = 0;
		for (const t of tabs) {
			if (t === tab) continue;
			const r = t.el.getBoundingClientRect();
			if (ev.clientX > r.left + r.width / 2) to++;
		}
		if (tabs.indexOf(tab) !== to) {
			tabs.splice(tabs.indexOf(tab), 1);
			tabs.splice(to, 0, tab);
			renderTabs();
		}
	};
	const up = () => {
		window.removeEventListener('mousemove', move);
		window.removeEventListener('mouseup', up);
		tab.el.classList.remove('dragging');
	};
	window.addEventListener('mousemove', move);
	window.addEventListener('mouseup', up);
}

// --- Panes and splits ------------------------------------------------------------------

function leaves(node, out) {
	out = out || [];
	if (node.pane) out.push(node.pane);
	else { leaves(node.a, out); leaves(node.b, out); }
	return out;
}

function findLeaf(node, p, parent) {
	if (node.pane === p) return { node: node, parent: parent };
	if (node.pane) return null;
	return findLeaf(node.a, p, node) || findLeaf(node.b, p, node);
}

function split(dir, launch) {
	const tab = active;
	if (!tab) return;
	const cur = tab.focused;
	const leaf = findLeaf(tab.root, cur, null);
	if (!leaf) return;
	if (!dir) {
		// Split along the longer side.
		const r = cur.el.getBoundingClientRect();
		dir = r.width >= r.height * 1.6 ? 'v' : 'h';
	}
	if (!launch) {
		const prof = cur.launch.run || cur.launch.profile === 'claude' ? defaultProfile() : cur.launch.profile;
		launch = { profile: prof, cwd: cur.launch.cwd };
	}
	const p = makePane(launch);
	p.tab = tab;
	const node = leaf.node;
	delete node.pane;
	node.dir = dir;
	node.ratio = 0.5;
	node.a = { pane: cur };
	node.b = { pane: p };
	tab.view.appendChild(p.el);
	layout(tab);
	openTerm(p);
	spawn(p);
	focusPane(p, true);
	renderTab(tab);
}

function closePane(p) {
	const tab = p.tab;
	if (!tab) return;
	const leaf = findLeaf(tab.root, p, null);
	if (!leaf) return;
	if (!leaf.parent) { closeTab(tab); return; }
	const parent = leaf.parent;
	const sibling = parent.a === leaf.node ? parent.b : parent.a;
	delete parent.dir; delete parent.ratio; delete parent.a; delete parent.b;
	Object.assign(parent, sibling);
	disposePane(p);
	if (tab.focused === p) tab.focused = leaves(parent)[0];
	layout(tab);
	focusPane(tab.focused, true);
	renderTab(tab);
}

function disposePane(p) {
	if (p.started && !p.exited) send('kill', { id: p.id });
	panes.delete(p.id);
	if (find.pane === p) closeFind();
	try { if (p.term) p.term.dispose(); } catch (e) { }
	p.el.remove();
}

function focusPane(p, takeFocus) {
	if (!p || !p.tab) return;
	const tab = p.tab;
	const changed = tab.focused !== p;
	tab.focused = p;
	for (const x of leaves(tab.root)) x.el.classList.toggle('focused', x === p);
	if (takeFocus && p.term && tab === active) p.term.focus();
	if (changed) {
		renderTab(tab);
		if (tab === active) pushTitle();
		if (find.open) { closeFind(); }
	}
}

// Moves focus to the nearest pane in a direction.
function focusDir(dx, dy) {
	const tab = active;
	const all = leaves(tab.root);
	if (all.length < 2) return false;
	const r0 = tab.focused.el.getBoundingClientRect();
	const cx = r0.left + r0.width / 2, cy = r0.top + r0.height / 2;
	let best = null, bestD = Infinity;
	for (const p of all) {
		if (p === tab.focused) continue;
		const r = p.el.getBoundingClientRect();
		const px = r.left + r.width / 2, py = r.top + r.height / 2;
		const ax = px - cx, ay = py - cy;
		if (dx && Math.sign(ax) !== dx) continue;
		if (dy && Math.sign(ay) !== dy) continue;
		if (dx && (r.bottom <= r0.top || r.top >= r0.bottom)) continue;
		if (dy && (r.right <= r0.left || r.left >= r0.right)) continue;
		const d = Math.abs(ax) + Math.abs(ay);
		if (d < bestD) { bestD = d; best = p; }
	}
	if (best) focusPane(best, true);
	return true;
}

// Grows the focused pane a step in a direction.
function resizeDir(dx, dy) {
	const tab = active;
	const want = dx ? 'v' : 'h';
	let node = findLeaf(tab.root, tab.focused, null);
	let child = node ? node.node : null;
	let parent = node ? node.parent : null;
	while (parent) {
		if (parent.dir === want) {
			const grow = (parent.a === child ? 1 : -1) * (dx || dy);
			parent.ratio = Math.max(0.12, Math.min(0.88, parent.ratio + grow * 0.05));
			layout(tab);
			return true;
		}
		child = parent;
		const up = findParent(tab.root, parent, null);
		parent = up;
	}
	return leaves(tab.root).length > 1;
}

function findParent(node, target, parent) {
	if (node === target) return parent;
	if (node.pane) return null;
	return findParent(node.a, target, node) || findParent(node.b, target, node);
}

function layout(tab) {
	if (!tab) return;
	const stage = $('stage');
	const W = stage.clientWidth, H = stage.clientHeight;
	for (const d of tab.view.querySelectorAll('.divider')) d.remove();
	const all = leaves(tab.root);
	tab.view.classList.toggle('split', all.length > 1);
	place(tab, tab.root, { x: 0, y: 0, w: W, h: H });
	for (const p of all) if (p.term && p.fit) try { p.fit.fit(); } catch (e) { }
}

function place(tab, node, r) {
	if (node.pane) {
		const s = node.pane.el.style;
		s.left = r.x + 'px'; s.top = r.y + 'px'; s.width = r.w + 'px'; s.height = r.h + 'px';
		return;
	}
	const d = document.createElement('div');
	d.className = 'divider ' + node.dir;
	if (node.dir === 'v') {
		const w = Math.round(r.w * node.ratio);
		place(tab, node.a, { x: r.x, y: r.y, w: w, h: r.h });
		place(tab, node.b, { x: r.x + w, y: r.y, w: r.w - w, h: r.h });
		Object.assign(d.style, { left: (r.x + w - 4) + 'px', top: r.y + 'px', width: '8px', height: r.h + 'px' });
	} else {
		const h = Math.round(r.h * node.ratio);
		place(tab, node.a, { x: r.x, y: r.y, w: r.w, h: h });
		place(tab, node.b, { x: r.x, y: r.y + h, w: r.w, h: r.h - h });
		Object.assign(d.style, { left: r.x + 'px', top: (r.y + h - 4) + 'px', width: r.w + 'px', height: '8px' });
	}
	d.addEventListener('mousedown', e => {
		e.preventDefault();
		d.classList.add('dragging');
		const move = ev => {
			const pos = node.dir === 'v' ? (ev.clientX - r.x) / r.w : (ev.clientY - $('stage').getBoundingClientRect().top - r.y) / r.h;
			node.ratio = Math.max(0.12, Math.min(0.88, pos));
			layout(tab);
		};
		const up = () => {
			window.removeEventListener('mousemove', move);
			window.removeEventListener('mouseup', up);
			const nd = tab.view.querySelector('.divider.dragging');
			if (nd) nd.classList.remove('dragging');
			focusPane(tab.focused, true);
		};
		window.addEventListener('mousemove', move);
		window.addEventListener('mouseup', up);
	});
	tab.view.appendChild(d);
}

let layoutQueued = false;
window.addEventListener('resize', () => {
	if (layoutQueued) return;
	layoutQueued = true;
	requestAnimationFrame(() => {
		layoutQueued = false;
		for (const t of tabs) layout(t);
		renderTabs();
	});
});

function whenFonts(fn) {
	if (!fontsReady) {
		fontsReady = Promise.all([
			document.fonts.load(prefs.fontSize + 'px "' + prefs.fontFamily + '"'),
			document.fonts.load('bold ' + prefs.fontSize + 'px "' + prefs.fontFamily + '"'),
		]).catch(() => { });
	}
	fontsReady.then(fn);
}

// --- Keys ----------------------------------------------------------------------------

function onTermKey(p, e) {
	if (e.type !== 'keydown') return true;
	const handled = shortcut(e, p);
	if (handled) {
		e.preventDefault();
		e.stopPropagation();
		return false;
	}
	if (prefs.shiftEnter && e.key === 'Enter' && e.shiftKey && !e.ctrlKey && !e.altKey && !e.metaKey) {
		// A new line inside the prompt (Claude Code and friends), not "run it".
		e.preventDefault();
		input(p, '\x1b\r');
		return false;
	}
	return true;
}

function shortcut(e, p) {
	const k = e.key, code = e.code;
	const ctrl = e.ctrlKey, shift = e.shiftKey, alt = e.altKey;
	p = p || (active && active.focused);
	if (ctrl && shift && !alt) {
		if (code === 'KeyT') { newTab({ profile: defaultProfile() }); return true; }
		if (code === 'KeyW') { closePane(p); return true; }
		if (code === 'KeyN') { send('cmd', { cmd: 'newWindow' }); return true; }
		if (code === 'KeyC') { copySelection(p); return true; }
		if (code === 'KeyV') { paste(p); return true; }
		if (code === 'KeyF') { openFind(); return true; }
		if (code === 'KeyD') { duplicateTab(); return true; }
		if (code === 'Tab') { cycleTab(-1); return true; }
		if (/^Digit[1-9]$/.test(code)) {
			const prof = S.profiles[+code.slice(5) - 1];
			if (prof) newTab({ profile: prof.id });
			return true;
		}
	}
	if (ctrl && !shift && !alt) {
		if (code === 'Tab') { cycleTab(1); return true; }
		if (k === 'c' || code === 'KeyC') {
			// With a selection Ctrl+C copies; without, it's the usual interrupt.
			if (p && p.term && p.term.hasSelection()) { copySelection(p); return true; }
			return false;
		}
		if (code === 'KeyV') { paste(p); return true; }
		if (code === 'Equal' || code === 'NumpadAdd') { zoom(1); return true; }
		if (code === 'Minus' || code === 'NumpadSubtract') { zoom(-1); return true; }
		if (code === 'Digit0' || code === 'Numpad0') { zoom(0); return true; }
		if (code === 'Comma') { toggleSettings(); return true; }
	}
	if (ctrl && alt && !shift && /^Digit[1-9]$/.test(code)) {
		const n = +code.slice(5);
		const t = n === 9 ? tabs[tabs.length - 1] : tabs[n - 1];
		if (t) activate(t);
		return true;
	}
	if (!ctrl && shift && !alt && code === 'Insert') { paste(p); return true; }
	if (ctrl && !shift && !alt && code === 'Insert') { copySelection(p); return true; }
	if (alt && shift && !ctrl) {
		if (code === 'KeyD') { split(null); return true; }
		if (code === 'Equal' || code === 'NumpadAdd') { split('v'); return true; }
		if (code === 'Minus' || code === 'NumpadSubtract') { split('h'); return true; }
		if (code === 'ArrowLeft') return resizeDir(-1, 0);
		if (code === 'ArrowRight') return resizeDir(1, 0);
		if (code === 'ArrowUp') return resizeDir(0, -1);
		if (code === 'ArrowDown') return resizeDir(0, 1);
	}
	if (alt && !shift && !ctrl && active && leaves(active.root).length > 1) {
		if (code === 'ArrowLeft') return focusDir(-1, 0);
		if (code === 'ArrowRight') return focusDir(1, 0);
		if (code === 'ArrowUp') return focusDir(0, -1);
		if (code === 'ArrowDown') return focusDir(0, 1);
	}
	return false;
}

// Shortcuts still work while focus is on the chrome (tabs, find, settings).
window.addEventListener('keydown', e => {
	if (e.target && e.target.closest && e.target.closest('.xterm')) return;
	if (e.key === 'Escape') {
		if (closePanels()) { e.preventDefault(); return; }
	}
	if (e.target && e.target.tagName === 'INPUT' && !(e.ctrlKey && e.shiftKey)) return;
	if (shortcut(e, null)) e.preventDefault();
});

function duplicateTab() {
	if (!active) return;
	const p = active.focused;
	newTab(Object.assign({}, p.launch), tabs.indexOf(active) + 1);
}

function zoom(dir) {
	const size = dir === 0 ? DEFAULTS.fontSize : Math.max(8, Math.min(32, prefs.fontSize + dir));
	setPrefs({ fontSize: size });
	toast('Text size ' + size);
}

window.addEventListener('wheel', e => {
	if (!e.ctrlKey) return;
	e.preventDefault();
	zoom(e.deltaY < 0 ? 1 : -1);
}, { passive: false });

// --- Clipboard ------------------------------------------------------------------------

function copySelection(p) {
	if (!p || !p.term || !p.term.hasSelection()) return;
	copyText(p.term.getSelection(), true);
	p.term.clearSelection();
}

function copyText(text, say) {
	if (!text) return;
	send('copy', { text: text });
	if (say) toast('Copied');
}

const pasteFor = { id: 0 };
function paste(p) {
	if (!p) return;
	pasteFor.id = p.id;
	send('paste', { id: p.id });
}

function onPaste(m) {
	const p = panes.get(m.id);
	if (!p || !p.term || !m.text) return;
	if (p.exited) return;
	p.term.paste(m.text);
	p.term.scrollToBottom();
}

// --- Find ------------------------------------------------------------------------------

const find = { open: false, pane: null, caseSensitive: false, regex: false };

function searchOpts(incremental) {
	return {
		caseSensitive: find.caseSensitive,
		regex: find.regex,
		incremental: !!incremental,
		decorations: {
			matchBackground: '#1f5f66',
			matchBorder: 'rgba(56,214,196,0.35)',
			matchOverviewRuler: '#38d6c4',
			activeMatchBackground: '#38d6c4',
			activeMatchBorder: '#9ff5ea',
			activeMatchColorOverviewRuler: '#ffffff',
		},
	};
}

function openFind(q) {
	if (!active) return;
	find.open = true;
	find.pane = active.focused;
	const bar = $('findbar');
	bar.classList.add('open');
	const input = $('find-q');
	if (q != null) input.value = q;
	else if (find.pane.term && find.pane.term.hasSelection()) {
		const sel = find.pane.term.getSelection();
		if (sel.length < 200 && sel.indexOf('\n') < 0) input.value = sel;
	}
	input.focus();
	input.select();
	if (input.value) runFind(1, true);
}

function closeFind() {
	if (!find.open) return;
	find.open = false;
	$('findbar').classList.remove('open', 'none');
	if (find.pane && find.pane.search) find.pane.search.clearDecorations();
	const p = find.pane;
	find.pane = null;
	if (p && p.term) p.term.focus();
}

function runFind(dir, incremental) {
	const p = find.pane;
	if (!p || !p.search) return;
	const q = $('find-q').value;
	if (!q) {
		p.search.clearDecorations();
		$('find-count').textContent = '';
		$('findbar').classList.remove('none');
		return;
	}
	let found;
	try { found = dir < 0 ? p.search.findPrevious(q, searchOpts(false)) : p.search.findNext(q, searchOpts(incremental)); }
	catch (e) { found = false; }
	if (!found) showCount({ resultIndex: -1, resultCount: 0 });
}

function showCount(r) {
	const none = r.resultCount === 0 && $('find-q').value !== '';
	$('findbar').classList.toggle('none', none);
	$('find-count').textContent = none ? 'No results' : (r.resultCount ? (r.resultIndex + 1) + '/' + r.resultCount : '');
}

$('find-q').addEventListener('input', () => runFind(1, true));
$('find-q').addEventListener('keydown', e => {
	if (e.key === 'Enter') { e.preventDefault(); runFind(e.shiftKey ? -1 : 1, false); }
	else if (e.key === 'Escape') { e.preventDefault(); closeFind(); }
});
$('find-next').onclick = () => runFind(1, false);
$('find-prev').onclick = () => runFind(-1, false);
$('find-close').onclick = () => closeFind();
$('find-case').onclick = () => { find.caseSensitive = !find.caseSensitive; $('find-case').classList.toggle('on', find.caseSensitive); runFind(1, true); $('find-q').focus(); };
$('find-regex').onclick = () => { find.regex = !find.regex; $('find-regex').classList.toggle('on', find.regex); runFind(1, true); $('find-q').focus(); };

// --- Panels: profiles, context menu, settings ------------------------------------------------

let openPanel = null;

function showPanel(el, opts) {
	closePanels();
	openPanel = el;
	el.classList.add('open');
	$('veil').classList.add('open');
	$('veil').classList.toggle('dim', !!(opts && opts.dim));
}

function closePanels() {
	if (!openPanel) return false;
	openPanel.classList.remove('open');
	$('veil').classList.remove('open', 'dim');
	$('profiles-btn').classList.remove('open');
	$('settings-btn').classList.remove('open');
	openPanel = null;
	if (active && active.focused && active.focused.term && !find.open) active.focused.term.focus();
	return true;
}

$('veil').addEventListener('mousedown', e => { e.preventDefault(); closePanels(); });

function menuItem(label, opts) {
	const b = document.createElement('button');
	b.className = 'item' + (opts.disabled ? ' disabled' : '');
	b.innerHTML = (opts.mark || (opts.icon ? icon(opts.icon, 16) : '')) + '<span class="label">' + esc(label) + '</span>' +
		(opts.badge ? '<span class="default">' + esc(opts.badge) + '</span>' : '') +
		(opts.key ? '<span class="key">' + esc(opts.key) + '</span>' : '');
	b.addEventListener('click', () => { closePanels(); opts.run(); });
	return b;
}

function sep() {
	const d = document.createElement('div');
	d.className = 'sep';
	return d;
}

function showProfiles() {
	const box = $('profiles');
	box.innerHTML = '';
	const def = defaultProfile();
	S.profiles.forEach((prof, i) => {
		box.appendChild(menuItem(prof.name, {
			mark: profileMark(prof.icon, 20),
			badge: prof.id === def ? 'Default' : '',
			key: i < 9 ? 'Ctrl+Shift+' + (i + 1) : '',
			run: () => newTab({ profile: prof.id }),
		}));
	});
	box.appendChild(sep());
	box.appendChild(menuItem('Split pane', { icon: 'splitRight', key: 'Alt+Shift+D', run: () => split(null) }));
	box.appendChild(menuItem('New window', { icon: 'window', key: 'Ctrl+Shift+N', run: () => send('cmd', { cmd: 'newWindow' }) }));
	box.appendChild(menuItem('Settings', { icon: 'settings', key: 'Ctrl+,', run: () => toggleSettings() }));
	const r = $('newtab-group').getBoundingClientRect();
	box.style.left = Math.max(8, Math.min(r.left, window.innerWidth - 260)) + 'px';
	showPanel(box);
	$('profiles-btn').classList.add('open');
}

function showContext(p, x, y) {
	const box = $('context');
	box.innerHTML = '';
	const sel = p.term && p.term.hasSelection();
	box.appendChild(menuItem('Copy', { icon: 'copy', key: 'Ctrl+C', disabled: !sel, run: () => copySelection(p) }));
	box.appendChild(menuItem('Paste', { icon: 'paste', key: 'Ctrl+V', run: () => paste(p) }));
	box.appendChild(sep());
	box.appendChild(menuItem('Split right', { icon: 'splitRight', key: 'Alt+Shift+=', run: () => { focusPane(p); split('v'); } }));
	box.appendChild(menuItem('Split down', { icon: 'splitDown', key: 'Alt+Shift+-', run: () => { focusPane(p); split('h'); } }));
	box.appendChild(menuItem('Find', { icon: 'search', key: 'Ctrl+Shift+F', run: () => { focusPane(p); openFind(); } }));
	box.appendChild(menuItem('Clear', { icon: 'clear', run: () => { p.term.clear(); } }));
	if (p.exited) box.appendChild(menuItem('Restart', { icon: 'restart', key: 'Enter', run: () => restart(p) }));
	box.appendChild(sep());
	box.appendChild(menuItem(leaves(p.tab.root).length > 1 ? 'Close pane' : 'Close tab', { icon: 'close', key: 'Ctrl+Shift+W', run: () => closePane(p) }));
	showPanel(box);
	const w = box.offsetWidth, h = box.offsetHeight;
	box.style.left = Math.min(x, window.innerWidth - w - 8) + 'px';
	box.style.top = Math.min(y, window.innerHeight - h - 8) + 'px';
}

$('stage').addEventListener('contextmenu', e => {
	e.preventDefault();
	const el = e.target.closest('.pane');
	if (!el) return;
	const p = [...panes.values()].find(x => x.el === el);
	if (!p || !p.term) return;
	// Programs that track the mouse get the right button; Shift still opens the menu.
	if (p.term.modes.mouseTrackingMode !== 'none' && !e.shiftKey) return;
	focusPane(p, false);
	showContext(p, e.clientX, e.clientY);
});

function toggleSettings() {
	if (openPanel === $('settings')) { closePanels(); return; }
	renderSettings();
	showPanel($('settings'));
	$('settings-btn').classList.add('open');
}

function renderSettings() {
	const box = $('settings');
	const def = defaultProfile();
	let h = '<h2>Terminal</h2><div class="sub">Changes apply to every window straight away.</div>';
	h += '<div class="row"><div class="label">Opens with</div><div class="chips">';
	for (const prof of S.profiles) h += '<button class="chip' + (prof.id === def ? ' on' : '') + '" data-profile="' + esc(prof.id) + '">' + profileMark(prof.icon, 16) + esc(prof.name) + '</button>';
	h += '</div></div>';
	h += '<div class="row"><div class="label">Font</div><div class="chips">';
	const known = FONTS.indexOf(prefs.fontFamily) >= 0;
	for (const f of FONTS) h += '<button class="chip' + (f === prefs.fontFamily ? ' on' : '') + '" data-font="' + esc(f) + '" style="font-family:\'' + f + '\',monospace">' + esc(f) + '</button>';
	h += '</div><input class="text-in" id="font-custom" spellcheck="false" placeholder="Another installed font, like a Nerd Font" value="' + (known ? '' : esc(prefs.fontFamily)) + '"></div>';
	h += '<div class="row line"><div class="label">Text size</div><div class="stepper"><button class="icon-btn small" data-step="-1">' + icon('min', 14) + '</button><b>' + prefs.fontSize + '</b><button class="icon-btn small" data-step="1">' + icon('plus', 14) + '</button></div></div>';
	h += '<div class="row"><div class="label">Line spacing <b>' + prefs.lineHeight.toFixed(2) + '</b></div><input type="range" id="line-height" min="1" max="1.6" step="0.05" value="' + prefs.lineHeight + '"></div>';
	h += '<div class="row"><div class="label">Cursor</div><div class="chips">';
	for (const c of [['bar', 'Bar'], ['block', 'Block'], ['underline', 'Underline']]) h += '<button class="chip' + (c[0] === prefs.cursorStyle ? ' on' : '') + '" data-cursor="' + c[0] + '">' + c[1] + '</button>';
	h += '<button class="chip' + (prefs.cursorBlink ? ' on' : '') + '" data-blink="1">Blink</button></div></div>';
	if (S.glass) h += '<div class="row"><div class="label">Glass <b>' + Math.round((1 - prefs.glass) * 100) + '%</b></div><input type="range" id="glass" min="0" max="100" step="1" value="' + Math.round((1 - prefs.glass) * 100) + '"></div>';
	h += '<div class="row line"><div><div class="label">Shift+Enter starts a new line</div><div class="hint">For Claude Code and other prompts that take several lines.</div></div><button class="switch' + (prefs.shiftEnter ? ' on' : '') + '" data-toggle="shiftEnter"></button></div>';
	h += '<div class="row line"><div><div class="label">Copy when you select</div><div class="hint">Ctrl+C copies a selection either way.</div></div><button class="switch' + (prefs.copyOnSelect ? ' on' : '') + '" data-toggle="copyOnSelect"></button></div>';
	h += '<div class="row"><div class="label">Shortcuts</div><div class="keys">' +
		'<span>New tab</span><kbd>Ctrl+Shift+T</kbd>' +
		'<span>Split pane</span><kbd>Alt+Shift+D</kbd>' +
		'<span>Move between panes</span><kbd>Alt+Arrows</kbd>' +
		'<span>Resize pane</span><kbd>Alt+Shift+Arrows</kbd>' +
		'<span>Close pane</span><kbd>Ctrl+Shift+W</kbd>' +
		'<span>Find</span><kbd>Ctrl+Shift+F</kbd>' +
		'<span>Switch tab</span><kbd>Ctrl+Tab</kbd>' +
		'<span>Text size</span><kbd>Ctrl+Wheel</kbd>' +
		'</div></div>';
	box.innerHTML = h;
	box.querySelectorAll('[data-profile]').forEach(b => b.onclick = () => { setPrefs({ defaultProfile: b.dataset.profile }); renderSettings(); });
	box.querySelectorAll('[data-font]').forEach(b => b.onclick = () => { setPrefs({ fontFamily: b.dataset.font }); renderSettings(); });
	box.querySelectorAll('[data-step]').forEach(b => b.onclick = () => { zoom(+b.dataset.step); renderSettings(); });
	box.querySelectorAll('[data-cursor]').forEach(b => b.onclick = () => { setPrefs({ cursorStyle: b.dataset.cursor }); renderSettings(); });
	box.querySelectorAll('[data-blink]').forEach(b => b.onclick = () => { setPrefs({ cursorBlink: !prefs.cursorBlink }); renderSettings(); });
	box.querySelectorAll('[data-toggle]').forEach(b => b.onclick = () => { const k = b.dataset.toggle; const o = {}; o[k] = !prefs[k]; setPrefs(o); b.classList.toggle('on', prefs[k]); });
	const custom = $('font-custom');
	custom.addEventListener('change', () => { const v = custom.value.trim(); if (v) { setPrefs({ fontFamily: v }); renderSettings(); } });
	custom.addEventListener('keydown', e => { if (e.key === 'Enter') custom.blur(); });
	const lh = $('line-height');
	fillRange(lh);
	lh.addEventListener('input', () => { fillRange(lh); setPrefs({ lineHeight: +lh.value }); lh.parentNode.querySelector('b').textContent = (+lh.value).toFixed(2); });
	const g = $('glass');
	if (g) {
		fillRange(g);
		g.addEventListener('input', () => { fillRange(g); setPrefs({ glass: 1 - g.value / 100 }); g.parentNode.querySelector('b').textContent = g.value + '%'; });
	}
}

function fillRange(r) {
	r.style.setProperty('--fill', ((r.value - r.min) / (r.max - r.min) * 100) + '%');
}

// --- Prefs ------------------------------------------------------------------------------

let prefsTimer = 0;
const prefsOut = {};
function setPrefs(change) {
	Object.assign(prefs, change);
	Object.assign(prefsOut, change);
	applyPrefs(change);
	clearTimeout(prefsTimer);
	prefsTimer = setTimeout(() => {
		send('prefs', { prefs: Object.assign({}, prefsOut) });
		for (const k in prefsOut) delete prefsOut[k];
	}, 250);
}

function applyPrefs(change) {
	document.documentElement.style.setProperty('--tint', String(Math.max(0, Math.min(1, prefs.glass))));
	const termKeys = ['fontSize', 'fontFamily', 'lineHeight', 'cursorStyle', 'cursorBlink'];
	if (!change || termKeys.some(k => k in change)) {
		const fontChanged = !change || 'fontFamily' in change || 'fontSize' in change;
		const apply = () => {
			const o = termOptions();
			for (const p of panes.values()) {
				if (!p.term) continue;
				p.term.options.fontFamily = o.fontFamily;
				p.term.options.fontSize = o.fontSize;
				p.term.options.lineHeight = o.lineHeight;
				p.term.options.cursorStyle = o.cursorStyle;
				p.term.options.cursorBlink = o.cursorBlink;
			}
			for (const t of tabs) layout(t);
		};
		if (fontChanged) {
			fontsReady = null;
			whenFonts(apply);
		} else apply();
	}
}

function setAccent(hex) {
	const m = /^#?([0-9a-f]{6})$/i.exec(hex || '');
	if (!m) return;
	const n = parseInt(m[1], 16);
	document.documentElement.style.setProperty('--accent', '#' + m[1]);
	document.documentElement.style.setProperty('--accent-rgb', (n >> 16) + ', ' + ((n >> 8) & 255) + ', ' + (n & 255));
	THEME.cursor = '#' + m[1];
	THEME.selectionBackground = 'rgba(' + (n >> 16) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',0.30)';
	for (const p of panes.values()) if (p.term) p.term.options.theme = Object.assign({}, THEME);
}

// --- Toast, confirm ---------------------------------------------------------------------

let toastTimer = 0;
function toast(text) {
	const t = $('toast');
	t.textContent = text;
	t.classList.add('show');
	clearTimeout(toastTimer);
	toastTimer = setTimeout(() => t.classList.remove('show'), 1400);
}

function confirmClose(count) {
	const box = $('confirm');
	box.querySelector('.confirm-title').textContent = 'Close ' + count + ' terminals?';
	showPanel(box, { dim: true });
	$('confirm-yes').focus();
}
$('confirm-no').onclick = () => closePanels();
$('confirm-yes').onclick = () => { closePanels(); send('cmd', { cmd: 'forceClose' }); };

// --- Window chrome ----------------------------------------------------------------------

$('newtab').onclick = () => newTab({ profile: defaultProfile() });
$('profiles-btn').onclick = () => { if (openPanel === $('profiles')) closePanels(); else showProfiles(); };
$('settings-btn').onclick = () => toggleSettings();
$('win-min').onclick = () => send('cmd', { cmd: 'minimize' });
$('win-max').onclick = () => send('cmd', { cmd: 'maximize' });
$('win-close').onclick = () => send('cmd', { cmd: 'close' });

for (const el of [$('strip'), $('drag'), $('tabs')]) {
	el.addEventListener('mousedown', e => {
		if (e.target !== el || e.button !== 0 || S.nativeDrag) return;
		send('drag');
	});
	el.addEventListener('dblclick', e => {
		if (e.target !== el) return;
		if (el === $('tabs')) newTab({ profile: defaultProfile() });
		else send('cmd', { cmd: 'maximize' });
	});
}

// --- From the host ------------------------------------------------------------------------

function onHost(e) {
	const d = e.data;
	if (typeof d === 'string') {
		if (d.charCodeAt(0) === 111) { // 'o'
			const c = d.indexOf(':');
			output(+d.slice(1, c), d.slice(c + 1));
		}
		return;
	}
	const m = d;
	if (!m || !m.t) return;
	switch (m.t) {
		case 'init': init(m); break;
		case 'started': {
			const p = panes.get(m.id);
			if (p) renderTab(p.tab);
			break;
		}
		case 'failed': {
			const p = panes.get(m.id);
			if (!p) break;
			p.exited = true;
			p.term.write('\x1b[38;2;255;107;129m  Couldn\'t start ' + (m.cmd || 'the shell') + '\x1b[0m\r\n  ' + (m.error || '') + '\r\n');
			renderTab(p.tab);
			break;
		}
		case 'exit': {
			const p = panes.get(m.id);
			if (!p || p.exited) break;
			p.exited = true;
			p.started = false;
			if (m.code === 0 && !S.selftest) { closePane(p); break; }
			p.term.write('\r\n\x1b[2m\x1b[38;2;150;160;175m[Exited with code ' + m.code + '. Press Enter to start again, or Ctrl+Shift+W to close.]\x1b[0m\r\n');
			renderTab(p.tab);
			break;
		}
		case 'paste': onPaste(m); break;
		case 'win':
			S.maximized = m.max;
			body.classList.toggle('maximized', m.max);
			$('win-max').innerHTML = icon(m.max ? 'restore' : 'max', 13);
			$('win-max').title = m.max ? 'Restore' : 'Maximise';
			break;
		case 'active':
			body.classList.toggle('inactive', !m.on);
			if (m.on && active && active.focused && active.focused.term && !openPanel && !find.open) active.focused.term.focus();
			break;
		case 'open': newTab(m.tab || {}); break;
		case 'prefs':
			Object.assign(prefs, m.prefs || {});
			applyPrefs(m.prefs || {});
			break;
		case 'confirmClose': confirmClose(m.count); break;
		case 'test': selftest(m); break;
	}
}

function init(m) {
	S.profiles = m.profiles || [];
	S.defaultProfile = m.defaultProfile || '';
	S.glass = m.glass !== false;
	S.nativeDrag = !!m.nativeDrag;
	S.build = m.build || S.build;
	S.selftest = !!m.selftest;
	body.classList.toggle('solid', !S.glass);
	Object.assign(prefs, m.prefs || {});
	for (const k in DEFAULTS) if (typeof prefs[k] !== typeof DEFAULTS[k]) prefs[k] = DEFAULTS[k];
	setAccent(m.accent);
	applyPrefs(null);
	const list = (m.tabs && m.tabs.length) ? m.tabs : [{}];
	for (const l of list) newTab(l);
}

function selftest(m) {
	const p = active && active.focused;
	switch (m.action) {
		case 'buffer': {
			const lines = [];
			for (const t of tabs) for (const x of leaves(t.root)) {
				if (!x.term) continue;
				const b = x.term.buffer.active;
				for (let i = 0; i < b.length; i++) { const l = b.getLine(i); if (l) lines.push(l.translateToString(true)); }
			}
			send('test', { what: 'buffer', text: lines.join('\n') });
			break;
		}
		case 'split': split('v', { profile: m.profile }); break;
		case 'menu': toggleSettings(); break;
		case 'closeMenu': closePanels(); break;
		case 'find': openFind(m.q); break;
	}
}

if (wv) {
	wv.addEventListener('message', onHost);
	send('ready');
}
