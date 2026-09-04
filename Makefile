EMACS ?= emacs
BATCH = $(EMACS) -Q --batch -L . -L test
ELISP = rbx-core.el rbx-model.el rbx-statement.el rbx-ui.el rbx.el

.PHONY: test compile checkdoc package-lint check clean

test:
	$(BATCH) -l test/test-helper.el \
	  -l test/rbx-core-test.el \
	  -l test/rbx-model-test.el \
	  -l test/rbx-statement-test.el \
	  -l test/rbx-ui-test.el \
	  -l test/rbx-test.el \
	  -f ert-run-tests-batch-and-exit

compile:
	$(BATCH) -f batch-byte-compile $(ELISP)

checkdoc:
	$(BATCH) --eval "(progn (require 'checkdoc) (dolist (file command-line-args-left) (checkdoc-file file)))" $(ELISP)

package-lint:
	$(BATCH) -l test/package-lint-helper.el -l package-lint \
	  -f package-lint-batch-and-exit rbx.el

check: clean test compile checkdoc package-lint
	$(MAKE) clean

clean:
	find . -name '*.elc' -delete
