;;; rbx-statement.el --- Statement variable hints for rbx -*- lexical-binding: t; -*-

;; Copyright (C) 2026 rbx.el contributors

;; Author: rbx.el contributors
;; Maintainer: rbx.el contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: tools, languages
;; URL: https://github.com/luishgh/rbx.el

;;; Commentary:

;; Show what each `\VAR{...}' reference in an rbx statement expands to.
;;
;; Unlike the rest of this package, this library is not a pure reader: `rbx
;; vars' and `rbx vars --render' are read-only by rbx's own design (see
;; `rbx-program') and exist specifically for a live editor to call, so this
;; is the one place rbx.el invokes rbx.  The grammar this file scans for and
;; the CLI protocol it speaks mirror rbx's own VS Code extension
;; (`vscode/src/rbx/statementVars.ts', `rbx/box/cli/commands/vars_cmd.py').

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'rbx-core)

(defcustom rbx-program "rbx"
  "Program used to invoke rbx for statement variable hints.

This is the sole exception to this package's normal rule of never invoking
rbx: `rbx vars' and `rbx vars --render' are read-only and idempotent by
rbx's own design, safe to call while a package is being edited."
  :type 'string
  :group 'rbx)

(cl-defstruct (rbx-statement-vars-payload
               (:constructor rbx-statement-vars-payload-create))
  "The vars rbx reports for a package.

VARS is the package's own resolved vars, an alist of dotted name to
display string.  GROUPS is an alist of group name to such an alist, one
per declared testcase group."
  vars groups)

(cl-defstruct (rbx-statement-var-ref (:constructor rbx-statement-var-ref-create))
  "One resolvable `\\VAR{...}' reference found in a statement buffer.

START and END bound the whole occurrence, including its delimiters.  GROUP
is the referenced testcase group, or nil for a package-root reference.
EXPRESSION is the canonical name-plus-filter-pipeline string, doubling as
the `rbx vars --render' request line and its cache key.  FILTERED marks
whether a render is needed; when nil, TEXT already holds the display
value."
  start end group expression filtered text)

(defun rbx-statement--backslashes-before (pos)
  "Return how many consecutive backslash characters precede buffer POS."
  (let ((count 0) (cursor (1- pos)))
    (while (and (>= cursor (point-min)) (eq (char-after cursor) ?\\))
      (setq count (1+ count) cursor (1- cursor)))
    count))

(defun rbx-statement--escaped-p (pos)
  "Return non-nil when the backslash at POS is itself escaped."
  (cl-oddp (rbx-statement--backslashes-before pos)))

(defun rbx-statement--commented-p (pos)
  "Return non-nil when POS lies after an unescaped `%' earlier on its line."
  (save-excursion
    (goto-char pos)
    (let ((line-start (line-beginning-position))
          found)
      (goto-char line-start)
      (while (and (not found) (< (point) pos))
        (when (and (eq (char-after (point)) ?%)
                   (cl-evenp (rbx-statement--backslashes-before (point))))
          (setq found t))
        (forward-char 1))
      found)))

(defconst rbx-statement--occurrence-regexp "\\\\VAR{\\([^}]*\\)}"
  "Regexp matching one `\\VAR{...}' occurrence.")

(defconst rbx-statement--group-reference-regexp
  (concat "\\`problem\\.groups"
          "\\(?:\\.\\([A-Za-z0-9][A-Za-z0-9_-]*\\)"
          "\\|\\[[ \t]*\\(['\"]\\)\\([A-Za-z0-9][A-Za-z0-9_-]*\\)\\2[ \t]*\\]\\)"
          "\\.\\([^z-a]*\\)\\'")
  "Regexp matching a `problem.groups.NAME...' or bracket-form reference.

Group 1 or group 3 names the referenced group, whichever form matched;
group 4 is the remainder of the reference.")

(defconst rbx-statement--foreign-scope-regexp
  "\\`\\(?:vars\\.\\)?\\(?:g\\|p\\|problem\\|contest\\|groups\\)\\."
  "Regexp matching a reference scope this package cannot resolve.

Covers a loop-bound alias (`g'/`p'), the rest of `problem.', and `contest'
and `groups' referenced directly: every one of those needs either a
per-iteration value or vars this package has never parsed, so a hint would
have to lie, and an absent hint never does.")

(defconst rbx-statement--reference-regexp
  (concat "\\`\\([A-Za-z_][A-Za-z0-9_]*\\(?:\\.[A-Za-z_][A-Za-z0-9_]*\\)*\\)"
          "[ \t\n]*\\(|[^z-a]*\\)?\\'")
  "Regexp matching a dotted variable name and an optional filter pipeline.")

(defun rbx-statement--classify (inner)
  "Classify trimmed `\\VAR{...}' content INNER.

Return a (GROUP . REST) cons, GROUP nil for a package-root reference, or
nil when INNER's scope cannot be resolved."
  (cond
   ((string-match rbx-statement--group-reference-regexp inner)
    (cons (or (match-string 1 inner) (match-string 3 inner))
          (match-string 4 inner)))
   ((string-match rbx-statement--foreign-scope-regexp inner) nil)
   (t (cons nil inner))))

(defun rbx-statement--canonicalize (name pipeline)
  "Return the canonical NAME plus PIPELINE expression, or nil to decline.

Declines an empty filter stage (a half-typed pipeline, e.g. \"n |\" or
\"n ||sci\") and a pipeline whose canonical form still holds a newline,
since both cross to `rbx vars --render' as one line of stdin."
  (if (null pipeline)
      name
    (let* ((stages (string-trim pipeline))
           (quoted (string-match-p "['\"]" stages))
           (parts (split-string stages "|")))
      (unless (and (not quoted)
                   (seq-some (lambda (part) (string-empty-p (string-trim part)))
                             (cdr parts)))
        (let* ((spaced (if quoted
                            stages
                          (string-trim
                           (replace-regexp-in-string
                            "[ \t\n]*|[ \t\n]*" " | " stages))))
               (expression (concat name " " spaced)))
          (unless (string-match-p "\n" expression)
            expression))))))

(defun rbx-statement--vars-for-group (payload group)
  "Return PAYLOAD's vars alist for GROUP, or nil when GROUP is unknown."
  (cdr (assoc group (rbx-statement-vars-payload-groups payload))))

(defun rbx-statement--lookup (vars name)
  "Return NAME's value in VARS, or nil when absent."
  (cdr (assoc name vars)))

(defun rbx-statement--build-ref (start end inner payload)
  "Return an `rbx-statement-var-ref' for INNER, or nil to decline.

START and END bound the whole `\\VAR{...}' occurrence; PAYLOAD resolves
scopes and names."
  (let ((scoped (rbx-statement--classify inner)))
    (when scoped
      (let* ((group (car scoped))
             (rest (string-trim (cdr scoped)))
             (vars (if group
                       (rbx-statement--vars-for-group payload group)
                     (rbx-statement-vars-payload-vars payload))))
        (when (string-match rbx-statement--reference-regexp rest)
          (let* ((name (replace-regexp-in-string
                        "\\`vars\\." "" (match-string 1 rest)))
                 (pipeline (match-string 2 rest))
                 (value (rbx-statement--lookup vars name)))
            (when value
              (let ((canonical (rbx-statement--canonicalize name pipeline)))
                (when canonical
                  (rbx-statement-var-ref-create
                   :start start :end end :group group
                   :expression (if group (concat group "\t" canonical) canonical)
                   :filtered (and pipeline t)
                   :text (unless pipeline value)))))))))))

(defun rbx-statement-scan-buffer (payload)
  "Return `rbx-statement-var-ref' values for `\\VAR{...}' refs in this buffer.

PAYLOAD is an `rbx-statement-vars-payload'.  Only a reference whose scope
and base name PAYLOAD can answer is returned; every other case -- an
escaped or commented occurrence, a dynamic or foreign scope, an
unresolvable name, or an unusable filter pipeline -- is silently dropped."
  (let (refs)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward rbx-statement--occurrence-regexp nil t)
        (let ((start (match-beginning 0))
              (end (match-end 0))
              (inner (string-trim (match-string 1))))
          (unless (or (rbx-statement--escaped-p start)
                      (rbx-statement--commented-p start))
            (when-let ((ref (rbx-statement--build-ref start end inner payload)))
              (push ref refs))))))
    (nreverse refs)))

(defun rbx-statement--run (root args input callback)
  "Run rbx with ARGS in ROOT, writing INPUT to stdin, then call CALLBACK.

Resolves `rbx-program' via `rbx-resolve-executable' first; when it cannot
be found at all, warns once and calls CALLBACK as though the process had
failed, without attempting a spawn that can only fail.  See
`rbx-run-process' for CALLBACK's contract otherwise."
  (let ((program (rbx-resolve-executable rbx-program "rbx" root)))
    (if (null program)
        (progn
          (rbx--warn-once
           'rbx
           (format
            "rbx.el could not find rbx (checked `rbx-program' (%s), PATH, \
and a login shell); statement variable hints are unavailable until it is \
installed or `rbx-program' is set."
            rbx-program))
          (funcall callback "" "" nil))
      (rbx-run-process root program args input callback))))

(defconst rbx-statement--invalid (make-symbol "rbx-statement-invalid")
  "Sentinel returned by a payload reader for a value of the wrong shape.")

(defconst rbx-statement--ansi-escape-regexp "\e\\[[0-9;?]*[ -/]*[@-~]"
  "Regexp matching one ANSI/VT100 escape sequence.")

(defun rbx-statement--parse-leading-object (text)
  "Return the first JSON object found in TEXT, trying each `{' in turn.

rbx's own noise -- a shell wrapper, a deprecation warning, Rich's
cursor-restore escape on exit -- can print before or around the payload,
so only a syntax error moves on to the next brace; a value that parses
but has the wrong shape is rbx's actual answer and is returned as-is."
  (let ((stripped (replace-regexp-in-string
                   rbx-statement--ansi-escape-regexp "" text))
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

(defun rbx-statement--read-vars (value)
  "Return VALUE as a flat alist of string to string.

Returns nil for an empty (but validly shaped) mapping, or
`rbx-statement--invalid' when VALUE is not a string-valued mapping."
  (cond
   ((null value) nil)
   ((not (rbx--wire-mapping-p value)) rbx-statement--invalid)
   (t (let ((entries (rbx--wire-mapping-entries value)))
        (if (cl-every (lambda (entry) (stringp (cdr entry))) entries)
            entries
          rbx-statement--invalid)))))

(defun rbx-statement--parse-vars (stdout)
  "Parse STDOUT as a flat vars payload (`rbx vars --json'), or nil."
  (let ((vars (rbx-statement--read-vars
               (rbx-statement--parse-leading-object stdout))))
    (unless (eq vars rbx-statement--invalid)
      (rbx-statement-vars-payload-create :vars vars :groups nil))))

(defun rbx-statement--parse-vars-with-groups (stdout)
  "Parse STDOUT as a grouped vars payload (`rbx vars --json --groups'), or nil."
  (let ((parsed (rbx-statement--parse-leading-object stdout)))
    (when (rbx--wire-mapping-p parsed)
      (let ((raw-groups (rbx--wire-get parsed "groups" rbx-statement--invalid))
            (raw-vars (rbx--wire-get parsed "vars" rbx-statement--invalid)))
        (when (and (not (eq raw-groups rbx-statement--invalid))
                   (not (eq raw-vars rbx-statement--invalid))
                   (or (null raw-groups) (rbx--wire-mapping-p raw-groups)))
          (let ((vars (rbx-statement--read-vars raw-vars)))
            (unless (eq vars rbx-statement--invalid)
              (let (groups (ok t))
                (dolist (entry (rbx--wire-mapping-entries raw-groups))
                  (let ((group-vars (rbx-statement--read-vars (cdr entry))))
                    (if (eq group-vars rbx-statement--invalid)
                        (setq ok nil)
                      (push (cons (car entry) group-vars) groups))))
                (when ok
                  (rbx-statement-vars-payload-create
                   :vars vars :groups (nreverse groups)))))))))))

(defun rbx-statement--parse-rendered (stdout)
  "Parse STDOUT as a flat map of expression to rendered text, or nil.

The shape rbx prints for `rbx vars --render' is the same flat map
`rbx vars --json' prints, keyed by expression rather than by var name."
  (let ((vars (rbx-statement--read-vars
               (rbx-statement--parse-leading-object stdout))))
    (unless (eq vars rbx-statement--invalid)
      vars)))

(cl-defstruct (rbx-statement--cache-entry
               (:constructor rbx-statement--cache-entry-create))
  "Cached rbx vars state for one package root.

PAYLOAD is the resolved `rbx-statement-vars-payload', or nil before the
first successful load.  LOADING and WAITING coordinate a load already in
flight.  RENDERED memoizes `rbx vars --render' results, storing `:none'
for an expression rbx declined, so a half-typed filter is not re-asked on
every keystroke."
  payload loading waiting rendered)

(defvar rbx-statement--cache (make-hash-table :test #'equal)
  "Cached rbx vars state, keyed by absolute package root.")

(defun rbx-statement--entry (package)
  "Return PACKAGE's cache entry, creating one if needed."
  (let ((root (rbx-package-root package)))
    (or (gethash root rbx-statement--cache)
        (puthash root
                 (rbx-statement--cache-entry-create
                  :rendered (make-hash-table :test #'equal))
                 rbx-statement--cache))))

(defun rbx-statement-invalidate (package)
  "Drop cached rbx vars state for PACKAGE."
  (remhash (rbx-package-root package) rbx-statement--cache))

(defun rbx-statement--complete-load (entry payload)
  "Store PAYLOAD in ENTRY and notify everyone waiting on it."
  (setf (rbx-statement--cache-entry-payload entry) payload)
  (setf (rbx-statement--cache-entry-loading entry) nil)
  (let ((waiting (nreverse (rbx-statement--cache-entry-waiting entry))))
    (setf (rbx-statement--cache-entry-waiting entry) nil)
    (dolist (callback waiting)
      (funcall callback payload))))

(defun rbx-statement--finish-load (package entry exit-code stdout)
  "Resolve ENTRY's pending vars load for PACKAGE with the process's result."
  (let ((payload (and exit-code (= exit-code 0)
                      (rbx-statement--parse-vars-with-groups stdout))))
    (if payload
        (rbx-statement--complete-load entry payload)
      ;; Either this rbx does not know --groups, or the payload was
      ;; malformed; the flat retry also degrades to nil when the package
      ;; itself cannot be read, which is what a broken manifest looks like
      ;; either way.
      (rbx-statement--run
       (rbx-package-root package) (list "vars" "--json") nil
       (lambda (flat-stdout _flat-stderr flat-exit-code)
         (let ((flat-payload (and flat-exit-code (= flat-exit-code 0)
                                  (rbx-statement--parse-vars flat-stdout))))
           (rbx-statement--complete-load entry flat-payload)))))))

(defun rbx-statement-load-vars (package callback)
  "Ensure PACKAGE's vars payload is cached, then call CALLBACK with it.

CALLBACK receives the cached `rbx-statement-vars-payload', or nil when rbx
could not answer."
  (let ((entry (rbx-statement--entry package)))
    (cond
     ((rbx-statement--cache-entry-payload entry)
      (funcall callback (rbx-statement--cache-entry-payload entry)))
     ((rbx-statement--cache-entry-loading entry)
      (push callback (rbx-statement--cache-entry-waiting entry)))
     (t
      (setf (rbx-statement--cache-entry-loading entry) t)
      (setf (rbx-statement--cache-entry-waiting entry) (list callback))
      (rbx-statement--run
       (rbx-package-root package) (list "vars" "--json" "--groups") nil
       (lambda (stdout _stderr exit-code)
         (rbx-statement--finish-load package entry exit-code stdout)))))))

(defun rbx-statement--rendered-alist (table expressions)
  "Return EXPRESSIONS paired with their cached text in TABLE, or nil."
  (mapcar (lambda (expression)
            (let ((cached (gethash expression table)))
              (cons expression (unless (eq cached :none) cached))))
          expressions))

(defun rbx-statement-render (package expressions callback)
  "Render EXPRESSIONS for PACKAGE, then call CALLBACK with an alist result.

Only expressions not already cached (successful or declined) are actually
sent to rbx.  CALLBACK receives every element of EXPRESSIONS paired with
its rendered text, or nil for one rbx declined to render."
  (let* ((entry (rbx-statement--entry package))
         (table (rbx-statement--cache-entry-rendered entry))
         (missing (seq-remove (lambda (expression) (gethash expression table))
                              expressions)))
    (if (null missing)
        (funcall callback (rbx-statement--rendered-alist table expressions))
      (rbx-statement--run
       (rbx-package-root package) (list "vars" "--render" "--target" "text")
       (concat (string-join missing "\n") "\n")
       (lambda (stdout _stderr exit-code)
         (let ((rendered (and exit-code (= exit-code 0)
                              (rbx-statement--parse-rendered stdout))))
           (dolist (expression missing)
             (puthash expression
                      (or (cdr (assoc expression rendered)) :none)
                      table)))
         (funcall callback (rbx-statement--rendered-alist table expressions)))))))

(provide 'rbx-statement)
;;; rbx-statement.el ends here
