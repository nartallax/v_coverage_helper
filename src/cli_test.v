module main

fn test_parse_cli_defaults() ! {
	cli := parse_cli(['vch', '--lcov', 'a.lcov', '--src', 'src', '--output', 'out'])!
	assert cli.lcov == 'a.lcov'
	assert cli.src == 'src'
	assert cli.output == 'out'
	assert cli.sort == 'path'
	assert cli.v_file_extensions == ['.v']
}

fn test_parse_cli_lcov_is_optional() ! {
	cli := parse_cli(['vch', '--src', 'src', '--output', 'out'])!
	assert cli.lcov == ''
}

fn test_parse_cli_all_options() ! {
	cli := parse_cli(['vch', '--lcov', 'a.lcov', '--src', 'src', '--output', 'out', '--sort',
		'score', '--v_file_extensions', ' v , .vh '])!
	assert cli.sort == 'score'
	assert cli.v_file_extensions == ['.v', '.vh']
}

fn test_parse_cli_rejects_bad_sort() {
	if _ := parse_cli(['vch', '--lcov', 'a', '--src', 'b', '--output', 'c', '--sort', 'nope']) {
		panic('expected an error for an invalid --sort value')
	}
}

fn test_parse_cli_rejects_missing_output() {
	if _ := parse_cli(['vch', '--lcov', 'a', '--src', 'b']) {
		panic('expected an error when --output is missing')
	}
}

fn test_parse_extensions_normalizes() {
	assert parse_extensions('.v') == ['.v']
	assert parse_extensions('v,.vh,,') == ['.v', '.vh']
	assert parse_extensions('') == []
}

fn test_parse_cli_min_coverage() ! {
	cli := parse_cli(['vch', '--src', 'src', '--output', 'out', '--min-coverage', '80.5'])!
	assert cli.min_coverage == 80.5
	// 0 (the default) disables the check
	cli2 := parse_cli(['vch', '--src', 'src', '--output', 'out'])!
	assert cli2.min_coverage == 0.0
}

fn test_parse_cli_rejects_bad_min_coverage() {
	if _ := parse_cli(['vch', '--src', 'src', '--output', 'out', '--min-coverage', '101']) {
		panic('expected an error for a min-coverage above 100')
	}
	if _ := parse_cli(['vch', '--src', 'src', '--output', 'out', '--min-coverage', '-1']) {
		panic('expected an error for a negative min-coverage')
	}
}
