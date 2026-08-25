;;; rbx-ui.el --- Native views for rbx artifacts -*- lexical-binding: t; -*-

;; Copyright (C) 2026 rbx.el contributors

;; Author: rbx.el contributors
;; Maintainer: rbx.el contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (magit-section "4.1.0")
;;                    (transient "0.7.5"))
;; Keywords: tools, languages
;; URL: https://github.com/luishgh/rbx.el

;;; Commentary:

;; Magit Section views and Transient actions for run and testset artifacts.
;; Generated files are shown read-only, using native file and diff buffers.

;;; Code:

(require 'browse-url)
(require 'diff)
(require 'eieio)
(require 'font-lock)
(require 'magit-section)
(require 'project)
(require 'rbx-model)
(require 'subr-x)
(require 'transient)

(defcustom rbx-solution-label 'trimmed
  "How solution paths are displayed in the run view.

`full' preserves the package-relative path, `basename' shows only its file
name, and `trimmed' removes the directory common to all solutions."
  :type '(choice (const full) (const trimmed) (const basename))
  :group 'rbx)

(defcustom rbx-testcase-layout 'below
  "Initial arrangement of input and result panes.

This is only a seed.  Once created, the same windows are reused so a layout
adjusted by the user remains intact."
  :type '(choice (const below) (const beside))
  :group 'rbx)

(defface rbx-hue-green
  '((((class color) (background light)) :foreground "#388a34")
    (((class color) (background dark)) :foreground "#89d185")
    (t :foreground "green"))
  "Green used by the VS Code extension's charts palette."
  :group 'rbx)

(defface rbx-hue-red
  '((((class color) (background light)) :foreground "#e51400")
    (((class color) (background dark)) :foreground "#f14c4c")
    (t :foreground "red"))
  "Red used by the VS Code extension's charts palette."
  :group 'rbx)

(defface rbx-hue-yellow
  '((((class color) (background light)) :foreground "#bf8803")
    (((class color) (background dark)) :foreground "#cca700")
    (t :foreground "yellow"))
  "Yellow used by the VS Code extension's charts palette."
  :group 'rbx)

(defface rbx-hue-blue
  '((((class color) (background light)) :foreground "#007acc")
    (((class color) (background dark)) :foreground "#75beff")
    (t :foreground "blue"))
  "Blue used by the VS Code extension's charts palette."
  :group 'rbx)

(defface rbx-hue-purple
  '((((class color) (background light)) :foreground "#652d90")
    (((class color) (background dark)) :foreground "#b180d7")
    (t :foreground "magenta"))
  "Purple used by the VS Code extension's charts palette."
  :group 'rbx)

(defface rbx-hue-orange
  '((((class color) (background light)) :foreground "#d18616")
    (((class color) (background dark)) :foreground "#d18616")
    (t :foreground "yellow"))
  "Orange used by the VS Code extension's charts palette."
  :group 'rbx)

(defface rbx-hue-dim
  '((((class color) (background light)) :foreground "#717171")
    (((class color) (background dark)) :foreground "#9d9d9d")
    (t :foreground "gray50"))
  "Dim foreground corresponding to VS Code's description foreground."
  :group 'rbx)

(defface rbx-hue-neutral
  '((t :inherit default))
  "Neutral foreground corresponding to VS Code's normal foreground."
  :group 'rbx)

(defface rbx-expected-accepted
  '((t :inherit rbx-hue-green))
  "Face for a solution declared accepted."
  :group 'rbx)

(defface rbx-expected-incorrect
  '((t :inherit rbx-hue-red))
  "Face for a solution declared incorrect."
  :group 'rbx)

(defface rbx-expected-slow
  '((t :inherit rbx-hue-yellow))
  "Face for a solution declared slow."
  :group 'rbx)

(defface rbx-expected-error
  '((t :inherit rbx-hue-blue))
  "Face for a solution declared to fail with an error."
  :group 'rbx)

(defface rbx-expected-other
  '((t :inherit rbx-hue-purple))
  "Face for other declared outcomes."
  :group 'rbx)

(defface rbx-expected-neutral
  '((t :inherit rbx-hue-neutral))
  "Face for ANY and unknown declared outcomes."
  :group 'rbx)

(defface rbx-outcome-accepted
  '((t :inherit rbx-hue-green :weight bold))
  "Face for accepted testcase verdicts."
  :group 'rbx)

(defface rbx-outcome-wrong
  '((t :inherit rbx-hue-red :weight bold))
  "Face for wrong-answer testcase verdicts."
  :group 'rbx)

(defface rbx-outcome-limit
  '((t :inherit rbx-hue-yellow :weight bold))
  "Face for time, idleness, and memory limit verdicts."
  :group 'rbx)

(defface rbx-outcome-error
  '((t :inherit rbx-hue-blue :weight bold))
  "Face for runtime and compilation error verdicts."
  :group 'rbx)

(defface rbx-outcome-output-limit
  '((t :inherit rbx-hue-orange :weight bold))
  "Face for output limit verdicts."
  :group 'rbx)

(defface rbx-outcome-internal
  '((t :inherit rbx-hue-purple :weight bold))
  "Face for judge and internal failures."
  :group 'rbx)

(defface rbx-outcome-dim
  '((t :inherit rbx-hue-dim))
  "Face for pending and skipped testcase verdicts."
  :group 'rbx)

(defface rbx-match
  '((t :inherit rbx-hue-green))
  "Face for a declaration met by a run."
  :group 'rbx)

(defface rbx-mismatch
  '((t :inherit rbx-hue-red :weight bold))
  "Face for a declaration missed by a run."
  :group 'rbx)

(defface rbx-warning
  '((t :inherit rbx-hue-yellow :weight bold))
  "Face for a passing run that still carries a warning."
  :group 'rbx)

(defface rbx-row-mismatch
  '((((class color) (background light)) :background "#fdecec" :extend t)
    (((class color) (background dark)) :background "#2f2222" :extend t)
    (t :inherit default))
  "Eight-percent red wash used only on missed-expectation rows."
  :group 'rbx)

(defface rbx-row-warning
  '((((class color) (background light)) :background "#fcfaf0" :extend t)
    (((class color) (background dark)) :background "#28261c" :extend t)
    (t :inherit default))
  "Six-percent yellow wash used only on warned rows."
  :group 'rbx)

(defconst rbx--outcome-short-names
  '(("accepted" . "AC")
    ("skipped" . "SKIP")
    ("wrong-answer" . "WA")
    ("time-limit-exceeded" . "TLE")
    ("idleness-limit-exceeded" . "ILE")
    ("memory-limit-exceeded" . "MLE")
    ("runtime-error" . "RTE")
    ("output-limit-exceeded" . "OLE")
    ("judge-failed" . "FL")
    ("internal-error" . "IE")
    ("compilation-error" . "CE"))
  "Display names for actual rbx outcomes.")

(defconst rbx--expectation-display
  '(("ANY" :label "ANY" :face rbx-expected-neutral :bold t)
    ("ACCEPTED" :label "AC" :face rbx-expected-accepted :bold t)
    ("ACCEPTED_OR_TLE" :label "AC or TLE" :face rbx-expected-accepted)
    ("WRONG_ANSWER" :label "WA" :face rbx-expected-incorrect)
    ("INCORRECT" :label "INCORRECT" :face rbx-expected-incorrect)
    ("RUNTIME_ERROR" :label "RTE" :face rbx-expected-error)
    ("TIME_LIMIT_EXCEEDED" :label "TLE" :face rbx-expected-slow)
    ("MEMORY_LIMIT_EXCEEDED" :label "MLE" :face rbx-expected-slow)
    ("OUTPUT_LIMIT_EXCEEDED" :label "OLE" :face rbx-expected-other)
    ("TLE_OR_RTE" :label "TLE or RTE" :face rbx-expected-slow)
    ("JUDGE_FAILED" :label "FL" :face rbx-expected-other)
    ("COMPILATION_ERROR" :label "CE" :face rbx-expected-error))
  "Labels and hues for declared rbx outcomes.")

(defclass rbx-root-section (magit-section) ())
(defclass rbx-solution-section (magit-section) ())
(defclass rbx-group-section (magit-section) ())
(defclass rbx-testcase-section (magit-section) ())
(defclass rbx-compilation-section (magit-section) ())
(defclass rbx-warning-section (magit-section) ())
(defclass rbx-testset-group-section (magit-section) ())
(defclass rbx-testset-testcase-section (magit-section) ())
(defclass rbx-coverage-section (magit-section) ())

(defvar-keymap rbx-view-mode-map
  :doc "Keymap for `rbx-view-mode'."
  :parent magit-section-mode-map
  "RET" #'rbx-view-visit
  "g" #'rbx-refresh
  "?" #'rbx-dispatch
  "q" #'quit-window)

(defvar-local rbx--package nil
  "Package displayed in the current rbx view.")

(defvar-local rbx--view nil
  "Kind of the current view, either `run' or `testset'.")

(defvar-local rbx--watcher nil
  "Artifact watcher owned by the current view buffer.")

(defvar-local rbx--testcase-context nil
  "Most recently opened testcase context in the current view.")

(defvar-local rbx--testcase-channel 'output
  "Sticky secondary channel for testcase inspection.")

(defvar-local rbx--input-window nil
  "Window reserved for testcase input by the current view.")

(defvar-local rbx--result-window nil
  "Window reserved for testcase output by the current view.")

(define-derived-mode rbx-view-mode magit-section-mode "rbx"
  "Major mode for browsing rbx run and testset artifacts."
  :group 'rbx
  (setq-local revert-buffer-function
              (lambda (&rest _ignored) (rbx-refresh)))
  (add-hook 'kill-buffer-hook #'rbx--stop-buffer-watcher nil t))

(defun rbx-outcome-short-name (outcome)
  "Return rbx's concise display name for actual OUTCOME."
  (if outcome
      (or (cdr (assoc outcome rbx--outcome-short-names)) "XX")
    "?"))

(defun rbx--outcome-face (outcome)
  "Return the display face for actual OUTCOME."
  (cond
   ((or (null outcome) (equal outcome "skipped")) 'rbx-outcome-dim)
   ((equal outcome "accepted") 'rbx-outcome-accepted)
   ((equal outcome "wrong-answer") 'rbx-outcome-wrong)
   ((member outcome '("time-limit-exceeded" "idleness-limit-exceeded"
                      "memory-limit-exceeded"))
    'rbx-outcome-limit)
   ((equal outcome "output-limit-exceeded") 'rbx-outcome-output-limit)
   ((member outcome '("runtime-error" "compilation-error"))
    'rbx-outcome-error)
   (t 'rbx-outcome-internal)))

(defun rbx--expectation-properties (outcome)
  "Return display properties for declared OUTCOME."
  (cdr (assoc (or outcome "ANY") rbx--expectation-display)))

(defun rbx--expectation-label (outcome)
  "Return the VS Code extension's label for declared OUTCOME."
  (or (plist-get (rbx--expectation-properties outcome) :label)
      outcome
      "ANY"))

(defun rbx--expected-face (outcome)
  "Return the face for declared OUTCOME."
  (or (plist-get (rbx--expectation-properties outcome) :face)
      'rbx-expected-neutral))

(defun rbx--expected-face-value (outcome)
  "Return a face value encoding OUTCOME's hue and emphasis."
  (let ((face (rbx--expected-face outcome)))
    (if (plist-get (rbx--expectation-properties outcome) :bold)
        (list face 'bold)
      face)))

(defun rbx--fontify (string face)
  "Return STRING propertized with FACE for Magit Section font locking."
  (propertize string 'font-lock-face face))

(defun rbx--expected (outcome)
  "Return a propertized label for declared OUTCOME."
  (rbx--fontify (rbx--expectation-label outcome)
                (rbx--expected-face-value outcome)))

(defun rbx-format-time (seconds)
  "Format SECONDS the same way as the rbx terminal UI."
  (when seconds (format "%d ms" (truncate (* seconds 1000)))))

(defun rbx-format-memory (bytes)
  "Format BYTES with the units used by rbx."
  (when bytes
    (cond
     ((< bytes 1024) (format "%d B" bytes))
     ((< bytes (* 1024 1024)) (format "%d KiB" (round (/ bytes 1024.0))))
     (t (format "%d MiB" (round (/ bytes 1048576.0)))))))

(defun rbx--format-size (bytes)
  "Format file size BYTES compactly."
  (rbx-format-memory bytes))

(defun rbx--score (score maximum)
  "Format SCORE out of MAXIMUM."
  (format "[%s/%s]" score maximum))

(defun rbx--report-for-solution (report solution)
  "Find SOLUTION's aggregate in REPORT."
  (and report
       (seq-find
        (lambda (candidate)
          (= (rbx-solution-report-index candidate)
             (rbx-solution-index solution)))
        (rbx-run-report-solutions report))))

(defun rbx--report-for-group (solution-report group)
  "Find GROUP's aggregate in SOLUTION-REPORT."
  (and solution-report
       (seq-find (lambda (candidate)
                   (equal (rbx-group-report-name candidate) group))
                 (rbx-solution-report-groups solution-report))))

(defun rbx--entries-by-group (entries)
  "Index ENTRIES by group while preserving their artifact order."
  (let ((index (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (push entry (gethash (rbx-testcase-group entry) index)))
    (maphash (lambda (group members)
               (puthash group (nreverse members) index))
             index)
    index))

(defun rbx--solution-label (solution all-solutions)
  "Return a display label for SOLUTION among ALL-SOLUTIONS."
  (let ((path (rbx-solution-path solution)))
    (pcase rbx-solution-label
      ('full path)
      ('basename (file-name-nondirectory path))
      ('trimmed
       (let* ((directories
               (mapcar (lambda (item)
                         (file-name-directory (rbx-solution-path item)))
                       all-solutions))
              (common (and directories
                           (cl-reduce #'rbx--common-directory directories))))
         (if (and common (string-prefix-p common path))
             (substring path (length common))
           path)))
      (_ path))))

(defun rbx--common-directory (left right)
  "Return the common directory prefix of LEFT and RIGHT."
  (let ((left-parts (split-string (or left "") "/" t))
        (right-parts (split-string (or right "") "/" t))
        result)
    (while (and left-parts right-parts
                (equal (car left-parts) (car right-parts)))
      (push (pop left-parts) result)
      (pop right-parts))
    (if result (concat (string-join (nreverse result) "/") "/") "")))

(defun rbx--match-marker (matches warning)
  "Return the independent match marker for MATCHES and WARNING."
  (cond
   ((not matches) (rbx--fontify "✗" 'rbx-mismatch))
   (warning (rbx--fontify "▲" 'rbx-warning))
   (t (rbx--fontify "✓" 'rbx-match))))

(defun rbx--row-state (matches warning)
  "Return the row emphasis state for MATCHES and WARNING."
  (cond
   ((not matches) 'missed)
   (warning 'warned)
   (t 'met)))

(defun rbx--decorate-row (line state)
  "Apply STATE's reserved background wash to LINE."
  (let ((decorated (copy-sequence line))
        (face (pcase state
                ('missed 'rbx-row-mismatch)
                ('warned 'rbx-row-warning))))
    (when face
      (font-lock-append-text-property
       0 (length decorated) 'font-lock-face face decorated))
    decorated))

(defun rbx--actual (outcome)
  "Return propertized actual OUTCOME text."
  (rbx--fontify (rbx-outcome-short-name outcome)
                (rbx--outcome-face outcome)))

(defun rbx--meta (&rest parts)
  "Join non-nil PARTS into a compact metadata string."
  (string-join (delq nil parts) "  "))

(defun rbx--evaluation-available-p (package solution entry)
  "Return non-nil when ENTRY has an evaluation for SOLUTION in PACKAGE."
  (file-readable-p
   (rbx-run-artifact-path package (rbx-solution-index solution)
                          (rbx-testcase-group entry)
                          (rbx-testcase-stem entry) ".eval")))

(defun rbx--evaluation-progress (package solution entries)
  "Return completed and total counts for SOLUTION's ENTRIES in PACKAGE."
  (cons (cl-count-if
         (lambda (entry)
           (rbx--evaluation-available-p package solution entry))
         entries)
        (length entries)))

(defun rbx--insert-run-testcase (package solution entry evaluation)
  "Insert ENTRY and its EVALUATION for SOLUTION in PACKAGE."
  (let ((context (list :kind 'run-testcase
                       :package package
                       :solution solution
                       :solution-index (rbx-solution-index solution)
                       :testcase entry
                       :evaluation evaluation)))
    (magit-insert-section (rbx-testcase-section context)
      (magit-insert-heading
       (format "    %s  %s%s\n"
               (rbx-testcase-stem entry)
               (rbx--actual (and evaluation
                                 (rbx-evaluation-outcome evaluation)))
               (let ((meta
                      (and evaluation
                           (rbx--meta
                            (rbx-format-time (rbx-evaluation-time evaluation))
                            (rbx-format-memory
                             (rbx-evaluation-memory evaluation))
                            (rbx-evaluation-message evaluation)
                            (and (rbx-evaluation-sanitizer-warnings evaluation)
                                 "sanitizer")))))
                 (if (string-empty-p (or meta "")) "" (concat "  " meta))))))))

(defun rbx--insert-run-group
    (package solution group entries solution-report)
  "Insert GROUP and its ENTRIES for SOLUTION in PACKAGE."
  (let* ((group-report (rbx--report-for-group solution-report group))
         (warning
          (and group-report
               (or (rbx-group-report-run-under-double-tl group-report)
                   (rbx-group-report-sanitizer-warnings group-report))))
         (progress (and (null group-report)
                        (rbx--evaluation-progress package solution entries)))
         (context (list :kind 'run-group :group group)))
    (magit-insert-section (rbx-group-section context t)
      (magit-insert-heading
       (if group-report
           (rbx--decorate-row
            (format "  %s  %s  %s  %s\n"
                    (rbx--match-marker
                     (rbx-group-report-matches-expectation group-report)
                     warning)
                    group
                    (if-let ((expected
                              (rbx-group-report-expected-outcome group-report)))
                        (format "declared %s → got %s"
                                (rbx--expected expected)
                                (rbx--actual
                                 (rbx-group-report-outcome group-report)))
                      (format "got %s"
                              (rbx--actual
                               (rbx-group-report-outcome group-report))))
                    (rbx--meta
                     (rbx--score (rbx-group-report-score group-report)
                                 (rbx-group-report-max-score group-report))
                     (rbx-format-time
                      (rbx-group-report-max-time group-report))
                     (rbx-format-memory
                      (rbx-group-report-max-memory group-report))))
            (rbx--row-state
             (rbx-group-report-matches-expectation group-report)
             warning))
         (format "  … %s  %d/%d\n" group (car progress) (cdr progress))))
      (magit-insert-section-body
        (dolist (entry entries)
          (rbx--insert-run-testcase
           package solution entry
           (rbx-load-evaluation package (rbx-solution-index solution)
                                entry)))))))

(defun rbx--insert-solution
    (package skeleton report solution groups entries-by-group)
  "Insert SOLUTION from SKELETON and REPORT for PACKAGE."
  (let* ((solution-report (rbx--report-for-solution report solution))
         (entries (rbx-skeleton-entries skeleton))
         (progress (and (null solution-report)
                        (rbx--evaluation-progress package solution entries)))
         (warning (and solution-report
                       (or (rbx-solution-report-run-under-double-tl
                            solution-report)
                           (rbx-solution-report-sanitizer-warnings
                            solution-report))))
         (context (list :kind 'solution :package package :solution solution)))
    (magit-insert-section (rbx-solution-section context)
      (magit-insert-heading
       (if solution-report
           (rbx--decorate-row
            (format "%s %s  declared %s → got %s  %s\n"
                    (rbx--match-marker
                     (rbx-solution-report-matches-expectation solution-report)
                     warning)
                    (rbx--fontify
                     (rbx--solution-label solution
                                          (rbx-skeleton-solutions skeleton))
                     (rbx--expected-face-value
                      (rbx-solution-expected-outcome solution)))
                    (rbx--expected (rbx-solution-expected-outcome solution))
                    (rbx--actual
                     (rbx-solution-report-outcome solution-report))
                    (rbx--meta
                     (rbx--score (rbx-solution-report-score solution-report)
                                 (rbx-solution-report-max-score solution-report))
                     (rbx-format-time
                      (rbx-solution-report-max-time solution-report))
                     (rbx-format-memory
                      (rbx-solution-report-max-memory solution-report))
                     (unless
                         (equal (rbx-solution-report-status solution-report)
                                "OK")
                       (rbx-solution-report-status solution-report))))
            (rbx--row-state
             (rbx-solution-report-matches-expectation solution-report)
             warning))
         (format "… %s  declared %s  %d/%d\n"
                 (rbx--fontify
                  (rbx--solution-label solution
                                       (rbx-skeleton-solutions skeleton))
                  (rbx--expected-face-value
                   (rbx-solution-expected-outcome solution)))
                 (rbx--expected (rbx-solution-expected-outcome solution))
                 (car progress) (cdr progress))))
      (dolist (group groups)
        (rbx--insert-run-group
         package solution group (gethash group entries-by-group)
         solution-report)))))

(defun rbx--insert-compilation (package findings)
  "Insert compilation FINDINGS for PACKAGE."
  (when findings
    (magit-insert-section (rbx-compilation-section nil)
      (magit-insert-heading (length findings) "Compilation findings")
      (dolist (finding findings)
        (let* ((context (list :kind 'compilation
                              :package package :finding finding))
               (failed (equal (rbx-compilation-status finding) "FAILED"))
               (expected (rbx-compilation-expected-outcome finding)))
          (magit-insert-section (rbx-compilation-section context)
            (magit-insert-heading
             (rbx--decorate-row
              (format "  %s %s  declared %s%s\n"
                      (if failed
                          (rbx--fontify "✗" 'rbx-mismatch)
                        (rbx--fontify "▲" 'rbx-warning))
                      (rbx--fontify (rbx-compilation-path finding)
                                    (rbx--expected-face-value expected))
                      (rbx--expected expected)
                      (if-let ((reason (rbx-compilation-reason finding)))
                          (concat "  " reason) ""))
              (if failed 'missed 'warned)))
            (dolist (warning (rbx-compilation-warnings finding))
              (magit-insert-section
                  (rbx-warning-section
                   (list :kind 'warning :package package :warning warning))
                (magit-insert-heading
                 (format "    %d%s  %s\n"
                         (rbx-warning-line warning)
                         (if-let ((flag (rbx-warning-flag warning)))
                             (concat " · " flag) "")
                         (rbx-warning-message warning)))))))))))

(defun rbx--insert-run-view (package)
  "Insert PACKAGE's run view at point."
  (if-let ((skeleton (rbx-load-skeleton package)))
      (let ((report (rbx-load-report package))
            (groups (rbx-skeleton-ordered-groups skeleton))
            (entries-by-group
             (rbx--entries-by-group (rbx-skeleton-entries skeleton))))
        (magit-insert-section
            (rbx-root-section (list :kind 'root :package package))
          (magit-insert-heading
           (format "Run · %s%s\n"
                   (abbreviate-file-name (rbx-package-root package))
                   (if (rbx-skeleton-sanitized skeleton) " · sanitized" "")))
          (when (rbx-skeleton-only-accepted skeleton)
            (insert (propertize
                     "Showing accepted solutions only (sanitized run).\n"
                     'face 'shadow)))
          (dolist (solution (rbx-skeleton-solutions skeleton))
            (rbx--insert-solution package skeleton report solution
                                  groups entries-by-group))
          (rbx--insert-compilation package
                                   (rbx-skeleton-compilation skeleton))))
    (magit-insert-section
        (rbx-root-section (list :kind 'root :package package))
      (magit-insert-heading "Run")
      (insert (propertize
               "No run artifacts yet.  Run `rbx run` in your terminal.\n"
               'face 'shadow)))))

(defun rbx--testcase-provenance (entry)
  "Return a concise provenance description for ENTRY."
  (cond
   ((rbx-testcase-generator-name entry)
    (string-join (delq nil
                       (list (rbx-testcase-generator-name entry)
                             (rbx-testcase-generator-args entry)))
                 " "))
   ((rbx-testcase-copied-from entry)
    (format "copied from %s" (rbx-testcase-copied-from entry)))
   ((rbx-testcase-generator-script entry)
    (format "%s:%s" (rbx-testcase-generator-script entry)
            (or (rbx-testcase-generator-script-line entry) "?")))
   (t "generated")))

(defun rbx--insert-testset-testcase (package testcase)
  "Insert TESTCASE from PACKAGE's testset."
  (let* ((entry (rbx-testset-testcase-entry testcase))
         (test (rbx-testset-testcase-test testcase))
         (validation (and test (rbx-testset-test-validation test)))
         (context (list :kind 'testset-testcase
                        :package package :testcase testcase)))
    (magit-insert-section (rbx-testset-testcase-section context)
      (magit-insert-heading
       (format "  %s  %s%s\n"
               (rbx-testset-testcase-stem testcase)
               (rbx--testcase-provenance entry)
               (let ((meta
                      (rbx--meta
                       (and validation
                            (if (rbx-testset-validation-result-ok validation)
                                (and (rbx-testset-validation-result-validator
                                      validation)
                                     (format
                                      "validated by %s"
                                      (rbx-testset-validation-result-validator
                                       validation)))
                              (rbx--fontify
                               (or (rbx-testset-validation-result-message
                                    validation)
                                   "validation failed")
                               'error)))
                       (and test
                            (rbx--format-size
                             (rbx-testset-test-input-size test)))
                       (and test
                            (rbx-testset-test-visualization test)
                            "visualized"))))
                 (if (string-empty-p meta) "" (concat "  " meta))))))))

(defun rbx--testset-cases-for-group (testset group)
  "Return TESTSET testcases in GROUP."
  (seq-filter
   (lambda (testcase)
     (equal (rbx-testcase-group (rbx-testset-testcase-entry testcase)) group))
   (rbx-testset-testcases testset)))

(defun rbx--insert-coverage (testset)
  "Insert constraint coverage from TESTSET."
  (when (rbx-testset-validation testset)
      (magit-insert-section (rbx-coverage-section nil t)
      (magit-insert-heading "Constraint coverage")
      (dolist (group (rbx-testset-validation testset))
        (magit-insert-section
            (rbx-coverage-section (list :kind 'coverage :bounds group))
          (magit-insert-heading (format "  %s%s\n"
                                        (rbx-group-bounds-group group)
                                        (if-let ((validator
                                                  (rbx-group-bounds-validator
                                                   group)))
                                            (format " · %s" validator) "")))
          (dolist (item (rbx-group-bounds-bounds group))
            (insert
             (format "    %s  min %s  max %s\n"
                     (car item)
                     (if (rbx-variable-bounds-min-hit (cdr item)) "✓" "·")
                     (if (rbx-variable-bounds-max-hit (cdr item)) "✓" "·")))))))))

(defun rbx--insert-testset-view (package)
  "Insert PACKAGE's testset view at point."
  (if-let ((testset (rbx-load-testset package)))
      (magit-insert-section
          (rbx-root-section (list :kind 'root :package package))
        (magit-insert-heading
         (format "Tests · %s%s\n"
                 (abbreviate-file-name (rbx-package-root package))
                 (if-let ((task-type (rbx-testset-task-type testset)))
                     (format " · %s" task-type) "")))
        (dolist (group (rbx-testset-ordered-groups testset))
          (let ((testcases (rbx--testset-cases-for-group testset group)))
            (magit-insert-section
                (rbx-testset-group-section
                 (list :kind 'testset-group :group group :testset testset))
              (magit-insert-heading
               (format "%s  %d testcase%s\n" group (length testcases)
                       (if (= (length testcases) 1) "" "s")))
              (dolist (testcase testcases)
                (rbx--insert-testset-testcase package testcase)))))
        (rbx--insert-coverage testset))
    (magit-insert-section
        (rbx-root-section (list :kind 'root :package package))
      (magit-insert-heading "Tests")
      (insert (propertize
               "No testset manifest yet.  Run `rbx build` in your terminal.\n"
               'face 'shadow)))))

(defun rbx-refresh ()
  "Refresh the current rbx artifact view."
  (interactive)
  (unless (and (derived-mode-p 'rbx-view-mode) rbx--package rbx--view)
    (user-error "This is not an initialized rbx view"))
  (let ((inhibit-read-only t)
        (line (line-number-at-pos)))
    (erase-buffer)
    (pcase rbx--view
      ('run (rbx--insert-run-view rbx--package))
      ('testset (rbx--insert-testset-view rbx--package))
      (_ (insert "Unknown rbx view.\n")))
    (goto-char (point-min))
    (forward-line (1- line))))

(defun rbx--stop-buffer-watcher ()
  "Stop the current view buffer's artifact watcher."
  (when rbx--watcher
    (rbx-stop-watcher rbx--watcher)
    (setq rbx--watcher nil)))

(defun rbx--start-buffer-watcher ()
  "Start or replace the current view buffer's artifact watcher."
  (rbx--stop-buffer-watcher)
  (let ((buffer (current-buffer)))
    (setq rbx--watcher
          (rbx-watch-package
           rbx--package
           (lambda ()
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (rbx--start-buffer-watcher)
                 (rbx-refresh))))))))

(defun rbx--project-root ()
  "Return the current project root or `default-directory'."
  (if-let ((project (project-current nil)))
      (project-root project)
    default-directory))

(defun rbx--select-package (&optional always-prompt)
  "Choose an rbx package, prompting when ALWAYS-PROMPT or ambiguous."
  (let* ((nearby (and (not always-prompt) (rbx-find-package)))
         (packages (if nearby
                       (list nearby)
                     (rbx-discover-packages (rbx--project-root)))))
    (pcase packages
      ('() (user-error "No problem.rbx.yml found"))
      (`(,only) only)
      (_
       (let* ((root (rbx--project-root))
              (choices
               (mapcar (lambda (package)
                         (cons (file-relative-name
                                (rbx-package-root package) root)
                               package))
                       packages)))
         (cdr (assoc (completing-read "rbx problem: " choices nil t)
                     choices)))))))

(defun rbx--open-view (view &optional package)
  "Open VIEW for PACKAGE."
  (let* ((selected (or package (rbx--select-package)))
         (label (file-name-nondirectory
                 (directory-file-name (rbx-package-root selected))))
         (buffer (get-buffer-create
                  (format "*rbx %s: %s*" view label))))
    (let ((window
           (display-buffer-in-side-window
            buffer '((side . left) (slot . -1) (window-width . 0.32)))))
      (select-window window))
    (unless (derived-mode-p 'rbx-view-mode)
      (rbx-view-mode))
    (setq rbx--package selected
          rbx--view view
          default-directory (rbx-package-root selected))
    (rbx--start-buffer-watcher)
    (rbx-refresh)
    buffer))

;;;###autoload
(defun rbx-run-view (&optional package)
  "Open the live run view for PACKAGE."
  (interactive)
  (rbx--open-view 'run package))

;;;###autoload
(defun rbx-testset-view (&optional package)
  "Open the built testset view for PACKAGE."
  (interactive)
  (rbx--open-view 'testset package))

(defun rbx-select-package ()
  "Select another problem for the current rbx view."
  (interactive)
  (unless (derived-mode-p 'rbx-view-mode)
    (user-error "This is not an rbx view"))
  (setq rbx--package (rbx--select-package t))
  (setq default-directory (rbx-package-root rbx--package))
  (rbx--start-buffer-watcher)
  (rbx-refresh))

(defun rbx--context ()
  "Return the action context of the Magit section at point."
  (when-let ((section (magit-current-section)))
    (oref section value)))

(defun rbx--context-path (context channel)
  "Return CONTEXT's artifact path for CHANNEL."
  (let* ((package (plist-get context :package))
         (kind (plist-get context :kind)))
    (pcase kind
      ('run-testcase
       (let* ((entry (plist-get context :testcase))
              (index (plist-get context :solution-index))
              (group (rbx-testcase-group entry))
              (stem (rbx-testcase-stem entry)))
         (pcase channel
           ('input (rbx-test-artifact-path package group stem ".in"))
           ('expected (rbx-test-artifact-path package group stem ".out"))
           ('output (rbx-run-artifact-path package index group stem ".out"))
           ('stderr (rbx-run-artifact-path package index group stem ".err"))
           ('log (rbx-run-artifact-path package index group stem ".log")))))
      ('testset-testcase
       (let* ((testcase (plist-get context :testcase))
              (entry (rbx-testset-testcase-entry testcase))
              (group (rbx-testcase-group entry))
              (stem (rbx-testset-testcase-stem testcase)))
         (pcase channel
           ('input (rbx-test-artifact-path package group stem ".in"))
           ('expected (rbx-test-artifact-path package group stem ".out"))))))))

(defun rbx--read-only-file-buffer (path)
  "Visit PATH and return its buffer with editing disabled."
  (unless (and path (file-readable-p path))
    (user-error "Artifact is not available: %s" (or path "unknown")))
  (let ((buffer (find-file-noselect path)))
    (with-current-buffer buffer
      (view-mode 1))
    buffer))

(defun rbx--diff-buffer (expected actual context)
  "Return a native diff buffer for EXPECTED and ACTUAL in CONTEXT."
  (unless (and expected actual
               (file-readable-p expected) (file-readable-p actual))
    (user-error "Output or expected answer is not available"))
  (let* ((entry (plist-get context :testcase))
         (stem (if (rbx-testset-testcase-p entry)
                   (rbx-testset-testcase-stem entry)
                 (rbx-testcase-stem entry)))
         (buffer (get-buffer-create (format "*rbx diff: %s*" stem))))
    (diff-no-select expected actual "-u" t buffer)))

(defun rbx--result-buffer (context)
  "Return the secondary inspection buffer for CONTEXT."
  (pcase rbx--testcase-channel
    ('output
     (if (eq (plist-get context :kind) 'run-testcase)
         (rbx--diff-buffer (rbx--context-path context 'expected)
                           (rbx--context-path context 'output) context)
       (rbx--read-only-file-buffer
        (rbx--context-path context 'expected))))
    ('stderr (rbx--read-only-file-buffer
              (rbx--context-path context 'stderr)))
    ('log (rbx--read-only-file-buffer (rbx--context-path context 'log)))
    (_ (user-error "Unknown testcase channel"))))

(defun rbx--display-testcase (context)
  "Display CONTEXT using persistent input and result windows."
  (let ((input-buffer
         (rbx--read-only-file-buffer (rbx--context-path context 'input)))
        (result-buffer (rbx--result-buffer context)))
    (unless (window-live-p rbx--input-window)
      (setq rbx--input-window
            (or (window-in-direction 'right)
                (split-window (selected-window) nil 'right))))
    (set-window-buffer rbx--input-window input-buffer)
    (unless (window-live-p rbx--result-window)
      (setq rbx--result-window
            (split-window rbx--input-window nil
                          (if (eq rbx-testcase-layout 'beside)
                              'right 'below))))
    (set-window-buffer rbx--result-window result-buffer)
    (select-window rbx--input-window)))

(defun rbx-open-testcase (&optional context)
  "Open the testcase represented by CONTEXT or the section at point."
  (interactive)
  (let ((value (or context (rbx--context))))
    (unless (memq (plist-get value :kind)
                  '(run-testcase testset-testcase))
      (user-error "No testcase at point"))
    (setq rbx--testcase-context value)
    (when (eq (plist-get value :kind) 'testset-testcase)
      (setq rbx--testcase-channel 'output))
    (rbx--display-testcase value)))

(defun rbx--show-channel (channel)
  "Set sticky testcase CHANNEL and redisplay the last testcase."
  (unless rbx--testcase-context
    (let ((context (rbx--context)))
      (when (memq (plist-get context :kind)
                  '(run-testcase testset-testcase))
        (setq rbx--testcase-context context))))
  (unless rbx--testcase-context
    (user-error "Open a testcase first"))
  (setq rbx--testcase-channel channel)
  (rbx--display-testcase rbx--testcase-context))

(defun rbx-show-output ()
  "Show solution output against the expected answer."
  (interactive)
  (rbx--show-channel 'output))

(defun rbx-show-stderr ()
  "Show stderr for the current testcase."
  (interactive)
  (rbx--show-channel 'stderr))

(defun rbx-show-log ()
  "Show the run log for the current testcase."
  (interactive)
  (rbx--show-channel 'log))

(defun rbx-open-input ()
  "Open the input artifact at point read-only."
  (interactive)
  (pop-to-buffer (rbx--read-only-file-buffer
                  (rbx--context-path (rbx--context) 'input))))

(defun rbx-open-expected ()
  "Open the expected-answer artifact at point read-only."
  (interactive)
  (pop-to-buffer (rbx--read-only-file-buffer
                  (rbx--context-path (rbx--context) 'expected))))

(defun rbx-open-output ()
  "Open the solution-output artifact at point read-only."
  (interactive)
  (pop-to-buffer (rbx--read-only-file-buffer
                  (rbx--context-path (rbx--context) 'output))))

(defun rbx-diff-output ()
  "Open a native diff of output against the expected answer."
  (interactive)
  (let ((context (rbx--context)))
    (pop-to-buffer
     (rbx--diff-buffer (rbx--context-path context 'expected)
                       (rbx--context-path context 'output) context))))

(defun rbx-open-solution ()
  "Open the solution represented by the section at point."
  (interactive)
  (let* ((context (rbx--context))
         (package (plist-get context :package))
         (solution (plist-get context :solution)))
    (unless solution (user-error "No solution at point"))
    (find-file (rbx-package-file-path package (rbx-solution-path solution)))))

(defun rbx-open-compilation-log ()
  "Open the compiler output represented by the section at point."
  (interactive)
  (let* ((context (rbx--context))
         (finding (plist-get context :finding))
         (package (plist-get context :package)))
    (unless finding (user-error "No compilation finding at point"))
    (pop-to-buffer
     (rbx--read-only-file-buffer
      (expand-file-name (rbx-compilation-log finding)
                        (rbx-runs-path package))))))

(defun rbx-open-warning ()
  "Visit the source location for the warning at point."
  (interactive)
  (let* ((context (rbx--context))
         (warning (plist-get context :warning))
         (package (plist-get context :package)))
    (unless warning (user-error "No compiler warning at point"))
    (find-file (rbx-package-file-path package (rbx-warning-file warning)))
    (goto-char (point-min))
    (forward-line (1- (rbx-warning-line warning)))))

(defun rbx-open-visualization ()
  "Open the input visualization for the testset testcase at point."
  (interactive)
  (let* ((context (rbx--context))
         (testcase (plist-get context :testcase))
         (test (and (rbx-testset-testcase-p testcase)
                    (rbx-testset-testcase-test testcase)))
         (visualization (and test (rbx-testset-test-visualization test)))
         (path (and visualization
                    (rbx-testset-visualization-input visualization))))
    (unless path (user-error "No input visualization for this testcase"))
    (let ((absolute (rbx-package-file-path (plist-get context :package) path)))
      (if (string-match-p (rx "." (or "html" "htm") string-end) absolute)
          (browse-url-of-file absolute)
        (find-file-other-window absolute)))))

(defun rbx-view-visit ()
  "Visit or toggle the rbx section at point."
  (interactive)
  (let* ((section (magit-current-section))
         (context (and section (oref section value))))
    (pcase (plist-get context :kind)
      ((or 'run-testcase 'testset-testcase) (rbx-open-testcase context))
      ('solution (rbx-open-solution))
      ('compilation (rbx-open-compilation-log))
      ('warning (rbx-open-warning))
      (_ (if section (magit-section-toggle section)
           (user-error "No rbx item at point"))))))

;;;###autoload
(transient-define-prefix rbx-dispatch ()
  "Open rbx views and act on the item at point."
  [["Views"
    ("r" "Run" rbx-run-view)
    ("t" "Tests" rbx-testset-view)
    ("p" "Select problem" rbx-select-package :if-mode rbx-view-mode)
    ("g" "Refresh" rbx-refresh :if-mode rbx-view-mode)]
   ["At point"
    ("RET" "Open" rbx-view-visit :if-mode rbx-view-mode)
    ("i" "Input" rbx-open-input :if-mode rbx-view-mode)
    ("a" "Expected" rbx-open-expected :if-mode rbx-view-mode)
    ("o" "Output" rbx-open-output :if-mode rbx-view-mode)
    ("d" "Diff" rbx-diff-output :if-mode rbx-view-mode)
    ("v" "Visualization" rbx-open-visualization :if-mode rbx-view-mode)]
   ["Sticky testcase channel"
    ("1" "Output vs answer" rbx-show-output :if-mode rbx-view-mode)
    ("2" "Stderr" rbx-show-stderr :if-mode rbx-view-mode)
    ("3" "Log" rbx-show-log :if-mode rbx-view-mode)]])

(provide 'rbx-ui)
;;; rbx-ui.el ends here
