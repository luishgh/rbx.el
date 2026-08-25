;;; rbx-ui-test.el --- Tests for rbx-ui -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for native rendering and display formatting.

;;; Code:

(require 'rbx-ui)
(require 'test-helper)

(ert-deftest rbx-format-outcomes-and-measurements-match-rbx ()
  (should (equal (rbx-outcome-short-name "wrong-answer") "WA"))
  (should (equal (rbx-outcome-short-name "future-verdict") "XX"))
  (should (equal (rbx-outcome-short-name nil) "?"))
  (should (equal (rbx-format-time 0.1299) "129 ms"))
  (should (equal (rbx-format-memory 1024) "1 KiB"))
  (should (equal (rbx-format-memory 1048576) "1 MiB")))

(ert-deftest rbx-verdict-palette-matches-vscode-hues ()
  (should (eq (rbx--outcome-face "accepted") 'rbx-outcome-accepted))
  (should (eq (rbx--outcome-face "wrong-answer") 'rbx-outcome-wrong))
  (should (eq (rbx--outcome-face "time-limit-exceeded")
              'rbx-outcome-limit))
  (should (eq (rbx--outcome-face "runtime-error") 'rbx-outcome-error))
  (should (eq (rbx--outcome-face "output-limit-exceeded")
              'rbx-outcome-output-limit))
  (should (eq (rbx--outcome-face "judge-failed")
              'rbx-outcome-internal))
  (should (eq (rbx--outcome-face "skipped") 'rbx-outcome-dim))
  (should (eq (rbx--outcome-face nil) 'rbx-outcome-dim)))

(ert-deftest rbx-expectation-palette-uses-vscode-labels ()
  (should (equal (rbx--expectation-label "ACCEPTED") "AC"))
  (should (equal (rbx--expectation-label "ACCEPTED_OR_TLE") "AC or TLE"))
  (should (equal (rbx--expectation-label "WRONG_ANSWER") "WA"))
  (should (equal (rbx--expectation-label "TLE_OR_RTE") "TLE or RTE"))
  (should (equal (rbx--expectation-label "future-outcome")
                 "future-outcome"))
  (should (eq (rbx--expected-face "OUTPUT_LIMIT_EXCEEDED")
              'rbx-expected-other))
  (should (eq (rbx--expected-face "future-outcome")
              'rbx-expected-neutral)))

(ert-deftest rbx-status-washes-rank-misses-above-warnings ()
  (should (eq (rbx--row-state nil t) 'missed))
  (should (eq (rbx--row-state t t) 'warned))
  (should (eq (rbx--row-state t nil) 'met)))

(ert-deftest rbx-palette-has-clean-slate-foregrounds ()
  (dolist (face '(rbx-hue-green rbx-hue-red rbx-hue-yellow rbx-hue-blue
                  rbx-hue-purple rbx-hue-orange rbx-hue-dim))
    (let ((foreground (face-attribute face :foreground nil t)))
      (should (stringp foreground))
      (should-not (equal foreground "unspecified-fg")))))

(ert-deftest rbx-render-run-keeps-declared-actual-and-match-channels-separate ()
  (rbx-test-with-directory root
    (rbx-test-write root "problem.rbx.yml" "name: Demo\n")
    (rbx-test-write
     root ".rbx/runs/skeleton.yml"
     (concat
      "solutions:\n  - path: sols/wa.cpp\n    outcome: WRONG_ANSWER\n"
      "groups:\n  - name: main\n    score: 100\n"
      "entries:\n  - group_entry: {group: main, index: 0}\n"))
    (rbx-test-write
     root ".rbx/runs/report.yml"
     (concat
      "version: 1\nsolutions:\n  - path: sols/wa.cpp\n    index: 0\n"
      "    expectedOutcome: WRONG_ANSWER\n    outcome: accepted\n"
      "    status: UNEXPECTED_VERDICTS\n    matchesExpectation: false\n"
      "    score: 100\n    maxScore: 100\n    failedGroups: [main]\n"
      "    groups:\n      - name: main\n        outcome: accepted\n"
      "        expectedOutcome: WRONG_ANSWER\n"
      "        matchesExpectation: false\n        score: 100\n"
      "        maxScore: 100\n"))
    (rbx-test-write
     root ".rbx/runs/0/main/000.eval"
     "result: {outcome: accepted, message: surprising}\nlog: {time: 0.01, memory: 2048}\n")
    (let ((package (rbx-package-create
                    :root (file-name-as-directory root)
                    :build-dir "build")))
      (with-temp-buffer
        (rbx-view-mode)
        (setq-local rbx--package package)
        (setq-local rbx--view 'run)
        (rbx-refresh)
        (let ((text (buffer-substring-no-properties (point-min) (point-max))))
          (should (string-match-p "✗.*wa\\.cpp.*declared WA.*got AC"
                                  text))
          (should (string-match-p "UNEXPECTED_VERDICTS" text))
          (should (string-match-p "000.*AC.*10 ms.*2 KiB" text)))
        (font-lock-ensure)
        (goto-char (point-min))
        (re-search-forward "^✗")
        (let ((position (match-beginning 0)))
          (should (memq 'rbx-mismatch
                        (ensure-list (get-text-property
                                      position 'font-lock-face))))
          (should (memq 'rbx-row-mismatch
                        (ensure-list (get-text-property
                                      position 'font-lock-face))))
          (should-not (get-text-property position 'face)))
        (re-search-forward "declared \\(WA\\)")
        (let ((position (match-beginning 1)))
          (should (memq 'rbx-expected-incorrect
                        (ensure-list (get-text-property
                                      position 'font-lock-face))))
          (should (memq 'rbx-row-mismatch
                        (ensure-list (get-text-property
                                      position 'font-lock-face)))))
        (re-search-forward "got \\(AC\\)")
        (let ((position (match-beginning 1)))
          (should (memq 'rbx-outcome-accepted
                        (ensure-list (get-text-property
                                      position 'font-lock-face))))
          (should (memq 'rbx-row-mismatch
                        (ensure-list (get-text-property
                                      position 'font-lock-face)))))))))

(ert-deftest rbx-render-testset-shows-provenance-and-validation ()
  (rbx-test-with-directory root
    (rbx-test-write root "problem.rbx.yml" "name: Demo\n")
    (rbx-test-write
     root "build/testset.yml"
     (concat
      "version: 1\ntask_type: BATCH\ngroups:\n  - name: main\n"
      "entries:\n  - group_entry: {group: main, index: 0}\n"
      "    metadata:\n      copied_to: {inputPath: build/tests/main/000.in}\n"
      "      generator_call: {name: gen, args: '5 3'}\n"
      "tests:\n  - group: main\n    index: 0\n"
      "    validation: {ok: true, validator: validator.cpp}\n"
      "    input_size: 10\n    output_size: 2\n"))
    (let ((package (rbx-package-create
                    :root (file-name-as-directory root)
                    :build-dir "build")))
      (with-temp-buffer
        (rbx-view-mode)
        (setq-local rbx--package package)
        (setq-local rbx--view 'testset)
        (rbx-refresh)
        (let ((text (buffer-substring-no-properties (point-min) (point-max))))
          (should (string-match-p "main.*1 testcase" text))
          (should (string-match-p "000.*gen 5 3.*validated by validator\\.cpp"
                                  text)))))))

(provide 'rbx-ui-test)
;;; rbx-ui-test.el ends here
