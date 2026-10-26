'use strict';
// A web app's title bar. The native side (oazy_browser.cs) owns the window and
// the site's page; this draws the bar and sends back what you click.

const wv = window.chrome && window.chrome.webview;
const send = (t, o) => {
	const msg = Object.assign({ t }, o || {});
	if (wv) wv.postMessage(msg);
	else if (window.__mockHost) window.__mockHost(msg);
};
const $ = id => document.getElementById(id);
const body = document.body;
const S = { tabs: [], active: 0, nav: {}, look: true, lost: false };

$('mark').innerHTML = icon('sparkle', 13);
$('back').innerHTML = icon('back', 17);
$('reload').innerHTML = icon('reload', 16);
$('look').innerHTML = icon('sparkle', 17);
$('browser').innerHTML = icon('external', 16);
$('win-min').innerHTML = icon('min', 15);
$('win-max').innerHTML = icon('max', 13);
$('win-close').innerHTML = icon('close', 15);

if (wv) wv.addEventListener('message', e => onMessage(e.data));

function onMessage(m) {
	switch (m.t) {
		case 'init':
			body.classList.toggle('solid', !m.glass);
			setAccent(m.accent);
			$('name').textContent = m.app || '';
			document.title = m.app || document.title;
			S.look = m.look !== false;
			renderLook();
			break;
		case 'tabs': S.tabs = m.tabs; S.active = m.active; renderTabs(); break;
		case 'nav': S.nav = m; renderNav(); break;
		case 'look': S.look = !!m.on; S.lost = false; renderLook(); break;
		case 'appStatus': S.lost = !m.ok; renderLook(); break;
		case 'win':
			body.classList.toggle('maximized', !!m.max);
			$('win-max').innerHTML = icon(m.max ? 'restore' : 'max', 13);
			$('win-max').title = m.max ? 'Restore' : 'Maximise';
			break;
		case 'active': body.classList.toggle('inactive', !m.on); break;
		case 'dlDone': chip('Saved ' + m.name + ' to Downloads', () => send('cmd', { cmd: 'downloadsFolder' })); break;
		case 'toast': chip(m.text); break;
	}
}

function setAccent(hex) {
	const m = /^#?([0-9a-f]{6})$/i.exec(hex || '');
	if (!m) return;
	const n = parseInt(m[1], 16);
	document.documentElement.style.setProperty('--accent', '#' + m[1]);
	document.documentElement.style.setProperty('--accent-rgb', (n >> 16) + ', ' + ((n >> 8) & 255) + ', ' + (n & 255));
}

function renderNav() {
	const n = S.nav;
	$('back').disabled = !n.back;
	$('reload').innerHTML = icon(n.loading ? 'stop' : 'reload', n.loading ? 15 : 16);
	$('reload').title = n.loading ? 'Stop' : 'Reload (Ctrl+R)';
	$('progress').classList.toggle('on', !!n.loading);
}

function renderLook() {
	const b = $('look');
	b.classList.toggle('on', S.look && !S.lost);
	b.classList.toggle('lost', S.look && S.lost);
	b.title = !S.look ? 'Oazy look is off: showing the site as it is (Ctrl+Shift+O)'
		: S.lost ? 'Oazy look couldn’t find its way around this page, so most of it shows as it is (Ctrl+Shift+O)'
		: 'Oazy look is on (Ctrl+Shift+O)';
}

function renderTabs() {
	const box = $('tabs');
	box.innerHTML = '';
	if (S.tabs.length < 2) return;
	for (const t of S.tabs) {
		const el = document.createElement('div');
		el.className = 'pill' + (t.id === S.active ? ' active' : '');
		el.innerHTML = '<span>' + esc(t.title || bareHost(t.url)) + '</span>' + (t.id === S.tabs[0].id ? '' : '<b class="x">' + icon('close', 12) + '</b>');
		el.onclick = e => {
			if (e.target.closest('.x')) send('closeTab', { id: t.id });
			else send('activate', { id: t.id });
		};
		box.appendChild(el);
	}
}

function chip(text, onClick) {
	const c = $('chip');
	c.textContent = text;
	c.classList.toggle('link', !!onClick);
	c.onclick = onClick || null;
	c.classList.add('show');
	clearTimeout(chip.t);
	chip.t = setTimeout(() => c.classList.remove('show'), 3200);
}

$('back').onclick = () => send('cmd', { cmd: 'back' });
$('reload').onclick = e => send('cmd', { cmd: S.nav.loading ? 'stop' : (e.shiftKey || e.ctrlKey ? 'hardReload' : 'reload') });
$('look').onclick = () => send('look', { on: !S.look });
$('browser').onclick = () => send('openInBrowser');
$('win-min').onclick = () => send('cmd', { cmd: 'minimize' });
$('win-max').onclick = () => send('cmd', { cmd: 'maximize' });
$('win-close').onclick = () => send('cmd', { cmd: 'close' });

// Where the runtime supports app-region these never fire (Windows drags the
// window itself); older runtimes get the same behaviour from here.
for (const el of [$('bar'), $('drag'), $('name'), $('mark')]) {
	el.addEventListener('mousedown', e => {
		if (e.button !== 0 || e.target !== el || e.detail > 1) return;
		send('drag');
	});
	el.addEventListener('dblclick', e => { if (e.target === el) send('cmd', { cmd: 'maximize' }); });
}

send('ready');
