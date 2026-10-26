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

(defun rbx-test--statement-diagnostics (root file)
  "Return the statement Flymake diagnostics of FILE under ROOT."
  (let ((buffer (find-file-noselect (expand-file-name file root)))
        diagnostics)
    (unwind-protect
        (with-current-buffer buffer
          (rbx-statement-flymake-backend
           (lambda (items) (setq diagnostics items)))
          diagnostics)
      (kill-buffer buffer))))

(defun rbx-test--write-statement-package (root findings)
  "Write a package under ROOT whose statement build report has FINDINGS."
  (rbx-test-write root "problem.rbx.yml"
                  (concat "name: Demo\nstatements:\n"
                          "  - language: en\n    file: statement/statement.rbx.tex\n"
                          "    type: rbxTeX\n"))
  (rbx-test-write root "statement/statement.rbx.tex"
                  (concat (mapconcat #'number-to-string (number-sequence 1 15) "\n")
                          "\n"))
  (rbx-test-write root "statement/samples/01.rbx.tex" "a\nb\nc\n")
  (rbx-test-write
   root ".rbx/statements/report.yml"
   (concat "version: 1\noutputs:\n"
           "  - kind: statement\n    language: en\n    format: pdf\n"
           "    path: build/statement-en.pdf\n    status: failed\n"
           "    findings:\n" findings)))

(ert-deftest rbx-statement-flymake-locates-errors-in-the-named-file ()
  (rbx-test-with-directory root
    (rbx-test--write-statement-package
     root (concat "      - origin: latex\n        severity: error\n"
                  "        message: Undefined control sequence.\n"
                  "        context: \\foo\n"
                  "        file: statement/statement.rbx.tex\n        line: 12\n"
                  "      - origin: latex\n        severity: warning\n"
                  "        message: Overfull hbox.\n"
                  "        file: statement/samples/01.rbx.tex\n        line: 2\n"))
    (let ((main (rbx-test--statement-diagnostics
                 root "statement/statement.rbx.tex"))
          (sample (rbx-test--statement-diagnostics
                   root "statement/samples/01.rbx.tex")))
      (should (= (length main) 1))
      (should (eq (flymake-diagnostic-type (car main)) :error))
      (should (string-match-p "Undefined control sequence\\.\n\\\\foo"
                              (flymake-diagnostic-text (car main))))
      (should (= (length sample) 1))
      (should (eq (flymake-diagnostic-type (car sample)) :warning))
      (should (string-match-p "Overfull"
                              (flymake-diagnostic-text (car sample)))))))

(ert-deftest rbx-statement-flymake-places-unlocated-errors-on-the-source ()
  (rbx-test-with-directory root
    (rbx-test--write-statement-package
     root "      - origin: build\n        severity: error\n        message: pdflatex failed.\n")
    (let ((main (rbx-test--statement-diagnostics
                 root "statement/statement.rbx.tex")))
      (should (= (length main) 1))
      (should (= (flymake-diagnostic-beg (car main)) 1))
      (should-not (rbx-test--statement-diagnostics
                   root "statement/samples/01.rbx.tex")))))

(ert-deftest rbx-statement-flymake-merges-repeats-across-outputs ()
  (rbx-test-with-directory root
    (let ((finding (concat "      - origin: latex\n        severity: error\n"
                           "        message: Boom.\n"
                           "        file: statement/statement.rbx.tex\n"
                           "        line: 3\n")))
      (rbx-test--write-statement-package root finding)
      (with-temp-buffer
        (insert-file-contents (expand-file-name ".rbx/statements/report.yml" root))
        (goto-char (point-max))
        (insert "  - kind: statement\n    language: en\n    format: tex\n"
                "    path: build/statement-en.tex\n    status: failed\n"
                "    findings:\n" finding)
        (write-region nil nil (expand-file-name ".rbx/statements/report.yml" root)))
      (rbx-reset-artifact-cache)
      (should (= (length (rbx-test--statement-diagnostics
                          root "statement/statement.rbx.tex"))
                 1)))))

(ert-deftest rbx-statement-flymake-ignores-a-missing-report ()
  (rbx-test-with-directory root
    (rbx-test-write root "problem.rbx.yml" "name: Demo\n")
    (rbx-test-write root "statement/statement.rbx.tex" "x\n")
    (should-not (rbx-test--statement-diagnostics
                 root "statement/statement.rbx.tex"))))

(ert-deftest rbx-mode-installs-the-statement-backend-in-tex-buffers-only ()
  (rbx-test-with-directory root
    (rbx-test-write root "problem.rbx.yml" "name: Demo\n")
    (let ((tex (find-file-noselect
                (rbx-test-write root "statement/statement.rbx.tex" "x\n")))
          (cpp (find-file-noselect (rbx-test-write root "sols/a.cpp" "x\n"))))
      (unwind-protect
          (cl-letf (((symbol-function 'flymake-mode) #'ignore)
                    ((symbol-function 'flymake-start) #'ignore)
                    ((symbol-function 'rbx-watch-package) #'ignore))
            (with-current-buffer tex
              (rbx-mode 1)
              (should (memq #'rbx-statement-flymake-backend
                            flymake-diagnostic-functions))
              (rbx-mode -1)
              (should-not (memq #'rbx-statement-flymake-backend
                                flymake-diagnostic-functions))
              (let ((rbx-statement-diagnostics nil))
                (rbx-mode 1)
                (should-not (memq #'rbx-statement-flymake-backend
                                  flymake-diagnostic-functions))
                (rbx-mode -1)))
            (with-current-buffer cpp
              (rbx-mode 1)
              (should-not (memq #'rbx-statement-flymake-backend
                                flymake-diagnostic-functions))
              (rbx-mode -1)))
        (kill-buffer tex)
        (kill-buffer cpp)))))

(ert-deftest rbx-mode-refuses-to-enable-from-a-hook-without-yq ()
  (rbx-test-with-directory root
    (let ((source (rbx-test-write root "sols/main.cpp" "int main() {}\n"))
          (warnings nil)
          (watched nil))
      (rbx-test-write root "problem.rbx.yml" "name: Demo\n")
      (rbx-reset-executables)
      (let ((buffer (find-file-noselect source)))
        (unwind-protect
            (cl-letf (((symbol-function 'rbx-resolve-executable)
                       (lambda (&rest _args) nil))
                      ((symbol-function 'rbx-watch-package)
                       (lambda (&rest _args) (setq watched t) 'watcher))
                      ((symbol-function 'display-warning)
                       (lambda (_type message &rest _args)
                         (push message warnings))))
              (with-current-buffer buffer
                (rbx-mode 1)
                (rbx-mode 1)
                (should-not rbx-mode)
                (should-not watched)
                (should-not (memq #'rbx-flymake-backend
                                  flymake-diagnostic-functions))
                (should (= (length warnings) 1))
                (should (string-match-p "mikefarah/yq" (car warnings)))))
          (rbx-reset-executables)
          (kill-buffer buffer))))))

(ert-deftest rbx-mode-signals-when-enabled-interactively-without-yq ()
  (rbx-test-with-directory root
    (let ((source (rbx-test-write root "sols/main.cpp" "int main() {}\n")))
      (rbx-test-write root "problem.rbx.yml" "name: Demo\n")
      (let ((buffer (find-file-noselect source)))
        (unwind-protect
            (cl-letf (((symbol-function 'rbx-resolve-executable)
                       (lambda (&rest _args) nil)))
              (with-current-buffer buffer
                (should-error (call-interactively #'rbx-mode)
                              :type 'user-error)
                (should-not rbx-mode)))
          (kill-buffer buffer))))))

(ert-deftest rbx-mode-does-not-check-yq-outside-a-package ()
  (rbx-test-with-directory root
    (let ((checked nil))
      (cl-letf (((symbol-function 'rbx-resolve-executable)
                 (lambda (&rest _args) (setq checked t) nil)))
        (with-temp-buffer
          (setq default-directory (file-name-as-directory root))
          (rbx-mode 1)
          (should rbx-mode)
          (should-not checked)
          (rbx-mode -1))))))

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

(ert-deftest rbx-view-package-helper-selects-outside-a-statement-buffer ()
  (rbx-test-with-directory root
    (rbx-test-write root "problem.rbx.yml" "name: Demo\n")
    (with-temp-buffer
      (let ((default-directory (file-name-as-directory root))
            (rbx-statement-var-hints t))
        (should-not (rbx--statement-package))
        (should (rbx-package-p (rbx--view-or-selected-package)))))))

(provide 'rbx-test)
;;; rbx-test.el ends here
