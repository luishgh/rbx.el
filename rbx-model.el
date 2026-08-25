;;; rbx-model.el --- Tolerant readers for rbx artifacts -*- lexical-binding: t; -*-

;; Copyright (C) 2026 rbx-for-emacs contributors

;; Author: rbx-for-emacs contributors
;; Maintainer: rbx-for-emacs contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (yaml "1.2.0"))
;; Keywords: tools, languages
;; URL: https://github.com/rsalesc/rbx

;;; Commentary:

;; Typed, tolerant readers for the YAML artifacts published by rbx.  These
;; structures mirror fields, never verdict decisions: aggregate outcomes,
;; scores, and expectation matches are accepted only from report.yml.

;;; Code:

(require 'cl-lib)
(require 'rbx-core)

(cl-defstruct (rbx-testcase (:constructor rbx-testcase-create))
  "A GenerationTestcaseEntry embedded in an rbx artifact."
  group index subgroup input-path output-path generator-name generator-args
  copied-from generator-script generator-script-line)

(cl-defstruct (rbx-solution (:constructor rbx-solution-create))
  "A solution entry in skeleton.yml."
  path expected-outcome index)

(cl-defstruct (rbx-group (:constructor rbx-group-create))
  "A testcase group entry in skeleton.yml."
  name score)

(cl-defstruct (rbx-warning (:constructor rbx-warning-create))
  "One parsed compiler warning."
  file line flag message)

(cl-defstruct (rbx-compilation (:constructor rbx-compilation-create))
  "Compilation findings for one declared solution."
  path expected-outcome status log warnings reason)

(cl-defstruct (rbx-skeleton (:constructor rbx-skeleton-create))
  "The structural artifact written when an rbx run starts."
  solutions entries groups compilation sanitized only-accepted)

(cl-defstruct (rbx-evaluation (:constructor rbx-evaluation-create))
  "Per-testcase facts from an evaluation artifact."
  outcome message time memory no-tle-outcome sanitizer-warnings)

(cl-defstruct (rbx-group-report (:constructor rbx-group-report-create))
  "One group aggregate from report.yml."
  name outcome expected-outcome matches-expectation score max-score max-time
  max-memory run-under-double-tl double-tl-verdicts sanitizer-warnings
  unexpected-no-tle-verdicts)

(cl-defstruct (rbx-solution-report (:constructor rbx-solution-report-create))
  "One solution aggregate from report.yml."
  path index expected-outcome outcome status matches-expectation
  pooled-matches-expectation score max-score max-time max-memory failed-groups
  expected-score run-under-double-tl double-tl-verdicts sanitizer-warnings
  groups)

(cl-defstruct (rbx-run-report (:constructor rbx-run-report-create))
  "Aggregate decisions published by rbx for a run."
  solutions)

(cl-defstruct (rbx-testset-group (:constructor rbx-testset-group-create))
  "A group declaration from testset.yml."
  name score deps subgroups vars)

(cl-defstruct (rbx-testset-validation-result
               (:constructor rbx-testset-validation-result-create))
  "The validator result for one built testcase."
  ok validator message)

(cl-defstruct (rbx-testset-visualization
               (:constructor rbx-testset-visualization-create))
  "Visualization paths for a built testcase."
  input output)

(cl-defstruct (rbx-testset-test (:constructor rbx-testset-test-create))
  "Build-time metadata attached to a testcase."
  group index validation visualization input-size output-size)

(cl-defstruct (rbx-variable-bounds (:constructor rbx-variable-bounds-create))
  "Whether both declared bounds of one variable were hit."
  min-hit max-hit)

(cl-defstruct (rbx-group-bounds (:constructor rbx-group-bounds-create))
  "Constraint coverage for one testcase group."
  group validator bounds)

(cl-defstruct (rbx-testset (:constructor rbx-testset-create))
  "The manifest published after a successful rbx build."
  version task-type groups entries tests validation)

(cl-defstruct (rbx-testset-testcase
               (:constructor rbx-testset-testcase-create))
  "A testset entry joined with its build-time metadata."
  entry stem test)

(defconst rbx--model-missing (make-symbol "rbx-missing")
  "Sentinel used to distinguish a missing field from YAML false or null.")

(defun rbx--model-field (root &rest keys)
  "Read string KEYS below ROOT, preserving missing-field information."
  (let ((current root))
    (catch 'missing
      (dolist (key keys current)
        (setq current (rbx--wire-get current key rbx--model-missing))
        (when (eq current rbx--model-missing)
          (throw 'missing rbx--model-missing))))))

(defun rbx--model-string (root &rest keys)
  "Read a string below ROOT at KEYS."
  (rbx--wire-string (apply #'rbx--model-field root keys)))

(defun rbx--model-number (root &rest keys)
  "Read a number below ROOT at KEYS."
  (rbx--wire-number (apply #'rbx--model-field root keys)))

(defun rbx--model-boolean (root keys default)
  "Read a boolean below ROOT at KEYS, using DEFAULT if absent or invalid."
  (let ((value (apply #'rbx--model-field root keys)))
    (cond
     ((eq value rbx--model-missing) default)
     ((eq value t) t)
     ((or (null value) (eq value :false)) nil)
     (t default))))

(defun rbx--model-strings (root &rest keys)
  "Read a list of strings below ROOT at KEYS, dropping other values."
  (delq nil
        (mapcar #'rbx--wire-string
                (rbx--wire-sequence
                 (apply #'rbx--model-field root keys)))))

(defun rbx-testcase-stem (testcase)
  "Return the real on-disk artifact stem for TESTCASE.

The generated input basename is authoritative.  A padded index is only the
fallback used for artifacts old enough not to record that path."
  (if-let ((path (rbx-testcase-input-path testcase)))
      (file-name-base path)
    (format "%03d" (rbx-testcase-index testcase))))

(defun rbx-parse-testcase-entry (raw)
  "Parse RAW as a GenerationTestcaseEntry, or return nil."
  (let ((group (rbx--model-string raw "group_entry" "group"))
        (index (rbx--model-number raw "group_entry" "index")))
    (when (and group index)
      (rbx-testcase-create
       :group group
       :index index
       :subgroup (rbx--model-string raw "subgroup_entry" "group")
       :input-path (rbx--model-string raw "metadata" "copied_to" "inputPath")
       :output-path (rbx--model-string raw "metadata" "copied_to" "outputPath")
       :generator-name
       (rbx--model-string raw "metadata" "generator_call" "name")
       :generator-args
       (rbx--model-string raw "metadata" "generator_call" "args")
       :copied-from
       (rbx--model-string raw "metadata" "copied_from" "inputPath")
       :generator-script
       (rbx--model-string raw "metadata" "generator_script" "path")
       :generator-script-line
       (rbx--model-number raw "metadata" "generator_script" "line")))))

(defun rbx--parse-warning (raw)
  "Parse RAW as a compilation warning, or return nil."
  (let ((file (rbx--model-string raw "file"))
        (line (rbx--model-number raw "line"))
        (message (rbx--model-string raw "msg")))
    (when (and file line message)
      (rbx-warning-create :file file
                          :line line
                          :flag (rbx--model-string raw "flag")
                          :message message))))

(defun rbx--parse-compilation (raw)
  "Parse RAW as compilation findings, or return nil."
  (let ((path (rbx--model-string raw "path"))
        (status (rbx--model-string raw "status"))
        (log (rbx--model-string raw "log")))
    (when (and path log (member status '("WARNINGS" "FAILED")))
      (rbx-compilation-create
       :path path
       :expected-outcome (rbx--model-string raw "outcome")
       :status status
       :log log
       :warnings (delq nil
                       (mapcar #'rbx--parse-warning
                               (rbx--wire-sequence
                                (rbx--model-field raw "warnings"))))
       :reason (rbx--model-string raw "reason")))))

(defun rbx-parse-skeleton (raw)
  "Parse RAW as a SolutionReportSkeleton, or return nil."
  (when (rbx--wire-mapping-p raw)
    (let (solutions entries groups compilation)
      (cl-loop for solution in (rbx--wire-sequence
                                (rbx--model-field raw "solutions"))
               for index from 0
               for path = (rbx--model-string solution "path")
               when path
               do (push (rbx-solution-create
                         :path path
                         :expected-outcome
                         (rbx--model-string solution "outcome")
                         :index index)
                        solutions))
      (dolist (entry (rbx--wire-sequence (rbx--model-field raw "entries")))
        (when-let ((parsed (rbx-parse-testcase-entry entry)))
          (push parsed entries)))
      (dolist (group (rbx--wire-sequence (rbx--model-field raw "groups")))
        (when-let ((name (rbx--model-string group "name")))
          (push (rbx-group-create :name name
                                  :score (rbx--model-number group "score"))
                groups)))
      (dolist (finding (rbx--wire-sequence
                        (rbx--model-field raw "compilation")))
        (when-let ((parsed (rbx--parse-compilation finding)))
          (push parsed compilation)))
      (rbx-skeleton-create
       :solutions (nreverse solutions)
       :entries (nreverse entries)
       :groups (nreverse groups)
       :compilation (nreverse compilation)
       :sanitized (rbx--model-boolean raw '("sanitized") nil)
       :only-accepted (rbx--model-boolean raw '("only_accepted") nil)))))

(defun rbx-parse-evaluation (raw)
  "Parse RAW as an Evaluation, or return nil."
  (when (rbx--wire-mapping-p raw)
    (rbx-evaluation-create
     :outcome (rbx--model-string raw "result" "outcome")
     :message (rbx--model-string raw "result" "message")
     :time (rbx--model-number raw "log" "time")
     :memory (rbx--model-number raw "log" "memory")
     :no-tle-outcome (rbx--model-string raw "result" "no_tle_outcome")
     :sanitizer-warnings
     (rbx--model-boolean raw '("result" "sanitizer_warnings") nil))))

(defun rbx--parse-group-report (raw)
  "Parse RAW as a group aggregate, or return nil."
  (when-let ((name (rbx--model-string raw "name")))
    (rbx-group-report-create
     :name name
     :outcome (rbx--model-string raw "outcome")
     :expected-outcome (rbx--model-string raw "expectedOutcome")
     :matches-expectation
     (rbx--model-boolean raw '("matchesExpectation") t)
     :score (or (rbx--model-number raw "score") 0)
     :max-score (or (rbx--model-number raw "maxScore") 0)
     :max-time (rbx--model-number raw "maxTime")
     :max-memory (rbx--model-number raw "maxMemory")
     :run-under-double-tl
     (rbx--model-boolean raw '("runUnderDoubleTl") nil)
     :double-tl-verdicts (rbx--model-strings raw "doubleTlVerdicts")
     :sanitizer-warnings
     (rbx--model-boolean raw '("sanitizerWarnings") nil)
     :unexpected-no-tle-verdicts
     (rbx--model-strings raw "unexpectedNoTleVerdicts"))))

(defun rbx--score-range (raw)
  "Parse RAW as an exact two-number score range."
  (let ((values (rbx--wire-sequence raw)))
    (when (and (= (length values) 2)
               (cl-every #'numberp values))
      values)))

(defun rbx--parse-solution-report (raw)
  "Parse RAW as a solution aggregate, or return nil."
  (let ((path (rbx--model-string raw "path"))
        (index (rbx--model-number raw "index")))
    (when (and path index)
      (rbx-solution-report-create
       :path path
       :index index
       :expected-outcome (rbx--model-string raw "expectedOutcome")
       :outcome (rbx--model-string raw "outcome")
       :status (or (rbx--model-string raw "status") "OK")
       :matches-expectation
       (rbx--model-boolean raw '("matchesExpectation") t)
       :pooled-matches-expectation
       (let ((value (rbx--model-field raw "pooledMatchesExpectation")))
         (unless (eq value rbx--model-missing)
           (rbx--model-boolean raw '("pooledMatchesExpectation") nil)))
       :score (or (rbx--model-number raw "score") 0)
       :max-score (or (rbx--model-number raw "maxScore") 0)
       :max-time (rbx--model-number raw "maxTime")
       :max-memory (rbx--model-number raw "maxMemory")
       :failed-groups (rbx--model-strings raw "failedGroups")
       :expected-score
       (rbx--score-range (rbx--model-field raw "expectedScore"))
       :run-under-double-tl
       (rbx--model-boolean raw '("runUnderDoubleTl") nil)
       :double-tl-verdicts (rbx--model-strings raw "doubleTlVerdicts")
       :sanitizer-warnings
       (rbx--model-boolean raw '("sanitizerWarnings") nil)
       :groups (delq nil
                     (mapcar #'rbx--parse-group-report
                             (rbx--wire-sequence
                              (rbx--model-field raw "groups"))))))))

(defun rbx-parse-report (raw)
  "Parse supported RunReport RAW, or return nil.

Unlike structural artifacts, unknown report versions are rejected because
rendering an incomplete testcase is safe while rendering a wrong aggregate
verdict is not."
  (when (equal (rbx--model-number raw "version") 1)
    (rbx-run-report-create
     :solutions
     (delq nil
           (mapcar #'rbx--parse-solution-report
                   (rbx--wire-sequence
                    (rbx--model-field raw "solutions")))))))

(defun rbx--parse-testset-group (raw)
  "Parse RAW as a testset group, or return nil."
  (when-let ((name (rbx--model-string raw "name")))
    (rbx-testset-group-create
     :name name
     :score (rbx--model-number raw "score")
     :deps (rbx--model-strings raw "deps")
     :subgroups (rbx--model-strings raw "subgroups")
     :vars (let ((vars (rbx--model-field raw "vars")))
             (if (rbx--wire-mapping-p vars) vars nil)))))

(defun rbx--parse-validation-result (raw)
  "Parse RAW as a testcase validation result, or return nil."
  (let ((ok (rbx--model-field raw "ok")))
    (unless (eq ok rbx--model-missing)
      (let ((message (rbx--model-string raw "message")))
        (rbx-testset-validation-result-create
         :ok (rbx--model-boolean raw '("ok") nil)
         :validator (rbx--model-string raw "validator")
         :message (unless (string-empty-p (or message "")) message))))))

(defun rbx--parse-visualization (raw)
  "Parse RAW as testcase visualization paths, or return nil."
  (let ((input (rbx--model-string raw "input"))
        (output (rbx--model-string raw "output")))
    (when (or input output)
      (rbx-testset-visualization-create :input input :output output))))

(defun rbx--parse-testset-test (raw)
  "Parse RAW as a testset metadata row, or return nil."
  (let ((group (rbx--model-string raw "group"))
        (index (rbx--model-number raw "index")))
    (when (and group index)
      (rbx-testset-test-create
       :group group
       :index index
       :validation
       (rbx--parse-validation-result
        (rbx--model-field raw "validation"))
       :visualization
       (rbx--parse-visualization (rbx--model-field raw "visualization"))
       :input-size (rbx--model-number raw "input_size")
       :output-size (rbx--model-number raw "output_size")))))

(defun rbx--parse-variable-bounds (raw)
  "Parse RAW as a two-boolean constraint-coverage pair."
  (let ((values (rbx--wire-sequence raw)))
    (when (= (length values) 2)
      (let ((minimum (nth 0 values))
            (maximum (nth 1 values)))
        (when (and (memq minimum '(t nil :false))
                   (memq maximum '(t nil :false)))
          (rbx-variable-bounds-create
           :min-hit (eq minimum t)
           :max-hit (eq maximum t)))))))

(defun rbx--parse-group-bounds (raw)
  "Parse RAW as one group's constraint coverage, or return nil."
  (when-let ((group (rbx--model-string raw "group")))
    (let (bounds)
      (dolist (item (let ((value (rbx--model-field raw "bounds")))
                      (and (rbx--wire-mapping-p value) value)))
        (when-let ((parsed (rbx--parse-variable-bounds (cdr item))))
          (push (cons (car item) parsed) bounds)))
      (rbx-group-bounds-create
       :group group
       :validator (rbx--model-string raw "validator")
       :bounds (nreverse bounds)))))

(defun rbx-parse-testset (raw)
  "Parse RAW as a TestsetManifest, or return nil."
  (when (rbx--wire-mapping-p raw)
    (let ((validation-value (rbx--model-field raw "validation")))
      (rbx-testset-create
       :version (rbx--model-number raw "version")
       :task-type (rbx--model-string raw "task_type")
       :groups (delq nil
                     (mapcar #'rbx--parse-testset-group
                             (rbx--wire-sequence
                              (rbx--model-field raw "groups"))))
       :entries (delq nil
                      (mapcar #'rbx-parse-testcase-entry
                              (rbx--wire-sequence
                               (rbx--model-field raw "entries"))))
       :tests (delq nil
                    (mapcar #'rbx--parse-testset-test
                            (rbx--wire-sequence
                             (rbx--model-field raw "tests"))))
       :validation
       (unless (eq validation-value rbx--model-missing)
         (delq nil
               (mapcar #'rbx--parse-group-bounds
                       (rbx--wire-sequence validation-value))))))))

(defun rbx-testset-testcases (testset)
  "Join TESTSET entries to their build-time metadata."
  (let ((by-key (make-hash-table :test #'equal)))
    (dolist (test (rbx-testset-tests testset))
      (puthash (cons (rbx-testset-test-group test)
                     (rbx-testset-test-index test))
               test by-key))
    (mapcar
     (lambda (entry)
       (rbx-testset-testcase-create
        :entry entry
        :stem (rbx-testcase-stem entry)
        :test (gethash (cons (rbx-testcase-group entry)
                             (rbx-testcase-index entry))
                       by-key)))
     (rbx-testset-entries testset))))

(defun rbx-skeleton-ordered-groups (skeleton)
  "Return nonempty group names in SKELETON declaration order."
  (let ((names (mapcar #'rbx-group-name (rbx-skeleton-groups skeleton))))
    (dolist (entry (rbx-skeleton-entries skeleton))
      (unless (member (rbx-testcase-group entry) names)
        (setq names (append names (list (rbx-testcase-group entry))))))
    (seq-filter
     (lambda (name)
       (seq-some (lambda (entry)
                   (equal (rbx-testcase-group entry) name))
                 (rbx-skeleton-entries skeleton)))
     names)))

(defun rbx-testset-ordered-groups (testset)
  "Return group names in TESTSET declaration order."
  (let ((names (mapcar #'rbx-testset-group-name
                       (rbx-testset-groups testset))))
    (dolist (entry (rbx-testset-entries testset))
      (unless (member (rbx-testcase-group entry) names)
        (setq names (append names (list (rbx-testcase-group entry))))))
    names))

(defun rbx-load-skeleton (package)
  "Read PACKAGE's current skeleton artifact."
  (rbx-parse-skeleton (rbx-read-yaml (rbx-skeleton-path package))))

(defun rbx-load-report (package)
  "Read PACKAGE's current supported run report."
  (rbx-parse-report (rbx-read-yaml (rbx-report-path package))))

(defun rbx-load-evaluation (package solution-index testcase)
  "Read one evaluation for PACKAGE, SOLUTION-INDEX, and TESTCASE."
  (rbx-parse-evaluation
   (rbx-read-yaml
    (rbx-run-artifact-path package solution-index
                           (rbx-testcase-group testcase)
                           (rbx-testcase-stem testcase) ".eval"))))

(defun rbx-load-testset (package)
  "Read PACKAGE's current testset manifest."
  (rbx-parse-testset (rbx-read-yaml (rbx-testset-path package))))

(provide 'rbx-model)
;;; rbx-model.el ends here
