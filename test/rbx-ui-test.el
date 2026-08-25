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
          (should (string-match-p "✗.*wa\\.cpp.*declared WRONG_ANSWER.*got AC"
                                  text))
          (should (string-match-p "UNEXPECTED_VERDICTS" text))
          (should (string-match-p "000.*AC.*10 ms.*2 KiB" text)))))))

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
