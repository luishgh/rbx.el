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

(provide 'rbx-test)
;;; rbx-test.el ends here
