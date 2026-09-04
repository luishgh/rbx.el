;;; test-helper.el --- Test helpers for rbx -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared helpers for the rbx ERT suite.

;;; Code:

(require 'ert)

(defmacro rbx-test-with-directory (binding &rest body)
  "Bind BINDING to a temporary directory while evaluating BODY."
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,binding (make-temp-file "rbx-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,binding t))))

(defun rbx-test-write (root relative contents)
  "Under ROOT, write CONTENTS to RELATIVE and return its full path."
  (let ((path (expand-file-name relative root)))
    (make-directory (file-name-directory path) t)
    (with-temp-file path
      (insert contents))
    path))

(defun rbx-test-write-executable (root name script)
  "Write SCRIPT as an executable shell program named NAME under ROOT."
  (let ((path (expand-file-name name root)))
    (with-temp-file path
      (insert "#!/bin/sh\n" script))
    (set-file-modes path #o755)
    path))

(defun rbx-test-wait (predicate &optional timeout)
  "Process output until PREDICATE is non-nil or TIMEOUT (default 5s) elapses."
  (let ((deadline (+ (float-time) (or timeout 5))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(provide 'test-helper)
;;; test-helper.el ends here

