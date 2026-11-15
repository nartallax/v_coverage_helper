module main

import os

// SortBy selects the order of files in the overview.
pub enum SortBy {
	path
	score // lowest coverage first
}

// RenderSettings holds the settings for HTML rendering.
pub struct RenderSettings {
pub:
	sort_by SortBy  // order of files in the overview
	src_dir string  // sources directory; entry paths are shown relative to it
}

// render_html writes the coverage report for `entries` into `html_dir`:
// a single index.html overview, plus one page per entry with partial
// coverage (entries with 0% or 100% coverage do not get their own page).
pub fn render_html(entries []CoverageEntry, html_dir string, settings RenderSettings) ! {
	if !os.exists(html_dir) {
		os.mkdir_all(html_dir)!
	}
	sorted := sort_entries(entries, settings.sort_by)
	src_dir := if settings.src_dir == '' { '' } else { to_abs(os.getwd(), settings.src_dir) }
	render_index(sorted, html_dir, src_dir)!
	render_file_pages(sorted, html_dir, src_dir)
}

// sort_entries returns a copy of `entries`, sorted by the given criterion.
// The score order puts the lowest coverage first, with the path as a
// tie-breaker for equal scores.
fn sort_entries(entries []CoverageEntry, by SortBy) []CoverageEntry {
	mut sorted := entries.clone()
	match by {
		.path {
			sorted.sort_with_compare(fn (a &CoverageEntry, b &CoverageEntry) int {
				return cmp_strings(a.file_path, b.file_path)
			})
		}
		.score {
			sorted.sort_with_compare(fn (a &CoverageEntry, b &CoverageEntry) int {
				pa := coverage_percent(a)
				pb := coverage_percent(b)
				if pa < pb {
					return -1
				}
				if pa > pb {
					return 1
				}
				return cmp_strings(a.file_path, b.file_path)
			})
		}
	}
	return sorted
}

fn cmp_strings(a string, b string) int {
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}

// coverage_percent returns the percentage of known lines that are covered.
// Entries without any known lines count as fully covered.
fn coverage_percent(e &CoverageEntry) f64 {
	if e.known_lines.len == 0 {
		return 100.0
	}
	return f64(e.covered_lines.len) / f64(e.known_lines.len) * 100.0
}

// has_file_page reports whether an entry with this coverage gets its own
// page: only entries with partial coverage do.
fn has_file_page(pct f64) bool {
	return pct > 0.0 && pct < 100.0
}

// page_name is the file name of the page describing `e`: the entry's path
// relative to the sources directory, with every character that is not a
// letter, a digit or a dot replaced by an underscore, plus a .html suffix.
fn page_name(src_dir string, e &CoverageEntry) string {
	return '${sanitize_file_name(rel_to(src_dir, e.file_path))}.html'
}

// sanitize_file_name replaces every character that is not a letter, a digit
// or a dot with an underscore.
fn sanitize_file_name(path string) string {
	mut out := []u8{len: path.len}
	for i := 0; i < path.len; i++ {
		c := path[i]
		if c.is_letter() || c.is_digit() || c == `.` {
			out[i] = c
		} else {
			out[i] = `_`
		}
	}
	return out.bytestr()
}

// percent_hue maps a coverage percentage to a hue: red (0) at 0% coverage,
// yellow (60) at 75%, green (120) at 100%.
fn percent_hue(pct f64) int {
	if pct <= 75.0 {
		return int(pct / 75.0 * 60.0)
	}
	return 60 + int((pct - 75.0) / 25.0 * 60.0)
}

fn percent_color(pct f64) string {
	return 'hsl(${percent_hue(pct)}, 85%, 65%)'
}

// percent_str formats a percentage with two digits after the dot.
fn percent_str(pct f64) string {
	return '${pct:.2f}'
}

// rel_to returns `path` relative to `src_dir` when it lies within it,
// otherwise `path` unchanged.
fn rel_to(src_dir string, path string) string {
	if src_dir != '' && path.starts_with('${src_dir}/') {
		return path[src_dir.len + 1..]
	}
	return path
}

// total_percent returns the total coverage over all entries: the share of
// all known lines that are covered.
fn total_percent(entries []CoverageEntry) f64 {
	mut known := 0
	mut covered := 0
	for e in entries {
		known += e.known_lines.len
		covered += e.covered_lines.len
	}
	if known == 0 {
		return 100.0
	}
	return f64(covered) / f64(known) * 100.0
}

// render_index writes the overview page listing all entries.
fn render_index(entries []CoverageEntry, html_dir string, src_dir string) ! {
	mut rows := []string{}
	for e in entries {
		pct := coverage_percent(e)
		mut path_html := escape_html(rel_to(src_dir, e.file_path))
		if has_file_page(pct) {
			path_html = '<a href="${page_name(src_dir, e)}">${path_html}</a>'
		}
		rows << '<tr><td class="path">${path_html}</td><td class="lines">${e.covered_lines.len}/${e.known_lines.len}</td><td class="pct"><span class="score" style="color: ${percent_color(pct)}">${percent_str(pct)}%</span></td></tr>'
	}
	total := total_percent(entries)
	html := '<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Coverage report</title>
<style>${base_css}
.path { font-family: ui-monospace, monospace; }
.lines, .pct { text-align: right; }
table { border-collapse: separate; border-spacing: 0; border-radius: 6px; border: 1px solid #2e3238; overflow: hidden; }
th, td { text-align: left; padding: 6px 12px; white-space: nowrap; border-bottom: 1px solid #2e3238; }
th { color: #9aa0a8; background: #22252a; }
th:not(:first-child), td:not(:first-child) { border-left: 1px solid #2e3238; }
tbody tr:last-child td { border-bottom: none; }
tbody tr:hover td { background: #262a30; }
</style>
</head>
<body>
<h1>Coverage report <span class="score" style="color: ${percent_color(total)}">${percent_str(total)}%</span></h1>
<table>
<thead><tr><th>Path</th><th>Lines</th><th>Percent</th></tr></thead>
<tbody>
${rows.join('\n')}
</tbody>
</table>
</body>
</html>
'
	os.write_file(os.join_path(html_dir, 'index.html'), html)!
}

// render_file_pages writes one page per entry with partial coverage.
fn render_file_pages(entries []CoverageEntry, html_dir string, src_dir string) {
	for e in entries {
		pct := coverage_percent(e)
		if !has_file_page(pct) {
			continue
		}
		name := page_name(src_dir, e)
		os.write_file(os.join_path(html_dir, name), file_page_html(e, pct)) or {
			eprintln('warning: could not write ${name}: ${err}')
		}
	}
}

// file_page_html builds the page for one source file: its contents with
// line numbers, covered lines marked green and uncovered lines red.
fn file_page_html(e &CoverageEntry, pct f64) string {
	mut covered := map[int]bool{}
	for line in e.covered_lines {
		covered[line] = true
	}
	mut known := map[int]bool{}
	for line in e.known_lines {
		known[line] = true
	}
	mut lines := []string{}
	for i, line in e.contents.split_into_lines() {
		n := i + 1
		mut cls := 'line'
		if covered[n] {
			cls += ' covered'
		} else if known[n] {
			cls += ' uncovered'
		}
		mut content := escape_html(line)
		if content == '' {
			content = '&nbsp;'
		}
		lines << '<div class="${cls}" id="L${n}"><span class="ln">${n}</span><span class="src">${content}</span></div>'
	}
	title := '${percent_str(pct)}% - ${escape_html(e.file_path)}'
	return '<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${title}</title>
<style>${base_css}
.top { display: flex; justify-content: space-between; align-items: center; gap: 12px; position: sticky; top: 0; z-index: 10; background: #1b1d21; padding: 0.5rem 0 1rem; border-bottom: 1px solid #2e3238; }
.path { font-family: ui-monospace, monospace; }
.line { display: flex; position: relative; z-index: 0; font-family: ui-monospace, monospace; font-size: 13px; line-height: 1.5; --tint: transparent; --hover: transparent; box-shadow: inset 0 0 0 100vmax var(--tint), inset 0 0 0 100vmax var(--hover); transition: box-shadow 0.15s ease; }
.ln { flex: none; width: 4em; text-align: right; padding-right: 12px; color: #6b7280; user-select: none; border-right: 1px solid #2e3238; }
.src { flex: 1; white-space: pre; padding-left: 12px; }
.line:nth-child(even) { background: #1f2227; }
.line.covered { --tint: rgba(63, 185, 80, 0.14); }
.line.uncovered { --tint: rgba(248, 81, 73, 0.14); }
.line:hover { --hover: rgba(255, 255, 255, 0.08); transition: none; }
.line::after { content: ""; position: absolute; inset: 0; z-index: -1; background: rgba(122, 176, 255, 0.42); opacity: 0; transition: opacity 1.2s linear; pointer-events: none; }
.line.flash::after { opacity: 1; transition: opacity 0.05s ease; }
</style>
</head>
<body>
<div class="top">
<span class="head"><span class="path">${escape_html(e.file_path)}</span> <span class="score" style="color: ${percent_color(pct)}">${percent_str(pct)}%</span></span>
<span class="actions">
<button onclick="jump(-1)">&larr; prev uncovered sequence</button>
<button onclick="jump(1)">next uncovered sequence &rarr;</button>
</span>
</div>
<div class="code">
${lines.join('\n')}
</div>
<script>
const uncovered = Array.from(document.querySelectorAll(".line.uncovered"));
// group adjacent uncovered lines into sequences: next/prev jump between
// sequences, skipping the remaining lines of the current one
const sequences = [];
for (const el of uncovered) {
	const n = parseInt(el.id.slice(1), 10);
	const last = sequences[sequences.length - 1];
	if (last !== undefined && n === last.end + 1) {
		last.end = n;
		last.els.push(el);
	} else {
		sequences.push({ start: n, end: n, els: [el] });
	}
}
let idx = -1;
let flashEls = [];
let flashTimer = null;
function clearFlash() {
	for (const el of flashEls) {
		el.classList.remove("flash");
	}
	flashEls = [];
}
function jump(step) {
	if (sequences.length === 0) {
		return;
	}
	idx = (idx + step + sequences.length) % sequences.length;
	sequences[idx].els[0].scrollIntoView({ behavior: "smooth", block: "center" });
	clearFlash();
	if (flashTimer !== null) {
		clearTimeout(flashTimer);
		flashTimer = null;
	}
	flashEls = sequences[idx].els;
	for (const el of flashEls) {
		el.classList.add("flash");
	}
	flashTimer = setTimeout(clearFlash, 1000);
}
</script>
</body>
</html>
'
}

// base_css holds the shared dark flat theme styles.
const base_css = ':root { color-scheme: dark; }
body { background: #1b1d21; color: #cfd3d8; font-family: system-ui, sans-serif; margin: 0; padding: 1rem 1.5rem; }
h1 { font-size: 1.3rem; font-weight: 600; }
a { color: #7ab0ff; }
.score { font-weight: bold; }
button { background: #2a2d33; color: #cfd3d8; border: 1px solid #3a3f46; padding: 6px 12px; font-family: inherit; font-size: 0.9rem; cursor: pointer; border-radius: 6px; }
button:hover { background: #34383f; }
'

// escape_html escapes the characters that are special in HTML.
fn escape_html(s string) string {
	return s.replace_each(['&', '&amp;', '<', '&lt;', '>', '&gt;', '"', '&quot;'])
}
