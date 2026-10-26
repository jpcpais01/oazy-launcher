// Line icons shared by the browser's pages (24x24, drawn with currentColor).
const ICONS = {
	back: '<path d="M15 5l-7 7 7 7"/>',
	forward: '<path d="M9 5l7 7-7 7"/>',
	reload: '<path d="M20 12a8 8 0 1 1-2.34-5.66"/><path d="M20 4v5h-5"/>',
	stop: '<path d="M6 6l12 12M18 6L6 18"/>',
	plus: '<path d="M12 5v14M5 12h14"/>',
	close: '<path d="M7 7l10 10M17 7L7 17"/>',
	min: '<path d="M6 12h12"/>',
	max: '<rect x="6" y="6" width="12" height="12" rx="2.5"/>',
	restore: '<rect x="5" y="8" width="11" height="11" rx="2.5"/><path d="M9 5h7.5A2.5 2.5 0 0 1 19 7.5V15"/>',
	lock: '<rect x="5.5" y="10.5" width="13" height="9.5" rx="2.5"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>',
	warn: '<path d="M12 4l9 16H3z"/><path d="M12 10v4M12 17.2v.1"/>',
	globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5a13 13 0 0 1 0 17M12 3.5a13 13 0 0 0 0 17"/>',
	search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
	clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
	star: '<path d="M12 4l2.4 5 5.4.6-4 3.7 1.1 5.4L12 16l-4.9 2.7 1.1-5.4-4-3.7 5.4-.6z"/>',
	pin: '<path d="M9 4h6l-1 5 3 3v2H7v-2l3-3z"/><path d="M12 14v6"/>',
	download: '<path d="M12 4v11M7 10.5l5 5 5-5"/><path d="M5 19.5h14"/>',
	menu: '<circle cx="5.5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="18.5" cy="12" r="1.3"/>',
	tab: '<rect x="3.5" y="5" width="17" height="14" rx="3"/><path d="M3.5 9.5h17"/>',
	window: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M7 8h.1M10 8h.1"/>',
	history: '<path d="M4 12a8 8 0 1 0 2.4-5.7"/><path d="M4 5v4h4"/><path d="M12 8v4l3 2"/>',
	zoomIn: '<path d="M12 6v12M6 12h12"/>',
	zoomOut: '<path d="M6 12h12"/>',
	fullscreen: '<path d="M4 9V5.5A1.5 1.5 0 0 1 5.5 4H9M15 4h3.5A1.5 1.5 0 0 1 20 5.5V9M20 15v3.5a1.5 1.5 0 0 1-1.5 1.5H15M9 20H5.5A1.5 1.5 0 0 1 4 18.5V15"/>',
	find: '<circle cx="10.5" cy="10.5" r="5.5"/><path d="M15 15l5 5"/><path d="M8 10.5h5"/>',
	print: '<path d="M7 9V4h10v5"/><rect x="4" y="9" width="16" height="7" rx="2"/><path d="M7 14h10v6H7z"/>',
	trash: '<path d="M5 7h14M10 7V5h4v2M7 7l1 12h8l1-12"/>',
	code: '<path d="M9 8l-4 4 4 4M15 8l4 4-4 4"/>',
	folder: '<path d="M3.5 7.5A2 2 0 0 1 5.5 5.5H10l2 2h6.5a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>',
	pause: '<path d="M9 6v12M15 6v12"/>',
	play: '<path d="M8 5.5v13l10-6.5z"/>',
	retry: '<path d="M4 12a8 8 0 1 0 2.4-5.7"/><path d="M4 5v4h4"/>',
	file: '<path d="M7 3.5h7l4 4V19a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 6 19V5A1.5 1.5 0 0 1 7.5 3.5z"/><path d="M14 3.5V8h4"/>',
	check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
	speaker: '<path d="M4 9.5h3l4-3.5v12l-4-3.5H4z"/><path d="M15 9a4 4 0 0 1 0 6M17.5 6.5a7.5 7.5 0 0 1 0 11"/>',
	muted: '<path d="M4 9.5h3l4-3.5v12l-4-3.5H4z"/><path d="M15.5 9.5l5 5M20.5 9.5l-5 5"/>',
	sad: '<circle cx="12" cy="12" r="8.5"/><path d="M8.5 16c1.8-1.8 5.2-1.8 7 0M9 10h.1M15 10h.1"/>',
	duplicate: '<rect x="8" y="8" width="11.5" height="11.5" rx="2.5"/><path d="M5 15.5V6.5A2 2 0 0 1 7 4.5h8.5"/>',
	edit: '<path d="M5 19l1-4 9.5-9.5a2 2 0 0 1 3 3L9 18z"/>',
	unpin: '<path d="M9 4h6l-1 5 3 3v2H7v-2l3-3z"/><path d="M4 4l16 16"/>',
	sparkle: '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/>',
	external: '<path d="M14 4.5h5.5V10M19.5 4.5L11 13"/><path d="M18 14v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4"/>',
};

function icon(name, size) {
	const s = size || 16;
	return '<svg class="ic" width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || '') + '</svg>';
}

function esc(s) {
	return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// A soft colour for sites without an icon, stable per host.
function hostHue(host) {
	let h = 0;
	for (const c of String(host || '')) h = (h * 31 + c.charCodeAt(0)) >>> 0;
	return h % 360;
}

function bareHost(url) {
	try { return new URL(url).hostname.replace(/^www\./, ''); } catch (e) { return ''; }
}
