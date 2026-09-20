;;; rbx-integration-test.el --- Integration tests against a real rbx -*- lexical-binding: t; -*-

;;; Commentary:

;; Unlike the hermetic ERT suite, these tests scaffold and run a real
;; problem package with the pinned `rbx' from `.venv-rbx' (see `make
;; rbx-venv') and feed its actual on-disk artifacts to rbx.el's tolerant
;; readers.  Their purpose is to catch drift between those readers and
;; rbx's real output, not to pin exact values -- rbx's own behavior is
;; free to change under a pinned-version bump.
;;
;; They are not part of the hermetic `make check' suite; run them with
;; `make check-integration'.  Every test `skip-unless's the real `rbx'
;; binary so the file loads harmlessly without `.venv-rbx'.

;;; Code:

(require 'rbx-core)
(require 'rbx-model)
(require 'rbx-statement)
(require 'test-helper)

(defconst rbx-integration-test--program
  (expand-file-name
   ".venv-rbx/bin/rbx"
   (locate-dominating-file default-directory "Makefile"))
  "Path to the real `rbx' binary built by `make rbx-venv'.")

(defun rbx-integration-test--run (directory &rest args)
  "Run the real rbx binary with ARGS in DIRECTORY.

Return its combined stdout/stderr.  Signal an error including that output
if rbx exits non-zero."
  (let ((default-directory (file-name-as-directory directory)))
    (with-temp-buffer
      (let ((status (apply #'call-process
                            rbx-integration-test--program nil t nil args)))
        (unless (zerop status)
          (error "rbx %s failed (%s) in %s:\n%s"
                 (string-join args " ") status directory (buffer-string)))
        (buffer-string)))))

(defun rbx-integration-test--create (parent name)
  "Scaffold problem NAME under PARENT using rbx's bundled `default' preset.

Answers the local-preset confirmation prompt non-interactively.  Feeds
stdin through a real OS pipe via `make-process': rbx's prompt library
only takes its answer from a non-interactive stdin when that stdin is a
pipe, not when it is a seekable file -- which is what `call-process' and
`call-process-region' use internally, and what makes them unsuitable
here."
  (let* ((default-directory (file-name-as-directory parent))
         (buffer (generate-new-buffer " *rbx-integration-test-create*"))
         exit-code)
    (unwind-protect
        (let ((process
               (make-process
                :name "rbx-integration-test-create"
                :buffer buffer
                :command (list rbx-integration-test--program
                               "create" "--name" name
                               "--preset" "default" "--local")
                :sentinel (lambda (proc _event)
                            (unless (process-live-p proc)
                              (setq exit-code (process-exit-status proc)))))))
          (process-send-string process "y\n")
          (process-send-eof process)
          (unless (rbx-test-wait (lambda () exit-code) 30)
            (error "rbx create did not exit within 30s"))
          (unless (zerop exit-code)
            (error "rbx create failed (%s):\n%s"
                   exit-code (with-current-buffer buffer (buffer-string)))))
      (kill-buffer buffer))))

(defmacro rbx-integration-test-with-package (binding &rest body)
  "Scaffold a real rbx problem package into BINDING, a temp directory."
  (declare (indent 1) (debug (symbolp body)))
  `(rbx-test-with-directory root
     (rbx-integration-test--create root "demo")
     (let ((,binding (file-name-as-directory (expand-file-name "demo" root))))
       ,@body)))

(ert-deftest rbx-integration-report-testset-and-skeleton-round-trip ()
  (skip-unless (file-executable-p rbx-integration-test--program))
  (rbx-integration-test-with-package demo
    (rbx-integration-test--run demo "run")
    (let ((package (rbx-find-package demo)))
      (should package)

      (let* ((report (rbx-load-report package))
             (solution (car (rbx-run-report-solutions report))))
        (should solution)
        (should (equal (rbx-solution-report-path solution) "sols/main.cpp"))
        (should (stringp (rbx-solution-report-outcome solution)))
        (should (rbx-solution-report-matches-expectation solution)))

      (let* ((skeleton (rbx-load-skeleton package))
             (solution (car (rbx-skeleton-solutions skeleton))))
        (should solution)
        (should (equal (rbx-solution-path solution) "sols/main.cpp"))
        (should (equal (rbx-solution-expected-outcome solution) "ACCEPTED")))

      (let ((testset (rbx-load-testset package)))
        (should testset)
        (should (rbx-testset-groups testset))
        (should (rbx-testset-entries testset)))

      (let ((statements (rbx-load-problem-statements package)))
        (should statements)
        (should (rbx-problem-statement-file (car statements)))))))

(defun rbx-integration-test--vars-command-available-p (directory)
  "Return non-nil when the real rbx binary offers a `vars' command.

Older rbx releases pinned by `rbx-requirements.txt' may predate `rbx
vars'; rbx-statement.el's sole exception to \"never invoke rbx\" is then
simply unexercised, not broken, so callers should skip rather than fail."
  (condition-case nil
      (progn (rbx-integration-test--run directory "vars" "--help") t)
    (error nil)))

(ert-deftest rbx-integration-vars-uses-the-documented-read-only-command ()
  (skip-unless (file-executable-p rbx-integration-test--program))
  (rbx-integration-test-with-package demo
    (skip-unless (rbx-integration-test--vars-command-available-p demo))
    (let ((package (rbx-find-package demo))
          (rbx-program rbx-integration-test--program)
          (payload :pending))
      (rbx-statement-load-vars
       package (lambda (result) (setq payload result)))
      (should (rbx-test-wait (lambda () (not (eq payload :pending))) 15))
      (should payload)
      (should (listp (rbx-statement-vars-payload-vars payload))))))

(provide 'rbx-integration-test)
;;; rbx-integration-test.el ends here
