// Oazy Claude's page: conversations with Claude Code, drawn in Oazy's glass.
//
// oazy_claude.cs runs claude headless and hands every line it prints to us
// as "c" + JSON; we speak Claude Code's stream-json back through it ("line"
// messages): user messages, answers to its permission requests
// (control_response), and control requests of our own (interrupt, mode,
// model). Other host messages are JSON objects; requests carry "rid" and get
// {"t": "reply", "rid"} back.
'use strict';

const wv = (window.chrome && window.chrome.webview) || window.__oazyMock || null;
const $ = id => document.getElementById(id);
const body = document.body;

function send(t, extra) {
	if (wv) wv.postMessage(Object.assign({ t: t }, extra || {}));
}

let nextRid = 1;
const waiting = new Map();
function ask(t, extra) {
	return new Promise(resolve => {
		if (!wv) { resolve({}); return; }
		const rid = nextRid++;
		waiting.set(rid, resolve);
		wv.postMessage(Object.assign({ t: t, rid: rid }, extra || {}));
	});
}

const MODES = [
	{ id: 'default', name: 'Ask before edits', short: 'Ask first', desc: 'Claude asks before it edits files or runs commands', icon: 'shield' },
	{ id: 'acceptEdits', name: 'Edit automatically', short: 'Auto-edit', desc: 'Edits files without asking; still asks before commands', icon: 'bolt' },
	{ id: 'plan', name: 'Plan first', short: 'Plan', desc: 'Reads and plans, changes nothing until you approve', icon: 'plan' },
];
const MODELS = [
	{ id: '', name: 'Default', desc: 'Whatever Claude Code would pick for you' },
	{ id: 'opus', name: 'Opus', desc: 'The most capable, for hard problems' },
	{ id: 'sonnet', name: 'Sonnet', desc: 'Fast and very capable' },
	{ id: 'haiku', name: 'Haiku', desc: 'The quickest, for small jobs' },
];
const DEFAULTS = { model: '', mode: 'default', cwd: '', side: true, folders: [] };
let prefs = Object.assign({}, DEFAULTS);

const S = {
	claude: '', home: '', terminal: false, selftest: false, nativeDrag: false,
	cwd: '',
	session: '',       // Claude Code's session id (to resume)
	proc: false,       // a claude process is running for this conversation
	starting: null,    // the promise of one being started
	running: false,    // a reply is under way
	turn: null,        // the element of the reply under way
	since: 0,
	streamed: new Set(),
	blocks: new Map(),
	tools: new Map(),
	asks: [],          // permission requests waiting for an answer
	attachments: [],
	recents: [],
	liveModel: '',
	title: '',
	ctl: 1,
};

// --- Chrome --------------------------------------------------------------------------------

$('side-btn').innerHTML = icon('sidebar', 16);
$('brand-mark').innerHTML = mark(16);
$('home-mark').innerHTML = mark(54);
$('win-min').innerHTML = icon('min', 15);
$('win-max').innerHTML = icon('max', 13);
$('win-close').innerHTML = icon('close', 15);
$('new-chat').querySelector('.ic-slot').innerHTML = icon('plus', 15);
$('img-btn').innerHTML = icon('image', 15);
$('term-btn').innerHTML = icon('terminal', 14) + '<span>Terminal</span>';

$('win-min').onclick = () => send('cmd', { cmd: 'minimize' });
$('win-max').onclick = () => send('cmd', { cmd: 'maximize' });
$('win-close').onclick = () => send('cmd', { cmd: 'close' });
$('side-btn').onclick = () => setPrefs({ side: !prefs.side });
$('new-chat').onclick = () => newChat();
$('folder-btn').onclick = e => folderMenu(e.currentTarget);
$('home-folder').onclick = e => folderMenu(e.currentTarget);
$('term-btn').onclick = () => openTerminal();
$('mode-btn').onclick = e => modeMenu(e.currentTarget);
$('model-btn').onclick = e => modelMenu(e.currentTarget);
$('img-btn').onclick = () => $('file-in').click();
$('send').onclick = () => (S.running && !composerText() ? stop() : submit());
$('file-in').onchange = () => { addFiles($('file-in').files); $('file-in').value = ''; };

for (const el of [$('strip'), $('drag'), $('brand')]) {
	el.addEventListener('mousedown', e => {
		if (e.button !== 0 || S.nativeDrag || (e.target !== el && !el.contains(e.target)) || e.target.closest('button')) return;
		send('drag');
	});
	el.addEventListener('dblclick', e => { if (!e.target.closest('button')) send('cmd', { cmd: 'maximize' }); });
}

window.addEventListener('mousedown', e => { if (e.button === 3 || e.button === 4) e.preventDefault(); });
document.addEventListener('click', e => {
	const a = e.target.closest('a[data-url]');
	if (a) { e.preventDefault(); send('open', { url: a.dataset.url }); return; }
	const copy = e.target.closest('.code .copy');
	if (copy) {
		const code = copy.closest('.code').querySelector('code');
		send('copy', { text: code ? code.textContent : '' });
		flash(copy);
	}
});

function flash(btn) {
	btn.classList.add('done');
	btn.innerHTML = icon('check', 13);
	setTimeout(() => { btn.classList.remove('done'); btn.innerHTML = icon('copy', 13); }, 1200);
}

function setPrefs(p) {
	Object.assign(prefs, p);
	send('prefs', { prefs: p });
	applyPrefs();
}

function applyPrefs() {
	body.classList.toggle('side-open', !!prefs.side);
	const mode = MODES.find(m => m.id === prefs.mode) || MODES[0];
	$('mode-btn').innerHTML = icon(mode.icon, 13) + '<span>' + mode.short + '</span>' + icon('down', 12);
	$('mode-btn').dataset.mode = mode.id;
	const model = MODELS.find(m => m.id === prefs.model) || MODELS[0];
	$('model-btn').innerHTML = '<span>' + (model.id ? model.name : (S.liveModel ? prettyModel(S.liveModel) : 'Default')) + '</span>' + icon('down', 12);
}

function prettyModel(id) {
	const m = /claude-(opus|sonnet|haiku|fable)-([\d-]+)/.exec(id || '');
	if (!m) return id || 'Default';
	return m[1][0].toUpperCase() + m[1].slice(1) + ' ' + m[2].replace(/-\d{8}$/, '').replace(/-/g, '.');
}

// --- Folders -----------------------------------------------------------------------------------

function baseName(p) {
	const parts = String(p || '').replace(/[\\/]+$/, '').split(/[\\/]/);
	return parts[parts.length - 1] || p;
}

function shortPath(p) {
	if (!p) return '';
	if (S.home && p.toLowerCase().startsWith(S.home.toLowerCase())) return '~' + p.slice(S.home.length);
	return p;
}

function setCwd(p) {
	S.cwd = p || S.home;
	const label = S.cwd === S.home ? 'Home' : baseName(S.cwd);
	$('folder-btn').innerHTML = icon('folder', 14) + '<span>' + esc(label) + '</span>' + icon('down', 12);
	$('folder-btn').title = S.cwd + ' (Ctrl+O to change)';
	$('home-folder').innerHTML = icon('folder', 15) + '<span>in <b>' + esc(label) + '</b></span><span class="dim">' + esc(shortPath(S.cwd)) + '</span>' + icon('down', 12);
	const folders = [S.cwd].concat((prefs.folders || []).filter(f => f.toLowerCase() !== S.cwd.toLowerCase())).slice(0, 8);
	setPrefs({ cwd: S.cwd, folders: folders });
}

async function pickFolder() {
	const r = await ask('pickFolder', { from: S.cwd });
	if (r.path) useFolder(r.path);
}

// Another folder is another conversation (unless this one hasn't started).
function useFolder(p) {
	if (p.toLowerCase() === (S.cwd || '').toLowerCase()) return;
	if (hasConversation()) newChat(p);
	else setCwd(p);
}

function folderMenu(anchor) {
	const items = [];
	for (const f of (prefs.folders || []).slice(0, 7)) {
		items.push({ label: f === S.home ? 'Home' : baseName(f), sub: shortPath(f), icon: 'folder', on: f.toLowerCase() === S.cwd.toLowerCase(), run: () => useFolder(f) });
	}
	if (items.length) items.push('-');
	items.push({ label: 'Choose a folder…', icon: 'plus', key: 'Ctrl O', run: pickFolder });
	items.push({ label: 'Show in Files', icon: 'open', run: () => send('explore', { path: S.cwd }) });
	openMenu(anchor, items);
}

// --- Menus, dialogs and toasts ----------------------------------------------------------------------

let menuAnchor = null;
function openMenu(anchor, items, up) {
	const m = $('menu');
	if (!m.hidden && menuAnchor === anchor) { closeMenu(); return; }
	m.innerHTML = '';
	for (const it of items) {
		if (it === '-') { m.appendChild(Object.assign(document.createElement('div'), { className: 'sep' })); continue; }
		const b = document.createElement('button');
		b.className = 'item' + (it.on ? ' on' : '');
		b.innerHTML = (it.icon ? icon(it.icon, 15) : '<span class="ic-gap"></span>') +
			'<span class="label"><span>' + esc(it.label) + '</span>' + (it.sub ? '<small>' + esc(it.sub) + '</small>' : '') + '</span>' +
			(it.on ? icon('check', 14) : (it.key ? '<kbd>' + esc(it.key) + '</kbd>' : ''));
		b.onclick = () => { closeMenu(); it.run(); };
		m.appendChild(b);
	}
	m.hidden = false;
	menuAnchor = anchor;
	anchor.classList.add('open');
	const r = anchor.getBoundingClientRect();
	const mr = m.getBoundingClientRect();
	let left = Math.min(r.left, innerWidth - mr.width - 10);
	let top = up || r.bottom + mr.height + 10 > innerHeight ? r.top - mr.height - 8 : r.bottom + 6;
	m.style.left = Math.max(10, left) + 'px';
	m.style.top = Math.max(46, top) + 'px';
	m.classList.toggle('up', top < r.top);
	const first = m.querySelector('.item');
	if (first) first.focus({ preventScroll: true });
}

function closeMenu() {
	$('menu').hidden = true;
	if (menuAnchor) menuAnchor.classList.remove('open');
	menuAnchor = null;
}

document.addEventListener('mousedown', e => {
	if (!$('menu').hidden && !$('menu').contains(e.target) && !(menuAnchor && menuAnchor.contains(e.target))) closeMenu();
}, true);
window.addEventListener('blur', closeMenu);
window.addEventListener('resize', () => { closeMenu(); autoSide(); });

function modeMenu(anchor) {
	openMenu(anchor, MODES.map(m => ({ label: m.name, sub: m.desc, icon: m.icon, on: m.id === prefs.mode, run: () => setMode(m.id) })), true);
}

function modelMenu(anchor) {
	openMenu(anchor, MODELS.map(m => ({
		label: m.name, sub: m.id ? m.desc : (S.liveModel ? 'Now ' + prettyModel(S.liveModel) : m.desc), on: m.id === prefs.model,
		run: () => setModel(m.id),
	})), true);
}

function setMode(id) {
	setPrefs({ mode: id });
	if (S.proc) control({ subtype: 'set_permission_mode', mode: id });
}

function setModel(id) {
	setPrefs({ model: id });
	if (S.proc && id) control({ subtype: 'set_model', model: id });
}

function dialog(title, text, buttons) {
	return new Promise(resolve => {
		const d = $('dialog');
		d.innerHTML = '<div class="dlg"><h2>' + esc(title) + '</h2><p>' + esc(text) + '</p><div class="row"></div></div>';
		const row = d.querySelector('.row');
		buttons.forEach((b, i) => {
			const el = document.createElement('button');
			el.className = 'btn' + (b.primary ? ' primary' : '') + (b.danger ? ' danger' : '');
			el.textContent = b.label;
			el.onclick = () => { d.hidden = true; resolve(i); };
			row.appendChild(el);
		});
		d.hidden = false;
		const p = row.querySelector('.primary') || row.lastChild;
		if (p) p.focus();
	});
}

let toastTimer = 0;
function toast(text) {
	const t = $('toast');
	t.textContent = text;
	t.classList.add('on');
	clearTimeout(toastTimer);
	toastTimer = setTimeout(() => t.classList.remove('on'), 3200);
}

// --- Recent conversations ------------------------------------------------------------------------

function ago(ms) {
	const s = (Date.now() - ms) / 1000;
	if (s < 60) return 'now';
	if (s < 3600) return Math.floor(s / 60) + 'm';
	if (s < 86400) return Math.floor(s / 3600) + 'h';
	if (s < 86400 * 7) return Math.floor(s / 86400) + 'd';
	return new Date(ms).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
}

function drawRecents() {
	const box = $('recents');
	box.innerHTML = '';
	if (!S.recents.length) {
		box.innerHTML = '<div class="side-empty">Your conversations with Claude Code show up here, from this app and the terminal.</div>';
		return;
	}
	for (const r of S.recents) {
		const b = document.createElement('button');
		b.className = 'recent' + (r.id === S.session ? ' on' : '');
		b.innerHTML = '<span class="r-title">' + esc(r.title) + '</span><span class="r-sub"><span>' + esc(r.cwd ? baseName(r.cwd) : '') + '</span><span>' + ago(r.at) + '</span></span>';
		b.title = r.title + (r.cwd ? '\n' + r.cwd : '');
		b.onclick = () => resume(r);
		box.appendChild(b);
	}
}

function autoSide() {
	body.classList.toggle('narrow', innerWidth < 860);
}

// --- Conversations -----------------------------------------------------------------------------

function hasConversation() {
	return !!S.session || $('thread').children.length > 0;
}

function showHome() {
	const empty = $('thread').children.length === 0;
	body.classList.toggle('empty', empty);
	$('home').hidden = !empty;
}

function stopProc() {
	if (S.proc || S.starting) send('stop');
	S.proc = false;
	S.starting = null;
	setRunning(false);
}

function clearThread() {
	$('thread').innerHTML = '';
	S.streamed.clear();
	S.blocks.clear();
	S.tools.clear();
	S.asks = [];
	drawAsk();
	S.turn = null;
}

function newChat(cwd) {
	stopProc();
	clearThread();
	S.session = '';
	setTitle('');
	if (cwd) setCwd(cwd);
	showHome();
	drawRecents();
	$('input').focus();
}

async function resume(r) {
	if (r.id === S.session && S.proc) return;
	stopProc();
	clearThread();
	S.session = r.id;
	if (r.cwd) setCwd(r.cwd);
	setTitle(r.title);
	drawRecents();
	$('thread').innerHTML = '<div class="loading">' + mark(22) + '</div>';
	showHome();
	const res = await ask('history', { id: r.id });
	if (S.session !== r.id) return;
	$('thread').innerHTML = '';
	drawHistory(res.lines || []);
	showHome();
	scrollDown(true);
	$('input').focus();
}

function setTitle(t) {
	S.title = t || '';
	$('convo-title').textContent = S.title;
	send('title', { text: S.title.slice(0, 60) });
}

// Starts claude for this conversation if it isn't running.
function ensureProc() {
	if (S.proc) return Promise.resolve(true);
	if (S.starting) return S.starting;
	S.starting = ask('start', { cwd: S.cwd, resume: S.session, model: prefs.model, mode: prefs.mode }).then(r => {
		S.starting = null;
		if (!r.ok) {
			if (r.error === 'missing') { S.claude = ''; drawSetup(); notice('error', 'Claude Code isn\'t installed on this PC yet.', 'Install it once and this app uses it, signed in as you.'); }
			else notice('error', 'Couldn\'t start Claude Code', r.error || '');
			setRunning(false);
			return false;
		}
		S.proc = true;
		return true;
	});
	return S.starting;
}

function writeLine(obj) {
	send('line', { line: JSON.stringify(obj) });
}

function control(request) {
	writeLine({ type: 'control_request', request_id: 'oazy-' + (S.ctl++), request: request });
}

function composerText() {
	return $('input').value.trim();
}

async function submit(textArg) {
	const text = (textArg != null ? textArg : $('input').value).trim();
	if (!text && !S.attachments.length) return;
	if (!S.claude) { drawSetup(); toast('Install Claude Code first'); return; }
	const images = S.attachments.slice();
	$('input').value = '';
	S.attachments = [];
	drawAttach();
	autosize();
	if (!S.title) setTitle(text.split('\n')[0].slice(0, 80) || 'Image');
	userBubble(text, images);
	showHome();
	scrollDown(true);
	setRunning(true);
	if (!await ensureProc()) return;
	const content = images.map(a => ({ type: 'image', source: { type: 'base64', media_type: a.type, data: a.data } }));
	if (text) content.push({ type: 'text', text: text });
	writeLine({ type: 'user', message: { role: 'user', content: content.length === 1 && !images.length ? text : content }, parent_tool_use_id: null, session_id: S.session || 'default' });
}

function stop() {
	if (!S.proc) return;
	control({ subtype: 'interrupt' });
	// Anything still waiting for an answer is moot now.
	for (const a of S.asks) answer(a, 'deny', true);
	status('Stopping…');
}

let runTimer = 0;
function setRunning(on) {
	if (S.running === on) return;
	S.running = on;
	body.classList.toggle('running', on);
	send('busy', { on: on });
	clearInterval(runTimer);
	if (on) {
		S.since = Date.now();
		runTimer = setInterval(tick, 1000);
		tick();
	} else {
		status('');
		S.turn = null;
		const w = $('thread').querySelector('.working');
		if (w) w.remove();
	}
	drawSend();
}

function tick() {
	const s = Math.floor((Date.now() - S.since) / 1000);
	status(s < 60 ? s + 's' : Math.floor(s / 60) + 'm ' + (s % 60) + 's');
	working();
}

function status(t) { $('status').textContent = t; }

function drawSend() {
	const stopNow = S.running && !composerText() && !S.attachments.length;
	$('send').innerHTML = icon(stopNow ? 'stop' : 'send', 16);
	$('send').classList.toggle('stop', stopNow);
	$('send').title = stopNow ? 'Stop (Esc)' : 'Send (Enter)';
	$('send').disabled = !stopNow && !composerText() && !S.attachments.length;
}

// --- Drawing a conversation ------------------------------------------------------------------------

function el(tag, cls, html) {
	const e = document.createElement(tag);
	if (cls) e.className = cls;
	if (html != null) e.innerHTML = html;
	return e;
}

function userBubble(text, images) {
	const row = el('div', 'msg user');
	const b = el('div', 'bubble');
	if (images && images.length) {
		const strip = el('div', 'imgs');
		for (const a of images) strip.appendChild(Object.assign(document.createElement('img'), { src: 'data:' + a.type + ';base64,' + a.data }));
		b.appendChild(strip);
	}
	if (text) b.appendChild(el('div', 'text', esc(text)));
	row.appendChild(b);
	$('thread').appendChild(row);
	S.turn = null;
	return row;
}

// The reply under way: one column with Claude's mark, text and tool cards.
function turn() {
	if (S.turn && S.turn.isConnected) return S.turn;
	const t = el('div', 'msg claude');
	t.appendChild(el('div', 'avatar', mark(15)));
	t.appendChild(el('div', 'col'));
	const w = $('thread').querySelector('.working');
	$('thread').insertBefore(t, w);
	S.turn = t;
	return t;
}

function col() { return turn().querySelector('.col'); }

function working() {
	if (!S.running) return;
	let w = $('thread').querySelector('.working');
	if (!w) {
		w = el('div', 'working', '<span class="orbit">' + mark(14) + '</span><span class="w-text"></span>');
		$('thread').appendChild(w);
	}
	const busy = S.asks.length ? 'Waiting for you' : (S.thinking ? 'Thinking' : 'Working');
	w.querySelector('.w-text').textContent = busy + '… ' + $('status').textContent + (S.asks.length ? '' : ' · Esc to stop');
	w.classList.toggle('paused', S.asks.length > 0);
}

function textBlock() {
	const b = el('div', 'md');
	b._src = '';
	col().appendChild(b);
	return b;
}

let drawQueued = new Set();
function drawMd(b) {
	drawQueued.add(b);
	if (drawQueued.size > 1) return;
	requestAnimationFrame(() => {
		const stick = nearBottom();
		for (const x of drawQueued) x.innerHTML = MD.render(x._src);
		drawQueued.clear();
		if (stick) scrollDown();
	});
}

function nearBottom() {
	const s = $('scroll');
	return s.scrollHeight - s.scrollTop - s.clientHeight < 120;
}

function scrollDown(force) {
	const s = $('scroll');
	if (force || nearBottom()) requestAnimationFrame(() => { s.scrollTop = s.scrollHeight; });
}

function notice(kind, title, text, actions) {
	const n = el('div', 'notice ' + kind, icon(kind === 'error' ? 'alert' : 'compact', 15) + '<div><b>' + esc(title) + '</b>' + (text ? '<span>' + esc(text) + '</span>' : '') + '</div>');
	if (actions) {
		const row = el('div', 'n-actions');
		for (const a of actions) {
			const b = el('button', 'btn small', esc(a.label));
			b.onclick = a.run;
			row.appendChild(b);
		}
		n.querySelector('div').appendChild(row);
	}
	const w = $('thread').querySelector('.working');
	$('thread').insertBefore(n, w);
	showHome();
	scrollDown(true);
	return n;
}

// --- Tool cards ------------------------------------------------------------------------------------

const TOOL_ICONS = {
	Bash: 'terminal', PowerShell: 'terminal', BashOutput: 'terminal', KillShell: 'terminal', Read: 'eye', Edit: 'edit', MultiEdit: 'edit', Write: 'newfile',
	NotebookEdit: 'edit', Glob: 'search', Grep: 'search', LS: 'folder', WebFetch: 'globe', WebSearch: 'globe', TodoWrite: 'todo',
	Task: 'agent', Agent: 'agent', ExitPlanMode: 'plan', Skill: 'book',
};

function rel(p) {
	if (!p) return '';
	const c = (S.cwd || '').replace(/[\\/]+$/, '');
	if (c && p.toLowerCase().startsWith(c.toLowerCase() + '\\')) return p.slice(c.length + 1);
	if (c && p.toLowerCase().startsWith(c.toLowerCase() + '/')) return p.slice(c.length + 1);
	return shortPath(p);
}

function short(s, n) {
	s = String(s || '').replace(/\s+/g, ' ').trim();
	return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

// [verb, target] for a tool call, in plain words.
function describe(name, input, done) {
	const i = input || {};
	const past = done !== false;
	switch (name) {
		case 'Bash': case 'PowerShell': return [i.description ? short(i.description, 70) : (past ? 'Ran' : 'Running'), i.description ? '' : short(i.command, 90), i.command];
		case 'Read': return [past ? 'Read' : 'Reading', rel(i.file_path)];
		case 'Edit': case 'MultiEdit': return [past ? 'Edited' : 'Editing', rel(i.file_path)];
		case 'Write': return [past ? 'Wrote' : 'Writing', rel(i.file_path)];
		case 'NotebookEdit': return [past ? 'Edited' : 'Editing', rel(i.notebook_path)];
		case 'Glob': return ['Found files', i.pattern];
		case 'Grep': return ['Searched for', i.pattern];
		case 'LS': return ['Listed', rel(i.path)];
		case 'WebFetch': return ['Read', i.url];
		case 'WebSearch': return ['Searched the web for', i.query];
		case 'TodoWrite': return ['Updated the plan', ''];
		case 'Task': case 'Agent': return [i.description ? short(i.description, 70) : 'Ran an agent', i.subagent_type || ''];
		case 'ExitPlanMode': return ['Plan ready', ''];
		case 'Skill': return ['Used a skill', i.skill || i.command || ''];
		case 'BashOutput': return ['Checked a command', ''];
		case 'KillShell': return ['Stopped a command', ''];
	}
	if (/^mcp__/.test(name)) {
		const p = name.split('__');
		return [p.slice(2).join(' ').replace(/_/g, ' '), p[1]];
	}
	return [name, ''];
}

function toolCard(id, name, parent) {
	let c = S.tools.get(id);
	if (c) return c;
	c = el('div', 'tool running');
	c._id = id;
	c._name = name;
	c._input = {};
	c.innerHTML = '<button class="t-head"><span class="t-ic">' + icon(TOOL_ICONS[name] || (/^mcp__/.test(name) ? 'tool' : 'tool'), 14) + '</span>' +
		'<span class="t-what"><span class="t-verb"></span><span class="t-target"></span></span><span class="t-state"></span><span class="t-chev">' + icon('chevron', 12) + '</span></button>' +
		'<div class="t-body"></div>';
	c.querySelector('.t-head').onclick = () => { c.classList.toggle('open'); if (c.classList.contains('open')) fillBody(c); };
	S.tools.set(id, c);
	const host = parent || col();
	// Cards in a row sit together as one stack.
	const last = host.lastElementChild;
	if (last && last.classList.contains('tools')) last.appendChild(c);
	else {
		const stack = el('div', 'tools');
		stack.appendChild(c);
		host.appendChild(stack);
	}
	headline(c);
	return c;
}

function headline(c) {
	const d = describe(c._name, c._input, !c.classList.contains('running'));
	c.querySelector('.t-verb').textContent = d[0];
	const t = c.querySelector('.t-target');
	t.textContent = d[1] || '';
	t.hidden = !d[1];
	c.title = d[2] || '';
	if (c._name === 'TodoWrite' && Array.isArray(c._input.todos)) drawTodos(c);
	if (c._name === 'Edit' || c._name === 'MultiEdit' || c._name === 'Write') {
		const n = countLines(c);
		const st = c.querySelector('.t-target');
		if (n && d[1]) st.innerHTML = esc(d[1]) + ' <span class="delta"><span class="add">+' + n[0] + '</span> <span class="del">−' + n[1] + '</span></span>';
	}
}

function countLines(c) {
	const i = c._input;
	const lines = s => (s ? String(s).split('\n').length : 0);
	if (c._name === 'Write') return [lines(i.content), 0];
	if (c._name === 'Edit') return [lines(i.new_string), lines(i.old_string)];
	if (c._name === 'MultiEdit' && Array.isArray(i.edits)) return i.edits.reduce((a, e) => [a[0] + lines(e.new_string), a[1] + lines(e.old_string)], [0, 0]);
	return null;
}

function setInput(c, input) {
	c._input = input || {};
	headline(c);
	if (c.classList.contains('open')) fillBody(c);
}

function toolDone(id, content, isError) {
	const c = S.tools.get(id);
	if (!c) return;
	c.classList.remove('running');
	c.classList.toggle('error', !!isError);
	c._result = resultText(content);
	c.querySelector('.t-state').innerHTML = isError ? icon('x', 13) : '';
	headline(c);
	if (c.classList.contains('open')) fillBody(c);
}

function resultText(content) {
	if (typeof content === 'string') return content;
	if (Array.isArray(content)) return content.map(b => b.type === 'text' ? b.text : (b.type === 'image' ? '[image]' : '')).join('\n');
	return content == null ? '' : JSON.stringify(content);
}

function diffHtml(oldS, newS) {
	const o = String(oldS || '').split('\n'), n = String(newS || '').split('\n');
	// Trim what both share at the ends, show the rest as removed then added.
	let a = 0;
	while (a < o.length && a < n.length && o[a] === n[a]) a++;
	let b = 0;
	while (b < o.length - a && b < n.length - a && o[o.length - 1 - b] === n[n.length - 1 - b]) b++;
	const ctx = (arr, from, to) => arr.slice(Math.max(0, from), Math.max(0, to)).map(l => '<div class="d-ctx">' + (esc(l) || ' ') + '</div>').join('');
	let h = ctx(o, a - 2, a);
	for (const l of o.slice(a, o.length - b)) h += '<div class="d-del">' + (esc(l) || ' ') + '</div>';
	for (const l of n.slice(a, n.length - b)) h += '<div class="d-add">' + (esc(l) || ' ') + '</div>';
	h += ctx(o, o.length - b, o.length - b + 2);
	return '<pre class="diff">' + h + '</pre>';
}

function clip(s, n) {
	s = String(s || '');
	return s.length > n ? s.slice(0, n) + '\n…' : s;
}

function fillBody(c) {
	const i = c._input || {};
	const r = c._result;
	let h = '';
	switch (c._name) {
		case 'Bash': case 'PowerShell':
			h += '<pre class="cmd"><span class="prompt">&gt;</span> ' + esc(i.command || '') + '</pre>';
			if (r != null) h += '<pre class="out">' + esc(clip(r, 6000) || '(no output)') + '</pre>';
			break;
		case 'Edit':
			h += '<div class="t-file">' + esc(rel(i.file_path)) + '</div>' + diffHtml(i.old_string, i.new_string);
			break;
		case 'MultiEdit':
			h += '<div class="t-file">' + esc(rel(i.file_path)) + '</div>' + (i.edits || []).map(e => diffHtml(e.old_string, e.new_string)).join('');
			break;
		case 'Write':
			h += '<div class="t-file">' + esc(rel(i.file_path)) + '</div><pre class="diff">' + clip(i.content, 8000).split('\n').map(l => '<div class="d-add">' + (esc(l) || ' ') + '</div>').join('') + '</pre>';
			break;
		case 'Read':
			h += '<div class="t-file">' + esc(i.file_path || '') + '</div>';
			if (r != null) h += '<pre class="out">' + esc(clip(r.replace(/^\s*\d+[→\t]/gm, ''), 4000)) + '</pre>';
			break;
		case 'TodoWrite': break;
		case 'ExitPlanMode':
			h += '<div class="md">' + MD.render(i.plan || '') + '</div>';
			break;
		default:
			h += '<pre class="out">' + esc(clip(JSON.stringify(i, null, 2), 3000)) + '</pre>';
			if (r != null) h += '<pre class="out">' + esc(clip(r, 6000)) + '</pre>';
	}
	if (c._subs && c._subs.length) h += '<div class="subs">' + c._subs.map(s => '<div>' + icon(TOOL_ICONS[s[0]] || 'tool', 12) + '<span>' + esc(s[1]) + '</span></div>').join('') + '</div>';
	if (c.classList.contains('error') && r && c._name !== 'Bash' && c._name !== 'PowerShell') h += '<pre class="out err">' + esc(clip(r, 2000)) + '</pre>';
	c.querySelector('.t-body').innerHTML = h;
}

function drawTodos(c) {
	let box = c.querySelector('.todos');
	if (!box) {
		box = el('div', 'todos');
		c.insertBefore(box, c.querySelector('.t-body'));
	}
	box.innerHTML = c._input.todos.map(t => '<div class="todo ' + esc(t.status) + '"><span class="box">' + (t.status === 'completed' ? icon('check', 11) : '') + '</span><span>' +
		esc(t.status === 'in_progress' && t.activeForm ? t.activeForm : t.content) + '</span></div>').join('');
	c.classList.add('has-todos');
}

// A subagent's steps show inside its card, as one line each.
function subStep(parentId, name, input) {
	const c = S.tools.get(parentId);
	if (!c) return;
	const d = describe(name, input, true);
	c._subs = (c._subs || []).concat([[name, d[0] + (d[1] ? ' ' + d[1] : '')]]).slice(-40);
	const t = c.querySelector('.t-target');
	t.hidden = false;
	t.textContent = d[0] + (d[1] ? ' ' + d[1] : '');
	if (c.classList.contains('open')) fillBody(c);
}

// --- Permission requests -------------------------------------------------------------------------

function onPermission(m) {
	const req = m.request || {};
	const a = { id: m.request_id, tool: req.tool_name, input: req.input || {}, suggestions: req.permission_suggestions || [], toolUseId: req.tool_use_id, reason: req.decision_reason || '' };
	S.asks.push(a);
	drawAsk();
	send('attention');
	if (S.selftest) send('test', { what: 'permission', detail: a.tool });
}

function suggestionLabel(a) {
	for (const s of a.suggestions) {
		if (s.type === 'setMode' && s.mode === 'acceptEdits') return 'Allow all edits';
		if (s.type === 'addRules' && Array.isArray(s.rules) && s.rules.length) {
			const r = s.rules[0];
			if (r.ruleContent) return 'Always allow ' + short(r.ruleContent, 28);
			return 'Always allow ' + (r.toolName || a.tool);
		}
		if (s.type === 'addDirectories') return 'Allow this folder';
	}
	return '';
}

function drawAsk() {
	const box = $('ask');
	const a = S.asks[0];
	body.classList.toggle('asking', !!a);
	if (!a) { box.hidden = true; box.innerHTML = ''; working(); return; }
	const i = a.input;
	let title, detail = '';
	const plan = a.tool === 'ExitPlanMode';
	switch (a.tool) {
		case 'Bash': case 'PowerShell':
			title = 'Run this command?';
			detail = '<pre class="cmd"><span class="prompt">&gt;</span> ' + esc(i.command || '') + '</pre>' + (i.description ? '<div class="a-note">' + esc(i.description) + '</div>' : '');
			break;
		case 'Edit': case 'MultiEdit':
			title = 'Edit ' + baseName(i.file_path) + '?';
			detail = '<div class="t-file">' + esc(rel(i.file_path)) + '</div>' + (a.tool === 'Edit' ? diffHtml(i.old_string, i.new_string) : (i.edits || []).map(e => diffHtml(e.old_string, e.new_string)).join(''));
			break;
		case 'Write':
			title = 'Create ' + baseName(i.file_path) + '?';
			detail = '<div class="t-file">' + esc(rel(i.file_path)) + '</div><pre class="diff">' + clip(i.content, 3000).split('\n').map(l => '<div class="d-add">' + (esc(l) || ' ') + '</div>').join('') + '</pre>';
			break;
		case 'ExitPlanMode':
			title = 'Claude\'s plan';
			detail = '<div class="md">' + MD.render(i.plan || '') + '</div>';
			break;
		case 'WebFetch':
			title = 'Read this page?';
			detail = '<div class="t-file">' + esc(i.url || '') + '</div>';
			break;
		default: {
			const d = describe(a.tool, i, false);
			title = 'Allow ' + (/^mcp__/.test(a.tool) ? d[0] + ' (' + d[1] + ')' : a.tool) + '?';
			detail = '<pre class="out">' + esc(clip(JSON.stringify(i, null, 2), 1500)) + '</pre>';
		}
	}
	// The diff is already right here; the card it belongs to can wait.
	const more = S.asks.length > 1 ? '<span class="a-more">+' + (S.asks.length - 1) + ' more</span>' : '';
	box.innerHTML = '<div class="a-head">' + icon(plan ? 'plan' : 'shield', 15) + '<b>' + esc(title) + '</b>' + more + '</div>' +
		'<div class="a-body">' + detail + '</div>' +
		'<div class="a-row"><input class="a-why" type="text" placeholder="' + (plan ? 'Or tell Claude what to change' : 'Or tell Claude what to do instead') + '" spellcheck="true"><div class="grow"></div></div>';
	const row = box.querySelector('.a-row');
	const btn = (label, cls, run, key) => {
		const b = el('button', 'btn ' + cls, esc(label) + (key ? '<kbd>' + key + '</kbd>' : ''));
		b.onclick = run;
		row.appendChild(b);
		return b;
	};
	if (plan) {
		btn('Keep planning', '', () => answer(a, 'deny'), 'Esc');
		btn('Start building', 'primary', () => answer(a, 'allow', false, 'acceptEdits'), 'Enter');
	} else {
		btn('Deny', '', () => answer(a, 'deny'), 'Esc');
		const always = suggestionLabel(a);
		if (always) btn(always, '', () => answer(a, 'always'));
		btn('Allow', 'primary', () => answer(a, 'allow'), 'Enter');
	}
	const why = box.querySelector('.a-why');
	why.addEventListener('keydown', e => {
		if (e.key === 'Enter' && why.value.trim()) { e.preventDefault(); answer(a, 'deny'); }
		e.stopPropagation();
	});
	box.hidden = false;
	box.classList.remove('in');
	void box.offsetWidth;
	box.classList.add('in');
	working();
	scrollDown(true);
}

function answer(a, how, quiet, mode) {
	const i = S.asks.indexOf(a);
	if (i < 0) return;
	S.asks.splice(i, 1);
	const why = $('ask').querySelector('.a-why');
	const note = why && !quiet ? why.value.trim() : '';
	let response;
	if (how === 'deny') {
		response = { behavior: 'deny', message: note ? 'The user said no, and said: ' + note : 'The user said no to this. Don\'t try it again; ask what they want instead.' };
		if (!note && !quiet && a.tool !== 'ExitPlanMode') response.interrupt = false;
	} else {
		response = { behavior: 'allow', updatedInput: a.input };
		if (how === 'always' && a.suggestions.length) response.updatedPermissions = a.suggestions;
	}
	writeLine({ type: 'control_response', response: { subtype: 'success', request_id: a.id, response: response } });
	if (how === 'always') for (const s of a.suggestions) if (s.type === 'setMode') { prefs.mode = s.mode; setPrefs({ mode: s.mode }); }
	if (mode) setPrefs({ mode: mode });
	const c = S.tools.get(a.toolUseId);
	if (c && how === 'deny') c.classList.add('denied');
	drawAsk();
	$('input').focus();
}

// --- From claude -----------------------------------------------------------------------------------

function onClaude(m) {
	switch (m.type) {
		case 'system':
			if (m.subtype === 'init') {
				if (m.session_id) {
					const was = S.session;
					S.session = m.session_id;
					if (was !== S.session) drawRecents();
				}
				if (m.model) { S.liveModel = m.model; applyPrefs(); }
			} else if (m.subtype === 'compact_boundary') notice('info', 'Conversation compacted', 'Claude summarised the earlier part to make room.');
			break;
		case 'stream_event':
			if (!m.parent_tool_use_id) onStream(m.event || {});
			break;
		case 'assistant': onAssistant(m); break;
		case 'user': onUser(m); break;
		case 'result': onResult(m); break;
		case 'control_request':
			if (m.request && m.request.subtype === 'can_use_tool') onPermission(m);
			else if (m.request_id) writeLine({ type: 'control_response', response: { subtype: 'error', request_id: m.request_id, error: 'Not supported in Oazy' } });
			break;
		case 'control_cancel_request':
			S.asks = S.asks.filter(a => a.id !== m.request_id);
			drawAsk();
			break;
		case 'rate_limit_event': {
			const r = m.rate_limit_info || {};
			if (r.status === 'rejected') notice('error', 'You\'ve reached your usage limit', r.resetsAt ? 'It resets at ' + new Date(r.resetsAt * 1000).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' }) + '.' : '');
			break;
		}
	}
}

function onStream(e) {
	switch (e.type) {
		case 'message_start':
			if (e.message && e.message.id) { S.msg = e.message.id; S.streamed.add(e.message.id); }
			S.blocks.clear();
			break;
		case 'content_block_start': {
			const cb = e.content_block || {};
			if (cb.type === 'text') S.blocks.set(e.index, { type: 'text', el: textBlock() });
			else if (cb.type === 'thinking' || cb.type === 'redacted_thinking') { S.thinking = true; S.blocks.set(e.index, { type: 'thinking', el: thinkingBlock() }); working(); }
			else if (cb.type === 'tool_use' || cb.type === 'server_tool_use') S.blocks.set(e.index, { type: 'tool', card: toolCard(cb.id, cb.name), json: '' });
			scrollDown();
			break;
		}
		case 'content_block_delta': {
			const b = S.blocks.get(e.index);
			const d = e.delta || {};
			if (!b) break;
			if (d.type === 'text_delta' && b.type === 'text') { b.el._src += d.text; drawMd(b.el); }
			else if (d.type === 'thinking_delta' && b.type === 'thinking') { b.text = (b.text || '') + (d.thinking || ''); }
			else if (d.type === 'input_json_delta' && b.type === 'tool') {
				b.json += d.partial_json || '';
				// Enough of the input to say what it's doing, before it's all here.
				const fp = /"(file_path|command|pattern|url|query|description)"\s*:\s*"((?:[^"\\]|\\.)*)"/.exec(b.json);
				if (fp && !b.card._input[fp[1]]) { try { b.card._input[fp[1]] = JSON.parse('"' + fp[2] + '"'); headline(b.card); } catch (x) { } }
			}
			break;
		}
		case 'content_block_stop': {
			const b = S.blocks.get(e.index);
			if (b && b.type === 'tool' && b.json) { try { setInput(b.card, JSON.parse(b.json)); } catch (x) { } }
			if (b && b.type === 'thinking') { finishThinking(b); S.thinking = false; working(); }
			break;
		}
	}
}

function thinkingBlock() {
	const t = el('div', 'thinking', '<span class="th-label">Thinking</span>');
	t._start = Date.now();
	col().appendChild(t);
	return t;
}

function finishThinking(b) {
	const s = Math.max(1, Math.round((Date.now() - b.el._start) / 1000));
	b.el.classList.add('done');
	b.el.querySelector('.th-label').textContent = 'Thought for ' + s + 's';
	if (b.text && b.text.trim()) {
		b.el.classList.add('has-text');
		b.el.title = 'Show what Claude thought';
		b.el.appendChild(el('div', 'th-text', esc(b.text)));
		b.el.onclick = () => b.el.classList.toggle('open');
	}
}

function onAssistant(m) {
	const msg = m.message || {};
	const content = Array.isArray(msg.content) ? msg.content : [];
	if (m.parent_tool_use_id) {
		for (const c of content) if (c.type === 'tool_use') subStep(m.parent_tool_use_id, c.name, c.input);
		return;
	}
	if (msg.model && msg.model !== '<synthetic>') { S.liveModel = msg.model; }
	const streamed = msg.id && S.streamed.has(msg.id);
	for (const c of content) {
		if (c.type === 'tool_use') {
			const card = toolCard(c.id, c.name);
			setInput(card, c.input);
		} else if (!streamed && c.type === 'text' && c.text) {
			const b = textBlock();
			b._src = c.text;
			drawMd(b);
		}
	}
	scrollDown();
}

function onUser(m) {
	const msg = m.message || {};
	if (!Array.isArray(msg.content)) return;
	for (const c of msg.content) {
		if (c.type === 'tool_result') {
			if (m.parent_tool_use_id) continue;
			toolDone(c.tool_use_id, c.content, c.is_error);
		}
	}
}

function onResult(m) {
	if (m.session_id) S.session = m.session_id;
	for (const [, c] of S.tools) if (c.classList.contains('running')) { c.classList.remove('running'); headline(c); }
	if (m.is_error || (m.subtype && m.subtype !== 'success')) {
		const text = m.result || (m.errors || []).join('\n') || '';
		if (/login|log in|authenticat|api key|oauth|credential/i.test(text)) signInNotice(text);
		else if (m.subtype === 'error_max_turns') notice('error', 'Claude stopped after many steps', 'Send a message to let it carry on.');
		else if (!/interrupt|abort/i.test(text) && text) notice('error', 'Claude ran into a problem', text);
	}
	S.asks = [];
	drawAsk();
	setRunning(false);
	send('recents');
	if (S.selftest) send('test', { what: 'done', detail: $('thread').innerText.slice(0, 2000) });
}

function signInNotice(text) {
	notice('error', 'Claude Code needs you to sign in', text ? short(text, 200) : 'Sign in once in the terminal, then come back here.', [
		{ label: 'Sign in in Terminal', run: () => send('terminal', { cwd: S.cwd, args: '' }) },
	]);
}

function onExit(m) {
	const wasRunning = S.running;
	S.proc = false;
	S.starting = null;
	S.asks = [];
	drawAsk();
	setRunning(false);
	const err = (m.err || '').trim();
	if (/login|log in|authenticat|api key|oauth|credential/i.test(err)) signInNotice(err);
	else if (wasRunning || (m.code && m.code !== 0 && err)) notice('error', 'Claude Code stopped', err ? short(err, 400) : 'It closed unexpectedly. Send your message again to pick up where you left off.');
}

// --- History: a past conversation from its transcript ----------------------------------------------------

function drawHistory(lines) {
	S.turn = null;
	for (const line of lines) {
		let m;
		try { m = JSON.parse(line); } catch (e) { continue; }
		if (m.isSidechain || m.isMeta) continue;
		const msg = m.message || {};
		if (m.type === 'user') {
			if (typeof msg.content === 'string') {
				const t = cleanUser(msg.content);
				if (t) userBubble(t, []);
				continue;
			}
			if (!Array.isArray(msg.content)) continue;
			const texts = [], imgs = [];
			for (const c of msg.content) {
				if (c.type === 'tool_result') toolDone(c.tool_use_id, c.content, c.is_error);
				else if (c.type === 'text') { const t = cleanUser(c.text); if (t) texts.push(t); }
				else if (c.type === 'image' && c.source && c.source.data) imgs.push({ type: c.source.media_type, data: c.source.data });
			}
			if (texts.length || imgs.length) userBubble(texts.join('\n'), imgs);
		} else if (m.type === 'assistant') {
			for (const c of (Array.isArray(msg.content) ? msg.content : [])) {
				if (c.type === 'text' && c.text) { const b = textBlock(); b._src = c.text; b.innerHTML = MD.render(c.text); }
				else if (c.type === 'tool_use') { const card = toolCard(c.id, c.name); card.classList.remove('running'); setInput(card, c.input); }
			}
		}
	}
	for (const [, c] of S.tools) if (c.classList.contains('running')) { c.classList.remove('running'); headline(c); }
	if (lines.length) notice('info', 'Picked up where you left off', 'Your next message continues this conversation.');
}

function cleanUser(t) {
	t = String(t || '').trim();
	if (!t || t.startsWith('<') || t.startsWith('Caveat:')) {
		const cmd = /<command-name>([^<]*)<\/command-name>/.exec(t);
		return cmd ? cmd[1].trim() : '';
	}
	if (t.startsWith('[Request interrupted')) return '';
	return t;
}

// --- Composer --------------------------------------------------------------------------------------

function autosize() {
	const t = $('input');
	t.style.height = 'auto';
	t.style.height = Math.min(t.scrollHeight, Math.round(innerHeight * 0.4)) + 'px';
	drawSend();
}

$('input').addEventListener('input', autosize);
$('input').addEventListener('keydown', e => {
	if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
		e.preventDefault();
		submit();
	}
});
$('input').addEventListener('paste', e => {
	const files = [];
	for (const it of (e.clipboardData && e.clipboardData.items) || []) if (it.kind === 'file' && /^image\//.test(it.type)) files.push(it.getAsFile());
	if (files.length) { e.preventDefault(); addFiles(files); }
});
document.addEventListener('dragover', e => { if (e.dataTransfer && Array.from(e.dataTransfer.types).includes('Files')) { e.preventDefault(); body.classList.add('dropping'); } });
document.addEventListener('dragleave', e => { if (!e.relatedTarget) body.classList.remove('dropping'); });
document.addEventListener('drop', e => {
	body.classList.remove('dropping');
	if (!e.dataTransfer || !e.dataTransfer.files.length) return;
	e.preventDefault();
	addFiles(e.dataTransfer.files);
});

function addFiles(list) {
	for (const f of Array.from(list || [])) {
		if (!/^image\/(png|jpeg|gif|webp)$/.test(f.type)) { toast('Only images can be added for now'); continue; }
		if (f.size > 5 * 1024 * 1024) { toast(f.name + ' is over 5 MB'); continue; }
		const r = new FileReader();
		r.onload = () => {
			S.attachments.push({ type: f.type, data: String(r.result).split(',')[1], name: f.name });
			drawAttach();
		};
		r.readAsDataURL(f);
	}
}

function drawAttach() {
	const box = $('attach');
	box.innerHTML = '';
	S.attachments.forEach((a, i) => {
		const t = el('div', 'att');
		t.appendChild(Object.assign(document.createElement('img'), { src: 'data:' + a.type + ';base64,' + a.data }));
		const x = el('button', 'att-x', icon('close', 11));
		x.onclick = () => { S.attachments.splice(i, 1); drawAttach(); };
		t.appendChild(x);
		box.appendChild(t);
	});
	box.hidden = !S.attachments.length;
	drawSend();
}

// --- Home: a fresh conversation ---------------------------------------------------------------------

const STARTERS = [
	{ icon: 'book', title: 'Explain this project', text: 'Give me a tour of this project: what it does, how it\'s laid out, and where the important parts are.' },
	{ icon: 'bug', title: 'Find and fix a bug', text: 'Something\'s broken: ' },
	{ icon: 'flask', title: 'Write some tests', text: 'Look at what\'s tested in this project and add tests for the most important untested code.' },
	{ icon: 'review', title: 'Review my changes', text: 'Review my uncommitted changes (git diff) and tell me about anything risky or wrong.' },
];

function drawHome() {
	const box = $('home-cards');
	box.innerHTML = '';
	for (const s of STARTERS) {
		const b = el('button', 'starter', icon(s.icon, 16) + '<span>' + esc(s.title) + '</span>');
		b.onclick = () => {
			$('input').value = s.text;
			autosize();
			$('input').focus();
			$('input').setSelectionRange(s.text.length, s.text.length);
		};
		box.appendChild(b);
	}
	const h = new Date().getHours();
	$('home-hi').textContent = h < 5 ? 'Up late? What are we building?' : h < 12 ? 'Morning. What are we working on?' : h < 18 ? 'What are we working on?' : 'Evening. What are we building?';
}

function drawSetup() {
	const box = $('setup');
	if (S.claude) { box.hidden = true; body.classList.remove('no-claude'); return; }
	body.classList.add('no-claude');
	box.hidden = false;
	box.innerHTML = '<div class="setup-card">' + icon('terminal', 18) + '<div><b>Claude Code isn\'t installed yet</b>' +
		'<span>This app runs the Claude Code on your PC, signed in with your Claude account. Install it once (it takes a minute), sign in, and you\'re set.</span>' +
		'<div class="n-actions"><button class="btn primary small" id="setup-install">Install Claude Code</button><button class="btn small" id="setup-check">Check again</button><button class="btn small" id="setup-pick">Find it myself…</button></div>' +
		'<small>Looked on your PATH, in ~/.local/bin, npm, pnpm, bun, scoop and the Claude desktop app\'s own copy.</small></div></div>';
	$('setup-install').onclick = () => send('terminal', { cwd: S.home, args: 'install' });
	$('setup-check').onclick = async () => {
		const r = await ask('findClaude');
		S.claude = r.claude || '';
		drawSetup();
		toast(S.claude ? 'Found Claude Code' : 'Still can\'t find it. Finish the install, then try again.');
	};
	$('setup-pick').onclick = async () => {
		const r = await ask('pickClaude');
		S.claude = r.claude || '';
		drawSetup();
		if (S.claude) toast('Found Claude Code');
	};
}

async function recheck() {
	const r = await ask('findClaude');
	if (!r.claude || S.claude) return;
	S.claude = r.claude;
	drawSetup();
	toast('Found Claude Code');
}

function openTerminal() {
	if (!S.claude) { drawSetup(); return; }
	// One conversation, one place: the terminal takes it over from here.
	const args = S.session ? '--resume ' + S.session : '';
	if (S.proc && !S.running) stopProc();
	send('terminal', { cwd: S.cwd, args: args });
	if (S.session) toast('Continuing in the terminal');
}

// --- Keys --------------------------------------------------------------------------------------------

document.addEventListener('keydown', e => {
	const ctrl = e.ctrlKey || e.metaKey;
	if (!$('dialog').hidden) {
		if (e.key === 'Escape') { const b = $('dialog').querySelector('.btn:not(.primary)'); if (b) b.click(); }
		return;
	}
	if (!$('menu').hidden) {
		const items = Array.from($('menu').querySelectorAll('.item'));
		const at = items.indexOf(document.activeElement);
		if (e.key === 'Escape') { e.preventDefault(); closeMenu(); $('input').focus(); }
		else if (e.key === 'ArrowDown') { e.preventDefault(); items[(at + 1) % items.length].focus(); }
		else if (e.key === 'ArrowUp') { e.preventDefault(); items[(at - 1 + items.length) % items.length].focus(); }
		return;
	}
	if (S.asks.length && document.activeElement && !document.activeElement.classList.contains('a-why')) {
		if (e.key === 'Enter' && !e.shiftKey && !composerText()) { e.preventDefault(); const p = $('ask').querySelector('.btn.primary'); if (p) p.click(); return; }
		if (e.key === 'Escape') { e.preventDefault(); answer(S.asks[0], 'deny'); return; }
	}
	if (e.key === 'Escape' && S.running) { e.preventDefault(); stop(); return; }
	if (e.key === 'Tab' && e.shiftKey) {
		e.preventDefault();
		const i = MODES.findIndex(m => m.id === prefs.mode);
		setMode(MODES[(i + 1) % MODES.length].id);
		toast(MODES.find(m => m.id === prefs.mode).name);
		return;
	}
	if (ctrl && !e.shiftKey && !e.altKey) {
		const k = e.key.toLowerCase();
		if (k === 'n') { e.preventDefault(); newChat(); }
		else if (k === 'b') { e.preventDefault(); setPrefs({ side: !prefs.side }); }
		else if (k === 'o') { e.preventDefault(); pickFolder(); }
		else if (k === 'w') { e.preventDefault(); send('cmd', { cmd: 'close' }); }
		else if (k === 'l') { e.preventDefault(); $('input').focus(); }
	}
	// Typing anywhere goes to the composer.
	if (!ctrl && !e.altKey && e.key.length === 1 && document.activeElement !== $('input') && !(document.activeElement && /INPUT|TEXTAREA/.test(document.activeElement.tagName))) $('input').focus();
});

// --- From the host -------------------------------------------------------------------------------------

function onHost(e) {
	const d = e.data;
	if (typeof d === 'string') {
		if (d[0] !== 'c') return;
		let m;
		try { m = JSON.parse(d.slice(1)); } catch (x) { return; }
		onClaude(m);
		return;
	}
	if (!d || !d.t) return;
	switch (d.t) {
		case 'reply': {
			const f = waiting.get(d.rid);
			if (f) { waiting.delete(d.rid); f(d); }
			break;
		}
		case 'init': init(d); break;
		case 'recents':
			S.recents = d.list || [];
			drawRecents();
			break;
		case 'exit': onExit(d); break;
		case 'open': if (d.cwd) newChat(d.cwd); break;
		case 'toast': toast(d.text); break;
		case 'win':
			body.classList.toggle('maximized', d.max);
			$('win-max').innerHTML = icon(d.max ? 'restore' : 'max', 13);
			$('win-max').title = d.max ? 'Restore' : 'Maximise';
			break;
		case 'active':
			body.classList.toggle('inactive', !d.on);
			// Back from installing it in the terminal: look again.
			if (d.on && !S.claude && S.home) recheck();
			break;
		case 'confirmClose':
			dialog('Claude is still working', 'Closing now stops this reply. Your conversation is saved either way.', [{ label: 'Keep working' }, { label: 'Close', primary: true, danger: true }])
				.then(i => { if (i === 1) send('cmd', { cmd: 'forceClose' }); });
			break;
		case 'test': selftest(d); break;
	}
}

function init(m) {
	S.nativeDrag = !!m.nativeDrag;
	S.selftest = !!m.selftest;
	S.home = m.home || '';
	S.claude = m.claude || '';
	S.terminal = !!m.terminal;
	body.classList.toggle('solid', m.glass === false);
	Object.assign(prefs, m.prefs || {});
	for (const k in DEFAULTS) if (typeof prefs[k] !== typeof DEFAULTS[k] || (Array.isArray(DEFAULTS[k]) && !Array.isArray(prefs[k]))) prefs[k] = DEFAULTS[k];
	if (!MODES.some(x => x.id === prefs.mode)) prefs.mode = 'default';
	setCwd(m.cwd || prefs.cwd || S.home);
	applyPrefs();
	autoSide();
	drawHome();
	drawSetup();
	showHome();
	drawSend();
	$('input').focus();
}

function selftest(m) {
	switch (m.action) {
		case 'send': $('input').value = m.text; autosize(); submit(); break;
		case 'allow': { const p = $('ask').querySelector('.btn.primary'); if (p) p.click(); break; }
		case 'expand': { const c = $('thread').querySelector('.tool:not(.has-todos) .t-head'); if (c) c.click(); break; }
		case 'menu': if (m.which === 'model') modelMenu($('model-btn')); break;
	}
}

drawSend();
if (wv) {
	wv.addEventListener('message', onHost);
	send('ready');
}
