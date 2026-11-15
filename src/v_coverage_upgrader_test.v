module src

import os

const sample_source = "module main

fn used() {
	println('hi')
}

pub fn dropped() {
	if true {
		println('x')
	}
}

fn same_line() {}

interface Foo {
	fn bar()
}

fn also_dropped() { println('y') }
"

fn test_dropped_functions_are_added_as_uncovered() ! {
	name := 'vch_sample_${os.getpid()}.v'
	path := os.join_path(os.temp_dir(), name)
	os.write_file(path, sample_source)!
	defer {
		os.rm(path) or {}
	}
	mut upgrader := new_coverage_upgrader(os.temp_dir(), ['.v'])

	// only `used` (lines 3-5) is mentioned in the lcov data
	entry := LcovEntry{
		file_path:     path
		known_lines:   [4]
		covered_lines: [4]
	}
	upgraded := upgrader.upgrade_lcov_entry(entry) or { panic('expected upgrade to succeed') }

	// dropped (7-11), same_line (13) and also_dropped (19) have no mentioned
	// line, so all their lines become known-but-uncovered; used stays as-is;
	// the bodyless interface method (line 16) is ignored
	assert upgraded.known_lines == [4, 7, 8, 9, 10, 11, 13, 19]
	assert upgraded.covered_lines == [4]
	assert upgraded.file_path == path
	assert upgraded.contents == sample_source
}

fn test_mentioned_function_is_not_touched() ! {
	name := 'vch_sample2_${os.getpid()}.v'
	path := os.join_path(os.temp_dir(), name)
	os.write_file(path, sample_source)!
	defer {
		os.rm(path) or {}
	}
	mut upgrader := new_coverage_upgrader(os.temp_dir(), ['.v'])

	// line 9 lies within dropped (7-11), so that function was not dropped;
	// the other unmentioned functions (used 3-5, same_line 13,
	// also_dropped 19) are still recovered
	entry := LcovEntry{
		file_path:   path
		known_lines: [9]
	}
	upgraded := upgrader.upgrade_lcov_entry(entry) or { panic('expected upgrade to succeed') }
	assert upgraded.known_lines == [3, 4, 5, 9, 13, 19]
}

fn test_multiline_signature() ! {
	source := "fn multi(
	a int,
	b int,
) {
	println(a)
}
"
	path := os.join_path(os.temp_dir(), 'vch_multi_${os.getpid()}.v')
	os.write_file(path, source)!
	defer {
		os.rm(path) or {}
	}
	mut upgrader := new_coverage_upgrader(os.temp_dir(), ['.v'])

	// no lines mentioned at all: the whole function (lines 1-6) is recovered
	entry := LcovEntry{
		file_path: path
	}
	upgraded := upgrader.upgrade_lcov_entry(entry) or { panic('expected upgrade to succeed') }
	assert upgraded.known_lines == [1, 2, 3, 4, 5, 6]
}

fn test_missing_source_file_errors() {
	mut upgrader := new_coverage_upgrader(os.temp_dir(), ['.v'])
	entry := LcovEntry{
		file_path: os.join_path(os.temp_dir(), 'no_such_source_file.v')
	}
	if _ := upgrader.upgrade_lcov_entry(entry) {
		panic('expected an error for a missing source file')
	}
}

fn test_cover_unknown_files() ! {
	root := os.join_path(os.temp_dir(), 'vch_unknown_${os.getpid()}')
	os.mkdir_all(os.join_path(root, 'sub'))!
	defer {
		os.rmdir_all(root) or {}
	}

	known := os.join_path(root, 'known.v')
	os.write_file(known, 'module main\n')!
	os.write_file(os.join_path(root, 'b.v'), 'fn b() {}\n')!
	os.write_file(os.join_path(root, 'sub', 'c.v'), 'fn c() {}\n')!
	os.write_file(os.join_path(root, 'ignored.txt'), 'not a v file\n')!
	os.write_file(os.join_path(root, 'skipped_test.v'), 'fn t() {}\n')!

	mut upgrader := new_coverage_upgrader(root, ['.v'])
	// the lcov data mentions only known.v
	upgrader.upgrade_lcov_entry(&LcovEntry{
		file_path:   known
		known_lines: [1]
	}) or { panic('expected upgrade to succeed') }

	entries := upgrader.cover_unknown_files() or { panic('expected cover_unknown_files to succeed') }

	// sorted, unknown .v files only; _test.v files are excluded
	assert entries.len == 2
	assert entries[0].file_path == os.join_path(root, 'b.v')
	assert entries[1].file_path == os.join_path(root, 'sub', 'c.v')
	for e in entries {
		assert e.known_lines == [1]
		assert e.covered_lines == []
		assert e.contents.len > 0
	}
}
