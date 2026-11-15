module main

import os

// max_line_len is the read buffer size for a single lcov line.
const max_line_len = 4096

// LcovEntry holds the parsed data of one lcov record, i.e. the coverage
// information for a single source file.
pub struct LcovEntry {
pub:
	file_path     string // absolute source file path, resolved from the SF: line
	known_lines   []int  // all line numbers mentioned in the record
	covered_lines []int  // line numbers with a non-zero execution count
}

// LcovParser reads an lcov tracefile record by record.
// Only records for files within `allowed_dir` that end with one of
// `extensions` are returned; all others are skipped. An empty `allowed_dir`
// disables the directory filter, an empty `extensions` disables the
// extension filter.
pub struct LcovParser {
mut:
	file        os.File
	buf         []u8    = []u8{len: max_line_len}
	lcov_dir    string // base dir for relative SF: paths in the tracefile
	allowed_dir string // absolute, normalized; '' means no filtering
	extensions  []string
}

// new_lcov_parser opens the lcov tracefile at `path` for reading and
// restricts the returned entries to files within `allowed_dir` ending with
// one of `extensions`. A relative `allowed_dir` is resolved against the
// current directory.
pub fn new_lcov_parser(path string, allowed_dir string, extensions []string) !LcovParser {
	return LcovParser{
		file:        os.open(path)!
		lcov_dir:    to_abs(os.getwd(), os.dir(path))
		allowed_dir: if allowed_dir == '' { '' } else { to_abs(os.getwd(), allowed_dir) }
		extensions:  extensions
	}
}

// close closes the underlying file.
pub fn (mut p LcovParser) close() {
	p.file.close()
}

// get_next returns the next record from the tracefile, i.e. the lines
// belonging to one source file, parsed into an LcovEntry.
// Records for files outside the allowed directory or without one of the
// accepted extensions are skipped. The entry's file_path is the resolved
// absolute path of the SF: value.
// It returns none once the whole file has been read.
// Unknown line kinds (TN, FN, FNDA, BRDA, LF, LH, ...) are ignored.
pub fn (mut p LcovParser) get_next() ?LcovEntry {
	for {
		rec := p.read_record()
		if rec.file_path != '' && p.is_within(rec.file_path) {
			full := to_abs(p.lcov_dir, rec.file_path)
			if p.has_known_extension(full) && !is_test_file(full, p.extensions) {
				return LcovEntry{
					file_path:     full
					known_lines:   rec.known_lines
					covered_lines: rec.covered_lines
				}
			}
		}
		if rec.eof {
			return none
		}
		// junk chunk or a filtered-out record: keep reading
	}
}

// is_test_file reports whether `path` is a test file, i.e. ends with
// `_test` plus one of the given extensions (e.g. `foo_test.v`).
fn is_test_file(path string, extensions []string) bool {
	return extensions.any(path.ends_with('_test${it}'))
}

// RawRecord is the unparsed-filter result of reading one lcov record.
struct RawRecord {
mut:
	file_path     string
	known_lines   []int
	covered_lines []int
	eof           bool // true when the tracefile ended while reading this record
}

// read_record reads lines up to and including the next end_of_record
// (or up to the end of the file) and returns the collected data.
// Unknown line kinds (TN, FN, FNDA, BRDA, LF, LH, ...) are ignored.
fn (mut p LcovParser) read_record() RawRecord {
	mut rec := RawRecord{}
	for {
		line := p.read_line() or {
			rec.eof = true
			break
		}
		if line == '' {
			continue
		}
		if line.starts_with('SF:') {
			rec.file_path = line[3..]
		} else if line.starts_with('DA:') {
			// DA:<line>,<execution count>[,<checksum>]
			parts := line[3..].split(',')
			if parts.len < 2 {
				continue
			}
			rec.known_lines << parts[0].int()
			if parts[1].int() > 0 {
				rec.covered_lines << parts[0].int()
			}
		} else if line == 'end_of_record' {
			break
		}
	}
	return rec
}

// is_within reports whether `path` lies inside the allowed directory.
fn (p &LcovParser) is_within(path string) bool {
	if p.allowed_dir == '' {
		return true
	}
	// relative SF: paths are resolved against the tracefile's directory
	full := to_abs(p.lcov_dir, path)
	return full == p.allowed_dir || full.starts_with('${p.allowed_dir}/')
}

// has_known_extension reports whether `path` ends with one of the accepted
// file extensions.
fn (p &LcovParser) has_known_extension(path string) bool {
	if p.extensions.len == 0 {
		return true
	}
	return p.extensions.any(path.ends_with(it))
}

// to_abs returns `path` with '/' separators, made absolute by resolving
// it against `base` when it is relative, and without a trailing slash.
fn to_abs(base string, path string) string {
	mut p := path.replace('\\', '/')
	if p.len > 1 && p.ends_with('/') {
		p = p[..p.len - 1]
	}
	if !p.starts_with('/') {
		p = '${base}/${p}'
	}
	return os.norm_path(p)
}

// read_line returns the next line without its line ending, or none at EOF.
fn (mut p LcovParser) read_line() ?string {
	n := p.file.read_bytes_with_newline(mut p.buf) or { return none }
	if n == 0 {
		return none
	}
	mut s := p.buf[..n].bytestr()
	if s.ends_with('\n') {
		s = s[..s.len - 1]
	}
	if s.ends_with('\r') {
		s = s[..s.len - 1]
	}
	return s
}
