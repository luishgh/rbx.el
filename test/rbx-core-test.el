;;; rbx-core-test.el --- Tests for rbx-core -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for package discovery, YAML reading, and artifact paths.

;;; Code:

(require 'rbx-core)
(require 'test-helper)

(ert-deftest rbx-read-yaml-is-tolerant-of-invalid-input ()
  (rbx-test-with-directory root
    (let ((path (rbx-test-write root "broken.yml" "key: [\n")))
      (should-not (rbx-read-yaml path)))))

(ert-deftest rbx-read-yaml-converts-through-yq-before-native-json-parsing ()
  (rbx-test-with-directory root
    (let ((path (rbx-test-write root "artifact.yml" "ignored: by stub\n"))
          invocation)
      (cl-letf (((symbol-function 'rbx-resolve-executable)
                 (lambda (configured _fallback) configured))
                ((symbol-function 'process-file)
                 (lambda (program input destination display &rest arguments)
                   (setq invocation
                         (list program input destination display arguments))
                   (insert "{\"answer\":42,\"disabled\":false}")
                   0)))
        (let ((parsed (rbx-read-yaml path)))
          (should (equal (rbx--wire-field parsed "answer") 42))
          (should (eq (rbx--wire-field parsed "disabled") :false)))
        (should (equal invocation
                       (list rbx-yq-program nil t nil
                             (list "--input-format=yaml"
                                   "--output-format=json"
                                   "--no-colors" "--indent=0"
                                   "." path))))))))

(ert-deftest rbx-read-yaml-ignores-failed-yq-conversions ()
  (rbx-test-with-directory root
    (let ((path (rbx-test-write root "artifact.yml"
                                "still: being-written\n")))
      (cl-letf (((symbol-function 'rbx-resolve-executable)
                 (lambda (configured _fallback) configured))
                ((symbol-function 'process-file)
                 (lambda (&rest _arguments)
                   (insert "conversion failed")
                   1)))
        (should-not (rbx-read-yaml path))))))

(ert-deftest rbx-discover-packages-finds-manifests-but-skips-artifacts ()
  (rbx-test-with-directory root
    (rbx-test-write root "contest/A/problem.rbx.yml" "name: Alpha\n")
    (rbx-test-write root "contest/B/problem.rbx.yml" "name: Beta\n")
    (rbx-test-write root ".rbx/copy/problem.rbx.yml" "name: Cache\n")
    (rbx-test-write root "build/copy/problem.rbx.yml" "name: Build\n")
    (let ((packages (rbx-discover-packages root)))
      (should (= (length packages) 2))
      (should (equal (mapcar (lambda (package)
                               (file-relative-name
                                (rbx-package-root package) root))
                             packages)
                     '("contest/A/" "contest/B/"))))))

(ert-deftest rbx-find-package-locates-nearest-manifest ()
  (rbx-test-with-directory root
    (rbx-test-write root "problem.rbx.yml" "name: Root\n")
    (make-directory (expand-file-name "sols/nested" root) t)
    (let ((package (rbx-find-package (expand-file-name "sols/nested" root))))
      (should package)
      (should (equal (rbx-package-root package)
                     (file-name-as-directory root))))))

(ert-deftest rbx-resolve-build-dir-defaults-to-build ()
  (rbx-test-with-directory root
    (should (equal (rbx-resolve-build-dir root) "build"))))

(ert-deftest rbx-resolve-build-dir-follows-installed-preset ()
  (rbx-test-with-directory root
    (let ((package-root (expand-file-name "contest/A" root)))
      (make-directory package-root t)
      (rbx-test-write root ".local.rbx/preset.rbx.yml" "env: env.rbx.yml\n")
      (rbx-test-write root ".local.rbx/env.rbx.yml" "buildDir: out/build.rbx\n")
      (should (equal (rbx-resolve-build-dir package-root) "out/build.rbx")))))

(ert-deftest rbx-resolve-build-dir-refuses-absolute-directory ()
  (rbx-test-with-directory root
    (rbx-test-write root "preset.rbx.yml" "env: env.rbx.yml\n")
    (rbx-test-write root "env.rbx.yml" "buildDir: /tmp/escape\n")
    (should (equal (rbx-resolve-build-dir root) "build"))))

(ert-deftest rbx-artifact-paths-use-package-layout ()
  (rbx-test-with-directory root
    (let ((package (rbx-package-create
                    :root (file-name-as-directory root)
                    :build-dir "build.rbx")))
      (should (equal (rbx-skeleton-path package)
                     (expand-file-name ".rbx/runs/skeleton.yml" root)))
      (should (equal (rbx-report-path package)
                     (expand-file-name ".rbx/runs/report.yml" root)))
      (should (equal (rbx-testset-path package)
                     (expand-file-name "build.rbx/testset.yml" root)))
      (should (equal (rbx-run-artifact-path
                      package 2 "main" "1-gen-000" ".eval")
                     (expand-file-name
                      ".rbx/runs/2/main/1-gen-000.eval" root))))))

(ert-deftest rbx-find-contest-root-locates-nearest-manifest ()
  (rbx-test-with-directory root
    (rbx-test-write root "contest.rbx.yml" "name: Finals\n")
    (make-directory (expand-file-name "A/sols" root) t)
    (should (equal (rbx-find-contest-root (expand-file-name "A/sols" root))
                   (file-name-as-directory root)))))

(ert-deftest rbx-find-contest-root-returns-nil-outside-a-contest ()
  (rbx-test-with-directory root
    (should-not (rbx-find-contest-root root))))

(ert-deftest rbx-discover-contest-variants-finds-canonical-only ()
  (rbx-test-with-directory root
    (rbx-test-write root "contest.rbx.yml" "name: Finals\n")
    (should (equal (mapcar #'car (rbx-discover-contest-variants root))
                   '(nil)))))

(ert-deftest rbx-discover-contest-variants-finds-siblings ()
  (rbx-test-with-directory root
    (rbx-test-write root "contest.rbx.yml" "use_variants: true\n")
    (rbx-test-write root "contest.div1.rbx.yml" "name: Division 1\n")
    (rbx-test-write root "contest.div2.rbx.yml" "name: Division 2\n")
    (let ((variants (rbx-discover-contest-variants root)))
      (should (assoc nil variants))
      (should (equal (sort (delq nil (mapcar #'car variants)) #'string-lessp)
                     '("div1" "div2"))))))

(ert-deftest rbx-discover-contest-variants-without-canonical-file ()
  (rbx-test-with-directory root
    (rbx-test-write root "contest.div1.rbx.yml" "name: Division 1\n")
    (should (equal (mapcar #'car (rbx-discover-contest-variants root))
                   '("div1")))))

(ert-deftest rbx-watch-package-debounces-relevant-artifacts ()
  (rbx-test-with-directory root
    (let ((package (rbx-package-create
                    :root (file-name-as-directory root)
                    :build-dir "build"))
          notifications
          (refreshes 0)
          watcher)
      (cl-letf (((symbol-function 'file-notify-add-watch)
                 (lambda (_directory _flags callback)
                   (push callback notifications)
                   (length notifications)))
                ((symbol-function 'file-notify-rm-watch) #'ignore))
        (let ((rbx-refresh-delay 0))
          (setq watcher
                (rbx-watch-package package (lambda () (cl-incf refreshes))))
          (should notifications)
          (funcall (car notifications)
                   '(1 changed "/tmp/package/.rbx/runs/report.yml"))
          (sleep-for 0.01)
          (should (= refreshes 1))
          (funcall (car notifications)
                   '(1 changed "/tmp/package/notes.txt"))
          (sleep-for 0.01)
          (should (= refreshes 1))
          (rbx-stop-watcher watcher))))))

(ert-deftest rbx-watch-contest-invokes-callback-with-the-changed-package ()
  (rbx-test-with-directory root
    (let* ((root-a (file-name-as-directory (expand-file-name "A" root)))
           (root-b (file-name-as-directory (expand-file-name "B" root)))
           (package-a (rbx-package-create :root root-a :build-dir "build"))
           (package-b (rbx-package-create :root root-b :build-dir "build"))
           notifications
           notified
           watchers)
      (make-directory root-a t)
      (make-directory root-b t)
      (cl-letf (((symbol-function 'file-notify-add-watch)
                 (lambda (directory _flags callback)
                   (push (cons directory callback) notifications)
                   (length notifications)))
                ((symbol-function 'file-notify-rm-watch) #'ignore))
        (let ((rbx-refresh-delay 0))
          (setq watchers
                (rbx-watch-contest
                 (list package-a package-b)
                 (lambda (package) (push package notified))))
          (should (= (length notifications) 2))
          (let ((for-b (cdr (assoc root-b notifications))))
            (funcall for-b '(1 changed "/tmp/B/.rbx/runs/report.yml")))
          (sleep-for 0.01)
          (should (equal notified (list package-b)))
          (mapc #'rbx-stop-watcher watchers))))))

(ert-deftest rbx-run-process-captures-stdout-stderr-and-exit-code ()
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable
                    root "fake" "echo out; echo err >&2; exit 3\n"))
          result)
      (rbx-run-process root program nil nil
                       (lambda (stdout stderr exit-code)
                         (setq result (list stdout stderr exit-code))))
      (should (rbx-test-wait (lambda () result)))
      (should (equal (nth 0 result) "out\n"))
      (should (equal (nth 1 result) "err\n"))
      (should (= (nth 2 result) 3)))))

(ert-deftest rbx-run-process-writes-stdin ()
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable root "fake" "cat\n"))
          result)
      (rbx-run-process root program nil "hello\n"
                       (lambda (stdout _stderr exit-code)
                         (setq result (cons stdout exit-code))))
      (should (rbx-test-wait (lambda () result)))
      (should (equal (car result) "hello\n"))
      (should (= (cdr result) 0)))))

(ert-deftest rbx-run-process-handles-spawn-error ()
  (rbx-test-with-directory root
    (let ((program (expand-file-name "does-not-exist" root))
          (got nil) result)
      (rbx-run-process root program nil nil
                       (lambda (_stdout _stderr exit-code)
                         (setq got t result exit-code)))
      (should (rbx-test-wait (lambda () got)))
      (should-not result))))

(ert-deftest rbx-run-process-times-out ()
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable root "fake" "sleep 5\n"))
          (got nil) result)
      (rbx-run-process root program nil nil
                       (lambda (_stdout _stderr exit-code)
                         (setq got t result exit-code))
                       0.3)
      (should (rbx-test-wait (lambda () got) 3))
      (should-not result))))

(ert-deftest rbx-run-process-sync-blocks-until-callback ()
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable root "fake" "echo hi\n")))
      (should (equal (rbx--run-process-sync root program nil nil)
                     '("hi\n" "" 0))))))

(ert-deftest rbx-command-available-p-true-for-a-working-executable ()
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable root "fake" "exit 0\n")))
      (should (rbx--command-available-p program root)))))

(ert-deftest rbx-command-available-p-false-for-a-failing-executable ()
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable root "fake" "exit 1\n")))
      (should-not (rbx--command-available-p program root)))))

(ert-deftest rbx-login-shell-path-finds-the-command ()
  (rbx-test-with-directory root
    (let* ((target (rbx-test-write-executable root "real-tool" "exit 0\n"))
          (shell (rbx-test-write-executable
                  root "fake-shell"
                  (format "echo noise\necho %s\n" target))))
      (let ((process-environment (cons (format "SHELL=%s" shell)
                                       process-environment)))
        (should (equal (rbx--login-shell-path "real-tool" root) target))))))

(ert-deftest rbx-login-shell-path-nil-when-not-found ()
  (rbx-test-with-directory root
    (let ((shell (rbx-test-write-executable root "fake-shell" "true\n")))
      (let ((process-environment (cons (format "SHELL=%s" shell)
                                       process-environment)))
        (should-not (rbx--login-shell-path "nope" root))))))

(ert-deftest rbx-resolve-executable-prefers-configured-then-path-then-login-shell ()
  (rbx-test-with-directory root
    (let (tried)
      (cl-letf (((symbol-function 'rbx--command-available-p)
                (lambda (command _root)
                  (push command tried)
                  (equal command "found-on-login-shell")))
               ((symbol-function 'rbx--login-shell-path)
                (lambda (_name _root) "found-on-login-shell")))
        (should (equal (rbx-resolve-executable "configured-tool" "fallback" root)
                      "found-on-login-shell"))
        (should (equal (nreverse tried)
                      '("configured-tool" "fallback" "found-on-login-shell")))))))

(ert-deftest rbx-resolve-executable-skips-configured-when-same-as-fallback ()
  (rbx-test-with-directory root
    (cl-letf (((symbol-function 'rbx--command-available-p)
              (lambda (command _root) (equal command "fallback"))))
      (should (equal (rbx-resolve-executable "fallback" "fallback" root)
                    "fallback")))))

(ert-deftest rbx-resolve-executable-caches-per-fallback-and-root ()
  (rbx-test-with-directory root
    (let ((calls 0))
      (cl-letf (((symbol-function 'rbx--command-available-p)
                (lambda (&rest _args) (cl-incf calls) t)))
        (should (equal (rbx-resolve-executable nil "fallback" root) "fallback"))
        (should (= calls 1))
        (should (equal (rbx-resolve-executable nil "fallback" root) "fallback"))
        (should (= calls 1))))))

(ert-deftest rbx-resolve-executable-caches-a-failed-resolution ()
  (rbx-test-with-directory root
    (let ((calls 0))
      (cl-letf (((symbol-function 'rbx--command-available-p)
                (lambda (&rest _args) (cl-incf calls) nil))
               ((symbol-function 'rbx--login-shell-path)
                (lambda (&rest _args) nil)))
        (should-not (rbx-resolve-executable nil "fallback" root))
        (let ((after-first calls))
          (should-not (rbx-resolve-executable nil "fallback" root))
          (should (= calls after-first)))))))

(ert-deftest rbx-reset-executables-clears-the-cache ()
  (rbx-test-with-directory root
    (let ((calls 0))
      (cl-letf (((symbol-function 'rbx--command-available-p)
                (lambda (&rest _args) (cl-incf calls) t)))
        (rbx-resolve-executable nil "fallback" root)
        (rbx-reset-executables)
        (rbx-resolve-executable nil "fallback" root)
        (should (= calls 2))))))

(ert-deftest rbx-warn-once-shows-a-message-only-once ()
  (let ((calls 0))
    (cl-letf (((symbol-function 'display-warning)
              (lambda (&rest _args) (cl-incf calls))))
      (rbx--warn-once 'test-key "message")
      (rbx--warn-once 'test-key "message")
      (should (= calls 1))
      (rbx-reset-executables)
      (rbx--warn-once 'test-key "message")
      (should (= calls 2)))))

(ert-deftest rbx-read-yaml-warns-once-when-yq-cannot-be-resolved ()
  (rbx-test-with-directory root
    (let ((path (rbx-test-write root "artifact.yml" "a: 1\n"))
          (warnings 0))
      (rbx-reset-executables)
      (cl-letf (((symbol-function 'rbx-resolve-executable) (lambda (&rest _args) nil))
               ((symbol-function 'display-warning)
                (lambda (&rest _args) (cl-incf warnings))))
        (should-not (rbx-read-yaml path))
        (should-not (rbx-read-yaml path))
        (should (= warnings 1))))))

(provide 'rbx-core-test)
;;; rbx-core-test.el ends here
