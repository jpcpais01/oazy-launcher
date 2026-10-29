// Line icons for Oazy Claude (24x24, drawn with currentColor), and Claude's mark.
const ICONS = {
	plus: '<path d="M12 5v14M5 12h14"/>',
	close: '<path d="M7 7l10 10M17 7L7 17"/>',
	clip: '<path d="m16 6-8.41 8.59a2 2 0 0 0 2.83 2.83l8.41-8.59a4 4 0 1 0-5.66-5.66l-8.38 8.55a6 6 0 1 0 8.49 8.49l8.38-8.55"/>',
	doc: '<path d="M14 3.5H7.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V8z"/><path d="M14 3.5V8h4.5M9 13h6M9 16.5h6"/>',
	min: '<path d="M6 12h12"/>',
	max: '<rect x="6" y="6" width="12" height="12" rx="2.5"/>',
	restore: '<rect x="5" y="8" width="11" height="11" rx="2.5"/><path d="M9 5h7.5A2.5 2.5 0 0 1 19 7.5V15"/>',
	sidebar: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M9.5 4.5v15"/>',
	folder: '<path d="M4 19h16a1.5 1.5 0 0 0 1.5-1.5V8.5A1.5 1.5 0 0 0 20 7h-7.4a1.5 1.5 0 0 1-1.2-.6l-.9-1.3A1.5 1.5 0 0 0 9.3 4.5H4A1.5 1.5 0 0 0 2.5 6v11.5A1.5 1.5 0 0 0 4 19z"/>',
	down: '<path d="M7 10l5 5 5-5"/>',
	chevron: '<path d="M10 7l5 5-5 5"/>',
	terminal: '<rect x="3" y="4.5" width="18" height="15" rx="3"/><path d="M7.5 9.5l3 2.5-3 2.5M12.5 15h4"/>',
	send: '<path d="M12 19V5M6 11l6-6 6 6"/>',
	stop: '<rect x="7" y="7" width="10" height="10" rx="2" fill="currentColor" stroke="none"/>',
	check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
	x: '<path d="M8 8l8 8M16 8l-8 8"/>',
	copy: '<rect x="8" y="8" width="11.5" height="11.5" rx="2.5"/><path d="M5 15.5V6.5A2 2 0 0 1 7 4.5h8.5"/>',
	edit: '<path d="M4 20h4L18.5 9.5a2.1 2.1 0 0 0-3-3L5 17v3z"/><path d="M13.5 8.5l3 3"/>',
	file: '<path d="M6.5 3.5h8l4 4v12a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-15a1 1 0 0 1 1-1z"/><path d="M14 3.5v4.5h4.5"/>',
	newfile: '<path d="M6.5 3.5h8l4 4v12a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-15a1 1 0 0 1 1-1z"/><path d="M12 10.5v6M9 13.5h6"/>',
	eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
	search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
	globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5a13 13 0 0 1 0 17M12 3.5a13 13 0 0 0 0 17"/>',
	todo: '<path d="M10 6.5h10M10 12h10M10 17.5h10"/><path d="M3.8 6.3l1.3 1.3 2.2-2.4M3.8 11.8l1.3 1.3 2.2-2.4"/><circle cx="5.3" cy="17.5" r="1.4"/>',
	agent: '<path d="M9.94 15.5A2 2 0 0 0 8.5 14.06l-6.13-1.58a.5.5 0 0 1 0-.96L8.5 9.94A2 2 0 0 0 9.94 8.5l1.58-6.13a.5.5 0 0 1 .96 0L14.06 8.5A2 2 0 0 0 15.5 9.94l6.13 1.58a.5.5 0 0 1 0 .96L15.5 14.06a2 2 0 0 0-1.44 1.44l-1.58 6.13a.5.5 0 0 1-.96 0z"/>',
	plan: '<path d="M9 4.5L3.5 6.5v13L9 17.5l6 2 5.5-2v-13L15 6.5z"/><path d="M9 4.5v13M15 6.5v13"/>',
	shield: '<path d="M12 3.5l7 2.8v5.2c0 4.4-3 7.6-7 9-4-1.4-7-4.6-7-9V6.3z"/>',
	bolt: '<path d="M13 3L5 13.5h6l-1 7.5 8-10.5h-6z"/>',
	image: '<rect x="3.5" y="5" width="17" height="14" rx="2.5"/><circle cx="9" cy="10" r="1.6"/><path d="M4 17.5l5-4.5 3.5 3 2.5-2 4.5 3.5"/>',
	alert: '<path d="M12 4l9 16H3z"/><path d="M12 10v4.5M12 17.3v.1"/>',
	tool: '<path d="M14.5 6.5a4 4 0 0 0-5 5L4 17l3 3 5.5-5.5a4 4 0 0 0 5-5l-2.5 2.5-2.5-.5-.5-2.5z"/>',
	open: '<path d="M14 4.5h5.5V10M19.5 4.5L11 13"/><path d="M18 14v3.5a2 2 0 0 1-2 2H6.5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2H10"/>',
	chat: '<path d="M20.5 14.5a2 2 0 0 1-2 2H8l-4.5 3.5V6.5a2 2 0 0 1 2-2h13a2 2 0 0 1 2 2z"/>',
	bug: '<rect x="7" y="8" width="10" height="12" rx="5"/><path d="M9.5 8V6.5a2.5 2.5 0 0 1 5 0V8M3.5 13h3.5M17 13h3.5M4.5 8.5l3 2M19.5 8.5l-3 2M4.5 18l3-2M19.5 18l-3-2"/>',
	flask: '<path d="M9.5 3.5h5M10.5 3.5v6L5 19a1.3 1.3 0 0 0 1.1 2h11.8A1.3 1.3 0 0 0 19 19l-5.5-9.5v-6"/><path d="M7.5 15h9"/>',
	review: '<circle cx="6.5" cy="6" r="2.2"/><circle cx="6.5" cy="18" r="2.2"/><circle cx="17.5" cy="12" r="2.2"/><path d="M6.5 8.2v7.6M8.5 7.2c4 1 7 2 7 2.8"/>',
	book: '<path d="M4.5 5.5A2 2 0 0 1 6.5 3.5h13v14h-13a2 2 0 0 0-2 2z"/><path d="M4.5 19.5a2 2 0 0 0 2 2h13v-4"/>',
	compact: '<path d="M4 9h16M4 15h16M12 3v4l-2-2M12 7l2-2M12 21v-4l-2 2M12 17l2 2"/>',
};

function icon(name, size) {
	const s = size || 16;
	return '<svg class="ic" width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || ICONS.tool) + '</svg>';
}

// Claude's mark as Oazy draws it: eight soft rays in warm coral.
function mark(size, plain) {
	const s = size || 20;
	const stroke = plain ? 'currentColor' : 'url(#mark-fill)';
	return '<svg class="mark" width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="' + stroke + '" stroke-width="2.4" stroke-linecap="round" aria-hidden="true">' +
		'<path d="M12 2.5v6M12 15.5v6M2.5 12h6M15.5 12h6M5.3 5.3l4.2 4.2M14.5 14.5l4.2 4.2M18.7 5.3l-4.2 4.2M9.5 14.5l-4.2 4.2"/></svg>';
}

function esc(s) {
	return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
