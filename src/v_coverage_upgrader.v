module src

import os

// CoverageEntry is an LcovEntry enriched with the contents of its source file.
pub struct CoverageEntry {
pub:
	file_path     string // source file path, as in the lcov record
	known_lines   []int  // all instrumented lines, plus lines of dropped functions
	covered_lines []int  // line numbers with a non-zero execution count
	contents      string // full source file contents
}

// FnDef is the line range of one function definition in a source file.
struct FnDef {
	start int // 1-based line number of the `fn` line
	end   int // 1-based line number of the closing `}`
}

// CoverageUpgrader upgrades lcov entries using the actual source files,
// recovering functions that the lcov generator dropped entirely.
pub struct CoverageUpgrader {
	src_dir    string   // absolute path to the sources directory
	extensions []string // extensions considered V source code files
mut:
	known_files map[string]bool // absolute paths of the upgraded entries
}

pub fn new_coverage_upgrader(src_dir string, extensions []string) CoverageUpgrader {
	return CoverageUpgrader{
		src_dir:     to_abs(os.getwd(), src_dir)
		extensions:  extensions
		known_files: map[string]bool{}
	}
}

// upgrade_lcov_entry reads the source file referenced by `entry` and returns
// a CoverageEntry for it. The entry's file_path is expected to be an absolute
// path, as produced by the lcov parser. The lcov generator drops functions
// that are never used, so a function whose whole range is unmentioned in the
// entry is added to known_lines (as uncovered) instead.
// Each successfully upgraded path is remembered for cover_unknown_files.
pub fn (mut u CoverageUpgrader) upgrade_lcov_entry(entry &LcovEntry) !CoverageEntry {
	full_path := to_abs('', entry.file_path)
	contents := os.read_file(full_path)!
	u.known_files[full_path] = true
	lines := contents.split_into_lines()
	defs := find_fn_defs(lines)
	// set of the lcov-mentioned lines, for quick range membership checks
	mut mentioned := map[int]bool{}
	for line in entry.known_lines {
		mentioned[line] = true
	}
	mut known := entry.known_lines.clone()
	for def in defs {
		if !has_mentioned_line(mentioned, def) {
			for l := def.start; l <= def.end; l++ {
				known << l
			}
		}
	}
	known.sort()
	return CoverageEntry{
		file_path:     full_path
		known_lines:   known
		covered_lines: entry.covered_lines
		contents:      contents
	}
}

// cover_unknown_files walks the sources directory recursively and returns a
// CoverageEntry for every source file (by extension) that was never passed
// to upgrade_lcov_entry. Such files are completely absent from the lcov
// data, so they are reported with no covered lines and line 1 as the only
// known line.
pub fn (u &CoverageUpgrader) cover_unknown_files() ![]CoverageEntry {
	mut files := []string{}
	for ext in u.extensions {
		files << os.walk_ext(u.src_dir, ext)
	}
	// walk order is filesystem-dependent; sort for a stable result
	files.sort()
	mut entries := []CoverageEntry{}
	for file in files {
		path := to_abs('', file)
		if u.known_files[path] || is_test_file(path, u.extensions) {
			continue
		}
		contents := os.read_file(path)!
		entries << CoverageEntry{
			file_path:     path
			known_lines:   [1]
			covered_lines: []
			contents:      contents
		}
	}
	return entries
}

// has_mentioned_line reports whether any lcov-mentioned line falls within
// the definition's range. Since the ranges of all definitions together span
// at most the whole file, these scans stay linear in the file size.
fn has_mentioned_line(mentioned map[int]bool, def FnDef) bool {
	for l := def.start; l <= def.end; l++ {
		if mentioned[l] {
			return true
		}
	}
	return false
}

// find_fn_defs scans source lines for function definitions: lines that start
// with `fn` (optionally after a `pub` prefix). For each start, the definition
// ends on the line with the matching closing `}`.
fn find_fn_defs(lines []string) []FnDef {
	mut defs := []FnDef{}
	for i, line in lines {
		mut l := line.trim(' \t\r')
		if l.starts_with('pub ') {
			l = l[4..].trim_left(' \t\r')
		}
		if !l.starts_with('fn ') {
			continue
		}
		if end := scan_fn_end(lines, i) {
			defs << FnDef{
				start: i + 1 // lcov line numbers are 1-based
				end:   end + 1
			}
		}
	}
	return defs
}

// scan_fn_end returns the 0-based index of the line closing the function
// definition that starts on line `start`, or none when the definition has no
// body (e.g. an interface method declaration) or is not terminated by the
// end of the file.
fn scan_fn_end(lines []string, start int) ?int {
	mut depth := 0
	mut seen_open := false
	for i := start; i < lines.len; i++ {
		for c in lines[i] {
			if c == `{` {
				seen_open = true
				depth++
			} else if c == `}` {
				if !seen_open {
					return none
				}
				depth--
				if depth == 0 {
					return i
				}
			}
		}
	}
	return none
}
