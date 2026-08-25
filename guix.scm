;;; guix.scm --- Guix package for rbx-for-emacs -*- mode: scheme; -*-

(use-modules (gnu packages emacs-build)
             (gnu packages emacs-xyz)
             (gnu packages textutils)
             (guix build-system emacs)
             (guix gexp)
             (guix git-download)
             (guix licenses)
             (guix packages)
             (guix utils))

(package
  (name "emacs-rbx")
  (version "0.1.0")
  (source
   (local-file (dirname (current-filename))
               "rbx-for-emacs-checkout"
               #:recursive? #t
               #:select? (git-predicate (current-source-directory))))
  (build-system emacs-build-system)
  (native-inputs (list emacs-package-lint))
  (propagated-inputs (list emacs-magit emacs-transient yq))
  (home-page "https://github.com/luishgh/rbx-for-emacs")
  (synopsis "Inspect rbx runs and testsets from Emacs")
  (description
   "rbx for Emacs provides native Magit Section views for inspecting rbx run
and testset artifacts, a Transient command interface, and Flymake diagnostics
for compiler findings.  It follows rbx's terminal-first workflow and never
invokes rbx or modifies generated artifacts.")
  (license expat))

;;; guix.scm ends here
