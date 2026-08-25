;;; rbx-model-test.el --- Tests for rbx-model -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the tolerant readers of rbx artifact models.

;;; Code:

(require 'rbx-model)
(require 'test-helper)

(defconst rbx-test--entry
  '(("group_entry" . (("group" . "main") ("index" . 3)))
    ("subgroup_entry" . (("group" . "small")))
    ("metadata" .
     (("copied_to" .
       (("inputPath" . "build/tests/main/1-gen-000.in")
        ("outputPath" . "build/tests/main/1-gen-000.out")))
      ("generator_call" . (("name" . "gen") ("args" . "5 3")))
      ("generator_script" . (("path" . "gen/main.rbx") ("line" . 12))))))
  "Representative GenerationTestcaseEntry wire value.")

(ert-deftest rbx-parse-testcase-entry-uses-generated-stem ()
  (let ((entry (rbx-parse-testcase-entry rbx-test--entry)))
    (should (equal (rbx-testcase-group entry) "main"))
    (should (= (rbx-testcase-index entry) 3))
    (should (equal (rbx-testcase-subgroup entry) "small"))
    (should (equal (rbx-testcase-stem entry) "1-gen-000"))
    (should (equal (rbx-testcase-generator-name entry) "gen"))
    (should (= (rbx-testcase-generator-script-line entry) 12))))

(ert-deftest rbx-testcase-stem-falls-back-to-padded-index ()
  (should (equal (rbx-testcase-stem
                  (rbx-testcase-create :group "main" :index 7))
                 "007")))

(ert-deftest rbx-parse-skeleton-keeps-distinct-expectations-and-findings ()
  (let* ((raw `(("solutions" .
                ((RUN . unused)
                 (("path" . "sols/main.cpp") ("outcome" . "ACCEPTED"))))
               ("entries" . (,rbx-test--entry))
               ("groups" . ((("name" . "main") ("score" . 100))))
               ("compilation" .
                ((("path" . "sols/wa.cpp")
                  ("outcome" . "WRONG_ANSWER")
                  ("status" . "WARNINGS")
                  ("log" . "compilation/1.log")
                  ("warnings" .
                   ((LATER . ignored)
                    (("file" . "sols/wa.cpp") ("line" . 22)
                     ("flag" . "-Wshadow") ("msg" . "shadows x")))))))
               ("sanitized" . t)
               ("only_accepted" . t)))
         (skeleton (rbx-parse-skeleton raw)))
    (should (= (length (rbx-skeleton-solutions skeleton)) 1))
    (let ((solution (car (rbx-skeleton-solutions skeleton))))
      (should (equal (rbx-solution-path solution) "sols/main.cpp"))
      (should (equal (rbx-solution-expected-outcome solution) "ACCEPTED"))
      (should (= (rbx-solution-index solution) 1)))
    (should (rbx-skeleton-sanitized skeleton))
    (should (rbx-skeleton-only-accepted skeleton))
    (let* ((finding (car (rbx-skeleton-compilation skeleton)))
           (warning (car (rbx-compilation-warnings finding))))
      (should (equal (rbx-compilation-status finding) "WARNINGS"))
      (should (= (rbx-warning-line warning) 22))
      (should (equal (rbx-warning-flag warning) "-Wshadow")))))

(ert-deftest rbx-parse-evaluation-reads-facts-without-aggregating ()
  (let ((evaluation
         (rbx-parse-evaluation
          '(("result" .
             (("outcome" . "time-limit-exceeded")
              ("message" . "late but correct")
              ("no_tle_outcome" . "accepted")
              ("sanitizer_warnings" . t)))
            ("log" . (("time" . 1.25) ("memory" . 4096)))))))
    (should (equal (rbx-evaluation-outcome evaluation)
                   "time-limit-exceeded"))
    (should (= (rbx-evaluation-time evaluation) 1.25))
    (should (= (rbx-evaluation-memory evaluation) 4096))
    (should (rbx-evaluation-sanitizer-warnings evaluation))))

(ert-deftest rbx-load-evaluation-caches-unchanged-artifact ()
  (rbx-test-with-directory root
    (let* ((package (rbx-package-create
                     :root (file-name-as-directory root)
                     :build-dir "build"))
           (testcase (rbx-testcase-create :group "main" :index 0))
           (relative ".rbx/runs/0/main/000.eval")
           (reads 0)
           (reader (symbol-function 'rbx-read-yaml)))
      (rbx-test-write root relative
                      "result: {outcome: accepted}\nlog: {time: 0.01}\n")
      (rbx-reset-artifact-cache)
      (cl-letf (((symbol-function 'rbx-read-yaml)
                 (lambda (path)
                   (cl-incf reads)
                   (funcall reader path))))
        (should (equal (rbx-evaluation-outcome
                        (rbx-load-evaluation package 0 testcase))
                       "accepted"))
        (should (equal (rbx-evaluation-outcome
                        (rbx-load-evaluation package 0 testcase))
                       "accepted"))
        (should (= reads 1))
        (rbx-test-write root relative
                        "result: {outcome: wrong-answer}\nlog: {time: 0.02}\n")
        (should (equal (rbx-evaluation-outcome
                        (rbx-load-evaluation package 0 testcase))
                       "wrong-answer"))
        (should (= reads 2))))))

(ert-deftest rbx-parse-report-rejects-unknown-versions ()
  (should-not (rbx-parse-report '(("version" . 2) ("solutions" . nil)))))

(ert-deftest rbx-parse-report-preserves-upstream-match-decision ()
  (let* ((raw
          '(("version" . 1)
            ("solutions" .
             ((("path" . "sols/wa.cpp")
               ("index" . 1)
               ("expectedOutcome" . "WRONG_ANSWER")
               ("outcome" . "accepted")
               ("status" . "UNEXPECTED_VERDICTS")
               ("matchesExpectation" . nil)
               ("pooledMatchesExpectation" . nil)
               ("score" . 100)
               ("maxScore" . 100)
               ("maxTime" . 0.12)
               ("maxMemory" . 1048576)
               ("failedGroups" . ("main"))
               ("groups" .
                ((("name" . "main")
                  ("outcome" . "accepted")
                  ("expectedOutcome" . "WRONG_ANSWER")
                  ("matchesExpectation" . nil)
                  ("score" . 100)
                  ("maxScore" . 100)))))))))
         (report (rbx-parse-report raw))
         (solution (car (rbx-run-report-solutions report)))
         (group (car (rbx-solution-report-groups solution))))
    (should-not (rbx-solution-report-matches-expectation solution))
    (should (equal (rbx-solution-report-status solution)
                   "UNEXPECTED_VERDICTS"))
    (should-not (rbx-group-report-matches-expectation group))))

(ert-deftest rbx-parse-testset-joins-build-metadata-by-group-and-index ()
  (let* ((testset
          (rbx-parse-testset
           `(("version" . 1) ("task_type" . "BATCH")
             ("groups" .
              ((("name" . "main") ("score" . 100)
                ("deps" . ("samples"))
                ("vars" . (("n" . 100))))))
             ("entries" . (,rbx-test--entry))
             ("tests" .
              ((("group" . "main") ("index" . 3)
                ("validation" .
                 (("ok" . t) ("validator" . "validator.cpp")))
                ("visualization" .
                 (("input" . "build/visual/main.svg")))
                ("input_size" . 80) ("output_size" . 4))))
             ("validation" .
              ((("group" . "main") ("validator" . "validator.cpp")
                ("bounds" . (("n" . (t nil))))))))))
         (case (car (rbx-testset-testcases testset)))
         (extra (rbx-testset-testcase-test case))
         (bounds (car (rbx-testset-validation testset))))
    (should (equal (rbx-testset-task-type testset) "BATCH"))
    (should (= (rbx-testset-test-input-size extra) 80))
    (should (rbx-testset-validation-result-ok
             (rbx-testset-test-validation extra)))
    (should (equal (rbx-testset-visualization-input
                    (rbx-testset-test-visualization extra))
                   "build/visual/main.svg"))
    (should (equal (rbx-variable-bounds-min-hit
                    (cdr (assoc "n" (rbx-group-bounds-bounds bounds))))
                   t))
    (should-not (rbx-variable-bounds-max-hit
                 (cdr (assoc "n" (rbx-group-bounds-bounds bounds)))))))

(provide 'rbx-model-test)
;;; rbx-model-test.el ends here
