.PHONY: test

# Runs the coverage helper on its own sources: runs the test suite with
# coverage instrumentation and writes the HTML report into coverage/.
test:
	v run src --src src --output coverage --min-coverage 75
