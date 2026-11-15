module main

import flag
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

// parse_cli parses the given arguments (including the executable name) into CliArgs.
pub fn parse_cli(args []string) !CliArgs {
	mut fp := flag.new_flag_parser(args)
	fp.application(app_name)
	fp.version(app_version()!)
	fp.description('A helper tool for V language code coverage.')
	fp.skip_executable()
	// use a default instead of string_opt, so that --help/--version are handled
	// by finalize() before we complain about the missing flag
	lcov := fp.string('lcov', 0, '', 'path to the lcov coverage file; when omitted, the tests are run to generate one', val_desc: 'FILE')
	src := fp.string('src', 0, '', 'path to the directory with the source files', val_desc: 'DIR')
	extensions_raw := fp.string('v_file_extensions', 0, '.v', 'comma-separated list of file extensions that are considered V source code files', val_desc: 'EXT,EXT,...')
	output := fp.string('output', 0, '', 'path to the output directory for the HTML report, and for the coverage data when --lcov is omitted', val_desc: 'DIR')
	sort := fp.string('sort', 0, 'path', 'sorting of files in the overview: "path", or "score" (lowest coverage first)', val_desc: 'path|score')
	min_coverage := fp.float('min-coverage', 0, 0.0, 'exit with an error when the total coverage is below this percentage', val_desc: 'PERCENT')
	fp.limit_free_args_to_exactly(0)!
	fp.finalize()!
	if src == '' {
		return error('parameter \'src\' not provided')
	}
	if output == '' {
		return error('parameter \'output\' not provided')
	}
	if sort != 'path' && sort != 'score' {
		return error('invalid value \'${sort}\' for parameter \'sort\': expected "path" or "score"')
	}
	if min_coverage < 0.0 || min_coverage > 100.0 {
		return error('invalid value \'${min_coverage}\' for parameter \'min-coverage\': expected a percentage between 0 and 100')
	}
	return CliArgs{
		lcov:              lcov
		src:               src
		v_file_extensions: parse_extensions(extensions_raw)
		output:            output
		sort:              sort
		min_coverage:      min_coverage
	}
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
