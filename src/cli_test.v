module src

import os

const vch_env_names = ['VCH_LCOV', 'VCH_SRC', 'VCH_V_FILE_EXTENSIONS', 'VCH_OUTPUT', 'VCH_SORT',
	'VCH_MIN_COVERAGE']

// clear_vch_env unsets all VCH_* environment variables, so that parse_cli
// tests are independent of the environment the test binary runs in, and
// returns the previous values for restore_vch_env.
fn clear_vch_env() map[string]string {
	mut saved := map[string]string{}
	for name in vch_env_names {
		if value := os.getenv_opt(name) {
			saved[name] = value
			os.unsetenv(name)
		}
	}
	return saved
}

// restore_vch_env restores the variables saved by clear_vch_env.
fn restore_vch_env(saved map[string]string) {
	for name, value in saved {
		os.setenv(name, value, true)
	}
}

fn test_parse_cli_defaults() ! {
	saved_env := clear_vch_env()
	defer {
		restore_vch_env(saved_env)
	}
	cli := parse_cli(['vch', '--lcov', 'a.lcov', '--src', 'src', '--output', 'out'])!
	assert cli.lcov == 'a.lcov'
	assert cli.src == 'src'
	assert cli.output == 'out'
	assert cli.sort == 'path'
	assert cli.v_file_extensions == ['.v']
}

fn test_parse_cli_lcov_is_optional() ! {
	saved_env := clear_vch_env()
	defer {
		restore_vch_env(saved_env)
	}
	cli := parse_cli(['vch', '--src', 'src', '--output', 'out'])!
	assert cli.lcov == ''
}

fn test_parse_cli_all_options() ! {
	saved_env := clear_vch_env()
	defer {
		restore_vch_env(saved_env)
	}
	cli := parse_cli(['vch', '--lcov', 'a.lcov', '--src', 'src', '--output', 'out', '--sort',
		'score', '--v_file_extensions', ' v , .vh '])!
	assert cli.sort == 'score'
	assert cli.v_file_extensions == ['.v', '.vh']
}

fn test_parse_cli_rejects_bad_sort() {
	saved_env := clear_vch_env()
	defer {
		restore_vch_env(saved_env)
	}
	if _ := parse_cli(['vch', '--lcov', 'a', '--src', 'b', '--output', 'c', '--sort', 'nope']) {
		panic('expected an error for an invalid --sort value')
	}
}

fn test_parse_cli_rejects_missing_output() {
	saved_env := clear_vch_env()
	defer {
		restore_vch_env(saved_env)
	}
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
	saved_env := clear_vch_env()
	defer {
		restore_vch_env(saved_env)
	}
	cli := parse_cli(['vch', '--src', 'src', '--output', 'out', '--min-coverage', '80.5'])!
	assert cli.min_coverage == 80.5
	// 0 (the default) disables the check
	cli2 := parse_cli(['vch', '--src', 'src', '--output', 'out'])!
	assert cli2.min_coverage == 0.0
}

fn test_parse_cli_rejects_bad_min_coverage() {
	saved_env := clear_vch_env()
	defer {
		restore_vch_env(saved_env)
	}
	if _ := parse_cli(['vch', '--src', 'src', '--output', 'out', '--min-coverage', '101']) {
		panic('expected an error for a min-coverage above 100')
	}
	if _ := parse_cli(['vch', '--src', 'src', '--output', 'out', '--min-coverage', '-1']) {
		panic('expected an error for a negative min-coverage')
	}
}

fn test_parse_cli_env_vars() ! {
	os.setenv('VCH_LCOV', 'env.lcov', true)
	os.setenv('VCH_SRC', 'env_src', true)
	os.setenv('VCH_V_FILE_EXTENSIONS', '.v,.vh', true)
	os.setenv('VCH_OUTPUT', 'env_out', true)
	os.setenv('VCH_SORT', 'score', true)
	os.setenv('VCH_MIN_COVERAGE', '55.5', true)
	defer {
		os.unsetenv('VCH_LCOV')
		os.unsetenv('VCH_SRC')
		os.unsetenv('VCH_V_FILE_EXTENSIONS')
		os.unsetenv('VCH_OUTPUT')
		os.unsetenv('VCH_SORT')
		os.unsetenv('VCH_MIN_COVERAGE')
	}

	// no flags at all: everything comes from the environment
	cli := parse_cli(['vch'])!
	assert cli.lcov == 'env.lcov'
	assert cli.src == 'env_src'
	assert cli.v_file_extensions == ['.v', '.vh']
	assert cli.output == 'env_out'
	assert cli.sort == 'score'
	assert cli.min_coverage == 55.5

	// a command line option takes precedence over the environment variable
	cli2 := parse_cli(['vch', '--src', 'flag_src'])!
	assert cli2.src == 'flag_src'
	assert cli2.output == 'env_out'
}

fn test_parse_cli_rejects_bad_env_min_coverage() {
	os.setenv('VCH_SRC', 's', true)
	os.setenv('VCH_OUTPUT', 'o', true)
	os.setenv('VCH_MIN_COVERAGE', 'not-a-number', true)
	defer {
		os.unsetenv('VCH_SRC')
		os.unsetenv('VCH_OUTPUT')
		os.unsetenv('VCH_MIN_COVERAGE')
	}
	if _ := parse_cli(['vch']) {
		panic('expected an error for a non-numeric VCH_MIN_COVERAGE')
	}
}
