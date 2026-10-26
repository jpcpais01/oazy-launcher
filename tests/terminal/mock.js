// A pretend Oazy Terminal host for looking at the page in a plain browser
// (tests/terminal/shot.js). Never shipped.
(function () {
	const listeners = [];
	const emit = data => setTimeout(() => listeners.forEach(f => f({ data: data })), 0);
	const lines = {};
	const E = '\x1b[';
	function banner(id, profile) {
		let s = '';
		if (profile === 'cmd') s += 'Microsoft Windows [Version 10.0.26100.2314]\r\n(c) Microsoft Corporation. All rights reserved.\r\n\r\n';
		else s += 'PowerShell 7.5.0\r\n\r\n';
		return s + prompt(profile);
	}
	function prompt(profile) {
		return profile === 'cmd' ? 'C:\\Users\\joao>' : E + '38;2;56;214;196mPS ' + E + '0mC:\\Users\\joao' + E + '38;2;56;214;196m>' + E + '0m ';
	}
	function demo() {
		let s = '\r\n' + E + '1mOazy Terminal' + E + '0m  ' + E + '2mtruecolor · unicode · mouse' + E + '0m\r\n\r\n';
		for (let i = 0; i < 72; i++) s += E + '48;2;' + Math.round(20 + i * 3) + ';' + Math.round(200 - i * 2) + ';' + Math.round(190 + i * 0.9) + 'm ';
		s += E + '0m\r\n\r\n';
		const names = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white'];
		for (let i = 0; i < 8; i++) s += E + (30 + i) + 'm' + names[i].padEnd(9) + E + '0m';
		s += '\r\n';
		for (let i = 0; i < 8; i++) s += E + (90 + i) + 'm' + names[i].padEnd(9) + E + '0m';
		s += '\r\n\r\n  ╭──────────────────────────────╮\r\n  │ ✓ build passed   🌴 ünïcødé  │\r\n  ╰──────────────────────────────╯\r\n\r\n';
		s += E + '38;2;242;163;124m✻ ' + E + '0m' + E + '1mWelcome to Claude Code!' + E + '0m\r\n\r\n';
		s += '  ' + E + '2m/help for help, /status for your current setup' + E + '0m\r\n\r\n';
		s += '  ' + E + '2mcwd: C:\\Users\\joao\\oazy-launcher' + E + '0m\r\n';
		return s;
	}
	const profiles = {};
	window.__oazyMock = {
		addEventListener: (t, f) => listeners.push(f),
		postMessage: m => {
			if (typeof m === 'string') {
				if (m[0] !== 'i') return;
				const c = m.indexOf(':');
				const id = +m.slice(1, c), d = m.slice(c + 1);
				if (d === '\r') {
					const cmd = (lines[id] || '').trim();
					lines[id] = '';
					emit('o' + id + ':\r\n' + (cmd === 'demo' ? demo() : '') + prompt(profiles[id]));
				} else if (d === '\x7f') {
					if (lines[id]) { lines[id] = lines[id].slice(0, -1); emit('o' + id + ':\b \b'); }
				} else { lines[id] = (lines[id] || '') + d; emit('o' + id + ':' + d); }
				return;
			}
			if (m.t === 'ready') {
				emit({ t: 'init', glass: true, accent: '#38d6c4', nativeDrag: true, build: 26100, selftest: false, defaultProfile: 'pwsh', prefs: {}, tabs: [],
					profiles: [
						{ id: 'pwsh', name: 'PowerShell', icon: 'pwsh' },
						{ id: 'powershell', name: 'Windows PowerShell', icon: 'powershell' },
						{ id: 'cmd', name: 'Command Prompt', icon: 'cmd' },
						{ id: 'wsl:Ubuntu', name: 'Ubuntu', icon: 'linux' },
						{ id: 'gitbash', name: 'Git Bash', icon: 'git' },
						{ id: 'claude', name: 'Claude Code', icon: 'claude' },
					] });
				emit({ t: 'win', max: false });
				emit({ t: 'active', on: true });
			} else if (m.t === 'spawn') {
				profiles[m.id] = m.profile;
				emit({ t: 'started', id: m.id, pid: 100 + m.id });
				emit('o' + m.id + ':' + banner(m.id, m.profile));
			}
		},
	};
})();
