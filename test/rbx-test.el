;;; rbx-test.el --- Integration tests for rbx -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for editor integration exposed by the main package.

;;; Code:

(require 'rbx)
(require 'test-helper)

(ert-deftest rbx-flymake-reports-published-compiler-findings ()
  (rbx-test-with-directory root
    (let ((source (rbx-test-write root "sols/wa.cpp" "int main() {\n}\n")))
      (rbx-test-write root "problem.rbx.yml" "name: Demo\n")
      (rbx-test-write
       root ".rbx/runs/skeleton.yml"
       (concat
        "solutions: []\nentries: []\ngroups: []\ncompilation:\n"
        "  - path: sols/wa.cpp\n    outcome: WRONG_ANSWER\n"
        "    status: WARNINGS\n    log: compilation/0.log\n"
        "    warnings:\n      - file: sols/wa.cpp\n        line: 1\n"
        "        flag: -Wshadow\n        msg: declaration shadows x\n"))
      (let ((buffer (find-file-noselect source))
            diagnostics)
        (unwind-protect
            (with-current-buffer buffer
              (rbx-flymake-backend (lambda (items) (setq diagnostics items)))
              (should (= (length diagnostics) 1))
              (let ((diagnostic (car diagnostics)))
                (should (eq (flymake-diagnostic-type diagnostic) :warning))
                (should (string-match-p
                         "declaration shadows x.*-Wshadow"
                         (flymake-diagnostic-text diagnostic)))
                (should (= (line-number-at-pos
                            (flymake-diagnostic-beg diagnostic))
                           1))))
          (kill-buffer buffer))))))

(ert-deftest rbx-mode-installs-and-removes-its-flymake-backend ()
  (with-temp-buffer
    (rbx-mode 1)
    (should (memq #'rbx-flymake-backend flymake-diagnostic-functions))
    (rbx-mode -1)
    (should-not (memq #'rbx-flymake-backend flymake-diagnostic-functions))))

(ert-deftest rbx-mode-refreshes-diagnostics-after-artifact-changes ()
  (rbx-test-with-directory root
    (let ((source (rbx-test-write root "sols/main.cpp" "int main() {}\n"))
          callback
          stopped
          (starts 0))
      (rbx-test-write root "problem.rbx.yml" "name: Demo\n")
      (let ((buffer (find-file-noselect source)))
        (unwind-protect
            (cl-letf (((symbol-function 'rbx-watch-package)
                       (lambda (_package function)
                         (setq callback function)
                         'watcher))
                      ((symbol-function 'rbx-stop-watcher)
                       (lambda (watcher) (setq stopped watcher)))
                      ((symbol-function 'flymake-start)
                       (lambda (&rest _args) (cl-incf starts))))
              (with-current-buffer buffer
                (rbx-mode 1)
                (should callback)
                (let ((before starts))
                  (funcall callback)
                  (should (= starts (1+ before))))
                (rbx-mode -1)
                (should (eq stopped 'watcher))))
          (kill-buffer buffer))))))

(ert-deftest rbx-mode-shows-statement-hints-for-a-declared-statement ()
  (rbx-test-with-directory root
    (let ((source (rbx-test-write root "statement.tex" "\\VAR{n}\n")))
      (rbx-test-write root "problem.rbx.yml" "ignored\n")
      (rbx-reset-artifact-cache)
      (let ((buffer (find-file-noselect source)))
        (unwind-protect
            (cl-letf (((symbol-function 'rbx-read-yaml)
                       (lambda (_path)
                         '(("statements" . ((("file" . "statement.tex")))))))
                      ((symbol-function 'rbx-statement-load-vars)
                       (lambda (_package callback)
                         (funcall callback
                                  (rbx-statement-vars-payload-create
                                   :vars '(("n" . "5")) :groups nil))))
                      ((symbol-function 'rbx-watch-package)
                       (lambda (&rest _args) 'watcher))
                      ((symbol-function 'rbx-stop-watcher) #'ignore))
              (with-current-buffer buffer
                (rbx-mode 1)
                (should (= (length rbx--statement-hint-overlays) 1))
                (should (equal (overlay-get (car rbx--statement-hint-overlays)
                                            'after-string)
                              (propertize " → 5" 'face 'rbx-statement-hint)))
                (rbx-mode -1)
                (should-not rbx--statement-hint-overlays)))
          (kill-buffer buffer))))))

(ert-deftest rbx-mode-skips-statement-hints-outside-a-declared-statement ()
  (rbx-test-with-directory root
    (let ((source (rbx-test-write root "notes.tex" "\\VAR{n}\n")))
      (rbx-test-write root "problem.rbx.yml" "ignored\n")
      (rbx-reset-artifact-cache)
      (let ((buffer (find-file-noselect source)))
        (unwind-protect
            (cl-letf (((symbol-function 'rbx-read-yaml)
                       (lambda (_path)
                         '(("statements" . ((("file" . "statement.tex")))))))
                      ((symbol-function 'rbx-watch-package)
                       (lambda (&rest _args) 'watcher))
                      ((symbol-function 'rbx-stop-watcher) #'ignore))
              (with-current-buffer buffer
                (rbx-mode 1)
                (should-not rbx--statement-hint-overlays)
                (rbx-mode -1)))
          (kill-buffer buffer))))))

(ert-deftest rbx-mode-respects-rbx-statement-var-hints-toggle ()
  (rbx-test-with-directory root
    (let ((source (rbx-test-write root "statement.tex" "\\VAR{n}\n"))
          (rbx-statement-var-hints nil))
      (rbx-test-write root "problem.rbx.yml" "ignored\n")
      (rbx-reset-artifact-cache)
      (let ((buffer (find-file-noselect source)))
        (unwind-protect
            (cl-letf (((symbol-function 'rbx-read-yaml)
                       (lambda (_path)
                         '(("statements" . ((("file" . "statement.tex")))))))
                      ((symbol-function 'rbx-watch-package)
                       (lambda (&rest _args) 'watcher))
                      ((symbol-function 'rbx-stop-watcher) #'ignore))
              (with-current-buffer buffer
                (rbx-mode 1)
                (should-not rbx--statement-hint-overlays)
                (rbx-mode -1)))
          (kill-buffer buffer))))))

(ert-deftest rbx-mode-refreshes-statement-hints-after-artifact-changes ()
  (rbx-test-with-directory root
    (let ((source (rbx-test-write root "statement.tex" "\\VAR{n}\n"))
          callback invalidated (value "5"))
      (rbx-test-write root "problem.rbx.yml" "ignored\n")
      (rbx-reset-artifact-cache)
      (let ((buffer (find-file-noselect source)))
        (unwind-protect
            (cl-letf (((symbol-function 'rbx-read-yaml)
                       (lambda (_path)
                         '(("statements" . ((("file" . "statement.tex")))))))
                      ((symbol-function 'rbx-statement-load-vars)
                       (lambda (_package callback)
                         (funcall callback
                                  (rbx-statement-vars-payload-create
                                   :vars (list (cons "n" value)) :groups nil))))
                      ((symbol-function 'rbx-statement-invalidate)
                       (lambda (_package) (setq invalidated t)))
                      ((symbol-function 'rbx-watch-package)
                       (lambda (_package function)
                         (setq callback function)
                         'watcher))
                      ((symbol-function 'rbx-stop-watcher) #'ignore))
              (with-current-buffer buffer
                (rbx-mode 1)
                (should (equal (overlay-get (car rbx--statement-hint-overlays)
                                            'after-string)
                              (propertize " → 5" 'face 'rbx-statement-hint)))
                (setq value "6")
                (funcall callback)
                (should invalidated)
                (should (equal (overlay-get (car rbx--statement-hint-overlays)
                                            'after-string)
                              (propertize " → 6" 'face 'rbx-statement-hint)))
                (rbx-mode -1)))
          (kill-buffer buffer))))))

(provide 'rbx-test)
;;; rbx-test.el ends here
