// A small Markdown renderer for Claude's replies: headings, paragraphs, lists
// (nested by indent), quotes, fenced code with a copy button, tables, rules,
// and inline code, bold, italic, strikethrough and links. Everything is
// escaped first, so a reply can never put its own HTML on the page. It's run
// again on every streamed chunk, so it stays simple and forgiving of a
// half-written reply (an unclosed fence is still a code block).

const MD = (() => {
	function inline(s) {
		// Code spans first, kept out of the other rules.
		const codes = [];
		s = s.replace(/(`+)([\s\S]*?[^`])\1(?!`)/g, (m, ticks, body) => {
			codes.push('<code>' + esc(body.trim() === '' ? body : body.replace(/^ (.*) $/, '$1')) + '</code>');
			return '\u0000' + (codes.length - 1) + '\u0000';
		});
		s = esc(s);
		// [text](url) and bare urls.
		s = s.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, (m, t, u) => '<a href="' + u + '" data-url="' + u + '">' + t + '</a>');
		s = s.replace(/(^|[\s(])(https?:\/\/[^\s<)]+[^\s<).,;:!?'"])/g, (m, pre, u) => pre + '<a href="' + u + '" data-url="' + u + '">' + u + '</a>');
		s = s.replace(/\*\*([^*\n]+?)\*\*/g, '<strong>$1</strong>');
		s = s.replace(/__([^_\n]+?)__/g, '<strong>$1</strong>');
		s = s.replace(/(^|[^*\w])\*([^*\s][^*\n]*?)\*(?!\w)/g, '$1<em>$2</em>');
		s = s.replace(/(^|[^_\w])_([^_\s][^_\n]*?)_(?!\w)/g, '$1<em>$2</em>');
		s = s.replace(/~~([^~\n]+?)~~/g, '<del>$1</del>');
		return s.replace(/\u0000(\d+)\u0000/g, (m, i) => codes[+i]);
	}

	function codeBlock(lang, lines) {
		const l = (lang || '').trim().split(/\s+/)[0];
		return '<div class="code"><div class="code-bar"><span>' + esc(l || 'code') + '</span><button class="copy" title="Copy">' + icon('copy', 13) + '</button></div>' +
			'<pre><code>' + esc(lines.join('\n')) + '</code></pre></div>';
	}

	function table(rows) {
		const cells = r => r.trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim());
		const head = cells(rows[0]);
		const align = cells(rows[1]).map(c => /^:-+:$/.test(c) ? 'center' : /^-+:$/.test(c) ? 'right' : '');
		let h = '<div class="table"><table><thead><tr>';
		head.forEach((c, i) => { h += '<th' + (align[i] ? ' style="text-align:' + align[i] + '"' : '') + '>' + inline(c) + '</th>'; });
		h += '</tr></thead><tbody>';
		for (const r of rows.slice(2)) {
			h += '<tr>';
			cells(r).forEach((c, i) => { h += '<td' + (align[i] ? ' style="text-align:' + align[i] + '"' : '') + '>' + inline(c) + '</td>'; });
			h += '</tr>';
		}
		return h + '</tbody></table></div>';
	}

	// Lists: a stack of open lists by indent.
	function list(lines) {
		let html = '';
		const stack = [];
		for (const raw of lines) {
			const m = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/.exec(raw);
			if (!m) {
				// A wrapped line of the item above.
				if (stack.length) html += ' ' + inline(raw.trim());
				continue;
			}
			const indent = m[1].replace(/\t/g, '    ').length;
			const ordered = /\d/.test(m[2]);
			while (stack.length && indent < stack[stack.length - 1].indent) html += '</li></' + stack.pop().tag + '>';
			const top = stack[stack.length - 1];
			if (!top || indent > top.indent) {
				const tag = ordered ? 'ol' : 'ul';
				html += '<' + tag + (ordered && parseInt(m[2], 10) !== 1 ? ' start="' + parseInt(m[2], 10) + '"' : '') + '>';
				stack.push({ indent: indent, tag: tag });
			} else html += '</li>';
			let body = m[3];
			const task = /^\[([ xX])\]\s+(.*)$/.exec(body);
			if (task) body = '<span class="task' + (task[1] !== ' ' ? ' done' : '') + '"></span>' + inline(task[2]);
			else body = inline(body);
			html += '<li>' + body;
		}
		while (stack.length) html += '</li></' + stack.pop().tag + '>';
		return html;
	}

	function render(src) {
		const lines = String(src || '').replace(/\r/g, '').split('\n');
		let out = '';
		let para = [];
		const flush = () => {
			if (para.length) out += '<p>' + para.map(inline).join('<br>') + '</p>';
			para = [];
		};
		for (let i = 0; i < lines.length; i++) {
			const line = lines[i];
			const fence = /^\s*(```+|~~~+)(.*)$/.exec(line);
			if (fence) {
				flush();
				const body = [];
				const close = fence[1];
				i++;
				while (i < lines.length && !lines[i].trim().startsWith(close)) body.push(lines[i++]);
				out += codeBlock(fence[2], body);
				continue;
			}
			if (/^\s*$/.test(line)) { flush(); continue; }
			const h = /^(#{1,6})\s+(.*?)\s*#*\s*$/.exec(line);
			if (h) { flush(); const n = Math.min(4, h[1].length + 1); out += '<h' + n + '>' + inline(h[2]) + '</h' + n + '>'; continue; }
			if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) { flush(); out += '<hr>'; continue; }
			if (/^\s*>/.test(line)) {
				flush();
				const q = [];
				while (i < lines.length && /^\s*>/.test(lines[i])) q.push(lines[i++].replace(/^\s*>\s?/, ''));
				i--;
				out += '<blockquote>' + render(q.join('\n')) + '</blockquote>';
				continue;
			}
			if (/^\s*\|.*\|\s*$/.test(line) && i + 1 < lines.length && /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/.test(lines[i + 1])) {
				flush();
				const rows = [];
				while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) rows.push(lines[i++]);
				i--;
				out += table(rows);
				continue;
			}
			if (/^\s*([-*+]|\d+[.)])\s+/.test(line)) {
				flush();
				const items = [];
				while (i < lines.length && (/^\s*([-*+]|\d+[.)])\s+/.test(lines[i]) || (/^\s+\S/.test(lines[i]) && items.length))) items.push(lines[i++]);
				i--;
				out += list(items);
				continue;
			}
			para.push(line);
		}
		flush();
		return out;
	}

	return { render: render, inline: inline };
})();
