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
        (let ((loads 0)
              (loader (symbol-function 'rbx-load-evaluation)))
          (cl-letf (((symbol-function 'rbx-load-evaluation)
                     (lambda (&rest arguments)
                       (cl-incf loads)
                       (apply loader arguments))))
            (rbx-refresh)
            (should (= loads 0))
            (let ((text (buffer-substring-no-properties
                         (point-min) (point-max))))
              (should (string-match-p
                       "✗.*wa\\.cpp.*declared WA.*got AC" text))
              (should (string-match-p "UNEXPECTED_VERDICTS" text))
              (should-not (string-match-p "000.*AC.*10 ms.*2 KiB" text)))
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
                                          position 'font-lock-face)))))
            (goto-char (point-min))
            (re-search-forward "^  ✗  main")
            (magit-section-show (magit-current-section))
            (should (= loads 1))
            (should (string-match-p
                     "000.*AC.*10 ms.*2 KiB"
                     (buffer-substring-no-properties
                      (point-min) (point-max))))))))))

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

(ert-deftest rbx-contest-hex-color-normalizes-short-hex ()
  (should (equal (rbx--contest-hex-color
                  (rbx-contest-problem-create :short-name "A" :color "#abc"))
                 "#aabbcc")))

(ert-deftest rbx-contest-hex-color-keeps-long-hex-verbatim ()
  (should (equal (rbx--contest-hex-color
                  (rbx-contest-problem-create :short-name "A" :color "#123456"))
                 "#123456")))

(ert-deftest rbx-contest-hex-color-prefers-declared-color-over-colorname ()
  (should (equal (rbx--contest-hex-color
                  (rbx-contest-problem-create
                   :short-name "A" :color "#111111" :color-name "Ignored"))
                 "#111111")))

(ert-deftest rbx-contest-hex-color-nil-without-a-color ()
  (should-not
   (rbx--contest-hex-color (rbx-contest-problem-create :short-name "A"))))

(ert-deftest rbx-contest-label-colors-short-name-when-known ()
  (let* ((problem (rbx-contest-problem-create :short-name "A"
                                              :color "#112233"))
         (label (rbx--contest-label problem)))
    (should (equal (substring-no-properties label) "A"))
    (should (equal (get-text-property 0 'font-lock-face label)
                   '(:foreground "#112233")))))

(ert-deftest rbx-contest-label-plain-without-a-color ()
  (let* ((problem (rbx-contest-problem-create :short-name "B"))
         (label (rbx--contest-label problem)))
    (should (equal label "B"))
    (should-not (get-text-property 0 'font-lock-face label))))

(ert-deftest rbx-contest-short-name-collides-p-detects-cross-contest-letters ()
  (let ((a (rbx-contest-membership-create
            :root "/contests/div1/"
            :contest (rbx-contest-create :name "Div 1")
            :problem (rbx-contest-problem-create :short-name "A")))
        (b (rbx-contest-membership-create
            :root "/contests/div2/"
            :contest (rbx-contest-create :name "Div 2")
            :problem (rbx-contest-problem-create :short-name "A"))))
    (should (rbx--contest-short-name-collides-p (list a b) a))
    (should-not (rbx--contest-short-name-collides-p (list a) a))
    (should-not (rbx--contest-short-name-collides-p (list a b) nil))))

(ert-deftest rbx-package-label-uses-relative-path-outside-a-contest ()
  (rbx-test-with-directory root
    (let ((package (rbx-package-create
                    :root (file-name-as-directory (expand-file-name "A" root))
                    :build-dir "build")))
      (should (equal (substring-no-properties
                      (rbx--package-label package root nil nil))
                     "A/")))))

(ert-deftest rbx-package-label-shows-colored-letter-inside-a-contest ()
  (rbx-test-with-directory root
    (let* ((package (rbx-package-create
                     :root (file-name-as-directory (expand-file-name "A" root))
                     :build-dir "build"))
           (membership (rbx-contest-membership-create
                        :root root
                        :contest (rbx-contest-create :name "Finals")
                        :problem (rbx-contest-problem-create
                                  :short-name "A" :color "#ff0000")))
           (label (rbx--package-label package root membership nil)))
      (should (equal (substring-no-properties label) "A  A"))
      (should (equal (get-text-property 0 'font-lock-face label)
                     '(:foreground "#ff0000"))))))

(ert-deftest rbx-package-label-qualifies-colliding-letters-with-contest-name ()
  (rbx-test-with-directory root
    (let* ((package (rbx-package-create
                     :root (file-name-as-directory
                            (expand-file-name "div1/A" root))
                     :build-dir "build"))
           (membership (rbx-contest-membership-create
                        :root (expand-file-name "div1" root)
                        :contest (rbx-contest-create :name "Div 1")
                        :problem (rbx-contest-problem-create
                                  :short-name "A"))))
      (should (equal (substring-no-properties
                      (rbx--package-label package root membership t))
                     "Div 1 · A  A")))))

(ert-deftest rbx-package-heading-label-falls-back-outside-a-contest ()
  (rbx-test-with-directory root
    (let ((package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build")))
      (cl-letf (((symbol-function 'rbx-package-contest-membership)
                 (lambda (_package) nil)))
        (should (equal (rbx--package-heading-label package "fallback")
                       "fallback"))))))

(ert-deftest rbx-package-heading-label-shows-letter-inside-a-contest ()
  (rbx-test-with-directory root
    (let* ((package-root (expand-file-name "A" root))
           (package (progn
                      (make-directory package-root t)
                      (rbx-package-create
                       :root (file-name-as-directory package-root)
                       :build-dir "build")))
           (membership (rbx-contest-membership-create
                        :root root
                        :contest (rbx-contest-create :name "Finals")
                        :problem (rbx-contest-problem-create
                                  :short-name "A"))))
      (cl-letf (((symbol-function 'rbx-package-contest-membership)
                 (lambda (_package) membership)))
        (should (equal (substring-no-properties
                        (rbx--package-heading-label package "fallback"))
                       "A · A"))))))

(ert-deftest rbx-render-contest-shows-one-block-per-variant ()
  (rbx-test-with-directory root
    (let* ((canonical (rbx-contest-create
                       :name "Finals" :variant-id nil
                       :problems (list (rbx-contest-problem-create
                                        :short-name "A" :color "#ff0000"))))
           (div1 (rbx-contest-create
                 :name "Division 1" :variant-id "div1"
                 :problems (list (rbx-contest-problem-create
                                  :short-name "B")))))
      (cl-letf (((symbol-function 'rbx-load-contest-variants)
                (lambda (_root) (list canonical div1))))
        (with-temp-buffer
          (rbx-view-mode)
          (setq-local rbx--contest-root root)
          (setq-local rbx--view 'contest)
          (rbx-refresh)
          (let ((text (buffer-substring-no-properties (point-min) (point-max))))
            (should (string-match-p "Canonical" text))
            (should (string-match-p "div1" text))
            (should (string-match-p "A" text))
            (should (string-match-p "B" text))))))))

(ert-deftest rbx-render-contest-without-any-manifest ()
  (rbx-test-with-directory root
    (cl-letf (((symbol-function 'rbx-load-contest-variants)
              (lambda (_root) nil)))
      (with-temp-buffer
        (rbx-view-mode)
        (setq-local rbx--contest-root root)
        (setq-local rbx--view 'contest)
        (rbx-refresh)
        (should (string-match-p
                "No contest.rbx.yml"
                (buffer-substring-no-properties (point-min) (point-max))))))))

(ert-deftest rbx-open-contest-problem-opens-run-view-for-resolved-path ()
  (rbx-test-with-directory root
    (let ((package-root (expand-file-name "A" root)))
      (rbx-test-write root "A/problem.rbx.yml" "name: Alpha\n")
      (let (opened)
        (cl-letf (((symbol-function 'rbx-run-view)
                  (lambda (package) (setq opened package))))
          (rbx-open-contest-problem
           (list :kind 'contest-problem :package-path package-root))
          (should opened)
          (should (equal (rbx-package-root opened)
                        (file-name-as-directory package-root))))))))

(ert-deftest rbx-open-contest-problem-errors-without-a-package ()
  (rbx-test-with-directory root
    (should-error
     (rbx-open-contest-problem
      (list :kind 'contest-problem
           :package-path (expand-file-name "missing" root)))
     :type 'user-error)))

(ert-deftest rbx-contest-view-errors-without-a-contest-manifest ()
  (rbx-test-with-directory root
    (cl-letf (((symbol-function 'rbx-find-contest-root)
              (lambda (&optional _directory) nil)))
      (let ((default-directory root))
        (should-error (rbx-contest-view) :type 'user-error)))))

(ert-deftest rbx-most-recently-touched-picks-latest-skeleton ()
  (rbx-test-with-directory root
    (let* ((root-a (expand-file-name "A" root))
           (root-b (expand-file-name "B" root))
           (package-a (progn (make-directory root-a t)
                             (rbx-package-create
                              :root (file-name-as-directory root-a)
                              :build-dir "build")))
           (package-b (progn (make-directory root-b t)
                             (rbx-package-create
                              :root (file-name-as-directory root-b)
                              :build-dir "build"))))
      (rbx-test-write root "A/.rbx/runs/skeleton.yml" "solutions: []\n")
      (rbx-test-write root "B/.rbx/runs/skeleton.yml" "solutions: []\n")
      (set-file-times (rbx-skeleton-path package-a)
                      (time-subtract (current-time) 10))
      (should (equal (rbx--most-recently-touched (list package-a package-b))
                     package-b))
      (should-not (rbx--most-recently-touched nil)))))

(ert-deftest rbx-toggle-contest-follow-retargets-to-latest-activity ()
  (rbx-test-with-directory root
    (let* ((root-a (expand-file-name "A" root))
           (root-b (expand-file-name "B" root)))
      (rbx-test-write root "A/problem.rbx.yml" "name: Alpha\n")
      (rbx-test-write root "B/problem.rbx.yml" "name: Beta\n")
      (rbx-test-write root "A/.rbx/runs/skeleton.yml" "solutions: []\n")
      (rbx-test-write root "B/.rbx/runs/skeleton.yml" "solutions: []\n")
      (set-file-times (expand-file-name "A/.rbx/runs/skeleton.yml" root)
                      (time-subtract (current-time) 10))
      (let* ((package-a (rbx-find-package root-a))
             (package-b (rbx-find-package root-b))
             (problem-a (rbx-contest-problem-create :short-name "A" :path "A"))
             (problem-b (rbx-contest-problem-create :short-name "B" :path "B"))
             (contest (rbx-contest-create :problems (list problem-a problem-b)))
             watch-args watch-callback)
        (cl-letf (((symbol-function 'rbx-package-contest-membership)
                  (lambda (package)
                    (rbx-contest-membership-create
                     :root root :contest contest
                     :problem (if (rbx--same-file-p (rbx-package-root package)
                                                    root-a)
                                 problem-a problem-b))))
                 ((symbol-function 'rbx-watch-contest)
                  (lambda (packages callback)
                    (setq watch-args packages watch-callback callback)
                    (list 'stub-watcher)))
                 ((symbol-function 'rbx-stop-watcher) #'ignore)
                 ((symbol-function 'rbx--start-buffer-watcher) #'ignore))
          (with-temp-buffer
            (rbx-view-mode)
            (setq-local rbx--package package-a)
            (setq-local rbx--view 'run)
            (rbx-refresh)
            (should-not (string-match-p
                        "following"
                        (buffer-substring-no-properties
                         (point-min) (point-max))))
            (rbx-toggle-contest-follow)
            (should (equal watch-args (list package-a package-b)))
            (should (string-match-p
                    "following"
                    (buffer-substring-no-properties
                     (point-min) (point-max))))
            (funcall watch-callback package-b)
            (should (equal rbx--package package-b))
            (rbx-toggle-contest-follow)
            (should-not rbx--contest-watchers)
            (should-not (string-match-p
                        "following"
                        (buffer-substring-no-properties
                         (point-min) (point-max))))))))))

(ert-deftest rbx-toggle-contest-follow-errors-outside-a-contest ()
  (rbx-test-with-directory root
    (rbx-test-write root "problem.rbx.yml" "name: Demo\n")
    (let ((package (rbx-find-package root)))
      (cl-letf (((symbol-function 'rbx-package-contest-membership)
                (lambda (_package) nil)))
        (with-temp-buffer
          (rbx-view-mode)
          (setq-local rbx--package package)
          (setq-local rbx--view 'run)
          (should-error (rbx-toggle-contest-follow) :type 'user-error))))))

(ert-deftest rbx-context-testcase-entry-unwraps-testset-testcase ()
  (let* ((entry (rbx-testcase-create :group "main" :index 0))
         (wrapped (rbx-testset-testcase-create
                  :entry entry :stem "000" :test nil)))
    (should (eq (rbx--context-testcase-entry
                (list :kind 'testset-testcase :testcase wrapped))
               entry))
    (should (eq (rbx--context-testcase-entry
                (list :kind 'run-testcase :testcase entry))
               entry))))

(ert-deftest rbx-testcase-info-lines-includes-origin-and-full-message-for-run ()
  (let* ((entry (rbx-testcase-create
                :group "main" :index 0
                :generator-name "gen" :generator-args "5 3"))
         (evaluation (rbx-evaluation-create
                     :outcome "wrong-answer"
                     :message "expected 5 but produced 6"
                     :time 0.01 :memory 2048))
         (context (list :kind 'run-testcase :testcase entry
                       :evaluation evaluation))
         (result (rbx--testcase-info-lines context))
         (lines (car result)))
    (should (member "Origin: gen 5 3" lines))
    (should (cl-some (lambda (line) (string-match-p "Verdict: WA" line))
                     lines))
    (should (equal (cdr result) "expected 5 but produced 6"))))

(ert-deftest rbx-testcase-info-lines-handles-run-testcase-without-evaluation ()
  (let* ((entry (rbx-testcase-create :group "main" :index 0))
         (context (list :kind 'run-testcase :testcase entry :evaluation nil))
         (result (rbx--testcase-info-lines context)))
    (should (member "No evaluation yet." (car result)))
    (should-not (cdr result))))

(ert-deftest rbx-testcase-info-lines-includes-validator-status-for-testset ()
  (let* ((entry (rbx-testcase-create :group "main" :index 0
                                     :copied-from "samples/1.in"))
         (validation (rbx-testset-validation-result-create
                     :ok nil :validator "validator.cpp"
                     :message "n is out of bounds"))
         (test (rbx-testset-test-create :group "main" :index 0
                                        :validation validation))
         (testcase (rbx-testset-testcase-create
                   :entry entry :stem "000" :test test))
         (context (list :kind 'testset-testcase :testcase testcase))
         (result (rbx--testcase-info-lines context)))
    (should (member "Origin: copied from samples/1.in" (car result)))
    (should (member "Validator: validator.cpp" (car result)))
    (should (member "Validation: failed" (car result)))
    (should (equal (cdr result) "n is out of bounds"))))

(ert-deftest rbx-show-testcase-info-pops-a-buffer-with-full-message ()
  (let* ((entry (rbx-testcase-create :group "main" :index 0))
         (evaluation (rbx-evaluation-create
                     :outcome "accepted" :message "ok, well done"))
         (context (list :kind 'run-testcase :testcase entry
                       :evaluation evaluation)))
    (unwind-protect
        (progn
          (rbx-show-testcase-info context)
          (with-current-buffer (get-buffer "*rbx testcase info*")
            (let ((text (buffer-string)))
              (should (string-match-p "^Testcase: 000$" text))
              (should (string-match-p "^Origin: generated$" text))
              (should (string-match-p "ok, well done" text)))))
      (when (get-buffer "*rbx testcase info*")
        (kill-buffer "*rbx testcase info*")))))

(ert-deftest rbx-visit-testcase-source-jumps-to-generator-script-line ()
  (rbx-test-with-directory root
    (let* ((script (rbx-test-write root "gen/main.rbx"
                                   "line one\nline two\nline three\n"))
          (package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build"))
          (entry (rbx-testcase-create
                 :group "main" :index 0
                 :generator-script "gen/main.rbx"
                 :generator-script-line 2))
          (context (list :kind 'run-testcase :package package :testcase entry))
          (buffer (rbx-visit-testcase-source context)))
      (unwind-protect
          (with-current-buffer buffer
            (should (equal (buffer-file-name) script))
            (should (= (line-number-at-pos) 2)))
        (kill-buffer buffer)))))

(ert-deftest rbx-visit-testcase-source-opens-copied-from-without-a-line ()
  (rbx-test-with-directory root
    (let* ((source (rbx-test-write root "samples/1.in" "3\n1 2 3\n"))
          (package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build"))
          (entry (rbx-testcase-create :group "main" :index 0
                                     :copied-from "samples/1.in"))
          (context (list :kind 'run-testcase :package package :testcase entry))
          (buffer (rbx-visit-testcase-source context)))
      (unwind-protect
          (with-current-buffer buffer
            (should (equal (buffer-file-name) source)))
        (kill-buffer buffer)))))

(ert-deftest rbx-visit-testcase-source-errors-without-a-recorded-location ()
  (let ((entry (rbx-testcase-create :group "main" :index 0)))
    (should-error
     (rbx-visit-testcase-source (list :kind 'run-testcase :testcase entry))
     :type 'user-error)))

(ert-deftest rbx-open-validator-opens-the-recorded-validator ()
  (rbx-test-with-directory root
    (let* ((source (rbx-test-write root "validator.cpp" "int main() {}\n"))
          (package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build"))
          (validation (rbx-testset-validation-result-create
                      :ok t :validator "validator.cpp"))
          (test (rbx-testset-test-create :group "main" :index 0
                                        :validation validation))
          (entry (rbx-testcase-create :group "main" :index 0))
          (testcase (rbx-testset-testcase-create :entry entry :stem "000"
                                                 :test test))
          (context (list :kind 'testset-testcase :package package
                        :testcase testcase))
          (buffer (rbx-open-validator context)))
      (unwind-protect
          (with-current-buffer buffer
            (should (equal (buffer-file-name) source)))
        (kill-buffer buffer)))))

(ert-deftest rbx-open-validator-errors-without-a-validator ()
  (let* ((test (rbx-testset-test-create :group "main" :index 0))
        (entry (rbx-testcase-create :group "main" :index 0))
        (testcase (rbx-testset-testcase-create :entry entry :stem "000"
                                              :test test)))
    (should-error
     (rbx-open-validator (list :kind 'testset-testcase :testcase testcase))
     :type 'user-error)))

(ert-deftest rbx-render-testset-shows-aggregate-statistics ()
  (rbx-test-with-directory root
    (rbx-test-write root "problem.rbx.yml" "name: Demo\n")
    (rbx-test-write
     root "build/testset.yml"
     (concat
      "version: 1\ntask_type: BATCH\n"
      "groups:\n  - name: samples\n  - name: main\n"
      "entries:\n"
      "  - group_entry: {group: samples, index: 0}\n"
      "    metadata: {copied_to: {inputPath: build/tests/samples/000.in}}\n"
      "  - group_entry: {group: main, index: 0}\n"
      "    metadata: {generator_call: {name: gen, args: '5 3'}}\n"
      "tests:\n"
      "  - group: samples\n    index: 0\n"
      "    input_size: 10\n    output_size: 2\n"
      "  - group: main\n    index: 0\n"
      "    input_size: 90\n    output_size: 8\n"))
    (let ((package (rbx-package-create
                   :root (file-name-as-directory root)
                   :build-dir "build")))
      (with-temp-buffer
        (rbx-view-mode)
        (setq-local rbx--package package)
        (setq-local rbx--view 'testset)
        (rbx-refresh)
        (let ((text (buffer-substring-no-properties (point-min) (point-max))))
          (should (string-match-p "Testset statistics.*2 testcases" text))
          (should (string-match-p "samples.*in 10 B.*out 2 B" text))
          (should (string-match-p "main.*in 90 B.*out 8 B" text)))))))

(ert-deftest rbx-insert-testset-statistics-renders-bars-and-totals ()
  (let* ((entry-a (rbx-testcase-create :group "samples" :index 0))
         (entry-b (rbx-testcase-create :group "main" :index 0))
         (test-a (rbx-testset-test-create :group "samples" :index 0
                                          :input-size 10 :output-size 2))
         (test-b (rbx-testset-test-create :group "main" :index 0
                                          :input-size 90 :output-size 8))
         (testset (rbx-testset-create
                  :groups (list (rbx-testset-group-create :name "samples")
                               (rbx-testset-group-create :name "main"))
                  :entries (list entry-a entry-b)
                  :tests (list test-a test-b))))
    (with-temp-buffer
      (rbx-view-mode)
      (let ((inhibit-read-only t))
        (magit-insert-section (rbx-root-section nil)
          (rbx--insert-testset-statistics testset)))
      (let ((text (buffer-substring-no-properties (point-min) (point-max))))
        (should (string-match-p "Testset statistics · 2 testcases · 110 B"
                               text))
        (should (string-match-p "samples.*in 10 B.*out 2 B" text))
        (should (string-match-p "main.*in 90 B.*out 8 B" text))))))

(ert-deftest rbx-insert-testset-statistics-omits-section-without-testcases ()
  (with-temp-buffer
    (rbx-view-mode)
    (let ((inhibit-read-only t))
      (magit-insert-section (rbx-root-section nil)
        (rbx--insert-testset-statistics (rbx-testset-create))))
    (should (string-empty-p (buffer-substring-no-properties
                            (point-min) (point-max))))))

(ert-deftest rbx-open-visualization-opens-input-image-file ()
  (rbx-test-with-directory root
    (let* ((image (rbx-test-write root "visual/000.png" "fake-png-bytes"))
          (package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build"))
          (visualization (rbx-testset-visualization-create
                         :input "visual/000.png"))
          (test (rbx-testset-test-create :group "main" :index 0
                                        :visualization visualization))
          (entry (rbx-testcase-create :group "main" :index 0))
          (testcase (rbx-testset-testcase-create
                    :entry entry :stem "000" :test test))
          (context (list :kind 'testset-testcase :package package
                        :testcase testcase))
          (buffer (rbx-open-visualization context)))
      (unwind-protect
          (with-current-buffer buffer
            (should (equal (buffer-file-name) image)))
        (kill-buffer buffer)))))

(ert-deftest rbx-open-visualization-browses-html-visualization ()
  (rbx-test-with-directory root
    (let* ((html (rbx-test-write root "visual/000.html" "<html></html>"))
          (package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build"))
          (visualization (rbx-testset-visualization-create
                         :input "visual/000.html"))
          (test (rbx-testset-test-create :group "main" :index 0
                                        :visualization visualization))
          (entry (rbx-testcase-create :group "main" :index 0))
          (testcase (rbx-testset-testcase-create
                    :entry entry :stem "000" :test test))
          (context (list :kind 'testset-testcase :package package
                        :testcase testcase))
          browsed)
      (cl-letf (((symbol-function 'browse-url-of-file)
                (lambda (path) (setq browsed path))))
        (rbx-open-visualization context)
        (should (equal browsed html))))))

(ert-deftest rbx-open-visualization-errors-without-a-visualization ()
  (let* ((test (rbx-testset-test-create :group "main" :index 0))
        (entry (rbx-testcase-create :group "main" :index 0))
        (testcase (rbx-testset-testcase-create
                  :entry entry :stem "000" :test test)))
    (should-error
     (rbx-open-visualization (list :kind 'testset-testcase :testcase testcase))
     :type 'user-error)))

(ert-deftest rbx-open-answer-visualization-opens-output-image-file ()
  (rbx-test-with-directory root
    (let* ((image (rbx-test-write root "visual/000-answer.png" "fake-bytes"))
          (package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build"))
          (visualization (rbx-testset-visualization-create
                         :input "visual/000.png"
                         :output "visual/000-answer.png"))
          (test (rbx-testset-test-create :group "main" :index 0
                                        :visualization visualization))
          (entry (rbx-testcase-create :group "main" :index 0))
          (testcase (rbx-testset-testcase-create
                    :entry entry :stem "000" :test test))
          (context (list :kind 'testset-testcase :package package
                        :testcase testcase))
          (buffer (rbx-open-answer-visualization context)))
      (unwind-protect
          (with-current-buffer buffer
            (should (equal (buffer-file-name) image)))
        (kill-buffer buffer)))))

(ert-deftest rbx-open-answer-visualization-errors-without-an-answer ()
  (let* ((visualization (rbx-testset-visualization-create :input "visual/000.png"))
        (test (rbx-testset-test-create :group "main" :index 0
                                      :visualization visualization))
        (entry (rbx-testcase-create :group "main" :index 0))
        (testcase (rbx-testset-testcase-create
                  :entry entry :stem "000" :test test)))
    (should-error
     (rbx-open-answer-visualization
      (list :kind 'testset-testcase :testcase testcase))
     :type 'user-error)))

(ert-deftest rbx-open-visualization-opens-input-image-file-for-run-testcase ()
  (rbx-test-with-directory root
    (let* ((image (rbx-test-write root "visual/000.png" "fake-png-bytes")))
      (rbx-test-write
       root "build/testset.yml"
       (concat "version: 1\ntask_type: BATCH\n"
              "tests:\n- group: main\n  index: 0\n"
              "  visualization:\n    input: visual/000.png\n"))
      (let* ((package (rbx-package-create :root (file-name-as-directory root)
                                          :build-dir "build"))
            (context (list :kind 'run-testcase :package package
                          :testcase (rbx-testcase-create :group "main"
                                                         :index 0)))
            (buffer (rbx-open-visualization context)))
        (unwind-protect
            (with-current-buffer buffer
              (should (equal (buffer-file-name) image)))
          (kill-buffer buffer))))))

(ert-deftest rbx-open-answer-visualization-opens-output-image-file-for-run-testcase ()
  (rbx-test-with-directory root
    (let* ((image (rbx-test-write root "visual/000-answer.png" "fake-bytes")))
      (rbx-test-write
       root "build/testset.yml"
       (concat "version: 1\ntask_type: BATCH\n"
              "tests:\n- group: main\n  index: 0\n"
              "  visualization:\n    input: visual/000.png\n"
              "    output: visual/000-answer.png\n"))
      (let* ((package (rbx-package-create :root (file-name-as-directory root)
                                          :build-dir "build"))
            (context (list :kind 'run-testcase :package package
                          :testcase (rbx-testcase-create :group "main"
                                                         :index 0)))
            (buffer (rbx-open-answer-visualization context)))
        (unwind-protect
            (with-current-buffer buffer
              (should (equal (buffer-file-name) image)))
          (kill-buffer buffer))))))

(ert-deftest rbx-open-visualization-errors-for-run-testcase-without-a-testset ()
  (rbx-test-with-directory root
    (let* ((package (rbx-package-create :root (file-name-as-directory root)
                                        :build-dir "build"))
          (context (list :kind 'run-testcase :package package
                        :testcase (rbx-testcase-create :group "main"
                                                       :index 0))))
      (should-error (rbx-open-visualization context) :type 'user-error))))

(ert-deftest rbx-open-visualization-errors-for-run-testcase-with-no-visualization ()
  (rbx-test-with-directory root
    (rbx-test-write
     root "build/testset.yml"
     (concat "version: 1\ntask_type: BATCH\n"
            "tests:\n- group: main\n  index: 0\n"
            "  input_size: 4\n"))
    (let* ((package (rbx-package-create :root (file-name-as-directory root)
                                        :build-dir "build"))
          (context (list :kind 'run-testcase :package package
                        :testcase (rbx-testcase-create :group "main"
                                                       :index 0))))
      (should-error (rbx-open-visualization context) :type 'user-error))))

(ert-deftest rbx-open-answer-visualization-errors-for-run-testcase-without-an-answer ()
  (rbx-test-with-directory root
    (rbx-test-write
     root "build/testset.yml"
     (concat "version: 1\ntask_type: BATCH\n"
            "tests:\n- group: main\n  index: 0\n"
            "  visualization:\n    input: visual/000.png\n"))
    (let* ((package (rbx-package-create :root (file-name-as-directory root)
                                        :build-dir "build"))
          (context (list :kind 'run-testcase :package package
                        :testcase (rbx-testcase-create :group "main"
                                                       :index 0))))
      (should-error (rbx-open-answer-visualization context) :type 'user-error))))

(ert-deftest rbx-visualization-thumbnail-builds-an-image-spec-for-a-picture ()
  (rbx-test-with-directory root
    (let ((path (rbx-test-write root "visual/000.png" "fake-png-bytes")))
      (should (rbx--visualization-thumbnail path)))))

(ert-deftest rbx-visualization-thumbnail-nil-for-html ()
  (rbx-test-with-directory root
    (let ((path (rbx-test-write root "visual/000.html" "<html></html>")))
      (should-not (rbx--visualization-thumbnail path)))))

(ert-deftest rbx-visualization-thumbnail-nil-for-a-missing-file ()
  (rbx-test-with-directory root
    (should-not (rbx--visualization-thumbnail
                (expand-file-name "missing.png" root)))))

(ert-deftest rbx-insert-gallery-groups-shows-thumbnails-and-links-by-group ()
  (rbx-test-with-directory root
    (let* ((html-path (rbx-test-write root "visual/main-000.html"
                                      "<html></html>"))
          (entry-samples (rbx-testcase-create :group "samples" :index 0))
          (entry-main (rbx-testcase-create :group "main" :index 0))
          (entry-empty (rbx-testcase-create :group "empty" :index 0))
          (vis-samples (rbx-testset-visualization-create
                       :input "visual/samples-000.png"))
          (vis-main (rbx-testset-visualization-create
                    :input "visual/main-000.html"))
          (test-samples (rbx-testset-test-create :group "samples" :index 0
                                                 :visualization vis-samples))
          (test-main (rbx-testset-test-create :group "main" :index 0
                                              :visualization vis-main))
          (testset (rbx-testset-create
                   :groups (list (rbx-testset-group-create :name "samples")
                                (rbx-testset-group-create :name "main")
                                (rbx-testset-group-create :name "empty"))
                   :entries (list entry-samples entry-main entry-empty)
                   :tests (list test-samples test-main)))
          (package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build")))
      (rbx-test-write root "visual/samples-000.png" "fake-png-bytes")
      (with-temp-buffer
        (rbx-view-mode)
        (let ((inhibit-read-only t))
          (magit-insert-section (rbx-root-section nil)
            (rbx--insert-gallery-groups package testset)))
        (goto-char (point-min))
        (should (search-forward "samples" nil t))
        (should (search-forward "main" nil t))
        (should-not (save-excursion
                     (goto-char (point-min))
                     (search-forward "empty" nil t)))
        (goto-char (point-min))
        (re-search-forward "000")
        (should (get-text-property (match-beginning 0) 'display))
        (goto-char (point-min))
        (should (search-forward (file-name-nondirectory html-path) nil t))))))

(ert-deftest rbx-insert-gallery-groups-shows-placeholder-without-visualizations ()
  (let ((testset (rbx-testset-create
                  :groups (list (rbx-testset-group-create :name "main"))
                  :entries (list (rbx-testcase-create :group "main" :index 0))))
        (package (rbx-package-create :root "/tmp/" :build-dir "build")))
    (with-temp-buffer
      (rbx-view-mode)
      (let ((inhibit-read-only t))
        (magit-insert-section (rbx-root-section nil)
          (rbx--insert-gallery-groups package testset)))
      (should (string-match-p "No visualizations found"
                             (buffer-substring-no-properties
                              (point-min) (point-max)))))))

(ert-deftest rbx-open-gallery-visualization-opens-the-path-at-point ()
  (rbx-test-with-directory root
    (let* ((image (rbx-test-write root "visual/000.png" "fake"))
          (buffer (rbx-open-gallery-visualization
                  (list :kind 'gallery-visualization :path image))))
      (unwind-protect
          (with-current-buffer buffer
            (should (equal (buffer-file-name) image)))
        (kill-buffer buffer)))))

(ert-deftest rbx-open-gallery-visualization-errors-without-a-path ()
  (should-error
   (rbx-open-gallery-visualization (list :kind 'gallery-visualization))
   :type 'user-error))

(ert-deftest rbx-solution-fringe-spec-maps-states-to-bitmaps-and-faces ()
  (should (equal (rbx--solution-fringe-spec 'met)
                '(rbx-fringe-tick . rbx-match)))
  (should (equal (rbx--solution-fringe-spec 'missed)
                '(right-triangle . rbx-mismatch)))
  (should (equal (rbx--solution-fringe-spec 'warned)
                '(exclamation-mark . rbx-warning))))

(ert-deftest rbx-insert-solution-places-a-fringe-overlay-for-a-matched-solution ()
  (let* ((solution (rbx-solution-create :path "sols/ac.cpp"
                                        :expected-outcome "ACCEPTED" :index 0))
         (skeleton (rbx-skeleton-create :solutions (list solution) :entries nil
                                        :groups nil :compilation nil))
         (solution-report (rbx-solution-report-create
                           :path "sols/ac.cpp" :index 0
                           :expected-outcome "ACCEPTED" :outcome "accepted"
                           :status "OK" :matches-expectation t
                           :score 100 :max-score 100 :groups nil))
         (report (rbx-run-report-create :solutions (list solution-report)))
         (package (rbx-package-create :root "/tmp/" :build-dir "build")))
    (with-temp-buffer
      (rbx-view-mode)
      (let ((inhibit-read-only t))
        (rbx--clear-fringe-overlays)
        (rbx--insert-solution package skeleton report solution nil
                              (make-hash-table :test #'equal)))
      (should (= (length rbx--fringe-overlays) 1))
      (let* ((overlay (car rbx--fringe-overlays))
            (before (overlay-get overlay 'before-string))
            (display (get-text-property 0 'display before)))
        (should (equal display (list 'left-fringe 'rbx-fringe-tick
                                     'rbx-match)))))))

(ert-deftest rbx-insert-solution-skips-fringe-for-a-pending-solution ()
  (let* ((solution (rbx-solution-create :path "sols/ac.cpp"
                                        :expected-outcome "ACCEPTED" :index 0))
         (skeleton (rbx-skeleton-create :solutions (list solution) :entries nil
                                        :groups nil :compilation nil))
         (package (rbx-package-create :root "/tmp/" :build-dir "build")))
    (with-temp-buffer
      (rbx-view-mode)
      (let ((inhibit-read-only t))
        (rbx--clear-fringe-overlays)
        (rbx--insert-solution package skeleton nil solution nil
                              (make-hash-table :test #'equal)))
      (should-not rbx--fringe-overlays))))

(ert-deftest rbx-clear-fringe-overlays-removes-stale-overlays ()
  (with-temp-buffer
    (rbx-view-mode)
    (let ((inhibit-read-only t))
      (insert "line\n")
      (rbx--insert-solution-fringe 'met)
      (should (= (length rbx--fringe-overlays) 1))
      (rbx--clear-fringe-overlays)
      (should-not rbx--fringe-overlays)
      (should-not (overlays-in (point-min) (point-max))))))

(provide 'rbx-ui-test)
;;; rbx-ui-test.el ends here
