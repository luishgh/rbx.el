;;; rbx-model-test.el --- Tests for rbx-model -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the tolerant readers of rbx artifact models.

;;; Code:

(require 'rbx-model)
(require 'rbx-cli)
(require 'test-helper)
(require 'rbx-time-inspect-fixtures)

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

(ert-deftest rbx-parse-evaluation-reads-the-testcase-score ()
  (should (= (rbx-evaluation-score
              (rbx-parse-evaluation
               '(("result" . (("outcome" . "partially-correct")
                              ("score" . 0.37037))))))
             0.37037))
  (should-not (rbx-evaluation-score
               (rbx-parse-evaluation
                '(("result" . (("outcome" . "accepted"))))))))

(ert-deftest rbx-parse-evaluation-reads-its-own-limits-and-wall-time ()
  (let ((evaluation
         (rbx-parse-evaluation
          '(("result" . (("outcome" . "time-limit-exceeded")))
            ("log" . (("time" . 2.0) ("wall_time" . 2.1)
                      ("metadata" . (("limits" . (("time" . 1000)
                                                  ("isDoubleTL" . t)))))))))))
    (should (= (rbx-limits-time (rbx-evaluation-limits evaluation)) 1000))
    (should (= (rbx-evaluation-wall-time evaluation) 2.1))))

(ert-deftest rbx-parse-evaluation-reads-checker-and-interactor-times ()
  (let ((evaluation
         (rbx-parse-evaluation
          '(("result" . (("outcome" . "accepted")
                         ("checker_timing" . (("time" . 0.012)))
                         ("interactor_timing" . (("time" . 0.3)
                                                 ("wall_time" . 0.4)))))
            ("log" . (("time" . 0.1)))))))
    (should (= (rbx-evaluation-checker-time evaluation) 0.012))
    (should (= (rbx-evaluation-interactor-time evaluation) 0.3)))
  (let ((evaluation (rbx-parse-evaluation
                     '(("result" . (("outcome" . "accepted")))))))
    (should-not (rbx-evaluation-checker-time evaluation))
    (should-not (rbx-evaluation-interactor-time evaluation))))

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

(defun rbx-test--statement-p (file template &rest paths)
  "Return whether FILE is a statement of a package declaring TEMPLATE.
PATHS are created under the package first."
  (rbx-test-with-directory root
    (rbx-test-write root "problem.rbx.yml" "ignored\n")
    (dolist (path paths) (rbx-test-write root path "content\n"))
    (let ((package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build")))
      (rbx-reset-artifact-cache)
      (cl-letf (((symbol-function 'rbx-read-yaml)
                 (lambda (_path)
                   `(("statements" . ((("language" . "*")
                                       ("file" . ,template))))))))
        (and (rbx-package-statement-p
              package (expand-file-name file root))
             t)))))

(ert-deftest rbx-package-statement-p-matches-a-lang-template ()
  (should (rbx-test--statement-p "statement/statement-en.rbx.tex"
                                 "statement/statement-{lang}.rbx.tex"
                                 "statement/statement-en.rbx.tex")))

(ert-deftest rbx-package-statement-p-rejects-unrelated-for-a-lang-template ()
  (should-not (rbx-test--statement-p "statement/other.tex"
                                     "statement/statement-{lang}.rbx.tex"
                                     "statement/other.tex")))

(ert-deftest rbx-package-statement-p-needs-one-lang-value-throughout ()
  (should (rbx-test--statement-p "en/statement-en.tex" "{lang}/statement-{lang}.tex"))
  (should-not (rbx-test--statement-p "en/statement-pt.tex"
                                     "{lang}/statement-{lang}.tex")))

(ert-deftest rbx-package-statement-p-still-matches-a-literal-file ()
  (should (rbx-test--statement-p "statement/a.tex" "statement/a.tex")))

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

(ert-deftest rbx-parse-skeleton-reads-validation ()
  (let* ((skeleton
          (rbx-parse-skeleton
           '(("validation"
              . (("mode" . "warn")
                 ("invalid"
                  . ((("group" . "main") ("index" . 2)
                      ("validator" . "val.cpp") ("message" . "n too big"))
                     (("group" . "main") ("index" . 3)
                      ("validator" . "val.cpp"))
                     (("group" . "main") ("validator" . "bad"))
                     LATER)))))))
         (invalid (rbx-skeleton-invalid skeleton)))
    (should (equal (rbx-skeleton-validation-mode skeleton) "warn"))
    ;; The malformed entry costs only itself.
    (should (= (length invalid) 2))
    (should (equal (rbx-invalid-test-group (car invalid)) "main"))
    (should (= (rbx-invalid-test-index (car invalid)) 2))
    (should (equal (rbx-invalid-test-validator (car invalid)) "val.cpp"))
    (should (equal (rbx-invalid-test-message (car invalid)) "n too big"))
    (should-not (rbx-invalid-test-message (cadr invalid)))))

(ert-deftest rbx-parse-skeleton-reads-quiet-validation-modes ()
  (dolist (mode '("off" "fail"))
    (should (equal (rbx-skeleton-validation-mode
                    (rbx-parse-skeleton `(("validation" . (("mode" . ,mode))))))
                   mode))))

(ert-deftest rbx-parse-skeleton-ignores-absent-or-unknown-validation ()
  (dolist (raw '((("solutions"))
                 (("validation"
                   . (("mode" . "sometimes")
                      ("invalid" . ((("group" . "a") ("index" . 0)
                                     ("validator" . "v")))))))))
    (let ((skeleton (rbx-parse-skeleton raw)))
      (should-not (rbx-skeleton-validation-mode skeleton))
      (should-not (rbx-skeleton-invalid skeleton)))))

(ert-deftest rbx-parse-report-reads-how-the-run-ended ()
  (cl-flet ((parse (&rest fields)
              (rbx-parse-report `(("version" . 1) ,@fields))))
    (let ((report (parse '("finished" . t) '("exitStatus" . "interrupted"))))
      (should (rbx-run-report-finished report))
      (should (equal (rbx-run-report-exit-status report) "interrupted")))
    (should (equal (rbx-run-report-exit-status
                    (parse '("finished" . t) '("exitStatus" . "error")))
                   "error"))
    ;; Finished without a usable status reads as an error, as upstream does.
    (should (equal (rbx-run-report-exit-status (parse '("finished" . t)))
                   "error"))
    (should (equal (rbx-run-report-exit-status
                    (parse '("finished" . t) '("exitStatus" . "weird")))
                   "error"))
    ;; Without the marker the run is in flight, or from an older rbx.
    (should-not (rbx-run-report-finished (parse '("exitStatus" . "ok"))))
    (should-not (rbx-run-report-finished (parse)))
    (should-not (rbx-run-report-exit-status (parse)))))

;;;; Declared outcome of a solution file

(ert-deftest rbx-normalize-outcome-follows-rbx-aliases ()
  (should (equal (rbx-normalize-outcome "ac/tle") "ACCEPTED_OR_TLE"))
  (should (equal (rbx-normalize-outcome "AC or TLE") "ACCEPTED_OR_TLE"))
  (should (equal (rbx-normalize-outcome "fail") "INCORRECT"))
  (should (equal (rbx-normalize-outcome "Accepted") "ACCEPTED"))
  (should (equal (rbx-normalize-outcome "wrong-answer") "WRONG_ANSWER"))
  (should (equal (rbx-normalize-outcome "TIME_LIMIT_EXCEEDED")
                 "TIME_LIMIT_EXCEEDED"))
  (should (equal (rbx-normalize-outcome "tl+ml") "TLE_OR_MLE"))
  (should-not (rbx-normalize-outcome "nonsense"))
  (should-not (rbx-normalize-outcome nil))
  (should-not (rbx-normalize-outcome 3)))

(defun rbx-model-test--declared (manifest file)
  "Return the outcome MANIFEST declares for FILE in a temporary package."
  (rbx-test-with-directory root
    (rbx-test-write root "problem.rbx.yml" manifest)
    (rbx-reset-artifact-cache)
    (rbx-declared-outcome (rbx--make-package root)
                          (expand-file-name file root))))

(ert-deftest rbx-declared-outcome-reads-an-exact-path ()
  (let ((manifest (concat "solutions:\n"
                          "  - path: sols/main.cpp\n    outcome: accepted\n"
                          "  - path: sols/wa.cpp\n    outcome: wa\n"
                          "  - path: sols/any.cpp\n")))
    (should (equal (rbx-model-test--declared manifest "sols/wa.cpp")
                   "WRONG_ANSWER"))
    (should (equal (rbx-model-test--declared manifest "sols/main.cpp")
                   "ACCEPTED"))
    (should (equal (rbx-model-test--declared manifest "sols/any.cpp") "ANY"))))

(ert-deftest rbx-declared-outcome-matches-globs ()
  (let ((manifest (concat "solutions:\n"
                          "  - path: sols/*.cpp\n    outcome: ac/tle\n"
                          "  - path: wrong/**/*.py\n    outcome: fail\n")))
    (should (equal (rbx-model-test--declared manifest "sols/a.cpp")
                   "ACCEPTED_OR_TLE"))
    (should-not (rbx-model-test--declared manifest "sols/deep/a.cpp"))
    (should (equal (rbx-model-test--declared manifest "wrong/x/y/a.py")
                   "INCORRECT"))
    (should (equal (rbx-model-test--declared manifest "wrong/a.py")
                   "INCORRECT"))))

(ert-deftest rbx-declared-outcome-prefers-the-most-specific-entry ()
  (let ((manifest (concat "solutions:\n"
                          "  - path: sols/*.cpp\n    outcome: accepted\n"
                          "  - path: sols/slow*.cpp\n    outcome: tle\n"
                          "  - path: sols/slow1.cpp\n    outcome: wa\n")))
    (should (equal (rbx-model-test--declared manifest "sols/slow1.cpp")
                   "WRONG_ANSWER"))
    (should (equal (rbx-model-test--declared manifest "sols/slow2.cpp")
                   "TIME_LIMIT_EXCEEDED"))
    (should (equal (rbx-model-test--declared manifest "sols/fast.cpp")
                   "ACCEPTED"))))

(ert-deftest rbx-declared-outcome-ignores-undeclared-and-broken-manifests ()
  (should-not (rbx-model-test--declared
               "solutions:\n  - path: sols/a.cpp\n" "sols/b.cpp"))
  (should-not (rbx-model-test--declared "name: Demo\n" "sols/b.cpp"))
  (should-not (rbx-model-test--declared
               "solutions:\n  - path: [unclosed\n    outcome: ac\n"
               "sols/a.cpp"))
  (should-not (rbx-model-test--declared
               "solutions:\n  - path: sols/a.cpp\n    outcome: bogus\n"
               "sols/a.cpp"))
  (should-not (rbx-model-test--declared "solutions: 3\n" "sols/a.cpp")))

(ert-deftest rbx-problem-manifest-readers-do-not-share-a-cache-entry ()
  (rbx-test-with-directory root
    (rbx-test-write root "problem.rbx.yml"
                    (concat "statements:\n  - file: s.tex\n"
                            "solutions:\n  - path: a.cpp\n    outcome: ac\n"))
    (rbx-reset-artifact-cache)
    (let ((package (rbx--make-package root)))
      (should (rbx-load-problem-statements package))
      (should (equal (rbx-declared-outcome
                      package (expand-file-name "a.cpp" root))
                     "ACCEPTED"))
      (should (rbx-load-problem-statements package)))))

;;;; Limits profiles

(defconst rbx-test--time-profile-raw
  '(("timeLimit" . 100) ("memoryLimit" . 256)
    ("modifiers" . (("py" . (("time" . 300))) ("cpp" . (("time" . 100)))))
    ("multipliers" . (("acToTimeLimit" . 2.0) ("timeLimitToTle" . 1.5)
                      ("timeResolution" . 100)))
    ("groups"
     . ((("languages" . ("py")) ("timeLimit" . 400) ("origin" . "multiplier")
         ("solutionCount" . 1) ("relativeToLanguage" . "cpp")
         ("multiplier" . 3.0) ("increment" . 50) ("isLeftover" . :false)
         ("estimatedTimeLimit" . 300)
         ("lowerViolation" . (("value" . 500) ("solution" . "sols/slow.py"))))
        (("languages" . ("cpp" "c")) ("timeLimit" . 100) ("origin" . "estimated")
         ("solutionCount" . 1) ("fastest" . 5) ("slowest" . 5)
         ("isLeftover" . t)
         ("lowerBound" . (("value" . 10) ("solution" . "sols/main.cpp")))
         ("upperBound" . (("value" . 120)))
         ("upperValidation"
          . (("confirmed" . ("sols/tle-slow.cpp"))
             ("violating" . ((("value" . 90) ("solution" . "sols/tle-fast.cpp"))))
             ("skipped" . ("sols/tle-never.cpp")))))
        "not a group"
        (("languages" . ("java")) ("origin" . "estimated"))))
    ("baseEstimate" . (("languages") ("timeLimit" . 100) ("origin" . "estimated")
                       ("solutionCount" . 1)))
    ("estimationChecksum" . "v1.h.45bb30e5.-.a2345dd9")
    ("runner" . "local")
    ("someFutureField" . "ignored")
    ("solutions"
     . ((("path" . "sols/main.cpp") ("language" . "cpp") ("role" . "lower")
         ("time" . 5))
        (("path" . "sols/tle-slow.cpp") ("language" . "cpp") ("role" . "upper")
         ("survivedAt" . 150))
        (("path" . "sols/slow.py") ("language" . "py") ("role" . "LOWER")
         ("time" . 250))
        (("path" . "sols/main.kt") ("language" . "kt") ("role" . "lower")
         ("time" . 40))
        (("language" . "cpp") ("role" . "lower"))))
    ("runs"
     . ((("path" . "sols/wa-off.cpp") ("language" . "cpp") ("timeLimit" . 100)
         ("expectedOutcome" . "WRONG_ANSWER") ("outcome" . "wrong-answer")
         ("matchesExpectation" . t) ("time" . 7))
        (("path" . "sols/re.py") ("language" . "py") ("timeLimit" . 300)
         ("expectedOutcome" . "RUNTIME_ERROR") ("outcome" . "accepted")
         ("matchesExpectation" . :false) ("time" . 20) ("complete" . :false))
        (("path" . "sols/ce.go") ("language" . "go") ("timeLimit" . 100)
         ("expectedOutcome" . "COMPILATION_ERROR")
         ("matchesExpectation" . t))
        (("language" . "cpp")))))
  "A limits profile as the YAML reader delivers it.
Shaped after what `rbx time --run-all' writes, with a hand-edited group
and the presentation-only checks rbx records.")

(ert-deftest rbx-parse-time-profile-reads-the-header ()
  (let* ((profile (rbx-parse-time-profile rbx-test--time-profile-raw))
         (multipliers (rbx-time-profile-multipliers profile)))
    (should (= (rbx-time-profile-time-limit profile) 100))
    (should (= (rbx-time-profile-memory-limit profile) 256))
    (should-not (rbx-time-profile-output-limit profile))
    (should-not (rbx-time-profile-inherit profile))
    (should (equal (rbx-time-profile-runner profile) "local"))
    (should (= (rbx-timing-multipliers-ac-to-time-limit multipliers) 2.0))
    (should (= (rbx-timing-multipliers-time-limit-to-tle multipliers) 1.5))
    (should-not (rbx-timing-multipliers-fastest-to-time-limit multipliers))
    (should (= (rbx-timing-multipliers-time-resolution multipliers) 100))))

(ert-deftest rbx-parse-time-profile-reads-groups ()
  (let* ((profile (rbx-parse-time-profile rbx-test--time-profile-raw))
         (groups (rbx-time-profile-groups profile))
         (py (nth 0 groups))
         (cpp (nth 1 groups))
         (base (rbx-time-profile-base-estimate profile)))
    ;; The string and the group with no limit are dropped.
    (should (= (length groups) 2))
    (should (equal (rbx-timing-group-languages py) '("py")))
    (should (= (rbx-timing-group-time-limit py) 400))
    (should (equal (rbx-timing-group-origin py) "multiplier"))
    (should (equal (rbx-timing-group-relative-to-language py) "cpp"))
    (should (= (rbx-timing-group-multiplier py) 3.0))
    (should (= (rbx-timing-group-increment py) 50))
    (should (= (rbx-timing-group-estimated-time-limit py) 300))
    (should-not (rbx-timing-group-leftover py))
    (should (= (rbx-timing-bound-value (rbx-timing-group-lower-violation py))
               500))
    (should (equal (rbx-timing-bound-solution
                    (rbx-timing-group-lower-violation py))
                   "sols/slow.py"))
    (should (rbx-timing-group-leftover cpp))
    (should (= (rbx-timing-group-fastest cpp) 5))
    (should (= (rbx-timing-bound-value (rbx-timing-group-lower-bound cpp)) 10))
    (should-not (rbx-timing-bound-solution (rbx-timing-group-upper-bound cpp)))
    (should (equal (rbx-timing-group-confirmed cpp) '("sols/tle-slow.cpp")))
    (should (equal (mapcar #'rbx-timing-bound-solution
                           (rbx-timing-group-violating cpp))
                   '("sols/tle-fast.cpp")))
    (should (equal (rbx-timing-group-skipped cpp) '("sols/tle-never.cpp")))
    (should (equal (rbx-timing-group-languages base) nil))
    (should (= (rbx-timing-group-time-limit base) 100))))

(ert-deftest rbx-parse-time-profile-reads-measurements-and-runs ()
  (let* ((profile (rbx-parse-time-profile rbx-test--time-profile-raw))
         (solutions (rbx-time-profile-solutions profile))
         (runs (rbx-time-profile-runs profile)))
    ;; Entries without a path are dropped.
    (should (= (length solutions) 4))
    (should (= (length runs) 3))
    (let ((main (nth 0 solutions)) (slow (nth 1 solutions)))
      (should (equal (rbx-timing-solution-path main) "sols/main.cpp"))
      (should (equal (rbx-timing-solution-language main) "cpp"))
      (should (eq (rbx-timing-solution-role main) 'lower))
      (should (= (rbx-timing-solution-time main) 5))
      (should (eq (rbx-timing-solution-role slow) 'upper))
      (should-not (rbx-timing-solution-time slow))
      (should (= (rbx-timing-solution-survived-at slow) 150)))
    ;; Roles are read case-insensitively.
    (should (eq (rbx-timing-solution-role (nth 2 solutions)) 'lower))
    (let ((wa (nth 0 runs)) (re (nth 1 runs)) (ce (nth 2 runs)))
      (should (equal (rbx-profile-run-path wa) "sols/wa-off.cpp"))
      (should (= (rbx-profile-run-time-limit wa) 100))
      (should (equal (rbx-profile-run-expected-outcome wa) "WRONG_ANSWER"))
      (should (equal (rbx-profile-run-outcome wa) "wrong-answer"))
      (should (eq (rbx-profile-run-matches-expectation wa) t))
      (should (rbx-profile-run-complete wa))
      (should (= (rbx-profile-run-time wa) 7))
      (should (eq (rbx-profile-run-matches-expectation re) nil))
      (should-not (rbx-profile-run-complete re))
      (should-not (rbx-profile-run-outcome ce))
      (should-not (rbx-profile-run-time ce)))))

(ert-deftest rbx-parse-time-profile-tolerates-older-and-sparse-profiles ()
  ;; Before rbx 2.6.1 there were no runs, and before 2.6.2 no runner.
  (let ((profile (rbx-parse-time-profile
                  '(("timeLimit" . 1000) ("inheritFromPackage" . t)))))
    (should (= (rbx-time-profile-time-limit profile) 1000))
    (should (rbx-time-profile-inherit profile))
    (should-not (rbx-time-profile-runner profile))
    (should-not (rbx-time-profile-multipliers profile))
    (should-not (rbx-time-profile-groups profile))
    (should-not (rbx-time-profile-base-estimate profile))
    (should-not (rbx-time-profile-solutions profile))
    (should-not (rbx-time-profile-runs profile)))
  ;; An unknown matchesExpectation is neither a match nor a mismatch.
  (let ((run (car (rbx-time-profile-runs
                   (rbx-parse-time-profile
                    '(("runs" . ((("path" . "a.cpp")
                                  ("expectedOutcome" . "ac"))))))))))
    (should (eq (rbx-profile-run-matches-expectation run) 'unknown))
    (should (equal (rbx-profile-run-expected-outcome run) "ACCEPTED")))
  (should-not (rbx-parse-time-profile nil))
  (should-not (rbx-parse-time-profile '("a" "list"))))

(ert-deftest rbx-time-profile-rows-file-entries-like-rbx ()
  (let* ((profile (rbx-parse-time-profile rbx-test--time-profile-raw))
         (rows (rbx-time-profile-rows profile))
         (base (nth 0 rows))
         (py (nth 1 rows))
         (cpp (nth 2 rows))
         (paths (lambda (row)
                  (list (mapcar #'rbx-timing-solution-path
                                (rbx-time-profile-row-solutions row))
                        (mapcar #'rbx-profile-run-path
                                (rbx-time-profile-row-runs row))))))
    (should (= (length rows) 3))
    (should (eq (rbx-time-profile-row-key base) 'base))
    (should (eq (rbx-time-profile-row-group base)
                (rbx-time-profile-base-estimate profile)))
    (should (= (rbx-time-profile-row-time-limit base) 100))
    (should (equal (rbx-time-profile-row-key py) 0))
    (should (= (rbx-time-profile-row-time-limit py) 400))
    ;; A language in a group is filed there; anything else under base.
    (should (equal (funcall paths base) '(("sols/main.kt") ("sols/ce.go"))))
    (should (equal (funcall paths py) '(("sols/slow.py") ("sols/re.py"))))
    (should (equal (funcall paths cpp)
                   '(("sols/main.cpp" "sols/tle-slow.cpp")
                     ("sols/wa-off.cpp"))))))

(ert-deftest rbx-time-profile-rows-without-groups-put-everything-under-base ()
  (let* ((profile (rbx-parse-time-profile
                   '(("timeLimit" . 700)
                     ("solutions" . ((("path" . "a.cpp") ("language" . "cpp")
                                      ("role" . "lower") ("time" . 3)))))))
         (rows (rbx-time-profile-rows profile)))
    (should (= (length rows) 1))
    (should-not (rbx-time-profile-row-group (car rows)))
    (should (= (rbx-time-profile-row-time-limit (car rows)) 700))
    (should (= (length (rbx-time-profile-row-solutions (car rows))) 1))))

(ert-deftest rbx-load-time-profile-reads-the-named-profile ()
  (rbx-test-with-directory root
    (rbx-test-write root ".limits/local.yml"
                    (concat "timeLimit: 100\nrunner: local\nsolutions:\n"
                            "- {path: sols/main.cpp, language: cpp, "
                            "role: lower, time: 5}\n"))
    (let ((package (rbx-package-create
                    :root (file-name-as-directory root) :build-dir "build")))
      (rbx-reset-artifact-cache)
      (should (equal (rbx-time-profile-runner
                      (rbx-load-time-profile package "local"))
                     "local"))
      (should-not (rbx-load-time-profile package "moj")))))

;;;; rbx time-inspect

(defun rbx-test--inspection (json)
  "Parse JSON, as `rbx time-inspect' prints it, into an inspection."
  (rbx-parse-time-inspection (rbx-cli-parse-json-object json)))

(defun rbx-test--inspect-row (inspection key)
  "Return INSPECTION's row with KEY."
  (cl-find key (rbx-time-inspection-rows inspection)
           :key #'rbx-time-inspect-row-key :test #'equal))

(ert-deftest rbx-parse-time-inspection-reads-the-header ()
  (let* ((inspection (rbx-test--inspection rbx-time-inspect-fixture-saved))
         (effective (rbx-time-inspection-effective inspection))
         (last-run (rbx-time-inspection-last-run inspection)))
    (should (equal (rbx-time-inspection-profile inspection) "local"))
    (should-not (rbx-time-inspection-errors inspection))
    (should-not (rbx-time-inspection-inherit inspection))
    (should (= (rbx-time-inspection-time-limit inspection) 100))
    (should-not (rbx-time-inspection-memory-limit inspection))
    (should (= (rbx-timing-multipliers-ac-to-time-limit
                (rbx-time-inspection-multipliers inspection))
               2.0))
    (should (eq (rbx-time-inspection-runs-source inspection) 'profile))
    (should-not (rbx-time-inspection-stale inspection))
    (should (equal (rbx-time-last-run-profiles last-run) '("local")))
    (should (equal (rbx-time-last-run-runner last-run) "local"))
    (should (rbx-time-last-run-finished last-run))
    (should (equal (rbx-time-last-run-ended-at last-run)
                   "2026-11-11T10:37:09-03:00"))
    (should (= (rbx-time-effective-limits-time-limit effective) 100))
    (should (= (rbx-time-effective-limits-memory-limit effective) 256))
    (should (= (rbx-time-effective-limits-output-limit effective) 4096))
    (should (equal (rbx-time-effective-limits-languages effective)
                   '(("cpp" 100 256) ("py" 300 256))))
    (should (equal (rbx-time-effective-limits-package effective)
                   '(1000 256 4096)))))

(ert-deftest rbx-parse-time-inspection-reads-rows-and-checks ()
  (let* ((inspection (rbx-test--inspection rbx-time-inspect-fixture-saved))
         (base (rbx-test--inspect-row inspection 'base))
         (py (rbx-test--inspect-row inspection 0))
         (cpp (rbx-test--inspect-row inspection 2))
         (check (rbx-time-inspect-row-check cpp)))
    (should (equal (mapcar #'rbx-time-inspect-row-key
                           (rbx-time-inspection-rows inspection))
                   '(base 0 2)))
    (should (equal (rbx-timing-group-origin (rbx-time-inspect-row-group py))
                   "multiplier"))
    (should (equal (rbx-timing-group-languages (rbx-time-inspect-row-group cpp))
                   '("cpp" "c")))
    (should (= (rbx-time-inspect-row-time-limit cpp) 100))
    (should-not (rbx-time-inspect-row-solutions base))
    (should (= (rbx-time-group-check-time-limit check) 100))
    (should (= (rbx-time-group-check-min check) 12))
    (should (equal (rbx-time-group-check-min-solution check) "sols/main.cpp"))
    (should (= (rbx-time-group-check-slowest check) 6))
    (should-not (rbx-time-group-check-max check))
    (should (equal (rbx-time-group-check-confirmed check) '("sols/tle-spin.cpp")))
    (should (rbx-time-group-check-ok check))
    (should-not (rbx-time-group-check-below-min check))
    (should-not (rbx-time-group-check-rejects-own-solutions check))))

(ert-deftest rbx-parse-time-inspection-reads-solution-checks-and-runs ()
  (let* ((inspection (rbx-test--inspection rbx-time-inspect-fixture-edited))
         (cpp (rbx-test--inspect-row inspection 2))
         (check (rbx-time-inspect-row-check cpp))
         (main (car (rbx-time-inspect-row-solutions cpp)))
         (slow (cadr (rbx-time-inspect-row-solutions cpp)))
         (run (car (rbx-time-inspect-row-runs cpp))))
    (should (= (rbx-time-group-check-estimated check) 100))
    (should (rbx-time-group-check-below-min check))
    (should (rbx-time-group-check-rejects-own-solutions check))
    (should-not (rbx-time-group-check-ok check))
    (should (equal (rbx-time-solution-check-path main) "sols/main.cpp"))
    (should (eq (rbx-time-solution-check-role main) 'lower))
    (should (= (rbx-time-solution-check-time main) 6))
    (should (eq (rbx-time-solution-check-status main) 'fails))
    (should (equal (rbx-time-solution-check-expected-outcome main) "ACCEPTED"))
    (should (eq (rbx-time-solution-check-role slow) 'upper))
    (should-not (rbx-time-solution-check-time slow))
    (should (= (rbx-time-solution-check-survived-at slow) 150))
    (should (= (rbx-time-solution-check-max slow) 100))
    (should (equal (rbx-time-solution-check-expected-outcome slow)
                   "TIME_LIMIT_EXCEEDED"))
    (should (equal (rbx-profile-run-path run) "sols/wa-off.cpp"))
    (should (equal (rbx-profile-run-expected-outcome run) "WRONG_ANSWER"))
    (should (equal (rbx-profile-run-outcome run) "wrong-answer"))
    (should (eq (rbx-profile-run-matches-expectation run) t))
    (should (rbx-profile-run-complete run))
    (should (= (rbx-profile-run-time run) 5))
    (should (= (rbx-profile-run-time-limit run) 100))))

(ert-deftest rbx-parse-time-inspection-reads-a-last-run-fallback ()
  (let ((inspection (rbx-test--inspection rbx-time-inspect-fixture-last-run)))
    (should (eq (rbx-time-inspection-runs-source inspection) 'last-run))
    (should (rbx-time-inspect-row-runs (rbx-test--inspect-row inspection 2)))))

(ert-deftest rbx-parse-time-inspection-reads-staleness ()
  (let ((inspection (rbx-test--inspection
                     (string-replace "\"stale\":null" "\"stale\":\"solutions\""
                                     rbx-time-inspect-fixture-saved))))
    (should (eq (rbx-time-inspection-stale inspection) 'solutions))))

(ert-deftest rbx-parse-time-inspection-rejects-another-version ()
  (should-not (rbx-test--inspection
               (string-replace "\"version\":1," "\"version\":2,"
                               rbx-time-inspect-fixture-saved)))
  (should-not (rbx-test--inspection "{\"profile\":\"local\"}"))
  (should-not (rbx-parse-time-inspection nil))
  (should-not (rbx-parse-time-inspection '(1 2 3))))

(ert-deftest rbx-parse-time-inspection-keeps-rbx-errors ()
  (let ((inspection
         (rbx-test--inspection
          (concat "{\"version\":1,\"profile\":\"local\",\"path\":\".limits/local.yml\","
                  "\"errors\":[\"A limits profile must be a YAML mapping.\"]}"))))
    (should (equal (rbx-time-inspection-errors inspection)
                   '("A limits profile must be a YAML mapping.")))
    (should-not (rbx-time-inspection-rows inspection))))

(ert-deftest rbx-parse-time-inspection-tolerates-missing-fields ()
  (let ((inspection
         (rbx-test--inspection
          (concat "{\"version\":1,\"rows\":[{\"key\":\"base\",\"report\":null,"
                  "\"timeLimit\":null,\"solutions\":[{\"status\":\"ok\"},"
                  "{\"path\":\"a.cpp\",\"status\":\"brand-new\"}]},"
                  "{\"key\":\"x\"}, 3]}"))))
    (should (eq (rbx-time-inspection-runs-source inspection) 'last-run))
    (should-not (rbx-time-inspection-effective inspection))
    (should-not (rbx-time-inspection-last-run inspection))
    (let ((rows (rbx-time-inspection-rows inspection)))
      (should (= (length rows) 1))
      (let ((base (car rows)))
        (should-not (rbx-time-inspect-row-group base))
        (should-not (rbx-time-inspect-row-check base))
        (should (equal (mapcar #'rbx-time-solution-check-status
                               (rbx-time-inspect-row-solutions base))
                       '(brand-new)))))))

(provide 'rbx-model-test)
;;; rbx-model-test.el ends here
