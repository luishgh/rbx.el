;;; rbx-core.el --- Artifact discovery and paths for rbx -*- lexical-binding: t; -*-

;; Copyright (C) 2026 rbx-for-emacs contributors

;; Author: rbx-for-emacs contributors
;; Maintainer: rbx-for-emacs contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (yaml "1.2.0"))
;; Keywords: tools, languages
;; URL: https://github.com/luishgh/rbx-for-emacs

;;; Commentary:

;; Locate rbx problem packages and map their stable on-disk artifact layout.
;; This library is intentionally a pure reader.  Invoking rbx, even to query
;; it, can invalidate cache directories owned by another rbx process.

;;; Code:

(require 'cl-lib)
(require 'filenotify)
(require 'subr-x)
(require 'yaml)

(defgroup rbx nil
  "Inspect rbx artifacts from Emacs."
  :group 'tools
  :prefix "rbx-")

(defcustom rbx-refresh-delay 0.2
  "Seconds to debounce artifact changes before refreshing a view."
  :type 'number
  :group 'rbx)

(defconst rbx-problem-manifest "problem.rbx.yml"
  "Name of an rbx problem manifest.")

(defconst rbx-cache-directory ".rbx"
  "Name of the cache directory managed by rbx.")

(defconst rbx-default-build-directory "build"
  "Default relative build directory used by rbx.")

(cl-defstruct (rbx-package
               (:constructor rbx-package-create (&key root build-dir)))
  "A discovered rbx package.

ROOT is the absolute directory containing `problem.rbx.yml'.
BUILD-DIR is the build directory relative to ROOT."
  root
  build-dir)

(cl-defstruct (rbx-watcher (:constructor rbx--watcher-create))
  "State used to watch one rbx package."
  package
  callback
  descriptors
  timer)

(defvar rbx--build-directory-cache (make-hash-table :test #'equal)
  "Build directories cached by absolute package root.")

(defun rbx-reset-build-directories ()
  "Forget all cached build-directory resolutions."
  (interactive)
  (clrhash rbx--build-directory-cache))

(defun rbx-read-yaml (path)
  "Read YAML from PATH as string-keyed alists and lists.

Return nil when PATH is missing, unreadable, empty, or temporarily invalid.
This tolerance is important because artifact files can be observed between a
truncate and the completing rename or write."
  (condition-case nil
      (when (file-readable-p path)
        (let ((contents (with-temp-buffer
                          (insert-file-contents path)
                          (buffer-string))))
          (unless (string-empty-p (string-trim contents))
            (yaml-parse-string contents
                               :object-type 'alist
                               :object-key-type 'string
                               :sequence-type 'list
                               :null-object nil
                               :false-object :false))))
    (error nil)))

(defun rbx--wire-mapping-p (value)
  "Return non-nil when VALUE is a string-keyed alist."
  (and (listp value)
       value
       (cl-every (lambda (item)
                   (and (consp item) (stringp (car item))))
                 value)))

(defun rbx--wire-get (mapping key &optional default)
  "Read KEY from MAPPING, returning DEFAULT when it is absent."
  (if (rbx--wire-mapping-p mapping)
      (alist-get key mapping default nil #'equal)
    default))

(defun rbx--wire-field (root &rest keys)
  "Read a nested field below ROOT by following string KEYS."
  (let ((current root))
    (catch 'missing
      (dolist (key keys current)
        (let ((missing (make-symbol "missing")))
          (setq current (rbx--wire-get current key missing))
          (when (eq current missing)
            (throw 'missing nil)))))))

(defun rbx--wire-sequence (value)
  "Return VALUE when it is a sequence rather than a mapping."
  (if (and (listp value) (not (rbx--wire-mapping-p value))) value nil))

(defun rbx--wire-string (value)
  "Return VALUE when it is a string."
  (and (stringp value) value))

(defun rbx--wire-number (value)
  "Return VALUE when it is a finite number."
  (and (numberp value)
       (or (not (floatp value)) (= value value))
       value))

(defun rbx--wire-boolean (value &optional default)
  "Return boolean VALUE, or DEFAULT when VALUE is not a YAML boolean."
  (cond
   ((eq value t) t)
   ((or (eq value :false) (null value)) nil)
   (t default)))

(defun rbx--ancestors (directory)
  "Return DIRECTORY and its ancestors, nearest first."
  (let ((current (directory-file-name (expand-file-name directory)))
        result
        parent)
    (while current
      (push current result)
      (setq parent (file-name-directory current))
      (setq parent (and parent (directory-file-name parent)))
      (setq current (unless (or (null parent) (equal parent current)) parent)))
    (nreverse result)))

(defun rbx--find-preset-directory (root)
  "Find the active preset directory governing ROOT."
  (or (cl-loop for directory in (rbx--ancestors root)
               for installed = (expand-file-name
                                ".local.rbx/preset.rbx.yml" directory)
               when (file-exists-p installed)
               return (file-name-directory installed))
      (cl-loop for directory in (rbx--ancestors root)
               for developed = (expand-file-name "preset.rbx.yml" directory)
               when (file-exists-p developed)
               return (file-name-directory developed))))

(defun rbx--resolve-build-directory-uncached (root)
  "Resolve ROOT's configured build directory without consulting a cache."
  (if-let* ((preset-directory (rbx--find-preset-directory root))
            (preset (rbx-read-yaml
                     (expand-file-name "preset.rbx.yml" preset-directory)))
            (environment (rbx--wire-string
                          (rbx--wire-field preset "env")))
            (configuration
             (rbx-read-yaml (expand-file-name environment preset-directory)))
            (build-directory
             (rbx--wire-string (rbx--wire-field configuration "buildDir")))
            ((not (file-name-absolute-p build-directory))))
      build-directory
    rbx-default-build-directory))

(defun rbx-resolve-build-dir (root)
  "Return the build directory for the package at ROOT.

The active preset is found using rbx's nearest `.local.rbx/preset.rbx.yml'
rule, with a developing checkout's `preset.rbx.yml' as fallback."
  (let* ((absolute (file-name-as-directory (expand-file-name root)))
         (missing (make-symbol "missing"))
         (cached (gethash absolute rbx--build-directory-cache missing)))
    (if (eq cached missing)
        (let ((resolved (rbx--resolve-build-directory-uncached absolute)))
          (puthash absolute resolved rbx--build-directory-cache)
          resolved)
      cached)))

(defun rbx--make-package (root)
  "Create an `rbx-package' rooted at ROOT."
  (let ((absolute (file-name-as-directory (expand-file-name root))))
    (rbx-package-create :root absolute
                        :build-dir (rbx-resolve-build-dir absolute))))

(defconst rbx--discovery-excluded-directories
  '(".git" ".git-data" ".rbx" ".env" ".direnv" "node_modules" "build")
  "Directory basenames omitted while discovering rbx packages.")

(defun rbx--discover-manifests (root)
  "Return problem manifest paths recursively below ROOT."
  (let (result)
    (cl-labels
        ((walk (directory)
           (dolist (path (directory-files
                          directory t directory-files-no-dot-files-regexp t))
             (cond
              ((file-directory-p path)
               (unless (or (file-symlink-p path)
                           (member (file-name-nondirectory
                                    (directory-file-name path))
                                   rbx--discovery-excluded-directories))
                 (walk path)))
              ((equal (file-name-nondirectory path) rbx-problem-manifest)
               (push path result))))))
      (when (file-directory-p root)
        (walk root)))
    result))

(defun rbx-discover-packages (&optional root)
  "Discover rbx packages recursively below ROOT.

ROOT defaults to `default-directory'.  Results are sorted by absolute package
root, which gives stable problem selection and view ordering."
  (let* ((base (expand-file-name (or root default-directory)))
         (roots (delete-dups
                 (mapcar #'file-name-directory
                         (rbx--discover-manifests base)))))
    (mapcar #'rbx--make-package (sort roots #'string-lessp))))

(defun rbx-find-package (&optional directory)
  "Return the nearest rbx package containing DIRECTORY.

DIRECTORY defaults to the current buffer's file directory, then
`default-directory'."
  (let* ((start (or directory
                    (and buffer-file-name (file-name-directory buffer-file-name))
                    default-directory))
         (root (locate-dominating-file start rbx-problem-manifest)))
    (when root (rbx--make-package root))))

(defun rbx-cache-path (package)
  "Return PACKAGE's cache directory."
  (expand-file-name rbx-cache-directory (rbx-package-root package)))

(defun rbx-runs-path (package)
  "Return PACKAGE's run artifact directory."
  (expand-file-name "runs" (rbx-cache-path package)))

(defun rbx-skeleton-path (package)
  "Return PACKAGE's solution skeleton path."
  (expand-file-name "skeleton.yml" (rbx-runs-path package)))

(defun rbx-report-path (package)
  "Return PACKAGE's aggregate run report path."
  (expand-file-name "report.yml" (rbx-runs-path package)))

(defun rbx-build-path (package)
  "Return PACKAGE's absolute build directory."
  (expand-file-name (rbx-package-build-dir package)
                    (rbx-package-root package)))

(defun rbx-tests-path (package)
  "Return PACKAGE's generated-test directory."
  (expand-file-name "tests" (rbx-build-path package)))

(defun rbx-testset-path (package)
  "Return PACKAGE's testset manifest path."
  (expand-file-name "testset.yml" (rbx-build-path package)))

(defun rbx-run-artifact-path (package solution-index group stem extension)
  "Return a run artifact path.

PACKAGE and SOLUTION-INDEX select a solution, GROUP and STEM select a
testcase, and EXTENSION includes its leading dot."
  (expand-file-name
   (format "%s/%s%s" group stem extension)
   (expand-file-name (number-to-string solution-index)
                     (rbx-runs-path package))))

(defun rbx-test-artifact-path (package group stem extension)
  "Return a generated test artifact path for PACKAGE, GROUP, and STEM.

EXTENSION includes its leading dot."
  (expand-file-name (format "%s/%s%s" group stem extension)
                    (rbx-tests-path package)))

(defun rbx-package-file-path (package recorded-path)
  "Resolve RECORDED-PATH relative to PACKAGE.

Both Windows and POSIX separators are accepted because artifacts can be read
on a different host from the one that produced them."
  (if (file-name-absolute-p recorded-path)
      recorded-path
    (expand-file-name
     (string-join (split-string recorded-path "[/\\\\]+" t) "/")
     (rbx-package-root package))))

(defun rbx--watchable-directories (package)
  "Return existing artifact directories worth watching for PACKAGE."
  (delete-dups
   (seq-filter #'file-directory-p
               (list (rbx-package-root package)
                     (rbx-cache-path package)
                     (rbx-runs-path package)
                     (rbx-build-path package)
                     (rbx-tests-path package)))))

(defun rbx--artifact-event-p (event)
  "Return non-nil when file notification EVENT concerns rbx state."
  (let ((path (nth 2 event)))
    (and (stringp path)
         (or (string-match-p
              (rx (or "problem.rbx.yml" "preset.rbx.yml" "testset.yml"
                      "skeleton.yml" "report.yml") string-end)
              path)
             (string-match-p
              (rx "." (or "eval" "out" "in" "err" "log" "pio")
                  string-end)
              path)
             (string-match-p (rx "/.rbx" (or "/" string-end)) path)))))

(defun rbx--watcher-notify (watcher event)
  "Schedule WATCHER's callback in response to EVENT."
  (when (rbx--artifact-event-p event)
    (when-let ((timer (rbx-watcher-timer watcher)))
      (cancel-timer timer))
    (setf (rbx-watcher-timer watcher)
          (run-at-time
           rbx-refresh-delay nil
           (lambda ()
             (setf (rbx-watcher-timer watcher) nil)
             (rbx-reset-build-directories)
             (funcall (rbx-watcher-callback watcher)))))))

(defun rbx-watch-package (package callback)
  "Watch PACKAGE artifacts and invoke CALLBACK after an artifact change.

The returned watcher must eventually be passed to `rbx-stop-watcher'."
  (let ((watcher (rbx--watcher-create :package package :callback callback)))
    (setf (rbx-watcher-descriptors watcher)
          (delq nil
                (mapcar
                 (lambda (directory)
                   (condition-case nil
                       (file-notify-add-watch
                        directory '(change attribute-change)
                        (lambda (event)
                          (rbx--watcher-notify watcher event)))
                     (file-notify-error nil)))
                 (rbx--watchable-directories package))))
    watcher))

(defun rbx-stop-watcher (watcher)
  "Stop WATCHER and cancel its pending refresh."
  (when watcher
    (when-let ((timer (rbx-watcher-timer watcher)))
      (cancel-timer timer)
      (setf (rbx-watcher-timer watcher) nil))
    (dolist (descriptor (rbx-watcher-descriptors watcher))
      (condition-case nil
          (file-notify-rm-watch descriptor)
        (file-notify-error nil)))
    (setf (rbx-watcher-descriptors watcher) nil)))

(provide 'rbx-core)
;;; rbx-core.el ends here
