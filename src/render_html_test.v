module main

import os

fn make_entries() []CoverageEntry {
	return [
		CoverageEntry{
			file_path: '/proj/full.v'
			known_lines: [1, 2]
			covered_lines: [1, 2]
			contents: 'fn f() {}\n'
		},
		CoverageEntry{
			file_path: '/proj/zero.v'
			known_lines: [1]
			covered_lines: []
			contents: 'fn z() {\n}\n'
		},
		CoverageEntry{
			file_path: '/proj/half.v'
			known_lines: [1, 2]
			covered_lines: [1]
			contents: 'fn h() {\n\tprintln("<b>&")\n}\n'
		},
	]
}

fn test_render_html_writes_index_and_partial_pages() ! {
	dir := os.join_path(os.temp_dir(), 'vch_html_${os.getpid()}')
	render_html(make_entries(), dir, RenderSettings{
		sort_by: .path
		src_dir: '/proj'
	})!
	defer {
		os.rmdir_all(dir) or {}
	}

	index := os.read_file(os.join_path(dir, 'index.html'))!
	// paths are shown relative to the src dir and pages are named after
	// them; only half (partial coverage) gets a page
	assert index.contains('<a href="half.v.html">half.v</a>')
	assert index.contains('>full.v<')
	assert index.contains('>zero.v<')
	assert !index.contains('href="full.v.html"')
	assert !index.contains('href="zero.v.html"')
	// capitalized column titles
	assert index.contains('<th>Path</th>')
	assert index.contains('<th>Lines</th>')
	assert index.contains('<th>Percent</th>')
	// lines column, percent with 2 decimals, 50% -> hue 40
	assert index.contains('1/2')
	assert index.contains('50.00%')
	assert index.contains('hsl(40, 85%, 65%)')
	// total coverage next to the heading: 3/5 = 60% -> hue 48
	assert index.contains('<h1>Coverage report <span class="score" style="color: hsl(48, 85%, 65%)">60.00%</span></h1>')

	assert !os.exists(os.join_path(dir, 'full.v.html'))
	assert !os.exists(os.join_path(dir, 'zero.v.html'))
	page := os.read_file(os.join_path(dir, 'half.v.html'))!
	assert page.contains('<title>50.00% - /proj/half.v</title>')
	// the page header shows the file coverage with the same color logic
	assert page.contains('<span class="score" style="color: hsl(40, 85%, 65%)">50.00%</span>')
	assert page.contains('class="line covered" id="L1"')
	assert page.contains('class="line uncovered" id="L2"')
	// source content is escaped
	assert page.contains('&lt;b&gt;&amp;')
	// uncovered line navigation
	assert page.contains('jump(1)')
}

fn test_render_html_sorts_by_score() ! {
	dir := os.join_path(os.temp_dir(), 'vch_html_score_${os.getpid()}')
	render_html(make_entries(), dir, RenderSettings{
		sort_by: .score
		src_dir: '/proj'
	})!
	defer {
		os.rmdir_all(dir) or {}
	}

	index := os.read_file(os.join_path(dir, 'index.html'))!
	// zero (0%) before half (50%) before full (100%)
	i_zero := index.index('>zero.v<') or { -1 }
	i_half := index.index('>half.v<') or { -1 }
	i_full := index.index('>full.v<') or { -1 }
	assert i_zero < i_half
	assert i_half < i_full
}

fn test_sanitize_file_name() {
	assert sanitize_file_name('src/a.v') == 'src_a.v'
	assert sanitize_file_name('weird name-1+.v') == 'weird_name_1_.v'
	assert sanitize_file_name('a.b/c-d.v') == 'a.b_c_d.v'
}

fn test_page_name_uses_sanitized_relative_path() ! {
	dir := os.join_path(os.temp_dir(), 'vch_html_names_${os.getpid()}')
	render_html([CoverageEntry{
		file_path:   '/proj/sub/mod.v'
		known_lines: [1, 2]
		covered_lines: [1]
		contents: 'fn m() {}\n'
	}], dir, RenderSettings{
		sort_by: .path
		src_dir: '/proj'
	})!
	defer {
		os.rmdir_all(dir) or {}
	}

	assert os.exists(os.join_path(dir, 'sub_mod.v.html'))
}
