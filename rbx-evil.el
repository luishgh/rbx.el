;;; rbx-evil.el --- Evil-mode support for rbx-view-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026 rbx.el contributors

;; Author: rbx.el contributors
;; Maintainer: rbx.el contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (evil "1.14.0"))
;; Keywords: tools, languages
;; URL: https://github.com/luishgh/rbx.el

;;; Commentary:

;; Optional evil-mode integration for `rbx-view-mode'.  This file is never
;; required by `rbx.el' directly; it is loaded on demand once `evil' itself
;; is loaded, so `evil' never becomes a hard dependency of the package.
;;
;; `rbx-view-mode' opens in evil's normal state, matching how
;; `evil-collection' treats `magit-section-mode', the mode it derives from.
;; Every key the mode defines or inherits from `magit-section-mode-map'
;; collides with an evil normal- or motion-state default, so this file
;; reinstates all of them on `rbx-view-mode-map' itself (never on
;; `magit-section-mode-map', so real Magit buffers are unaffected).  The one
;; behavioral change from the non-evil bindings is `g': it is freed for
;; evil's own `g'-prefixed motions (`gg', `G', ...), and `rbx-refresh' moves
;; to `g r', mirroring the same "refresh lives on g r" convention evil and
;; evil-collection already use elsewhere (e.g. Magit's own `rbx-refresh').

;;; Code:

(require 'evil)
(require 'rbx-ui)

(evil-set-initial-state 'rbx-view-mode 'normal)

(evil-define-key 'normal rbx-view-mode-map
  (kbd "RET") #'rbx-view-visit
  (kbd "TAB") #'magit-section-toggle
  (kbd "^")   #'magit-section-up
  (kbd "n")   #'magit-section-forward
  (kbd "p")   #'magit-section-backward
  (kbd "q")   #'quit-window
  (kbd "?")   #'rbx-dispatch
  (kbd "g")   nil
  (kbd "g r") #'rbx-refresh)

(provide 'rbx-evil)
;;; rbx-evil.el ends here
