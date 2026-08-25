EMACS ?= emacs
BATCH = $(EMACS) -Q --batch -L . -L test
ELISP = rbx-core.el rbx-model.el rbx-ui.el rbx.el

.PHONY: test compile checkdoc check clean

test:
	$(BATCH) -l test/test-helper.el \
	  -l test/rbx-core-test.el \
	  -l test/rbx-model-test.el \
	  -l test/rbx-ui-test.el \
	  -l test/rbx-test.el \
	  -f ert-run-tests-batch-and-exit

compile:
	$(BATCH) -f batch-byte-compile $(ELISP)

checkdoc:
	$(BATCH) --eval "(progn (require 'checkdoc) (dolist (file command-line-args-left) (checkdoc-file file)))" $(ELISP)

check: clean test compile checkdoc clean

clean:
	find . -name '*.elc' -delete
