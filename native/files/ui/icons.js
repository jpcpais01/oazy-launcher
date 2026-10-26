// Line icons for Oazy Files' chrome (24x24, drawn with currentColor), and the
// folder, drive and document art (64x64, gradients from files.html).
const ICONS = {
	plus: '<path d="M12 5v14M5 12h14"/>',
	close: '<path d="M7 7l10 10M17 7L7 17"/>',
	min: '<path d="M6 12h12"/>',
	max: '<rect x="6" y="6" width="12" height="12" rx="2.5"/>',
	restore: '<rect x="5" y="8" width="11" height="11" rx="2.5"/><path d="M9 5h7.5A2.5 2.5 0 0 1 19 7.5V15"/>',
	back: '<path d="M19 12H5M11 6l-6 6 6 6"/>',
	fwd: '<path d="M5 12h14M13 6l6 6-6 6"/>',
	up: '<path d="M12 19V5M6 11l6-6 6 6"/>',
	reload: '<path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3"/><path d="M19.5 4.5v4h-4"/>',
	chevron: '<path d="M10 7l5 5-5 5"/>',
	down: '<path d="M7 10l5 5 5-5"/>',
	search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
	settings: '<circle cx="12" cy="12" r="3"/><path d="M12 3.5v2.2M12 18.3v2.2M20.5 12h-2.2M5.7 12H3.5M18 6l-1.6 1.6M7.6 16.4L6 18M18 18l-1.6-1.6M7.6 7.6L6 6"/>',
	grid: '<rect x="4" y="4" width="7" height="7" rx="2"/><rect x="13" y="4" width="7" height="7" rx="2"/><rect x="4" y="13" width="7" height="7" rx="2"/><rect x="13" y="13" width="7" height="7" rx="2"/>',
	list: '<path d="M9 6.5h11M9 12h11M9 17.5h11"/><path d="M4.5 6.5h.1M4.5 12h.1M4.5 17.5h.1"/>',
	sort: '<path d="M7 5v14M4 16l3 3 3-3"/><path d="M13 7h7M13 12h5M13 17h3"/>',
	panel: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M14.5 4.5v15"/>',
	open: '<path d="M14 4.5h5.5V10M19.5 4.5L11 13"/><path d="M18 14v3.5a2 2 0 0 1-2 2H6.5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2H10"/>',
	tab: '<rect x="3.5" y="6.5" width="17" height="13" rx="2.5"/><path d="M3.5 10h17M8.5 6.5V4.5h7v2"/>',
	window: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M3.5 9h17"/>',
	cut: '<circle cx="6.5" cy="17" r="2.5"/><circle cx="17.5" cy="17" r="2.5"/><path d="M8.5 15.5L17 4.5M15.5 15.5L7 4.5"/>',
	copy: '<rect x="8" y="8" width="11.5" height="11.5" rx="2.5"/><path d="M5 15.5V6.5A2 2 0 0 1 7 4.5h8.5"/>',
	paste: '<path d="M9 4.5h6v3H9z"/><path d="M15 6h2a2 2 0 0 1 2 2v10.5a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h2"/>',
	rename: '<path d="M4 20h4L18.5 9.5a2.1 2.1 0 0 0-3-3L5 17v3z"/><path d="M13.5 8.5l3 3"/>',
	trash: '<path d="M4.5 7h15M10 7V5h4v2M6.5 7l1 12.5h9l1-12.5"/><path d="M10 11v5M14 11v5"/>',
	path: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
	pin: '<path d="M9 4.5h6l-1 5 3.5 3.5h-11L10 9.5z"/><path d="M12 13v6.5"/>',
	unpin: '<path d="M9 4.5h6l-1 5 3.5 3.5h-11L10 9.5z"/><path d="M12 13v6.5M4 4l16 16"/>',
	terminal: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M7.5 9.5l3 2.5-3 2.5M12.5 15h4"/>',
	info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8h.1"/>',
	zip: '<path d="M6.5 3.5h8l4 4v12a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-15a1 1 0 0 1 1-1z"/><path d="M11 3.5v2M11 7.5v2M11 11.5v2M10 15.5h2v2h-2z"/>',
	extract: '<path d="M12 4v10M8 10.5l4 4 4-4"/><path d="M5 15.5v2.5a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-2.5"/>',
	folderPlus: '<path d="M3.5 7.5A2 2 0 0 1 5.5 5.5H10l2 2h6.5a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/><path d="M12 10.5v5M9.5 13h5"/>',
	filePlus: '<path d="M6.5 3.5h7l4.5 4.5v11.5a1 1 0 0 1-1 1H6.5a1 1 0 0 1-1-1V4.5a1 1 0 0 1 1-1z"/><path d="M13.5 3.5V8H18M12 11.5v5M9.5 14h5"/>',
	check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
	dot: '<circle cx="12" cy="12" r="3" fill="currentColor"/>',
	home: '<path d="M4 11l8-6.5 8 6.5"/><path d="M6 9.5V19a1 1 0 0 0 1 1h3.5v-5.5h3V20H17a1 1 0 0 0 1-1V9.5"/>',
	recycle: '<path d="M5.5 7h13M10 7V5h4v2M7 7l1 12.5h8L17 7"/><path d="M10.2 14.6l1.8-3 1.8 3h-3.6z"/>',
	external: '<path d="M14 4.5h5.5V10M19.5 4.5L12 12"/><path d="M18 14v3.5a2 2 0 0 1-2 2H6.5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2H10"/>',
	shield: '<path d="M12 3.5l7 2.8v5.2c0 4.4-3 7.6-7 9-4-1.4-7-4.6-7-9V6.3z"/>',
	eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
	keyboard: '<rect x="3" y="6.5" width="18" height="11" rx="2.5"/><path d="M7 10h.1M10 10h.1M13 10h.1M16 10h.1M8 14h8"/>',
	clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
	drive: '<rect x="3.5" y="12" width="17" height="7" rx="2"/><path d="M5.5 12l2-6.5h9l2 6.5M16.5 15.5h.1"/>',
	star: '<path d="M12 4.5l2.3 4.7 5.2.8-3.8 3.6.9 5.2L12 16.4l-4.6 2.4.9-5.2-3.8-3.6 5.2-.8z"/>',
};

// White glyphs drawn on the front of a special folder.
const FOLDER_GLYPHS = {
	home: '<path d="M25 37l7-5.5 7 5.5"/><path d="M27 35.5V43h3.5v-4h3v4H37v-7.5"/>',
	desktop: '<rect x="24" y="31" width="16" height="10" rx="1.5"/><path d="M29 44.5h6M32 41v3.5"/>',
	downloads: '<path d="M32 30v11M27.5 37l4.5 4.5 4.5-4.5M26 45h12"/>',
	documents: '<path d="M27 30.5h7l4 4v11h-11z"/><path d="M30 37.5h5M30 41h5"/>',
	pictures: '<rect x="24.5" y="31" width="15" height="12" rx="2"/><path d="M25 41l4.5-4.5 3.5 3.5 2-2 4.5 4"/><circle cx="35" cy="34.5" r="1.2"/>',
	music: '<path d="M30 42.5V31.5l9-2v11"/><circle cx="28" cy="42.5" r="2.2"/><circle cx="37" cy="40.5" r="2.2"/>',
	videos: '<rect x="24" y="31" width="16" height="12" rx="2.5"/><path d="M30.5 34.2v5.6l4.6-2.8z" fill="#fff"/>',
	games: '<rect x="23.5" y="32" width="17" height="10" rx="5"/><path d="M28 35v4M26 37h4M35.5 36h.1M37.5 38h.1"/>',
	code: '<path d="M28.5 33l-4 4 4 4M35.5 33l4 4-4 4"/>',
	cloud: '<path d="M27.5 42.5a4 4 0 0 1-.5-8 5.5 5.5 0 0 1 10.6 1.4 3.3 3.3 0 0 1-.6 6.6z"/>',
};

function icon(name, size) {
	const s = size || 16;
	return '<svg class="ic" width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || '') + '</svg>';
}

// A glassy amber folder, with a glyph for the special ones.
function folderArt(kind, size, open) {
	const s = size || 64;
	const g = FOLDER_GLYPHS[kind] || '';
	return '<svg class="art folder' + (open ? ' open' : '') + '" width="' + s + '" height="' + s + '" viewBox="0 0 64 64" aria-hidden="true">' +
		'<path d="M6 15.5A4.5 4.5 0 0 1 10.5 11h12.3a3 3 0 0 1 2.2 1l3.6 3.9h24.9A4.5 4.5 0 0 1 58 20.4V47a4.5 4.5 0 0 1-4.5 4.5h-43A4.5 4.5 0 0 1 6 47z" fill="url(#fold-back)"/>' +
		'<rect class="sheet" x="11" y="19" width="42" height="22" rx="2.5" fill="#fff" opacity="0.92"/>' +
		'<path class="front" d="M5.2 27.8A4.5 4.5 0 0 1 9.7 23h44.6a4.5 4.5 0 0 1 4.5 4.8l-1.3 19.7A4.5 4.5 0 0 1 53 51.7H11a4.5 4.5 0 0 1-4.5-4.2z" fill="url(#fold-front)"/>' +
		'<path d="M5.2 27.8A4.5 4.5 0 0 1 9.7 23h44.6a4.5 4.5 0 0 1 4.5 4.8l-.6 9H5.9z" fill="url(#fold-gloss)"/>' +
		'<path d="M9.7 23.6h44.6" stroke="#fff" stroke-opacity="0.7" stroke-width="1" fill="none"/>' +
		(g ? '<g fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" opacity="0.95" style="filter:drop-shadow(0 1px 1px rgba(150,80,10,.45))">' + g + '</g>' : '') +
		'</svg>';
}

// A drive: a brushed slab with a lit strip, the system one wearing a small Windows mark.
function driveArt(type, size, system) {
	const s = size || 64;
	const led = type === 'usb' ? '#ffb35c' : type === 'network' ? '#7cb8f5' : type === 'disc' ? '#c79bff' : 'var(--accent)';
	let mark = '';
	if (system) mark = '<g transform="translate(14 36)" fill="#7cc6ff"><rect width="4.6" height="4.6" rx=".6"/><rect x="5.4" width="4.6" height="4.6" rx=".6"/><rect y="5.4" width="4.6" height="4.6" rx=".6"/><rect x="5.4" y="5.4" width="4.6" height="4.6" rx=".6"/></g>';
	else if (type === 'usb') mark = '<path d="M16 41h8M20 37v8" stroke="#cfd9e2" stroke-width="2" stroke-linecap="round"/>';
	else if (type === 'network') mark = '<path d="M14 41a6 6 0 0 1 12 0M17 41a3 3 0 0 1 6 0" stroke="#cfd9e2" stroke-width="1.8" fill="none" stroke-linecap="round"/>';
	return '<svg class="art drive" width="' + s + '" height="' + s + '" viewBox="0 0 64 64" aria-hidden="true">' +
		'<path d="M12 22l4.5-8.5A4 4 0 0 1 20 11.5h24a4 4 0 0 1 3.5 2L52 22z" fill="url(#drive-body)" opacity="0.85"/>' +
		'<rect x="7" y="22" width="50" height="28" rx="6" fill="url(#drive-face)"/>' +
		'<rect x="7.5" y="22.5" width="49" height="27" rx="5.5" fill="none" stroke="#fff" stroke-opacity="0.18"/>' +
		mark +
		'<rect x="34" y="39" width="16" height="3.2" rx="1.6" fill="' + led + '" style="filter:drop-shadow(0 0 3px ' + led + ')"/>' +
		'</svg>';
}

// Document art for when Windows has no icon to give (or before it arrives).
const DOC_COLORS = {
	image: ['#c79bff', '#7d4fd6'], video: ['#ff8ea0', '#d23f5f'], audio: ['#ff9fd2', '#c4448a'], code: ['#6fe3cf', '#1f9a8a'],
	archive: ['#ffd27a', '#c98a1c'], doc: ['#8fc2ff', '#3f7ad6'], app: ['#9fb4c8', '#4b6074'], text: ['#c6d0d9', '#7a8794'], pdf: ['#ff8a7a', '#c9392b'],
};

function docArt(cat, size, label) {
	const s = size || 64;
	const c = DOC_COLORS[cat] || DOC_COLORS.text;
	return '<svg class="art doc" width="' + s + '" height="' + s + '" viewBox="0 0 64 64" aria-hidden="true">' +
		'<path d="M15 6.5h23l13 13v36a3 3 0 0 1-3 3H15a3 3 0 0 1-3-3v-46a3 3 0 0 1 3-3z" fill="url(#doc-sheet)"/>' +
		'<path d="M38 6.5v10a3 3 0 0 0 3 3h10z" fill="#c4d0da"/>' +
		'<rect x="12" y="38" width="39" height="14" fill="' + c[1] + '" opacity="0.92"/>' +
		'<rect x="12" y="38" width="39" height="7" fill="' + c[0] + '" opacity="0.6"/>' +
		(label ? '<text x="31.5" y="48.6" text-anchor="middle" font-size="9.5" font-weight="700" fill="#fff" font-family="Geist, Segoe UI, sans-serif">' + esc(label.slice(0, 4).toUpperCase()) + '</text>' : '') +
		'</svg>';
}

function esc(s) {
	return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
