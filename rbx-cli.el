;;; rbx-cli.el --- The rbx commands rbx.el may run -*- lexical-binding: t; -*-

;; Copyright (C) 2026 rbx.el contributors

;; Author: rbx.el contributors
;; Maintainer: rbx.el contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: tools, languages
;; URL: https://github.com/luishgh/rbx.el

;;; Commentary:

;; rbx.el reads what rbx leaves on disk and leaves running rbx to the
;; terminal.  The exceptions are commands that meet all of these:
;;
;; - they write nothing to the package or to rbx's caches,
;; - they print structured output, and
;; - rbx means them for an editor to call.
;;
;; Today those are `rbx vars' (statement variable hints) and `rbx
;; time-inspect' without its edit flags (the time profile view).  Both are
;; what rbx's own VS Code extension calls.  Every invocation goes through
;; `rbx-cli-run', which refuses anything else.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'rbx-core)

(defcustom rbx-program "rbx"
  "Program used to invoke rbx.

rbx.el only runs the few rbx commands meant for an editor to call: `rbx
vars' for statement variable hints and `rbx time-inspect' for the time
profile view.  Both are read-only by rbx's own design, safe to call while a
package is being edited.  See `rbx-cli-run'."
  :type 'string
  :group 'rbx)

(defconst rbx-cli--allowed-commands '("vars" "time-inspect")
  "The rbx subcommands `rbx-cli-run' may start.")

(defconst rbx-cli--time-inspect-edit-flags
  '("--set" "--revert" "--memory" "--inherit" "--no-inherit")
  "Flags that make `rbx time-inspect' answer with an edited profile.
It still writes nothing, but an edit is out of scope for a read-only view.")

(defun rbx-cli--refusal (args)
  "Return why ARGS may not be run, or nil when they may."
  (let ((command (car args)))
    (cond
     ((not (member command rbx-cli--allowed-commands))
      (format "rbx.el does not run `rbx %s'; run it in your terminal"
              (string-join args " ")))
     ((and (equal command "time-inspect")
           (seq-some (lambda (arg)
                       (seq-some (lambda (flag)
                                   (or (equal arg flag)
                                       (string-prefix-p (concat flag "=") arg)))
                                 rbx-cli--time-inspect-edit-flags))
                     (cdr args)))
      (format "rbx.el does not edit limits profiles through `rbx %s'"
              (string-join args " "))))))

(defun rbx-cli--program (root)
  "Return the `rbx-program' that applies to the package at ROOT.

A buffer-local value wins when the current buffer lives under ROOT.
Otherwise the value is read as ROOT's directory-local variables set it, since
callers often run from a process sentinel in an unrelated buffer.  The option
is deliberately not `safe-local-variable': a program path can run arbitrary
code, so Emacs prompts before honouring a directory-local one."
  (if (and (local-variable-p 'rbx-program)
           (file-in-directory-p default-directory root))
      rbx-program
    (with-temp-buffer
      (setq default-directory (file-name-as-directory root))
      (hack-dir-local-variables-non-file-buffer)
      rbx-program)))

(defun rbx-cli-run (root args input callback &optional timeout what)
  "Run rbx with ARGS in ROOT, writing INPUT to stdin, then call CALLBACK.

ARGS must name an allowlisted, read-only command (see the commentary of
this file); anything else signals an error without starting a process.
Resolves `rbx-program' via `rbx-resolve-executable' first; when it cannot
be found at all, warns once and calls CALLBACK as though the process had
failed.  WHAT names the feature that needs rbx, for that warning.
TIMEOUT and CALLBACK are as for `rbx-run-process'."
  (when-let* ((refusal (rbx-cli--refusal args)))
    (error "%s" refusal))
  (let* ((configured (rbx-cli--program root))
         (program (rbx-resolve-executable configured "rbx" root)))
    (if (null program)
        (progn
          (rbx--warn-once
           'rbx
           (format
            "rbx.el could not find rbx (checked `rbx-program' (%s), PATH, \
and a login shell); %s are unavailable until it is installed or \
`rbx-program' is set."
            configured (or what "statement variable hints")))
          (funcall callback "" "" nil))
      (rbx-run-process root program args input callback timeout))))

(defconst rbx-cli--ansi-escape-regexp "\e\\[[0-9;?]*[ -/]*[@-~]"
  "Regexp matching one ANSI/VT100 escape sequence.")

(defun rbx-cli-parse-json-object (text)
  "Return the first JSON object found in TEXT, trying each `{' in turn.

rbx's own noise -- a shell wrapper, a deprecation warning, Rich's
cursor-restore escape on exit -- can print before or around the payload,
so only a syntax error moves on to the next brace; a value that parses
but has the wrong shape is rbx's actual answer and is returned as-is.
Objects are alists keyed by symbols, arrays lists, JSON null nil and false
`:false'."
  (let ((stripped (replace-regexp-in-string
                   rbx-cli--ansi-escape-regexp "" text))
        (start 0)
        result)
    (while (and (not result) (setq start (string-search "{" stripped start)))
      (condition-case nil
          (setq result (list (json-parse-string (substring stripped start)
                                                :object-type 'alist
                                                :array-type 'list
                                                :null-object nil
                                                :false-object :false)))
        (error nil))
      (setq start (1+ start)))
    (car result)))

(provide 'rbx-cli)
;;; rbx-cli.el ends here
