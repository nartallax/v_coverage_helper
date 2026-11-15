module main

import os

fn main() {
	cli := parse_cli(os.args) or {
		eprintln('error: ${err}')
		eprintln('usage: ${app_name} --src <path> --output <path> [--lcov <path>]')
		exit(1)
	}
	generate_report(cli) or {
		eprintln('error: ${err}')
		exit(1)
	}
}

// generate_report runs the whole pipeline: obtain an lcov tracefile (from
// --lcov, or by running the tests with coverage instrumentation), upgrade
// its entries with the actual sources, discover source files missing from
// the tracefile, and render the HTML report.
fn generate_report(cli CliArgs) ! {
	lcov_path := if cli.lcov != '' { cli.lcov } else { run_coverage(cli.output, cli.src)! }
	mut parser := new_lcov_parser(lcov_path, cli.src, cli.v_file_extensions)!
	defer {
		parser.close()
	}
	mut upgrader := new_coverage_upgrader(cli.src, cli.v_file_extensions)
	mut entries := []CoverageEntry{}
	for {
		entry := parser.get_next() or { break }
		upgraded := upgrader.upgrade_lcov_entry(entry) or {
			eprintln('warning: skipping ${entry.file_path}: ${err}')
			continue
		}
		entries << upgraded
	}
	entries << upgrader.cover_unknown_files()!
	render_html(entries, cli.output, RenderSettings{
		sort_by: if cli.sort == 'score' { .score } else { .path }
		src_dir: cli.src
	})!
	total := total_percent(entries)
	index_path := os.join_path(os.real_path(cli.output), 'index.html')
	println('total coverage: ${percent_str(total)}%')
	println('coverage report written to file://${index_path}')
	if cli.min_coverage > 0.0 && total < cli.min_coverage {
		return error('total coverage ${percent_str(total)}% is below the required ${percent_str(cli.min_coverage)}%')
	}
}

// run_coverage runs the tests of `src_dir` with coverage instrumentation
// into `output_dir`, converts the coverage data into an lcov tracefile and
// returns its path.
fn run_coverage(output_dir string, src_dir string) !string {
	if !os.exists(output_dir) {
		os.mkdir_all(output_dir)!
	}
	println('running tests for ${src_dir}...')
	res := os.exec(['v', '-no-skip-unused', '-coverage', output_dir, 'test', src_dir])
	if res.exit_code != 0 {
		return error('v test failed:\n${res.output}')
	}
	if res.output.trim_space() != '' {
		println(res.output.trim_space())
	}
	println('converting coverage data to lcov...')
	lcov_path := os.join_path(output_dir, 'lcov.info')
	res2 := os.exec(['v', 'cover', output_dir, '--lcov', lcov_path])
	if res2.exit_code != 0 {
		return error('v cover failed:\n${res2.output}')
	}
	return lcov_path
}
