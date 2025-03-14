;;; completion/vertico/config.el -*- lexical-binding: t; -*-

(defvar +vertico-company-completion-styles '(basic partial-completion orderless)
  "Completion styles for company to use.

The completion/vertico module uses the orderless completion style by default,
but this returns too broad a candidate set for company completion. This variable
overrides `completion-styles' during company completion sessions.")

(defvar +vertico-consult-fd-args nil
  "Shell command and arguments the vertico module uses for fd.")

;;
;;; Packages

(use-package! vertico
  :hook (doom-first-input . vertico-mode)
  :config
  (setq vertico-resize nil
        vertico-count 17
        vertico-cycle t
        completion-in-region-function
        (lambda (&rest args)
          (apply (if vertico-mode
                     #'consult-completion-in-region
                   #'completion--in-region)
                 args)))
  ;; Cleans up path when moving directories with shadowed paths syntax, e.g.
  ;; cleans ~/foo/bar/// to /, and ~/foo/bar/~/ to ~/.
  (add-hook 'rfn-eshadow-update-overlay-hook #'vertico-directory-tidy)
  (map! :map vertico-map [backspace] #'vertico-directory-delete-char))


(use-package! orderless
  :after-call doom-first-input-hook
  :config
  (defun +vertico-orderless-dispatch (pattern _index _total)
    (cond
     ;; Ensure $ works with Consult commands, which add disambiguation suffixes
     ((string-suffix-p "$" pattern)
      `(orderless-regexp . ,(concat (substring pattern 0 -1) "[\x100000-\x10FFFD]*$")))
     ;; Ignore single !
     ((string= "!" pattern) `(orderless-literal . ""))
     ;; Without literal
     ((string-prefix-p "!" pattern) `(orderless-without-literal . ,(substring pattern 1)))
     ;; Character folding
     ((string-prefix-p "%" pattern) `(char-fold-to-regexp . ,(substring pattern 1)))
     ((string-suffix-p "%" pattern) `(char-fold-to-regexp . ,(substring pattern 0 -1)))
     ;; Initialism matching
     ((string-prefix-p "`" pattern) `(orderless-initialism . ,(substring pattern 1)))
     ((string-suffix-p "`" pattern) `(orderless-initialism . ,(substring pattern 0 -1)))
     ;; Literal matching
     ((string-prefix-p "=" pattern) `(orderless-literal . ,(substring pattern 1)))
     ((string-suffix-p "=" pattern) `(orderless-literal . ,(substring pattern 0 -1)))
     ;; Flex matching
     ((string-prefix-p "~" pattern) `(orderless-flex . ,(substring pattern 1)))
     ((string-suffix-p "~" pattern) `(orderless-flex . ,(substring pattern 0 -1)))))
  (add-to-list
   'completion-styles-alist
   '(+vertico-basic-remote
     +vertico-basic-remote-try-completion
     +vertico-basic-remote-all-completions
     "Use basic completion on remote files only"))
  (setq completion-styles '(orderless)
        completion-category-defaults nil
        ;; note that despite override in the name orderless can still be used in
        ;; find-file etc.
        completion-category-overrides '((file (styles +vertico-basic-remote orderless partial-completion)))
        orderless-style-dispatchers '(+vertico-orderless-dispatch)
        orderless-component-separator "[ &]")
  ;; ...otherwise find-file gets different highlighting than other commands
  (set-face-attribute 'completions-first-difference nil :inherit nil))


(use-package! consult
  :defer t
  :init
  (define-key!
    [remap apropos]                       #'consult-apropos
    [remap bookmark-jump]                 #'consult-bookmark
    [remap evil-show-marks]               #'consult-mark
    [remap evil-show-jumps]               #'+vertico/jump-list
    [remap goto-line]                     #'consult-goto-line
    [remap imenu]                         #'consult-imenu
    [remap locate]                        #'consult-locate
    [remap load-theme]                    #'consult-theme
    [remap man]                           #'consult-man
    [remap recentf-open-files]            #'consult-recent-file
    [remap switch-to-buffer]              #'consult-buffer
    [remap switch-to-buffer-other-window] #'consult-buffer-other-window
    [remap switch-to-buffer-other-frame]  #'consult-buffer-other-frame
    [remap yank-pop]                      #'consult-yank-pop
    [remap persp-switch-to-buffer]        #'+vertico/switch-workspace-buffer)
  (advice-add #'completing-read-multiple :override #'consult-completing-read-multiple)
  (advice-add #'multi-occur :override #'consult-multi-occur)
  :config
  (setq consult-project-root-function #'doom-project-root
        consult-narrow-key "<"
        consult-line-numbers-widen t
        consult-async-min-input 2
        consult-async-refresh-delay  0.15
        consult-async-input-throttle 0.2
        consult-async-input-debounce 0.1)
  (unless +vertico-consult-fd-args
    (setq +vertico-consult-fd-args
          (if doom-projectile-fd-binary
              (format "%s --color=never -i -H -E .git --regex %s"
                      doom-projectile-fd-binary
                      (if IS-WINDOWS "--path-separator=/" ""))
            consult-find-args)))

  (consult-customize
   consult-ripgrep consult-git-grep consult-grep
   consult-bookmark consult-recent-file
   +default/search-project +default/search-project-for-symbol-at-point
   +default/search-other-project +vertico/search-symbol-at-point
   +default/search-cwd +default/search-other-cwd
   +default/search-notes-for-symbol-at-point
   consult--source-file consult--source-project-file consult--source-bookmark
   :preview-key (kbd "C-SPC"))
  (consult-customize
   consult-theme
   :preview-key (list (kbd "C-SPC") :debounce 0.5 'any))
  (after! org
    (defvar +vertico--consult-org-source
      `(:name     "Org"
        :narrow   ?o
        :hidden t
        :category buffer
        :state    ,#'consult--buffer-state
        :items    ,(lambda () (mapcar #'buffer-name (org-buffer-list)))))
    (add-to-list 'consult-buffer-sources '+vertico--consult-org-source 'append))
  (map! :map consult-crm-map
        :desc "Select candidate" "TAB" #'+vertico/crm-select
        :desc "Enter candidates" "RET" #'+vertico/crm-exit))


(use-package! consult-flycheck
  :when (featurep! :checkers syntax)
  :after (consult flycheck))


(use-package! embark
  :defer t
  :init
  (setq which-key-use-C-h-commands nil
        prefix-help-command #'embark-prefix-help-command)
  (map! [remap describe-bindings] #'embark-bindings
        "C-;"               #'embark-act  ; to be moved to :config default if accepted
        (:map minibuffer-local-map
         "C-;"               #'embark-act
         "C-c C-;"           #'embark-export
         :desc "Export to writable buffer" "C-c C-e" #'+vertico/embark-export-write)
        (:leader
         :desc "Actions" "a" #'embark-act)) ; to be moved to :config default if accepted
  :config
  (set-popup-rule! "^\\*Embark Export Grep" :size 0.35 :ttl 0 :quit nil)
  (cl-nsubstitute #'+vertico-embark-which-key-indicator #'embark-mixed-indicator embark-indicators)
  (add-to-list 'embark-indicators #'+vertico-embark-vertico-indicator)
  ;; add the package! target finder before the file target finder,
  ;; so we don't get a false positive match.
  (let ((pos (or (cl-position
                  'embark-target-file-at-point
                  embark-target-finders)
                 (length embark-target-finders))))
    (cl-callf2
        cons
        '+vertico-embark-target-package-fn
        (nthcdr pos embark-target-finders)))
  (embark-define-keymap +vertico/embark-doom-package-map
    "Keymap for Embark package actions for packages installed by Doom."
    ("h" doom/help-packages)
    ("b" doom/bump-package)
    ("c" doom/help-package-config)
    ("u" doom/help-package-homepage))
  (setf (alist-get 'package embark-keymap-alist) #'+vertico/embark-doom-package-map)
  (map! (:map embark-file-map
         :desc "Open target with sudo" "s" #'doom/sudo-find-file
         (:when (featurep! :tools magit)
          :desc "Open magit-status of target" "g"   #'+vertico/embark-magit-status)
         (:when (featurep! :ui workspaces)
          :desc "Open in new workspace" "TAB" #'+vertico/embark-open-in-new-workspace))))


(use-package! marginalia
  :hook (doom-first-input . marginalia-mode)
  :init
  (map! :map minibuffer-local-map
        :desc "Cycle marginalia views" "M-A" #'marginalia-cycle)
  :config
  (when (featurep! +icons)
    (add-hook 'marginalia-mode-hook #'all-the-icons-completion-marginalia-setup))
  (advice-add #'marginalia--project-root :override #'doom-project-root)
  (pushnew! marginalia-command-categories
            ;; HACK temporarily disabled until #5494 is fixed
            ;;'(+default/find-file-under-here. file)
            ;;'(doom/find-file-in-emacsd . project-file)
            ;;'(doom/find-file-in-other-project . project-file)
            ;;'(doom/find-file-in-private-config . file)
            '(doom/describe-active-minor-mode . minor-mode)
            '(flycheck-error-list-set-filter . builtin)
            '(persp-switch-to-buffer . buffer)
            '(projectile-find-file . project-file)
            '(projectile-recentf . project-file)
            '(projectile-switch-to-buffer . buffer)
            '(projectile-switch-project . project-file)))


(use-package! embark-consult
  :after (embark consult)
  :config
  (add-hook 'embark-collect-mode-hook #'consult-preview-at-point-mode))


(use-package! wgrep
  :commands wgrep-change-to-wgrep-mode
  :config (setq wgrep-auto-save-buffer t))
