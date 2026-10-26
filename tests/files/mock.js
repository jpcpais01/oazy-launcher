// A pretend Oazy Files host with a small pretend disk, for looking at the page
// in a plain browser (tests/files/shot.js). Never shipped.
(function () {
	const listeners = [];
	const emit = data => setTimeout(() => listeners.forEach(f => f({ data: data })), 0);
	const now = Date.now(), H = 3600000, D = 24 * H;
	const home = 'C:\\Users\\joao';
	// path -> {dir, size, mtime, attrs, kids}
	const fs = new Map();
	let t = 0;
	function add(path, size, ago, attrs) {
		const dir = size == null;
		fs.set(path.toLowerCase(), { path: path, dir: dir, size: dir ? -1 : size, mtime: now - (ago != null ? ago : (t += 7) * H), ctime: now - 400 * D, attrs: (attrs || 0) | (dir ? 16 : 32), kids: dir ? new Set() : null });
		const i = path.lastIndexOf('\\');
		let parent = path.slice(0, i);
		if (/^[A-Z]:$/.test(parent)) parent += '\\';
		const p = fs.get(parent.toLowerCase());
		if (p && path.length > 3) p.kids.add(path.toLowerCase());
	}
	add('C:\\'); add('D:\\');
	add('C:\\Users'); add('C:\\Windows'); add('C:\\Program Files'); add('C:\\Program Files (x86)'); add('C:\\ProgramData', null, 30 * D, 2);
	add('C:\\pagefile.sys', 17179869184, 2 * H, 6);
	add(home);
	for (const f of ['Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos', 'oazy-launcher', 'Games', 'OneDrive', 'Saved Games']) add(home + '\\' + f);
	add(home + '\\AppData', null, 2 * D, 2);
	add(home + '\\.gitconfig', 312, 40 * D, 0);
	add(home + '\\NTUSER.DAT', 3145728, 1 * H, 6);
	const dl = home + '\\Downloads';
	add(dl + '\\Godot_v4.5.1-stable_win64.exe.zip', 62_914_560, 3 * H);
	add(dl + '\\SteamSetup.exe', 2_398_112, 26 * H);
	add(dl + '\\invoice-october.pdf', 184_320, 50 * H);
	add(dl + '\\lagoon-wallpaper-5k.jpg', 6_815_744, 1 * H);
	add(dl + '\\screenshot 2026-10-25 214455.png', 1_310_720, 20 * H);
	add(dl + '\\trip to Madeira.mp4', 734_003_200, 9 * D);
	add(dl + '\\Discord Setup.exe', 98_566_144, 12 * D);
	add(dl + '\\notes for the launcher.txt', 4_096, 2 * D);
	add(dl + '\\soundtrack.flac', 41_943_040, 30 * D);
	add(dl + '\\fonts');
	add(dl + '\\fonts\\Inter.ttf', 803_000, 40 * D);
	add(dl + '\\project-brief.docx', 92_160, 4 * D);
	add(dl + '\\budget 2026.xlsx', 38_912, 6 * D);
	add(dl + '\\old installers');
	add(dl + '\\VSCodeUserSetup-x64.exe', 98_000_000, 15 * D);
	add(dl + '\\data-export.json', 1_048_576, 18 * D);
	add(dl + '\\desktop.ini', 282, 300 * D, 6);
	const pics = home + '\\Pictures';
	add(pics + '\\Screenshots'); add(pics + '\\Camera Roll'); add(pics + '\\Wallpapers');
	for (let i = 1; i <= 14; i++) add(pics + '\\IMG_20' + (2500 + i * 37) + '.jpg', 3_000_000 + i * 140_000, i * 9 * H);
	add(pics + '\\sunset over the lagoon.png', 5_200_000, 5 * D);
	const repo = home + '\\oazy-launcher';
	for (const f of ['.github', 'assets', 'native', 'scripts', 'shaders', 'tests', 'tools']) add(repo + '\\' + f);
	add(repo + '\\.git', null, 1 * H, 2);
	add(repo + '\\project.godot', 1_830, 3 * H);
	add(repo + '\\README.md', 6_120, 30 * H);
	add(repo + '\\VERSION', 4, 9 * D);
	add(repo + '\\export_presets.cfg', 1_204, 3 * D);
	add(repo + '\\scripts\\shell'); add(repo + '\\scripts\\autoload');
	add(repo + '\\scripts\\autoload\\files.gd', 5_400, 2 * H);
	add(repo + '\\scripts\\shell\\desktop.gd', 26_000, 5 * H);
	add(home + '\\Documents\\Readme for the files app.md', 2_200, 3 * H);
	add(home + '\\Documents\\Taxes'); add(home + '\\Documents\\Recipes');
	add(home + '\\Documents\\CV 2026.pdf', 220_000, 70 * D);
	add(home + '\\Music\\Playlists');
	add(home + '\\Games\\Hollow Knight'); add(home + '\\Games\\Celeste');
	add('D:\\Games'); add('D:\\Backups'); add('D:\\SteamLibrary'); add('D:\\Movies');
	add('D:\\Backups\\photos-2025.zip', 8_589_934_592, 200 * D);

	function row(e, withParent) {
		const name = e.path.slice(e.path.lastIndexOf('\\') + 1) || e.path;
		const r = [name, e.dir ? 1 : 0, e.size, e.mtime, e.ctime, e.attrs];
		if (withParent) { let p = e.path.slice(0, e.path.lastIndexOf('\\')); if (/^[A-Z]:$/.test(p)) p += '\\'; r.push(p); }
		return r;
	}
	function norm(p) {
		p = String(p || '').replace(/\//g, '\\').replace(/%USERPROFILE%/ig, home);
		if (/^[a-z]:$/i.test(p)) p += '\\';
		if (p.length > 3) p = p.replace(/\\+$/, '');
		return p.charAt(0).toUpperCase() + p.slice(1);
	}
	const types = { '.zip': 'Compressed (zipped) Folder', '.exe': 'Application', '.pdf': 'Microsoft Edge PDF Document', '.jpg': 'JPG File', '.png': 'PNG File', '.mp4': 'MP4 Video', '.txt': 'Text Document', '.flac': 'FLAC Audio', '.docx': 'Microsoft Word Document', '.xlsx': 'Microsoft Excel Worksheet', '.json': 'JSON Source File', '.md': 'Markdown Source File', '.gd': 'GDScript File', '.ttf': 'TrueType font file', '.godot': 'GODOT File', '.cfg': 'CFG File', '.ini': 'Configuration settings', '.sys': 'System file', '.dat': 'DAT File' };
	function reply(m, body) { emit(Object.assign({ t: 'reply', rid: m.rid }, body)); }
	const clip = { paths: [], cut: false };
	function remove(key) {
		const e = fs.get(key);
		if (!e) return;
		if (e.kids) for (const k of [...e.kids]) remove(k);
		fs.delete(key);
		for (const v of fs.values()) if (v.kids) v.kids.delete(key);
	}
	window.__oazyFs = fs;
	window.__oazyMock = {
		addEventListener: (t, f) => listeners.push(f),
		postMessage: m => {
			switch (m.t) {
				case 'ready':
					emit({ t: 'init', glass: true, accent: '#38d6c4', nativeDrag: true, prefs: window.__oazyPrefs || {}, tabs: window.__oazyTabs || [], selftest: false });
					emit({ t: 'win', max: false });
					emit({ t: 'active', on: true });
					break;
				case 'places':
					reply(m, {
						home: home, user: 'joao', system: 'C:\\',
						quick: [['joao', home, 'home'], ['Desktop', home + '\\Desktop', 'desktop'], ['Downloads', dl, 'downloads'], ['Documents', home + '\\Documents', 'documents'], ['Pictures', pics, 'pictures'], ['Music', home + '\\Music', 'music'], ['Videos', home + '\\Videos', 'videos']].map(q => ({ name: q[0], path: q[1], kind: q[2] })),
						drives: [
							{ path: 'C:\\', letter: 'C:', type: 'fixed', name: '', total: 999_653_638_144, free: 412_316_860_416 },
							{ path: 'D:\\', letter: 'D:', type: 'fixed', name: 'Games', total: 2_000_381_014_016, free: 160_000_000_000 },
							{ path: 'E:\\', letter: 'E:', type: 'usb', name: 'SANDISK', total: 64_000_000_000, free: 51_000_000_000 },
						],
					});
					break;
				case 'list': {
					const p = norm(m.path);
					const e = fs.get(p.toLowerCase());
					if (!e) { reply(m, { path: p, error: 'missing' }); break; }
					if (!e.dir) { reply(m, { path: e.path, file: true }); break; }
					const items = [...e.kids].map(k => row(fs.get(k)));
					const tmap = {};
					for (const it of items) { const d = it[0].lastIndexOf('.'); if (!it[1] && d > 0) { const x = it[0].slice(d).toLowerCase(); if (types[x]) tmap[x] = types[x]; } }
					const drive = e.path[0] === 'D' ? [160_000_000_000, 2_000_381_014_016] : [412_316_860_416, 999_653_638_144];
					setTimeout(() => reply(m, { path: e.path, items: items, types: tmap, free: drive[0], total: drive[1] }), 30);
					break;
				}
				case 'recent': {
					const pick = [dl + '\\notes for the launcher.txt', repo + '\\project.godot', dl + '\\invoice-october.pdf', pics + '\\IMG_202537.jpg', home + '\\Documents\\CV 2026.pdf', dl + '\\budget 2026.xlsx', repo + '\\README.md'];
					reply(m, { items: pick.filter(p => fs.has(p.toLowerCase())).map((p, i) => { const r = row(fs.get(p.toLowerCase()), true); r.push(now - (i * 5 + 1) * H); return r; }) });
					break;
				}
				case 'preview': {
					const e = fs.get(norm(m.path).toLowerCase());
					if (!e) { reply(m, { error: 'missing' }); break; }
					if (e.dir) { let f = 0, d = 0; for (const k of e.kids) fs.get(k).dir ? d++ : f++; reply(m, { files: f, dirs: d }); break; }
					if (/\.(txt|md|gd|json|cfg|godot)$/i.test(e.path)) reply(m, { text: '# Oazy Files\n\nYour folders, in Oazy\'s glass.\n\n- Tabs, a sidebar with your places and drives\n- Icons and details views, thumbnails\n- Search everything under a folder\n- Copy, move, rename, delete (to the Recycle Bin)\n' });
					else if (/\.(jpg|png)$/i.test(e.path)) reply(m, { w: 4032, h: 3024 });
					else reply(m, {});
					break;
				}
				case 'search': {
					const root = norm(m.root).toLowerCase();
					const q = m.q.toLowerCase();
					const found = [];
					for (const e of fs.values()) {
						const name = e.path.slice(e.path.lastIndexOf('\\') + 1).toLowerCase();
						if (e.path.toLowerCase().startsWith(root + (root.endsWith('\\') ? '' : '\\')) && name.includes(q) && (m.hidden || !(e.attrs & 2))) found.push(row(e, true));
					}
					setTimeout(() => emit({ t: 'found', sid: m.sid, items: found.slice(0, 3), folders: 40, done: false }), 60);
					setTimeout(() => emit({ t: 'found', sid: m.sid, items: found.slice(3), folders: 212, done: true }), 260);
					break;
				}
				case 'rename': {
					const e = fs.get(m.path.toLowerCase());
					const parent = m.path.slice(0, m.path.lastIndexOf('\\'));
					const np = parent + '\\' + m.name;
					remove(m.path.toLowerCase());
					add(np, e.dir ? null : e.size, 0);
					reply(m, { ok: true, path: np });
					break;
				}
				case 'mkdir': case 'newfile': {
					let p = m.dir + '\\' + m.name, i = 2;
					const dot = m.name.lastIndexOf('.');
					while (fs.has(p.toLowerCase())) p = m.dir + '\\' + (m.t === 'mkdir' || dot < 0 ? m.name + ' (' + i++ + ')' : m.name.slice(0, dot) + ' (' + i++ + ')' + m.name.slice(dot));
					add(p, m.t === 'mkdir' ? null : 0, 0);
					reply(m, { ok: true, path: p, name: p.slice(p.lastIndexOf('\\') + 1) });
					break;
				}
				case 'delete':
					for (const p of m.paths) remove(p.toLowerCase());
					setTimeout(() => reply(m, { ok: true }), 120);
					break;
				case 'transfer': case 'paste': {
					const paths = m.t === 'paste' ? clip.paths : m.paths;
					const move = m.t === 'paste' ? clip.cut : m.move;
					if (!paths.length) { reply(m, { ok: false, empty: true }); break; }
					for (const p of paths) {
						const e = fs.get(p.toLowerCase());
						if (!e) continue;
						const name = p.slice(p.lastIndexOf('\\') + 1);
						if (move) remove(p.toLowerCase());
						add(m.dest + '\\' + name, e.dir ? null : e.size, 0);
					}
					setTimeout(() => reply(m, { ok: true }), 300);
					break;
				}
				case 'clipSet': clip.paths = m.paths; clip.cut = m.cut; break;
				case 'open': {
					const e = fs.get((m.paths[0] || '').toLowerCase());
					if (e && e.dir) reply(m, { navigate: e.path });
					else reply(m, { ok: true });
					break;
				}
				case 'compress': case 'extract': reply(m, { ok: true, path: m.path || m.paths[0] }); break;
				case 'title': document.title = m.text + ' - Oazy Files'; break;
			}
		},
	};
})();
