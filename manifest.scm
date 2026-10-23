(specifications->manifest
 '("bash"
   "coreutils"
   "diffutils"
   "emacs-evil"
   "emacs-magit"
   "emacs-package-lint"
   "emacs-transient"
   "emacs"
   "findutils"
   ;; For the integration suite: rbx compiles validators with g++.  GCC 16
   ;; cannot build the testlib.h that rbx bundles, so stay on an older one.
   "gcc-toolchain@13"
   "git"
   "make"
   "python"
   "python-pip"
   "ripgrep"
   ;; For the statement-build integration test: rbx runs pdflatex on its
   ;; bundled ICPC template, which needs these beyond the small scheme.
   "texlive-scheme-small"
   "texlive-enumitem"
   "texlive-import"
   "texlive-logicpuzzle"
   "texlive-marginnote"
   "texlive-moreverb"
   "texlive-multirow"
   "texlive-pmboxdraw"
   "texlive-titlesec"
   "yq"))
