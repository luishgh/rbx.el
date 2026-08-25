;;; package-lint-helper.el --- Isolated package-lint setup -*- lexical-binding: t; -*-

;;; Commentary:

;; Teach package.el about dependencies supplied directly by Guix.  Guix puts
;; their libraries on `load-path' without adding package descriptors to
;; `package-alist', while package-lint intentionally checks that every declared
;; dependency has a descriptor.  Building the descriptors from the libraries'
;; own package headers keeps the check isolated and verifies the exact versions
;; in manifest.scm.

;;; Code:

(require 'package)

(setq package-alist nil
      package-archive-contents nil)

(dolist (dependency '((magit-section . "magit-section")
                      (transient . "transient")))
  (let* ((located (locate-library (cdr dependency)))
         (source (and located
                      (if (string-suffix-p ".elc" located)
                          (concat (file-name-sans-extension located) ".el")
                        located)))
         (library (and source (file-readable-p source) source)))
    (unless library
      (error "Missing package-lint dependency: %s" (car dependency)))
    (with-temp-buffer
      (insert-file-contents library)
      (emacs-lisp-mode)
      (let ((descriptor (package-buffer-info)))
        (unless (eq (package-desc-name descriptor) (car dependency))
          (error "Library %s describes %s, expected %s"
                 library (package-desc-name descriptor) (car dependency)))
        (push descriptor (alist-get (car dependency) package-alist))))))

(defvar rbx-test--package-alist package-alist
  "Package descriptors derived from the pure Guix environment.")

(defun rbx-test--restore-package-descriptors (&rest _ignored)
  "Restore pure-Guix descriptors after `package-initialize'."
  (setq package-alist rbx-test--package-alist
        package-archive-contents nil))

;; `package-lint-batch-and-exit' initializes package.el immediately before
;; linting.  Guix libraries are not package.el installations, so that operation
;; otherwise discards the descriptors constructed above.
(advice-add 'package-initialize :after #'rbx-test--restore-package-descriptors)

(provide 'package-lint-helper)
;;; package-lint-helper.el ends here
