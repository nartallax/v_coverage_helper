# v_coverage_helper
A tool that helps with V language code coverage output.

It reads (or generates) an lcov tracefile, recovers functions that the
coverage generator dropped because they were never used, discovers source
files missing from the tracefile entirely, and renders a dark-themed HTML
report with an overview and per-file pages.

## Installation and usage

```
# Install as a V module from git:
v install --git https://github.com/nartallax/v_coverage_helper

# Recommended way of running the tool is with v tool, like this:
VCH_SRC=./src/ VCH_OUTPUT=./coverage/ v tool v_coverage_helper

#Every option can be given through an environment variable:
#`VCH_LCOV`, `VCH_SRC`, `VCH_V_FILE_EXTENSIONS`, `VCH_OUTPUT`, `VCH_SORT`,
#`VCH_MIN_COVERAGE`. A command line option takes precedence over the
#environment variable.

# Alternative way to run the tool - v run toolpath
# this way you can pass options directly instead of env variables:
alias vch='v run ~/.vmodules/v_coverage_helper'
vch --src . --output coverage --min-coverage 80
```
