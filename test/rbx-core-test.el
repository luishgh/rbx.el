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

(provide 'rbx-core-test)
;;; rbx-core-test.el ends here
