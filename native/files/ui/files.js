// Oazy Files' page: tabs, the sidebar, folder views (a virtual grid and a
// details list), Home, search, menus and drag and drop, talking to
// oazy_files.cs. Messages are JSON objects; requests carry "rid" and get a
// {"t": "reply", "rid"} back.
'use strict';

const wv = (window.chrome && window.chrome.webview) || window.__oazyMock || null;
const $ = id => document.getElementById(id);
const body = document.body;
const ICON_HOST = 'https://oazy-icons.example/i';

function send(t, extra) {
	if (wv) wv.postMessage(Object.assign({ t: t }, extra || {}));
}

let nextRid = 1;
const waiting = new Map();
function ask(t, extra, files) {
	return new Promise(resolve => {
		if (!wv) { resolve({}); return; }
		const rid = nextRid++;
		waiting.set(rid, resolve);
		const msg = Object.assign({ t: t, rid: rid }, extra || {});
		if (files && files.length && wv.postMessageWithAdditionalObjects) wv.postMessageWithAdditionalObjects(msg, files);
		else wv.postMessage(msg);
	});
}

const S = { glass: true, nativeDrag: false, selftest: false, maximized: false, places: null, recent: null, home: '', types: {}, kinds: new Map(), clip: null, system: 'C:\\' };
const DEFAULTS = {
	view: 'grid', iconSize: 88, showHidden: false, showExt: true, foldersFirst: true, thumbs: true,
	sort: 'name', desc: false, details: false, glass: 0.62, pinned: [], sideWidth: 232,
};
let prefs = Object.assign({}, DEFAULTS);

$('newtab').innerHTML = icon('plus', 16);
$('settings-btn').innerHTML = icon('settings', 16);
$('win-min').innerHTML = icon('min', 15);
$('win-max').innerHTML = icon('max', 13);
$('win-close').innerHTML = icon('close', 15);
$('back').innerHTML = icon('back', 17);
$('fwd').innerHTML = icon('fwd', 17);
$('up').innerHTML = icon('up', 17);
$('reload').innerHTML = icon('reload', 16);
$('searchbox').querySelector('.glyph').innerHTML = icon('search', 15);
$('search-x').innerHTML = icon('close', 13);
$('new-btn').innerHTML = icon('plus', 15) + '<span>New</span>';
$('sort-btn').innerHTML = icon('sort', 17);
$('details-btn').innerHTML = icon('panel', 17);
for (const b of $('viewseg').children) b.innerHTML = icon(b.dataset.view, 15);

// --- Paths --------------------------------------------------------------------------------

const DRIVE_ROOT = /^[A-Za-z]:\\?$/;
const UNC_ROOT = /^\\\\[^\\]+\\[^\\]+\\?$/;
const isRoot = p => DRIVE_ROOT.test(p) || UNC_ROOT.test(p);
const keyOf = p => String(p).toLowerCase();

function join(dir, name) {
	return dir.endsWith('\\') ? dir + name : dir + '\\' + name;
}

function parentOf(p) {
	if (!p || isRoot(p)) return '';
	const t = p.replace(/\\+$/, '');
	const i = t.lastIndexOf('\\');
	if (i < 0) return '';
	const up = t.slice(0, i);
	if (/^[A-Za-z]:$/.test(up)) return up + '\\';
	if (/^\\\\[^\\]*$/.test(up) || up === '\\') return '';
	return up;
}

function baseName(p) {
	if (!p) return 'Home';
	if (isRoot(p)) return driveLabel(p);
	const t = p.replace(/\\+$/, '');
	return t.slice(t.lastIndexOf('\\') + 1);
}

function rootOf(p) {
	const m = /^([A-Za-z]):/.exec(p || '');
	if (m) return m[1].toUpperCase() + ':';
	const u = /^\\\\[^\\]+\\[^\\]+/.exec(p || '');
	return u ? u[0].toLowerCase() : '';
}

function driveOf(p) {
	if (!S.places) return null;
	const r = keyOf(rootOf(p));
	return S.places.drives.find(d => keyOf(d.letter) === r) || null;
}

function driveLabel(p) {
	const d = driveOf(p);
	const letter = rootOf(p);
	if (!/^[A-Z]:$/.test(letter)) return p.replace(/\\+$/, '');
	const name = d && d.name ? d.name : (d && d.type === 'usb' ? 'USB Drive' : d && d.type === 'network' ? 'Network Drive' : d && d.type === 'disc' ? 'DVD Drive' : 'Local Disk');
	return name + ' (' + letter + ')';
}

// --- Entries ------------------------------------------------------------------------------

// A host row: [name, isDir, size, modified, created, attributes, folder?, opened?].
function entry(row, dir) {
	const name = row[0], isDir = row[1] === 1;
	const parent = row[6] || dir;
	const path = join(parent, name);
	const dot = name.lastIndexOf('.');
	const ext = !isDir && dot > 0 ? name.slice(dot).toLowerCase() : '';
	return { name: name, dir: isDir, size: row[2], mtime: row[3], ctime: row[4], attrs: row[5] | 0, parent: parent, path: path, key: keyOf(path), ext: ext, when: row[7] || 0 };
}

const isHidden = e => (e.attrs & 2) !== 0;

const EXT_CAT = {};
for (const [cat, list] of Object.entries({
	image: 'jpg jpeg png gif bmp webp tif tiff heic heif avif jfif ico svg psd raw cr2 nef arw dng',
	video: 'mp4 mkv mov avi wmv webm m4v flv mpg mpeg 3gp ts',
	audio: 'mp3 flac wav m4a aac ogg opus wma aiff mid midi',
	archive: 'zip rar 7z tar gz bz2 xz zst cab iso',
	code: 'js ts jsx tsx css scss html htm json xml yml yaml toml py cs c h cpp hpp rs go java kt gd gdshader tscn tres sh ps1 bat cmd sql lua rb php swift vue svelte ini cfg conf md',
	doc: 'doc docx odt rtf xls xlsx ods csv ppt pptx odp pages numbers key epub',
	pdf: 'pdf',
	app: 'exe msi lnk url dll sys appx msix appref-ms',
	text: 'txt log nfo srt vtt',
})) for (const x of list.split(' ')) EXT_CAT['.' + x] = cat;

const THUMB_EXT = new Set('.jpg .jpeg .png .gif .bmp .webp .tif .tiff .heic .heif .avif .jfif .psd .mp4 .mkv .mov .avi .wmv .webm .m4v .mpg .mpeg .3gp .mp3 .flac .m4a .wma .pdf .svg'.split(' '));
const PHOTO_EXT = new Set('.jpg .jpeg .png .gif .bmp .webp .tif .tiff .heic .heif .avif .jfif .psd .mp4 .mkv .mov .avi .wmv .webm .m4v .mpg .mpeg .3gp'.split(' '));
// Their icon is their own, not their type's.
const OWN_ICON = new Set('.exe .lnk .ico .url .cur .ani .msc .cpl .scr .appref-ms .msi'.split(' '));
const RUNNABLE = new Set('.exe .bat .cmd .msi .ps1 .com'.split(' '));

const category = e => e.dir ? 'folder' : (EXT_CAT[e.ext] || 'text');

function typeName(e) {
	if (e.dir) return 'File folder';
	if (S.types[e.ext]) return S.types[e.ext];
	return e.ext ? e.ext.slice(1).toUpperCase() + ' File' : 'File';
}

function shownName(e) {
	if (e.dir) return e.name;
	if (e.ext === '.lnk' || e.ext === '.url') return e.name.slice(0, -e.ext.length);
	return prefs.showExt || !e.ext ? e.name : e.name.slice(0, -e.ext.length);
}

function folderKind(path) {
	return S.kinds.get(keyOf(path)) || '';
}

const BUCKETS = [16, 20, 24, 32, 40, 48, 64, 80, 96, 128, 160, 192, 256, 320, 384, 512];
function bucket(px) {
	for (const b of BUCKETS) if (b >= px) return b;
	return 512;
}

function iconUrl(e, css, thumb) {
	const px = bucket(Math.round(css * (window.devicePixelRatio || 1)));
	const th = thumb && prefs.thumbs && THUMB_EXT.has(e.ext);
	const own = th || OWN_ICON.has(e.ext);
	const k = own ? e.path + '|' + e.mtime : 'type:' + (e.ext || 'none');
	return ICON_HOST + '?p=' + encodeURIComponent(e.path) + '&s=' + px + '&k=' + encodeURIComponent(k) + '&th=' + (th ? 1 : 0);
}

// An entry's picture: folder art, or Windows' icon / thumbnail with document art if it has none.
function artFor(e, css, thumb) {
	if (e.dir) return folderArt(folderKind(e.path), Math.round(css));
	return '<img draggable="false" src="' + esc(iconUrl(e, css, thumb)) + '" data-cat="' + category(e) + '" data-size="' + Math.round(css) + '" data-label="' + esc(e.ext.slice(1)) + '" alt="">';
}

document.addEventListener('load', ev => {
	if (ev.target.tagName === 'IMG') ev.target.classList.add('ok');
}, true);
document.addEventListener('error', ev => {
	const img = ev.target;
	if (img.tagName !== 'IMG' || img.dataset.cat === undefined) return;
	const holder = img.parentElement;
	img.outerHTML = docArt(img.dataset.cat, +img.dataset.size || 32, img.dataset.label);
	if (holder) holder.classList.remove('photo');
}, true);

// --- Formatting -------------------------------------------------------------------------------

function fmtSize(n) {
	if (n == null || n < 0) return '';
	if (n < 1024) return n + ' B';
	const u = ['KB', 'MB', 'GB', 'TB', 'PB'];
	let i = -1;
	do { n /= 1024; i++; } while (n >= 1024 && i < u.length - 1);
	return (n < 10 ? n.toFixed(1) : Math.round(n)) + ' ' + u[i];
}

const dateFmt = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
const timeFmt = new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit' });
function fmtDate(ms) {
	if (!ms) return '';
	const d = new Date(ms);
	const now = new Date();
	const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
	if (ms >= today) return 'Today, ' + timeFmt.format(d);
	if (ms >= today - 86400000) return 'Yesterday, ' + timeFmt.format(d);
	return dateFmt.format(d) + ', ' + timeFmt.format(d);
}

const plural = (n, one, many) => n.toLocaleString() + ' ' + (n === 1 ? one : (many || one + 's'));

// --- Tabs ---------------------------------------------------------------------------------------

let nextTab = 1;
const tabs = [];
let active = null;

function makeTab() {
	return {
		id: nextTab++, path: null, hist: [], hi: -1, items: [], view: [], index: new Map(), sel: new Set(),
		anchor: null, cursor: null, scroll: 0, restore: null, loading: false, error: null, search: null, seq: 0,
		free: 0, total: 0, pendingSelect: null, pendingRename: false, el: null,
	};
}

function newTab(path, at, background) {
	const tab = makeTab();
	if (at == null || at < 0 || at > tabs.length) tabs.push(tab);
	else tabs.splice(at, 0, tab);
	buildTabEl(tab);
	renderTabs();
	go(tab, path || '');
	if (!background || !active) activate(tab);
	return tab;
}

function tabTitle(tab) {
	if (tab.search) return 'Search: ' + tab.search.q;
	return tab.path ? baseName(tab.path) : 'Home';
}

function buildTabEl(tab) {
	const el = document.createElement('div');
	el.className = 'tab new';
	el.innerHTML = '<span class="mark"></span><span class="title"></span><button class="x" title="Close (Ctrl+W)">' + icon('close', 13) + '</button>';
	el.addEventListener('mousedown', e => {
		if (e.button === 1) { e.preventDefault(); closeTab(tab); return; }
		if (e.button !== 0 || e.target.closest('.x')) return;
		activate(tab);
		startTabDrag(tab, e);
	});
	el.addEventListener('contextmenu', e => { e.preventDefault(); activate(tab); tabMenu(tab, e.clientX, e.clientY); });
	el.querySelector('.x').addEventListener('click', () => closeTab(tab));
	setTimeout(() => el.classList.remove('new'), 300);
	tab.el = el;
	renderTab(tab);
}

function renderTabs() {
	const box = $('tabs');
	for (const t of tabs) if (t.el.parentNode !== box || t.el !== box.children[tabs.indexOf(t)]) box.insertBefore(t.el, box.children[tabs.indexOf(t)] || null);
	const ai = tabs.indexOf(active);
	tabs.forEach((t, i) => {
		t.el.classList.toggle('active', t === active);
		t.el.classList.toggle('before-active', i === ai - 1);
	});
	box.style.flexBasis = (tabs.length * 212) + 'px';
	const tiny = tabs.length > 0 && box.clientWidth / tabs.length < 76;
	for (const t of tabs) t.el.classList.toggle('tiny', tiny);
}

function renderTab(tab) {
	if (!tab.el) return;
	const title = tabTitle(tab);
	tab.el.querySelector('.title').textContent = title;
	tab.el.title = tab.path || 'Home';
	tab.el.dataset.drop = tab.path && !tab.search ? tab.path : '';
	tab.el.querySelector('.mark').innerHTML = tab.search ? icon('search', 15) : tab.path ? folderArt(folderKind(tab.path), 18) : icon('home', 16);
	if (tab === active) send('title', { text: title });
}

function activate(tab) {
	if (!tab) return;
	if (active && active !== tab) {
		active.scroll = scroller.scrollTop;
		if (renaming) commitRename(true);
	}
	const changed = active !== tab;
	active = tab;
	renderTabs();
	renderTab(tab);
	$('search-in').value = tab.search ? tab.search.q : '';
	$('searchbox').classList.toggle('active', !!tab.search);
	if (changed) {
		clearLive();
		tab.restore = tab.scroll;
		renderAll();
		send('watch', { path: tab.path || '' });
		if (tab.path && !tab.loading && !tab.search) load(tab, true);
		else if (homeMode()) loadHome();
	}
}

function closeTab(tab) {
	const i = tabs.indexOf(tab);
	if (i < 0) return;
	if (tab.search) send('cancelSearch');
	tabs.splice(i, 1);
	tab.el.remove();
	if (tabs.length === 0) { send('cmd', { cmd: 'close' }); return; }
	if (tab === active) activate(tabs[Math.min(i, tabs.length - 1)]);
	else renderTabs();
}

function cycleTab(dir) {
	const i = tabs.indexOf(active);
	activate(tabs[(i + dir + tabs.length) % tabs.length]);
}

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

// --- Navigation -----------------------------------------------------------------------------------

function go(tab, path, opts) {
	opts = opts || {};
	if (tab.search) endSearch(tab, false);
	if (tab.hi >= 0 && tab.hist[tab.hi]) tab.hist[tab.hi].scroll = tab === active ? scroller.scrollTop : tab.scroll;
	if (opts.push !== false) {
		tab.hist.splice(tab.hi + 1);
		tab.hist.push({ path: path, scroll: 0 });
		tab.hi = tab.hist.length - 1;
	}
	tab.path = path;
	tab.items = [];
	tab.view = [];
	tab.index = new Map();
	tab.sel = new Set();
	tab.cursor = tab.anchor = null;
	tab.error = null;
	tab.scroll = 0;
	tab.restore = opts.scroll || 0;
	tab.pendingSelect = opts.select || null;
	renderTab(tab);
	if (tab === active) {
		clearLive();
		renderAll();
		send('watch', { path: path });
	}
	load(tab);
}

function back() {
	const t = active;
	if (t.search) { endSearch(t, true); return; }
	if (t.hi <= 0) return;
	t.hist[t.hi].scroll = scroller.scrollTop;
	const cur = t.path;
	t.hi--;
	const h = t.hist[t.hi];
	go(t, h.path, { push: false, scroll: h.scroll, select: parentOf(cur) && keyOf(parentOf(cur)) === keyOf(h.path) ? baseName(cur) : null });
}

function forward() {
	const t = active;
	if (t.hi >= t.hist.length - 1) return;
	t.hist[t.hi].scroll = scroller.scrollTop;
	t.hi++;
	go(t, t.hist[t.hi].path, { push: false, scroll: t.hist[t.hi].scroll });
}

function goUp() {
	const t = active;
	if (t.search) { endSearch(t, true); return; }
	if (!t.path) return;
	go(t, parentOf(t.path), { select: isRoot(t.path) ? null : baseName(t.path) });
}

async function load(tab, quiet) {
	const seq = ++tab.seq;
	if (!tab.path) {
		tab.loading = false;
		if (tab === active) { setLoading(false); renderAll(); loadHome(); }
		return;
	}
	tab.loading = true;
	if (tab === active && !quiet) setLoading(true);
	const r = await ask('list', { path: tab.path });
	if (seq !== tab.seq) return;
	tab.loading = false;
	if (r.file) {
		// A file: show its folder with it picked out.
		const parent = parentOf(r.path);
		tab.path = parent;
		if (tab.hist[tab.hi]) tab.hist[tab.hi].path = parent;
		tab.pendingSelect = baseName(r.path);
		return load(tab, quiet);
	}
	if (r.path && r.path !== tab.path) {
		tab.path = r.path;
		if (tab.hist[tab.hi]) tab.hist[tab.hi].path = r.path;
	}
	tab.error = r.error || null;
	Object.assign(S.types, r.types || {});
	tab.items = (r.items || []).map(row => entry(row, tab.path));
	tab.free = r.free || 0;
	tab.total = r.total || 0;
	if (!tab.search) refreshView(tab);
	for (const k of [...tab.sel]) if (!tab.index.has(k)) tab.sel.delete(k);
	let reveal = null;
	if (tab.pendingSelect) {
		const k = keyOf(join(tab.path, tab.pendingSelect));
		if (tab.index.has(k)) {
			tab.sel = new Set([k]);
			tab.cursor = tab.anchor = k;
			reveal = k;
		}
		tab.pendingSelect = null;
	} else if (tab.selectIndex != null && tab.view.length) {
		const e = tab.view[Math.min(tab.selectIndex, tab.view.length - 1)];
		tab.sel = new Set([e.key]);
		tab.cursor = tab.anchor = e.key;
	}
	tab.selectIndex = null;
	renderTab(tab);
	if (tab !== active) return;
	setLoading(false);
	renderAll();
	if (reveal) scrollToIndex(tab.index.get(reveal));
	if (tab.pendingRename && reveal) startRename(reveal);
	tab.pendingRename = false;
}

function reload(quiet) {
	if (active.search) { startSearch(active, active.search.q); return; }
	load(active, quiet);
	if (!active.path) refreshPlaces();
}

function setLoading(on) {
	clearTimeout(setLoading.t);
	if (!on) { body.classList.remove('loading'); return; }
	// Only show the bar for slow folders.
	setLoading.t = setTimeout(() => body.classList.add('loading'), 180);
}

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });

function refreshView(tab) {
	let list = tab.search ? tab.search.items : tab.items;
	if (!prefs.showHidden) list = list.filter(e => !isHidden(e));
	const k = prefs.sort, d = prefs.desc ? -1 : 1;
	list = list.slice().sort((a, b) => {
		if (prefs.foldersFirst && a.dir !== b.dir) return a.dir ? -1 : 1;
		let c = 0;
		if (k === 'date') c = a.mtime - b.mtime;
		else if (k === 'size') c = (a.dir ? -1 : a.size) - (b.dir ? -1 : b.size);
		else if (k === 'type') c = collator.compare(typeName(a), typeName(b));
		else if (k === 'where') c = collator.compare(a.parent, b.parent);
		if (c === 0) c = collator.compare(a.name, b.name);
		return c * d;
	});
	tab.view = list;
	tab.index = new Map();
	list.forEach((e, i) => tab.index.set(e.key, i));
}

const homeMode = () => !active.path && !active.search;
const canWrite = () => !!active.path && !active.search && !active.error;

function selected() {
	const t = active;
	const out = [];
	for (const k of t.sel) {
		const i = t.index.get(k);
		if (i != null) out.push(t.view[i]);
	}
	out.sort((a, b) => t.index.get(a.key) - t.index.get(b.key));
	return out;
}

// --- Rendering ------------------------------------------------------------------------------------

const scroller = $('scroller');
const canvas = $('canvas');
let L = null;
const live = new Map();

function clearLive() {
	for (const el of live.values()) el.remove();
	live.clear();
}

function renderAll() {
	if (!active) return;
	const home = homeMode();
	body.classList.toggle('home-mode', home);
	body.classList.toggle('list-mode', prefs.view === 'list' && !home);
	canvas.className = prefs.view === 'list' ? 'list' : 'grid';
	for (const b of $('viewseg').children) b.classList.toggle('on', b.dataset.view === prefs.view);
	$('details-btn').classList.toggle('on', !!prefs.details);
	$('back').disabled = active.hi <= 0 && !active.search;
	$('fwd').disabled = active.hi >= active.hist.length - 1;
	$('up').disabled = !active.path && !active.search;
	$('new-btn').disabled = !canWrite();
	$('search-in').placeholder = 'Search ' + (active.path ? baseName(active.path) : 'Home');
	$('searchbox').classList.toggle('busy', !!(active.search && !active.search.done));
	renderCrumbs();
	renderSideState();
	renderListHead();
	if (home) {
		canvas.style.height = '0px';
		$('empty').classList.remove('show');
		renderHome();
	} else {
		layout();
		renderItems();
		renderEmpty();
	}
	if (active.restore != null) {
		scroller.scrollTop = active.restore;
		active.restore = null;
		if (!home) renderItems();
	}
	renderStatus();
	renderSelbar();
	renderDetails();
}

function layout() {
	const n = active.view.length;
	const width = scroller.clientWidth;
	if (prefs.view === 'list') {
		L = { mode: 'list', cols: 1, w: Math.max(200, width - 24), h: 32, gap: 0, gapY: 0, padX: 12, padY: 6, n: n };
	} else {
		const s = prefs.iconSize;
		const min = s + 34;
		const gap = 6, padX = 14;
		const cols = Math.max(1, Math.floor((width - padX * 2 + gap) / (min + gap)));
		const w = Math.floor((width - padX * 2 - gap * (cols - 1)) / cols);
		L = { mode: 'grid', cols: cols, w: w, h: s + 60 + (active.search ? 14 : 0), gap: gap, gapY: 6, padX: padX, padY: 12, n: n, s: s };
	}
	const rows = Math.ceil(n / L.cols);
	canvas.style.height = (L.padY * 2 + rows * (L.h + L.gapY) + 64) + 'px';
}

function posOf(i) {
	const r = Math.floor(i / L.cols), c = i % L.cols;
	return { x: L.padX + c * (L.w + L.gap), y: L.padY + r * (L.h + L.gapY) };
}

function sigOf(e) {
	return [L.mode, L.s, prefs.showExt, prefs.thumbs, !!active.search, e.name, e.size, e.mtime, e.attrs].join('|');
}

function renderItems() {
	const tab = active;
	if (!L || homeMode()) return;
	const top = scroller.scrollTop, vh = scroller.clientHeight;
	const span = L.h + L.gapY;
	const r0 = Math.max(0, Math.floor((top - L.padY) / span) - 2);
	const r1 = Math.floor((top + vh - L.padY) / span) + 2;
	const i0 = r0 * L.cols, i1 = Math.min(tab.view.length, (r1 + 1) * L.cols);
	const keep = new Set();
	for (let i = i0; i < i1; i++) {
		const e = tab.view[i];
		keep.add(e.key);
		let el = live.get(e.key);
		const sig = sigOf(e);
		if (el && el._sig !== sig && !(renaming && renaming.el === el)) { el.remove(); el = null; }
		if (!el) {
			el = makeItem(e);
			el._sig = sig;
			live.set(e.key, el);
			canvas.appendChild(el);
		}
		const p = posOf(i);
		if (el._x !== p.x || el._y !== p.y) {
			el.style.transform = 'translate(' + p.x + 'px,' + p.y + 'px)';
			el.style.setProperty('--at', 'translate(' + p.x + 'px,' + p.y + 'px)');
			el._x = p.x;
			el._y = p.y;
		}
		if (el._w !== L.w || el._h !== L.h) {
			el.style.width = L.w + 'px';
			el.style.height = L.h + 'px';
			el._w = L.w;
			el._h = L.h;
		}
		el._e = e;
		paintState(el, e, tab);
	}
	for (const [k, el] of live) {
		if (keep.has(k) || (renaming && renaming.el === el)) continue;
		el.remove();
		live.delete(k);
	}
}

function makeItem(e) {
	const el = document.createElement('div');
	el.className = 'item';
	el.dataset.key = e.key;
	if (e.dir) el.dataset.drop = e.path;
	el.title = e.name + (active.search ? '\n' + e.parent : '');
	if (L.mode === 'grid') {
		const s = L.s;
		const photo = !e.dir && prefs.thumbs && PHOTO_EXT.has(e.ext);
		const css = e.dir ? s * 0.94 : photo ? s : Math.round(s * 0.8);
		el.innerHTML = '<div class="thumb' + (photo ? ' photo' : '') + '" style="width:' + s + 'px;height:' + s + 'px">' + artFor(e, css, true) + '</div>' +
			'<div class="name">' + esc(shownName(e)) + '</div>' +
			(active.search ? '<div class="sub">' + esc(baseName(e.parent)) + '</div>' : '');
	} else {
		el.classList.add('cols');
		if (active.search) el.classList.add('with-loc');
		el.innerHTML = '<div class="cell-name"><span class="icon-cell">' + artFor(e, 20, false) + '</span><span class="label">' + esc(shownName(e)) + '</span></div>' +
			(active.search ? '<div>' + esc(e.parent) + '</div>' : '') +
			'<div>' + esc(fmtDate(e.mtime)) + '</div>' +
			(active.search ? '' : '<div>' + esc(typeName(e)) + '</div>') +
			'<div class="num">' + (e.dir ? '' : esc(fmtSize(e.size))) + '</div>';
	}
	return el;
}

function paintState(el, e, tab) {
	el.classList.toggle('sel', tab.sel.has(e.key));
	el.classList.toggle('cursor', tab.cursor === e.key);
	el.classList.toggle('cut', !!(S.clip && S.clip.cut && S.clip.keys.has(e.key)));
	el.classList.toggle('hidden', isHidden(e));
}

function paintAll() {
	for (const el of live.values()) if (el._e) paintState(el, el._e, active);
}

function renderEmpty() {
	const box = $('empty');
	const t = active;
	let html = '';
	if (t.error === 'missing') html = folderArt('', 72) + '<div class="big">Can\'t find ' + esc(t.path) + '</div><div>Check the spelling, or it may have been moved or deleted.</div>';
	else if (t.error === 'denied') html = icon('shield', 44) + '<div class="big">You don\'t have permission to open this folder</div><div>Windows keeps it locked to protect your PC or another user.</div><button class="btn" data-act="explorer">' + icon('external', 15) + 'Open in Windows Explorer</button>';
	else if (t.error) html = icon('info', 40) + '<div class="big">Couldn\'t open this folder</div><div>' + esc(t.error) + '</div>';
	else if (t.search && t.search.done && !t.view.length) html = icon('search', 40) + '<div class="big">No results for “' + esc(t.search.q) + '”</div><div>Searched ' + plural(t.search.folders, 'folder') + ' in ' + esc(baseName(t.search.root)) + '.</div>';
	else if (!t.search && !t.loading && !t.view.length && t.path) html = folderArt('', 72) + '<div class="big">This folder is empty</div><div>Drop files here, or press Ctrl+V to paste.</div>';
	box.innerHTML = html;
	box.classList.toggle('show', !!html);
	const b = box.querySelector('[data-act=explorer]');
	if (b) b.onclick = () => send('explorer', { path: active.path });
}

function scrollToIndex(i) {
	if (i == null || !L) return;
	const p = posOf(i);
	const vh = scroller.clientHeight;
	const bottomPad = active.sel.size ? 70 : 10;
	if (p.y < scroller.scrollTop + 4) scroller.scrollTop = p.y - L.padY;
	else if (p.y + L.h > scroller.scrollTop + vh - bottomPad) scroller.scrollTop = p.y + L.h - vh + bottomPad;
	renderItems();
}

let scrollRaf = 0;
scroller.addEventListener('scroll', () => {
	if (scrollRaf) return;
	scrollRaf = requestAnimationFrame(() => { scrollRaf = 0; renderItems(); });
}, { passive: true });

new ResizeObserver(() => {
	if (!active) return;
	if (!homeMode()) { layout(); renderItems(); }
	renderTabs();
	fitCrumbs();
}).observe(scroller);

// --- List header ----------------------------------------------------------------------------------

function renderListHead() {
	const h = $('listhead');
	if (prefs.view !== 'list' || homeMode()) { h.innerHTML = ''; return; }
	const cols = active.search
		? [['name', 'Name'], ['where', 'Folder'], ['date', 'Date modified'], ['size', 'Size', true]]
		: [['name', 'Name'], ['date', 'Date modified'], ['type', 'Type'], ['size', 'Size', true]];
	h.className = 'cols' + (active.search ? ' with-loc' : '');
	h.innerHTML = '';
	for (const c of cols) {
		const d = document.createElement('div');
		d.className = (c[2] ? 'num' : '') + (prefs.sort === c[0] ? ' on' : '');
		d.innerHTML = (c[2] && prefs.sort === c[0] ? icon(prefs.desc ? 'down' : 'up', 12) : '') + '<span>' + c[1] + '</span>' + (!c[2] && prefs.sort === c[0] ? icon(prefs.desc ? 'down' : 'up', 12) : '');
		d.onclick = () => sortBy(c[0]);
		h.appendChild(d);
	}
}

function sortBy(key) {
	if (prefs.sort === key) setPrefs({ desc: !prefs.desc });
	else setPrefs({ sort: key, desc: key === 'date' || key === 'size' });
}

// --- Breadcrumbs and the address box ---------------------------------------------------------

function crumbSegs(path) {
	const segs = [{ label: 'Home', path: '', home: true }];
	if (!path) return segs;
	// Start at a known folder (Downloads, Documents, ...) when inside one.
	let base = null;
	if (S.places) {
		for (const q of S.places.quick) {
			const k = keyOf(q.path);
			if ((keyOf(path) === k || keyOf(path).startsWith(k + '\\')) && (!base || q.path.length > base.path.length)) base = q;
		}
	}
	let rest;
	if (base) {
		segs.push({ label: base.name, path: base.path, kind: base.kind });
		rest = path.slice(base.path.length).split('\\').filter(Boolean);
		let acc = base.path;
		for (const r of rest) { acc = join(acc, r); segs.push({ label: r, path: acc }); }
		return segs;
	}
	const root = rootOf(path);
	if (/^[A-Z]:$/.test(root)) {
		segs.push({ label: driveLabel(root), path: root + '\\', drive: true });
		rest = path.slice(3).split('\\').filter(Boolean);
		let acc = root + '\\';
		for (const r of rest) { acc = join(acc, r); segs.push({ label: r, path: acc }); }
	} else {
		segs.push({ label: root, path: root, drive: true });
		rest = path.slice(root.length).split('\\').filter(Boolean);
		let acc = root;
		for (const r of rest) { acc = join(acc, r); segs.push({ label: r, path: acc }); }
	}
	return segs;
}

function renderCrumbs() {
	const c = $('crumbs');
	c.innerHTML = '';
	const segs = crumbSegs(active.path);
	segs.forEach((s, i) => {
		if (i > 0) {
			const sep = document.createElement('button');
			sep.className = 'crumb-sep';
			sep.innerHTML = icon('chevron', 13);
			sep.onclick = e => { e.stopPropagation(); subfolderMenu(segs[i - 1].path, sep); };
			c.appendChild(sep);
		}
		const b = document.createElement('button');
		b.className = 'crumb';
		if (s.path) b.dataset.drop = s.path;
		const art = s.home ? icon('home', 16) : s.drive ? driveArt((driveOf(s.path) || {}).type || 'fixed', 18, keyOf(s.path) === keyOf(S.system)) : s.kind ? folderArt(s.kind, 18) : '';
		b.innerHTML = art + (s.home && segs.length > 1 ? '' : '<span>' + esc(s.label) + '</span>');
		b.title = s.home ? 'Home' : s.path;
		b.onclick = e => { e.stopPropagation(); if (active.search || keyOf(s.path) !== keyOf(active.path)) go(active, s.path); };
		b.onauxclick = e => { if (e.button === 1) newTab(s.path, tabs.indexOf(active) + 1, true); };
		c.appendChild(b);
	});
	if (active.search) {
		const sep = document.createElement('span');
		sep.className = 'crumb-sep';
		sep.innerHTML = icon('chevron', 13);
		c.appendChild(sep);
		const b = document.createElement('span');
		b.className = 'crumb';
		b.innerHTML = icon('search', 14) + '<span>Results for “' + esc(active.search.q) + '”</span>';
		c.appendChild(b);
	}
	fitCrumbs();
}

// Long paths fold their middle into "…".
function fitCrumbs() {
	const c = $('crumbs');
	const kids = [...c.children];
	kids.forEach(k => { k.style.display = ''; });
	const old = c.querySelector('.crumb-more');
	if (old) old.remove();
	if (c.scrollWidth <= c.clientWidth) return;
	const hidden = [];
	// children: home, (sep, crumb)*; hide pairs after home until it fits.
	for (let i = 1; i + 3 < kids.length && c.scrollWidth > c.clientWidth; i += 2) {
		kids[i].style.display = 'none';
		kids[i + 1].style.display = 'none';
		hidden.push(kids[i + 1]);
	}
	if (!hidden.length) return;
	const more = document.createElement('button');
	more.className = 'crumb crumb-more';
	more.textContent = '…';
	more.onclick = e => {
		e.stopPropagation();
		const r = more.getBoundingClientRect();
		showMenu(hidden.map(h => ({ label: h.textContent, art: folderArt('', 18), run: () => go(active, h.dataset.drop) })), r.left, r.bottom + 4);
	};
	c.insertBefore(more, kids[1]);
	const sep = document.createElement('span');
	sep.className = 'crumb-sep crumb-more';
	sep.innerHTML = icon('chevron', 13);
	c.insertBefore(sep, more);
}

async function subfolderMenu(path, anchor) {
	const r0 = anchor.getBoundingClientRect();
	anchor.classList.add('open');
	let items;
	if (!path) {
		items = (S.places ? S.places.quick : []).map(q => ({ label: q.name, art: folderArt(q.kind, 18), run: () => go(active, q.path) }));
		items.push({ sep: true });
		for (const d of S.places ? S.places.drives : []) items.push({ label: driveLabel(d.path), art: driveArt(d.type, 18, keyOf(d.path) === keyOf(S.system)), run: () => go(active, d.path) });
	} else {
		const r = await ask('list', { path: path });
		const dirs = (r.items || []).map(row => entry(row, r.path || path)).filter(e => e.dir && (prefs.showHidden || !isHidden(e)));
		dirs.sort((a, b) => collator.compare(a.name, b.name));
		items = dirs.slice(0, 60).map(e => ({ label: e.name, art: folderArt(folderKind(e.path), 18), run: () => go(active, e.path) }));
		if (!items.length) items = [{ label: 'No folders inside', disabled: true }];
	}
	showMenu(items, r0.left - 4, r0.bottom + 4, () => anchor.classList.remove('open'));
}

$('crumbs').addEventListener('click', e => { if (e.target === $('crumbs')) editAddress(); });
$('address').addEventListener('mousedown', e => { if (e.target === $('address')) { e.preventDefault(); editAddress(); } });

function editAddress() {
	const box = $('address'), inp = $('addr-in');
	box.classList.add('editing');
	inp.value = active.path || '';
	inp.placeholder = 'Type a folder, like C:\\Users or %APPDATA%';
	inp.focus();
	inp.select();
}

function endAddress() {
	$('address').classList.remove('editing');
}

$('addr-in').addEventListener('keydown', e => {
	e.stopPropagation();
	if (e.key === 'Escape') { endAddress(); scroller.focus(); }
	else if (e.key === 'Enter') {
		const v = $('addr-in').value.trim();
		endAddress();
		scroller.focus();
		if (/^shell:/i.test(v)) { send('explorer', { path: v }); return; }
		if (!v || /^home$/i.test(v)) go(active, '');
		else go(active, v);
	}
});
$('addr-in').addEventListener('blur', endAddress);

// --- Sidebar -----------------------------------------------------------------------------------------

function sideItem(label, art, path, opts) {
	const b = document.createElement('button');
	b.className = 'side-item' + (opts && opts.cls ? ' ' + opts.cls : '');
	b.dataset.path = path;
	if (path && !(opts && opts.nodrop)) b.dataset.drop = path;
	b.title = (opts && opts.title) || path || label;
	b.innerHTML = art + (opts && opts.meta ? opts.meta : '<span class="label">' + esc(label) + '</span>');
	b.addEventListener('click', () => { if (opts && opts.run) opts.run(); else if (active.search || keyOf(path) !== keyOf(active.path || '')) go(active, path); });
	b.addEventListener('auxclick', e => { if (e.button === 1 && !(opts && opts.run)) newTab(path, tabs.indexOf(active) + 1, true); });
	b.addEventListener('contextmenu', e => { e.preventDefault(); if (!(opts && opts.run)) placeMenu(path, e.clientX, e.clientY); });
	return b;
}

function head(text) {
	const d = document.createElement('div');
	d.className = 'side-head';
	d.textContent = text;
	return d;
}

function renderSide() {
	const side = $('side');
	side.innerHTML = '';
	side.appendChild(sideItem('Home', '<span style="width:22px;display:grid;place-items:center">' + icon('home', 18) + '</span>', '', { title: 'Home', nodrop: true }));
	if (S.places) for (const q of S.places.quick) side.appendChild(sideItem(q.name, folderArt(q.kind, 22), q.path));
	if (prefs.pinned.length) {
		side.appendChild(head('Pinned'));
		for (const p of prefs.pinned) side.appendChild(sideItem(baseName(p), folderArt(folderKind(p), 22), p));
	}
	if (S.places && S.places.drives.length) {
		side.appendChild(head('This PC'));
		for (const d of S.places.drives) {
			const used = d.total ? 1 - d.free / d.total : 0;
			const meta = '<span class="meta"><span class="label">' + esc(driveLabel(d.path)) + '</span>' +
				(d.total ? '<span class="usage' + (used > 0.9 ? ' full' : '') + '"><i style="width:' + Math.round(used * 100) + '%"></i></span>' : '') + '</span>';
			side.appendChild(sideItem(driveLabel(d.path), driveArt(d.type, 26, keyOf(d.path) === keyOf(S.system)), d.path, {
				cls: 'drive', meta: meta, title: d.total ? fmtSize(d.free) + ' free of ' + fmtSize(d.total) : d.path,
			}));
		}
	}
	const rb = sideItem('Recycle Bin', '<span style="width:22px;display:grid;place-items:center">' + icon('recycle', 18) + '</span>', '', {
		title: 'Opens in Windows Explorer', nodrop: true, run: () => send('explorer', { path: 'shell:RecycleBinFolder' }),
	});
	rb.style.marginTop = '10px';
	side.appendChild(rb);
	renderSideState();
}

function renderSideState() {
	const cur = active && !active.search ? keyOf(active.path || '') : null;
	for (const b of $('side').querySelectorAll('.side-item')) b.classList.toggle('on', cur !== null && keyOf(b.dataset.path) === cur && !b.title.startsWith('Opens'));
}

function buildKinds() {
	S.kinds = new Map();
	if (!S.places) return;
	for (const q of S.places.quick) S.kinds.set(keyOf(q.path), q.kind);
}

let placesAt = 0;
async function refreshPlaces() {
	placesAt = Date.now();
	const p = await ask('places');
	if (!p || !p.quick) return;
	S.places = p;
	S.home = p.home;
	S.system = p.system || S.system;
	buildKinds();
	renderSide();
	for (const t of tabs) renderTab(t);
	if (active) {
		renderCrumbs();
		if (homeMode()) renderHome();
	}
}

$('side-grip').addEventListener('mousedown', e => {
	e.preventDefault();
	const x0 = e.clientX, w0 = prefs.sideWidth;
	const move = ev => {
		const w = Math.max(170, Math.min(420, w0 + ev.clientX - x0));
		document.documentElement.style.setProperty('--side', w + 'px');
		prefs.sideWidth = w;
	};
	const up = () => {
		window.removeEventListener('mousemove', move);
		window.removeEventListener('mouseup', up);
		setPrefs({ sideWidth: prefs.sideWidth });
	};
	window.addEventListener('mousemove', move);
	window.addEventListener('mouseup', up);
});

// --- Home ----------------------------------------------------------------------------------------------

let homeSel = null;

async function loadHome() {
	renderHome();
	if (Date.now() - placesAt > 8000) refreshPlaces();
	const r = await ask('recent');
	S.recent = (r.items || []).map(row => entry(row, row[6]));
	if (active && homeMode()) renderHome();
}

function renderHome() {
	const h = $('home');
	h.innerHTML = '';
	const sec = (title) => { const t = document.createElement('h3'); t.textContent = title; h.appendChild(t); };
	sec('Quick access');
	const qa = document.createElement('div');
	qa.className = 'qa-grid';
	const quick = (S.places ? S.places.quick : []).map(q => ({ name: q.name, path: q.path, kind: q.kind }))
		.concat(prefs.pinned.map(p => ({ name: baseName(p), path: p, kind: folderKind(p), pinned: true })));
	for (const q of quick) {
		const b = document.createElement('button');
		b.className = 'qa';
		b.dataset.drop = q.path;
		b.title = q.path;
		b.innerHTML = folderArt(q.kind, 42) + '<span class="t"><span class="n">' + esc(q.name) + '</span><span class="p">' + esc(q.pinned ? 'Pinned' : parentOf(q.path) || q.path) + '</span></span>';
		b.onclick = () => go(active, q.path);
		b.onauxclick = e => { if (e.button === 1) newTab(q.path, tabs.indexOf(active) + 1, true); };
		b.oncontextmenu = e => { e.preventDefault(); placeMenu(q.path, e.clientX, e.clientY); };
		qa.appendChild(b);
	}
	h.appendChild(qa);

	if (S.places && S.places.drives.length) {
		sec('Drives');
		const dg = document.createElement('div');
		dg.className = 'drive-grid';
		for (const d of S.places.drives) {
			const used = d.total ? 1 - d.free / d.total : 0;
			const b = document.createElement('button');
			b.className = 'drive-card';
			b.dataset.drop = d.path;
			b.innerHTML = driveArt(d.type, 48, keyOf(d.path) === keyOf(S.system)) + '<span class="t"><span class="n">' + esc(driveLabel(d.path)) + '</span>' +
				(d.total ? '<span class="usage' + (used > 0.9 ? ' full' : '') + '"><i style="width:' + Math.round(used * 100) + '%"></i></span><span class="f">' + fmtSize(d.free) + ' free of ' + fmtSize(d.total) + '</span>' : '<span class="f">Not available</span>') + '</span>';
			b.onclick = () => go(active, d.path);
			b.oncontextmenu = e => { e.preventDefault(); placeMenu(d.path, e.clientX, e.clientY); };
			dg.appendChild(b);
		}
		h.appendChild(dg);
	}

	sec('Recent');
	const list = document.createElement('div');
	list.className = 'recent-list';
	const recent = (S.recent || []).filter(e => !e.dir).slice(0, 18);
	if (!S.recent) list.innerHTML = '<div class="home-none">…</div>';
	else if (!recent.length) list.innerHTML = '<div class="home-none">Files you open show up here.</div>';
	for (const e of recent) {
		const b = document.createElement('div');
		b.className = 'recent' + (homeSel === e.key ? ' sel' : '');
		b.title = e.path;
		b.innerHTML = '<span class="icon-cell">' + artFor(e, 22, false) + '</span><span class="n">' + esc(shownName(e)) + '</span><span class="p">' + esc(e.parent) + '</span><span class="d">' + esc(fmtDate(e.when || e.mtime)) + '</span>';
		b.onclick = () => { homeSel = e.key; for (const x of list.children) x.classList.toggle('sel', x === b); };
		b.ondblclick = () => openEntries([e]);
		b.oncontextmenu = ev => {
			ev.preventDefault();
			homeSel = e.key;
			for (const x of list.children) x.classList.toggle('sel', x === b);
			showMenu([
				{ label: 'Open', icon: 'open', strong: true, run: () => openEntries([e]) },
				{ label: 'Open file location', icon: 'tab', run: () => go(active, e.parent, { select: e.name }) },
				{ sep: true },
				{ label: 'Copy as path', icon: 'path', run: () => copyPaths([e]) },
				{ label: 'Properties', icon: 'info', run: () => send('props', { path: e.path }) },
			], ev.clientX, ev.clientY);
		};
		list.appendChild(b);
	}
	h.appendChild(list);
}

// --- Selection, keyboard and mouse ---------------------------------------------------------------

function setSel(keys, cursor) {
	active.sel = new Set(keys);
	if (cursor !== undefined) active.cursor = cursor;
	selectionChanged();
}

function selectionChanged() {
	paintAll();
	renderStatus();
	renderSelbar();
	renderDetails();
}

function selectRange(fromKey, toKey, add) {
	const t = active;
	const a = t.index.get(fromKey), b = t.index.get(toKey);
	if (a == null || b == null) { setSel([toKey], toKey); return; }
	const s = add ? new Set(t.sel) : new Set();
	for (let i = Math.min(a, b); i <= Math.max(a, b); i++) s.add(t.view[i].key);
	t.sel = s;
	t.cursor = toKey;
	selectionChanged();
}

let pendingSingle = null;
let press = null;

scroller.addEventListener('mousedown', e => {
	if (homeMode()) return;
	if (renaming && !e.target.closest('.rename')) commitRename(false);
	if (e.target.closest('.rename')) return;
	scroller.focus({ preventScroll: true });
	const el = e.target.closest('.item');
	if (e.button === 1) {
		e.preventDefault();
		if (el && el._e && el._e.dir) newTab(el._e.path, tabs.indexOf(active) + 1, true);
		return;
	}
	if (e.button !== 0 && e.button !== 2) return;
	const t = active;
	if (el && el._e) {
		const k = el._e.key;
		if (e.button === 2) {
			if (!t.sel.has(k)) { t.anchor = k; setSel([k], k); }
			return;
		}
		if (e.ctrlKey) {
			const s = new Set(t.sel);
			if (s.has(k)) s.delete(k); else s.add(k);
			t.anchor = k;
			t.sel = s;
			t.cursor = k;
			selectionChanged();
		} else if (e.shiftKey && t.anchor) selectRange(t.anchor, k, false);
		else if (!t.sel.has(k)) { t.anchor = k; setSel([k], k); }
		else { pendingSingle = k; t.cursor = k; paintAll(); }
		beginPress(e, k);
		return;
	}
	if (e.button === 2) {
		if (!e.ctrlKey && t.sel.size) setSel([]);
		return;
	}
	if (e.offsetX > scroller.clientWidth) return; // the scrollbar
	beginMarquee(e);
});

scroller.addEventListener('dblclick', e => {
	if (homeMode() || e.button !== 0) return;
	const el = e.target.closest('.item');
	if (!el || !el._e || e.target.closest('.rename')) return;
	openEntries([el._e]);
});

scroller.addEventListener('contextmenu', e => {
	e.preventDefault();
	if (homeMode()) return;
	const el = e.target.closest('.item');
	if (el && el._e) itemMenu(e.clientX, e.clientY);
	else backgroundMenu(e.clientX, e.clientY);
});

function beginMarquee(e) {
	const t = active;
	const rect = scroller.getBoundingClientRect();
	const sx = e.clientX - rect.left, sy = e.clientY - rect.top + scroller.scrollTop;
	const base = e.ctrlKey || e.shiftKey ? new Set(t.sel) : new Set();
	if (!e.ctrlKey && !e.shiftKey && t.sel.size) setSel([]);
	const box = $('marquee');
	let last = e, moved = false, raf = 0;
	const update = () => {
		const cx = Math.max(0, Math.min(scroller.clientWidth, last.clientX - rect.left));
		const cy = Math.max(0, Math.min(scroller.scrollHeight, last.clientY - rect.top + scroller.scrollTop));
		if (!moved && Math.hypot(cx - sx, cy - sy) < 4) return;
		moved = true;
		const x0 = Math.min(sx, cx), y0 = Math.min(sy, cy), x1 = Math.max(sx, cx), y1 = Math.max(sy, cy);
		box.style.display = 'block';
		box.style.left = x0 + 'px';
		box.style.top = y0 + 'px';
		box.style.width = (x1 - x0) + 'px';
		box.style.height = (y1 - y0) + 'px';
		const s = new Set(base);
		const span = L.h + L.gapY;
		const r0 = Math.max(0, Math.floor((y0 - L.padY) / span));
		const r1 = Math.floor((y1 - L.padY) / span);
		for (let r = r0; r <= r1; r++) {
			for (let c = 0; c < L.cols; c++) {
				const i = r * L.cols + c;
				if (i >= t.view.length) break;
				const p = posOf(i);
				if (p.x < x1 && p.x + L.w > x0 && p.y < y1 && p.y + L.h > y0) s.add(t.view[i].key);
			}
		}
		t.sel = s;
		selectionChanged();
	};
	const tick = () => {
		raf = 0;
		const r = scroller.getBoundingClientRect();
		let dy = 0;
		if (last.clientY < r.top + 20) dy = -Math.min(40, r.top + 20 - last.clientY);
		else if (last.clientY > r.bottom - 20) dy = Math.min(40, last.clientY - r.bottom + 20);
		if (dy) { scroller.scrollTop += dy; update(); raf = requestAnimationFrame(tick); }
	};
	const move = ev => { last = ev; update(); if (!raf) raf = requestAnimationFrame(tick); };
	const up = () => {
		window.removeEventListener('mousemove', move);
		window.removeEventListener('mouseup', up);
		if (raf) cancelAnimationFrame(raf);
		box.style.display = 'none';
	};
	window.addEventListener('mousemove', move);
	window.addEventListener('mouseup', up);
}

// --- Drag and drop ---------------------------------------------------------------------------------

let D = null;

function beginPress(e, key) {
	const x0 = e.clientX, y0 = e.clientY;
	const move = ev => {
		if (!D) {
			if (Math.hypot(ev.clientX - x0, ev.clientY - y0) < 6) return;
			startDrag();
		}
		dragMove(ev);
	};
	const up = ev => {
		endPress();
		if (D) dragDrop(ev);
		else if (pendingSingle === key && !ev.ctrlKey && !ev.shiftKey) { active.anchor = key; setSel([key], key); }
		pendingSingle = null;
	};
	press = { move: move, up: up };
	window.addEventListener('mousemove', move);
	window.addEventListener('mouseup', up);
}

function endPress() {
	if (!press) return;
	window.removeEventListener('mousemove', press.move);
	window.removeEventListener('mouseup', press.up);
	press = null;
}

function startDrag() {
	const list = selected();
	if (!list.length) return;
	pendingSingle = null;
	D = { list: list, keys: new Set(list.map(e => e.key)), paths: list.map(e => e.path), target: null, el: null, hoverTab: null, hoverAt: 0 };
	const g = $('ghost');
	const first = list[0];
	g.innerHTML = (first.dir ? folderArt(folderKind(first.path), 48) : '<img src="' + esc(iconUrl(first, 48, true)) + '" alt="">') + (list.length > 1 ? '<span class="n">' + list.length + '</span>' : '');
	g.classList.add('show');
	body.classList.add('dragging');
}

function dropTargetAt(x, y) {
	const el = document.elementFromPoint(x, y);
	if (!el) return null;
	const t = el.closest('[data-drop]');
	if (t && t.dataset.drop) return t;
	return null;
}

function dragMove(ev) {
	const g = $('ghost'), note = $('dropnote');
	g.style.transform = 'translate(' + (ev.clientX + 14) + 'px,' + (ev.clientY + 12) + 'px)';
	if (ev.clientX < 1 || ev.clientY < 1 || ev.clientX >= window.innerWidth - 1 || ev.clientY >= window.innerHeight - 1) {
		// Out of the window: Windows takes over, so the files can land in any app.
		const paths = D.paths;
		cancelDrag();
		endPress();
		send('dragOut', { paths: paths });
		return;
	}
	const el = dropTargetAt(ev.clientX, ev.clientY);
	let dest = el ? el.dataset.drop : null;
	if (dest && (D.keys.has(keyOf(dest)) || D.paths.every(p => keyOf(parentOf(p)) === keyOf(dest)) || D.paths.some(p => keyOf(dest).startsWith(keyOf(p) + '\\')))) dest = null;
	if (D.el && D.el !== el) D.el.classList.remove('drop');
	D.el = dest ? el : null;
	D.target = dest;
	if (D.el) D.el.classList.add('drop');
	// Hovering a tab for a moment opens it, so you can drop into it.
	if (el && el.classList.contains('tab')) {
		if (D.hoverTab !== el) { D.hoverTab = el; D.hoverAt = Date.now(); }
		else if (Date.now() - D.hoverAt > 650) {
			const t = tabs.find(x => x.el === el);
			if (t && t !== active) activate(t);
		}
	} else D.hoverTab = null;
	if (dest) {
		const move = moveFor(D.paths, dest, ev);
		note.innerHTML = (move ? 'Move to ' : 'Copy to ') + '<b>' + esc(baseName(dest)) + '</b>';
		note.style.transform = 'translate(' + (ev.clientX + 16) + 'px,' + (ev.clientY + 68) + 'px)';
		note.classList.add('show');
	} else note.classList.remove('show');
}

function moveFor(paths, dest, ev) {
	if (ev.ctrlKey) return false;
	if (ev.shiftKey) return true;
	return paths.every(p => rootOf(p) === rootOf(dest));
}

function dragDrop(ev) {
	const d = D;
	cancelDrag();
	if (d.target) transfer(d.paths, d.target, moveFor(d.paths, d.target, ev));
}

function cancelDrag() {
	if (!D) return;
	if (D.el) D.el.classList.remove('drop');
	D = null;
	$('ghost').classList.remove('show');
	$('dropnote').classList.remove('show');
	body.classList.remove('dragging');
}

// Files dragged in from other apps.
let extEl = null;
const hasFiles = e => e.dataTransfer && [...e.dataTransfer.types].includes('Files');

function extTarget(e) {
	const el = dropTargetAt(e.clientX, e.clientY);
	if (el) return { el: el, dest: el.dataset.drop };
	const c = document.elementFromPoint(e.clientX, e.clientY);
	if (c && c.closest('#content') && canWrite()) return { el: null, dest: active.path };
	return null;
}

document.addEventListener('dragover', e => {
	if (!hasFiles(e)) return;
	const t = extTarget(e);
	if (extEl && (!t || t.el !== extEl)) { extEl.classList.remove('drop'); extEl = null; }
	if (!t) { e.dataTransfer.dropEffect = 'none'; e.preventDefault(); return; }
	e.preventDefault();
	e.dataTransfer.dropEffect = e.ctrlKey ? 'copy' : e.shiftKey ? 'move' : 'copy';
	if (t.el) { extEl = t.el; extEl.classList.add('drop'); }
});
document.addEventListener('dragleave', e => {
	if (e.relatedTarget) return;
	if (extEl) { extEl.classList.remove('drop'); extEl = null; }
});
document.addEventListener('drop', e => {
	if (!hasFiles(e)) return;
	e.preventDefault();
	if (extEl) { extEl.classList.remove('drop'); extEl = null; }
	const t = extTarget(e);
	const files = [...e.dataTransfer.files];
	if (!t || !files.length) return;
	busy('Copying ' + plural(files.length, 'item') + '…');
	ask('drop', { dest: t.dest, mode: e.ctrlKey ? 'copy' : e.shiftKey ? 'move' : 'auto' }, files).then(r => {
		busy('');
		if (r.error) toast(r.error, true);
		reload(true);
	});
});

// --- Actions ------------------------------------------------------------------------------------------

async function openEntries(list, opts) {
	opts = opts || {};
	if (!list.length) return;
	const dirs = list.filter(e => e.dir), files = list.filter(e => !e.dir);
	if (dirs.length === 1 && !files.length && !opts.newTab) { go(active, dirs[0].path); return; }
	for (const d of dirs) newTab(d.path, tabs.indexOf(active) + 1, dirs.length > 1 || files.length > 0);
	if (!files.length) return;
	const r = await ask('open', { paths: files.map(f => f.path), verb: opts.verb || '' });
	if (r.navigate) go(active, r.navigate);
	else if (r.error) toast(r.error, true);
}

async function transfer(paths, dest, move) {
	busy((move ? 'Moving ' : 'Copying ') + plural(paths.length, 'item') + '…');
	const r = await ask('transfer', { paths: paths, dest: dest, move: move });
	busy('');
	if (r.error) toast(r.error, true);
	reload(true);
}

function copyPaths(list) {
	if (!list.length) return;
	send('copyText', { text: list.map(e => '"' + e.path + '"').join('\r\n') });
	toast(list.length === 1 ? 'Copied the path' : 'Copied ' + list.length + ' paths');
}

function clip(cut) {
	const list = selected();
	if (!list.length) return;
	send('clipSet', { paths: list.map(e => e.path), cut: cut });
	S.clip = { keys: new Set(list.map(e => e.key)), cut: cut };
	paintAll();
	toast((cut ? 'Cut ' : 'Copied ') + (list.length === 1 ? shownName(list[0]) : plural(list.length, 'item')));
}

async function paste(dest) {
	dest = dest || active.path;
	if (!dest || active.search && dest === active.path) return;
	busy('Pasting…');
	const r = await ask('paste', { dest: dest });
	busy('');
	if (r.empty) { toast('Nothing to paste'); return; }
	if (r.error) toast(r.error, true);
	if (S.clip && S.clip.cut) S.clip = null;
	reload(true);
}

async function del(permanent) {
	const list = selected();
	if (!list.length) return;
	if (permanent) {
		const what = list.length === 1 ? '“' + shownName(list[0]) + '”' : plural(list.length, 'item');
		if (!await confirmBox('Delete ' + what + ' for good?', 'It skips the Recycle Bin, so you can\'t get it back.', 'Delete')) return;
	}
	active.selectIndex = active.index.get(list[0].key);
	busy(permanent ? 'Deleting…' : 'Moving to the Recycle Bin…');
	const r = await ask('delete', { paths: list.map(e => e.path), permanent: permanent });
	busy('');
	if (r.error) toast(r.error, true);
	if (active.search) {
		const gone = new Set(list.map(e => e.key));
		active.search.items = active.search.items.filter(e => !gone.has(e.key) || !r.ok);
		refreshView(active);
		active.sel = new Set();
		renderAll();
	} else reload(true);
}

async function newFolder() {
	if (!canWrite()) return;
	const r = await ask('mkdir', { dir: active.path, name: 'New folder' });
	if (!r.ok) { toast(r.error || 'Couldn\'t make a folder here', true); return; }
	active.pendingSelect = r.name;
	active.pendingRename = true;
	load(active, true);
}

async function newFile() {
	if (!canWrite()) return;
	const r = await ask('newfile', { dir: active.path, name: 'New text document.txt' });
	if (!r.ok) { toast(r.error || 'Couldn\'t make a file here', true); return; }
	active.pendingSelect = r.name;
	active.pendingRename = true;
	load(active, true);
}

async function compress(list) {
	busy('Compressing…');
	const r = await ask('compress', { paths: list.map(e => e.path) });
	busy('');
	if (r.error) { toast(r.error, true); return; }
	active.pendingSelect = baseName(r.path);
	reload(true);
}

async function extract(e) {
	busy('Extracting ' + e.name + '…');
	const r = await ask('extract', { path: e.path });
	busy('');
	if (r.error) { toast(r.error, true); return; }
	active.pendingSelect = baseName(r.path);
	reload(true);
}

function togglePin(path) {
	const k = keyOf(path);
	const has = prefs.pinned.some(p => keyOf(p) === k);
	setPrefs({ pinned: has ? prefs.pinned.filter(p => keyOf(p) !== k) : prefs.pinned.concat([path]) });
	toast(has ? 'Unpinned ' + baseName(path) : 'Pinned ' + baseName(path) + ' to the sidebar');
}

const isPinned = path => prefs.pinned.some(p => keyOf(p) === keyOf(path));

// --- Rename ------------------------------------------------------------------------------------------

let renaming = null;

function startRename(key) {
	const t = active;
	const i = t.index.get(key);
	if (i == null || t.search && false) return;
	scrollToIndex(i);
	const el = live.get(key);
	if (!el) return;
	const e = t.view[i];
	setSel([key], key);
	const list = L.mode === 'list';
	const target = el.querySelector(list ? '.label' : '.name');
	const input = document.createElement(list ? 'input' : 'textarea');
	input.className = 'rename';
	input.value = e.name;
	input.spellcheck = false;
	if (!list) input.rows = 1;
	target.replaceWith(input);
	const fit = () => { if (!list) { input.style.height = 'auto'; input.style.height = Math.min(64, input.scrollHeight) + 'px'; } };
	fit();
	input.addEventListener('input', fit);
	input.focus();
	input.setSelectionRange(0, e.dir || !e.ext ? e.name.length : e.name.length - e.ext.length);
	renaming = { key: key, el: el, input: input, entry: e, tab: t };
	renderSelbar();
	input.addEventListener('keydown', ev => {
		ev.stopPropagation();
		if (ev.key === 'Enter') { ev.preventDefault(); commitRename(false); }
		else if (ev.key === 'Escape') { ev.preventDefault(); commitRename(true); }
	});
	input.addEventListener('blur', () => { if (renaming && renaming.input === input) commitRename(false); });
	input.addEventListener('mousedown', ev => ev.stopPropagation());
	input.addEventListener('dblclick', ev => ev.stopPropagation());
}

async function commitRename(cancel) {
	const r = renaming;
	if (!r) return;
	renaming = null;
	const val = r.input.value.replace(/[\r\n]/g, '').trim();
	r.el.remove();
	live.delete(r.key);
	if (r.tab === active) { renderItems(); renderSelbar(); }
	scroller.focus({ preventScroll: true });
	if (cancel || !val || val === r.entry.name) return;
	const res = await ask('rename', { path: r.entry.path, name: val });
	if (!res.ok) { toast(res.error || 'Couldn\'t rename it', true); return; }
	if (r.tab.search) {
		const e = r.tab.search.items.find(x => x.key === r.key);
		if (e) Object.assign(e, entry([val, e.dir ? 1 : 0, e.size, e.mtime, e.ctime, e.attrs, e.parent], e.parent));
		refreshView(r.tab);
		r.tab.sel = new Set([keyOf(join(r.entry.parent, val))]);
		if (r.tab === active) { clearLive(); renderAll(); }
		return;
	}
	r.tab.pendingSelect = val;
	load(r.tab, true);
}

// --- Search ------------------------------------------------------------------------------------------

let searchSeq = 1, searchTimer = 0;

$('search-in').addEventListener('input', () => {
	clearTimeout(searchTimer);
	const q = $('search-in').value.trim();
	$('searchbox').classList.toggle('active', !!$('search-in').value);
	searchTimer = setTimeout(() => {
		if (q) startSearch(active, q);
		else endSearch(active, true);
	}, q.length <= 1 ? 380 : 220);
});
$('search-in').addEventListener('focus', () => $('searchbox').classList.add('focus'));
$('search-in').addEventListener('blur', () => $('searchbox').classList.remove('focus'));
$('search-in').addEventListener('keydown', e => {
	e.stopPropagation();
	if (e.key === 'Escape') {
		e.preventDefault();
		if ($('search-in').value) { $('search-in').value = ''; $('searchbox').classList.remove('active'); endSearch(active, true); }
		else scroller.focus();
	} else if (e.key === 'Enter' || e.key === 'ArrowDown') {
		e.preventDefault();
		clearTimeout(searchTimer);
		const q = $('search-in').value.trim();
		if (q && (!active.search || active.search.q !== q)) startSearch(active, q);
		scroller.focus();
		if (active.view.length) { active.anchor = active.view[0].key; setSel([active.view[0].key], active.view[0].key); }
	}
});
$('search-x').addEventListener('click', () => {
	$('search-in').value = '';
	$('searchbox').classList.remove('active');
	endSearch(active, true);
	scroller.focus();
});

function startSearch(tab, q) {
	const root = tab.path || S.home;
	if (!root) return;
	if (tab.search) send('cancelSearch');
	tab.search = { q: q, sid: searchSeq++, items: [], done: false, folders: 0, root: root, truncated: false };
	tab.sel = new Set();
	tab.cursor = tab.anchor = null;
	refreshView(tab);
	send('search', { sid: tab.search.sid, root: root, q: q, hidden: prefs.showHidden });
	renderTab(tab);
	if (tab === active) {
		$('searchbox').classList.add('active');
		clearLive();
		scroller.scrollTop = 0;
		renderAll();
	}
}

function endSearch(tab, rerender) {
	if (!tab.search) return;
	send('cancelSearch');
	tab.search = null;
	refreshView(tab);
	tab.sel = new Set();
	renderTab(tab);
	if (tab === active) {
		$('search-in').value = '';
		$('searchbox').classList.remove('active', 'busy');
		if (rerender) {
			clearLive();
			renderAll();
			if (tab.path) load(tab, true);
			else loadHome();
		}
	}
}

let foundRaf = 0;
function onFound(m) {
	const tab = tabs.find(t => t.search && t.search.sid === m.sid);
	if (!tab) return;
	const s = tab.search;
	for (const row of m.items || []) s.items.push(entry(row, row[6]));
	s.folders = m.folders || s.folders;
	if (m.done) { s.done = true; s.truncated = !!m.truncated; }
	if (foundRaf) return;
	foundRaf = requestAnimationFrame(() => {
		foundRaf = 0;
		refreshView(tab);
		if (tab !== active) return;
		layout();
		renderItems();
		renderEmpty();
		renderStatus();
		$('searchbox').classList.toggle('busy', !s.done);
	});
}

// --- Status, selection bar, details ----------------------------------------------------------------

function renderStatus() {
	const t = active;
	const count = $('st-count'), sel = $('st-sel'), free = $('st-free');
	if (homeMode()) { count.textContent = ''; sel.textContent = ''; free.textContent = ''; return; }
	if (t.search) count.textContent = plural(t.view.length, 'result') + (t.search.truncated ? '+' : '') + (t.search.done ? '' : ' so far');
	else count.textContent = t.loading && !t.view.length ? '' : plural(t.view.length, 'item');
	const list = selected();
	if (list.length) {
		const files = list.filter(e => !e.dir);
		const size = files.reduce((a, e) => a + Math.max(0, e.size), 0);
		sel.textContent = plural(list.length, 'selected', 'selected').replace(/^1 /, '1 ') + (files.length ? ' · ' + fmtSize(size) : '');
	} else sel.textContent = '';
	free.textContent = t.total && !t.search ? fmtSize(t.free) + ' free of ' + fmtSize(t.total) : '';
}

let busyCount = 0;
function busy(text) {
	$('st-busy').textContent = text || '';
	busyCount = text ? busyCount + 1 : Math.max(0, busyCount - 1);
}

const selbar = $('selbar');
selbar.innerHTML = '<span class="count"></span>' +
	'<button class="icon-btn" data-a="open" title="Open (Enter)">' + icon('open', 17) + '</button><span class="sep"></span>' +
	'<button class="icon-btn" data-a="cut" title="Cut (Ctrl+X)">' + icon('cut', 17) + '</button>' +
	'<button class="icon-btn" data-a="copy" title="Copy (Ctrl+C)">' + icon('copy', 17) + '</button>' +
	'<button class="icon-btn" data-a="rename" title="Rename (F2)">' + icon('rename', 17) + '</button>' +
	'<button class="icon-btn danger" data-a="delete" title="Delete (Del)">' + icon('trash', 17) + '</button><span class="sep"></span>' +
	'<button class="icon-btn" data-a="more" title="More">' + icon('dot', 17).replace('<circle cx="12" cy="12" r="3" fill="currentColor"/>', '<circle cx="6" cy="12" r="1.6" fill="currentColor"/><circle cx="12" cy="12" r="1.6" fill="currentColor"/><circle cx="18" cy="12" r="1.6" fill="currentColor"/>') + '</button>' +
	'<button class="icon-btn" data-a="clear" title="Clear selection (Esc)">' + icon('close', 15) + '</button>';
selbar.addEventListener('mousedown', e => e.preventDefault());
selbar.addEventListener('click', e => {
	const b = e.target.closest('button');
	if (!b) return;
	switch (b.dataset.a) {
		case 'open': openEntries(selected()); break;
		case 'cut': clip(true); break;
		case 'copy': clip(false); break;
		case 'rename': { const l = selected(); if (l.length === 1) startRename(l[0].key); break; }
		case 'delete': del(false); break;
		case 'more': { const r = b.getBoundingClientRect(); itemMenu(r.left, r.top - 8, true); break; }
		case 'clear': setSel([]); break;
	}
});

function renderSelbar() {
	const n = active ? active.sel.size : 0;
	const show = n > 0 && !homeMode() && !renaming;
	selbar.classList.toggle('show', show);
	if (!show) return;
	selbar.querySelector('.count').innerHTML = '<b>' + n.toLocaleString() + '</b> selected';
	selbar.querySelector('[data-a=rename]').style.display = n === 1 ? '' : 'none';
}

let detailsTimer = 0, detailsSeq = 0;
function renderDetails() {
	if (!prefs.details) return;
	clearTimeout(detailsTimer);
	detailsTimer = setTimeout(fillDetails, 60);
}

async function fillDetails() {
	const pane = $('details');
	const t = active;
	const seq = ++detailsSeq;
	const list = homeMode() ? [] : selected();
	let e = list.length === 1 ? list[0] : null;
	if (!e && !list.length && t.path && !t.search) e = { name: baseName(t.path), dir: true, path: t.path, mtime: 0, folder: true, ext: '', key: keyOf(t.path), parent: parentOf(t.path) };
	if (!e && !list.length) {
		pane.innerHTML = '<div class="dt-preview">' + icon('home', 64) + '</div><div class="dt-name">Home</div><div class="dt-kind">Pick a file to see more about it.</div>';
		return;
	}
	if (!e) {
		const files = list.filter(x => !x.dir), size = files.reduce((a, x) => a + Math.max(0, x.size), 0);
		pane.innerHTML = '<div class="dt-preview">' + folderArt('', 96) + '</div><div class="dt-name">' + plural(list.length, 'item') + '</div>' +
			'<div class="dt-kind">' + plural(list.length - files.length, 'folder') + ', ' + plural(files.length, 'file') + '</div>' +
			(files.length ? '<div class="dt-rows"><span class="k">Size</span><span class="v">' + fmtSize(size) + '</span></div>' : '');
		return;
	}
	const photo = !e.dir && prefs.thumbs && THUMB_EXT.has(e.ext);
	const art = e.dir ? folderArt(folderKind(e.path), 112) : '<img class="' + (PHOTO_EXT.has(e.ext) ? 'photo' : '') + '" src="' + esc(iconUrl(e, photo ? 256 : 112, true)) + '" data-cat="' + category(e) + '" data-size="112" data-label="' + esc(e.ext.slice(1)) + '" alt="">';
	const rows = [];
	rows.push(['Type', typeName(e)]);
	if (!e.dir) rows.push(['Size', fmtSize(e.size) + (e.size >= 1024 ? ' (' + e.size.toLocaleString() + ' bytes)' : '')]);
	if (e.mtime) rows.push(['Modified', fmtDate(e.mtime)]);
	if (e.ctime) rows.push(['Created', fmtDate(e.ctime)]);
	rows.push(['Location', e.folder ? parentOf(e.path) || e.path : e.parent]);
	const renderRows = extra => '<div class="dt-rows">' + rows.concat(extra || []).map(r => '<span class="k">' + esc(r[0]) + '</span><span class="v">' + esc(r[1]) + '</span>').join('') + '</div>';
	pane.innerHTML = '<div class="dt-preview">' + art + '</div><div class="dt-name">' + esc(e.name) + '</div><div class="dt-kind">' + esc(typeName(e)) + '</div>' + renderRows() +
		'<div class="dt-actions"><button class="btn" data-a="open">' + icon('open', 15) + 'Open</button><button class="btn" data-a="path">' + icon('path', 15) + 'Copy path</button></div>';
	pane.querySelector('[data-a=open]').onclick = () => e.folder ? null : openEntries([e]);
	if (e.folder) pane.querySelector('[data-a=open]').remove();
	pane.querySelector('[data-a=path]').onclick = () => copyPaths([e]);
	const p = await ask('preview', { path: e.path });
	if (seq !== detailsSeq) return;
	const extra = [];
	if (p.w) extra.push(['Dimensions', p.w + ' × ' + p.h]);
	if (e.dir && p.files != null) extra.push(['Contains', plural(p.dirs, 'folder') + ', ' + plural(p.files, 'file')]);
	if (p.target) extra.push(['Points to', p.target]);
	if (extra.length) pane.querySelector('.dt-rows').outerHTML = renderRows(extra);
	if (p.text != null && !photo) {
		const pre = document.createElement('pre');
		pre.textContent = p.text.slice(0, 4000);
		const box = pane.querySelector('.dt-preview');
		box.innerHTML = '';
		box.appendChild(pre);
	}
}

// --- Menus ------------------------------------------------------------------------------------------

let openPanel = null, panelDone = null;

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
	$('settings-btn').classList.remove('open');
	openPanel = null;
	if (panelDone) { const f = panelDone; panelDone = null; f(); }
	return true;
}

$('veil').addEventListener('mousedown', e => { e.preventDefault(); closePanels(); });
$('veil').addEventListener('contextmenu', e => e.preventDefault());

function menuButton(it) {
	const b = document.createElement('button');
	b.className = 'item-m' + (it.disabled ? ' disabled' : '') + (it.strong ? ' strong' : '') + (it.danger ? ' danger' : '');
	const lead = it.check !== undefined ? '<span class="tick">' + (it.check ? icon('check', 16) : '') + '</span>' : it.art ? it.art : it.icon ? icon(it.icon, 16) : '';
	b.innerHTML = lead + '<span class="label">' + esc(it.label) + '</span>' + (it.key ? '<span class="key">' + esc(it.key) + '</span>' : '');
	b.addEventListener('click', () => { closePanels(); if (it.run) it.run(); });
	return b;
}

function showMenu(items, x, y, done) {
	const m = $('menu');
	m.innerHTML = '';
	for (const it of items) {
		if (!it) continue;
		if (it.sep) {
			if (m.lastChild && !m.lastChild.classList.contains('sep')) { const d = document.createElement('div'); d.className = 'sep'; m.appendChild(d); }
			continue;
		}
		if (it.head) { const d = document.createElement('div'); d.className = 'head'; d.textContent = it.head; m.appendChild(d); continue; }
		if (it.icons) {
			const row = document.createElement('div');
			row.className = 'row-icons';
			for (const b of it.icons) {
				const btn = document.createElement('button');
				btn.title = b.label + (b.key ? ' (' + b.key + ')' : '');
				if (b.danger) btn.className = 'danger';
				btn.innerHTML = icon(b.icon, 17) + '<span>' + esc(b.label) + '</span>';
				btn.onclick = () => { closePanels(); b.run(); };
				row.appendChild(btn);
			}
			m.appendChild(row);
			continue;
		}
		m.appendChild(menuButton(it));
	}
	while (m.lastChild && m.lastChild.classList.contains('sep')) m.lastChild.remove();
	showPanel(m);
	panelDone = done || null;
	const w = m.offsetWidth, h = m.offsetHeight;
	const left = Math.max(6, Math.min(x, window.innerWidth - w - 6));
	const top = y + h > window.innerHeight - 6 ? Math.max(6, y - h) : y;
	m.style.left = left + 'px';
	m.style.top = top + 'px';
	m.style.transformOrigin = (left < x - 4 ? 'right ' : 'left ') + (top < y ? 'bottom' : 'top');
}

function itemMenu(x, y, above) {
	const list = selected();
	if (!list.length) return;
	const one = list.length === 1 ? list[0] : null;
	const items = [];
	items.push({ icons: [
		{ label: 'Cut', icon: 'cut', key: 'Ctrl+X', run: () => clip(true) },
		{ label: 'Copy', icon: 'copy', key: 'Ctrl+C', run: () => clip(false) },
		one ? { label: 'Rename', icon: 'rename', key: 'F2', run: () => startRename(one.key) } : null,
		{ label: 'Delete', icon: 'trash', key: 'Del', danger: true, run: () => del(false) },
	].filter(Boolean) });
	items.push({ label: 'Open', icon: 'open', key: 'Enter', strong: true, run: () => openEntries(list) });
	if (one && one.dir) {
		items.push({ label: 'Open in new tab', icon: 'tab', key: 'Ctrl+Enter', run: () => openEntries([one], { newTab: true }) });
		items.push({ label: 'Open in new window', icon: 'window', run: () => send('cmd', { cmd: 'newWindow', path: one.path }) });
	}
	if (one && !one.dir) items.push({ label: 'Open with…', icon: 'grid', run: () => send('openWith', { path: one.path }) });
	if (one && RUNNABLE.has(one.ext)) items.push({ label: 'Run as administrator', icon: 'shield', run: () => openEntries([one], { verb: 'runas' }) });
	if (active.search && one) items.push({ label: 'Open file location', icon: 'folderPlus', run: () => go(active, one.parent, { select: one.name }) });
	items.push({ sep: true });
	if (one && one.dir) items.push({ label: 'Paste into folder', icon: 'paste', run: () => paste(one.path) });
	items.push({ label: 'Copy as path', icon: 'path', key: 'Ctrl+Shift+C', run: () => copyPaths(list) });
	if (one && one.dir) items.push({ label: isPinned(one.path) ? 'Unpin from sidebar' : 'Pin to sidebar', icon: isPinned(one.path) ? 'unpin' : 'pin', run: () => togglePin(one.path) });
	items.push({ sep: true });
	if (one && one.ext === '.zip') items.push({ label: 'Extract here', icon: 'extract', run: () => extract(one) });
	if (!(one && one.ext === '.zip')) items.push({ label: 'Compress to ZIP', icon: 'zip', run: () => compress(list) });
	if (one && one.dir) items.push({ label: 'Open in Terminal', icon: 'terminal', run: () => send('terminal', { path: one.path }) });
	if (one) items.push({ label: 'Show in Windows Explorer', icon: 'external', run: () => send('explorer', { path: one.path }) });
	items.push({ sep: true });
	items.push({ label: 'Delete for good', icon: 'trash', key: 'Shift+Del', danger: true, run: () => del(true) });
	if (one) items.push({ label: 'Properties', icon: 'info', key: 'Alt+Enter', run: () => send('props', { path: one.path }) });
	showMenu(items, x, y);
	if (above) {
		const m = $('menu');
		m.style.top = Math.max(6, y - m.offsetHeight) + 'px';
		m.style.transformOrigin = 'left bottom';
	}
}

function backgroundMenu(x, y) {
	const t = active;
	const w = canWrite();
	const radio = (label, on, run) => ({ label: label, check: on, run: run });
	showMenu([
		w ? { label: 'New folder', icon: 'folderPlus', key: 'Ctrl+Shift+N', run: newFolder } : null,
		w ? { label: 'New text document', icon: 'filePlus', run: newFile } : null,
		w ? { label: 'Paste', icon: 'paste', key: 'Ctrl+V', run: () => paste() } : null,
		{ sep: true },
		{ head: 'Sort by' },
		radio('Name', prefs.sort === 'name', () => setPrefs({ sort: 'name', desc: false })),
		radio('Date modified', prefs.sort === 'date', () => setPrefs({ sort: 'date', desc: true })),
		radio('Type', prefs.sort === 'type', () => setPrefs({ sort: 'type', desc: false })),
		radio('Size', prefs.sort === 'size', () => setPrefs({ sort: 'size', desc: true })),
		{ sep: true },
		radio('Icons', prefs.view === 'grid', () => setPrefs({ view: 'grid' })),
		radio('Details', prefs.view === 'list', () => setPrefs({ view: 'list' })),
		radio('Show hidden items', prefs.showHidden, () => setPrefs({ showHidden: !prefs.showHidden })),
		{ sep: true },
		t.path && !t.search ? { label: isPinned(t.path) ? 'Unpin from sidebar' : 'Pin to sidebar', icon: isPinned(t.path) ? 'unpin' : 'pin', run: () => togglePin(t.path) } : null,
		t.path && !t.search ? { label: 'Open in Terminal', icon: 'terminal', run: () => send('terminal', { path: t.path }) } : null,
		t.path && !t.search ? { label: 'Open in Windows Explorer', icon: 'external', run: () => send('explorer', { path: t.path }) } : null,
		t.path && !t.search ? { label: 'Copy folder path', icon: 'path', run: () => copyPaths([{ path: t.path }]) } : null,
		{ label: 'Select all', icon: 'check', key: 'Ctrl+A', run: selectAll },
		t.path && !t.search ? { label: 'Properties', icon: 'info', run: () => send('props', { path: t.path }) } : null,
	], x, y);
}

function placeMenu(path, x, y) {
	if (!path) return;
	showMenu([
		{ label: 'Open', icon: 'open', strong: true, run: () => go(active, path) },
		{ label: 'Open in new tab', icon: 'tab', run: () => newTab(path, tabs.indexOf(active) + 1) },
		{ label: 'Open in new window', icon: 'window', run: () => send('cmd', { cmd: 'newWindow', path: path }) },
		{ sep: true },
		isRoot(path) ? null : { label: isPinned(path) ? 'Unpin from sidebar' : 'Pin to sidebar', icon: isPinned(path) ? 'unpin' : 'pin', run: () => togglePin(path) },
		{ label: 'Paste here', icon: 'paste', run: () => paste(path) },
		{ label: 'Copy as path', icon: 'path', run: () => copyPaths([{ path: path }]) },
		{ label: 'Open in Terminal', icon: 'terminal', run: () => send('terminal', { path: path }) },
		{ label: 'Properties', icon: 'info', run: () => send('props', { path: path }) },
	], x, y);
}

function tabMenu(tab, x, y) {
	showMenu([
		{ label: 'New tab', icon: 'plus', key: 'Ctrl+T', run: () => newTab('', tabs.indexOf(tab) + 1) },
		{ label: 'Duplicate tab', icon: 'copy', run: () => newTab(tab.path, tabs.indexOf(tab) + 1) },
		{ label: 'Open in new window', icon: 'window', run: () => { send('cmd', { cmd: 'newWindow', path: tab.path || '' }); closeTab(tab); } },
		{ sep: true },
		tabs.length > 1 ? { label: 'Close other tabs', icon: 'close', run: () => { for (const t of tabs.slice()) if (t !== tab) closeTab(t); } } : null,
		{ label: 'Close tab', icon: 'close', key: 'Ctrl+W', run: () => closeTab(tab) },
	], x, y);
}

function newMenu() {
	const r = $('new-btn').getBoundingClientRect();
	showMenu([
		{ label: 'Folder', art: folderArt('', 18), key: 'Ctrl+Shift+N', run: newFolder },
		{ label: 'Text document', icon: 'filePlus', run: newFile },
	], r.left, r.bottom + 6);
}

function sortMenu() {
	const r = $('sort-btn').getBoundingClientRect();
	const radio = (label, on, run) => ({ label: label, check: on, run: run });
	showMenu([
		radio('Name', prefs.sort === 'name', () => setPrefs({ sort: 'name', desc: false })),
		radio('Date modified', prefs.sort === 'date', () => setPrefs({ sort: 'date', desc: true })),
		radio('Type', prefs.sort === 'type', () => setPrefs({ sort: 'type', desc: false })),
		radio('Size', prefs.sort === 'size', () => setPrefs({ sort: 'size', desc: true })),
		{ sep: true },
		radio('Ascending', !prefs.desc, () => setPrefs({ desc: false })),
		radio('Descending', prefs.desc, () => setPrefs({ desc: true })),
		{ sep: true },
		radio('Folders first', prefs.foldersFirst, () => setPrefs({ foldersFirst: !prefs.foldersFirst })),
	], Math.min(r.left, window.innerWidth - 260), r.bottom + 6);
}

// --- Settings -----------------------------------------------------------------------------------------

function toggleSettings() {
	if (openPanel === $('settings')) { closePanels(); return; }
	renderSettings();
	showPanel($('settings'));
	$('settings-btn').classList.add('open');
}

function renderSettings() {
	const s = $('settings');
	const sw = (key, label, hint) => '<div class="row"><div class="line"><div><div class="label">' + label + '</div>' + (hint ? '<div class="hint">' + hint + '</div>' : '') + '</div><button class="switch' + (prefs[key] ? ' on' : '') + '" data-key="' + key + '"></button></div></div>';
	s.innerHTML = '<h2>Oazy Files</h2><div class="sub">Your folders, in Oazy\'s glass</div>' +
		sw('showHidden', 'Show hidden items', 'Files and folders Windows keeps out of sight. Ctrl+H') +
		sw('showExt', 'Show file extensions', 'Like .txt and .exe after file names.') +
		sw('foldersFirst', 'Folders first', 'Keep folders above files whatever the sort.') +
		sw('thumbs', 'Picture and video previews', 'Show what\'s inside instead of an icon.') +
		'<div class="row"><div class="label">Glass <b id="glass-val"></b></div><input id="glass-in" type="range" min="0.3" max="0.95" step="0.01"></div>' +
		'<div class="row"><div class="label">Keys</div><div class="keys">' +
		[['New tab', 'Ctrl+T'], ['New folder', 'Ctrl+Shift+N'], ['Rename', 'F2'], ['Search', 'Ctrl+F'], ['Address bar', 'Ctrl+L'], ['Back / up', 'Alt+← / Alt+↑'], ['Details pane', 'Alt+P'], ['Icon size', 'Ctrl+wheel'], ['Delete for good', 'Shift+Del']]
			.map(k => '<span>' + k[0] + '</span><kbd>' + k[1] + '</kbd>').join('') + '</div></div>';
	for (const b of s.querySelectorAll('.switch')) b.onclick = () => { setPrefs({ [b.dataset.key]: !prefs[b.dataset.key] }); b.classList.toggle('on', !!prefs[b.dataset.key]); };
	const g = $('glass-in');
	g.value = prefs.glass;
	const show = () => { $('glass-val').textContent = Math.round((1 - g.value) * 100 / 0.7) + '%'; fillRange(g); };
	show();
	g.oninput = () => { prefs.glass = +g.value; document.documentElement.style.setProperty('--tint', g.value); show(); };
	g.onchange = () => setPrefs({ glass: +g.value });
}

function fillRange(r) {
	const min = +r.min, max = +r.max;
	r.style.setProperty('--fill', ((r.value - min) / (max - min) * 100) + '%');
}

function setPrefs(change) {
	Object.assign(prefs, change);
	send('prefs', { prefs: change });
	applyPrefs(change);
}

function applyPrefs(change) {
	const all = !change;
	const has = k => all || k in change;
	document.documentElement.style.setProperty('--tint', prefs.glass);
	document.documentElement.style.setProperty('--side', prefs.sideWidth + 'px');
	body.classList.toggle('details-on', !!prefs.details);
	$('zoom').value = prefs.iconSize;
	fillRange($('zoom'));
	if (all) return;
	if (has('pinned')) { renderSide(); if (homeMode()) renderHome(); }
	if (has('showHidden') && active.search) { startSearch(active, active.search.q); return; }
	if (has('showHidden') || has('sort') || has('desc') || has('foldersFirst')) for (const t of tabs) refreshView(t);
	if (has('view') || has('iconSize') || has('showExt') || has('thumbs') || has('showHidden') || has('sort') || has('desc') || has('foldersFirst') || has('details')) {
		clearLive();
		renderAll();
		const k = active.cursor;
		if (k && active.index.has(k)) scrollToIndex(active.index.get(k));
	}
}

$('zoom').addEventListener('input', () => {
	prefs.iconSize = +$('zoom').value;
	fillRange($('zoom'));
	clearLive();
	layout();
	renderItems();
});
$('zoom').addEventListener('change', () => setPrefs({ iconSize: prefs.iconSize }));

scroller.addEventListener('wheel', e => {
	if (!e.ctrlKey || homeMode()) return;
	e.preventDefault();
	zoom(e.deltaY < 0 ? 1 : -1);
}, { passive: false });

function zoom(dir) {
	if (prefs.view === 'list') { if (dir > 0) setPrefs({ view: 'grid', iconSize: 48 }); return; }
	const next = prefs.iconSize + dir * 12;
	if (next < 48) { setPrefs({ view: 'list' }); return; }
	setPrefs({ iconSize: Math.max(48, Math.min(208, next)) });
}

// --- Toast, confirm ---------------------------------------------------------------------------------

let toastTimer = 0;
function toast(text, error) {
	const t = $('toast');
	t.textContent = text;
	t.classList.toggle('error', !!error);
	t.classList.add('show');
	clearTimeout(toastTimer);
	toastTimer = setTimeout(() => t.classList.remove('show'), error ? 3200 : 1600);
}

function confirmBox(title, text, yes) {
	return new Promise(resolve => {
		const box = $('confirm');
		box.querySelector('.confirm-title').textContent = title;
		box.querySelector('.confirm-text').textContent = text;
		$('confirm-yes').textContent = yes || 'OK';
		let answered = false;
		const answer = v => { if (answered) return; answered = true; closePanels(); resolve(v); };
		showPanel(box, { dim: true });
		panelDone = () => answer(false);
		$('confirm-yes').onclick = () => { panelDone = null; answer(true); };
		$('confirm-no').onclick = () => answer(false);
		$('confirm-yes').focus();
	});
}

// --- Keyboard --------------------------------------------------------------------------------------------

let typeBuf = '', typeAt = 0;

function selectAll() {
	if (homeMode()) return;
	setSel(active.view.map(e => e.key));
}

function moveCursor(delta, ev, abs) {
	const t = active;
	const n = t.view.length;
	if (!n || !L) return;
	let i = t.cursor != null && t.index.has(t.cursor) ? t.index.get(t.cursor) : -1;
	let j = abs != null ? abs : (i < 0 ? 0 : i + delta);
	j = Math.max(0, Math.min(n - 1, j));
	const k = t.view[j].key;
	if (ev.shiftKey) selectRange(t.anchor || k, k, ev.ctrlKey);
	else if (ev.ctrlKey) { t.cursor = k; paintAll(); }
	else { t.anchor = k; setSel([k], k); }
	t.cursor = k;
	scrollToIndex(j);
	paintAll();
}

function typeAhead(ch) {
	const t = active;
	const now = Date.now();
	typeBuf = now - typeAt > 800 ? ch : typeBuf + ch;
	typeAt = now;
	const q = typeBuf.toLowerCase();
	const n = t.view.length;
	const start = t.cursor != null && t.index.has(t.cursor) ? t.index.get(t.cursor) : -1;
	const from = typeBuf.length === 1 ? start + 1 : Math.max(0, start);
	for (let o = 0; o < n; o++) {
		const i = (from + o) % n;
		if (t.view[i].name.toLowerCase().startsWith(q)) { moveCursor(0, {}, i); return; }
	}
}

const inField = e => e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA');

window.addEventListener('keydown', e => {
	const k = e.key, ctrl = e.ctrlKey, shift = e.shiftKey, alt = e.altKey;
	if (D && k === 'Escape') { cancelDrag(); endPress(); return; }
	if (openPanel) {
		if (k === 'Escape') { e.preventDefault(); closePanels(); }
		if (openPanel === $('confirm') && k === 'Enter') { e.preventDefault(); $('confirm-yes').click(); }
		if (openPanel === $('menu') && (k === 'ArrowDown' || k === 'ArrowUp' || k === 'Enter')) menuKeys(e);
		return;
	}
	if (inField(e)) return;
	const t = active;
	let handled = true;
	if (ctrl && (k === 't' || k === 'T') && !shift) newTab('', tabs.indexOf(t) + 1);
	else if (ctrl && (k === 'w' || k === 'W' || k === 'F4')) closeTab(t);
	else if (ctrl && k === 'Tab') cycleTab(shift ? -1 : 1);
	else if (ctrl && !shift && /^[1-9]$/.test(k)) { const i = k === '9' ? tabs.length - 1 : +k - 1; if (tabs[i]) activate(tabs[i]); }
	else if (ctrl && (k === 'n' || k === 'N') && !shift) send('cmd', { cmd: 'newWindow', path: t.path || '' });
	else if (ctrl && shift && (k === 'N' || k === 'n')) newFolder();
	else if ((ctrl && (k === 'l' || k === 'L')) || (alt && (k === 'd' || k === 'D')) || k === 'F4') editAddress();
	else if ((ctrl && (k === 'f' || k === 'F' || k === 'e' || k === 'E')) || k === 'F3') { $('search-in').focus(); $('search-in').select(); }
	else if ((alt && k === 'ArrowLeft') || k === 'Backspace' || k === 'BrowserBack') back();
	else if ((alt && k === 'ArrowRight') || k === 'BrowserForward') forward();
	else if (alt && k === 'ArrowUp') goUp();
	else if (alt && (k === 'p' || k === 'P')) setPrefs({ details: !prefs.details });
	else if (alt && k === 'Enter') { const l = selected(); send('props', { path: l.length ? l[0].path : t.path }); }
	else if (k === 'F5' || (ctrl && (k === 'r' || k === 'R'))) reload(false);
	else if (ctrl && k === ',') toggleSettings();
	else if (ctrl && (k === 'h' || k === 'H')) setPrefs({ showHidden: !prefs.showHidden });
	else if (ctrl && shift && k === '!') setPrefs({ view: 'grid' });
	else if (ctrl && shift && k === '@') setPrefs({ view: 'list' });
	else if (ctrl && shift && (k === '1' || k === 'Digit1')) setPrefs({ view: 'grid' });
	else if (ctrl && shift && (k === '2' || k === 'Digit2')) setPrefs({ view: 'list' });
	else if (ctrl && (k === '=' || k === '+')) zoom(1);
	else if (ctrl && k === '-') zoom(-1);
	else if (homeMode()) handled = homeKeys(e);
	else if (ctrl && (k === 'a' || k === 'A')) selectAll();
	else if (ctrl && (k === 'c' || k === 'C') && !shift) clip(false);
	else if (ctrl && shift && (k === 'c' || k === 'C')) copyPaths(selected().length ? selected() : [{ path: t.path }]);
	else if (ctrl && (k === 'x' || k === 'X')) clip(true);
	else if (ctrl && (k === 'v' || k === 'V')) paste();
	else if (k === 'F2') { const l = selected(); if (l.length) startRename((t.cursor && t.sel.has(t.cursor)) ? t.cursor : l[0].key); }
	else if (k === 'Delete') del(shift);
	else if (k === 'Enter') { const l = selected(); if (l.length) openEntries(l, { newTab: ctrl }); }
	else if (k === 'Escape') { if (t.search) endSearch(t, true); else if (t.sel.size) setSel([]); }
	else if (k === 'ArrowRight' && L && L.mode === 'grid') moveCursor(1, e);
	else if (k === 'ArrowLeft' && L && L.mode === 'grid') moveCursor(-1, e);
	else if (k === 'ArrowDown') moveCursor(L ? L.cols : 1, e);
	else if (k === 'ArrowUp') moveCursor(L ? -L.cols : -1, e);
	else if (k === 'Home') moveCursor(0, e, 0);
	else if (k === 'End') moveCursor(0, e, t.view.length - 1);
	else if (k === 'PageDown' || k === 'PageUp') {
		const rows = Math.max(1, Math.floor(scroller.clientHeight / (L.h + L.gapY)) - 1);
		moveCursor((k === 'PageDown' ? 1 : -1) * rows * L.cols, e);
	} else if (k === ' ' && ctrl && t.cursor) {
		const s = new Set(t.sel);
		if (s.has(t.cursor)) s.delete(t.cursor); else s.add(t.cursor);
		t.sel = s;
		selectionChanged();
	} else if (k.length === 1 && !ctrl && !alt && k !== ' ') typeAhead(k);
	else handled = false;
	if (handled) e.preventDefault();
});

function homeKeys(e) {
	if (e.key === 'Enter' && homeSel) {
		const r = (S.recent || []).find(x => x.key === homeSel);
		if (r) openEntries([r]);
		return true;
	}
	return false;
}

function menuKeys(e) {
	e.preventDefault();
	const items = [...$('menu').querySelectorAll('.item-m:not(.disabled)')];
	if (!items.length) return;
	let i = items.findIndex(b => b.classList.contains('hot'));
	if (e.key === 'Enter') { if (i >= 0) items[i].click(); return; }
	if (i >= 0) items[i].classList.remove('hot');
	i = e.key === 'ArrowDown' ? (i + 1) % items.length : (i <= 0 ? items.length - 1 : i - 1);
	items[i].classList.add('hot');
}

window.addEventListener('mouseup', e => {
	if (e.button === 3) { e.preventDefault(); back(); }
	else if (e.button === 4) { e.preventDefault(); forward(); }
});
window.addEventListener('mousedown', e => { if (e.button === 3 || e.button === 4) e.preventDefault(); });
window.addEventListener('contextmenu', e => { if (!inField(e)) e.preventDefault(); });

// --- Window chrome -----------------------------------------------------------------------------------------

$('newtab').onclick = () => newTab('', tabs.length);
$('settings-btn').onclick = () => toggleSettings();
$('win-min').onclick = () => send('cmd', { cmd: 'minimize' });
$('win-max').onclick = () => send('cmd', { cmd: 'maximize' });
$('win-close').onclick = () => send('cmd', { cmd: 'close' });
$('back').onclick = back;
$('fwd').onclick = forward;
$('up').onclick = goUp;
$('reload').onclick = () => reload(false);
$('new-btn').onclick = newMenu;
$('sort-btn').onclick = sortMenu;
$('details-btn').onclick = () => setPrefs({ details: !prefs.details });
for (const b of $('viewseg').children) b.onclick = () => setPrefs({ view: b.dataset.view });

for (const el of [$('strip'), $('drag'), $('tabs')]) {
	el.addEventListener('mousedown', e => {
		if (e.target !== el || e.button !== 0 || S.nativeDrag) return;
		send('drag');
	});
	el.addEventListener('dblclick', e => {
		if (e.target !== el) return;
		if (el === $('tabs')) newTab('', tabs.length);
		else send('cmd', { cmd: 'maximize' });
	});
}

function setAccent(hex) {
	const m = /^#?([0-9a-f]{6})$/i.exec(hex || '');
	if (!m) return;
	const n = parseInt(m[1], 16);
	document.documentElement.style.setProperty('--accent', '#' + m[1]);
	document.documentElement.style.setProperty('--accent-rgb', (n >> 16) + ', ' + ((n >> 8) & 255) + ', ' + (n & 255));
}

// --- From the host -------------------------------------------------------------------------------------------

function onHost(e) {
	const m = e.data;
	if (!m || !m.t) return;
	switch (m.t) {
		case 'reply': {
			const f = waiting.get(m.rid);
			if (f) { waiting.delete(m.rid); f(m); }
			break;
		}
		case 'init': init(m); break;
		case 'found': onFound(m); break;
		case 'changed':
			if (active && active.path && keyOf(m.path) === keyOf(active.path) && !active.search && !renaming) load(active, true);
			break;
		case 'dragEnd':
			if (m.effect & 2) reload(true);
			break;
		case 'win':
			S.maximized = m.max;
			body.classList.toggle('maximized', m.max);
			$('win-max').innerHTML = icon(m.max ? 'restore' : 'max', 13);
			$('win-max').title = m.max ? 'Restore' : 'Maximise';
			break;
		case 'active':
			body.classList.toggle('inactive', !m.on);
			if (m.on && Date.now() - placesAt > 15000) refreshPlaces();
			break;
		case 'open': newTab(m.path || '', tabs.length); break;
		case 'prefs':
			Object.assign(prefs, m.prefs || {});
			applyPrefs(m.prefs || {});
			break;
		case 'test': selftest(m); break;
	}
}

function init(m) {
	S.glass = m.glass !== false;
	S.nativeDrag = !!m.nativeDrag;
	S.selftest = !!m.selftest;
	body.classList.toggle('solid', !S.glass);
	Object.assign(prefs, m.prefs || {});
	for (const k in DEFAULTS) if (typeof prefs[k] !== typeof DEFAULTS[k] || (Array.isArray(DEFAULTS[k]) && !Array.isArray(prefs[k]))) prefs[k] = DEFAULTS[k];
	setAccent(m.accent);
	applyPrefs(null);
	refreshPlaces();
	const list = (m.tabs && m.tabs.length) ? m.tabs : [''];
	list.forEach((p, i) => newTab(p, null, i > 0));
	scroller.focus();
}

function selftest(m) {
	switch (m.action) {
		case 'state': {
			const names = active.view.slice(0, 500).map(e => e.name);
			const images = canvas.querySelectorAll('img.ok').length;
			send('test', { what: 'state', names: names, images: images, path: active.path });
			break;
		}
		case 'go': go(active, m.path || ''); break;
		case 'view': setPrefs({ view: m.view }); break;
		case 'select': {
			const e = active.view.find(x => x.name === m.name);
			if (e) { active.anchor = e.key; setSel([e.key], e.key); }
			break;
		}
		case 'search': $('search-in').value = m.q; startSearch(active, m.q); break;
		case 'clearSearch': endSearch(active, true); break;
		case 'menu': {
			if (!active.view.length) break;
			const e = active.view[0];
			setSel([e.key], e.key);
			const el = live.get(e.key);
			const r = el ? el.getBoundingClientRect() : { left: 200, top: 200, width: 0, height: 0 };
			itemMenu(r.left + r.width / 2, r.top + r.height / 2);
			break;
		}
		case 'closeMenu': closePanels(); break;
	}
}

if (wv) {
	wv.addEventListener('message', onHost);
	send('ready');
}
