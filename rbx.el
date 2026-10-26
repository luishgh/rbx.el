;;; rbx.el --- Inspect rbx runs and testsets -*- lexical-binding: t; -*-

;; Copyright (C) 2026 rbx.el contributors

;; Author: rbx.el contributors
;; Maintainer: rbx.el contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (magit-section "4.1.0") (transient "0.7.5"))
;; Keywords: tools, languages
;; URL: https://github.com/luishgh/rbx.el

;;; Commentary:

;; Inspect the files produced by `rbx run' and `rbx build' without leaving
;; Emacs.  The package follows the official VS Code extension's terminal-first
;; philosophy: it never invokes rbx and never writes generated artifacts,
;; with one deliberate exception -- `rbx-statement.el' calls the read-only
;; `rbx vars' to show statement variable hints, exactly as the VS Code
;; extension does.
;;
;; Run `M-x rbx-dispatch' for the main Transient menu, or call
;; `rbx-run-view' and `rbx-testset-view' directly.  Enable `rbx-mode' in
;; solution buffers to publish compiler findings through Flymake, and in
;; statement buffers to show `\VAR{...}' value hints.
;;
;; For evil-mode bindings in `rbx-view-mode', load `rbx-evil.el' from your
;; own configuration once `evil' is loaded, e.g.:
;;
;;   (with-eval-after-load 'evil (require 'rbx-evil))
;;
;; `evil' is never a hard dependency of this package.

;;; Code:

(require 'flymake)
(require 'rbx-ui)
(require 'rbx-statement)

(defcustom rbx-compilation-diagnostics t
  "Whether `rbx-mode' publishes compiler findings through Flymake."
  :type 'boolean
  :group 'rbx)

(defcustom rbx-statement-diagnostics t
  "Whether `rbx-mode' publishes statement build errors through Flymake.
Only TeX buffers are affected."
  :type 'boolean
  :group 'rbx)

(defcustom rbx-statement-var-hints t
  "Whether `rbx-mode' shows `\\VAR{...}' value hints in statement buffers."
  :type 'boolean
  :group 'rbx)

(defconst rbx--statement-hints-delay 0.3
  "Idle seconds to debounce statement hint recomputation after an edit.")

(defface rbx-statement-hint
  '((t :inherit shadow))
  "Face for a statement variable's resolved value hint."
  :group 'rbx)

(defvar-keymap rbx-mode-map
  :doc "Keymap for `rbx-mode'."
  "C-c r" #'rbx-dispatch)

(defvar-local rbx--artifact-watcher nil
  "Artifact watcher used to refresh Flymake diagnostics and statement hints.")

(defvar-local rbx--statement-hint-overlays nil
  "Overlays showing this buffer's statement variable hints.")

(defvar-local rbx--statement-hints-timer nil
  "Idle timer debouncing this buffer's statement hint refresh.")

(defvar rbx-mode)

(defun rbx--diagnostic-region (line)
  "Return a Flymake region for LINE in the current buffer."
  (or (flymake-diag-region (current-buffer) line)
      (cons (point-min) (min (1+ (point-min)) (point-max)))))

(defun rbx--warning-diagnostic (warning)
  "Create a Flymake diagnostic for WARNING."
  (let* ((region (rbx--diagnostic-region (rbx-warning-line warning)))
         (flag (rbx-warning-flag warning))
         (text (concat (rbx-warning-message warning)
                       (if flag (format " (%s)" flag) ""))))
    (flymake-make-diagnostic (current-buffer) (car region) (cdr region)
                             :warning text)))

(defun rbx--failure-diagnostic (finding)
  "Create a Flymake diagnostic for failed compilation FINDING."
  (let ((region (rbx--diagnostic-region 1)))
    (flymake-make-diagnostic
     (current-buffer) (car region) (cdr region) :error
     (or (rbx-compilation-reason finding)
         "rbx failed to compile this solution"))))

(defun rbx-flymake-backend (report-fn &rest _args)
  "Report rbx compilation findings using Flymake REPORT-FN."
  (let ((package (and buffer-file-name (rbx-find-package)))
        diagnostics)
    (when-let* ((skeleton (and package (rbx-load-skeleton package))))
      (dolist (finding (rbx-skeleton-compilation skeleton))
        (let ((finding-file
               (rbx-package-file-path package (rbx-compilation-path finding))))
          (when (and (equal (rbx-compilation-status finding) "FAILED")
                     (rbx--same-file-p buffer-file-name finding-file))
            (push (rbx--failure-diagnostic finding) diagnostics)))
        (dolist (warning (rbx-compilation-warnings finding))
          (let ((warning-file
                 (rbx-package-file-path package (rbx-warning-file warning))))
            (when (rbx--same-file-p buffer-file-name warning-file)
              (push (rbx--warning-diagnostic warning) diagnostics))))))
    (funcall report-fn (nreverse diagnostics))))

;;;; Statement build diagnostics

(defun rbx--statement-tex-buffer-p ()
  "Return non-nil when the current buffer visits a TeX file."
  (and buffer-file-name
       (or (derived-mode-p 'tex-mode)
           (equal (file-name-extension buffer-file-name) "tex"))))

(defun rbx--statement-finding-severity (finding)
  "Return the Flymake type for the `rbx-statement-finding' FINDING."
  (pcase (rbx-statement-finding-severity finding)
    ("error" :error)
    ("warning" :warning)
    (_ :note)))

(defun rbx--statement-output-sources (package output)
  "Return the absolute files an unlocated finding of OUTPUT belongs to.
PACKAGE is the rbx package.  That is the output's recorded source,
else the declared statements in its language."
  (if-let* ((source (rbx-statement-output-source output)))
      (list (rbx-package-file-path package source))
    (let ((language (rbx-statement-output-language output)))
      (mapcar (lambda (statement)
                (rbx-package-file-path package
                                       (rbx-problem-statement-file statement)))
              (seq-filter
               (lambda (statement)
                 (or (null language)
                     (equal (rbx-problem-statement-language statement)
                            language)))
               (rbx-load-problem-statements package))))))

(defun rbx-statement-flymake-backend (report-fn &rest _args)
  "Report statement build errors using Flymake REPORT-FN.

A statement spans several files (the main one plus samples and anything
it includes), so a finding is shown in whichever file it names, as
recorded in the last build report.  A finding naming no file is shown at
the top of the statement's source."
  (let ((package (and buffer-file-name (rbx-find-package)))
        seen diagnostics)
    (when-let* ((report (and package (rbx-load-statement-report package))))
      (dolist (output (rbx-statement-report-outputs report))
        (dolist (finding (rbx-statement-output-findings output))
          (let* ((file (rbx-statement-finding-file finding))
                 (line (rbx-statement-finding-line finding))
                 (message (rbx-statement-finding-message finding))
                 (key (list file line message)))
            (when (and (not (member key seen))
                       (if file
                           (rbx--same-file-p
                            buffer-file-name
                            (rbx-package-file-path package file))
                         (seq-some
                          (lambda (source)
                            (rbx--same-file-p buffer-file-name source))
                          (rbx--statement-output-sources package output))))
              (push key seen)
              (let ((region (rbx--diagnostic-region (or line 1)))
                    (context (rbx-statement-finding-context finding)))
                (push (flymake-make-diagnostic
                       (current-buffer) (car region) (cdr region)
                       (rbx--statement-finding-severity finding)
                       (if context (concat message "\n" context) message))
                      diagnostics)))))))
    (funcall report-fn (nreverse diagnostics))))

(defun rbx--clear-statement-hint-overlays ()
  "Remove this buffer's statement hint overlays."
  (mapc #'delete-overlay rbx--statement-hint-overlays)
  (setq rbx--statement-hint-overlays nil))

(defun rbx--statement-package ()
  "Return the rbx package this buffer's statement belongs to, or nil.

Also nil when `rbx-statement-var-hints' is off or this file is not one of
the package's declared statements."
  (when (and rbx-statement-var-hints buffer-file-name)
    (when-let* ((package (rbx-find-package)))
      (when (rbx-package-statement-p package buffer-file-name)
        package))))

(defun rbx--render-statement-hints (refs package)
  "Render REFS as overlays for PACKAGE, filling filtered ones from the cache.

A filtered ref missing from the render cache is simply skipped this pass;
the render it kicks off re-triggers a refresh once it lands, the same way
`rbx--start-artifact-watcher' already does for an on-disk change.  A
refresh started before a previous one's render lands may show it against
stale positions for one edit's worth of staleness, which self-corrects on
the next refresh -- an absent or momentarily stale hint is preferred over
a wrong one."
  (let ((filtered (delete-dups
                   (mapcar #'rbx-statement-var-ref-expression
                           (seq-filter #'rbx-statement-var-ref-filtered refs))))
        (buffer (current-buffer)))
    (rbx-statement-render
     package filtered
     (lambda (rendered)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (rbx--clear-statement-hint-overlays)
           (dolist (ref refs)
             (let ((text (if (rbx-statement-var-ref-filtered ref)
                              (cdr (assoc (rbx-statement-var-ref-expression ref)
                                          rendered))
                            (rbx-statement-var-ref-text ref))))
               (when text
                 (let ((overlay (make-overlay (rbx-statement-var-ref-end ref)
                                               (rbx-statement-var-ref-end ref))))
                   (overlay-put overlay 'after-string
                                (propertize (format " → %s" text)
                                            'face 'rbx-statement-hint))
                   (push overlay rbx--statement-hint-overlays)))))))))))

(defun rbx--refresh-statement-hints ()
  "Recompute this buffer's statement variable hint overlays."
  (let ((package (rbx--statement-package))
        (buffer (current-buffer)))
    (if (null package)
        (rbx--clear-statement-hint-overlays)
      (rbx-statement-load-vars
       package
       (lambda (payload)
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (if (null payload)
                 (rbx--clear-statement-hint-overlays)
               (rbx--render-statement-hints
                (rbx-statement-scan-buffer payload) package)))))))))

(defun rbx--schedule-statement-hints (&rest _args)
  "Debounce a statement hint refresh after a buffer change."
  (when rbx--statement-hints-timer
    (cancel-timer rbx--statement-hints-timer))
  (let ((buffer (current-buffer)))
    (setq rbx--statement-hints-timer
          (run-at-time
           rbx--statement-hints-delay nil
           (lambda ()
             (setq rbx--statement-hints-timer nil)
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (rbx--refresh-statement-hints))))))))

(defun rbx--enable-statement-hints ()
  "Start showing statement variable hints in this buffer, if applicable."
  (when (rbx--statement-package)
    (add-hook 'after-change-functions #'rbx--schedule-statement-hints nil t)
    (rbx--refresh-statement-hints)))

(defun rbx--disable-statement-hints ()
  "Stop showing statement variable hints in this buffer."
  (remove-hook 'after-change-functions #'rbx--schedule-statement-hints t)
  (when rbx--statement-hints-timer
    (cancel-timer rbx--statement-hints-timer)
    (setq rbx--statement-hints-timer nil))
  (rbx--clear-statement-hint-overlays))

(defun rbx--stop-artifact-watcher ()
  "Stop the current buffer's artifact watcher."
  (when rbx--artifact-watcher
    (rbx-stop-watcher rbx--artifact-watcher)
    (setq rbx--artifact-watcher nil)))

(defun rbx--missing-dependency ()
  "Return why `rbx-mode' cannot run in this buffer, or nil when it can.

Only a buffer inside a package needs yq; the manifest is located without
reading it, since reading YAML is exactly what needs yq."
  (when (locate-dominating-file
         (or (and buffer-file-name (file-name-directory buffer-file-name))
             default-directory)
         rbx-problem-manifest)
    (condition-case err
        (progn (rbx-ensure-yq) nil)
      (user-error (error-message-string err)))))

(defun rbx--start-artifact-watcher ()
  "Start or replace the current buffer's artifact watcher."
  (rbx--stop-artifact-watcher)
  (when-let* ((package (and buffer-file-name (rbx-find-package))))
    (let ((buffer (current-buffer)))
      (setq rbx--artifact-watcher
            (rbx-watch-package
             package
             (lambda ()
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (when rbx-mode
                     (when (or rbx-compilation-diagnostics
                               (memq #'rbx-statement-flymake-backend
                                     flymake-diagnostic-functions))
                       (flymake-start))
                     (when rbx-statement-var-hints
                       (rbx-statement-invalidate package)
                       (rbx--refresh-statement-hints)))))))))))

;;;###autoload
(define-minor-mode rbx-mode
  "Integrate the current rbx package with Emacs.

The mode binds `C-c r' to `rbx-dispatch'.  When
`rbx-compilation-diagnostics' is non-nil, it also makes findings from the
most recent run available to Flymake, and with `rbx-statement-diagnostics'
it does the same for statement build errors in TeX buffers.  When
`rbx-statement-var-hints' is non-nil and this file is one of the package's
declared statements, it shows what each `\\VAR{...}' reference resolves to.

Inside a package the mode needs mikefarah/yq; without it the mode stays
off, warning once when enabled from a hook."
  :lighter " rbx"
  :keymap rbx-mode-map
  :group 'rbx
  (if rbx-mode
      (if-let* ((problem (rbx--missing-dependency)))
          (progn
            (setq rbx-mode nil)
            ;; From a major-mode hook, warn instead of aborting the user's
            ;; other hooks and the file visit itself.
            (if (called-interactively-p 'any)
                (user-error "%s" problem)
              (rbx--warn-once 'yq problem)))
        (when rbx-compilation-diagnostics
          (add-hook 'flymake-diagnostic-functions #'rbx-flymake-backend nil t))
        (when (and rbx-statement-diagnostics (rbx--statement-tex-buffer-p))
          (add-hook 'flymake-diagnostic-functions
                    #'rbx-statement-flymake-backend nil t))
        (when (or rbx-compilation-diagnostics rbx-statement-var-hints
                  (memq #'rbx-statement-flymake-backend
                        flymake-diagnostic-functions))
          (add-hook 'kill-buffer-hook #'rbx--stop-artifact-watcher nil t)
          (rbx--start-artifact-watcher))
        (when (and buffer-file-name
                   (or rbx-compilation-diagnostics
                       (memq #'rbx-statement-flymake-backend
                             flymake-diagnostic-functions)))
          (flymake-mode 1)
          (flymake-start))
        (rbx--enable-statement-hints))
    (remove-hook 'flymake-diagnostic-functions #'rbx-flymake-backend t)
    (remove-hook 'flymake-diagnostic-functions
                 #'rbx-statement-flymake-backend t)
    (remove-hook 'kill-buffer-hook #'rbx--stop-artifact-watcher t)
    (rbx--stop-artifact-watcher)
    (rbx--disable-statement-hints)))

(provide 'rbx)
;;; rbx.el ends here
