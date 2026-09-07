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

(define-fringe-bitmap 'rbx-fringe-tick
  [#x00 #x01 #x02 #x04 #x88 #x50 #x20 #x00])

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
(defclass rbx-statistics-section (magit-section) ())
(defclass rbx-gallery-group-section (magit-section) ())
(defclass rbx-gallery-testcase-section (magit-section) ())
(defclass rbx-contest-section (magit-section) ())
(defclass rbx-contest-variant-section (magit-section) ())
(defclass rbx-contest-problem-section (magit-section) ())

(defvar-keymap rbx-view-mode-map
  :doc "Keymap for `rbx-view-mode'."
  :parent magit-section-mode-map
  "RET" #'rbx-view-visit
  "g" #'rbx-refresh
  "?" #'rbx-dispatch
  "q" #'quit-window)

(defvar-local rbx--package nil
  "Package displayed in the current rbx view.")

(defvar-local rbx--contest-root nil
  "Contest root displayed in the current rbx contest view.")

(defvar-local rbx--contest-watchers nil
  "Watchers used to follow the contest's active problem, when following.

Non-nil exactly when the current run view is following, per
`rbx-toggle-contest-follow'.")

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

(defvar-local rbx--fringe-overlays nil
  "Overlays showing per-solution fringe indicators in the current run view.")

(define-derived-mode rbx-view-mode magit-section-mode "rbx"
  "Major mode for browsing rbx run and testset artifacts."
  :group 'rbx
  (setq-local revert-buffer-function
              (lambda (&rest _ignored) (rbx-refresh)))
  (add-hook 'kill-buffer-hook #'rbx--stop-buffer-watcher nil t)
  (add-hook 'kill-buffer-hook #'rbx--stop-contest-follow nil t))

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

(defun rbx--solution-fringe-spec (state)
  "Return a (BITMAP . FACE) fringe spec for solution row STATE.

STATE is one of `rbx--row-state's values."
  (pcase state
    ('met (cons 'rbx-fringe-tick 'rbx-match))
    ('missed (cons 'right-triangle 'rbx-mismatch))
    ('warned (cons 'exclamation-mark 'rbx-warning))))

(defun rbx--clear-fringe-overlays ()
  "Remove this buffer's solution fringe overlays."
  (mapc #'delete-overlay rbx--fringe-overlays)
  (setq rbx--fringe-overlays nil))

(defun rbx--insert-solution-fringe (state)
  "Place a fringe indicator for STATE on the line just inserted at point."
  (let* ((spec (rbx--solution-fringe-spec state))
         (beg (line-beginning-position 0))
         (overlay (make-overlay beg (1+ beg))))
    (overlay-put overlay 'before-string
                 (propertize "!" 'display
                            (list 'left-fringe (car spec) (cdr spec))))
    (push overlay rbx--fringe-overlays)))

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
         (state (and solution-report
                    (rbx--row-state
                     (rbx-solution-report-matches-expectation solution-report)
                     warning)))
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
            state)
         (format "… %s  declared %s  %d/%d\n"
                 (rbx--fontify
                  (rbx--solution-label solution
                                       (rbx-skeleton-solutions skeleton))
                  (rbx--expected-face-value
                   (rbx-solution-expected-outcome solution)))
                 (rbx--expected (rbx-solution-expected-outcome solution))
                 (car progress) (cdr progress))))
      (when state
        (rbx--insert-solution-fringe state))
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
  (rbx--clear-fringe-overlays)
  (if-let ((skeleton (rbx-load-skeleton package)))
      (let ((report (rbx-load-report package))
            (groups (rbx-skeleton-ordered-groups skeleton))
            (entries-by-group
             (rbx--entries-by-group (rbx-skeleton-entries skeleton))))
        (magit-insert-section
            (rbx-root-section (list :kind 'root :package package))
          (magit-insert-heading
           (format "Run · %s%s%s\n"
                   (rbx--package-heading-label
                    package (abbreviate-file-name (rbx-package-root package)))
                   (if rbx--contest-watchers " · following" "")
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
      (magit-insert-heading
       (format "Run%s" (if rbx--contest-watchers " · following" "")))
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

(defun rbx--context-testcase-entry (context)
  "Return CONTEXT's underlying `rbx-testcase' entry.

CONTEXT may be a `run-testcase' context, whose :testcase value already is
the entry, or a `testset-testcase' context, whose :testcase value wraps it
in an `rbx-testset-testcase'."
  (let ((testcase (plist-get context :testcase)))
    (if (rbx-testset-testcase-p testcase)
        (rbx-testset-testcase-entry testcase)
      testcase)))

(defun rbx--testcase-info-lines (context)
  "Return (METADATA-LINES . MESSAGE) describing the testcase at CONTEXT.

METADATA-LINES is a list of short strings meant to be shown one per line.
MESSAGE is the checker's or validator's own message, to be shown in full
afterwards, or nil when there is none."
  (let* ((kind (plist-get context :kind))
         (testcase (plist-get context :testcase))
         (entry (rbx--context-testcase-entry context))
         (stem (if (eq kind 'run-testcase)
                  (rbx-testcase-stem entry)
                (rbx-testset-testcase-stem testcase)))
         (header (list (format "Testcase: %s" stem)
                      (format "Origin: %s" (rbx--testcase-provenance entry)))))
    (pcase kind
      ('run-testcase
       (let ((evaluation (plist-get context :evaluation)))
         (if (null evaluation)
             (cons (append header (list "No evaluation yet.")) nil)
           (cons (append header
                        (list (format "Verdict: %s"
                                     (rbx-outcome-short-name
                                      (rbx-evaluation-outcome evaluation)))
                             (rbx--meta
                              (rbx-format-time (rbx-evaluation-time evaluation))
                              (rbx-format-memory
                               (rbx-evaluation-memory evaluation))
                              (and (rbx-evaluation-sanitizer-warnings evaluation)
                                  "sanitizer"))))
                (rbx-evaluation-message evaluation)))))
      ('testset-testcase
       (let* ((test (rbx-testset-testcase-test testcase))
             (validation (and test (rbx-testset-test-validation test))))
         (if (null validation)
             (cons (append header (list "No validation recorded.")) nil)
           (cons (append header
                        (list (format "Validator: %s"
                                     (or (rbx-testset-validation-result-validator
                                          validation)
                                        "unknown"))
                             (format "Validation: %s"
                                    (if (rbx-testset-validation-result-ok
                                         validation)
                                        "ok" "failed"))))
                (rbx-testset-validation-result-message validation)))))
      (_ (user-error "No testcase at point")))))

(defun rbx-show-testcase-info (&optional context)
  "Show a dedicated info card for the testcase at CONTEXT.

Shows the full test origin — including for run testcases, unlike the
truncated inline summary — and, when available, the checker's or
validator's own message in full and wrapped rather than truncated."
  (interactive)
  (let* ((result (rbx--testcase-info-lines (or context (rbx--context))))
         (lines (car result))
         (message (cdr result))
         (buffer (get-buffer-create "*rbx testcase info*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (dolist (line lines) (insert line "\n"))
        (when (and message (not (string-empty-p message)))
          (insert "\n")
          (let ((start (point)))
            (insert message "\n")
            (fill-region start (point))))
        (goto-char (point-min)))
      (view-mode 1))
    (display-buffer buffer)))

(defun rbx-visit-testcase-source (&optional context)
  "Visit the source behind the testcase at CONTEXT.

Jumps to the recorded generator script line, or opens the copied-from file
when there is no generator script.  Returns the buffer now visiting it."
  (interactive)
  (let* ((value (or context (rbx--context)))
         (package (plist-get value :package))
         (entry (and (memq (plist-get value :kind)
                          '(run-testcase testset-testcase))
                    (rbx--context-testcase-entry value))))
    (unless entry (user-error "No testcase at point"))
    (cond
     ((rbx-testcase-generator-script entry)
      (let ((buffer (find-file
                    (rbx-package-file-path
                     package (rbx-testcase-generator-script entry)))))
        (goto-char (point-min))
        (forward-line (1- (or (rbx-testcase-generator-script-line entry) 1)))
        buffer))
     ((rbx-testcase-copied-from entry)
      (find-file
       (rbx-package-file-path package (rbx-testcase-copied-from entry))))
     (t (user-error "No source location recorded for this testcase")))))

(defun rbx-open-validator (&optional context)
  "Open the validator source for the testset testcase at CONTEXT."
  (interactive)
  (let* ((value (or context (rbx--context)))
         (testcase (plist-get value :testcase))
         (test (and (rbx-testset-testcase-p testcase)
                   (rbx-testset-testcase-test testcase)))
         (validation (and test (rbx-testset-test-validation test)))
         (validator (and validation
                        (rbx-testset-validation-result-validator validation))))
    (unless validator (user-error "No validator recorded for this testcase"))
    (find-file (rbx-package-file-path (plist-get value :package) validator))))

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

(defconst rbx--statistics-bar-width 20
  "Column width of the bar drawn in the testset statistics section.")

(defun rbx--statistics-bar (value maximum)
  "Return a proportional bar for VALUE out of MAXIMUM."
  (let ((filled (if (> maximum 0)
                   (round (* rbx--statistics-bar-width (/ (float value) maximum)))
                 0)))
    (rbx--fontify
     (concat (make-string filled ?█)
            (make-string (- rbx--statistics-bar-width filled) ?·))
     'rbx-hue-blue)))

(defun rbx--insert-testset-statistics (testset)
  "Insert aggregate size and count statistics for TESTSET."
  (when-let ((stats (rbx-testset-statistics testset)))
    (let* ((total-count
           (apply #'+ (mapcar #'rbx-testset-group-stats-count stats)))
          (total-input
           (apply #'+ (mapcar #'rbx-testset-group-stats-input-size stats)))
          (total-output
           (apply #'+ (mapcar #'rbx-testset-group-stats-output-size stats)))
          (largest
           (apply #'max 1 (mapcar #'rbx-testset-group-stats-input-size stats))))
      (magit-insert-section (rbx-statistics-section nil t)
        (magit-insert-heading
         (format "Testset statistics · %d testcase%s · %s\n"
                total-count (if (= total-count 1) "" "s")
                (rbx--format-size (+ total-input total-output))))
        (dolist (group-stats stats)
          (insert
           (format "  %-12s %s  %s\n"
                  (rbx-testset-group-stats-group group-stats)
                  (rbx--statistics-bar
                   (rbx-testset-group-stats-input-size group-stats) largest)
                  (rbx--meta
                   (format "%d testcase%s"
                          (rbx-testset-group-stats-count group-stats)
                          (if (= (rbx-testset-group-stats-count group-stats) 1)
                              "" "s"))
                   (format "in %s"
                          (rbx--format-size
                           (rbx-testset-group-stats-input-size group-stats)))
                   (format "out %s"
                          (rbx--format-size
                           (rbx-testset-group-stats-output-size
                            group-stats)))))))))))

(defun rbx--insert-testset-view (package)
  "Insert PACKAGE's testset view at point."
  (if-let ((testset (rbx-load-testset package)))
      (magit-insert-section
          (rbx-root-section (list :kind 'root :package package))
        (magit-insert-heading
         (format "Tests · %s%s\n"
                 (rbx--package-heading-label
                  package (abbreviate-file-name (rbx-package-root package)))
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
        (rbx--insert-coverage testset)
        (rbx--insert-testset-statistics testset))
    (magit-insert-section
        (rbx-root-section (list :kind 'root :package package))
      (magit-insert-heading "Tests")
      (insert (propertize
               "No testset manifest yet.  Run `rbx build` in your terminal.\n"
               'face 'shadow)))))

(defconst rbx--gallery-thumbnail-width 200
  "Maximum pixel width of a thumbnail in the visualization gallery.")

(defun rbx--visualization-thumbnail (path)
  "Return a thumbnail `create-image' spec for PATH, or nil.

Returns nil for an HTML PATH (browsable, not thumbnailable), a missing or
unreadable file, or any image Emacs cannot create."
  (unless (string-match-p (rx "." (or "html" "htm") string-end) path)
    (and (file-readable-p path)
        (ignore-errors
          (create-image path nil nil :max-width rbx--gallery-thumbnail-width)))))

(defun rbx--insert-gallery-testcase (package testcase)
  "Insert TESTCASE's input visualization thumbnail or link, for PACKAGE."
  (let* ((path (rbx--testset-testcase-visualization-path testcase 'input))
         (absolute (rbx-package-file-path package path))
         (image (rbx--visualization-thumbnail absolute))
         (context (list :kind 'gallery-visualization
                        :package package :path absolute)))
    (magit-insert-section (rbx-gallery-testcase-section context)
      (magit-insert-heading
       (if image
          (concat (propertize (rbx-testset-testcase-stem testcase)
                              'display image)
                 "\n")
        (format "%s  %s\n"
               (rbx-testset-testcase-stem testcase)
               (rbx--fontify (file-name-nondirectory absolute) 'link)))))))

(defun rbx--insert-gallery-groups (package testset)
  "Insert one gallery block per TESTSET group with a visualization.

PACKAGE resolves the package-relative visualization paths recorded in
TESTSET."
  (let ((any nil))
    (dolist (group (rbx-testset-ordered-groups testset))
      (let ((testcases
            (seq-filter
             (lambda (testcase)
               (rbx--testset-testcase-visualization-path testcase 'input))
             (rbx--testset-cases-for-group testset group))))
        (when testcases
          (setq any t)
          (magit-insert-section
              (rbx-gallery-group-section (list :kind 'gallery-group
                                               :group group))
            (magit-insert-heading (format "%s\n" group))
            (dolist (testcase testcases)
              (rbx--insert-gallery-testcase package testcase))))))
    (unless any
      (insert (propertize "No visualizations found in this testset.\n"
                          'face 'shadow)))))

(defun rbx--insert-gallery-view (package)
  "Insert PACKAGE's visualization gallery at point."
  (if-let ((testset (rbx-load-testset package)))
      (magit-insert-section
          (rbx-root-section (list :kind 'root :package package))
        (magit-insert-heading
         (format "Visualizations · %s\n"
                (rbx--package-heading-label
                 package (abbreviate-file-name (rbx-package-root package)))))
        (rbx--insert-gallery-groups package testset))
    (magit-insert-section
        (rbx-root-section (list :kind 'root :package package))
      (magit-insert-heading "Visualizations")
      (insert (propertize
               "No testset manifest yet.  Run `rbx build` in your terminal.\n"
               'face 'shadow)))))

(defun rbx--insert-contest-problem (contest-root problem)
  "Insert PROBLEM declared under CONTEST-ROOT."
  (let* ((resolved (rbx-contest-problem-resolved-path problem contest-root))
         (context (list :kind 'contest-problem :package-path resolved)))
    (magit-insert-section (rbx-contest-problem-section context)
      (magit-insert-heading
       (format "  %s  %s\n"
               (rbx--contest-label problem)
               (file-name-nondirectory (directory-file-name resolved)))))))

(defun rbx--insert-contest-variant (contest-root contest)
  "Insert one variant block for CONTEST declared under CONTEST-ROOT."
  (let ((context (list :kind 'contest-variant :contest contest)))
    (magit-insert-section (rbx-contest-variant-section context t)
      (magit-insert-heading
       (format "%s\n" (or (rbx-contest-variant-id contest) "Canonical")))
      (dolist (problem (rbx-contest-problems contest))
        (rbx--insert-contest-problem contest-root problem)))))

(defun rbx--insert-contest-view (contest-root)
  "Insert the contest at CONTEST-ROOT, one block per declared variant.

Every variant is shown side by side because rbx never records which `-C'
selection a terminal invocation used."
  (magit-insert-section
      (rbx-contest-section (list :kind 'root :contest-root contest-root))
    (magit-insert-heading
     (format "Contest · %s\n" (abbreviate-file-name contest-root)))
    (let ((contests (rbx-load-contest-variants contest-root)))
      (if (null contests)
          (insert (propertize
                   "No contest.rbx.yml found here.\n" 'face 'shadow))
        (dolist (contest contests)
          (rbx--insert-contest-variant contest-root contest))))))

(defun rbx-refresh ()
  "Refresh the current rbx artifact view."
  (interactive)
  (unless (and (derived-mode-p 'rbx-view-mode)
              rbx--view
              (pcase rbx--view
                ('contest rbx--contest-root)
                (_ rbx--package)))
    (user-error "This is not an initialized rbx view"))
  (let ((inhibit-read-only t)
        (line (line-number-at-pos)))
    (erase-buffer)
    (pcase rbx--view
      ('run (rbx--insert-run-view rbx--package))
      ('testset (rbx--insert-testset-view rbx--package))
      ('contest (rbx--insert-contest-view rbx--contest-root))
      ('gallery (rbx--insert-gallery-view rbx--package))
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

(defun rbx--contest-follow-candidates ()
  "Return the run view's contest member packages, or nil outside a contest."
  (when-let* ((membership (and rbx--package
                              (rbx-package-contest-membership rbx--package)))
             (root (rbx-contest-membership-root membership))
             (contest (rbx-contest-membership-contest membership)))
    (delq nil
          (mapcar
           (lambda (problem)
             (rbx-find-package
              (rbx-contest-problem-resolved-path problem root)))
           (rbx-contest-problems contest)))))

(defun rbx--most-recently-touched (packages)
  "Return whichever of PACKAGES most recently produced run artifacts."
  (car
   (car
    (sort
     (delq nil
          (mapcar
           (lambda (package)
             (when-let ((mtime (file-attribute-modification-time
                                (file-attributes
                                 (rbx-skeleton-path package)))))
               (cons package mtime)))
           packages))
     (lambda (a b) (time-less-p (cdr b) (cdr a)))))))

(defun rbx--stop-contest-follow ()
  "Stop the current buffer's contest auto-follow watchers, if any."
  (when rbx--contest-watchers
    (mapc #'rbx-stop-watcher rbx--contest-watchers)
    (setq rbx--contest-watchers nil)))

(defun rbx--start-contest-follow (candidates)
  "Start following whichever of CANDIDATES is most recently active."
  (let ((buffer (current-buffer)))
    (setq rbx--contest-watchers
         (rbx-watch-contest
          candidates
          (lambda (_package)
            (when (buffer-live-p buffer)
              (with-current-buffer buffer
                (when-let ((latest (rbx--most-recently-touched candidates)))
                  (unless (equal latest rbx--package)
                    (setq rbx--package latest)
                    (rbx--start-buffer-watcher)))
                (rbx-refresh))))))))

(defun rbx-toggle-contest-follow ()
  "Toggle following the contest's currently active problem in this view.

Since `rbx contest each run' leaves no on-disk marker for which problem is
running, this follows whichever contest member most recently produced run
artifacts."
  (interactive)
  (unless (derived-mode-p 'rbx-view-mode)
    (user-error "This is not an rbx view"))
  (if rbx--contest-watchers
      (progn (rbx--stop-contest-follow) (rbx-refresh))
    (let ((candidates (rbx--contest-follow-candidates)))
      (unless candidates
        (user-error "The current package is not part of a contest"))
      (rbx--start-contest-follow candidates)
      (rbx-refresh))))

(defun rbx--project-root ()
  "Return the current project root or `default-directory'."
  (if-let ((project (project-current nil)))
      (project-root project)
    default-directory))

(defun rbx--contest-hex-color (problem)
  "Return a normalized \"#rrggbb\" string for PROBLEM's declared color.

Accepts the hex forms rbx itself accepts (`#abc' and `#abcdef') verbatim, and
falls back to Emacs's own color resolution for X11 color names.  Returns nil
when PROBLEM has no color or it cannot be resolved."
  (when-let ((color (or (rbx-contest-problem-color problem)
                        (rbx-contest-problem-color-name problem))))
    (cond
     ((string-match
       "\\`#\\([0-9a-fA-F]\\)\\([0-9a-fA-F]\\)\\([0-9a-fA-F]\\)\\'" color)
      (concat "#" (mapconcat (lambda (n) (let ((digit (match-string n color)))
                                          (concat digit digit)))
                             '(1 2 3) "")))
     ((string-match-p "\\`#[0-9a-fA-F]\\{6\\}\\'" color) color)
     (t (when-let ((values (ignore-errors (color-values color))))
         (apply #'format "#%02x%02x%02x"
                (mapcar (lambda (component) (ash component -8)) values)))))))

(defun rbx--contest-label (problem)
  "Return PROBLEM's short name, colored by its declared color when known."
  (let ((short-name (rbx-contest-problem-short-name problem))
        (hex (rbx--contest-hex-color problem)))
    (if hex (rbx--fontify short-name (list :foreground hex)) short-name)))

(defun rbx--contest-short-name-collides-p (memberships membership)
  "Return non-nil when MEMBERSHIP's short name recurs under another contest.

MEMBERSHIPS is the full list of `rbx-contest-membership' values (or nil)
being displayed together, used to detect divisions that share a letter."
  (and membership
       (cl-some
        (lambda (other)
          (and other
              (not (equal (rbx-contest-membership-root other)
                          (rbx-contest-membership-root membership)))
              (equal (rbx-contest-problem-short-name
                     (rbx-contest-membership-problem other))
                    (rbx-contest-problem-short-name
                     (rbx-contest-membership-problem membership)))))
        memberships)))

(defun rbx--package-label (package root membership collides)
  "Return PACKAGE's completion/display label.

MEMBERSHIP is PACKAGE's `rbx-contest-membership', when any, and ROOT is the
directory relative labels fall back to outside a contest.  When COLLIDES is
non-nil, the owning contest's name is prefixed so that two divisions sharing
a letter, e.g. both starting at \"A\", stay visually distinct."
  (if membership
      (let* ((problem (rbx-contest-membership-problem membership))
             (contest-name (rbx-contest-name
                           (rbx-contest-membership-contest membership)))
             (qualifier (and collides (not (string-empty-p contest-name))
                            (concat contest-name " · "))))
        (concat (or qualifier "") (rbx--contest-label problem) "  "
               (file-name-nondirectory
                (directory-file-name (rbx-package-root package)))))
    (file-relative-name (rbx-package-root package) root)))

(defun rbx--package-heading-label (package fallback)
  "Return PACKAGE's contest letter/name label, or FALLBACK outside a contest."
  (if-let ((membership (rbx-package-contest-membership package)))
      (concat (rbx--contest-label (rbx-contest-membership-problem membership))
             " · " (file-name-nondirectory
                    (directory-file-name (rbx-package-root package))))
    fallback))

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
              (memberships (mapcar #'rbx-package-contest-membership packages))
              (choices
               (cl-mapcar
                (lambda (package membership)
                  (cons (rbx--package-label
                        package root membership
                        (rbx--contest-short-name-collides-p
                         memberships membership))
                       package))
                packages memberships)))
         (cdr (assoc (completing-read "rbx problem: " choices nil t)
                     choices)))))))

(defun rbx--open-view (view &optional package)
  "Open VIEW for PACKAGE."
  (let* ((selected (or package (rbx--select-package)))
         (label (rbx--package-heading-label
                 selected (file-name-nondirectory
                          (directory-file-name (rbx-package-root selected)))))
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

;;;###autoload
(defun rbx-visualization-gallery (&optional package)
  "Open a visualization gallery for PACKAGE's built testset."
  (interactive)
  (rbx--open-view 'gallery package))

;;;###autoload
(defun rbx-contest-view (&optional contest-root)
  "Open the contest view for CONTEST-ROOT.

CONTEST-ROOT defaults to the contest owning the package shown in the
current view, or the nearest contest to `default-directory'."
  (interactive)
  (let* ((root (or contest-root
                   (rbx-find-contest-root
                    (if rbx--package
                        (rbx-package-root rbx--package)
                      default-directory)))))
    (unless root (user-error "No contest.rbx.yml found"))
    (let ((buffer (get-buffer-create
                   (format "*rbx contest: %s*"
                          (file-name-nondirectory
                           (directory-file-name root))))))
      (let ((window (display-buffer-in-side-window
                    buffer '((side . left) (slot . -1) (window-width . 0.32)))))
        (select-window window))
      (unless (derived-mode-p 'rbx-view-mode)
        (rbx-view-mode))
      (setq rbx--contest-root root
           rbx--view 'contest
           default-directory root)
      (rbx-refresh)
      buffer)))

(defun rbx-select-package ()
  "Select another problem for the current rbx view."
  (interactive)
  (unless (derived-mode-p 'rbx-view-mode)
    (user-error "This is not an rbx view"))
  (rbx--stop-contest-follow)
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

(defun rbx--open-visualization-path (path)
  "Open visualization PATH, browsing HTML and visiting anything else.

Returns whatever `browse-url-of-file' or `find-file-other-window' returns."
  (if (string-match-p (rx "." (or "html" "htm") string-end) path)
      (browse-url-of-file path)
    (find-file-other-window path)))

(defun rbx--testset-test-visualization-path (test channel)
  "Return TEST's CHANNEL visualization path, or nil.

CHANNEL is `input' or `output'."
  (let ((visualization (and test (rbx-testset-test-visualization test))))
    (and visualization
        (pcase channel
          ('input (rbx-testset-visualization-input visualization))
          ('output (rbx-testset-visualization-output visualization))))))

(defun rbx--testset-testcase-visualization-path (testcase channel)
  "Return TESTCASE's CHANNEL visualization path, or nil.

CHANNEL is `input' or `output'."
  (rbx--testset-test-visualization-path
   (rbx-testset-testcase-test testcase) channel))

(defun rbx--context-testset-test (context)
  "Return the `rbx-testset-test' backing CONTEXT, or nil.

CONTEXT may be a `testset-testcase' context, whose :testcase value already
wraps the test, or a `run-testcase' context, whose :testcase value is a bare
`rbx-testcase' entry looked up by group and index in the package's testset."
  (let ((testcase (plist-get context :testcase)))
    (pcase (plist-get context :kind)
      ('testset-testcase (rbx-testset-testcase-test testcase))
      ('run-testcase
       (when-let* ((package (plist-get context :package))
                   (testset (rbx-load-testset package)))
         (rbx-testset-find-test testset
                                (rbx-testcase-group testcase)
                                (rbx-testcase-index testcase)))))))

(defun rbx-open-visualization (&optional context)
  "Open the input visualization for the testcase at CONTEXT."
  (interactive)
  (let* ((value (or context (rbx--context)))
         (path (rbx--testset-test-visualization-path
                (rbx--context-testset-test value) 'input)))
    (unless path (user-error "No input visualization for this testcase"))
    (rbx--open-visualization-path
     (rbx-package-file-path (plist-get value :package) path))))

(defun rbx-open-answer-visualization (&optional context)
  "Open the answer visualization for the testcase at CONTEXT."
  (interactive)
  (let* ((value (or context (rbx--context)))
         (path (rbx--testset-test-visualization-path
                (rbx--context-testset-test value) 'output)))
    (unless path (user-error "No answer visualization for this testcase"))
    (rbx--open-visualization-path
     (rbx-package-file-path (plist-get value :package) path))))

(defun rbx-open-contest-problem (&optional context)
  "Open the run view for the contest problem represented by CONTEXT."
  (interactive)
  (let* ((value (or context (rbx--context)))
         (path (plist-get value :package-path))
         (package (and path (rbx-find-package path))))
    (unless package
      (user-error "No problem.rbx.yml found for this entry"))
    (rbx-run-view package)))

(defun rbx-open-gallery-visualization (&optional context)
  "Open the visualization gallery entry at CONTEXT full-size."
  (interactive)
  (let* ((value (or context (rbx--context)))
         (path (plist-get value :path)))
    (unless path (user-error "No visualization at point"))
    (rbx--open-visualization-path path)))

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
      ('contest-problem (rbx-open-contest-problem context))
      ('gallery-visualization (rbx-open-gallery-visualization context))
      (_ (if section (magit-section-toggle section)
           (user-error "No rbx item at point"))))))

;;;###autoload
(transient-define-prefix rbx-dispatch ()
  "Open rbx views and act on the item at point."
  [["Views"
    ("r" "Run" rbx-run-view)
    ("t" "Tests" rbx-testset-view)
    ("c" "Contest" rbx-contest-view)
    ("G" "Visualizations" rbx-visualization-gallery)
    ("p" "Select problem" rbx-select-package :if-mode rbx-view-mode)
    ("f" "Follow running problem" rbx-toggle-contest-follow
     :if-mode rbx-view-mode)
    ("g" "Refresh" rbx-refresh :if-mode rbx-view-mode)]
   ["At point"
    ("RET" "Open" rbx-view-visit :if-mode rbx-view-mode)
    ("i" "Input" rbx-open-input :if-mode rbx-view-mode)
    ("a" "Expected" rbx-open-expected :if-mode rbx-view-mode)
    ("o" "Output" rbx-open-output :if-mode rbx-view-mode)
    ("d" "Diff" rbx-diff-output :if-mode rbx-view-mode)
    ("v" "Input visualization" rbx-open-visualization :if-mode rbx-view-mode)
    ("A" "Answer visualization" rbx-open-answer-visualization
     :if-mode rbx-view-mode)
    ("m" "Testcase info" rbx-show-testcase-info :if-mode rbx-view-mode)
    ("s" "Visit source" rbx-visit-testcase-source :if-mode rbx-view-mode)
    ("V" "Open validator" rbx-open-validator :if-mode rbx-view-mode)]
   ["Sticky testcase channel"
    ("1" "Output vs answer" rbx-show-output :if-mode rbx-view-mode)
    ("2" "Stderr" rbx-show-stderr :if-mode rbx-view-mode)
    ("3" "Log" rbx-show-log :if-mode rbx-view-mode)]])

(provide 'rbx-ui)
;;; rbx-ui.el ends here
