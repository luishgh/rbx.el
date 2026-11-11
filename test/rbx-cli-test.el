;;; rbx-cli-test.el --- Tests for rbx-cli -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the allowlisted rbx invocations and their output parsing.

;;; Code:

(require 'rbx-cli)
(require 'test-helper)

(ert-deftest rbx-cli-run-delegates-to-rbx-run-process-when-resolved ()
  (rbx-test-with-directory root
    (let (delegated-args result)
      (cl-letf (((symbol-function 'rbx-resolve-executable)
                (lambda (configured fallback given-root)
                  (should (equal configured rbx-program))
                  (should (equal fallback "rbx"))
                  (should (equal given-root root))
                  "/usr/bin/rbx"))
               ((symbol-function 'rbx-run-process)
                (lambda (given-root program args input callback &optional timeout)
                  (setq delegated-args (list given-root program args input timeout))
                  (funcall callback "out" "" 0))))
        (rbx-cli-run root '("vars" "--json") "in"
                     (lambda (stdout stderr exit-code)
                       (setq result (list stdout stderr exit-code)))
                     30)
        (should (equal delegated-args (list root "/usr/bin/rbx"
                                            '("vars" "--json") "in" 30)))
        (should (equal result '("out" "" 0)))))))

(ert-deftest rbx-cli-run-honours-a-directory-local-program ()
  (rbx-test-with-directory root
    (rbx-test-write root ".dir-locals.el"
                    "((nil . ((rbx-program . \"/opt/rbx-2.3/bin/rbx\"))))")
    (let ((enable-local-variables :all) configured)
      ;; The caller's buffer lives elsewhere, as in a process sentinel.
      (with-temp-buffer
        (setq default-directory temporary-file-directory)
        (cl-letf (((symbol-function 'rbx-resolve-executable)
                   (lambda (program &rest _) (setq configured program) nil))
                  ((symbol-function 'display-warning) #'ignore))
          (rbx-cli-run root '("vars" "--json") nil #'ignore)))
      (should (equal configured "/opt/rbx-2.3/bin/rbx")))))

(ert-deftest rbx-cli-run-honours-a-buffer-local-program ()
  (rbx-test-with-directory root
    (let (configured)
      (with-temp-buffer
        (setq default-directory (file-name-as-directory root))
        (setq-local rbx-program "/local/rbx")
        (cl-letf (((symbol-function 'rbx-resolve-executable)
                   (lambda (program &rest _) (setq configured program) nil))
                  ((symbol-function 'display-warning) #'ignore))
          (rbx-cli-run root '("vars" "--json") nil #'ignore)))
      (should (equal configured "/local/rbx")))))

(ert-deftest rbx-cli-run-declines-without-attempting-a-spawn ()
  (rbx-test-with-directory root
    (let (spawned result warning)
      (cl-letf (((symbol-function 'rbx-resolve-executable)
                (lambda (&rest _args) nil))
               ((symbol-function 'rbx-run-process)
                (lambda (&rest _args) (setq spawned t)))
               ((symbol-function 'display-warning)
                (lambda (_type message &rest _args) (setq warning message))))
        (clrhash rbx--warned-once)
        (rbx-cli-run root '("time-inspect" "-p" "local") nil
                     (lambda (stdout stderr exit-code)
                       (setq result (list stdout stderr exit-code)))
                     nil "the time profile checks")
        (should-not spawned)
        (should (string-match-p "the time profile checks" warning))
        (should (equal result '("" "" nil)))))))

(ert-deftest rbx-cli-run-refuses-a-command-off-the-allowlist ()
  (rbx-test-with-directory root
    (let (resolved spawned)
      (cl-letf (((symbol-function 'rbx-resolve-executable)
                (lambda (&rest _args) (setq resolved t) "/usr/bin/rbx"))
               ((symbol-function 'rbx-run-process)
                (lambda (&rest _args) (setq spawned t))))
        (dolist (args '(("run") ("build") ("time" "-p" "local") ("clear")
                        nil ("--version")))
          (should-error (rbx-cli-run root args nil #'ignore)))
        (should-not resolved)
        (should-not spawned)))))

(ert-deftest rbx-cli-run-refuses-time-inspect-edits ()
  (rbx-test-with-directory root
    (let (spawned)
      (cl-letf (((symbol-function 'rbx-resolve-executable)
                (lambda (&rest _args) "/usr/bin/rbx"))
               ((symbol-function 'rbx-run-process)
                (lambda (&rest _args) (setq spawned t))))
        (dolist (flag '(("--set" "0=900") ("--set=base=900") ("--revert" "base")
                        ("--memory" "256") ("--inherit") ("--no-inherit")))
          (should-error
           (rbx-cli-run root (append '("time-inspect" "-p" "local" "--stdin") flag)
                        nil #'ignore)))
        (should-not spawned)
        (rbx-cli-run root '("time-inspect" "-p" "local" "--stdin") "" #'ignore)
        (should spawned)))))

(ert-deftest rbx-cli-parse-json-object-tolerates-ansi-and-noise ()
  (should (equal (rbx-cli-parse-json-object
                  (concat "warning: {not json\n"
                          "{\"version\":1,\"rows\":[]}"
                          "\n\e[?25h"))
                 '((version . 1) (rows)))))

(ert-deftest rbx-cli-parse-json-object-returns-nil-without-one ()
  (should-not (rbx-cli-parse-json-object "Error: No such command\n"))
  (should-not (rbx-cli-parse-json-object "")))

(provide 'rbx-cli-test)
;;; rbx-cli-test.el ends here
