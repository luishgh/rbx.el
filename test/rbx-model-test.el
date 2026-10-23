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

(ert-deftest rbx-parse-limits-reads-camel-case-fields ()
  (let ((limits (rbx--parse-limits
                 '(("time" . 1000) ("configuredTime" . 1500) ("memory" . 256)
                   ("output" . 4096) ("isDoubleTL" . t) ("profile" . "fast")))))
    (should (= (rbx-limits-time limits) 1000))
    (should (= (rbx-limits-configured-time limits) 1500))
    (should (= (rbx-limits-memory limits) 256))
    (should (rbx-limits-double-tl limits))
    (should (equal (rbx-limits-profile limits) "fast"))
    (should (= (rbx-limits-expanded-time limits) 2000))
    (should-not (rbx-limits-expanded-time
                 (rbx--parse-limits '(("memory" . 256)))))
    (should-not (rbx--parse-limits nil))))

(ert-deftest rbx-parse-skeleton-reads-limits-per-solution-and-language ()
  (let ((skeleton
         (rbx-parse-skeleton
          '(("solutions" . ((("path" . "a.cpp") ("outcome" . "ACCEPTED")
                             ("limits" . (("time" . 1000) ("isDoubleTL" . t))))
                            (("path" . "b.py") ("outcome" . "ACCEPTED"))))
            ("limits" . (("cpp" . (("time" . 1000) ("memory" . 256)))
                         ("py" . (("time" . 3000) ("memory" . 256)))))))))
    (should (= (rbx-limits-time
                (rbx-solution-limits (car (rbx-skeleton-solutions skeleton))))
               1000))
    (should-not (rbx-solution-limits
                 (cadr (rbx-skeleton-solutions skeleton))))
    (should (equal (mapcar #'car (rbx-skeleton-limits skeleton))
                   '("cpp" "py")))
    (should (= (rbx-limits-time
                (cdr (assoc "py" (rbx-skeleton-limits skeleton))))
               3000))))

(ert-deftest rbx-parse-evaluation-reads-its-own-limits-and-wall-time ()
  (let ((evaluation
         (rbx-parse-evaluation
          '(("result" . (("outcome" . "time-limit-exceeded")))
            ("log" . (("time" . 2.0) ("wall_time" . 2.1)
                      ("metadata" . (("limits" . (("time" . 1000)
                                                  ("isDoubleTL" . t)))))))))))
    (should (= (rbx-limits-time (rbx-evaluation-limits evaluation)) 1000))
    (should (= (rbx-evaluation-wall-time evaluation) 2.1))))

(ert-deftest rbx-parse-report-reads-time-limit-and-untuned-suspicion ()
  (let ((report (rbx--parse-solution-report
                 '(("path" . "a.cpp") ("index" . 0) ("timeLimit" . 1.5)
                   ("untunedLimitsSuspected" . t)))))
    (should (= (rbx-solution-report-time-limit report) 1.5))
    (should (rbx-solution-report-untuned-limits-suspected report)))
  (let ((report (rbx--parse-solution-report '(("path" . "a.cpp") ("index" . 0)))))
    (should-not (rbx-solution-report-time-limit report))
    (should-not (rbx-solution-report-untuned-limits-suspected report))))

(ert-deftest rbx-load-report-survives-a-half-written-file ()
  (rbx-test-with-directory root
    (let ((package (rbx-package-create
                    :root (file-name-as-directory root) :build-dir "build"))
          (path ".rbx/runs/report.yml"))
      (rbx-reset-artifact-cache)
      (rbx-test-write root path "version: 1\nsolutions: [\n  - path: a.cpp\n")
      (should-not (rbx-load-report package))
      ;; The finished write must be picked up even though the broken parse
      ;; happened first and the file kept its name.
      (rbx-test-write
       root path
       (concat "version: 1\nsolutions:\n  - path: a.cpp\n    index: 0\n"
               "    outcome: accepted\n"))
      (let ((report (rbx-load-report package)))
        (should report)
        (should (= (length (rbx-run-report-solutions report)) 1)))
      ;; And a later torn rewrite drops the stale report rather than
      ;; showing the previous run's verdicts for the new one.
      (rbx-test-write root path "version: 1\nsolutions: [\n")
      (should-not (rbx-load-report package)))))

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

(ert-deftest rbx-testset-find-test-looks-up-by-group-and-index ()
  (let* ((wanted (rbx-testset-test-create :group "main" :index 3))
        (testset (rbx-testset-create
                  :tests (list (rbx-testset-test-create :group "main" :index 0)
                              wanted
                              (rbx-testset-test-create :group "samples"
                                                       :index 3)))))
    (should (eq (rbx-testset-find-test testset "main" 3) wanted))
    (should-not (rbx-testset-find-test testset "main" 4))
    (should-not (rbx-testset-find-test testset "other" 3))))

(ert-deftest rbx-parse-contest-problem-reads-declared-fields ()
  (let ((problem (rbx--parse-contest-problem
                  '(("short_name" . "A")
                    ("aliases" . ("alpha"))
                    ("path" . "problems/a")
                    ("color" . "#ff0000")
                    ("colorName" . "Red")))))
    (should (equal (rbx-contest-problem-short-name problem) "A"))
    (should (equal (rbx-contest-problem-aliases problem) '("alpha")))
    (should (equal (rbx-contest-problem-path problem) "problems/a"))
    (should (equal (rbx-contest-problem-color problem) "#ff0000"))
    (should (equal (rbx-contest-problem-color-name problem) "Red"))))

(ert-deftest rbx-parse-contest-problem-requires-short-name ()
  (should-not (rbx--parse-contest-problem '(("path" . "problems/a")))))

(ert-deftest rbx-contest-problem-resolved-path-defaults-to-short-name ()
  (let ((problem (rbx-contest-problem-create :short-name "B")))
    (should (equal (rbx-contest-problem-resolved-path problem "/contest/")
                   (expand-file-name "B" "/contest/")))))

(ert-deftest rbx-contest-problem-resolved-path-honors-declared-path ()
  (let ((problem (rbx-contest-problem-create :short-name "B" :path "prob/b")))
    (should (equal (rbx-contest-problem-resolved-path problem "/contest/")
                   (expand-file-name "prob/b" "/contest/")))))

(ert-deftest rbx-parse-contest-reads-problems-and-dispatcher-flag ()
  (let ((contest (rbx-parse-contest
                  '(("name" . "Finals")
                    ("use_variants" . t)
                    ("problems" .
                     ((("short_name" . "A")) (("short_name" . "B"))))))))
    (should (equal (rbx-contest-name contest) "Finals"))
    (should (rbx-contest-use-variants contest))
    (should (equal (mapcar #'rbx-contest-problem-short-name
                           (rbx-contest-problems contest))
                   '("A" "B")))))

(ert-deftest rbx-load-contest-tags-variant-id-and-source-path ()
  (rbx-test-with-directory root
    (let ((path (rbx-test-write root "contest.div1.rbx.yml" "ignored\n")))
      (rbx-reset-artifact-cache)
      (cl-letf (((symbol-function 'rbx-read-yaml)
                 (lambda (_path) '(("name" . "Division 1")))))
        (let ((contest (rbx-load-contest path "div1")))
          (should (equal (rbx-contest-name contest) "Division 1"))
          (should (equal (rbx-contest-variant-id contest) "div1"))
          (should (equal (rbx-contest-source-path contest) path)))))))

(ert-deftest rbx-load-contest-variants-omits-dispatcher-sentinel ()
  (rbx-test-with-directory root
    (rbx-test-write root "contest.rbx.yml" "ignored\n")
    (rbx-test-write root "contest.div1.rbx.yml" "ignored\n")
    (rbx-reset-artifact-cache)
    (cl-letf (((symbol-function 'rbx-read-yaml)
               (lambda (path)
                 (if (string-match-p "contest\\.rbx\\.yml\\'" path)
                     '(("use_variants" . t))
                   '(("name" . "Division 1")
                     ("problems" . ((("short_name" . "A")))))))))
      (let ((contests (rbx-load-contest-variants root)))
        (should (= (length contests) 1))
        (should (equal (rbx-contest-variant-id (car contests)) "div1"))))))

(ert-deftest rbx-load-contest-variants-includes-canonical-when-not-dispatching ()
  (rbx-test-with-directory root
    (rbx-test-write root "contest.rbx.yml" "ignored\n")
    (rbx-reset-artifact-cache)
    (cl-letf (((symbol-function 'rbx-read-yaml)
               (lambda (_path)
                 '(("name" . "Finals") ("problems" . ((("short_name" . "A"))))))))
      (let ((contests (rbx-load-contest-variants root)))
        (should (= (length contests) 1))
        (should (null (rbx-contest-variant-id (car contests))))))))

(ert-deftest rbx-package-contest-membership-matches-default-path ()
  (rbx-test-with-directory root
    (rbx-test-write root "contest.rbx.yml" "ignored\n")
    (let ((package-root (expand-file-name "A" root)))
      (make-directory package-root t)
      (rbx-reset-artifact-cache)
      (cl-letf (((symbol-function 'rbx-read-yaml)
                 (lambda (_path)
                   '(("name" . "Finals")
                     ("problems" .
                      ((("short_name" . "A") ("color" . "red"))
                       (("short_name" . "B"))))))))
        (let* ((package (rbx-package-create
                         :root (file-name-as-directory package-root)
                         :build-dir "build"))
               (membership (rbx-package-contest-membership package)))
          (should membership)
          (should (equal (rbx-contest-problem-short-name
                          (rbx-contest-membership-problem membership))
                         "A"))
          (should (equal (rbx-contest-name (rbx-contest-membership-contest
                                            membership))
                         "Finals"))
          (should (equal (rbx-contest-membership-root membership)
                         (file-name-as-directory root))))))))

(ert-deftest rbx-package-contest-membership-honors-declared-path ()
  (rbx-test-with-directory root
    (rbx-test-write root "contest.rbx.yml" "ignored\n")
    (let ((package-root (expand-file-name "solutions/first" root)))
      (make-directory package-root t)
      (rbx-reset-artifact-cache)
      (cl-letf (((symbol-function 'rbx-read-yaml)
                 (lambda (_path)
                   '(("problems" .
                      ((("short_name" . "A") ("path" . "solutions/first"))))))))
        (let* ((package (rbx-package-create
                         :root (file-name-as-directory package-root)
                         :build-dir "build"))
               (membership (rbx-package-contest-membership package)))
          (should membership)
          (should (equal (rbx-contest-problem-short-name
                          (rbx-contest-membership-problem membership))
                         "A")))))))

(ert-deftest rbx-package-contest-membership-nil-outside-a-contest ()
  (rbx-test-with-directory root
    (let ((package (rbx-package-create
                    :root (file-name-as-directory root) :build-dir "build")))
      (should-not (rbx-package-contest-membership package)))))

(ert-deftest rbx-package-contest-membership-nil-when-unlisted ()
  (rbx-test-with-directory root
    (rbx-test-write root "contest.rbx.yml" "ignored\n")
    (let ((package-root (expand-file-name "C" root)))
      (make-directory package-root t)
      (rbx-reset-artifact-cache)
      (cl-letf (((symbol-function 'rbx-read-yaml)
                 (lambda (_path)
                   '(("problems" . ((("short_name" . "A"))))))))
        (let ((package (rbx-package-create
                       :root (file-name-as-directory package-root)
                       :build-dir "build")))
          (should-not (rbx-package-contest-membership package)))))))

(ert-deftest rbx-testset-statistics-aggregates-by-group-in-order ()
  (let* ((entry-a1 (rbx-testcase-create :group "samples" :index 0))
         (entry-a2 (rbx-testcase-create :group "samples" :index 1))
         (entry-b1 (rbx-testcase-create :group "main" :index 0))
         (test-a1 (rbx-testset-test-create :group "samples" :index 0
                                           :input-size 10 :output-size 2))
         (test-a2 (rbx-testset-test-create :group "samples" :index 1
                                           :input-size 20 :output-size 4))
         (testset (rbx-testset-create
                  :groups (list (rbx-testset-group-create :name "samples")
                               (rbx-testset-group-create :name "main")
                               (rbx-testset-group-create :name "empty"))
                  :entries (list entry-a1 entry-a2 entry-b1)
                  :tests (list test-a1 test-a2)))
         (stats (rbx-testset-statistics testset)))
    (should (equal (mapcar #'rbx-testset-group-stats-group stats)
                  '("samples" "main")))
    (let ((samples (car stats)) (main (cadr stats)))
      (should (= (rbx-testset-group-stats-count samples) 2))
      (should (= (rbx-testset-group-stats-input-size samples) 30))
      (should (= (rbx-testset-group-stats-output-size samples) 6))
      (should (= (rbx-testset-group-stats-count main) 1))
      (should (= (rbx-testset-group-stats-input-size main) 0))
      (should (= (rbx-testset-group-stats-output-size main) 0)))))

(ert-deftest rbx-testset-statistics-nil-for-a-testset-without-entries ()
  (should-not (rbx-testset-statistics (rbx-testset-create))))

(ert-deftest rbx-parse-problem-statements-reads-declared-fields ()
  (let ((statements (rbx-parse-problem-statements
                     '(("name" . "problem-a")
                       ("statements" .
                        ((("language" . "en") ("title" . "Problem A")
                          ("file" . "statement/statement.rbx.tex")
                          ("type" . "rbxTeX"))))))))
    (should (= (length statements) 1))
    (let ((statement (car statements)))
      (should (equal (rbx-problem-statement-language statement) "en"))
      (should (equal (rbx-problem-statement-title statement) "Problem A"))
      (should (equal (rbx-problem-statement-file statement)
                    "statement/statement.rbx.tex"))
      (should (equal (rbx-problem-statement-type statement) "rbxTeX")))))

(ert-deftest rbx-parse-problem-statements-includes-tutorials ()
  (let ((statements (rbx-parse-problem-statements
                     '(("statements" . ((("language" . "en")
                                         ("file" . "statement.rbx.tex"))))
                       ("tutorials" . ((("language" . "en")
                                        ("file" . "tutorial.rbx.tex"))))))))
    (should (equal (mapcar #'rbx-problem-statement-file statements)
                   '("statement.rbx.tex" "tutorial.rbx.tex")))))

(ert-deftest rbx-parse-problem-statements-requires-a-file ()
  (should-not (rbx-parse-problem-statements
              '(("statements" . ((("language" . "en"))))))))

(ert-deftest rbx-parse-problem-statements-empty-without-any-declared ()
  (should-not (rbx-parse-problem-statements '(("name" . "problem-a")))))

(ert-deftest rbx-package-statement-p-matches-a-declared-file ()
  (rbx-test-with-directory root
    (rbx-test-write root "problem.rbx.yml" "ignored\n")
    (rbx-test-write root "statement/statement.rbx.tex" "content\n")
    (let ((package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build")))
      (rbx-reset-artifact-cache)
      (cl-letf (((symbol-function 'rbx-read-yaml)
                (lambda (_path)
                  '(("statements" .
                    ((("file" . "statement/statement.rbx.tex"))))))))
        (should (rbx-package-statement-p
                package (expand-file-name "statement/statement.rbx.tex" root)))
        (should-not (rbx-package-statement-p
                    package (expand-file-name "other.tex" root)))))))

(ert-deftest rbx-parse-statement-report-reads-outputs-and-findings ()
  (let* ((report (rbx-parse-statement-report
                  '(("version" . 1)
                    ("outputs"
                     . ((("kind" . "statement") ("language" . "en")
                         ("format" . "pdf") ("path" . "build/statement-en.pdf")
                         ("source" . "statement/statement.rbx.tex")
                         ("status" . "failed") ("seconds" . 1.5)
                         ("findings"
                          . ((("origin" . "latex") ("severity" . "error")
                              ("message" . "Undefined control sequence.")
                              ("file" . "statement/statement.rbx.tex")
                              ("line" . 12) ("context" . "\\foo")))))
                        (("kind" . "tutorial") ("format" . "pdf")
                         ("path" . "build/tutorial-en.pdf")
                         ("status" . "ok")))))))
         (outputs (rbx-statement-report-outputs report))
         (failed (car outputs))
         (finding (car (rbx-statement-output-findings failed))))
    (should (= (length outputs) 2))
    (should (equal (rbx-statement-output-path failed)
                   "build/statement-en.pdf"))
    (should (equal (rbx-statement-output-status failed) "failed"))
    (should (equal (rbx-statement-finding-file finding)
                   "statement/statement.rbx.tex"))
    (should (= (rbx-statement-finding-line finding) 12))
    (should (equal (rbx-statement-finding-severity finding) "error"))
    (should (equal (rbx-statement-output-status (cadr outputs)) "ok"))))

(ert-deftest rbx-parse-statement-report-ignores-unknown-versions ()
  (should-not (rbx-parse-statement-report
               '(("version" . 2) ("outputs" . ((("path" . "x.pdf"))))))))

(ert-deftest rbx-parse-statement-report-drops-outputs-without-a-path ()
  (let ((report (rbx-parse-statement-report
                 '(("version" . 1)
                   ("outputs" . ((("kind" . "statement"))))))))
    (should-not (rbx-statement-report-outputs report))))

(defconst rbx-test--stress-raw
  '(("version" . 1) ("state" . "done") ("startedAt" . "2026-10-20T10:00:00Z")
    ("elapsed" . 12.5) ("executed" . 40) ("skipped" . 3)
    ("pid" . 42) ("host" . "box")
    ("spec" . (("name" . "wa-hunt") ("generator" . "gen 1 10")
               ("finder" . "[sols/a.cpp] ~ INCORRECT") ("slowest" . :false)
               ("timeout" . 10) ("findingsLimit" . 5) ("timelimit" . 1000)
               ("doubleTL" . t) ("fuzz" . ("main"))))
    ("solutions" . ("sols/main.cpp" "sols/a.cpp"))
    ("findings"
     . ((("index" . 1) ("duration" . 80)
         ("generator" . (("name" . "gen") ("args" . "1 10 --seed=7")))
         ("results" . ((("solution" . 1) ("outcome" . "wrong-answer")
                        ("time" . 0.12) ("memory" . 2048)))))
        (("index" . 2)
         ("generator" . (("name" . "gen")))))))
  "A stress manifest as the YAML reader delivers it.")

(ert-deftest rbx-parse-stress-reads-session-and-findings ()
  (let* ((stress (rbx-parse-stress rbx-test--stress-raw))
         (finding (car (rbx-stress-findings stress)))
         (result (car (rbx-stress-finding-results finding))))
    (should (equal (rbx-stress-state stress) "done"))
    (should (equal (rbx-stress-name stress) "wa-hunt"))
    (should (equal (rbx-stress-finder stress) "[sols/a.cpp] ~ INCORRECT"))
    (should (= (rbx-stress-executed stress) 40))
    (should (= (rbx-stress-skipped stress) 3))
    (should (rbx-stress-double-tl stress))
    (should (= (rbx-stress-timelimit stress) 1000))
    (should (equal (rbx-stress-fuzz stress) '("main")))
    (should (equal (rbx-stress-solutions stress)
                   '("sols/main.cpp" "sols/a.cpp")))
    (should (= (length (rbx-stress-findings stress)) 2))
    (should (= (rbx-stress-finding-index finding) 1))
    (should (equal (rbx-stress-finding-generator finding)
                   "gen 1 10 --seed=7"))
    (should (= (rbx-stress-finding-duration finding) 80))
    (should (= (rbx-stress-result-solution result) 1))
    (should (equal (rbx-stress-result-outcome result) "wrong-answer"))
    (should (= (rbx-stress-result-memory result) 2048))
    (should (equal (rbx-stress-finding-generator
                    (cadr (rbx-stress-findings stress)))
                   "gen"))))

(ert-deftest rbx-parse-stress-ignores-unknown-versions-and-bad-states ()
  (should-not (rbx-parse-stress '(("version" . 2) ("state" . "done"))))
  (should-not (rbx-parse-stress '(("version" . 1)))))

(ert-deftest rbx-parse-stress-skips-findings-without-an-index ()
  (let ((stress (rbx-parse-stress
                 '(("version" . 1) ("state" . "running")
                   ("findings" . ((("generator" . (("name" . "g")))))
                   )))))
    (should-not (rbx-stress-findings stress))))

(provide 'rbx-model-test)
;;; rbx-model-test.el ends here
