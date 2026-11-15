# V coverage helper

A tool that helps with V language code coverage output.  

Because normal V coverage output is too raw; it's much better in html, just like llvm-cov does it.  

Also normal coverage instrumentation won't report unused functions/files as not covered; this tool handles it - unused functions and files are listed as uncovered.

## Installation and usage

```
# Install as a V module from git:
v install --git https://github.com/nartallax/v_coverage_helper

# Recommended way of running the tool is with v tool, like this:
# this will run `v test ./src/` and then process coverage data into an HTML report
VCH_SRC=./src/ VCH_OUTPUT=./coverage/ v tool v_coverage_helper

# Every option can be given through an environment variable:
# `VCH_LCOV`, `VCH_SRC`, `VCH_V_FILE_EXTENSIONS`, `VCH_OUTPUT`, `VCH_SORT`,
# `VCH_MIN_COVERAGE`. A command line option takes precedence over the
# environment variable.
```
