module src

import os

fn write_sample_lcov(extra_content string) !string {
	path := os.join_path(os.temp_dir(), 'vch_lcov_test_${os.getpid()}.lcov')
	os.write_file(path, [
		'TN:',
		'SF:src/main.v',
		'FN:3,main',
		'FNDA:1,main',
		'FNF:1',
		'FNH:1',
		'BRDA:4,0,0,1',
		'BRF:1',
		'BRH:1',
		'DA:3,1',
		'DA:4,0',
		'DA:5,2',
		'LF:3',
		'LH:2',
		'end_of_record',
		'TN:',
		'SF:src/cli.v',
		'DA:8,0',
		'DA:9,3',
		'end_of_record',
	].join('\n') + '\n' + extra_content)!
	return path
}

fn test_get_next_returns_entries_then_none() ! {
	path := write_sample_lcov('')!
	defer {
		os.rm(path) or {}
	}
	mut parser := new_lcov_parser(path, os.temp_dir(), ['.v'])!
	defer {
		parser.close()
	}

	first := parser.get_next() or { panic('expected first entry') }
	// relative SF: paths are resolved against the tracefile's directory
	assert first.file_path == '${os.temp_dir()}/src/main.v'
	// known_lines holds every DA-mentioned line, covered or not
	assert first.known_lines == [3, 4, 5]
	// only lines with a non-zero execution count are reported as covered
	assert first.covered_lines == [3, 5]

	second := parser.get_next() or { panic('expected second entry') }
	assert second.file_path == '${os.temp_dir()}/src/cli.v'
	assert second.known_lines == [8, 9]
	assert second.covered_lines == [9]

	if _ := parser.get_next() {
		panic('expected none after the last record')
	}
}

fn test_empty_filter_returns_all_entries() ! {
	path := write_sample_lcov('')!
	defer {
		os.rm(path) or {}
	}
	mut parser := new_lcov_parser(path, '', [])!
	defer {
		parser.close()
	}

	mut entry := parser.get_next() or { panic('expected first entry') }
	assert entry.file_path == '${os.temp_dir()}/src/main.v'
	entry = parser.get_next() or { panic('expected second entry') }
	assert entry.file_path == '${os.temp_dir()}/src/cli.v'
	if _ := parser.get_next() {
		panic('expected none after the last record')
	}
}

fn test_get_next_skips_junk_between_records() ! {
	path := write_sample_lcov('TN:\nsome stray line\n')!
	defer {
		os.rm(path) or {}
	}
	mut parser := new_lcov_parser(path, os.temp_dir(), ['.v'])!
	defer {
		parser.close()
	}

	mut entry := parser.get_next() or { panic('expected first entry') }
	assert entry.file_path == '${os.temp_dir()}/src/main.v'
	assert parser.get_next() or { panic('expected second entry') }.file_path == '${os.temp_dir()}/src/cli.v'
	// trailing junk without an SF: line yields none
	if _ := parser.get_next() {
		panic('expected none for trailing junk')
	}
}

fn test_get_next_handles_crlf() ! {
	path := os.join_path(os.temp_dir(), 'vch_lcov_crlf_${os.getpid()}.lcov')
	os.write_file(path, 'SF:src/a.v\r\nDA:1,1\r\nDA:2,0\r\nend_of_record\r\n')!
	defer {
		os.rm(path) or {}
	}
	mut parser := new_lcov_parser(path, os.temp_dir(), ['.v'])!
	defer {
		parser.close()
	}

	mut entry := parser.get_next() or { panic('expected entry') }
	assert entry.file_path == '${os.temp_dir()}/src/a.v'
	assert entry.known_lines == [1, 2]
	assert entry.covered_lines == [1]
}

fn test_filter_skips_entries_outside_allowed_dir() ! {
	tmp := os.temp_dir()
	path := os.join_path(tmp, 'vch_lcov_filter_${os.getpid()}.lcov')
	os.write_file(path, [
		'SF:sub/a.v', // inside the allowed dir
		'DA:1,1',
		'end_of_record',
		'SF:subx/b.v', // sibling whose name merely starts with "sub"
		'DA:2,1',
		'end_of_record',
		'SF:/etc/passwd', // absolute path outside the allowed dir
		'DA:3,1',
		'end_of_record',
		'SF:../outside.v', // resolves above the allowed dir
		'DA:4,1',
		'end_of_record',
		'SF:sub/deep/c.v', // nested deeper inside the allowed dir
		'DA:5,1',
		'end_of_record',
	].join('\n') + '\n')!
	defer {
		os.rm(path) or {}
	}

	// a trailing slash on the allowed dir must not change the outcome
	mut parser := new_lcov_parser(path, '${tmp}/sub/', ['.v'])!
	defer {
		parser.close()
	}

	mut entry := parser.get_next() or { panic('expected first entry') }
	assert entry.file_path == '${tmp}/sub/a.v'
	entry = parser.get_next() or { panic('expected second entry') }
	assert entry.file_path == '${tmp}/sub/deep/c.v'
	if _ := parser.get_next() {
		panic('expected none: all other records are outside the allowed dir')
	}
}

fn test_filter_skips_entries_without_known_extension() ! {
	tmp := os.temp_dir()
	path := os.join_path(tmp, 'vch_lcov_ext_${os.getpid()}.lcov')
	os.write_file(path, [
		'SF:src/main.v', // has an accepted extension
		'DA:1,1',
		'end_of_record',
		'SF:notes.txt', // wrong extension
		'DA:2,1',
		'end_of_record',
		'SF:sub/lib.vv', // wrong extension (.vv, not .v)
		'DA:3,1',
		'end_of_record',
		'SF:src/cli.v', // accepted, comes after the dropped ones
		'DA:4,1',
		'end_of_record',
	].join('\n') + '\n')!
	defer {
		os.rm(path) or {}
	}

	mut parser := new_lcov_parser(path, '', ['.v'])!
	defer {
		parser.close()
	}

	mut entry := parser.get_next() or { panic('expected first entry') }
	assert entry.file_path == '${tmp}/src/main.v'
	entry = parser.get_next() or { panic('expected second entry') }
	assert entry.file_path == '${tmp}/src/cli.v'
	if _ := parser.get_next() {
		panic('expected none: entries with other extensions are skipped')
	}
}

fn test_absolute_sf_path_is_kept_as_is() ! {
	path := os.join_path(os.temp_dir(), 'vch_lcov_abs_${os.getpid()}.lcov')
	os.write_file(path, 'SF:/abs/path/a.v\nDA:1,1\nend_of_record\n')!
	defer {
		os.rm(path) or {}
	}
	mut parser := new_lcov_parser(path, '', ['.v'])!
	defer {
		parser.close()
	}

	entry := parser.get_next() or { panic('expected entry') }
	assert entry.file_path == '/abs/path/a.v'
}

fn test_test_files_are_skipped() ! {
	path := os.join_path(os.temp_dir(), 'vch_lcov_testfiles_${os.getpid()}.lcov')
	os.write_file(path, [
		'SF:src/app_test.v', // test file: skipped
		'DA:1,1',
		'end_of_record',
		'SF:src/app.v', // regular file: kept
		'DA:1,1',
		'end_of_record',
	].join('\n') + '\n')!
	defer {
		os.rm(path) or {}
	}
	mut parser := new_lcov_parser(path, '', ['.v'])!
	defer {
		parser.close()
	}

	entry := parser.get_next() or { panic('expected entry') }
	assert entry.file_path == '${os.temp_dir()}/src/app.v'
	if _ := parser.get_next() {
		panic('expected none: test files are skipped')
	}
}
