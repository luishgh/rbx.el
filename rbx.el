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
;; philosophy: it never invokes rbx and never writes generated artifacts.
;;
;; Run `M-x rbx-dispatch' for the main Transient menu, or call
;; `rbx-run-view' and `rbx-testset-view' directly.  Enable `rbx-mode' in
;; solution buffers to publish compiler findings through Flymake.

;;; Code:

(require 'flymake)
(require 'rbx-ui)

(defcustom rbx-compilation-diagnostics t
  "Whether `rbx-mode' publishes compiler findings through Flymake."
  :type 'boolean
  :group 'rbx)

(defvar-keymap rbx-mode-map
  :doc "Keymap for `rbx-mode'."
  "C-c r" #'rbx-dispatch)

(defvar-local rbx--diagnostics-watcher nil
  "Artifact watcher used to refresh Flymake diagnostics.")

(defvar rbx-mode)

(defun rbx--same-file-p (left right)
  "Return non-nil when LEFT and RIGHT name the same local file."
  (and left right
       (if (and (file-exists-p left) (file-exists-p right))
           (file-equal-p left right)
         (equal (expand-file-name left) (expand-file-name right)))))

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
    (when-let ((skeleton (and package (rbx-load-skeleton package))))
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

(defun rbx--stop-diagnostics-watcher ()
  "Stop the current buffer's diagnostics watcher."
  (when rbx--diagnostics-watcher
    (rbx-stop-watcher rbx--diagnostics-watcher)
    (setq rbx--diagnostics-watcher nil)))

(defun rbx--start-diagnostics-watcher ()
  "Start or replace the current buffer's diagnostics watcher."
  (rbx--stop-diagnostics-watcher)
  (when-let ((package (and buffer-file-name (rbx-find-package))))
    (let ((buffer (current-buffer)))
      (setq rbx--diagnostics-watcher
            (rbx-watch-package
             package
             (lambda ()
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (when rbx-mode
                     ;; Re-register after directory creation so a run that
                     ;; started from an empty package becomes recursively
                     ;; visible without polling.
                     (rbx--start-diagnostics-watcher)
                     (flymake-start))))))))))

;;;###autoload
(define-minor-mode rbx-mode
  "Integrate the current rbx package with Emacs.

The mode binds `C-c r' to `rbx-dispatch'.  When
`rbx-compilation-diagnostics' is non-nil, it also makes findings from the most
recent run available to Flymake."
  :lighter " rbx"
  :keymap rbx-mode-map
  :group 'rbx
  (if rbx-mode
      (when rbx-compilation-diagnostics
        (add-hook 'flymake-diagnostic-functions #'rbx-flymake-backend nil t)
        (add-hook 'kill-buffer-hook #'rbx--stop-diagnostics-watcher nil t)
        (rbx--start-diagnostics-watcher)
        (when buffer-file-name
          (flymake-mode 1)
          (flymake-start)))
    (remove-hook 'flymake-diagnostic-functions #'rbx-flymake-backend t)
    (remove-hook 'kill-buffer-hook #'rbx--stop-diagnostics-watcher t)
    (rbx--stop-diagnostics-watcher)))

(provide 'rbx)
;;; rbx.el ends here
