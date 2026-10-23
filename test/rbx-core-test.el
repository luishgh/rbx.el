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
                 (lambda (configured _fallback &rest _) configured))
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
                 (lambda (configured _fallback &rest _) configured))
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

(defmacro rbx-test-with-recorded-watches (watches &rest body)
  "Run BODY with `file-notify-add-watch' recording into WATCHES.
WATCHES is a symbol bound to an alist of (DIRECTORY . CALLBACK) pairs, newest
first; removed watches are dropped from it."
  (declare (indent 1))
  `(let ((,watches nil) (rbx-test--next-descriptor 0))
     (cl-letf (((symbol-function 'file-notify-add-watch)
                (lambda (directory _flags callback)
                  (let ((descriptor (cl-incf rbx-test--next-descriptor)))
                    (push (list descriptor directory callback) ,watches)
                    descriptor)))
               ((symbol-function 'file-notify-rm-watch)
                (lambda (descriptor)
                  (setq ,watches (cl-remove descriptor ,watches :key #'car)))))
       ,@body)))

(defvar rbx-test--next-descriptor 0)

(defun rbx-test--watched-directories (watches)
  "Return the sorted directory names, relative to nothing, in WATCHES."
  (sort (mapcar (lambda (watch) (directory-file-name (nth 1 watch))) watches)
        #'string<))

(ert-deftest rbx-watcher-adopts-directories-created-after-it-started ()
  (rbx-test-with-directory root
    (rbx-test-with-recorded-watches watches
      (let* ((package (rbx-package-create
                       :root (file-name-as-directory root) :build-dir "build"))
             (rbx-refresh-delay 0)
             (refreshes 0)
             (watcher (rbx-watch-package package (lambda () (cl-incf refreshes)))))
        (should (equal (rbx-test--watched-directories watches)
                       (list (directory-file-name (rbx-package-root package)))))
        (make-directory (expand-file-name ".rbx/runs/0/main" root) t)
        (funcall (nth 2 (car (last watches)))
                 (list 1 'created (expand-file-name ".rbx" root)))
        (sleep-for 0.01)
        (should (= refreshes 1))
        (should (member (expand-file-name ".rbx/runs/0/main" root)
                        (rbx-test--watched-directories watches)))
        (should (member (expand-file-name ".rbx/runs" root)
                        (rbx-test--watched-directories watches)))
        ;; Syncing again must not stack duplicate watches.
        (let ((count (length watches)))
          (funcall (nth 2 (car (last watches)))
                   (list 1 'changed (expand-file-name ".rbx/runs/report.yml" root)))
          (sleep-for 0.01)
          (should (= (length watches) count)))
        (rbx-stop-watcher watcher)
        (should-not watches)))))

(ert-deftest rbx-watcher-follows-a-repointed-build-directory ()
  (rbx-test-with-directory root
    (rbx-test-write root ".local.rbx/preset.rbx.yml" "env: env.rbx.yml\n")
    (rbx-test-write root ".local.rbx/env.rbx.yml" "buildDir: build\n")
    (make-directory (expand-file-name "build/tests" root) t)
    (make-directory (expand-file-name "out/tests" root) t)
    (rbx-reset-build-directories)
    (rbx-test-with-recorded-watches watches
      (let* ((package (rbx--make-package root))
             (rbx-refresh-delay 0)
             (seen nil)
             (watcher (rbx-watch-package
                       package
                       (lambda () (push (rbx-package-build-dir package) seen)))))
        (should (equal (rbx-package-build-dir package) "build"))
        (should (member (expand-file-name ".local.rbx" root)
                        (rbx-test--watched-directories watches)))
        (should (member (expand-file-name "build/tests" root)
                        (rbx-test--watched-directories watches)))
        (rbx-test-write root ".local.rbx/env.rbx.yml" "buildDir: out\n")
        (funcall (nth 2 (car (last watches)))
                 (list 1 'changed (expand-file-name ".local.rbx/env.rbx.yml" root)))
        (sleep-for 0.01)
        (should (equal seen '("out")))
        (should (equal (rbx-package-build-dir package) "out"))
        (should (member (expand-file-name "out/tests" root)
                        (rbx-test--watched-directories watches)))
        (should-not (member (expand-file-name "build/tests" root)
                            (rbx-test--watched-directories watches)))
        (rbx-stop-watcher watcher)))))

(ert-deftest rbx-adhoc-package-reads-the-irun-directory ()
  (let* ((package (rbx-package-create :root "/p/" :build-dir "build"))
         (adhoc (rbx-adhoc-package package)))
    (should (equal (rbx-runs-path package) "/p/.rbx/runs"))
    (should (equal (rbx-runs-path adhoc) "/p/.rbx/runs/.irun"))
    (should (equal (rbx-skeleton-path adhoc)
                   "/p/.rbx/runs/.irun/skeleton.yml"))
    (should (equal (rbx-report-path adhoc)
                   "/p/.rbx/runs/.irun/report.yml"))
    ;; rbx irun writes no group level under each solution.
    (should (equal (rbx-run-artifact-path adhoc 1 "interactive" "000" ".out")
                   "/p/.rbx/runs/.irun/1/000.out"))
    (should (equal (rbx-run-artifact-path package 1 "main" "000" ".out")
                   "/p/.rbx/runs/1/main/000.out"))
    (should (equal (rbx-adhoc-input-path adhoc "000" ".in")
                   "/p/.rbx/runs/.irun/inputs/000.in"))
    ;; The stress session is never nested inside the ad-hoc run.
    (should (equal (rbx-stress-path adhoc) "/p/.rbx/runs/.stress"))
    ;; The original package is untouched.
    (should-not (rbx-package-runs-subdir package))))

(ert-deftest rbx-watcher-covers-the-irun-directories ()
  (rbx-test-with-directory root
    (make-directory (expand-file-name ".rbx/runs/.irun/0" root) t)
    (make-directory (expand-file-name ".rbx/runs/.irun/inputs" root) t)
    (let ((adhoc (rbx-adhoc-package
                  (rbx-package-create
                   :root (file-name-as-directory root) :build-dir "build"))))
      (dolist (dir '(".rbx/runs/.irun" ".rbx/runs/.irun/0"
                     ".rbx/runs/.irun/inputs"))
        (should (member (expand-file-name dir root)
                        (rbx--watchable-directories adhoc)))))))

(ert-deftest rbx-stress-paths-follow-the-published-layout ()
  (let ((package (rbx-package-create :root "/p/" :build-dir "build")))
    (should (equal (rbx-stress-manifest-path package)
                   "/p/.rbx/runs/.stress/stress.yml"))
    (should (equal (rbx-stress-finding-path package 3 "input.in")
                   "/p/.rbx/runs/.stress/findings/3/input.in"))))

(ert-deftest rbx-watcher-covers-stress-finding-directories ()
  (rbx-test-with-directory root
    (make-directory (expand-file-name ".rbx/runs/.stress/findings/1" root) t)
    (let ((package (rbx-package-create
                    :root (file-name-as-directory root) :build-dir "build")))
      (dolist (dir '(".rbx/runs/.stress" ".rbx/runs/.stress/findings"
                     ".rbx/runs/.stress/findings/1"))
        (should (member (expand-file-name dir root)
                        (rbx--watchable-directories package)))))))

(ert-deftest rbx-watcher-covers-the-statement-report-directory ()
  (rbx-test-with-directory root
    (make-directory (expand-file-name ".rbx/statements" root) t)
    (let ((package (rbx-package-create
                    :root (file-name-as-directory root) :build-dir "build")))
      (should (equal (rbx-statement-report-path package)
                     (expand-file-name ".rbx/statements/report.yml" root)))
      (should (member (expand-file-name ".rbx/statements" root)
                      (rbx--watchable-directories package))))))

(ert-deftest rbx-artifact-event-p-accepts-the-preset-environment-file ()
  (should (rbx--artifact-event-p
           '(1 changed "/p/.local.rbx/env.rbx.yml")))
  (should (rbx--artifact-event-p
           '(1 changed "/p/.rbx/runs/0/main/000.eval"))))

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
          (let ((for-b (cdr (assoc (directory-file-name root-b) notifications))))
            (funcall for-b '(1 changed "/tmp/B/.rbx/runs/report.yml")))
          (sleep-for 0.01)
          (should (equal notified (list package-b)))
          (mapc #'rbx-stop-watcher watchers))))))

(ert-deftest rbx-run-process-captures-stdout-stderr-and-exit-code ()
  :tags '(needs-shell)
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
  :tags '(needs-shell)
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
  :tags '(needs-shell)
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable root "fake" "echo hi\n")))
      (should (equal (rbx--run-process-sync root program nil nil)
                     '("hi\n" "" 0))))))

(ert-deftest rbx-run-process-sync-does-not-run-timers ()
  :tags '(needs-shell)
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable root "fake" "sleep 0.3\necho done\n"))
          (fired nil)
          timer)
      (setq timer (run-at-time 0 nil (lambda () (setq fired t))))
      (unwind-protect
          (progn
            (should (equal (rbx--run-process-sync root program nil nil)
                           '("done\n" "" 0)))
            (should-not fired))
        (cancel-timer timer)))))

(ert-deftest rbx-run-process-sync-times-out ()
  :tags '(needs-shell)
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable root "fake" "sleep 5\n"))
          (start (float-time)))
      (should-not (nth 2 (rbx--run-process-sync root program nil nil 0.3)))
      (should (< (- (float-time) start) 2)))))

(ert-deftest rbx-run-process-sync-handles-spawn-error ()
  (rbx-test-with-directory root
    (pcase-let ((`(,stdout ,_stderr ,exit-code)
                 (rbx--run-process-sync
                  root (expand-file-name "does-not-exist" root) nil nil)))
      (should (equal stdout ""))
      (should-not (eql exit-code 0)))))

(ert-deftest rbx-run-process-sync-captures-stderr-and-stdin ()
  :tags '(needs-shell)
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable
                    root "fake" "cat; echo err >&2; exit 3\n")))
      (should (equal (rbx--run-process-sync root program nil "in\n")
                     '("in\n" "err\n" 3))))))

(ert-deftest rbx-command-available-p-true-for-a-working-executable ()
  :tags '(needs-shell)
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable root "fake" "exit 0\n")))
      (should (rbx--command-available-p program root)))))

(ert-deftest rbx-command-available-p-false-for-a-failing-executable ()
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable root "fake" "exit 1\n")))
      (should-not (rbx--command-available-p program root)))))

(ert-deftest rbx-login-shell-path-finds-the-command ()
  :tags '(needs-shell)
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
                (lambda (command _root &rest _)
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
              (lambda (command _root &rest _) (equal command "fallback"))))
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

;; envrc.el and similar packages make `exec-path' buffer-local; a bare
;; command name resolved there must not be re-resolved elsewhere.
(ert-deftest rbx-resolve-executable-returns-the-absolute-path-it-found ()
  (rbx-test-with-directory root
    (let ((program (rbx-test-write-executable root "fallback" "exit 0\n")))
      (cl-letf (((symbol-function 'rbx--command-available-p)
                 (lambda (&rest _args) t)))
        (with-temp-buffer
          (setq-local exec-path (list root))
          (should (equal (rbx-resolve-executable nil "fallback" root)
                         program)))))))

(ert-deftest rbx-read-yaml-runs-the-yq-found-in-the-calling-buffer ()
  :tags '(needs-shell)
  (rbx-test-with-directory root
    (let ((path (rbx-test-write root "artifact.yml" "ignored: by stub\n"))
          (bin (file-name-directory
                (rbx-test-write-executable
                 (progn (make-directory (expand-file-name "bin" root))
                        (expand-file-name "bin" root))
                 "yq"
                 "case \"$1\" in --version) echo 'yq (https://github.com/mikefarah/yq/) version v4.0.0';; *) echo '{\"answer\":42}';; esac\n"))))
      (rbx-reset-executables)
      (unwind-protect
          (with-temp-buffer
            (setq default-directory (file-name-as-directory root))
            (setq-local exec-path (cons bin (default-value 'exec-path)))
            (let ((rbx-yq-program "yq"))
              (should (equal (rbx--wire-field (rbx-read-yaml path) "answer")
                             42))))
        (rbx-reset-executables)))))

(ert-deftest rbx-resolve-executable-rejects-candidates-failing-the-version-check ()
  (rbx-test-with-directory root
    (let (tried)
      (cl-letf (((symbol-function 'rbx--run-process-sync)
                 (lambda (_root command _args _input &optional _timeout)
                   (push command tried)
                   (list (if (equal command "good") "right flavor" "wrong")
                         "" 0)))
                ((symbol-function 'rbx--login-shell-path)
                 (lambda (_name _root) "good")))
        (should (equal (rbx-resolve-executable
                        "configured" "fallback" root
                        (lambda (version) (string-match-p "right" version)))
                       "good"))
        (should (equal (nreverse tried) '("configured" "fallback" "good")))))))

(ert-deftest rbx-yq-version-supported-p-accepts-only-mikefarah-yq ()
  (should (rbx--yq-version-supported-p
           "yq (https://github.com/mikefarah/yq/) version v4.53.3\n"))
  (should-not (rbx--yq-version-supported-p "yq 3.4.3\n")))

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

(ert-deftest rbx-read-yaml-returns-nil-quietly-when-yq-cannot-be-resolved ()
  (rbx-test-with-directory root
    (let ((path (rbx-test-write root "artifact.yml" "a: 1\n"))
          (warnings 0))
      (rbx-reset-executables)
      (cl-letf (((symbol-function 'rbx-resolve-executable) (lambda (&rest _args) nil))
               ((symbol-function 'display-warning)
                (lambda (&rest _args) (cl-incf warnings))))
        (should-not (rbx-read-yaml path))
        (should (= warnings 0))))))

(ert-deftest rbx-ensure-yq-returns-the-resolved-program ()
  (cl-letf (((symbol-function 'rbx-resolve-executable)
             (lambda (&rest _args) "/opt/yq")))
    (should (equal (rbx-ensure-yq) "/opt/yq"))))

(ert-deftest rbx-ensure-yq-signals-user-error-when-yq-is-missing ()
  (rbx-test-with-directory root
    (cl-letf (((symbol-function 'rbx-resolve-executable) (lambda (&rest _args) nil)))
      (with-temp-buffer
        (setq-local exec-path (list root))
        (let ((err (should-error (rbx-ensure-yq root) :type 'user-error)))
          (should (string-match-p "mikefarah/yq" (cadr err)))
          (should (string-match-p "not found" (cadr err))))))))

(ert-deftest rbx-ensure-yq-names-a-wrong-flavor-yq-it-found ()
  (rbx-test-with-directory root
    (let ((wrong (rbx-test-write-executable root "yq" "echo 'yq 3.4.3'\n")))
      (cl-letf (((symbol-function 'rbx-resolve-executable)
                 (lambda (&rest _args) nil)))
        (with-temp-buffer
          (setq-local exec-path (list root))
          (let ((rbx-yq-program "yq")
                (err (should-error (rbx-ensure-yq root) :type 'user-error)))
            (should (string-match-p (regexp-quote wrong) (cadr err)))
            (should (string-match-p "not mikefarah/yq" (cadr err)))))))))

(provide 'rbx-core-test)
;;; rbx-core-test.el ends here
