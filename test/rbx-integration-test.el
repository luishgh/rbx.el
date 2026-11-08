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

(require 'rbx)
(require 'rbx-core)
(require 'rbx-model)
(require 'rbx-statement)
(require 'rbx-ui)
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

(defun rbx-integration-test--replace-in-file (file from to)
  "Replace the first literal FROM with TO in FILE, or signal an error."
  (with-temp-file file
    (insert-file-contents file)
    (goto-char (point-min))
    (unless (search-forward from nil t)
      (error "%S not found in %s" from file))
    (replace-match to t t)))

(defun rbx-integration-test--make-partially-scored (demo)
  "Turn the package at DEMO into one scored by points, with a partial solution.

The default preset scores in binary, so it never produces fractional scores
or a `partially-correct' verdict."
  (write-region "#include \"testlib.h\"
int main(int argc, char *argv[]) {
  registerTestlibCmd(argc, argv);
  long long a = ans.readLong(), o = ouf.readLong();
  if (a == o) quitf(_ok, \"ok\");
  quitp(37.037, \"partial answer\");
}
" nil (expand-file-name "partial-checker.cpp" demo))
  (write-region "#include <iostream>
int main() {
  long long a, b;
  std::cin >> a >> b;
  std::cout << a + b + 1 << std::endl;
}
" nil (expand-file-name "sols/partial.cpp" demo))
  (let ((manifest (expand-file-name "problem.rbx.yml" demo)))
    (rbx-integration-test--replace-in-file
     manifest "checker: {path: wcmp.cpp}"
     "scoring: points\nchecker: {path: partial-checker.cpp}")
    (rbx-integration-test--replace-in-file
     manifest "- name: samples\n"
     "- name: samples\n  score: 100\n  aggregation: sum\n")
    (rbx-integration-test--replace-in-file
     manifest "\nstatements:\n"
     "\n- path: sols/partial.cpp\n  outcome: partially correct\nstatements:\n")))

(ert-deftest rbx-integration-partial-scoring-renders-like-rbx ()
  (skip-unless (file-executable-p rbx-integration-test--program))
  (rbx-integration-test-with-package demo
    (rbx-integration-test--make-partially-scored demo)
    (rbx-integration-test--run demo "run")
    (let* ((package (rbx-find-package demo))
           (solutions (rbx-run-report-solutions (rbx-load-report package)))
           (main (seq-find (lambda (solution)
                             (equal (rbx-solution-report-path solution)
                                    "sols/main.cpp"))
                           solutions))
           (partial (seq-find (lambda (solution)
                                (equal (rbx-solution-report-path solution)
                                       "sols/partial.cpp"))
                              solutions)))
      (should (equal (rbx--score (rbx-solution-report-score main)
                                 (rbx-solution-report-max-score main))
                     "[100/100]"))
      (should (equal (rbx--score (rbx-solution-report-score partial)
                                 (rbx-solution-report-max-score partial))
                     "[37.04/100]"))
      (should (equal (rbx-outcome-short-name
                      (rbx-solution-report-outcome partial))
                     "PC"))
      (should (rbx-solution-report-matches-expectation partial))
      (let ((percents
             (delq nil
                   (mapcar
                    (lambda (entry)
                      (when-let* ((evaluation
                                   (rbx-load-evaluation
                                    package (rbx-solution-report-index partial)
                                    entry))
                                  (percent (rbx--evaluation-percent
                                            evaluation)))
                        (substring-no-properties percent)))
                    (rbx-skeleton-entries (rbx-load-skeleton package))))))
        (should percents)
        (should (cl-every (lambda (text) (string-suffix-p "%" text))
                          percents)))
      (should (equal (rbx--expectation-label
                      (rbx-solution-expected-outcome
                       (seq-find (lambda (solution)
                                   (equal (rbx-solution-path solution)
                                          "sols/partial.cpp"))
                                 (rbx-skeleton-solutions
                                  (rbx-load-skeleton package)))))
                     "PC")))))

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

(defun rbx-integration-test--run-allowing-failure (directory &rest args)
  "Run the real rbx with ARGS in DIRECTORY, ignoring a non-zero exit.
Statement and stress failures are findings rbx publishes, not errors."
  (condition-case nil
      (apply #'rbx-integration-test--run directory args)
    (error nil)))

(ert-deftest rbx-integration-limits-and-tutorials-round-trip ()
  (skip-unless (file-executable-p rbx-integration-test--program))
  (rbx-integration-test-with-package demo
    (rbx-integration-test--run demo "run")
    (let* ((package (rbx-find-package demo))
           (skeleton (rbx-load-skeleton package))
           (solution (car (rbx-skeleton-solutions skeleton)))
           (report (car (rbx-run-report-solutions (rbx-load-report package))))
           (statements (rbx-load-problem-statements package)))
      (should (rbx-skeleton-limits skeleton))
      (should (rbx-limits-time (rbx-solution-limits solution)))
      (should (numberp (rbx-solution-report-time-limit report)))
      ;; The default preset declares `{lang}' templates; they must match.
      (should (rbx-package-statement-p
               package (expand-file-name "statement/statement-en.rbx.tex"
                                         demo)))
      ;; The scaffold declares both a statement and an editorial.
      (should (seq-some (lambda (statement)
                          (string-match-p "editorial"
                                          (rbx-problem-statement-file statement)))
                        statements)))))

(ert-deftest rbx-integration-a-normal-run-reads-as-finished-and-validated ()
  (skip-unless (file-executable-p rbx-integration-test--program))
  (rbx-integration-test-with-package demo
    (rbx-integration-test--run demo "run")
    (let* ((package (rbx-find-package demo))
           (report (rbx-load-report package))
           (skeleton (rbx-load-skeleton package)))
      ;; A rename of the end marker would silently turn this into "in flight".
      (should (rbx-run-report-finished report))
      (should (equal (rbx-run-report-exit-status report) "ok"))
      (should (equal (rbx-skeleton-validation-mode skeleton) "fail"))
      (should-not (rbx-skeleton-invalid skeleton)))))

(ert-deftest rbx-integration-on-invalid-warn-lists-the-rejected-testcase ()
  (skip-unless (file-executable-p rbx-integration-test--program))
  (rbx-integration-test-with-package demo
    ;; The default validator requires both numbers in [N.min, N.max].
    (rbx-test-write demo "statement/samples/099.in" "0 5\n")
    (rbx-integration-test--run demo "run" "--on-invalid=warn")
    (let* ((package (rbx-find-package demo))
           (skeleton (rbx-load-skeleton package))
           (invalid (rbx-skeleton-invalid skeleton)))
      (should (equal (rbx-skeleton-validation-mode skeleton) "warn"))
      (should (= (length invalid) 1))
      (should (equal (rbx-invalid-test-group (car invalid)) "samples"))
      (should (integerp (rbx-invalid-test-index (car invalid))))
      (should (stringp (rbx-invalid-test-validator (car invalid))))
      ;; The run still completed, and the view flags the row.
      (should (rbx-run-report-finished (rbx-load-report package)))
      (with-temp-buffer
        (rbx-view-mode)
        (setq-local rbx--package package)
        (setq-local rbx--view 'run)
        (rbx-refresh)
        (rbx-expand-all)
        (should (string-match-p "1 invalid testcase" (buffer-string)))
        (should (string-match-p "⚠ invalid" (buffer-string)))))))

(ert-deftest rbx-integration-declared-outcome-matches-the-skeleton ()
  (skip-unless (file-executable-p rbx-integration-test--program))
  (rbx-integration-test-with-package demo
    (rbx-integration-test--run demo "run")
    (rbx-reset-artifact-cache)
    (let* ((package (rbx-find-package demo))
           (skeleton (rbx-load-skeleton package)))
      (should (rbx-skeleton-solutions skeleton))
      ;; The manifest reader and rbx's own resolution must agree on every
      ;; solution, otherwise the alias table has drifted.
      (dolist (solution (rbx-skeleton-solutions skeleton))
        (should (equal (rbx-declared-outcome
                        package (rbx-package-file-path
                                 package (rbx-solution-path solution)))
                       (rbx-solution-expected-outcome solution)))))))

(ert-deftest rbx-integration-adhoc-run-round-trip ()
  (skip-unless (file-executable-p rbx-integration-test--program))
  (rbx-integration-test-with-package demo
    (rbx-test-write demo "in.txt" "1 2\n")
    (rbx-integration-test--run demo "irun" "-i" "in.txt" "sols/main.cpp")
    (rbx-reset-artifact-cache)
    (let* ((package (rbx-adhoc-package (rbx-find-package demo)))
           (skeleton (rbx-load-skeleton package))
           (entry (car (rbx-skeleton-entries skeleton)))
           (stem (rbx-testcase-stem entry))
           (report (car (rbx-run-report-solutions (rbx-load-report package)))))
      (should (equal (rbx-solution-report-path report) "sols/main.cpp"))
      (should (file-readable-p (rbx-adhoc-input-path package stem ".in")))
      (should (file-readable-p (rbx-adhoc-input-path package stem ".out")))
      (dolist (extension '(".out" ".err" ".eval"))
        (should (file-readable-p
                 (rbx-run-artifact-path package 0 (rbx-testcase-group entry)
                                        stem extension))))
      (should (rbx-load-evaluation package 0 entry))
      (with-temp-buffer
        (rbx-view-mode)
        (let ((inhibit-read-only t))
          (rbx--insert-run-view package))
        (should (string-match-p "Ad-hoc run" (buffer-string)))
        (should (string-match-p "main\\.cpp" (buffer-string)))))))

(ert-deftest rbx-integration-stress-session-round-trip ()
  (skip-unless (file-executable-p rbx-integration-test--program))
  (rbx-integration-test-with-package demo
    (rbx-test-write
     demo "sols/wa-bad.cpp"
     (concat "#include <bits/stdc++.h>\n"
             "int main() { long long a, b; std::cin >> a >> b;\n"
             "  std::cout << a + b + (a % 3 == 0) << std::endl; }\n"))
    (rbx-integration-test--run-allowing-failure
     demo "stress" "-g" "tests/gen.cpp 10 @"
     "-f" "[sols/wa-bad.cpp] ~ INCORRECT" "-t" "30" "-n" "2")
    (rbx-reset-artifact-cache)
    (let* ((package (rbx-find-package demo))
           (stress (rbx-load-stress package)))
      (should stress)
      (should (equal (rbx-stress-state stress) "done"))
      (should (equal (rbx-stress-solutions stress)
                     '("sols/main.cpp" "sols/wa-bad.cpp")))
      (should (>= (length (rbx-stress-findings stress)) 1))
      (dolist (finding (rbx-stress-findings stress))
        (let ((index (rbx-stress-finding-index finding))
              (result (car (rbx-stress-finding-results finding))))
          (should (string-match-p "gen" (rbx-stress-finding-generator finding)))
          (should (equal (rbx-stress-result-outcome result) "wrong-answer"))
          (dolist (file (list "input.in" "input.ans"
                              (format "%d.out" (rbx-stress-result-solution result))
                              (format "%d.err" (rbx-stress-result-solution result))))
            (should (file-readable-p
                     (rbx-stress-finding-path package index file))))))
      (with-temp-buffer
        (rbx-view-mode)
        (let ((inhibit-read-only t))
          (rbx--insert-stress-view package))
        (should (string-match-p "wa-bad\\.cpp" (buffer-string)))
        (should (string-match-p "WA" (buffer-string)))))))

(ert-deftest rbx-integration-time-profile-round-trip ()
  (skip-unless (file-executable-p rbx-integration-test--program))
  (rbx-integration-test-with-package demo
    ;; Not needed by the estimate, so `--run-all' judges it at the limit.
    (rbx-test-write
     demo "sols/wa-off.cpp"
     (concat "#include <bits/stdc++.h>\n"
             "int main() { long long a, b; std::cin >> a >> b;\n"
             "  std::cout << a + b + 1 << std::endl; }\n"))
    (rbx-integration-test--run demo "time" "--auto" "--run-all")
    (rbx-reset-artifact-cache)
    (let* ((package (rbx-find-package demo))
           (profile (rbx-load-time-profile package "local")))
      (should (member "local" (rbx-time-profile-names package)))
      (should profile)
      (should (equal (rbx-time-profile-runner profile) "local"))
      (should (rbx-time-profile-multipliers profile))
      (should (rbx-time-profile-groups profile))
      (should (rbx-time-profile-base-estimate profile))
      (let ((main (cl-find "sols/main.cpp" (rbx-time-profile-solutions profile)
                           :key #'rbx-timing-solution-path :test #'equal))
            (run (car (rbx-time-profile-runs profile))))
        (should (eq (rbx-timing-solution-role main) 'lower))
        (should (numberp (rbx-timing-solution-time main)))
        (should (equal (rbx-profile-run-path run) "sols/wa-off.cpp"))
        (should (equal (rbx-profile-run-expected-outcome run) "WRONG_ANSWER"))
        (should (equal (rbx-profile-run-outcome run) "wrong-answer"))
        (should (eq (rbx-profile-run-matches-expectation run) t))
        (should (rbx-profile-run-complete run))
        ;; The run is filed under the group of its language.
        (should (cl-some (lambda (row)
                           (and (rbx-time-profile-row-group row)
                                (member "cpp" (rbx-timing-group-languages
                                               (rbx-time-profile-row-group row)))
                                (memq run (rbx-time-profile-row-runs row))))
                         (cdr (rbx-time-profile-rows profile)))))
      (with-temp-buffer
        (rbx-view-mode)
        (let ((inhibit-read-only t))
          (rbx--insert-time-profile-view package "local"))
        (should (string-match-p "sols/main\\.cpp +accepted" (buffer-string)))
        (should (string-match-p "✓ sols/wa-off\\.cpp  declared WA → got WA"
                                (buffer-string)))))))

(ert-deftest rbx-integration-statement-report-round-trip ()
  (skip-unless (file-executable-p rbx-integration-test--program))
  (skip-unless (executable-find "pdflatex"))
  (rbx-integration-test-with-package demo
    (rbx-integration-test--run demo "statements" "build")
    (rbx-reset-artifact-cache)
    (let* ((package (rbx-find-package demo))
           (output (car (rbx-statement-report-outputs
                         (rbx-load-statement-report package)))))
      (should output)
      (should (equal (rbx-statement-output-status output) "ok"))
      (should (equal (rbx-statement-output-format output) "pdf"))
      (should (rbx--statement-output-file package output)))
    ;; Break the statement: the failure is published and located.
    (let ((file (expand-file-name "statement/statement-en.rbx.tex" demo)))
      (with-temp-file file
        (insert-file-contents file)
        (goto-char (point-min))
        (forward-line 1)
        (end-of-line)
        (insert " \\undefinedmacro{x}")))
    (rbx-integration-test--run-allowing-failure demo "statements" "build")
    (rbx-reset-artifact-cache)
    (let* ((package (rbx-find-package demo))
           (output (car (rbx-statement-report-outputs
                         (rbx-load-statement-report package))))
           (finding (car (rbx-statement-output-findings output))))
      (should (equal (rbx-statement-output-status output) "failed"))
      (should finding)
      (should (equal (rbx-statement-finding-file finding)
                     "statement/statement-en.rbx.tex"))
      (should (= (rbx-statement-finding-line finding) 2))
      (let ((buffer (find-file-noselect
                     (expand-file-name "statement/statement-en.rbx.tex" demo)))
            diagnostics)
        (unwind-protect
            (with-current-buffer buffer
              (rbx-statement-flymake-backend
               (lambda (items) (setq diagnostics items)))
              (should (= (length diagnostics) 1))
              (should (eq (flymake-diagnostic-type (car diagnostics)) :error))
              (should (= (line-number-at-pos
                          (flymake-diagnostic-beg (car diagnostics)))
                         2))
              (should (string-match-p
                       "Undefined"
                       (flymake-diagnostic-text (car diagnostics)))))
          (kill-buffer buffer))))))

(provide 'rbx-integration-test)
;;; rbx-integration-test.el ends here
