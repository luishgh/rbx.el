;;; rbx-evil-test.el --- Tests for rbx-evil -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the optional evil-mode integration.

;;; Code:

(require 'evil)
(require 'rbx-evil)
(require 'test-helper)

(defmacro rbx-evil-test-with-view-buffer (binding &rest body)
  "Bind BINDING to a live `rbx-view-mode' buffer with evil enabled."
  (declare (indent 1) (debug (symbolp body)))
  `(with-temp-buffer
     (let ((,binding (current-buffer)))
       (rbx-view-mode)
       (evil-local-mode 1)
       ,@body)))

(ert-deftest rbx-evil-opens-rbx-view-mode-in-normal-state ()
  (rbx-evil-test-with-view-buffer _buffer
    (should (eq evil-state 'normal))))

(ert-deftest rbx-evil-reinstates-rbx-view-mode-bindings ()
  (rbx-evil-test-with-view-buffer _buffer
    (should (eq (key-binding (kbd "RET")) #'rbx-view-visit))
    (should (eq (key-binding (kbd "TAB")) #'magit-section-toggle))
    (should (eq (key-binding (kbd "^")) #'magit-section-up))
    (should (eq (key-binding (kbd "n")) #'magit-section-forward))
    (should (eq (key-binding (kbd "p")) #'magit-section-backward))
    (should (eq (key-binding (kbd "q")) #'quit-window))
    (should (eq (key-binding (kbd "?")) #'rbx-dispatch))
    (should (eq (key-binding (kbd "g r")) #'rbx-refresh))))

(ert-deftest rbx-evil-frees-g-for-evils-own-motions ()
  (rbx-evil-test-with-view-buffer _buffer
    (should (eq (key-binding (kbd "g g")) #'evil-goto-first-line))
    (should (eq (key-binding (kbd "G")) #'evil-goto-line))))

(provide 'rbx-evil-test)
;;; rbx-evil-test.el ends here
