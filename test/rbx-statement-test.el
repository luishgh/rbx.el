;;; rbx-statement-test.el --- Tests for rbx-statement -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the `\VAR{...}' scanner, CLI protocol, and caching.

;;; Code:

(require 'rbx-statement)
(require 'test-helper)

(defun rbx-statement-test--payload ()
  "Return a representative `rbx-statement-vars-payload' fixture."
  (rbx-statement-vars-payload-create
   :vars '(("AB.max" . "200") ("AB.min" . "1") ("n" . "5"))
   :groups '(("sub1" . (("AB.max" . "10") ("AB.min" . "1")))
             ("sub-1" . (("AB.max" . "10"))))))

(defmacro rbx-statement-test--with-buffer (text &rest body)
  "Insert TEXT into a temporary buffer and evaluate BODY there."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     ,@body))

(defun rbx-statement-test--scan (text)
  "Scan TEXT against the fixture payload and return the resulting refs."
  (rbx-statement-test--with-buffer text
    (rbx-statement-scan-buffer (rbx-statement-test--payload))))

(ert-deftest rbx-statement-scan-root-reference-with-vars-prefix ()
  (let ((refs (rbx-statement-test--scan "\\VAR{vars.AB.max}")))
    (should (= (length refs) 1))
    (let ((ref (car refs)))
      (should-not (rbx-statement-var-ref-group ref))
      (should (equal (rbx-statement-var-ref-expression ref) "AB.max"))
      (should-not (rbx-statement-var-ref-filtered ref))
      (should (equal (rbx-statement-var-ref-text ref) "200"))
      (should (= (rbx-statement-var-ref-start ref) 1))
      (should (= (rbx-statement-var-ref-end ref)
                 (1+ (length "\\VAR{vars.AB.max}")))))))

(ert-deftest rbx-statement-scan-root-reference-shorthand ()
  (let ((refs (rbx-statement-test--scan "\\VAR{AB.max}")))
    (should (= (length refs) 1))
    (should (equal (rbx-statement-var-ref-text (car refs)) "200"))))

(ert-deftest rbx-statement-scan-group-dot-form-shorthand ()
  (let ((refs (rbx-statement-test--scan "\\VAR{problem.groups.sub1.AB.max}")))
    (should (= (length refs) 1))
    (let ((ref (car refs)))
      (should (equal (rbx-statement-var-ref-group ref) "sub1"))
      (should (equal (rbx-statement-var-ref-expression ref) "sub1\tAB.max"))
      (should (equal (rbx-statement-var-ref-text ref) "10")))))

(ert-deftest rbx-statement-scan-group-dot-form-with-vars-infix ()
  (let ((refs (rbx-statement-test--scan "\\VAR{problem.groups.sub1.vars.AB.max}")))
    (should (= (length refs) 1))
    (should (equal (rbx-statement-var-ref-text (car refs)) "10"))))

(ert-deftest rbx-statement-scan-group-bracket-form-single-quote ()
  (let ((refs (rbx-statement-test--scan "\\VAR{problem.groups['sub-1'].AB.max}")))
    (should (= (length refs) 1))
    (should (equal (rbx-statement-var-ref-group (car refs)) "sub-1"))))

(ert-deftest rbx-statement-scan-group-bracket-form-double-quote ()
  (let ((refs (rbx-statement-test--scan "\\VAR{problem.groups[\"sub1\"].AB.max}")))
    (should (= (length refs) 1))
    (should (equal (rbx-statement-var-ref-group (car refs)) "sub1"))))

(ert-deftest rbx-statement-scan-filter-without-args-is-filtered ()
  (let ((refs (rbx-statement-test--scan "\\VAR{AB.max|sci}")))
    (should (= (length refs) 1))
    (let ((ref (car refs)))
      (should (rbx-statement-var-ref-filtered ref))
      (should-not (rbx-statement-var-ref-text ref))
      (should (equal (rbx-statement-var-ref-expression ref) "AB.max | sci")))))

(ert-deftest rbx-statement-scan-filter-with-args-and-spacing-canonicalizes ()
  (let ((refs (rbx-statement-test--scan "\\VAR{AB.max   |   sci(3)}")))
    (should (equal (rbx-statement-var-ref-expression (car refs)) "AB.max | sci(3)"))))

(ert-deftest rbx-statement-scan-filter-chain ()
  (let ((refs (rbx-statement-test--scan "\\VAR{AB.max|sci|upper}")))
    (should (equal (rbx-statement-var-ref-expression (car refs))
                   "AB.max | sci | upper"))))

(ert-deftest rbx-statement-scan-quoted-filter-arg-not-respaced ()
  (let ((refs (rbx-statement-test--scan
              "\\VAR{n|default('x|y')}")))
    (should (equal (rbx-statement-var-ref-expression (car refs))
                   "n |default('x|y')"))))

(ert-deftest rbx-statement-scan-declines-half-typed-pipeline ()
  (should-not (rbx-statement-test--scan "\\VAR{AB.max |}"))
  (should-not (rbx-statement-test--scan "\\VAR{AB.max ||sci}")))

(ert-deftest rbx-statement-scan-declines-escaped-var ()
  (should-not (rbx-statement-test--scan "\\\\VAR{AB.max}")))

(ert-deftest rbx-statement-scan-declines-commented-var ()
  (should-not (rbx-statement-test--scan "% a comment \\VAR{AB.max}\n")))

(ert-deftest rbx-statement-scan-ignores-escaped-percent ()
  (let ((refs (rbx-statement-test--scan "\\%not a comment \\VAR{AB.max}\n")))
    (should (= (length refs) 1))))

(ert-deftest rbx-statement-scan-declines-loop-bound-and-foreign-scopes ()
  (should-not (rbx-statement-test--scan "\\VAR{g.AB.max}"))
  (should-not (rbx-statement-test--scan "\\VAR{p.AB.max}"))
  (should-not (rbx-statement-test--scan "\\VAR{problem.title}"))
  (should-not (rbx-statement-test--scan "\\VAR{contest.vars.x}"))
  (should-not (rbx-statement-test--scan "\\VAR{groups.sub1.AB.max}")))

(ert-deftest rbx-statement-scan-declines-unknown-group ()
  (should-not (rbx-statement-test--scan "\\VAR{problem.groups.nope.AB.max}")))

(ert-deftest rbx-statement-scan-declines-undefined-name ()
  (should-not (rbx-statement-test--scan "\\VAR{typo}"))
  (should-not (rbx-statement-test--scan "\\VAR{problem.groups.sub1.typo}")))

(ert-deftest rbx-statement-scan-declines-a-literal-brace-occurrence ()
  (should-not (rbx-statement-test--scan "\\VAR{{'a': 1}}")))

(ert-deftest rbx-statement-scan-finds-multiple-references ()
  (let ((refs (rbx-statement-test--scan "\\VAR{AB.max} and \\VAR{AB.min}")))
    (should (= (length refs) 2))
    (should (equal (mapcar #'rbx-statement-var-ref-text refs) '("200" "1")))))

(defun rbx-statement-test--write-fake-rbx (root script)
  "Write SCRIPT as an executable fake rbx program under ROOT."
  (let ((path (expand-file-name "fake-rbx" root)))
    (with-temp-file path
      (insert "#!/bin/sh\n" script))
    (set-file-modes path #o755)
    path))

(defun rbx-statement-test--wait (predicate &optional timeout)
  "Process output until PREDICATE is non-nil or TIMEOUT (default 5s) elapses."
  (let ((deadline (+ (float-time) (or timeout 5))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(ert-deftest rbx-statement-run-captures-stdout-stderr-and-exit-code ()
  (rbx-test-with-directory root
    (let ((rbx-program (rbx-statement-test--write-fake-rbx
                        root "echo out; echo err >&2; exit 3\n"))
          result)
      (rbx-statement--run root nil nil
                         (lambda (stdout stderr exit-code)
                           (setq result (list stdout stderr exit-code))))
      (should (rbx-statement-test--wait (lambda () result)))
      (should (equal (nth 0 result) "out\n"))
      (should (equal (nth 1 result) "err\n"))
      (should (= (nth 2 result) 3)))))

(ert-deftest rbx-statement-run-writes-stdin ()
  (rbx-test-with-directory root
    (let ((rbx-program (rbx-statement-test--write-fake-rbx root "cat\n"))
          result)
      (rbx-statement--run root nil "hello\n"
                         (lambda (stdout _stderr exit-code)
                           (setq result (cons stdout exit-code))))
      (should (rbx-statement-test--wait (lambda () result)))
      (should (equal (car result) "hello\n"))
      (should (= (cdr result) 0)))))

(ert-deftest rbx-statement-run-handles-spawn-error ()
  (rbx-test-with-directory root
    (let ((rbx-program (expand-file-name "does-not-exist" root))
          (got nil) result)
      (rbx-statement--run root nil nil
                         (lambda (_stdout _stderr exit-code)
                           (setq got t result exit-code)))
      (should (rbx-statement-test--wait (lambda () got)))
      (should-not result))))

(ert-deftest rbx-statement-run-times-out ()
  (rbx-test-with-directory root
    (let ((rbx-program (rbx-statement-test--write-fake-rbx root "sleep 5\n"))
          (rbx-statement--timeout 0.3)
          (got nil) result)
      (rbx-statement--run root nil nil
                         (lambda (_stdout _stderr exit-code)
                           (setq got t result exit-code)))
      (should (rbx-statement-test--wait (lambda () got) 3))
      (should-not result))))

(ert-deftest rbx-statement-parse-vars-with-groups-tolerates-ansi-and-noise ()
  (let ((payload (rbx-statement--parse-vars-with-groups
                  (concat "warning: something\n"
                         "{\"vars\":{\"n\":\"5\"},\"groups\":{\"sub1\":{\"m\":\"1\"}}}"
                         "\n\e[?25h"))))
    (should payload)
    (should (equal (rbx-statement-vars-payload-vars payload) '(("n" . "5"))))
    (should (equal (cdr (assoc "sub1" (rbx-statement-vars-payload-groups payload)))
                  '(("m" . "1"))))))

(ert-deftest rbx-statement-parse-vars-with-groups-nil-for-wrong-shape ()
  (should-not (rbx-statement--parse-vars-with-groups "{\"vars\":{\"n\":5}}"))
  (should-not (rbx-statement--parse-vars-with-groups "{\"vars\":{\"n\":\"5\"}}"))
  (should-not (rbx-statement--parse-vars-with-groups "not json at all")))

(ert-deftest rbx-statement-parse-vars-flat-shape ()
  (let ((payload (rbx-statement--parse-vars "{\"n\":\"5\"}")))
    (should (equal (rbx-statement-vars-payload-vars payload) '(("n" . "5"))))
    (should-not (rbx-statement-vars-payload-groups payload))))

(ert-deftest rbx-statement-load-vars-caches-and-dedupes-concurrent-callers ()
  (rbx-test-with-directory root
    (let ((package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build"))
          (calls 0)
          pending-callback
          results)
      (cl-letf (((symbol-function 'rbx-statement--run)
                (lambda (_root args _input callback)
                  (cl-incf calls)
                  (should (equal args '("vars" "--json" "--groups")))
                  (setq pending-callback callback))))
        (rbx-statement-load-vars package (lambda (p) (push p results)))
        (rbx-statement-load-vars package (lambda (p) (push p results)))
        (should (= calls 1))
        (should (= (length results) 0))
        (funcall pending-callback "{\"vars\":{\"n\":\"5\"},\"groups\":{}}" "" 0)
        (should (= (length results) 2))
        (rbx-statement-load-vars package (lambda (p) (push p results)))
        (should (= calls 1))
        (should (= (length results) 3))))))

(ert-deftest rbx-statement-load-vars-falls-back-without-groups-support ()
  (rbx-test-with-directory root
    (let ((package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build"))
          invocations result)
      (cl-letf (((symbol-function 'rbx-statement--run)
                (lambda (_root args _input callback)
                  (push args invocations)
                  (if (member "--groups" args)
                      (funcall callback "" "unknown option" 2)
                    (funcall callback "{\"n\":\"5\"}" "" 0)))))
        (rbx-statement-load-vars package (lambda (p) (setq result p)))
        (should (equal (nreverse invocations)
                      '(("vars" "--json" "--groups") ("vars" "--json"))))
        (should (equal (rbx-statement-vars-payload-vars result) '(("n" . "5"))))
        (should-not (rbx-statement-vars-payload-groups result))))))

(ert-deftest rbx-statement-load-vars-nil-when-package-unreadable ()
  (rbx-test-with-directory root
    (let ((package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build"))
          (got 'unset))
      (cl-letf (((symbol-function 'rbx-statement--run)
                (lambda (_root _args _input callback)
                  (funcall callback "" "broken" 1))))
        (rbx-statement-load-vars package (lambda (p) (setq got p)))
        (should-not got)))))

(ert-deftest rbx-statement-invalidate-forces-a-fresh-load ()
  (rbx-test-with-directory root
    (let ((package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build"))
          (calls 0))
      (cl-letf (((symbol-function 'rbx-statement--run)
                (lambda (_root _args _input callback)
                  (cl-incf calls)
                  (funcall callback "{\"vars\":{},\"groups\":{}}" "" 0))))
        (rbx-statement-load-vars package #'ignore)
        (should (= calls 1))
        (rbx-statement-load-vars package #'ignore)
        (should (= calls 1))
        (rbx-statement-invalidate package)
        (rbx-statement-load-vars package #'ignore)
        (should (= calls 2))))))

(ert-deftest rbx-statement-render-caches-successes-and-declines ()
  (rbx-test-with-directory root
    (let ((package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build"))
          (calls 0)
          result)
      (cl-letf (((symbol-function 'rbx-statement--run)
                (lambda (_root args input callback)
                  (cl-incf calls)
                  (should (equal args '("vars" "--render" "--target" "text")))
                  (should (equal input "AB.max | sci\nbad\n"))
                  (funcall callback "{\"AB.max | sci\":\"2×10²\"}" "" 0))))
        (rbx-statement-render
         package '("AB.max | sci" "bad")
         (lambda (alist) (setq result alist)))
        (should (equal (cdr (assoc "AB.max | sci" result)) "2×10²"))
        (should-not (cdr (assoc "bad" result)))
        (should (assoc "bad" result))
        (rbx-statement-render package '("AB.max | sci" "bad") #'ignore)
        (should (= calls 1))))))

(ert-deftest rbx-statement-render-only-requests-missing-expressions ()
  (rbx-test-with-directory root
    (let ((package (rbx-package-create :root (file-name-as-directory root)
                                       :build-dir "build"))
          requested)
      (cl-letf (((symbol-function 'rbx-statement--run)
                (lambda (_root _args input callback)
                  (setq requested (split-string input "\n" t))
                  (funcall callback (format "{\"%s\":\"1\"}" (car requested))
                          "" 0))))
        (rbx-statement-render package '("a") #'ignore)
        (should (equal requested '("a")))
        (rbx-statement-render package '("a" "b") #'ignore)
        (should (equal requested '("b")))))))

(provide 'rbx-statement-test)
;;; rbx-statement-test.el ends here
