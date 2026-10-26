// Line icons for the terminal's chrome (24x24, drawn with currentColor).
const ICONS = {
	plus: '<path d="M12 5v14M5 12h14"/>',
	close: '<path d="M7 7l10 10M17 7L7 17"/>',
	min: '<path d="M6 12h12"/>',
	max: '<rect x="6" y="6" width="12" height="12" rx="2.5"/>',
	restore: '<rect x="5" y="8" width="11" height="11" rx="2.5"/><path d="M9 5h7.5A2.5 2.5 0 0 1 19 7.5V15"/>',
	chevron: '<path d="M7 10l5 5 5-5"/>',
	up: '<path d="M7 14l5-5 5 5"/>',
	down: '<path d="M7 10l5 5 5-5"/>',
	search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
	settings: '<circle cx="12" cy="12" r="3"/><path d="M12 3.5v2.2M12 18.3v2.2M20.5 12h-2.2M5.7 12H3.5M18 6l-1.6 1.6M7.6 16.4L6 18M18 18l-1.6-1.6M7.6 7.6L6 6"/>',
	copy: '<rect x="8" y="8" width="11.5" height="11.5" rx="2.5"/><path d="M5 15.5V6.5A2 2 0 0 1 7 4.5h8.5"/>',
	paste: '<path d="M9 4.5h6v3H9z"/><path d="M15 6h2a2 2 0 0 1 2 2v10.5a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h2"/>',
	splitRight: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M12 4.5v15"/>',
	splitDown: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M3.5 12h17"/>',
	clear: '<path d="M5 7h14M10 7V5h4v2M7 7l1 12h8l1-12"/>',
	window: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M7 8h.1M10 8h.1"/>',
	restart: '<path d="M4 12a8 8 0 1 0 2.4-5.7"/><path d="M4 5v4h4"/>',
	check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
	folder: '<path d="M3.5 7.5A2 2 0 0 1 5.5 5.5H10l2 2h6.5a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>',
	keyboard: '<rect x="3" y="6.5" width="18" height="11" rx="2.5"/><path d="M7 10h.1M10 10h.1M13 10h.1M16 10h.1M8 14h8"/>',
};

// Profile marks: a glyph on a small glass tile in the shell's own colours.
const PROFILE_LOOKS = {
	pwsh: { a: '#4f8ff0', b: '#1d3f8f', glyph: '<path d="M7 8l5 4-5 4M13 16.5h4.5"/>' },
	powershell: { a: '#3b6fc0', b: '#14295a', glyph: '<path d="M7 8l5 4-5 4M13 16.5h4.5"/>' },
	cmd: { a: '#6b7788', b: '#232a35', glyph: '<path d="M7 9l3 3-3 3M12 15h5"/>' },
	linux: { a: '#f39a52', b: '#b0441d', glyph: '<path d="M14.5 6.5h-3.2a2.3 2.3 0 0 0 0 4.6h1.4a2.3 2.3 0 0 1 0 4.6H9.5M12 4.8v1.7M12 15.7v1.8"/>' },
	git: { a: '#f2734f', b: '#a72e1a', glyph: '<circle cx="8.5" cy="7.5" r="1.6"/><circle cx="8.5" cy="16.5" r="1.6"/><circle cx="15.5" cy="10" r="1.6"/><path d="M8.5 9.1v5.8M15.5 11.6c0 2.4-2.5 3.1-5.6 3.9"/>' },
	claude: { a: '#f2a37c', b: '#b8532f', glyph: '<path d="M12 5v14M5.9 8.5l12.2 7M5.9 15.5l12.2-7"/>' },
};

function icon(name, size) {
	const s = size || 16;
	return '<svg class="ic" width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || '') + '</svg>';
}

function profileMark(kind, size) {
	const look = PROFILE_LOOKS[kind] || PROFILE_LOOKS.cmd;
	const s = size || 18;
	return '<span class="pmark" style="width:' + s + 'px;height:' + s + 'px;background:linear-gradient(150deg,' + look.a + ',' + look.b + ')">' +
		'<svg width="' + Math.round(s * 0.82) + '" height="' + Math.round(s * 0.82) + '" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round">' + look.glyph + '</svg></span>';
}

function esc(s) {
	return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
