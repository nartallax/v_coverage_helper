module src

import flag
import os
import strconv
import v.vmod

// app_name is the human-readable application name, used in usage output.
const app_name = 'v coverage helper'

// CliArgs holds the parsed command line arguments.
pub struct CliArgs {
	lcov              string   // path to the lcov tracefile; '' means generate one by running the tests
	src               string   // path to the directory with source files
	v_file_extensions []string // extensions considered V source code files
	output            string   // output directory: HTML report, and coverage data when lcov is omitted
	sort              string   // overview sort order: 'path' or 'score'
	min_coverage      f64      // minimum total coverage percent; 0 disables the check
}

// app_version reads the version from v.mod.
// The file contents are embedded at compile time via @VMOD_FILE.
pub fn app_version() !string {
	manifest := vmod.decode(@VMOD_FILE) or {
		return error('failed to parse v.mod: ${err}')
	}
	return manifest.version
}

// parse_cli parses the given arguments (including the executable name) into
// CliArgs. Every option can also come from a VCH_* environment variable;
// a command line option takes precedence over the environment variable.
pub fn parse_cli(args []string) !CliArgs {
	mut fp := flag.new_flag_parser(args)
	fp.application(app_name)
	fp.version(app_version()!)
	fp.description('A helper tool for V language code coverage.')
	fp.skip_executable()
	fp.footer('Every option can also be given through an environment variable:\n' +
		'VCH_LCOV, VCH_SRC, VCH_V_FILE_EXTENSIONS, VCH_OUTPUT, VCH_SORT,\n' +
		'VCH_MIN_COVERAGE. A command line option takes precedence over the\n' +
		'environment variable.')
	// use a default instead of string_opt, so that --help/--version are handled
	// by finalize() before we complain about the missing flag
	lcov := fp.string('lcov', 0, '', 'path to the lcov coverage file; when omitted, the tests are run to generate one', val_desc: 'FILE')
	src_arg := fp.string('src', 0, '', 'path to the directory with the source files', val_desc: 'DIR')
	extensions_raw := fp.string('v_file_extensions', 0, '', 'comma-separated list of file extensions that are considered V source code files', val_desc: 'EXT,EXT,...')
	output := fp.string('output', 0, '', 'path to the output directory for the HTML report, and for the coverage data when --lcov is omitted', val_desc: 'DIR')
	sort := fp.string('sort', 0, '', 'sorting of files in the overview: "path", or "score" (lowest coverage first)', val_desc: 'path|score')
	min_coverage_raw := fp.string('min-coverage', 0, '', 'exit with an error when the total coverage is below this percentage', val_desc: 'PERCENT')
	fp.limit_free_args_to_exactly(0)!
	fp.finalize()!

	src_v := flag_or_env(src_arg, 'VCH_SRC', '')
	if src_v == '' {
		return error('parameter \'src\' not provided')
	}
	output_v := flag_or_env(output, 'VCH_OUTPUT', '')
	if output_v == '' {
		return error('parameter \'output\' not provided')
	}
	sort_v := flag_or_env(sort, 'VCH_SORT', 'path')
	if sort_v != 'path' && sort_v != 'score' {
		return error('invalid value \'${sort_v}\' for parameter \'sort\': expected "path" or "score"')
	}
	return CliArgs{
		lcov:              flag_or_env(lcov, 'VCH_LCOV', '')
		src:               src_v
		v_file_extensions: parse_extensions(flag_or_env(extensions_raw, 'VCH_V_FILE_EXTENSIONS', '.v'))
		output:            output_v
		sort:              sort_v
		min_coverage:      min_coverage_from(flag_or_env(min_coverage_raw, 'VCH_MIN_COVERAGE', ''))!
	}
}

// flag_or_env returns the flag value when given, the environment variable
// `env_name` when set, and `default_value` otherwise.
fn flag_or_env(flag_value string, env_name string, default_value string) string {
	if flag_value != '' {
		return flag_value
	}
	if env := os.getenv_opt(env_name) {
		if env != '' {
			return env
		}
	}
	return default_value
}

// min_coverage_from parses a minimum coverage percentage; '' disables the check.
fn min_coverage_from(raw string) !f64 {
	if raw == '' {
		return 0.0
	}
	value := strconv.atof64(raw, allow_extra_chars: false, allow_overflow: false) or {
		return error('invalid value \'${raw}\' for parameter \'min-coverage\': expected a percentage')
	}
	if value < 0.0 || value > 100.0 {
		return error('invalid value \'${value}\' for parameter \'min-coverage\': expected a percentage between 0 and 100')
	}
	return value
}

// parse_extensions splits a comma-separated extension list into extensions
// that each start with a dot; empty items are dropped.
fn parse_extensions(s string) []string {
	mut exts := []string{}
	for part in s.split(',') {
		mut e := part.trim(' \t')
		if e == '' {
			continue
		}
		if !e.starts_with('.') {
			e = '.${e}'
		}
		exts << e
	}
	return exts
}
