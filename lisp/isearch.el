;;; isearch.el --- incremental search minor mode -*- lexical-binding: t -*-

;; Copyright (C) 1992-1997, 1999-2025 Free Software Foundation, Inc.

;; Author: Daniel LaLiberte <liberte@cs.uiuc.edu>
;; Maintainer: emacs-devel@gnu.org
;; Keywords: matching
;; Package: emacs

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Instructions

;; For programmed use of isearch-mode, e.g. calling `isearch-forward',
;; isearch-mode behaves modally and does not return until the search
;; is completed.  It uses a recursive-edit to behave this way.

;; The key bindings active within isearch-mode are defined below in
;; `isearch-mode-map'.  Also see minibuffer-local-isearch-map
;; for bindings active during `isearch-edit-string'.

;; isearch-mode should work even if you switch windows with the mouse,
;; in which case isearch-mode is terminated automatically before the
;; switch.

;; The search ring and completion commands automatically put you in
;; the minibuffer to edit the string.  This gives you a chance to
;; modify the search string before executing the search.  There are
;; three commands to terminate the editing: C-s and C-r exit the
;; minibuffer and search forward and reverse respectively, while C-m
;; exits and searches in the last search direction.

;; Exiting immediately from isearch uses isearch-edit-string instead
;; of nonincremental-search, if `search-nonincremental-instead' is non-nil.
;; The name of this option should probably be changed if we decide to
;; keep the behavior.  No point in forcing nonincremental search until
;; the last possible moment.

;;; Code:

(eval-when-compile (require 'cl-lib))
(eval-when-compile (require 'subr-x))

;; Some additional options and constants.

(defgroup isearch nil
  "Incremental search minor mode."
  :link '(emacs-commentary-link "isearch")
  :link '(custom-manual "(emacs)Incremental Search")
  :prefix "isearch-"
  :prefix "search-"
  :group 'matching)


(defcustom search-exit-option t
  "Defines what control characters do in incremental search.
If t, random control and meta characters terminate the search
and are then executed normally.
If `edit', edit the search string instead of exiting.
If `append', the characters which you type that are not interpreted by
the incremental search are simply appended to the search string.
If nil, run the command without exiting Isearch."
  :type '(choice (const :tag "Terminate incremental search" t)
                 (const :tag "Edit the search string" edit)
                 (const :tag "Append control characters to the search string" append)
                 (const :tag "Don't terminate incremental search" nil))
  :version "27.1")

(defcustom search-slow-window-lines 1
  "Number of lines in slow search display windows.
These are the short windows used during incremental search on slow terminals.
Negative means put the slow search window at the top (normally it's at bottom)
and the value is minus the number of lines."
  :type 'integer)

(defcustom search-slow-speed 1200
  "Highest terminal speed at which to use \"slow\" style incremental search.
This is the style where a one-line window is created to show the line
that the search has reached."
  :type 'integer)

(defcustom search-upper-case 'not-yanks
  "If non-nil, upper case chars disable case fold searching.
That is, upper and lower case chars must match exactly.
This applies no matter where the chars come from, but does not
apply to chars in regexps that are prefixed with `\\'.
If this value is `not-yanks', text yanked into the search string
in Isearch mode is always downcased."
  :type '(choice (const :tag "off" nil)
		 (const not-yanks)
		 (other :tag "on" t)))

(defcustom search-nonincremental-instead t
  "If non-nil, do a nonincremental search instead of exiting immediately.
This affects the behavior of `isearch-exit' and any key bound to that
command: if this variable is nil, `isearch-exit' always exits the search;
if the value is non-nil, and the search string is empty, `isearch-exit'
starts a nonincremental search instead.  (Actually, `isearch-edit-string'
is called to let you enter the search string, and RET terminates editing
and does a nonincremental search.)"
  :type 'boolean)

(defcustom search-whitespace-regexp "[ \t]+"
  "If non-nil, regular expression to match a sequence of whitespace chars.
When you enter a space or spaces in the incremental search, it
will match any sequence matched by this regexp.  As an exception,
spaces are treated normally in regexp incremental search if they
occur in a regexp construct like [...] or *, + or ?.

If the value is a string, it applies to both ordinary and
regexp incremental search.  If the value is nil, or
`isearch-lax-whitespace' is nil for ordinary incremental search, or
`isearch-regexp-lax-whitespace' is nil for regexp incremental search,
then each space you type matches literally, against one space.

You might want to use something like \"[ \\t\\r\\n]+\" instead.
In the Customization buffer, that is `[' followed by a space, a
tab, a carriage return (control-M), a newline, and `]+'.  Don't
add any capturing groups into this value; that can change the
numbering of existing capture groups in unexpected ways."
  :type '(choice (const :tag "Match Spaces Literally" nil)
                 (const :tag "Tabs and spaces" "[ \t]+")
                 (const :tag "Tabs, spaces and line breaks" "[ \t\n]+")
		 regexp)
  :version "28.1")

(defcustom search-invisible 'open
  "If t incremental search/query-replace can match hidden text.
A nil value means don't match invisible text.
When the value is `open', if the text matched is made invisible by
an overlay having a non-nil `invisible' property, and that overlay
has a non-nil property `isearch-open-invisible', then incremental
search will show the hidden text.  (This applies when using `outline.el'
and `hideshow.el'.)

To temporarily change the value for an active incremental search,
use \\<isearch-mode-map>\\[isearch-toggle-invisible].

See also the related option `isearch-hide-immediately'.

See also `reveal-mode' if you want overlays to automatically be opened
whenever point is in one of them."
  :type '(choice (const :tag "Match hidden text" t)
		 (const :tag "Open overlays" open)
		 (const :tag "Don't match hidden text" nil)))

(defcustom isearch-hide-immediately t
  "If non-nil, re-hide an invisible match right away.
This variable makes a difference when `search-invisible' is set to `open'.
If non-nil, invisible matches are re-hidden as soon as the match moves
off the invisible text surrounding the match.
If nil then do not re-hide opened invisible text when the match moves.
Whatever the value, all opened invisible text is hidden again after exiting
the search, with the exception of the last successful match, if any."
  :type 'boolean)

(defcustom isearch-resume-in-command-history nil
  "If non-nil, `isearch-resume' commands are added to the command history.
This allows you to resume earlier Isearch sessions through the
command history."
  :type 'boolean)

(defcustom isearch-wrap-pause t
  "Define the behavior of wrapping when there are no more matches.
When t (by default), signal an error when no more matches are found.
Then after repeating the search, wrap with `isearch-wrap-function'.
When `no', wrap immediately after reaching the last match.
When `no-ding', wrap immediately without flashing the screen.
When nil, never wrap, just stop at the last match.
With the values `no' and `no-ding' the search will try
to wrap around also on typing a character."
  :type '(choice (const :tag "Pause before wrapping" t)
                 (const :tag "No pause before wrapping" no)
                 (const :tag "No pause and no flashing" no-ding)
                 (const :tag "Disable wrapping" nil))
  :version "28.1")

(defcustom isearch-repeat-on-direction-change nil
  "Whether a direction change should move to another match.
When nil, the default, a direction change moves point to the other
end of the current search match.
When t, a direction change moves to another search match, if there
is one."
  :type '(choice (const :tag "Remain on the same match" nil)
                 (const :tag "Move to another match" t))
  :version "28.1")

(defvar isearch-mode-hook nil
  "Function(s) to call after starting up an incremental search.")

(defvar isearch-update-post-hook nil
  "Function(s) to call after isearch has found matches in the buffer.")

(defvar isearch-mode-end-hook nil
  "Function(s) to call after terminating an incremental search.
When these functions are called, `isearch-mode-end-hook-quit'
is non-nil if the user quits the search.")

(defvar isearch-mode-end-hook-quit nil
  "Non-nil while running `isearch-mode-end-hook' if the user quits the search.")

(defvar isearch-message-function nil
  "Function to call to display the search prompt.
If nil, use function `isearch-message'.")

(defvar isearch-wrap-function nil
  "Function to call to wrap the search when search is failed.
The function is called with no parameters, and would typically
move point.

If nil, move point to the beginning of the buffer for a forward
search, or to the end of the buffer for a backward search.")

(defvar isearch-push-state-function nil
  "Function to save a function restoring the mode-specific Isearch state
to the search status stack.")

(defvar isearch-filter-predicate #'isearch-filter-visible
  "Predicate to filter hits of Isearch and replace commands.
Isearch hits that don't satisfy the predicate will be skipped.
The value should be a function of two arguments; it will be
called with the positions of the start and the end of the text
matched by Isearch and replace commands.  If this function
returns nil, Isearch and replace commands will continue searching
without stopping at resp. replacing this match.
This function is expected to be careful not to clobber the match data.

If you use `add-function' to modify this variable, you can use the
`isearch-message-prefix' advice property to specify the prefix string
displayed in the search message.")

(defvar isearch-text-conversion-style nil
  "Value of `text-conversion-style' before Isearch mode
was enabled in this buffer.")

;; Search ring.

(defvar search-ring nil
  "List of search string sequences.")
(defvar regexp-search-ring nil
  "List of regular expression search string sequences.")

(defcustom search-ring-max 16
  "Maximum length of search ring before oldest elements are thrown away."
  :type 'integer)
(defcustom regexp-search-ring-max 16
  "Maximum length of regexp search ring before oldest elements are thrown away."
  :type 'integer)

(defvar search-ring-yank-pointer nil
  "Index in `search-ring' of last string reused.
It is nil if none yet.")
(defvar regexp-search-ring-yank-pointer nil
  "Index in `regexp-search-ring' of last string reused.
It is nil if none yet.")

(defcustom search-ring-update nil
  "Non-nil if advancing or retreating in the search ring should cause search.
Default value, nil, means edit the string instead."
  :type 'boolean)

(autoload 'char-fold-to-regexp "char-fold")

(defcustom search-default-mode nil
  "Default mode to use when starting isearch.
Value is nil, t, or a function.

If nil, default to literal searches (note that `case-fold-search'
and `isearch-lax-whitespace' may still be applied).\\<isearch-mode-map>
If t, default to regexp searches (as if typing \\[isearch-toggle-regexp] during
isearch).

If a function, use that function as an `isearch-regexp-function'.
Example functions (and the keys to toggle them during isearch)
are `word-search-regexp' \(\\[isearch-toggle-word]), `isearch-symbol-regexp'
\(\\[isearch-toggle-symbol]), and `char-fold-to-regexp' \(\\[isearch-toggle-char-fold])."
  ;; :type is set below by `isearch-define-mode-toggle'.
  :type '(choice (const :tag "Literal search" nil)
                 (const :tag "Regexp search" t)
                 (function :tag "Other"))
  :version "25.1")

;;; isearch highlight customization.

(defcustom search-highlight t
  "Non-nil means incremental search highlights the current match."
  :type 'boolean)

(defcustom search-highlight-submatches t
  "Whether to highlight regexp subexpressions of the current regexp match.
The faces used to do the highlights are named `isearch-group-1',
`isearch-group-2', etc.  (By default, only these 2 are defined.)
When there are more matches than faces, then faces are reused from the
beginning, in a cyclical manner, so the `isearch-group-1' face is
isreused for the third match.  If you want to use more distinctive colors,
you can define more of these faces using the same numbering scheme."
  :type 'boolean
  :version "28.1")

(defface isearch
  '((((class color) (min-colors 88) (background light))
     ;; The background must not be too dark, for that means
     ;; the character is hard to see when the cursor is there.
     (:background "magenta3" :foreground "lightskyblue1"))
    (((class color) (min-colors 88) (background dark))
     (:background "palevioletred2" :foreground "brown4"))
    (((class color) (min-colors 16))
     (:background "magenta4" :foreground "cyan1"))
    (((class color) (min-colors 8))
     (:background "magenta4" :foreground "cyan1"))
    (t (:inverse-video t)))
  "Face for highlighting Isearch matches."
  :group 'isearch
  :group 'basic-faces)
(defvar isearch-face 'isearch)

(defface isearch-fail
  '((((class color) (min-colors 88) (background light))
     (:background "RosyBrown1"))
    (((class color) (min-colors 88) (background dark))
     (:background "red4"))
    (((class color) (min-colors 16))
     (:background "red"))
    (((class color) (min-colors 8))
     (:background "red"))
    (((class color grayscale))
     :foreground "grey")
    (t (:inverse-video t)))
  "Face for highlighting failed part in Isearch echo-area message."
  :version "23.1")

(defcustom isearch-lazy-highlight t
  "Controls the lazy-highlighting during incremental search.
When non-nil, all text currently visible on the screen
matching the current search string is highlighted lazily
(see `lazy-highlight-initial-delay' and `lazy-highlight-interval').

When multiple windows display the current buffer, the
highlighting is displayed only on the selected window, unless
this variable is set to the symbol `all-windows'."
  :type '(choice (const :tag "Off" nil)
                 (const :tag "On, and applied to current window" t)
                 (const :tag "On, and applied to all windows" all-windows))
  :group 'lazy-highlight
  :group 'isearch)

(defcustom isearch-lazy-count nil
  "Show match numbers in the search prompt.
When both this option and `isearch-lazy-highlight' are non-nil,
show the current match number and the total number of matches
in the buffer (or its restriction), including all hidden matches."
  :type 'boolean
  :group 'lazy-count
  :group 'isearch
  :version "27.1")

;;; Lazy highlight customization.

(defgroup lazy-highlight nil
  "Lazy highlighting feature for matching strings."
  :prefix "lazy-highlight-"
  :version "21.1"
  :group 'isearch
  :group 'matching)

(defcustom lazy-highlight-cleanup t
  "Controls whether to remove extra highlighting after a search.
If this is nil, extra highlighting can be \"manually\" removed with
\\[lazy-highlight-cleanup]."
  :type 'boolean
  :group 'lazy-highlight)

(defcustom lazy-highlight-initial-delay 0.25
  "Seconds to wait before beginning to lazily highlight all matches.
This setting only has effect when the search string is less than
`lazy-highlight-no-delay-length' characters long."
  :type 'number
  :group 'lazy-highlight)

(defcustom lazy-highlight-no-delay-length 3
  "For search strings at least this long, lazy highlight starts immediately.
For shorter search strings, `lazy-highlight-initial-delay'
applies."
  :type 'integer
  :group 'lazy-highlight
  :version "28.1")

(defcustom lazy-highlight-interval 0 ; 0.0625
  "Seconds between lazily highlighting successive matches."
  :type 'number
  :group 'lazy-highlight)

(defcustom lazy-highlight-max-at-a-time nil ; 20 (bug#25751)
  "Maximum matches to highlight at a time (for `lazy-highlight').
Larger values may reduce Isearch's responsiveness to user input;
smaller values make matches highlight slowly.
A value of nil means highlight all matches shown on the screen."
  :type '(choice (const :tag "All" nil)
		 (integer :tag "Some"))
  :group 'lazy-highlight)

(defcustom lazy-highlight-buffer-max-at-a-time 200 ; 20 (bug#48581)
  "Maximum matches to highlight at a time (for `lazy-highlight-buffer').
Larger values may reduce Isearch's responsiveness to user input;
smaller values make matches highlight slowly.
A value of nil means highlight all matches in the buffer."
  :type '(choice (const :tag "All" nil)
		 (integer :tag "Some"))
  :group 'lazy-highlight
  :version "28.1")

(defcustom lazy-highlight-buffer nil
  "Controls the lazy-highlighting of the full buffer.
When non-nil, all text in the buffer matching the current search
string is highlighted lazily (see `lazy-highlight-initial-delay',
`lazy-highlight-interval' and `lazy-highlight-buffer-max-at-a-time').
This is useful when `lazy-highlight-cleanup' is customized to nil
and doesn't remove full-buffer highlighting after a search."
  :type 'boolean
  :group 'lazy-highlight
  :version "27.1")

(defface lazy-highlight
  '((((class color) (min-colors 88) (background light))
     (:background "paleturquoise" :distant-foreground "black"))
    (((class color) (min-colors 88) (background dark))
     (:background "paleturquoise4" :distant-foreground "white"))
    (((class color) (min-colors 16))
     (:background "turquoise3" :distant-foreground "white"))
    (((class color) (min-colors 8))
     (:background "turquoise3" :distant-foreground "white"))
    (t (:underline t)))
  "Face for lazy highlighting of matches other than the current one."
  :group 'lazy-highlight
  :group 'basic-faces)

;;; Lazy count customization.

(defgroup lazy-count nil
  "Lazy counting feature for reporting the number of matches."
  :prefix "lazy-count-"
  :version "27.1"
  :group 'isearch
  :group 'matching)

(defcustom lazy-count-prefix-format "%s/%s "
  "Format of the current/total number of matches for the prompt prefix."
  :type '(choice (const :tag "No prefix" nil)
                 (string :tag "Prefix format string" "%s/%s "))
  :group 'lazy-count
  :version "27.1")

(defcustom lazy-count-suffix-format nil
  "Format of the current/total number of matches for the prompt suffix."
  :type '(choice (const :tag "No suffix" nil)
                 (string :tag "Suffix format string" " [%s of %s]"))
  :group 'lazy-count
  :version "27.1")

(defvar lazy-count-invisible-format " (invisible %s)"
  "Format of the number of invisible matches for the prompt.
When invisible matches exist, their number is appended
after the total number of matches.  Display nothing when
this variable is nil.")


;; Define isearch help map.

(defvar isearch-help-map
  (let ((map (make-sparse-keymap)))
    (define-key map (char-to-string help-char) 'isearch-help-for-help)
    (define-key map [help] 'isearch-help-for-help)
    (define-key map [f1] 'isearch-help-for-help)
    (define-key map "?" 'isearch-help-for-help)
    (define-key map "b" 'isearch-describe-bindings)
    (define-key map "k" 'isearch-describe-key)
    (define-key map "m" 'isearch-describe-mode)
    (define-key map "q" 'help-quit)
    map)
  "Keymap for characters following the Help key for Isearch mode.")

(eval-when-compile (require 'help-macro))

(make-help-screen isearch-help-for-help-internal
  "Type a help option: [bkm] or ?"
  "You have typed %THIS-KEY%, the help character.  Type a Help option:
\(Type \\<isearch-help-map>\\[help-quit] to exit the Help command.)

  \\[isearch-describe-bindings]	Display all Isearch key bindings.
  \\[isearch-describe-key]	Display full documentation of Isearch key sequence.
  \\[isearch-describe-mode]	Display documentation of Isearch mode.

You can't type here other help keys available in the global help map,
but outside of this help window when you type them in Isearch mode,
they exit Isearch mode before displaying global help."
  isearch-help-map)

(defvar isearch--display-help-action '(nil (inhibit-same-window . t)))

(defun isearch-help-for-help ()
  "Display Isearch help menu."
  (interactive)
  (let ((display-buffer-overriding-action isearch--display-help-action))
    (isearch-help-for-help-internal))
  (isearch-update))

(defun isearch-describe-bindings ()
  "Show a list of all keys defined in Isearch mode, and their definitions.
This is like `describe-bindings', but displays only Isearch keys."
  (interactive)
  (let ((display-buffer-overriding-action isearch--display-help-action))
    (with-help-window "*Help*"
      (with-current-buffer standard-output
	(princ "Isearch Mode Bindings:\n")
	(princ (substitute-command-keys "\\{isearch-mode-map}"))))))

(defun isearch-describe-key ()
  "Display documentation of the function invoked by isearch key."
  (interactive)
  (let ((display-buffer-overriding-action isearch--display-help-action))
    (call-interactively 'describe-key))
  (when isearch-mode (isearch-update)))

(defun isearch-describe-mode ()
  "Display documentation of Isearch mode."
  (interactive)
  (let ((display-buffer-overriding-action isearch--display-help-action))
    (describe-function 'isearch-forward))
  (when isearch-mode (isearch-update)))


;; Define isearch-mode keymap.

(defun isearch-tmm-menubar ()
  "Run `tmm-menubar' while `isearch-mode' is enabled."
  (interactive)
  (require 'tmm)
  (run-hooks 'menu-bar-update-hook)
  (let ((command nil))
    (let ((menu-bar (menu-bar-keymap)))
      (with-isearch-suspended
       (setq command (let ((isearch-mode t)) ; Show bindings from
                                             ; `isearch-mode-map' in
                                             ; tmm's prompt.
                       (tmm-prompt menu-bar nil nil t)))))
    (call-interactively command)))

(defvar isearch-menu-bar-commands
  '(isearch-tmm-menubar tmm-menubar menu-bar-open mouse-minor-mode-menu)
  "List of commands that can open a menu during Isearch.")

;; Note: Before adding more key bindings to this map, please keep in
;; mind that any unbound key exits Isearch and runs the command bound
;; to it in the local or global map.  So in effect every key unbound
;; in this map is implicitly bound.
(defvar isearch-mode-map
  (let ((i 0)
	(map (make-keymap)))
    (or (char-table-p (nth 1 map))
	(error "The initialization of isearch-mode-map must be updated"))
    ;; Make all multibyte characters search for themselves.
    (set-char-table-range (nth 1 map) (cons #x100 (max-char))
			  'isearch-printing-char)

    ;; Single-byte printing chars extend the search string by default.
    (setq i ?\s)
    (while (< i 256)
      (define-key map (vector i) 'isearch-printing-char)
      (setq i (1+ i)))

    ;; To handle local bindings with meta char prefix keys, define
    ;; another full keymap.  This must be done for any other prefix
    ;; keys as well, one full keymap per char of the prefix key.  It
    ;; would be simpler to disable the global keymap, and/or have a
    ;; default local key binding for any key not otherwise bound.
    (let ((meta-map (make-sparse-keymap)))
      (define-key map (char-to-string meta-prefix-char) meta-map))

    ;; Several non-printing chars change the searching behavior.
    (define-key map "\C-s" 'isearch-repeat-forward)
    (define-key map "\C-r" 'isearch-repeat-backward)
    ;; Define M-C-s and M-C-r like C-s and C-r so that the same key
    ;; combinations can be used to repeat regexp isearches that can
    ;; be used to start these searches.
    (define-key map "\M-\C-s" 'isearch-repeat-forward)
    (define-key map "\M-\C-r" 'isearch-repeat-backward)
    (define-key map "\177" 'isearch-delete-char)
    (define-key map [backspace] 'undefined) ;bug#20466.
    (define-key map "\C-g" 'isearch-abort)

    ;; This assumes \e is the meta-prefix-char.
    (or (= ?\e meta-prefix-char)
	(error "Inconsistency in isearch.el"))
    (define-key map "\e\e\e" 'isearch-cancel)

    (define-key map "\C-q" 'isearch-quote-char)

    (define-key map "\r" 'isearch-exit)
    (define-key map [return] 'isearch-exit)
    (define-key map "\C-j" 'isearch-printing-char)
    (define-key map "\t" 'isearch-printing-char)
    (define-key map [?\S-\ ] 'isearch-printing-char)

    (define-key map    "\C-w" 'isearch-yank-word-or-char)
    (define-key map "\M-\C-w" 'isearch-yank-symbol-or-char)
    (define-key map "\M-\C-d" 'isearch-del-char)
    (define-key map "\M-\C-y" 'isearch-yank-char)
    (define-key map    "\C-y" 'isearch-yank-kill)
    (define-key map "\M-\C-z" 'isearch-yank-until-char)
    (define-key map "\M-s\C-e" 'isearch-yank-line)

    (define-key map "\M-s\M-<" 'isearch-beginning-of-buffer)
    (define-key map "\M-s\M->" 'isearch-end-of-buffer)

    (define-key map (char-to-string help-char) isearch-help-map)
    (define-key map [help] isearch-help-map)
    (define-key map [f1] isearch-help-map)

    (define-key map "\M-n" 'isearch-ring-advance)
    (define-key map "\M-p" 'isearch-ring-retreat)
    (define-key map "\M-y" 'isearch-yank-pop-only)

    (define-key map "\M-\t" 'isearch-complete)

    ;; Frame events should exit the search, because such frame events
    ;; as `switch-frame’ and `delete-frame’ change the current buffer.
    ;; See Bug#41338 for details.
    (define-key map [switch-frame] nil)
    (define-key map [delete-frame] nil)
    (define-key map [iconify-frame] nil)
    (define-key map [make-frame-visible] nil)
    (define-key map [mouse-movement] nil)
    (define-key map [language-change] nil)

    ;; For searching multilingual text.
    (define-key map "\C-\\" 'isearch-toggle-input-method)
    (define-key map "\C-^" 'isearch-toggle-specified-input-method)
    (define-key map "\C-x\\" 'isearch-transient-input-method)

    ;; People expect to be able to paste with the mouse.
    (define-key map [mouse-2] #'isearch-mouse-2)
    (define-key map [down-mouse-2] nil)
    (define-key map [xterm-paste] #'isearch-xterm-paste)

    ;; Some bindings you may want to put in your isearch-mode-hook.
    ;; Suggest some alternates...
    (define-key map "\M-c" 'isearch-toggle-case-fold)
    (define-key map "\M-r" 'isearch-toggle-regexp)
    (define-key map "\M-e" 'isearch-edit-string)

    (put 'isearch-toggle-case-fold :advertised-binding "\M-sc")
    (put 'isearch-toggle-regexp    :advertised-binding "\M-sr")
    (put 'isearch-edit-string      :advertised-binding "\M-se")

    (define-key map "\M-se" 'isearch-edit-string)
    ;; More toggles defined by `isearch-define-mode-toggle'.

    (define-key map [?\M-%] 'isearch-query-replace)
    (define-key map [?\C-\M-%] 'isearch-query-replace-regexp)
    (define-key map "\M-so" 'isearch-occur)
    (define-key map "\M-shr" 'isearch-highlight-regexp)
    (define-key map "\M-shl" 'isearch-highlight-lines-matching-regexp)

    ;; The key translations defined in the C-x 8 prefix should add
    ;; characters to the search string.  See iso-transl.el.
    (define-key map "\C-x8\r" 'isearch-char-by-name)
    (define-key map "\C-x8e\r" 'isearch-emoji-by-name)
    map)
  "Keymap for `isearch-mode'.")

(easy-menu-define isearch-menu-bar-map  isearch-mode-map
  "Menu for `isearch-mode'."
  `("Isearch"
    ["Cancel search" isearch-cancel
     :help "Cancel current search and return to starting point"
     :filter ,(lambda (binding)
               (if isearch-success 'isearch-abort binding))]
    ["Remove characters not found" isearch-abort
     :help "Quit current search"
     :visible (not isearch-success)]
    ["Finish search" isearch-exit
     :help "Finish search leaving point where it is"
     :visible (not (string-equal isearch-string ""))]
    ["Nonincremental search" isearch-exit
     :help "Start nonincremental search"
     :visible (string-equal isearch-string "")]
    ["Repeat search forward" isearch-repeat-forward
     :help "Repeat current search forward"]
    ["Repeat search backward" isearch-repeat-backward
     :help "Repeat current search backward"]
    ["Go to first match" isearch-beginning-of-buffer
     :help "Go to first occurrence of current search string"]
    ["Go to last match" isearch-end-of-buffer
     :help "Go to last occurrence of current search string"]
    ["Undo last input item" isearch-delete-char
     :help "Undo the effect of the last Isearch command"]
    ["Delete last char from search string" isearch-del-char
     :help "Delete last character from search string"]
    ["Edit next search string" isearch-ring-advance
     :help "Edit next search string in Isearch history"]
    ["Edit previous search string" isearch-ring-retreat
     :help "Edit previous search string in Isearch history"]
    ["Edit current search string" isearch-edit-string
     :help "Edit current search string"]
    ("Yank on search string"
     ["Char" isearch-yank-char
      :help "Yank char at point on search string"]
     ["Word/char"
      isearch-yank-word-or-char
      :help "Yank next word or char on search string"]
     ["Symbol/char"
      isearch-yank-symbol-or-char
      :help "Yank next symbol or char on search string"]
     ["Rest of line" isearch-yank-line
      :help "Yank the rest of the current line on search string"]
     ["Until char..." isearch-yank-until-char
      :help "Yank from point to specified character into search string"]
     ["Current kill" isearch-yank-kill
      :help "Append current kill to search string"]
     ["Previous kill" isearch-yank-pop-only
      :help "Replace previous yanked kill on search string"])
    "---"
    ["Lax whitespace matching" isearch-toggle-lax-whitespace
     :help "Lax whitespace matching"
     :style toggle
     :selected isearch-lax-whitespace]
    ["Case folding matching" isearch-toggle-case-fold
     :help "Case folding matching"
     :style toggle
     :selected isearch-case-fold-search]
    ["Character folding matching" isearch-toggle-char-fold
     :help "Character folding matching"
     :style toggle
     :selected (eq isearch-regexp-function
                   'char-fold-to-regexp)]
    ["Invisible text matching" isearch-toggle-invisible
     :help "Invisible text matching"
     :style toggle
     :selected isearch-invisible]
    ["Regexp matching" isearch-toggle-regexp
     :help "Regexp matching"
     :style toggle
     :selected isearch-regexp]
    ["Symbol matching" isearch-toggle-symbol
     :help "Symbol matching"
     :style toggle
     :selected (eq isearch-regexp-function
                   'isearch-symbol-regexp)]
    ["Word matching" isearch-toggle-word
     :help "Word matching"
     :style toggle
     :selected (eq isearch-regexp-function 'word-search-regexp)]
    "---"
    ["Search for literal char" isearch-quote-char
     :help "Search for literal char"]
    ["Search for char by name" isearch-char-by-name
     :help "Search for character by name"]
    ["Search for Emoji by name" isearch-emoji-by-name
     :help "Search for Emoji by its Unicode name"]
    "---"
    ["Toggle input method" isearch-toggle-input-method
     :help "Toggle input method for search"]
    ["Turn on specific input method" isearch-toggle-specified-input-method
     :help "Turn on specific input method for search"]
    ["Turn on transient input method" isearch-transient-input-method
     :help "Turn on transient input method for search"]
    "---"
    ["Highlight all matches for search string" isearch-highlight-regexp
     :help "Highlight all matches for current search string"]
    ["Show all matches for search string" isearch-occur
     :help "Show all matches for current search string"]
    ["Replace search string" isearch-query-replace
     :help "Replace matches for current search string"]
    ["Replace search string as regexp" isearch-query-replace-regexp
     :help "Replace matches for current search string as regexp"]
    "---"
    ["Complete current search string" isearch-complete
     :help "Complete current search string over search history"]))

(defvar isearch-tool-bar-old-map nil
  "Variable holding the old local value of `tool-bar-map', if any.")

(defun isearch-tool-bar-image (image-name)
  "Return an image specification for IMAGE-NAME."
  (eval (tool-bar--image-expression image-name)))

(defvar isearch-tool-bar-map
  (let ((map (make-sparse-keymap)))
    (define-key map [isearch-describe-mode]
      (list 'menu-item "Help" 'isearch-describe-mode
            :help "Get help for Isearch"
            :image '(isearch-tool-bar-image "help")))
    (define-key map [isearch-occur]
      (list 'menu-item "Show hits" 'isearch-occur
            :help "Show each search hit"
            :image '(isearch-tool-bar-image "index")))
    (define-key map [isearch-query-replace]
      (list 'menu-item "Replace" 'isearch-query-replace
            :help "Replace search string"
            :image '(isearch-tool-bar-image "search-replace")))
    (define-key map [isearch-delete-char]
      (list 'menu-item "Undo" 'isearch-delete-char
            :help "Undo last input item"
            :image '(isearch-tool-bar-image "undo")))
    (define-key map [isearch-exit]
      (list 'menu-item "Finish" 'isearch-exit
            :help "Finish search leaving point where it is"
            :image '(isearch-tool-bar-image "exit")
            :visible '(not (string-equal isearch-string ""))))
    (define-key map [isearch-cancel]
      (list 'menu-item "Abort" 'isearch-cancel
            :help "Abort search"
            :image '(isearch-tool-bar-image "close")
            :filter (lambda (binding)
                      (if isearch-success 'isearch-abort binding))))
    (define-key map [isearch-repeat-forward]
      (list 'menu-item "Repeat forward" 'isearch-repeat-forward
            :help "Repeat search forward"
            :image '(isearch-tool-bar-image "right-arrow")))
    (define-key map [isearch-repeat-backward]
      (list 'menu-item "Repeat backward" 'isearch-repeat-backward
            :help "Repeat search backward"
            :image '(isearch-tool-bar-image "left-arrow")))
    map))

(defvar-keymap minibuffer-local-isearch-map
  :doc "Keymap for editing Isearch strings in the minibuffer."
  :parent minibuffer-local-map
  "RET"     #'exit-minibuffer
  "M-TAB"   #'isearch-complete-edit
  "C-s"     #'isearch-forward-exit-minibuffer
  "C-r"     #'isearch-reverse-exit-minibuffer
  "C-f"     #'isearch-yank-char-in-minibuffer
  "<right>" #'isearch-yank-char-in-minibuffer)

;; Internal variables declared globally for byte-compiler.
;; These are all set with setq while isearching
;; and bound locally while editing the search string.

(defvar isearch-forward nil)	; Searching in the forward direction.
(defvar isearch-regexp nil)	; Searching for a regexp.
;; We still support setting this to t for backwards compatibility.
(define-obsolete-variable-alias 'isearch-word
  'isearch-regexp-function "25.1")
(defvar isearch-regexp-function nil
  "Regexp-based search mode for words/symbols.
If non-nil, a function to convert a search string to a regexp
used by regexp search functions.

The function should accept 1 or 2 arguments: the original string
to convert, and a flag, whose non-nil value means the match
doesn't have to start or end on a word boundary.  The function
should return the corresponding regexp, a string.

The symbol property `isearch-message-prefix' put on this function
specifies the prefix string displayed in the search message.

Existing functions you could use as values are `word-search-regexp',
`isearch-symbol-regexp', and `char-fold-to-regexp'.

This variable is set and changed during isearch.  To change the
default behavior used for searches, see `search-default-mode'
instead.")

(defcustom isearch-lax-whitespace t
  "If non-nil, a space will match a sequence of whitespace chars.
When you enter a space or spaces in ordinary incremental search, it
will match any sequence matched by the regexp defined by the variable
`search-whitespace-regexp'.  If the value is nil, each space you type
matches literally, against one space.  You can toggle the value of this
variable by the command `isearch-toggle-lax-whitespace', usually bound to
`M-s SPC' during isearch."
  :type 'boolean
  :group 'isearch
  :version "25.1")

(defvar isearch-regexp-lax-whitespace nil
  "If non-nil, a space will match a sequence of whitespace chars.
When you enter a space or spaces in regexp incremental search, it
will match any sequence matched by the regexp defined by the variable
`search-whitespace-regexp'.  If the value is nil, each space you type
matches literally, against one space.  You can toggle the value of this
variable by the command `isearch-toggle-lax-whitespace', usually bound to
`M-s SPC' during isearch.")

(defvar isearch-cmds nil
  "Stack of search status elements.
Each element is an `isearch--state' struct where the slots are
 [STRING MESSAGE POINT SUCCESS FORWARD OTHER-END WORD/REGEXP-FUNCTION
  ERROR WRAPPED BARRIER CASE-FOLD-SEARCH POP-FUN MATCH-DATA]")

(defvar isearch-string "")  ; The current search string.
(defvar isearch-message "") ; text-char-description version of isearch-string

(defvar isearch-message-prefix-add nil) ; Additional text for the message prefix
(defvar isearch-message-suffix-add nil) ; Additional text for the message suffix

(defvar isearch-success t)	; Searching is currently successful.
(defvar isearch-error nil)	; Error message for failed search.
(defvar isearch-other-end nil)	; Start (end) of match if forward (backward).
(defvar isearch-wrapped nil)	; Searching restarted from the top (bottom).
(defvar isearch-barrier 0
  "Recorded minimum/maximal point for the current search.")
(defvar isearch-just-started nil)
(defvar isearch-start-hscroll 0)	; hscroll when starting the search.
(defvar isearch-match-data nil)         ; match-data of regexp-based search

;; case-fold-search while searching.
;;   either nil, t, or 'yes.  'yes means the same as t except that mixed
;;   case in the search string is ignored.
(defvar isearch-case-fold-search nil)

;; search-invisible while searching.
;;   either nil, t, or 'open.  'open means the same as t except that
;;   opens hidden overlays.
(defvar isearch-invisible search-invisible)

(defvar isearch-last-case-fold-search nil)

;; Used to save default value while isearch is active
(defvar isearch-original-minibuffer-message-timeout nil)

(defvar isearch-adjusted nil)
(defvar isearch-slow-terminal-mode nil)
;; If t, using a small window.
(defvar isearch-small-window nil)
(defvar isearch-opoint 0)
;; The window configuration active at the beginning of the search.
(defvar isearch-window-configuration nil)

;; Flag to indicate a yank occurred, so don't move the cursor.
(defvar isearch-yank-flag nil)

;; A function to be called after each input character is processed.
;; (It is not called after characters that exit the search.)
;; It is only set from an optional argument to `isearch-mode'.
(defvar isearch-op-fun nil)

;;  Is isearch-mode in a recursive edit for modal searching.
(defvar isearch-recursive-edit nil)

;; Should isearch be terminated after doing one search?
(defvar isearch-nonincremental nil)

;; New value of isearch-nonincremental after isearch-edit-string.
(defvar isearch-new-nonincremental nil)

;; New value of isearch-forward after isearch-edit-string.
(defvar isearch-new-forward nil)

;; Accumulate here the overlays opened during searching.
(defvar isearch-opened-overlays nil)

;; Non-nil if the string exists but is invisible.
(defvar isearch-hidden nil)

;; The value of input-method-function when isearch is invoked.
(defvar isearch-input-method-function nil)

(defvar isearch--saved-local-map nil)
(defvar isearch--saved-overriding-local-map nil)

;; Minor-mode-alist changes - kind of redundant with the
;; echo area, but if isearching in multiple windows, it can be useful.
;; Also, clicking the mode-line indicator pops up
;; `isearch-menu-bar-map'.

(or (assq 'isearch-mode minor-mode-alist)
    (nconc minor-mode-alist
	   (list '(isearch-mode isearch-mode))))

;; We add an entry for `isearch-mode' to `minor-mode-map-alist' so
;; that `isearch-menu-bar-map' can show on the menu bar.
(or (assq 'isearch-mode minor-mode-map-alist)
    (nconc minor-mode-map-alist
           (list (cons 'isearch-mode isearch-mode-map))))

(defvar-local isearch-mode nil) ;; Name of the minor mode, if non-nil.

(define-key global-map "\C-s" 'isearch-forward)
(define-key esc-map    "\C-s" 'isearch-forward-regexp)
(define-key global-map "\C-r" 'isearch-backward)
(define-key esc-map    "\C-r" 'isearch-backward-regexp)
(define-key search-map    "w" 'isearch-forward-word)
(define-key search-map    "_" 'isearch-forward-symbol)
(define-key search-map    "." 'isearch-forward-symbol-at-point)
(define-key search-map "\M-." 'isearch-forward-thing-at-point)

;; Entry points to isearch-mode.

(defun isearch-forward (&optional regexp-p no-recursive-edit)
  "Do incremental search forward.
With a prefix argument, do an incremental regular expression search instead.
\\<isearch-mode-map>
As you type characters, they add to the search string and are found.
The following non-printing keys are bound in `isearch-mode-map'.

Type \\[isearch-delete-char] to cancel last input item from end of search string.
Type \\[isearch-exit] to exit, leaving point at location found.
Type LFD (\\`C-j') to match end of line.
Type \\[isearch-repeat-forward] to search again forward,\
 \\[isearch-repeat-backward] to search again backward.
Type \\[isearch-beginning-of-buffer] to go to the first match,\
 \\[isearch-end-of-buffer] to go to the last match.
Type \\[isearch-yank-word-or-char] to yank next word or character in buffer
  onto the end of the search string, and search for it.
Type \\[isearch-del-char] to delete character from end of search string.
Type \\[isearch-yank-char] to yank char from buffer onto end of search\
 string and search for it.
Type \\[isearch-yank-until-char] to yank from point until the next instance of a
 specified character onto end of search string and search for it.
Type \\[isearch-yank-line] to yank rest of line onto end of search string\
 and search for it.
Type \\[isearch-yank-kill] to yank the last string of killed text.
Type \\[isearch-yank-pop-only] to replace string just yanked into search prompt
 with string killed before it.
Type \\[isearch-quote-char] to quote control character to search for it.
Type \\[isearch-char-by-name] to add a character to search by Unicode name,\
 with completion.
\\[isearch-abort] while searching or when search has failed cancels input\
 back to what has
 been found successfully.
\\[isearch-abort] when search is successful aborts and moves point to\
 starting point.

If you try to exit with the search string still empty, it invokes
 nonincremental search.

Type \\[isearch-toggle-case-fold] to toggle search case-sensitivity.
Type \\[isearch-toggle-invisible] to toggle search in invisible text.
Type \\[isearch-toggle-regexp] to toggle regular-expression mode.
Type \\[isearch-toggle-word] to toggle word mode.
Type \\[isearch-toggle-symbol] to toggle symbol mode.
Type \\[isearch-toggle-char-fold] to toggle character folding.

Type \\[isearch-toggle-lax-whitespace] to toggle whitespace matching.
In incremental searches, a space or spaces normally matches any whitespace
defined by the variable `search-whitespace-regexp'; see also the variables
`isearch-lax-whitespace' and `isearch-regexp-lax-whitespace'.

Type \\[isearch-edit-string] to edit the search string in the minibuffer.

Also supported is a search ring of the previous 16 search strings.
Type \\[isearch-ring-advance] to search for the next item in the search ring.
Type \\[isearch-ring-retreat] to search for the previous item in the search\
 ring.
Type \\[isearch-complete] to complete the search string using the search ring.

Type \\[isearch-query-replace] to run `query-replace' with string to\
 replace from last search string.
Type \\[isearch-query-replace-regexp] to run `query-replace-regexp'\
 with the last search string.
Type \\[isearch-occur] to run `occur' that shows\
 the last search string.
Type \\[isearch-highlight-regexp] to run `highlight-regexp'\
 that highlights the last search string.
Type \\[isearch-highlight-lines-matching-regexp] to run\
 `highlight-lines-matching-regexp' that highlights lines
 matching the last search string.

Type \\[isearch-describe-bindings] to display all Isearch key bindings.
Type \\[isearch-describe-key] to display documentation of Isearch key.
Type \\[isearch-describe-mode] to display documentation of Isearch mode.

If an input method is turned on in the current buffer, that input
method is also active while you are typing characters to search.
To toggle the input method, type \\[isearch-toggle-input-method].  \
It also toggles the input
method in the current buffer.

To use a different input method for searching, type \
\\[isearch-toggle-specified-input-method],
and specify an input method you want to use.

To activate a transient input method, type \\[isearch-transient-input-method].

The above keys, bound in `isearch-mode-map', are often controlled by
 options; do \\[apropos] on search-.* to find them.
Other control and meta characters terminate the search
 and are then executed normally (depending on `search-exit-option').
Likewise for function keys and mouse button events.

If this function is called non-interactively with a nil NO-RECURSIVE-EDIT,
it does not return to the calling function until the search is done.
See the function `isearch-mode' for more information."

  (interactive "P\np")
  (isearch-mode t (not (null regexp-p)) nil (not no-recursive-edit)))

(defun isearch-forward-regexp (&optional not-regexp no-recursive-edit)
  "Do incremental search forward for regular expression.
With a prefix argument, do a regular string search instead.
Like ordinary incremental search except that your input is treated
as a regexp.  See the command `isearch-forward' for more information.

In incremental searches, a space or spaces normally matches any
whitespace defined by the variable `search-whitespace-regexp'.
To search for a literal space and nothing else, enter \\`C-q SPC'.
To toggle whitespace matching, use `isearch-toggle-lax-whitespace',
usually bound to \\`M-s SPC' during isearch.
This command does not support character folding."
  (interactive "P\np")
  (isearch-mode t (null not-regexp) nil (not no-recursive-edit)))

(defun isearch-forward-word (&optional not-word no-recursive-edit)
  "Do incremental search forward for a sequence of words.
With a prefix argument, do a regular string search instead.
Like ordinary incremental search except that your input is treated
as a sequence of words without regard to how the words are separated.
See the command `isearch-forward' for more information.
This command does not support character folding, and lax space matching
has no effect on it."
  (interactive "P\np")
  (isearch-mode t nil nil (not no-recursive-edit) (null not-word)))

(defun isearch-forward-symbol (&optional _not-symbol no-recursive-edit)
  "Do incremental search forward for a symbol.
The prefix argument is currently unused.
Like ordinary incremental search except that your input is treated
as a symbol surrounded by symbol boundary constructs \\_< and \\_>.
See the command `isearch-forward' for more information.
This command does not support character folding, and lax space matching
has no effect on it."
  (interactive "P\np")
  (isearch-mode t nil nil (not no-recursive-edit) 'isearch-symbol-regexp))

(defun isearch-backward (&optional regexp-p no-recursive-edit)
  "Do incremental search backward.
With a prefix argument, do a regular expression search instead.
See the command `isearch-forward' for more information."
  (interactive "P\np")
  (isearch-mode nil (not (null regexp-p)) nil (not no-recursive-edit)))

(defun isearch-backward-regexp (&optional not-regexp no-recursive-edit)
  "Do incremental search backward for regular expression.
With a prefix argument, do a regular string search instead.
Like ordinary incremental search except that your input is treated
as a regexp.  See the command `isearch-forward-regexp' for more information."
  (interactive "P\np")
  (isearch-mode nil (null not-regexp) nil (not no-recursive-edit)))

(defun isearch-forward-symbol-at-point (&optional arg)
  "Do incremental search forward for a symbol found near point.
Like ordinary incremental search except that the symbol found at point
is added to the search string initially as a regexp surrounded
by symbol boundary constructs \\_< and \\_>.
See the command `isearch-forward-symbol' for more information.
With a prefix argument, search for ARGth symbol forward if ARG is
positive, or search for ARGth symbol backward if ARG is negative."
  (interactive "P")
  (isearch-forward-symbol nil 1)
  (let ((bounds (find-tag-default-bounds))
        (count (and arg (prefix-numeric-value arg))))
    (cond
     (bounds
      (when (< (car bounds) (point))
	(goto-char (car bounds)))
      (isearch-yank-string
       (buffer-substring-no-properties (car bounds) (cdr bounds)))
      (when count
        (isearch-repeat-forward count)))
     (t
      (setq isearch-error "No symbol at point")
      (isearch-push-state)
      (isearch-update)))))

(defcustom isearch-forward-thing-at-point '(region url symbol sexp)
  "A list of symbols to try to get the \"thing\" at point.
Each element of the list should be one of the symbols supported by
`bounds-of-thing-at-point'.  This variable is used by the command
`isearch-forward-thing-at-point' to yank the initial \"thing\"
as text to the search string."
  :type '(repeat (symbol :tag "Thing symbol"))
  :group 'isearch
  :version "28.1")

(defun isearch-forward-thing-at-point ()
  "Do incremental search forward for the \"thing\" found near point.
Like ordinary incremental search except that the \"thing\" found at point
is added to the search string initially.  The \"thing\" is defined by
`bounds-of-thing-at-point'.  You can customize the variable
`isearch-forward-thing-at-point' to define a list of symbols to try
to find a \"thing\" at point.  For example, when the list contains
the symbol `region' and the region is active, then text from the
active region is added to the search string."
  (interactive)
  (isearch-forward nil 1)
  (let ((bounds (seq-some (lambda (thing)
                            (bounds-of-thing-at-point thing))
                          isearch-forward-thing-at-point)))
    (cond
     (bounds
      (when (use-region-p)
        (deactivate-mark))
      (when (< (car bounds) (point))
	(goto-char (car bounds)))
      (isearch-yank-string
       (buffer-substring-no-properties (car bounds) (cdr bounds))))
     (t
      (setq isearch-error "No thing at point")
      (isearch-push-state)
      (isearch-update)))))


;; isearch-mode only sets up incremental search for the minor mode.
;; All the work is done by the isearch-mode commands.

;; Not used yet:
;;(defvar isearch-commands '(isearch-forward isearch-backward
;;			     isearch-forward-regexp isearch-backward-regexp)
;;  "List of commands for which isearch-mode does not recursive-edit.")

(declare-function set-text-conversion-style "textconv.c")

(defun isearch-mode (forward &optional regexp op-fun recursive-edit regexp-function)
  "Start Isearch minor mode.
It is called by the function `isearch-forward' and other related functions.

The non-nil arg FORWARD means searching in the forward direction.

The non-nil arg REGEXP does an incremental regular expression search.

The arg OP-FUN is a function to be called after each input character
is processed.  (It is not called after characters that exit the search.)

When the arg RECURSIVE-EDIT is non-nil, this function behaves modally and
does not return to the calling function until the search is completed.
To behave this way it enters a recursive edit and exits it when done
isearching.

Also display the on-screen keyboard if necessary.

The arg REGEXP-FUNCTION, if non-nil, should be a function.  It is
used to set the value of `isearch-regexp-function'."

  ;; Initialize global vars.
  (setq isearch-forward forward
	isearch-regexp (or regexp
                           (and (not regexp-function)
                                (eq search-default-mode t)))
	isearch-regexp-function (or regexp-function
                                    (and (functionp search-default-mode)
                                         (not regexp)
                                         search-default-mode))
	isearch-op-fun op-fun
	isearch-last-case-fold-search isearch-case-fold-search
	isearch-case-fold-search case-fold-search
	isearch-invisible search-invisible
	isearch-string ""
	isearch-message ""
	isearch-cmds nil
	isearch-success t
	isearch-wrapped nil
	isearch-barrier (point)
	isearch-adjusted nil
	isearch-yank-flag nil
	isearch-error nil
	isearch-slow-terminal-mode (and (<= baud-rate search-slow-speed)
					(> (window-height)
					   (* 4
					      (abs search-slow-window-lines))))
	isearch-other-end nil
	isearch-small-window nil
	isearch-just-started t
	isearch-start-hscroll (window-hscroll)
	isearch-match-data nil

	isearch-opoint (point)
	search-ring-yank-pointer nil
	isearch-opened-overlays nil
	isearch-input-method-function input-method-function
	regexp-search-ring-yank-pointer nil

	isearch-pre-scroll-point nil
	isearch-pre-move-point nil

	isearch-lazy-count-current nil
	isearch-lazy-count-total nil
	isearch-lazy-count-invisible nil

	;; Save the original value of `minibuffer-message-timeout', and
	;; set it to nil so that isearch's messages don't get timed out.
	isearch-original-minibuffer-message-timeout minibuffer-message-timeout
	minibuffer-message-timeout nil)

  (if (local-variable-p 'tool-bar-map)
      (setq isearch-tool-bar-old-map tool-bar-map))
  (setq-local tool-bar-map isearch-tool-bar-map)

  ;; We must bypass input method while reading key.  When a user type
  ;; printable character, appropriate input method is turned on in
  ;; minibuffer to read multibyte characters.
  (setq-local input-method-function nil)

  (looking-at "")
  (setq isearch-window-configuration
	(if isearch-slow-terminal-mode (current-window-configuration) nil))

  ;; Maybe make minibuffer frame visible and/or raise it.
  (let ((frame (window-frame (minibuffer-window))))
    (unless (memq (frame-live-p frame) '(nil t))
      (unless (frame-visible-p frame)
	(make-frame-visible frame))
      (if minibuffer-auto-raise
	  (raise-frame frame))))

  (setq	isearch-mode " Isearch")  ;; forward? regexp?
  (force-mode-line-update)

  (setq isearch--saved-local-map overriding-terminal-local-map)
  (setq overriding-terminal-local-map isearch-mode-map)
  (run-hooks 'isearch-mode-hook)
  ;; Remember the initial map possibly modified
  ;; by external packages in isearch-mode-hook.  (Bug#16035)
  (setq isearch--saved-overriding-local-map overriding-terminal-local-map)

  ;; Pushing the initial state used to be before running isearch-mode-hook,
  ;; but a hook might set `isearch-push-state-function' used in
  ;; `isearch-push-state' to save mode-specific initial state.  (Bug#4994)
  (isearch-push-state)

  (isearch-update)

  (add-hook 'pre-command-hook 'isearch-pre-command-hook)
  (add-hook 'post-command-hook 'isearch-post-command-hook)
  (add-hook 'mouse-leave-buffer-hook 'isearch-mouse-leave-buffer)
  (add-hook 'delete-frame-functions 'isearch-done)
  (add-hook 'kbd-macro-termination-hook 'isearch-done)

  ;; If the keyboard is not up and the last event did not come from
  ;; a keyboard, bring it up so that the user can type.
  ;;
  ;; last-event-frame may be `macro', since people apparently make use
  ;; of I-search in keyboard macros.  (bug#65175)
  (when (and (not (eq last-event-frame 'macro))
             (or (not last-event-frame)
                 (not (eq (device-class last-event-frame
                                        last-event-device)
                          'keyboard))))
    (frame-toggle-on-screen-keyboard (selected-frame) nil))

  ;; Disable text conversion so that isearch can behave correctly.

  (when (fboundp 'set-text-conversion-style)
    (setq isearch-text-conversion-style
          text-conversion-style)
    (set-text-conversion-style nil))

  ;; isearch-mode can be made modal (in the sense of not returning to
  ;; the calling function until searching is completed) by entering
  ;; a recursive-edit and exiting it when done isearching.
  (if recursive-edit
      (let ((isearch-recursive-edit t))
	(recursive-edit)))
  isearch-success)


;; Some high level utilities.  Others below.
(defvar isearch--current-buffer nil)

(defun isearch-update ()
  "This is called after every isearch command to update the display.
The second last thing it does is to run `isearch-update-post-hook'.
The last thing is to trigger a new round of lazy highlighting."
  (unless (eq (current-buffer) isearch--current-buffer)
    (when (buffer-live-p isearch--current-buffer)
      (with-current-buffer isearch--current-buffer
        (setq cursor-sensor-inhibit (delq 'isearch cursor-sensor-inhibit))))
    (setq isearch--current-buffer (current-buffer))
    (make-local-variable 'cursor-sensor-inhibit)
    ;; Suspend things like cursor-intangible during Isearch so we can search
    ;; even within intangible text.
    (push 'isearch cursor-sensor-inhibit))

  (if (and (null unread-command-events)
	   (null executing-kbd-macro))
      (progn
        (if (not (input-pending-p))
          (funcall (or isearch-message-function #'isearch-message)))
        (if (and isearch-slow-terminal-mode
                 (not (or isearch-small-window
                          (pos-visible-in-window-group-p))))
            (let ((found-point (point)))
              (setq isearch-small-window t)
              (move-to-window-line 0)
              (let ((window-min-height 1))
                (split-window nil (if (< search-slow-window-lines 0)
                                      (1+ (- search-slow-window-lines))
                                    (- (window-height)
                                       (1+ search-slow-window-lines)))))
              (if (< search-slow-window-lines 0)
                  (progn (vertical-motion (- 1 search-slow-window-lines))
                         (set-window-start (next-window) (point))
                         (set-window-hscroll (next-window)
                                             (window-hscroll))
                         (set-window-hscroll (selected-window) 0))
                (other-window 1))
              (goto-char found-point))
	  ;; Keep same hscrolling as at the start of the search when possible
	  (let ((current-scroll (window-hscroll))
		visible-p)
	    (set-window-hscroll (selected-window) isearch-start-hscroll)
	    (setq visible-p (pos-visible-in-window-group-p nil nil t))
	    (if (or (not visible-p)
		    ;; When point is not visible because of hscroll,
		    ;; pos-visible-in-window-group-p returns non-nil, but
		    ;; the X coordinate it returns is 1 pixel beyond
		    ;; the last visible one.
		    (>= (car visible-p)
                        (* (window-max-chars-per-line) (frame-char-width)))
                    (< (car visible-p) 0))
		(set-window-hscroll (selected-window) current-scroll))))
	(if isearch-other-end
            (if (< isearch-other-end (point)) ; isearch-forward?
                (isearch-highlight isearch-other-end (point) isearch-match-data)
              (isearch-highlight (point) isearch-other-end isearch-match-data))
          (isearch-dehighlight))))
  (setq ;; quit-flag nil  not for isearch-mode
   isearch-adjusted nil
   isearch-yank-flag nil)
  ;; We must prevent the point moving to the end of composition when a
  ;; part of the composition has just been searched.
  (setq disable-point-adjustment t)
  (run-hooks 'isearch-update-post-hook)
  (when isearch-lazy-highlight
    (isearch-lazy-highlight-new-loop)))

(defun isearch-done (&optional nopush edit)
  "Exit Isearch mode.
Called by all commands that terminate isearch-mode.
For successful search, pass no args.
For a failing search, NOPUSH is t.
For going to the minibuffer to edit the search string,
NOPUSH is t and EDIT is t.
If NOPUSH is non-nil, we don't push the string on the search ring."

  (when isearch-resume-in-command-history
    (add-to-history 'command-history
                    `(isearch-resume ,isearch-string ,isearch-regexp
                                     ,isearch-regexp-function ,isearch-forward
                                     ,isearch-message
                                     ',isearch-case-fold-search)))

  (remove-hook 'pre-command-hook 'isearch-pre-command-hook)
  (remove-hook 'post-command-hook 'isearch-post-command-hook)
  (remove-hook 'mouse-leave-buffer-hook 'isearch-mouse-leave-buffer)
  (remove-hook 'delete-frame-functions 'isearch-done)
  (remove-hook 'kbd-macro-termination-hook 'isearch-done)
  (when (buffer-live-p isearch--current-buffer)
    (with-current-buffer isearch--current-buffer
      (setq isearch--current-buffer nil)
      (setq cursor-sensor-inhibit (delq 'isearch cursor-sensor-inhibit))))

  (setq overriding-terminal-local-map isearch--saved-local-map)
  ;; (setq pre-command-hook isearch-old-pre-command-hook) ; for lemacs
  (setq minibuffer-message-timeout isearch-original-minibuffer-message-timeout)
  (isearch-dehighlight)
  (lazy-highlight-cleanup lazy-highlight-cleanup)
  (setq isearch-lazy-highlight-last-string nil)
  (let ((found-start (window-group-start))
	(found-point (point)))
    (when isearch-window-configuration
      (set-window-configuration isearch-window-configuration)
      (if isearch-small-window
	  (goto-char found-point)
	;; set-window-configuration clobbers window-start; restore it.
	;; This has an annoying side effect of clearing the last_modiff
	;; field of the window, which can cause unwanted scrolling,
	;; so don't do it unless truly necessary.
	(set-window-group-start (selected-window) found-start t))))

  (setq isearch-mode nil)
  (if isearch-input-method-function
      (setq-local input-method-function isearch-input-method-function)
    (kill-local-variable 'input-method-function))

  (if isearch-tool-bar-old-map
      (progn
        (setq-local tool-bar-map isearch-tool-bar-old-map)
        (setq isearch-tool-bar-old-map nil))
    (kill-local-variable 'tool-bar-map))

  ;; Restore the previous text conversion style.
  (when (fboundp 'set-text-conversion-style)
    (set-text-conversion-style isearch-text-conversion-style))

  (force-mode-line-update)

  ;; If we ended in the middle of some intangible text,
  ;; move to the further end of that intangible text.
  (let ((after (if (eobp) nil
		 (get-text-property (point) 'intangible)))
	(before (if (bobp) nil
		  (get-text-property (1- (point)) 'intangible))))
    (when (and before after (eq before after))
      (goto-char
       (if isearch-forward
           (next-single-property-change (point) 'intangible)
         (previous-single-property-change (point) 'intangible)))))

  (if (and (> (length isearch-string) 0) (not nopush))
      ;; Update the ring data.
      (isearch-update-ring isearch-string isearch-regexp))

  (let ((isearch-mode-end-hook-quit (and nopush (not edit))))
    (run-hooks 'isearch-mode-end-hook))

  ;; If there was movement, mark the starting position.
  ;; Maybe should test difference between and set mark only if > threshold.
  (if (/= (point) isearch-opoint)
      (or (and transient-mark-mode mark-active)
	  (progn
	    (push-mark isearch-opoint t)
	    (or executing-kbd-macro (> (minibuffer-depth) 0) edit
		(message "Mark saved where search started")))))

  (and (not edit) isearch-recursive-edit (exit-recursive-edit)))

(defvar isearch-mouse-commands '(mouse-minor-mode-menu)
  "List of mouse commands that are allowed during Isearch.")

(defun isearch-mouse-leave-buffer ()
  "Exit Isearch unless the mouse command is allowed in Isearch.

Mouse commands are allowed in Isearch if they have a non-nil
`isearch-scroll' property or if they are listed in
`isearch-mouse-commands'."
  (unless (or (memq this-command isearch-mouse-commands)
              (eq (get this-command 'isearch-scroll) t))
    (isearch-done)))

(defun isearch-update-ring (string &optional regexp)
  "Add STRING to the beginning of the search ring.
REGEXP if non-nil says use the regexp search ring."
  (let ((history-delete-duplicates t))
    (add-to-history
     (if regexp 'regexp-search-ring 'search-ring)
     (isearch-string-propertize string)
     (if regexp regexp-search-ring-max search-ring-max)
     t)))

(defun isearch-string-propertize (string &optional properties)
  "Add isearch properties to the isearch string."
  (unless properties
    (setq properties `(isearch-case-fold-search ,isearch-case-fold-search))
    (unless isearch-regexp
      (setq properties (append properties `(isearch-regexp-function ,isearch-regexp-function)))))
  (apply 'propertize string properties))

(defun isearch-update-from-string-properties (string)
  "Update isearch properties from the isearch STRING."
  (when (plist-member (text-properties-at 0 string) 'isearch-case-fold-search)
    (setq isearch-case-fold-search
	  (get-text-property 0 'isearch-case-fold-search string)))
  (when (plist-member (text-properties-at 0 string) 'isearch-regexp-function)
    (setq isearch-regexp-function
	  (get-text-property 0 'isearch-regexp-function string))))


;; The search status structure and stack.

(cl-defstruct (isearch--state
               (:constructor nil)
               (:copier nil)
               (:constructor isearch--get-state
                (&aux
                 (string isearch-string)
                 (message isearch-message)
                 (point (point))
                 (success isearch-success)
                 (forward isearch-forward)
                 (other-end isearch-other-end)
                 (word isearch-regexp-function)
                 (error isearch-error)
                 (wrapped isearch-wrapped)
                 (barrier isearch-barrier)
                 (case-fold-search isearch-case-fold-search)
                 (pop-fun (if isearch-push-state-function
                              (funcall isearch-push-state-function)))
                 (match-data isearch-match-data))))
  (string nil :read-only t)
  (message nil :read-only t)
  (point nil :read-only t)
  (success nil :read-only t)
  (forward nil :read-only t)
  (other-end nil :read-only t)
  (word nil :read-only t)
  (error nil :read-only t)
  (wrapped nil :read-only t)
  (barrier nil :read-only t)
  (case-fold-search nil :read-only t)
  (pop-fun nil :read-only t)
  (match-data nil :read-only t))

(defun isearch--set-state (cmd)
  (setq isearch-string (isearch--state-string cmd)
	isearch-message (isearch--state-message cmd)
	isearch-success (isearch--state-success cmd)
	isearch-forward (isearch--state-forward cmd)
	isearch-other-end (isearch--state-other-end cmd)
	isearch-regexp-function (isearch--state-word cmd)
	isearch-error (isearch--state-error cmd)
	isearch-wrapped (isearch--state-wrapped cmd)
	isearch-barrier (isearch--state-barrier cmd)
	isearch-case-fold-search (isearch--state-case-fold-search cmd)
	isearch-match-data (isearch--state-match-data cmd))
  (if (functionp (isearch--state-pop-fun cmd))
      (funcall (isearch--state-pop-fun cmd) cmd))
  (goto-char (isearch--state-point cmd)))

(defun isearch-pop-state ()
  (setq isearch-cmds (cdr isearch-cmds))
  (isearch--set-state (car isearch-cmds)))

(defun isearch-push-state ()
  (push (isearch--get-state) isearch-cmds))


;; Commands active while inside of the isearch minor mode.

(defun isearch-exit ()
  "Exit search normally.
However, if this is the first command after starting incremental
search and `search-nonincremental-instead' is non-nil, do a
nonincremental search instead via `isearch-edit-string'."
  (interactive)
  (if (and search-nonincremental-instead
	   (= 0 (length isearch-string)))
      (let ((isearch-nonincremental t))
	(isearch-edit-string)) ;; this calls isearch-done as well
    (isearch-done))
  (isearch-clean-overlays))

(defun isearch-fail-pos (&optional msg)
  "Return position of first mismatch in search string, or nil if none.
If MSG is non-nil, use variable `isearch-message', otherwise `isearch-string'."
  (let ((cmds isearch-cmds)
	(curr-msg (if msg isearch-message isearch-string))
	succ-msg)
    (when (or (not isearch-success) isearch-error)
      (while (and cmds
		  (or (not (isearch--state-success (car cmds)))
		      (isearch--state-error (car cmds))))
        (pop cmds))
      (setq succ-msg (and cmds (if msg (isearch--state-message (car cmds))
				 (isearch--state-string (car cmds)))))
      (if (and (stringp succ-msg)
	       (< (length succ-msg) (length curr-msg))
	       (equal succ-msg
		      (substring curr-msg 0 (length succ-msg))))
	  (length succ-msg)
	0))))

(define-obsolete-variable-alias 'isearch-new-word
  'isearch-new-regexp-function "25.1")

(defvar isearch-new-regexp-function nil
  "Holds the next `isearch-regexp-function' inside `with-isearch-suspended'.
If this is set inside code wrapped by the macro
`with-isearch-suspended', then the value set will be used as the
`isearch-regexp-function' once isearch resumes.")

(defvar isearch-suspended nil)

(defmacro with-isearch-suspended (&rest body)
  "Exit Isearch mode, run BODY, and reinvoke the pending search.
You can update the global isearch variables by setting new values to
`isearch-new-string', `isearch-new-message', `isearch-new-forward',
`isearch-new-regexp-function', `isearch-new-case-fold',
`isearch-new-nonincremental'."
  ;; This code is very hairy for several reasons, explained in the code.
  ;; Mainly, isearch-mode must be terminated while editing and then restarted.
  ;; If there were a way to catch any change of buffer from the minibuffer,
  ;; this could be simplified greatly.
  ;; Editing doesn't back up the search point.  Should it?
  `(condition-case nil
      (progn
	(let ((isearch-new-nonincremental isearch-nonincremental)

	      ;; Locally bind all isearch global variables to protect them
	      ;; from recursive isearching.
	      ;; isearch-string -message and -forward are not bound
	      ;; so they may be changed.  Instead, save the values.
	      (isearch-new-string isearch-string)
	      (isearch-new-message isearch-message)
	      (isearch-new-forward isearch-forward)
	      (isearch-new-regexp-function isearch-regexp-function)
	      (isearch-new-case-fold isearch-case-fold-search)

	      (isearch-regexp isearch-regexp)
	      (isearch-op-fun isearch-op-fun)
	      (isearch-cmds isearch-cmds)
	      (isearch-success isearch-success)
	      (isearch-wrapped isearch-wrapped)
	      (isearch-barrier isearch-barrier)
	      (isearch-adjusted isearch-adjusted)
	      (isearch-yank-flag isearch-yank-flag)
	      (isearch-error isearch-error)
	      (isearch-match-data isearch-match-data)

	      (multi-isearch-file-list-new multi-isearch-file-list)
	      (multi-isearch-buffer-list-new multi-isearch-buffer-list)
	      (multi-isearch-next-buffer-function multi-isearch-next-buffer-current-function)
	      (multi-isearch-current-buffer-new multi-isearch-current-buffer)
  ;;; Don't bind this.  We want isearch-search, below, to set it.
  ;;; And the old value won't matter after that.
  ;;;	    (isearch-other-end isearch-other-end)
  ;;; Perhaps some of these other variables should be bound for a
  ;;; shorter period, ending before the next isearch-search.
  ;;; But there doesn't seem to be a real bug, so let's not risk it now.
	      (isearch-opoint isearch-opoint)
	      (isearch-slow-terminal-mode isearch-slow-terminal-mode)
	      (isearch-small-window isearch-small-window)
	      (isearch-recursive-edit isearch-recursive-edit)
	      ;; Save current configuration so we can restore it here.
	      (isearch-window-configuration (current-window-configuration))

	      ;; This could protect the index of the search rings,
	      ;; but we can't reliably count the number of typed M-p
	      ;; in `read-from-minibuffer' to adjust the index accordingly.
	      ;; So when the following is commented out, `isearch-mode'
	      ;; below resets the index to the predictable value nil.
	      ;; (search-ring-yank-pointer search-ring-yank-pointer)
	      ;; (regexp-search-ring-yank-pointer regexp-search-ring-yank-pointer)

	      ;; Temporarily restore `minibuffer-message-timeout'.
	      (minibuffer-message-timeout
	       isearch-original-minibuffer-message-timeout)
	      (isearch-original-minibuffer-message-timeout
	       isearch-original-minibuffer-message-timeout)
	      old-point old-other-end)

          (setq isearch-suspended t)

	  ;; Actually terminate isearching until editing is done.
	  ;; This is so that the user can do anything without failure,
	  ;; like switch buffers and start another isearch, and return.
	  (condition-case nil
	      (isearch-done t t)
	    (exit nil))			; was recursive editing

	  ;; Save old point and isearch-other-end before reading from minibuffer
	  ;; that can change their values.
	  (setq old-point (point) old-other-end isearch-other-end)

	  (unwind-protect
	      (progn ,@body)

            (setq isearch-suspended nil)

	    ;; Always resume isearching by restarting it.
	    (isearch-mode isearch-forward
			  isearch-regexp
			  isearch-op-fun
			  nil
			  isearch-regexp-function)

	    ;; Copy new local values to isearch globals
	    (setq isearch-string isearch-new-string
		  isearch-message isearch-new-message
		  isearch-forward isearch-new-forward
		  isearch-nonincremental isearch-new-nonincremental
		  isearch-regexp-function isearch-new-regexp-function
		  isearch-case-fold-search isearch-new-case-fold
		  multi-isearch-current-buffer multi-isearch-current-buffer-new
		  multi-isearch-file-list multi-isearch-file-list-new
		  multi-isearch-buffer-list multi-isearch-buffer-list-new)

            (isearch-update-from-string-properties isearch-string)

	    ;; Restore the minibuffer message before moving point.
            (funcall (or isearch-message-function #'isearch-message) nil t)

	    ;; Set point at the start (end) of old match if forward (backward),
	    ;; so after exiting minibuffer isearch resumes at the start (end)
	    ;; of this match and can find it again.
	    (if (and old-other-end (eq old-point (point))
		     (eq isearch-forward isearch-new-forward))
		(goto-char old-other-end)))

	  ;; Empty isearch-string means use default.
	  (when (= 0 (length isearch-string))
	    (setq isearch-string (or (car (if isearch-regexp
					      regexp-search-ring
					    search-ring))
				     "")

		  isearch-message
		  (mapconcat 'isearch-text-char-description
			     isearch-string ""))
	    ;; After taking the last element, adjust ring to previous one.
	    (isearch-ring-adjust1 nil)))

	;; This used to push the state as of before this C-s, but it adds
	;; an inconsistent state where part of variables are from the
	;; previous search (e.g. `isearch-success'), and part of variables
	;; are just entered from the minibuffer (e.g. `isearch-string').
	;; (isearch-push-state)

	;; Reinvoke the pending search.
	(isearch-search)
        ;; If no code has changed the search parameters, then pushing
        ;; a new state of Isearch should not be necessary.
        (unless (and isearch-cmds
                     (equal (car isearch-cmds) (isearch--get-state)))
          (isearch-push-state))        ; this pushes the correct state
	(isearch-update)
	(if isearch-nonincremental
	    (progn
	      ;; (sit-for 1) ;; needed if isearch-done does: (message "")
	      (isearch-done)
	      ;; The search done message is confusing when the string
	      ;; is empty, so erase it.
	      (if (equal isearch-string "")
		  (message "")))))

    (quit  ; handle abort-recursive-edit
     (setq isearch-suspended nil)
     (isearch-abort)  ;; outside of let to restore outside global values
     )))

(defvar minibuffer-history-symbol) ;; from external package gmhist.el

(defun isearch-edit-string ()
  "Edit the search string in the minibuffer.
The following additional command keys are active while editing.
\\<minibuffer-local-isearch-map>
\\[exit-minibuffer] to resume incremental searching with the edited string.
\\[isearch-forward-exit-minibuffer] to resume isearching forward.
\\[isearch-reverse-exit-minibuffer] to resume isearching backward.
\\[isearch-complete-edit] to complete the search string using the search ring."
  (interactive)
  (with-isearch-suspended
   (let* ((message-log-max nil)
	  ;; Don't add a new search string to the search ring here
	  ;; in `read-from-minibuffer'. It should be added only
	  ;; by `isearch-update-ring' called from `isearch-done'.
	  (history-add-new-input nil)
	  ;; Binding minibuffer-history-symbol to nil is a work-around
	  ;; for some incompatibility with gmhist.
	  (minibuffer-history-symbol)
	  ;; Search string might have meta information on text properties.
	  (minibuffer-allow-text-properties t))
     (setq isearch-new-string
	   (minibuffer-with-setup-hook
               (minibuffer-lazy-highlight-setup)
             (read-from-minibuffer
	      (isearch-message-prefix nil isearch-nonincremental)
	      (cons isearch-string (1+ (or (isearch-fail-pos)
					   (length isearch-string))))
	      minibuffer-local-isearch-map nil
	      (if isearch-regexp
		  (cons 'regexp-search-ring
		        (1+ (or regexp-search-ring-yank-pointer -1)))
	        (cons 'search-ring
		      (1+ (or search-ring-yank-pointer -1))))
	      nil t))
	   isearch-new-message
	   (mapconcat 'isearch-text-char-description
		      isearch-new-string "")))))

(defun isearch-nonincremental-exit-minibuffer ()
  (interactive)
  (setq isearch-new-nonincremental t)
  (exit-minibuffer))
;; It makes no sense to change the value of `isearch-new-nonincremental'
;; from nil to t during `isearch-edit-string'.   Thus marked as obsolete.
(make-obsolete 'isearch-nonincremental-exit-minibuffer 'exit-minibuffer "24.4")

(defun isearch-forward-exit-minibuffer ()
  "Resume isearching forward from the minibuffer that edits the search string."
  (interactive)
  (setq isearch-new-forward t isearch-new-nonincremental nil)
  (exit-minibuffer))

(defun isearch-reverse-exit-minibuffer ()
  "Resume isearching backward from the minibuffer that edits the search string."
  (interactive)
  (setq isearch-new-forward nil isearch-new-nonincremental nil)
  (exit-minibuffer))

(defun isearch-cancel ()
  "Terminate the search and go back to the starting point."
  (interactive)
  (if (and isearch-push-state-function isearch-cmds)
      ;; For defined push-state function, restore the first state.
      ;; This calls pop-state function and restores original point.
      (let ((isearch-cmds (last isearch-cmds)))
	(isearch--set-state (car isearch-cmds)))
    (goto-char isearch-opoint))
  (isearch-done t)                      ; Exit isearch..
  (isearch-clean-overlays)
  (signal 'quit nil))                   ; ..and pass on quit signal.

(defun isearch-abort ()
  "Abort incremental search mode if searching is successful, signaling quit.
Otherwise, revert to previous successful search and continue searching.
Use `isearch-exit' to quit without signaling."
  (interactive)
  ;; (ding)  signal instead below, if quitting
  (discard-input)
  (if (and isearch-success (not isearch-error))
      ;; If search is successful and has no incomplete regexp,
      ;; move back to starting point and really do quit.
      (progn
        (setq isearch-success nil)
        (isearch-cancel))
    ;; If search is failing, or has an incomplete regexp,
    ;; rub out until it is once more successful.
    (while (or (not isearch-success) isearch-error)
      (isearch-pop-state))
    (isearch-update)))

(defun isearch-repeat (direction &optional count)
  ;; Utility for isearch-repeat-forward and isearch-repeat-backward.
  (if (eq isearch-forward (eq direction 'forward))
      ;; C-s in forward or C-r in reverse.
      (if (equal isearch-string "")
	  ;; If search string is empty, use last one.
	  (if (null (if isearch-regexp regexp-search-ring search-ring))
	      (setq isearch-error "No previous search string")
	    (setq isearch-string
		  (car (if isearch-regexp regexp-search-ring search-ring))
		  isearch-message
		  (mapconcat 'isearch-text-char-description
			     isearch-string "")
		  isearch-case-fold-search isearch-last-case-fold-search)
	    ;; After taking the last element, adjust ring to previous one.
	    (isearch-ring-adjust1 nil))
	;; If already have what to search for, repeat it.
	(unless (or isearch-success (null isearch-wrap-pause))
	  ;; Set isearch-wrapped before calling isearch-wrap-function
	  (setq isearch-wrapped t)
	  (if isearch-wrap-function
	      (funcall isearch-wrap-function)
	    (goto-char (if isearch-forward (point-min) (point-max))))))
    ;; C-s in reverse or C-r in forward, change direction.
    (if (and isearch-other-end isearch-repeat-on-direction-change
             (or (null isearch-cmds)
                 ;; Go to 'isearch-other-end' only when point is still
                 ;; on the current match.  However, after scrolling
                 ;; (when 'isearch-allow-scroll' is 'unlimited'),
                 ;; repeat the reversed search from a new position
                 ;; where point was moved during scrolling (bug#78074).
                 (eq (isearch--state-point (car isearch-cmds)) (point))))
        (goto-char isearch-other-end))
    (setq isearch-forward (not isearch-forward)
	  isearch-success t))

  (setq isearch-barrier (point)) ; For subsequent \| if regexp.

  (if (equal isearch-string "")
      (setq isearch-success t)
    ;; For the case when count > 1, don't keep intermediate states
    ;; added to isearch-cmds by isearch-push-state in this loop.
    (let ((isearch-cmds isearch-cmds)
          (was-success isearch-success))
      (while (<= 0 (setq count (1- (or count 1))))
	(if (and isearch-success
		 (equal (point) isearch-other-end)
		 (not isearch-just-started))
	    ;; If repeating a search that found
	    ;; an empty string, ensure we advance.
	    (if (if isearch-forward (eobp) (bobp))
		;; If there's nowhere to advance to, fail (and wrap next time).
		(progn
		  (setq isearch-success nil)
		  (ding))
	      (forward-char (if isearch-forward 1 -1))
	      (isearch-search))
	  (isearch-search))
	  (when (> count 0)
	    ;; Update isearch-cmds, so if isearch-search fails later,
	    ;; it can restore old successful state from isearch-cmds.
	    (isearch-push-state))
          (cond
           ;; Wrap immediately and repeat the search again
           ((memq isearch-wrap-pause '(no no-ding))
            (if isearch-success
                (setq was-success isearch-success)
              ;; If failed this time after succeeding last time
              (when was-success
                (setq was-success nil)
                (setq count (1+ count)) ;; Increment to force repeat
                (setq isearch-wrapped t)
                (if isearch-wrap-function
                    (funcall isearch-wrap-function)
                  (goto-char (if isearch-forward (point-min) (point-max)))))))
           ;; Stop looping on failure
           (t (when (or (not isearch-success) isearch-error)
                (setq count 0)))))))

  (isearch-push-state)
  (isearch-update))

(defun isearch-repeat-forward (&optional arg)
  "Repeat incremental search forwards.
With a numeric argument, repeat the search ARG times.
A negative argument searches backwards.
\\<isearch-mode-map>
This command finds the next relative occurrence of the current
search string.  To find the absolute occurrence from the beginning
of the buffer, type \\[isearch-beginning-of-buffer] with a numeric argument."
  (interactive "P")
  (if arg
      (let ((count (prefix-numeric-value arg)))
        (cond ((< count 0)
               (isearch-repeat-backward (abs count))
               ;; Reverse the direction back
               (let ((isearch-repeat-on-direction-change nil))
                 (isearch-repeat 'forward)))
              (t
               ;; Take into account one iteration to reverse direction
               (unless isearch-repeat-on-direction-change
                 (when (not isearch-forward) (setq count (1+ count))))
               (isearch-repeat 'forward count))))
    (isearch-repeat 'forward)))

(defun isearch-repeat-backward (&optional arg)
  "Repeat incremental search backwards.
With a numeric argument, repeat the search ARG times.
A negative argument searches forwards.
\\<isearch-mode-map>
This command finds the next relative occurrence of the current
search string.  To find the absolute occurrence from the end
of the buffer, type \\[isearch-end-of-buffer] with a numeric argument."
  (interactive "P")
  (if arg
      (let ((count (prefix-numeric-value arg)))
        (cond ((< count 0)
               (isearch-repeat-forward (abs count))
               ;; Reverse the direction back
               (let ((isearch-repeat-on-direction-change nil))
                 (isearch-repeat 'backward)))
              (t
               ;; Take into account one iteration to reverse direction
               (unless isearch-repeat-on-direction-change
                 (when isearch-forward (setq count (1+ count))))
               (isearch-repeat 'backward count))))
    (isearch-repeat 'backward)))

(defun isearch-beginning-of-buffer (&optional arg)
  "Go to the first occurrence of the current search string.
Move point to the beginning of the buffer and search forwards from the top.
\\<isearch-mode-map>
With a numeric argument, go to the ARGth absolute occurrence counting from
the beginning of the buffer.  To find the next relative occurrence forwards,
type \\[isearch-repeat-forward] with a numeric argument.
You might want to use `isearch-allow-motion' instead of this command."
  (interactive "p")
  (if (and arg (< arg 0))
      (isearch-end-of-buffer (abs arg))
    ;; For the case when the match is at bobp,
    ;; don't forward char in isearch-repeat
    (setq isearch-just-started t)
    (goto-char (point-min))
    (let ((current-direction (if isearch-forward 'forward 'backward))
          (isearch-repeat-on-direction-change nil))
      (isearch-repeat 'forward arg)
      (unless (eq current-direction (if isearch-forward 'forward 'backward))
        (isearch-repeat current-direction)))))

(defun isearch-end-of-buffer (&optional arg)
  "Go to the last occurrence of the current search string.
Move point to the end of the buffer and search backwards from the bottom.
\\<isearch-mode-map>
With a numeric argument, go to the ARGth absolute occurrence counting from
the end of the buffer.  To find the next relative occurrence backwards,
type \\[isearch-repeat-backward] with a numeric argument.
You might want to use `isearch-allow-motion' instead of this command."
  (interactive "p")
  (if (and arg (< arg 0))
      (isearch-beginning-of-buffer (abs arg))
    (setq isearch-just-started t)
    (goto-char (point-max))
    (let ((current-direction (if isearch-forward 'forward 'backward))
          (isearch-repeat-on-direction-change nil))
      (isearch-repeat 'backward arg)
      (unless (eq current-direction (if isearch-forward 'forward 'backward))
        (isearch-repeat current-direction)))))


;;; Toggles for `isearch-regexp-function' and `search-default-mode'.
(defmacro isearch-define-mode-toggle (mode key function &optional docstring &rest body)
  "Define a command called `isearch-toggle-MODE' and bind it to `M-s KEY'.
The first line of the command's docstring is auto-generated, the
remainder may be provided in DOCSTRING.
If FUNCTION is a symbol, this command first toggles the value of
`isearch-regexp-function' between nil and FUNCTION.  Also set the
`isearch-message-prefix' property of FUNCTION.
The command then executes BODY and updates the isearch prompt."
  (declare (indent defun))
  (let ((command-name (intern (format "isearch-toggle-%s" mode)))
        (key (concat "\M-s" key)))
    `(progn
       (defun ,command-name ()
         ,(format "Toggle %s searching on or off.%s" mode
                  (if docstring (concat "\n" docstring) ""))
         (interactive)
         (unless isearch-mode (isearch-mode t))
         ,@(when function
             `((setq isearch-regexp-function
                     (unless (eq isearch-regexp-function #',function)
                       #',function))
               (setq isearch-regexp nil)))
         ,@body
         (setq isearch-success t isearch-adjusted 'toggle)
         (isearch-update))
       (define-key isearch-mode-map ,key #',command-name)
       ,@(when (and function (symbolp function))
           `((put ',function 'isearch-message-prefix ,(format "%s " mode))
             (put ',function :advertised-binding ,key)
             (cl-callf (lambda (types) (cons 'choice
                                        (cons '(const :tag ,(capitalize (format "%s search" mode)) ,function)
                                              (cdr types))))
                 (get 'search-default-mode 'custom-type)))))))

(isearch-define-mode-toggle word "w" word-search-regexp "\
Turning on word search turns off regexp mode.")
(isearch-define-mode-toggle symbol "_" isearch-symbol-regexp "\
Turning on symbol search turns off regexp mode.")
(isearch-define-mode-toggle char-fold "'" char-fold-to-regexp "\
Turning on character-folding turns off regexp mode.")

(isearch-define-mode-toggle regexp "r" nil nil
  (setq isearch-regexp (not isearch-regexp))
  (if isearch-regexp (setq isearch-regexp-function nil)))

(defvar isearch-message-properties minibuffer-prompt-properties
  "Text properties that are added to the isearch prompt.")

(defun isearch--momentary-message (string &optional seconds)
  "Print STRING at the end of the isearch prompt for 1 second.
The optional argument SECONDS overrides the number of seconds."
  (let ((message-log-max nil))
    (message "%s%s%s"
             (isearch-message-prefix nil isearch-nonincremental)
             isearch-message
             (apply #'propertize (format " [%s]" string)
                    isearch-message-properties)))
  (sit-for (or seconds 1)))

(isearch-define-mode-toggle lax-whitespace " " nil
  "In ordinary search, toggles the value of the variable
`isearch-lax-whitespace'.  In regexp search, toggles the
value of the variable `isearch-regexp-lax-whitespace'."
  (isearch--momentary-message
   (if (if isearch-regexp
           (setq isearch-regexp-lax-whitespace (not isearch-regexp-lax-whitespace))
         (setq isearch-lax-whitespace (not isearch-lax-whitespace)))
       "match spaces loosely"
     "match spaces literally")))

(isearch-define-mode-toggle case-fold "c" nil
  "Toggles the value of the variable `isearch-case-fold-search'."
  (isearch--momentary-message
   (if (setq isearch-case-fold-search
             (if isearch-case-fold-search nil 'yes))
       "case insensitive"
     "case sensitive")))

(isearch-define-mode-toggle invisible "i" nil
  "This determines whether to search inside invisible text or not.
Toggles the variable `isearch-invisible' between values
nil and a non-nil value of the option `search-invisible'
\(or `open' if `search-invisible' is nil)."
  "match %svisible text"
  (isearch--momentary-message
   (if (setq isearch-invisible
             (if isearch-invisible
                 nil (or search-invisible 'open)))
       "match invisible text"
     "match visible text")))


;; Word search

(defun word-search-regexp (string &optional lax)
  "Return a regexp which matches words, ignoring punctuation.
Given STRING, a string of words separated by word delimiters,
compute a regexp that matches those exact words separated by
arbitrary punctuation.  If the string begins or ends in whitespace,
the beginning or the end of the string matches arbitrary whitespace.
Otherwise if LAX is non-nil, the beginning or the end of the string
need not match a word boundary.

Used in `word-search-forward', `word-search-backward',
`word-search-forward-lax', `word-search-backward-lax'."
  (cond
   ((equal string "") "")
   ((string-match-p "\\`\\W+\\'" string) "\\W+")
   (t (concat
       (if (string-match-p "\\`\\W" string) "\\W+"
	 "\\<")
       (mapconcat 'regexp-quote (split-string string "\\W+" t) "\\W+")
       (if (string-match-p "\\W\\'" string) "\\W+"
	 (unless lax "\\>"))))))

(defun word-search-backward (string &optional bound noerror count)
  "Search backward from point for STRING, ignoring differences in punctuation.
Set point to the beginning of the occurrence found, and return point.
An optional second argument bounds the search; it is a buffer position.
  The match found must not begin before that position.  A value of nil
  means search to the beginning of the accessible portion of the buffer.
Optional third argument, if t, means if fail just return nil (no error).
  If not nil and not t, position at limit of search and return nil.
Optional fourth argument COUNT, if a positive number, means to search
  for COUNT successive occurrences.  If COUNT is negative, search
  forward, instead of backward, for -COUNT occurrences.  A value of
  nil means the same as 1.
With COUNT positive, the match found is the COUNTth to last one (or
  last, if COUNT is 1 or nil) in the buffer located entirely before
  the origin of the search; correspondingly with COUNT negative.

Relies on the function `word-search-regexp' to convert a sequence
of words in STRING to a regexp used to search words without regard
to punctuation.
This command does not support character folding, and lax space matching
has no effect on it."
  (interactive "sWord search backward: ")
  (re-search-backward (word-search-regexp string nil) bound noerror count))

(defun word-search-forward (string &optional bound noerror count)
  "Search forward from point for STRING, ignoring differences in punctuation.
Set point to the end of the occurrence found, and return point.
An optional second argument bounds the search; it is a buffer position.
  The match found must not end after that position.  A value of nil
  means search to the end of the accessible portion of the buffer.
Optional third argument, if t, means if fail just return nil (no error).
  If not nil and not t, move to limit of search and return nil.
Optional fourth argument COUNT, if a positive number, means to search
  for COUNT successive occurrences.  If COUNT is negative, search
  backward, instead of forward, for -COUNT occurrences.  A value of
  nil means the same as 1.
With COUNT positive, the match found is the COUNTth one (or first,
  if COUNT is 1 or nil) in the buffer located entirely after the
  origin of the search; correspondingly with COUNT negative.

Relies on the function `word-search-regexp' to convert a sequence
of words in STRING to a regexp used to search words without regard
to punctuation.
This command does not support character folding, and lax space matching
has no effect on it."
  (interactive "sWord search: ")
  (re-search-forward (word-search-regexp string nil) bound noerror count))

(defun word-search-backward-lax (string &optional bound noerror count)
  "Search backward from point for STRING, ignoring differences in punctuation.
Set point to the beginning of the occurrence found, and return point.

Unlike `word-search-backward', the end of STRING need not match a word
boundary, unless STRING ends in whitespace.

An optional second argument bounds the search; it is a buffer position.
  The match found must not begin before that position.  A value of nil
  means search to the beginning of the accessible portion of the buffer.
Optional third argument, if t, means if fail just return nil (no error).
  If not nil and not t, position at limit of search and return nil.
Optional fourth argument COUNT, if a positive number, means to search
  for COUNT successive occurrences.  If COUNT is negative, search
  forward, instead of backward, for -COUNT occurrences.  A value of
  nil means the same as 1.
With COUNT positive, the match found is the COUNTth to last one (or
  last, if COUNT is 1 or nil) in the buffer located entirely before
  the origin of the search; correspondingly with COUNT negative.

Relies on the function `word-search-regexp' to convert a sequence
of words in STRING to a regexp used to search words without regard
to punctuation.
This command does not support character folding, and lax space matching
has no effect on it."
  (interactive "sWord search backward: ")
  (re-search-backward (word-search-regexp string t) bound noerror count))

(defun word-search-forward-lax (string &optional bound noerror count)
  "Search forward from point for STRING, ignoring differences in punctuation.
Set point to the end of the occurrence found, and return point.

Unlike `word-search-forward', the end of STRING need not match a word
boundary, unless STRING ends in whitespace.

An optional second argument bounds the search; it is a buffer position.
  The match found must not end after that position.  A value of nil
  means search to the end of the accessible portion of the buffer.
Optional third argument, if t, means if fail just return nil (no error).
  If not nil and not t, move to limit of search and return nil.
Optional fourth argument COUNT, if a positive number, means to search
  for COUNT successive occurrences.  If COUNT is negative, search
  backward, instead of forward, for -COUNT occurrences.  A value of
  nil means the same as 1.
With COUNT positive, the match found is the COUNTth one (or first,
  if COUNT is 1 or nil) in the buffer located entirely after the
  origin of the search; correspondingly with COUNT negative.

Relies on the function `word-search-regexp' to convert a sequence
of words in STRING to a regexp used to search words without regard
to punctuation.
This command does not support character folding, and lax space matching
has no effect on it."
  (interactive "sWord search: ")
  (re-search-forward (word-search-regexp string t) bound noerror count))

;; Symbol search

(defun isearch-symbol-regexp (string &optional lax)
  "Return a regexp which matches STRING as a symbol.
Creates a regexp where STRING is surrounded by symbol delimiters \\_< and \\_>.
If there are more than one symbol, then compute a regexp that matches
those exact symbols separated by non-symbol characters.  If the string
begins or ends in whitespace, the beginning or the end of the string
matches arbitrary non-symbol whitespace.  Otherwise if LAX is non-nil,
the beginning or the end of the string need not match a symbol boundary."
  (let ((not-word-symbol-re
	 ;; This regexp matches all syntaxes except word and symbol syntax.
	 "\\(?:\\s-\\|\\s.\\|\\s(\\|\\s)\\|\\s\"\\|\\s\\\\|\\s/\\|\\s$\\|\\s'\\|\\s<\\|\\s>\\|\\s!\\|\\s|\\)+"))
    (cond
     ((equal string "") "")
     ((string-match-p (format "\\`%s\\'" not-word-symbol-re) string)
      not-word-symbol-re)
     (t (concat
	 (if (string-match-p (format "\\`%s" not-word-symbol-re) string)
	     not-word-symbol-re
	   "\\_<")
	 (mapconcat 'regexp-quote (split-string string not-word-symbol-re t)
		    not-word-symbol-re)
	 (if (string-match-p (format "%s\\'" not-word-symbol-re) string)
	     not-word-symbol-re
	   (unless lax "\\_>")))))))

;; Search with lax whitespace

(defun search-forward-lax-whitespace (string &optional bound noerror count)
  "Search forward for STRING, matching a sequence of whitespace chars."
  (let ((search-spaces-regexp search-whitespace-regexp))
    (re-search-forward (regexp-quote string) bound noerror count)))

(defun search-backward-lax-whitespace (string &optional bound noerror count)
  "Search backward for STRING, matching a sequence of whitespace chars."
  (let ((search-spaces-regexp search-whitespace-regexp))
    (re-search-backward (regexp-quote string) bound noerror count)))

(defun re-search-forward-lax-whitespace (regexp &optional bound noerror count)
  "Search forward for REGEXP, matching a sequence of whitespace chars."
  (let ((search-spaces-regexp search-whitespace-regexp))
    (re-search-forward regexp bound noerror count)))

(defun re-search-backward-lax-whitespace (regexp &optional bound noerror count)
  "Search backward for REGEXP, matching a sequence of whitespace chars."
  (let ((search-spaces-regexp search-whitespace-regexp))
    (re-search-backward regexp bound noerror count)))

(dolist (old '(re-search-forward-lax-whitespace search-backward-lax-whitespace
               search-forward-lax-whitespace re-search-backward-lax-whitespace))
  (make-obsolete old
                 "instead, use (let ((search-spaces-regexp search-whitespace-regexp))
               (re-search-... ...))"
                 "25.1"))


(defun isearch-query-replace (&optional arg regexp-flag)
  "Start `query-replace' with string to replace from last search string.
The ARG (prefix arg if interactive), if non-nil, means replace
only matches surrounded by word boundaries.  A negative prefix
arg means replace backward.  Note that using the prefix arg
is possible only when `isearch-allow-scroll' is non-nil or
`isearch-allow-prefix' is non-nil, and it doesn't always provide the
correct matches for `query-replace', so the preferred way to run word
replacements from Isearch is `M-s w ... M-%'.

As each match is found, the user must type a character saying
what to do with it.  Type SPC or `y' to replace the match,
DEL or `n' to skip and go to the next match.  For more directions,
type \\[help-command] at that time."
  (interactive
   (list current-prefix-arg))
  (barf-if-buffer-read-only)
  (if regexp-flag (setq isearch-regexp t))
  (let ((case-fold-search isearch-case-fold-search)
	;; set `search-upper-case' to nil to not call
	;; `isearch-no-upper-case-p' in `perform-replace'
	(search-upper-case nil)
	(search-invisible isearch-invisible)
	(replace-lax-whitespace
	 isearch-lax-whitespace)
	(replace-regexp-lax-whitespace
	 isearch-regexp-lax-whitespace)
	(delimited (and arg (not (eq arg '-))))
	(backward (and arg (eq arg '-)))
	;; Set `isearch-recursive-edit' to nil to prevent calling
	;; `exit-recursive-edit' in `isearch-done' that terminates
	;; the execution of this command when it is non-nil.
	;; We call `exit-recursive-edit' explicitly at the end below.
	(isearch-recursive-edit nil)
	(isearch-string-propertized
         (isearch-string-propertize isearch-string)))
    (isearch-done nil t)
    (isearch-clean-overlays)
    (if (and isearch-other-end
	     (if backward
		 (> isearch-other-end (point))
	       (< isearch-other-end (point)))
             (not (and transient-mark-mode mark-active
                       (if backward
			   (> (mark) (point))
			 (< (mark) (point))))))
        (goto-char isearch-other-end))
    (set query-replace-from-history-variable
         (cons isearch-string-propertized
               (symbol-value query-replace-from-history-variable)))
    (perform-replace
     isearch-string-propertized
     (query-replace-read-to
      isearch-string-propertized
      (concat "Query replace"
              (isearch--describe-regexp-mode (or delimited isearch-regexp-function) t)
	      (if backward " backward" "")
	      (if (use-region-p) " in region" ""))
      isearch-regexp)
     t isearch-regexp (or delimited isearch-regexp-function) nil nil
     (use-region-beginning) (use-region-end)
     backward))
  (and isearch-recursive-edit (exit-recursive-edit)))

(defun isearch-query-replace-regexp (&optional arg)
  "Start `query-replace-regexp' with string to replace from last search string.
See `isearch-query-replace' for more information.

As each match is found, the user must type a character saying
what to do with it.  Type SPC or `y' to replace the match,
DEL or `n' to skip and go to the next match.  For more directions,
type \\[help-command] at that time."
  (interactive
   (list current-prefix-arg))
  (isearch-query-replace arg t))

(defun isearch-occur (regexp &optional nlines)
  "Run `occur' using the last search string as the regexp.
Interactively, REGEXP is constructed using the search string from the
last search command.  NLINES has the same meaning as in `occur'.

If the last search command was a word search, REGEXP is computed from
the search words, ignoring punctuation.  If the last search
command was a regular expression search, REGEXP is the regular
expression used in that search.  If the last search command searched
for a literal string, REGEXP is constructed by quoting all the special
characters in that string."
  (interactive
   (let* ((perform-collect (consp current-prefix-arg))
	  (regexp (cond
		   ((functionp isearch-regexp-function)
		    (funcall isearch-regexp-function isearch-string))
		   (isearch-regexp-function (word-search-regexp isearch-string))
		   (isearch-regexp isearch-string)
		   (t (regexp-quote isearch-string)))))
     (list regexp
	   (if perform-collect
	       ;; Perform collect operation
	       (if (zerop (regexp-opt-depth regexp))
		   ;; No subexpression so collect the entire match.
		   "\\&"
		 ;; Get the regexp for collection pattern.
		 (let ((default (car occur-collect-regexp-history))
		       regexp-collect)
		   (with-isearch-suspended
		    (setq regexp-collect
			  (read-regexp
			   (format-prompt "Regexp to collect" default)
			   default 'occur-collect-regexp-history)))
		   regexp-collect))
	     ;; Otherwise normal occur takes numerical prefix argument.
	     (when current-prefix-arg
	       (prefix-numeric-value current-prefix-arg))))))
  (let ((case-fold-search isearch-case-fold-search)
	;; Set `search-upper-case' to nil to not call
	;; `isearch-no-upper-case-p' in `occur-1'.
	(search-upper-case nil)
	(search-spaces-regexp
	 (if (if isearch-regexp
		 isearch-regexp-lax-whitespace
	       isearch-lax-whitespace)
	     search-whitespace-regexp)))
    (occur (if isearch-regexp-function
	       (propertize regexp
			   'isearch-string isearch-string
			   'isearch-regexp-function-descr
                           (isearch--describe-regexp-mode isearch-regexp-function))
	     regexp)
	   nlines
	   (if (use-region-p) (region-bounds)))))

(declare-function hi-lock-read-face-name "hi-lock" ())

(defun isearch--highlight-regexp-or-lines (hi-lock-func)
  "Run HI-LOCK-FUNC to exit isearch, leaving the matches highlighted.
This is the internal function used by `isearch-highlight-regexp'
and `isearch-highlight-lines-matching-regexp' to invoke
HI-LOCK-FUNC (either `highlight-regexp' or `highlight-lines-matching-regexp',
respectively)."
  (let (
	;; Set `isearch-recursive-edit' to nil to prevent calling
	;; `exit-recursive-edit' in `isearch-done' that terminates
	;; the execution of this command when it is non-nil.
	;; We call `exit-recursive-edit' explicitly at the end below.
	(isearch-recursive-edit nil))
    (isearch-done nil t)
    (isearch-clean-overlays))
  (require 'hi-lock nil t)
  (let ((regexp (cond ((functionp isearch-regexp-function)
                       (funcall isearch-regexp-function isearch-string))
		      (isearch-regexp-function (word-search-regexp isearch-string))
		      (isearch-regexp isearch-string)
		      (t (regexp-quote isearch-string)))))
    (let ((case-fold-search isearch-case-fold-search)
          ;; Set `search-upper-case' to nil to not call
          ;; `isearch-no-upper-case-p' in `hi-lock'.
          (search-upper-case nil)
          (search-spaces-regexp
           (if (if isearch-regexp
                   isearch-regexp-lax-whitespace
                 isearch-lax-whitespace)
               search-whitespace-regexp)))
      (funcall hi-lock-func regexp (hi-lock-read-face-name) isearch-string)))
  (and isearch-recursive-edit (exit-recursive-edit)))

(defun isearch-highlight-regexp ()
  "Exit Isearch mode and call `highlight-regexp'.
The arguments passed to `highlight-regexp' are the regexp from
the last search and the face from `hi-lock-read-face-name'."
  (interactive)
  (isearch--highlight-regexp-or-lines
   (lambda (regexp face lighter)
     (highlight-regexp regexp face nil lighter))))

(defun isearch-highlight-lines-matching-regexp ()
  "Exit Isearch mode and call `highlight-lines-matching-regexp'.
The arguments passed to `highlight-lines-matching-regexp' are the
regexp from the last search and the face from `hi-lock-read-face-name'."
  (interactive)
  (isearch--highlight-regexp-or-lines
   (lambda (regexp face _lighter)
     (highlight-lines-matching-regexp regexp face))))


(defun isearch-delete-char ()
  "Undo last input item during a search.

An input item is the result of a command that pushes a new state
of isearch (as recorded by the `isearch--state' structure) to
`isearch-cmds'.  Info node `(emacs)Basic Isearch' explains when
Emacs records a new input item.

If no input items have been entered yet, just beep."
  (interactive)
  (if (null (cdr isearch-cmds))
      (ding)
    (isearch-pop-state))
  ;; When going back to the hidden match, reopen it and close other overlays.
  (when (and (eq isearch-invisible 'open) isearch-hide-immediately)
    (if isearch-other-end
        (let ((search-invisible isearch-invisible))
          (isearch-range-invisible (min (point) isearch-other-end)
                                   (max (point) isearch-other-end)))
      (isearch-close-unnecessary-overlays (point) (point))))
  (isearch-update))

(defun isearch-del-char (&optional arg)
  "Delete character from end of search string and search again.
Unlike `isearch-delete-char', it only deletes the last character,
but doesn't cancel the effect of other isearch command.
If search string is empty, just beep."
  (interactive "p")
  (if (= 0 (length isearch-string))
      (ding)
    (setq isearch-string (substring isearch-string 0
				    (- (min (or arg 1)
					    (length isearch-string))))
          isearch-message (mapconcat 'isearch-text-char-description
                                     isearch-string "")))
  ;; Do the following before moving point.
  (funcall (or isearch-message-function #'isearch-message) nil t)
  ;; Use the isearch-other-end as new starting point to be able
  ;; to find the remaining part of the search string again.
  ;; This is like what `isearch-search-and-update' does,
  ;; but currently it doesn't support deletion of characters
  ;; for the case where unsuccessful search may become successful
  ;; by deletion of characters.
  (if isearch-other-end (goto-char isearch-other-end))
  (isearch-search)
  (isearch-push-state)
  (isearch-update))

(defun isearch-yank-string (string)
  "Pull STRING into search string."
  ;; Downcase the string if not supposed to case-fold yanked strings.
  (if (and isearch-case-fold-search
	   (eq 'not-yanks search-upper-case))
      (setq string (downcase string)))
  (if isearch-regexp (setq string (regexp-quote string)))
  ;; Don't move cursor in reverse search.
  (setq isearch-yank-flag t)
  (isearch-process-search-string
   string (mapconcat 'isearch-text-char-description string "")))

(defun isearch-yank-kill ()
  "Pull string from kill ring into search string."
  (interactive)
  (unless isearch-mode (isearch-mode t))
  (isearch-yank-string (current-kill 0)))

(defun isearch-yank-from-kill-ring ()
  "Read a string from the `kill-ring' and append it to the search string."
  (interactive)
  (with-isearch-suspended
   (let ((string (read-from-kill-ring "Yank from kill-ring: ")))
     (if (and isearch-case-fold-search
              (eq 'not-yanks search-upper-case))
         (setq string (downcase string)))
     (if isearch-regexp (setq string (regexp-quote string)))
     (setq isearch-yank-flag t)
     (setq isearch-new-string (concat isearch-string string)
           isearch-new-message (concat isearch-message
                                       (mapconcat 'isearch-text-char-description
                                                  string ""))))))

(defun isearch-yank-pop ()
  "Replace just-yanked search string with previously killed string.
Unlike `isearch-yank-pop-only', when this command is called not immediately
after a `isearch-yank-kill' or a `isearch-yank-pop', it activates the
minibuffer to read a string from the `kill-ring' as `yank-pop' does."
  (interactive)
  (if (not (memq last-command '(isearch-yank-kill
                                isearch-yank-pop isearch-yank-pop-only)))
      (isearch-yank-from-kill-ring)
    (isearch-pop-state)
    (isearch-yank-string (current-kill 1))))

(defun isearch-yank-pop-only (&optional arg)
  "Replace just-yanked search string with previously killed string.
Unlike `isearch-yank-pop', when this command is called not immediately
after a `isearch-yank-kill' or a `isearch-yank-pop-only', it only pops
the last killed string instead of activating the minibuffer to read
a string from the `kill-ring' as `yank-pop' does.  The prefix arg \\[universal-argument]
always reads a string from the `kill-ring' using the minibuffer."
  (interactive "P")
  (cond
   ((equal arg '(4))
    (isearch-yank-from-kill-ring))
   ((not (memq last-command '(isearch-yank-kill
                              isearch-yank-pop isearch-yank-pop-only)))
    ;; Fall back on `isearch-yank-kill' for the benefits of people
    ;; who are used to the old behavior of `M-y' in isearch mode.
    ;; In future, `M-y' could be changed from `isearch-yank-pop-only'
    ;; to `isearch-yank-pop' that uses the kill-ring-browser.
    (isearch-yank-kill))
   (t
    (isearch-pop-state)
    (isearch-yank-string (current-kill 1)))))

(defun isearch-yank-x-selection ()
  "Pull current PRIMARY X selection into the search string."
  (interactive)
  (isearch-yank-string (ignore-errors (gui-get-primary-selection)))
  ;; If `gui-get-selection' returned the text from the active region,
  ;; then it "used" the mark which we should hence deactivate.
  (when select-active-regions (deactivate-mark)))


(defun isearch-mouse-2 (click)
  "Handle mouse-2 in Isearch mode.
For a click in the echo area, invoke `isearch-yank-x-selection'.
Otherwise invoke whatever the calling mouse-2 command sequence
is bound to outside of Isearch."
  (interactive "e")
  (let ((w (posn-window (event-start click)))
        (binding (let ((overriding-terminal-local-map isearch--saved-local-map)
                       ;; Key search depends on mode (bug#47755)
                       (isearch-mode nil))
                   (key-binding (this-command-keys-vector) t))))
    (if (or mouse-yank-at-point
            (and (window-minibuffer-p w)
	         (not (minibuffer-window-active-p w)))) ; in echo area
        (isearch-yank-x-selection)
      (when (functionp binding)
	(call-interactively binding)))))

(declare-function xterm--pasted-text "term/xterm" ())

(defun isearch-xterm-paste (event)
  "Pull terminal paste into search string."
  (interactive "e")
  (when (eq (car-safe event) 'xterm-paste)
    (let ((pasted-text (nth 1 event)))
      (isearch-yank-string pasted-text))))

(defvar isearch--yank-prev-point nil)

(defun isearch-yank-internal (jumpform)
  "Pull the text from point to the point reached by JUMPFORM.
JUMPFORM is a lambda expression that takes no arguments and returns
a buffer position, possibly having moved point to that position.
For example, it might move point forward by a word and return point,
or it might return the position of the end of the line."
  (isearch-yank-string
   (save-excursion
     (and (not isearch-forward) isearch-other-end
	  (goto-char isearch-other-end))
     (and (not isearch-success) isearch--yank-prev-point
	  (goto-char isearch--yank-prev-point))
     (buffer-substring-no-properties
      (point)
      (prog1
	  (setq isearch--yank-prev-point (funcall jumpform))
	(when isearch-success
	  (setq isearch--yank-prev-point nil)))))))

(defun isearch-yank-char-in-minibuffer (&optional arg)
  "Pull next character from buffer into end of search string in minibuffer."
  (interactive "p")
  (if (eobp)
      (insert
       (with-minibuffer-selected-window
         (buffer-substring-no-properties
          (point) (progn (forward-char arg) (point)))))
    (forward-char arg)))

(defun isearch-yank-char (&optional arg)
  "Pull next character from buffer into search string.
If optional ARG is non-nil, pull in the next ARG characters."
  (interactive "p")
  (isearch-yank-internal (lambda () (forward-char arg) (point))))

(defun isearch--yank-char-or-syntax (syntax-list fn &optional arg)
  (isearch-yank-internal
   (lambda ()
     (dotimes (_ arg)
       (if (or (memq (char-syntax (or (char-after) 0)) syntax-list)
               (memq (char-syntax (or (char-after (1+ (point))) 0))
                     syntax-list))
	   (funcall fn 1)
         (forward-char 1)))
     (point))))

(defun isearch-yank-word-or-char (&optional arg)
  "Pull next character or word from buffer into search string.
If optional ARG is non-nil, pull in the next ARG characters/words."
  (interactive "p")
  (isearch--yank-char-or-syntax '(?w) 'forward-word arg))

(defun isearch-yank-symbol-or-char (&optional arg)
  "Pull next character or symbol from buffer into search string.
If optional ARG is non-nil, pull in the next ARG characters/symbols."
  (interactive "p")
  (isearch--yank-char-or-syntax '(?w ?_) 'forward-symbol arg))

(defun isearch-yank-word (&optional arg)
  "Pull next word from buffer into search string.
If optional ARG is non-nil, pull in the next ARG words."
  (interactive "p")
  (isearch-yank-internal (lambda () (forward-word arg) (point))))

(defun isearch-yank-until-char (char &optional arg)
  "Pull everything until next instance of CHAR from buffer into search string.
Interactively, prompt for CHAR.
If optional ARG is non-nil, pull until next ARGth instance of CHAR.
This is often useful for keyboard macros, for example in programming
languages or markup languages in which CHAR marks a token boundary."
  (interactive "cYank until character: \np")
  (isearch-yank-internal
   (lambda () (let ((inhibit-field-text-motion t))
                (condition-case nil
                    (progn
                      (search-forward (char-to-string char) nil nil arg)
                      (forward-char -1))
                  (search-failed
                   (message "`%c' not found" char)
                   (sit-for 2)))
                (point)))))

(defun isearch-yank-line (&optional arg)
  "Pull rest of line from buffer into search string.
If optional ARG is non-nil, yank the next ARG lines."
  (interactive "p")
  (isearch-yank-internal
   (lambda () (let ((inhibit-field-text-motion t))
		(line-end-position (if (eolp) (1+ arg) arg))))))

(defun isearch-char-by-name (&optional count)
  "Read a character by its Unicode name and add it to the search string.
Completion is available like in `read-char-by-name' used by `insert-char'.
With argument, add COUNT copies of the character."
  (interactive "p")
  (with-isearch-suspended
   (let ((char (read-char-by-name "Add character to search (Unicode name or hex): ")))
     (when char
       (let ((string (if (and (integerp count) (> count 1))
			 (make-string count char)
		       (char-to-string char))))
	 (setq isearch-new-string (concat isearch-new-string string)
	       isearch-new-message (concat isearch-new-message
					   (mapconcat 'isearch-text-char-description
						      string ""))))))))

(autoload 'emoji--read-emoji "emoji")
(defun isearch-emoji-by-name (&optional count)
  "Read an Emoji name and add it to the search string COUNT times.
COUNT (interactively, the prefix argument) defaults to 1.
The command accepts Unicode names like \"smiling face\" or
\"heart with arrow\", and completion is available."
  (interactive "p")
  (emoji--init)
  (with-isearch-suspended
   (pcase-let* ((`(,glyph . ,derived) (emoji--read-emoji))
                (emoji (if derived
                           (completing-read "Select derivation: "
                                            (cons glyph derived) nil t)
                         glyph)))
     (when (and (integerp count) (> count 1))
       (setq emoji (apply 'concat (make-list count emoji))))
     (when emoji
       (setq isearch-new-string (concat isearch-new-string emoji)
             isearch-new-message (concat isearch-new-message
					   (mapconcat 'isearch-text-char-description
						      emoji "")))))))

(defun isearch-search-and-update ()
  "Do the search and update the display."
  (when (or isearch-success
	    ;; Unsuccessful regexp search may become successful by
	    ;; addition of characters which make isearch-string valid
	    isearch-regexp
	    ;; If the string was found but was completely invisible,
	    ;; it might now be partly visible, so try again.
	    (prog1 isearch-hidden (setq isearch-hidden nil)))
    ;; In reverse search, adding stuff at
    ;; the end may cause zero or many more chars to be
    ;; matched, in the string following point.
    ;; Allow all those possibilities without moving point as
    ;; long as the match does not extend past search origin.
    (if (and (not isearch-forward) (not isearch-adjusted)
	     (condition-case ()
		 (let ((case-fold-search isearch-case-fold-search))
		   (if (and (eq case-fold-search t) search-upper-case)
		       (setq case-fold-search
			     (isearch-no-upper-case-p isearch-string isearch-regexp)))
		   (looking-at (cond
				((functionp isearch-regexp-function)
				 (funcall isearch-regexp-function isearch-string t))
				(isearch-regexp-function (word-search-regexp isearch-string t))
				(isearch-regexp isearch-string)
				(t (regexp-quote isearch-string)))))
	       (error nil))
	     (or isearch-yank-flag
		 (<= (match-end 0)
		     (min isearch-opoint isearch-barrier))))
	(progn
	  (setq isearch-success t
		isearch-error nil
		isearch-other-end (match-end 0))
	  (if (and (eq isearch-case-fold-search t) search-upper-case)
	      (setq isearch-case-fold-search
		    (isearch-no-upper-case-p isearch-string isearch-regexp))))
      ;; Not regexp, not reverse, or no match at point.
      ;; Do the following before moving point.
      (funcall (or isearch-message-function #'isearch-message) nil t)
      (if (and isearch-other-end (not isearch-adjusted))
	  (goto-char (if isearch-forward isearch-other-end
		       (min isearch-opoint
			    isearch-barrier
			    (1+ isearch-other-end)))))
      (isearch-search)
      (when (and (memq isearch-wrap-pause '(no no-ding))
                 (not isearch-success))
        (let ((isearch-cmds isearch-cmds))
          (isearch-repeat (if isearch-forward 'forward 'backward))))))
  (isearch-push-state)
  (if isearch-op-fun (funcall isearch-op-fun))
  (isearch-update))


;; *, ?, }, and | chars can make a regexp more liberal.
;; They can make a regexp match sooner or make it succeed instead of failing.
;; So go back to place last successful search started
;; or to the last ^S/^R (barrier), whichever is nearer.
;; + needs no special handling because the string must match at least once.

(defun isearch-backslash (str)
  "Return t if STR ends in an odd number of backslashes."
  (oddp (- (length str) (string-match "\\\\*\\'" str))))

(defun isearch-fallback (want-backslash &optional allow-invalid to-barrier)
  "Return point to previous successful match to allow regexp liberalization.
\\<isearch-mode-map>
Respects \\[isearch-repeat-forward] and \\[isearch-repeat-backward] by \
stopping at `isearch-barrier' as needed.

Do nothing if a backslash is escaping the liberalizing character.
If WANT-BACKSLASH is non-nil, invert this behavior (for \\} and \\|).

Do nothing if regexp has recently been invalid unless optional
ALLOW-INVALID non-nil.

If optional TO-BARRIER non-nil, ignore previous matches and go exactly
to the barrier."
  ;; (eq (not a) (not b)) makes all non-nil values equivalent
  (when (and isearch-regexp (eq (not (isearch-backslash isearch-string))
				(not want-backslash))
	     ;; We have to check 2 stack frames because the last might be
	     ;; invalid just because of a backslash.
	     (or (not isearch-error)
		 (not (isearch--state-error (cadr isearch-cmds)))
		 allow-invalid))
    (if to-barrier
	(progn (goto-char isearch-barrier)
	       (setq isearch-adjusted t))
      (let* ((stack isearch-cmds)
	     (previous (cdr stack))	; lookbelow in the stack
	     (frame (car stack)))
	;; Walk down the stack looking for a valid regexp (as of course only
	;; they can be the previous successful match); this conveniently
	;; removes all bracket-sets and groups that might be in the way, as
	;; well as partial \{\} constructs that the code below leaves behind.
	;; Also skip over postfix operators -- though horrid,
	;; 'ab?\{5,6\}+\{1,2\}*' is perfectly valid.
	(while (and previous
		    (or (isearch--state-error frame)
			(let* ((string (isearch--state-string frame))
			       (lchar (aref string (1- (length string)))))
			  ;; The operators aren't always operators; check
			  ;; backslashes.  This doesn't handle the case of
			  ;; operators at the beginning of the regexp not
			  ;; being special, but then we should fall back to
			  ;; the barrier anyway because it's all optional.
			  (if (isearch-backslash
			       (isearch--state-string (car previous)))
			      (eq lchar ?\})
			    (memq lchar '(?* ?? ?+))))))
	  (setq stack previous previous (cdr previous) frame (car stack)))
	(when stack
	  ;; `stack' now refers the most recent valid regexp that is not at
	  ;; all optional in its last term.  Now dig one level deeper and find
	  ;; what matched before that.
	  (let ((last-other-end
		 (or (and (car previous)
			  (isearch--state-other-end (car previous)))
		     isearch-barrier)))
	    (goto-char (if isearch-forward
			   (max last-other-end isearch-barrier)
			 (min last-other-end isearch-barrier)))
	    (setq isearch-adjusted t)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; scrolling within Isearch mode.  Alan Mackenzie (acm@muc.de), 2003/2/24
;;
;; The idea here is that certain vertical scrolling commands (like C-l
;; `recenter') should be usable WITHIN Isearch mode.  For a command to be
;; suitable, it must NOT alter the buffer, swap to another buffer or frame,
;; tamper with isearch's state, or move point.  It is unacceptable for the
;; search string to be scrolled out of the current window.  If a command
;; attempts this, we scroll the text back again.
;;
;; We implement this feature with a property called `isearch-scroll'.
;; If a command's symbol has the value t for this property or for the
;; `scroll-command' property, it is a scrolling command.  The feature
;; needs to be enabled by setting the customizable variable
;; `isearch-allow-scroll' to a non-nil value.
;;
;; The universal argument commands (e.g. C-u) in simple.el are marked
;; as scrolling commands, and isearch.el has been amended to allow
;; prefix arguments to be passed through to scrolling commands.  Thus
;; M-0 C-l will scroll point to the top of the window.
;;
;; Horizontal scrolling commands are currently not catered for.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Set the isearch-scroll property on some standard functions:
;; Scroll-bar functions:
(if (fboundp 'scroll-bar-toolkit-scroll)
    (put 'scroll-bar-toolkit-scroll 'isearch-scroll t))
(if (fboundp 'w32-handle-scroll-bar-event)
    (put 'w32-handle-scroll-bar-event 'isearch-scroll t))

;; Commands which scroll the window (some scroll commands
;; already have the `scroll-command' property on them):
(put 'recenter 'isearch-scroll t)
(put 'recenter-top-bottom 'isearch-scroll t)
(put 'reposition-window 'isearch-scroll t)

;; Commands which act on the other window
(put 'list-buffers 'isearch-scroll t)
(put 'scroll-other-window 'isearch-scroll t)
(put 'scroll-other-window-down 'isearch-scroll t)
(put 'beginning-of-buffer-other-window 'isearch-scroll t)
(put 'end-of-buffer-other-window 'isearch-scroll t)
(put 'recenter-other-window 'isearch-scroll t)

;; Commands which change the window layout
(put 'delete-other-windows 'isearch-scroll t)
(put 'balance-windows 'isearch-scroll t)
(put 'split-window-right 'isearch-scroll t)
(put 'split-window-below 'isearch-scroll t)
(put 'enlarge-window 'isearch-scroll t)
(put 'enlarge-window-horizontally 'isearch-scroll t)
(put 'shrink-window-horizontally 'isearch-scroll t)
(put 'shrink-window 'isearch-scroll t)
;; The next two commands don't exit Isearch in isearch-mouse-leave-buffer
(put 'mouse-drag-mode-line 'isearch-scroll t)
(put 'mouse-drag-vertical-line 'isearch-scroll t)

;; For context menu with isearch submenu
(put 'context-menu-open 'isearch-scroll t)

;; Aliases for split-window-*
(put 'split-window-vertically 'isearch-scroll t)
(put 'split-window-horizontally 'isearch-scroll t)

;; Universal argument commands
(put 'universal-argument 'isearch-scroll t)
(put 'universal-argument-more 'isearch-scroll t)
(put 'negative-argument 'isearch-scroll t)
(put 'digit-argument 'isearch-scroll t)

(defcustom isearch-allow-scroll nil
  "Whether scrolling is allowed during incremental search.
If non-nil, scrolling commands can be used in Isearch mode.
However, you cannot scroll far enough that the current match is
no longer visible (is off screen).  But if the value is `unlimited'
that limitation is removed and you can scroll any distance off screen.
If nil, scrolling commands exit Isearch mode.
See also the related option `isearch-allow-motion'."
  :type '(choice (const :tag "Scrolling exits Isearch" nil)
                 (const :tag "Scrolling with current match on screen" t)
                 (const :tag "Scrolling with current match off screen" unlimited))
  :group 'isearch)

(put 'beginning-of-buffer 'isearch-motion
     (cons (lambda () (goto-char (point-min))) 'forward))
(put 'end-of-buffer 'isearch-motion
     (cons (lambda () (goto-char (point-max)) (recenter -1 t)) 'backward))
(put 'scroll-up-command 'isearch-motion
     (cons (lambda () (goto-char (window-end)) (recenter 0 t)) 'forward))
(put 'scroll-down-command 'isearch-motion
     (cons (lambda () (goto-char (window-start)) (recenter -1 t)) 'backward))

(defcustom isearch-allow-motion nil
  "Whether to allow movement between isearch matches by cursor motion commands.
If non-nil, the four motion commands \\<isearch-mode-map>\\[beginning-of-buffer], \\[end-of-buffer], \
\\[scroll-up-command] and \\[scroll-down-command], when invoked
during Isearch, move respectively to the first occurrence of the current
search string in the buffer, the last one, the first one after the current
window, and the last one before the current window.
If nil, these motion commands normally exit Isearch and are executed.
See also the related options `isearch-motion-changes-direction' and
`isearch-allow-scroll'."
  :type '(choice (const :tag "Off" nil)
                 (const :tag "On" t))
  :group 'isearch
  :version "28.1")

(defcustom isearch-motion-changes-direction nil
  "Whether motion commands during incremental search change search direction.
If nil, the search direction (forward or backward) does not change when
motion commands are used during incremental search, except when wrapping.
If non-nil, the search direction is forward after \
\\<isearch-mode-map>\\[beginning-of-buffer] and \\[scroll-up-command], and
backward after \\[end-of-buffer] and \\[scroll-down-command]."
  :type '(choice (const :tag "Off" nil)
                 (const :tag "On" t))
  :group 'isearch
  :version "28.1")

(defcustom isearch-allow-prefix t
  "Whether prefix arguments are allowed during incremental search.
If non-nil, entering a prefix argument will not terminate the
search.  This option is ignored \(presumed t) when
`isearch-allow-scroll' is set."
  :version "24.4"
  :type 'boolean
  :group 'isearch)

(defun isearch-string-out-of-window (isearch-point)
  "Test whether the search string is currently outside of the window.
Return nil if it's completely visible, or if point is visible,
together with as much of the search string as will fit; the symbol
`above' if we need to scroll the text downwards; the symbol `below',
if upwards."
  (let ((w-start (window-group-start))
        (w-end (window-group-end nil t))
        (w-L1 (save-excursion
                (save-selected-window (move-to-window-group-line 1) (point))))
        (w-L-1 (save-excursion
                 (save-selected-window (move-to-window-group-line -1) (point))))
        start end)                  ; start and end of search string in buffer
    (if isearch-forward
        (setq end isearch-point  start (or isearch-other-end isearch-point))
      (setq start isearch-point  end (or isearch-other-end isearch-point)))
    (cond ((or (and (>= start w-start) (<= end w-end))
               (if isearch-forward
                   (and (>= isearch-point w-L-1) (< isearch-point w-end)) ; point on Line -1
                 (and (>= isearch-point w-start) (< isearch-point w-L1)))) ; point on Line 0
           nil)
          ((and (< start w-start)
                (< isearch-point w-L-1))
           'above)
          (t 'below))))

(defun isearch-back-into-window (above isearch-point)
  "Scroll the window to bring the search string back into view.
Restore point to ISEARCH-POINT in the process.  ABOVE is t when the
search string is above the top of the window, nil when it is beneath
the bottom."
  (let (start end)
    (if isearch-forward
        (setq end isearch-point  start (or isearch-other-end isearch-point))
      (setq start isearch-point  end (or isearch-other-end isearch-point)))
    (if above
        (progn
          (goto-char start)
          (recenter-window-group 0)
          (when (>= isearch-point (window-group-end nil t))
            (goto-char isearch-point)
            (recenter-window-group -1)))
      (goto-char end)
      (recenter-window-group -1)
      (when (< isearch-point (window-group-start))
        (goto-char isearch-point)
        (recenter-window-group 0))))
  (goto-char isearch-point))

(defvar isearch-pre-scroll-point nil)
(defvar isearch-pre-move-point nil)

(defcustom isearch-yank-on-move nil
  "Motion keys yank text to the search string while you move the cursor.
If `shift', extend the search string by motion commands while holding down
the shift key.  The search string is extended by yanking text that
ends at the new position after moving point in the current buffer.
If t, extend the search string without the shift key pressed.
To enable motion commands, put the `isearch-move' property on their
symbols to `enabled', or to disable an automatically detected
shift-translated command, use the property value `disabled'."
  :type '(choice (const :tag "Motion keys exit Isearch" nil)
                 (const :tag "Motion keys extend the search string" t)
                 (const :tag "Shifted motion keys extend the search string" shift))
  :group 'isearch
  :version "27.1")

(defun isearch-pre-command-hook ()
  "Decide whether to exit Isearch mode before executing the command.
Don't exit Isearch if the key sequence that invoked this command
is bound in `isearch-mode-map', or if the invoked command is
a prefix argument command (when `isearch-allow-prefix' is non-nil),
or it is a scrolling command (when `isearch-allow-scroll' is non-nil).
Otherwise, exit Isearch (when `search-exit-option' is t)
before the command is executed globally with terminated Isearch.
See more for options in `search-exit-option'."
  (let* ((key (this-single-command-keys))
	 (main-event (aref key 0)))
    (cond
     ;; Don't exit Isearch if we're in the middle of some
     ;; `set-transient-map' thingy like `universal-argument--mode'.
     ((not (eq overriding-terminal-local-map isearch--saved-overriding-local-map)))
     ;; Don't exit Isearch for isearch key bindings.
     ((or (commandp (lookup-key isearch-mode-map key nil))
          (commandp
           (lookup-key
            `(keymap (tool-bar menu-item nil ,isearch-tool-bar-map)) key))))
     ;; Allow key bindings that open a menubar.
     ((memq this-command isearch-menu-bar-commands))
     ;; Optionally edit the search string instead of exiting.
     ((eq search-exit-option 'edit)
      (setq this-command 'isearch-edit-string))
     ;; Handle motion command functions.
     ((and isearch-allow-motion
           (symbolp this-command)
           (get this-command 'isearch-motion)
           ;; Don't override `isearch-yank-on-move' used below.
           (not (and (eq isearch-yank-on-move 'shift)
                     this-command-keys-shift-translated)))
      (let* ((property (get this-command 'isearch-motion))
             (function (car property))
             (current-direction (if isearch-forward 'forward 'backward))
             (direction (or (cdr property)
                            (if isearch-forward 'forward 'backward))))
        (funcall function)
        (setq isearch-just-started t)
        (let ((isearch-repeat-on-direction-change nil))
          (isearch-repeat direction))
        (when (and isearch-success (not isearch-motion-changes-direction))
          (unless (eq direction current-direction)
            (let ((isearch-repeat-on-direction-change nil))
              (isearch-repeat current-direction))))
        (setq this-command 'ignore)))
     ;; Handle a scrolling function or prefix argument.
     ((or (and isearch-allow-prefix
               (memq this-command '(universal-argument universal-argument-more
				    digit-argument negative-argument)))
	  (and isearch-allow-scroll
	       (symbolp this-command)
	       (or (eq (get this-command 'isearch-scroll) t)
		   (eq (get this-command 'scroll-command) t))))
      (when isearch-allow-scroll
	(unless (eq isearch-allow-scroll 'unlimited)
          (setq isearch-pre-scroll-point (point)))))
     ;; A mouse click on the isearch message starts editing the search string.
     ((and (eq (car-safe main-event) 'down-mouse-1)
	   (window-minibuffer-p (posn-window (event-start main-event))))
      ;; Swallow the up-event.
      (read--potential-mouse-event)
      (setq this-command 'isearch-edit-string))
     ;; Don't terminate the search for motion commands.
     ((and isearch-yank-on-move
           (symbolp this-command)
           (not (eq (get this-command 'isearch-move) 'disabled))
           (or (eq (get this-command 'isearch-move) 'enabled)
               (and (eq isearch-yank-on-move t)
                    (stringp (nth 1 (interactive-form this-command)))
                    (string-match-p "^\\^"
				    (nth 1 (interactive-form this-command))))
               (and (eq isearch-yank-on-move 'shift)
                    this-command-keys-shift-translated)))
      (setq this-command-keys-shift-translated nil)
      (setq isearch-pre-move-point (point)))
     ;; Append control characters to the search string
     ((eq search-exit-option 'append)
      (unless (memq nil (mapcar #'characterp key))
        (isearch-process-search-string key key))
      (setq this-command 'ignore))
     ;; Other characters terminate the search and are then executed normally.
     (search-exit-option
      (isearch-done)
      (isearch-clean-overlays)))))

(defun isearch-post-command-hook ()
   (when isearch-pre-scroll-point
     (let ((ab-bel (isearch-string-out-of-window isearch-pre-scroll-point)))
       (if ab-bel
	   (isearch-back-into-window (eq ab-bel 'above) isearch-pre-scroll-point)
	 (goto-char isearch-pre-scroll-point)))
     (setq isearch-pre-scroll-point nil)
     (isearch-update))
   (when (eq isearch-allow-scroll 'unlimited)
     (when isearch-lazy-highlight
       (isearch-lazy-highlight-new-loop)))
   (when isearch-pre-move-point
     (when (not (eq isearch-pre-move-point (point)))
       (let ((string (buffer-substring-no-properties
                      (or isearch-other-end isearch-opoint) (point))))
         (if isearch-regexp (setq string (regexp-quote string)))
         (setq isearch-string string)
         (setq isearch-message (mapconcat 'isearch-text-char-description
                                          string ""))
         (setq isearch-yank-flag t)
         (setq isearch-forward (<= (or isearch-other-end isearch-opoint) (point)))
         (when isearch-forward
           (goto-char isearch-pre-move-point))
         (isearch-search-and-update)))
     (setq isearch-pre-move-point nil))
  (force-mode-line-update))

(defun isearch-quote-char (&optional count)
  "Quote special characters for incremental search.
With argument, add COUNT copies of the character."
  (interactive "p")
  (let ((char (read-quoted-char (isearch-message t))))
    (unless (characterp char)
      (user-error "%s is not a valid character"
		  (key-description (vector char))))
    ;; Assume character codes 0200 - 0377 stand for characters in some
    ;; single-byte character set, and convert them to Emacs
    ;; characters.
    (if (and isearch-regexp isearch-regexp-lax-whitespace (= char ?\s))
	(if (subregexp-context-p isearch-string (length isearch-string))
	    (isearch-process-search-string "[ ]" " ")
	  (isearch-process-search-char char count))
      ;; This used to assume character codes 0240 - 0377 stand for
      ;; characters in some single-byte character set, and converted them
      ;; to Emacs characters.  But in 23.1 this feature is deprecated
      ;; in favor of inserting the corresponding Unicode characters.
      ;; (and enable-multibyte-characters
      ;;      (>= char ?\200)
      ;;      (<= char ?\377)
      ;;      (setq char (unibyte-char-to-multibyte char)))
      (isearch-process-search-char char count))))

(defun isearch-printing-char (&optional char count)
  "Add this ordinary printing CHAR to the search string and search.
With argument, add COUNT copies of the character."
  (interactive (list last-command-event
		     (prefix-numeric-value current-prefix-arg)))
  (let ((char (or char last-command-event)))
    (if (= char ?\S-\ )
	(setq char ?\s))
    (if current-input-method
	(isearch-process-search-multibyte-characters char count)
      (isearch-process-search-char char count))))

(defun isearch-process-search-char (char &optional count)
  "Add CHAR to the search string, COUNT times.
Search is updated accordingly."
  ;; * and ? are special in regexps when not preceded by \.
  ;; } and | are special in regexps when preceded by \.
  ;; Nothing special for + because it matches at least once.
  (cond
   ((memq char '(?* ??)) (isearch-fallback nil))
   ((eq   char ?\})      (isearch-fallback t t))
   ((eq   char ?|)       (isearch-fallback t nil t)))

  ;; Append the char(s) to the search string,
  ;; update the message and re-search.
  (let* ((string (if (and (integerp count) (> count 1))
		     (make-string count char)
		   (char-to-string char)))
	 (message (if (>= char ?\200)
		      string
		    (mapconcat 'isearch-text-char-description string ""))))
    (isearch-process-search-string string message)))

(defun isearch-process-search-string (string message)
  (setq isearch-string (concat isearch-string string)
	isearch-message (concat isearch-message message))
  (isearch-search-and-update))


;; Search Ring

(defun isearch-ring-adjust1 (advance)
  ;; Helper for isearch-ring-adjust
  (let* ((ring (if isearch-regexp regexp-search-ring search-ring))
	 (length (length ring))
	 (yank-pointer-name (if isearch-regexp
				'regexp-search-ring-yank-pointer
			      'search-ring-yank-pointer))
	 (yank-pointer (eval yank-pointer-name)))
    (if (zerop length)
	()
      (set yank-pointer-name
	   (setq yank-pointer
		 (mod (+ (or yank-pointer (if advance 0 -1))
			 (if advance -1 1))
		      length)))
      (setq isearch-string (nth yank-pointer ring)
	    isearch-message (mapconcat 'isearch-text-char-description
				       isearch-string ""))
      (isearch-update-from-string-properties isearch-string))))

(defun isearch-ring-adjust (advance)
  ;; Helper for isearch-ring-advance and isearch-ring-retreat
  (isearch-ring-adjust1 advance)
  (if search-ring-update
      (progn
        (funcall (or isearch-message-function #'isearch-message) nil t)
	(isearch-search)
	(isearch-push-state)
	(isearch-update))
    ;; Otherwise, edit the search string instead.  Note that there is
    ;; no need to push the search state after isearch-edit-string here
    ;; since isearch-edit-string already pushes its state
    (isearch-edit-string)))

(defun isearch-ring-advance ()
  "Advance to the next search string in the ring."
  ;; This could be more general to handle a prefix arg, but who would use it.
  (interactive)
  (isearch-ring-adjust 'advance))

(defun isearch-ring-retreat ()
  "Retreat to the previous search string in the ring."
  (interactive)
  (isearch-ring-adjust nil))

(defun isearch-complete1 ()
  ;; Helper for isearch-complete and isearch-complete-edit
  ;; Return t if completion OK, nil if no completion exists.
  (let* ((ring (if isearch-regexp regexp-search-ring search-ring))
         (completion-ignore-case case-fold-search)
         (completion (try-completion isearch-string ring)))
    (cond
     ((eq completion t)
      ;; isearch-string stays the same
      t)
     ((or completion ; not nil, must be a string
	  (= 0 (length isearch-string))) ; shouldn't have to say this
      (if (equal completion isearch-string)  ;; no extension?
	  (progn
	    (if completion-auto-help
		(with-output-to-temp-buffer "*Isearch completions*"
		  (display-completion-list
		   (all-completions isearch-string ring))))
	    t)
	(and completion
	     (setq isearch-string completion))))
     (t
      (message "No completion") ; waits a second if in minibuffer
      nil))))

(defun isearch-complete ()
  "Complete the search string from the strings on the search ring.
The completed string is then editable in the minibuffer.
If there is no completion possible, say so and continue searching."
  (interactive)
  (if (isearch-complete1)
      (progn (setq isearch-message
		   (mapconcat 'isearch-text-char-description
			      isearch-string ""))
	     (isearch-edit-string))
    ;; else
    (sit-for 1)
    (isearch-update)))

(defun isearch-complete-edit ()
  "Same as `isearch-complete' except in the minibuffer."
  (interactive)
  (setq isearch-string (field-string))
  (if (isearch-complete1)
      (progn
	(delete-field)
	(insert isearch-string))))


;; Message string

(defun isearch-message (&optional c-q-hack ellipsis)
  "Generate and print the message string."

  ;; N.B.: This function should always be called with point at the
  ;; search point, because in certain (rare) circumstances, undesired
  ;; scrolling can happen when point is elsewhere.  These
  ;; circumstances are when follow-mode is active, the search string
  ;; spans two (or several) windows, and the message about to be
  ;; displayed will cause the echo area to expand.
  (let ((cursor-in-echo-area ellipsis)
	(m isearch-message)
	(fail-pos (isearch-fail-pos t)))
    ;; Highlight failed part
    (when fail-pos
      (setq m (copy-sequence m))
      (add-text-properties fail-pos (length m) '(face isearch-fail) m)
      ;; Highlight failed trailing whitespace
      (when (string-match " +$" m)
	(add-text-properties (match-beginning 0) (match-end 0)
			     '(face trailing-whitespace) m)))
    (setq m (concat
	     (isearch-message-prefix ellipsis isearch-nonincremental)
	     m
	     (isearch-message-suffix c-q-hack)))
    (if c-q-hack m (let ((message-log-max nil)) (message "%s" m)))))

(defun isearch--describe-regexp-mode (regexp-function &optional space-before)
  "Make a string for describing REGEXP-FUNCTION.
If SPACE-BEFORE is non-nil, put a space before, instead of after,
the word mode."
  (when (eq regexp-function t)
    (setq regexp-function #'word-search-regexp))
  (let ((description
         (cond
          ;; 1. Do not use a description on the default search mode,
          ;;    but only if the default search mode is non-nil.
          ((and (or (and search-default-mode
                         (equal search-default-mode regexp-function))
                    ;; Special case where `search-default-mode' is t
                    ;; (defaults to regexp searches).
                    (and (eq search-default-mode t)
                         (eq search-default-mode isearch-regexp)))
                ;; Also do not omit description in case of error
                ;; in default non-literal search.
                (or isearch-success (not (or regexp-function isearch-regexp))))
           "")
          ;; 2. Use the `isearch-message-prefix' set for
          ;;    `regexp-function' if available.
          (regexp-function
           (and (symbolp regexp-function)
                (or (get regexp-function 'isearch-message-prefix)
                    "")))
          ;; 3. Else if `isearch-regexp' is non-nil, set description
          ;;    to "regexp ".
          (isearch-regexp "regexp ")
          ;; 4. Else if we're in literal mode (and if the default
          ;;    mode is also not literal), describe it.
          ((functionp search-default-mode) "literal ")
          ;; 5. And finally, if none of the above is true, set the
          ;;    description to an empty string.
          (t ""))))
    (if space-before
        ;; Move space from the end to the beginning.
        (replace-regexp-in-string "\\(.*\\) \\'" " \\1" description)
      description)))
(define-obsolete-function-alias 'isearch--describe-word-mode
  'isearch--describe-regexp-mode "25.1")

(defun isearch-message-prefix (&optional ellipsis nonincremental)
  ;; If about to search, and previous search regexp was invalid,
  ;; check that it still is.  If it is valid now,
  ;; let the message we display while searching say that it is valid.
  (and isearch-error ellipsis
       (condition-case ()
	   (progn (re-search-forward isearch-string (point) t)
		  (setq isearch-error nil))
	 (error nil)))
  ;; If currently failing, display no ellipsis.
  (or isearch-success (setq ellipsis nil))
  (let ((m (concat (if isearch-success "" "failing ")
		   (if (eq isearch-adjusted t) "pending " "")
		   (if (and isearch-wrapped
			    (not isearch-wrap-function)
			    (if isearch-forward
				(> (point) isearch-opoint)
			      (< (point) isearch-opoint)))
		       "over")
		   (if isearch-wrapped "wrapped ")
                   (if (and (not isearch-success) (buffer-narrowed-p) widen-automatically)
                       "narrowed " "")
                   (if (and (not isearch-success) (not isearch-case-fold-search))
                       "case-sensitive ")
                   (let ((prefix ""))
                     (dolist (advice-function (list isearch-filter-predicate
                                                    isearch-search-fun-function))
                       (advice-function-mapc
                        (lambda (_ props)
                          (let ((np (cdr (assq 'isearch-message-prefix props))))
                            (if np (setq prefix (concat np prefix)))))
                        advice-function))
                     prefix)
                   (isearch--describe-regexp-mode isearch-regexp-function)
		   (cond
		    (multi-isearch-file-list "multi-file ")
		    (multi-isearch-buffer-list "multi-buffer ")
		    (t ""))
		   (or isearch-message-prefix-add "")
		   (if nonincremental "search" "I-search")
		   (if isearch-forward "" " backward")
		   (if current-input-method
		       ;; Input methods for RTL languages use RTL
		       ;; characters for their title, and that messes
		       ;; up the display of search text after the prompt.
		       (bidi-string-mark-left-to-right
			(concat " [" current-input-method-title "]: "))
		     ": ")
		   )))
    (apply #'propertize (concat (isearch-lazy-count-format)
                        (upcase (substring m 0 1)) (substring m 1))
	   isearch-message-properties)))

(defun isearch-message-suffix (&optional c-q-hack)
  (apply #'propertize (concat (if c-q-hack "^Q" "")
		      (isearch-lazy-count-format 'suffix)
		      (if isearch-error
			  (concat " [" isearch-error "]")
			"")
		      (or isearch-message-suffix-add ""))
	 isearch-message-properties))

(defun isearch-lazy-count-format (&optional suffix-p)
  "Format the current match number and the total number of matches.
When SUFFIX-P is non-nil, the returned string is intended for
`isearch-message-suffix' prompt.  Otherwise, for
`isearch-message-prefix'."
  (let ((format-string (if suffix-p
                           lazy-count-suffix-format
                         lazy-count-prefix-format)))
    (if (and format-string
             isearch-lazy-count
             isearch-lazy-count-current
             (not isearch-error)
             (not isearch-suspended))
        (format format-string
                (if isearch-lazy-highlight-forward
                    isearch-lazy-count-current
                  (if (eq isearch-lazy-count-current 0)
                      0
                    (- isearch-lazy-count-total
                       isearch-lazy-count-current
                       -1)))
                (if (and isearch-lazy-count-invisible
                         lazy-count-invisible-format)
                    (concat (format "%s" (or isearch-lazy-count-total "?"))
                            (format lazy-count-invisible-format
                                    isearch-lazy-count-invisible))
                  (or isearch-lazy-count-total "?")))
      "")))


;; Searching

(defvar isearch-search-fun-function 'isearch-search-fun-default
  "Non-default value overrides the behavior of `isearch-search-fun-default'.
This variable's value should be a function, which will be called
with no arguments, and should return a function that takes three
arguments: STRING, BOUND, and NOERROR.  STRING is the string to
be searched for.  See `re-search-forward' for the meaning of
BOUND and NOERROR arguments.

This returned function will be used by `isearch-search-string' to
search for the first occurrence of STRING.")

(defun isearch-search-fun ()
  "Return the function to use for the search.
Can be changed via `isearch-search-fun-function' for special needs."
  (funcall (or isearch-search-fun-function 'isearch-search-fun-default)))

(defun isearch--lax-regexp-function-p ()
  "Non-nil if next regexp-function call should be lax."
  (or (memq this-command '(isearch-printing-char isearch-del-char))
      isearch-yank-flag))

(defun isearch-search-fun-default ()
  "Return default functions to use for the search."
  (lambda (string &optional bound noerror count)
    (let (;; Evaluate this before binding `search-spaces-regexp' which
          ;; can break all sorts of regexp searches.  In particular,
          ;; calling `isearch-regexp-function' can trigger autoloading
          ;; (Bug#35802).
          (regexp
           (cond (isearch-regexp-function
                  (let ((lax (and (not bound) ; not lazy-highlight
                                  (isearch--lax-regexp-function-p))))
                    (when lax
                      (setq isearch-adjusted 'lax))
                    (if (functionp isearch-regexp-function)
                        (funcall isearch-regexp-function string lax)
                      (word-search-regexp string lax))))
                 (isearch-regexp string)
                 (t (regexp-quote string))))
          ;; Use lax versions to not fail at the end of the word while
          ;; the user adds and removes characters in the search string
          ;; (or when using nonincremental word isearch)
          (search-spaces-regexp (when (if isearch-regexp
                                          isearch-regexp-lax-whitespace
                                        isearch-lax-whitespace)
                                  search-whitespace-regexp)))
      (funcall
       (if isearch-forward #'re-search-forward #'re-search-backward)
       regexp bound noerror count))))

(defun isearch-search-string (string bound noerror)
  "Search for the first occurrence of STRING or its translation.
STRING's characters are translated using `translation-table-for-input'
if that is non-nil.
If found, move point to the end of the occurrence,
update the match data, and return point.
An optional second argument bounds the search; it is a buffer position.
The match found must not extend after that position.
Optional third argument, if t, means if fail just return nil (no error).
  If not nil and not t, move to limit of search and return nil."
  (let* ((func (isearch-search-fun))
         (pos1 (save-excursion (funcall func string bound noerror)))
         pos2)
    (when (and
	   ;; Avoid "obsolete" warnings for translation-table-for-input.
	   (with-no-warnings
	     (char-table-p translation-table-for-input))
	   (multibyte-string-p string)
	   ;; Minor optimization.
	   (string-match-p "[^[:ascii:]]" string))
      (let ((translated
             (apply 'string
                    (mapcar (lambda (c)
                              (or
			       ;; Avoid "obsolete" warnings for
			       ;; translation-table-for-input.
			       (with-no-warnings
				 (aref translation-table-for-input c))
			       c))
                            string)))
            match-data)
        (when translated
          (save-match-data
            (save-excursion
              (if (setq pos2 (funcall func translated bound noerror))
                  (setq match-data (match-data t)))))
          (when (and pos2
                     (or (not pos1)
                         (if isearch-forward (< pos2 pos1) (> pos2 pos1))))
            (setq pos1 pos2)
            (set-match-data match-data)))))
    (when pos1
      ;; When using multiple buffers isearch, switch to the new buffer here,
      ;; because `save-excursion' above doesn't allow doing it inside funcall.
      (when multi-isearch-next-buffer-current-function
        (multi-isearch-switch-buffer))
      (goto-char pos1)
      pos1)))

(defun isearch-search ()
  "Do the search with the current search string."
  (if (and (eq isearch-case-fold-search t) search-upper-case)
      (setq isearch-case-fold-search
	    (isearch-no-upper-case-p isearch-string isearch-regexp)))
  (condition-case lossage
      (let ((inhibit-quit nil)
	    (case-fold-search isearch-case-fold-search)
	    (search-invisible isearch-invisible)
	    (retry t))
	(setq isearch-error nil)
	(while retry
	  (setq isearch-success
		(isearch-search-string isearch-string nil t))
	  ;; Clear RETRY unless the search predicate says
	  ;; to skip this search hit.
	  (if (or (not isearch-success)
		  (funcall isearch-filter-predicate
			   (match-beginning 0) (match-end 0)))
	      (setq retry nil)
	    ;; Advance point on empty matches before retrying
	    (when (= (match-beginning 0) (match-end 0))
	      (if (if isearch-forward (eobp) (bobp))
		  (setq retry nil isearch-success nil)
		(forward-char (if isearch-forward 1 -1))))))
	(setq isearch-just-started nil)
	(when isearch-success
	  (setq isearch-other-end
		(if isearch-forward (match-beginning 0) (match-end 0)))
          (setq isearch-match-data (match-data t))))

    (quit (isearch-unread ?\C-g)
	  (setq isearch-success nil))

    (invalid-regexp
     (setq isearch-error (car (cdr lossage)))
     (cond
      ((string-match
	"\\`Premature \\|\\`Unmatched "
	isearch-error)
       (setq isearch-error "incomplete input"))
      ((and (not isearch-regexp)
	    (string-match "\\`Regular expression too big" isearch-error))
       (cond
	(isearch-regexp-function
         (setq isearch-error nil)
         (setq isearch-regexp-function nil)
         (isearch-search-and-update)
         (isearch--momentary-message "Too many words; switched to literal mode" 2))
	((and isearch-lax-whitespace search-whitespace-regexp)
	 (setq isearch-error "Too many spaces for whitespace matching"))))))

    (search-failed
     (setq isearch-success nil)
     (setq isearch-error (nth 2 lossage)))

    (error
     ;; stack overflow in regexp search.
     (setq isearch-error (format "%s" lossage))))

  (unless isearch-success
    ;; Ding if failed this time after succeeding last time.
    (and (isearch--state-success (car isearch-cmds))
	 (not (eq isearch-wrap-pause 'no-ding))
	 (ding))
    (if (functionp (isearch--state-pop-fun (car isearch-cmds)))
        (funcall (isearch--state-pop-fun (car isearch-cmds))
                 (car isearch-cmds)))
    (goto-char (isearch--state-point (car isearch-cmds)))))


;; Called when opening an overlay, and we are still in isearch.
(defun isearch-open-overlay-temporary (ov)
  (if (not (null (overlay-get ov 'isearch-open-invisible-temporary)))
      ;; Some modes would want to open the overlays temporary during
      ;; isearch in their own way, they should set the overlay's
      ;; `isearch-open-invisible-temporary' property to a function
      ;; doing this.
      ;; Warning: if your code uses this technique, it should not
      ;; delete the overlay passed to that function, since the values
      ;; of the `invisible' property will be recorded on that overlay,
      ;; to be restored after isearch is done with the text hidden by
      ;; the overlay.
      (funcall  (overlay-get ov 'isearch-open-invisible-temporary)  ov nil)
    ;; Store the values for the `invisible' property, and then set it to nil.
    ;; This way the text hidden by this overlay becomes visible.
    (overlay-put ov 'isearch-invisible (overlay-get ov 'invisible))
    (overlay-put ov 'invisible nil)))


;; This is called at the end of isearch.  It will open the overlays
;; that contain the latest match.  Obviously in case of a C-g the
;; point returns to the original location which surely is not contain
;; in any of these overlays, se we are safe in this case too.
(defun isearch-open-necessary-overlays (ov)
  (let ((inside-overlay (and  (> (point) (overlay-start ov))
			      (<= (point) (overlay-end ov))))
	;; If this exists it means that the overlay was opened using
	;; this function, not by us tweaking the overlay properties.
	(fct-temp (overlay-get ov 'isearch-open-invisible-temporary)))
    (when (or inside-overlay (not fct-temp))
      ;; restore the values for the `invisible' properties.
      (overlay-put ov 'invisible (overlay-get ov 'isearch-invisible))
      (overlay-put ov 'isearch-invisible nil))
    (if inside-overlay
	(funcall (overlay-get ov 'isearch-open-invisible)  ov)
      (if fct-temp
	  (funcall fct-temp ov t)))))

;; This is called when exiting isearch. It closes the temporary
;; opened overlays, except the ones that contain the latest match.
(defun isearch-clean-overlays ()
  (when isearch-opened-overlays
    (mapc 'isearch-open-necessary-overlays isearch-opened-overlays)
    (setq isearch-opened-overlays nil)))


(defun isearch-intersects-p (start0 end0 start1 end1)
  "Return t if regions START0..END0 and START1..END1 intersect."
  (or (and (>= start0 start1) (<  start0 end1))
      (and (>  end0 start1)   (<= end0 end1))
      (and (>= start1 start0) (<  start1 end0))
      (and (>  end1 start0)   (<= end1 end0))))


;; Verify if the current match is outside of each element of
;; `isearch-opened-overlays', if so close that overlay.

(defun isearch-close-unnecessary-overlays (beg end)
  (let ((overlays isearch-opened-overlays))
    (setq isearch-opened-overlays nil)
    (dolist (ov overlays)
      (if (isearch-intersects-p beg end (overlay-start ov) (overlay-end ov))
	  (push ov isearch-opened-overlays)
	(let ((fct-temp (overlay-get ov 'isearch-open-invisible-temporary)))
	  (if fct-temp
	      ;; If this exists it means that the overlay was opened
	      ;; using this function, not by us tweaking the overlay
	      ;; properties.
	      (funcall fct-temp ov t)
	    (overlay-put ov 'invisible (overlay-get ov 'isearch-invisible))
	    (overlay-put ov 'isearch-invisible nil)))))))


(defun isearch-range-invisible (beg end)
  "Return t if all the text from BEG to END is invisible."
  (when (/= beg end)
    ;; Check that invisibility runs up to END.
    (save-excursion
      (goto-char beg)
      (let (;; can-be-opened keeps track if we can open some overlays.
	    (can-be-opened (memq search-invisible '(open can-be-opened)))
	    ;; the list of overlays that could be opened
	    (crt-overlays nil))
	(when (and can-be-opened isearch-hide-immediately
		   (not (eq search-invisible 'can-be-opened)))
	  (isearch-close-unnecessary-overlays beg end))
	;; If the following character is currently invisible,
	;; skip all characters with that same `invisible' property value.
	;; Do that over and over.
	(while (and (< (point) end) (invisible-p (point)))
	  (if (invisible-p (get-text-property (point) 'invisible))
	      (progn
		(goto-char (next-single-property-change (point) 'invisible
							nil end))
		;; if text is hidden by an `invisible' text property
		;; we cannot open it at all.
		(setq can-be-opened nil))
	    (when can-be-opened
	      (let ((overlays (overlays-at (point)))
		    ov-list
		    o
		    invis-prop)
		(while overlays
		  (setq o (car overlays)
			invis-prop (overlay-get o 'invisible))
		  (if (invisible-p invis-prop)
		      (if (overlay-get o 'isearch-open-invisible)
			  (setq ov-list (cons o ov-list))
			;; We found one overlay that cannot be
			;; opened, that means the whole chunk
			;; cannot be opened.
			(setq can-be-opened nil)))
		  (setq overlays (cdr overlays)))
		(if can-be-opened
		    ;; It makes sense to append to the open
		    ;; overlays list only if we know that this is
		    ;; t.
		    (setq crt-overlays (append ov-list crt-overlays)))))
	    (goto-char (next-overlay-change (point)))))
	;; See if invisibility reaches up thru END.
	(if (>= (point) end)
	    (if (and can-be-opened (consp crt-overlays))
		(progn
		  (unless (eq search-invisible 'can-be-opened)
		    (setq isearch-opened-overlays
			  (append isearch-opened-overlays crt-overlays))
		    (mapc 'isearch-open-overlay-temporary crt-overlays))
		  nil)
	      (setq isearch-hidden t)))))))

(defun isearch-filter-visible (beg end)
  "Return non-nil if text between BEG and END is deemed visible by Isearch.
This function is intended to be used as `isearch-filter-predicate'.
It returns non-nil if the text between BEG and END is visible to
Isearch, at least partially, as determined by `isearch-range-invisible'.
If `search-invisible' is t, which allows Isearch matches inside
invisible text, this function will always return non-nil, regardless
of what `isearch-range-invisible' says."
  (and (not (text-property-not-all beg end 'inhibit-isearch nil))
       (or (eq search-invisible t)
           (not (isearch-range-invisible beg end)))))


;; General utilities

(defun isearch-no-upper-case-p (string regexp-flag)
  "Return t if there are no upper case chars in STRING.
If REGEXP-FLAG is non-nil, disregard letters preceded by `\\' (but not `\\\\')
since they have special meaning in a regexp."
  (let (quote-flag (i 0) (len (length string)) found)
    (while (and (not found) (< i len))
      (let ((char (aref string i)))
	(if (and regexp-flag (eq char ?\\))
	    (setq quote-flag (not quote-flag))
	  (if (and (not quote-flag) (not (eq char (downcase char))))
	      (setq found t))
	  (setq quote-flag nil)))
      (setq i (1+ i)))
    (not (or found
             ;; Even if there's no uppercase char, we want to detect the use
             ;; of [:upper:] or [:lower:] char-class, which indicates
             ;; clearly that the user cares about case distinction.
             (and regexp-flag (string-match "\\[:\\(upp\\|low\\)er:]" string)
                  (condition-case err
                      (progn
                        (string-match (substring string 0 (match-beginning 0))
                                      "")
                        nil)
                    (invalid-regexp
                     (equal "Unmatched [ or [^" (cadr err)))))))))

;; Portability functions to support various Emacs versions.

(defun isearch-text-char-description (c)
  (cond
   ((< c ?\s) (propertize
	       (char-to-string c)
	       'display (propertize (format "^%c" (+ c 64)) 'face 'escape-glyph)))
   ((= c ?\^?) (propertize
		(char-to-string c)
		'display (propertize "^?" 'face 'escape-glyph)))
   (t (char-to-string c))))

;; General function to unread characters or events.
;; Also insert them in a keyboard macro being defined.
(defun isearch-unread (&rest char-or-events)
  (mapc 'store-kbd-macro-event char-or-events)
  (setq unread-command-events
	(append char-or-events unread-command-events)))


;; Highlighting

(defvar isearch-overlay nil)
(defvar isearch-submatches-overlays nil)

(defface isearch-group-1
  '((((class color) (min-colors 88) (background light))
     (:background "#f000f0" :foreground "lightskyblue1"))
    (((class color) (min-colors 88) (background dark))
     (:background "palevioletred1" :foreground "brown4"))
    (t (:inherit isearch)))
  "Face for highlighting Isearch the odd group matches."
  :group 'isearch
  :version "28.1")

(defface isearch-group-2
  '((((class color) (min-colors 88) (background light))
     (:background "#a000a0" :foreground "lightskyblue1"))
    (((class color) (min-colors 88) (background dark))
     (:background "palevioletred3" :foreground "brown4"))
    (t (:inherit isearch)))
  "Face for highlighting Isearch the even group matches."
  :group 'isearch
  :version "28.1")

(defun isearch-highlight (beg end &optional match-data)
  (if search-highlight
      (if isearch-overlay
	  ;; Overlay already exists, just move it.
	  (move-overlay isearch-overlay beg end (current-buffer))
	;; Overlay doesn't exist, create it.
	(setq isearch-overlay (make-overlay beg end))
	;; 1001 is higher than lazy's 1000 and ediff's 100+
	(overlay-put isearch-overlay 'priority 1001)
	(overlay-put isearch-overlay 'face isearch-face)))

  (when (and search-highlight-submatches isearch-regexp)
    (mapc 'delete-overlay isearch-submatches-overlays)
    (setq isearch-submatches-overlays nil)
    ;; 'cddr' removes whole expression match from match-data
    (let ((submatch-data (cddr match-data))
          (group 0)
          b e ov face)
      (while submatch-data
        (setq b (pop submatch-data)
              e (pop submatch-data))
        (when (and (integer-or-marker-p b)
                   (integer-or-marker-p e))
          (setq ov (make-overlay b e)
                group (1+ group)
                face (intern-soft (format "isearch-group-%d" group)))
          ;; Recycle faces from beginning
          (unless (facep face)
            (setq group 1 face 'isearch-group-1))
          (overlay-put ov 'face face)
          (overlay-put ov 'priority 1002)
          (push ov isearch-submatches-overlays))))))

(defun isearch-dehighlight ()
  (when isearch-overlay
    (delete-overlay isearch-overlay))
  (when search-highlight-submatches
    (mapc 'delete-overlay isearch-submatches-overlays)
    (setq isearch-submatches-overlays nil)))


;; isearch-lazy-highlight feature
;; by Bob Glickstein <http://www.zanshin.com/~bobg/>

;; When active, *every* match for the current search string is
;; highlighted: the current one using the normal isearch match color
;; and all the others using `isearch-lazy-highlight'.  The extra
;; highlighting makes it easier to anticipate where the cursor will
;; land each time you press C-s or C-r to repeat a pending search.
;; Highlighting of these additional matches happens in a deferred
;; fashion using "idle timers," so the cycles needed do not rob
;; isearch of its usual snappy response.

;; IMPLEMENTATION NOTE: This depends on some isearch internals.
;; Specifically:
;;  - `isearch-update' is expected to be called (at least) every time
;;    the search string or window-start changes;
;;  - `isearch-string' is expected to contain the current search
;;    string as entered by the user;
;;  - the type of the current search is expected to be given by
;;    `isearch-regexp-function' and `isearch-regexp';
;;  - the direction of the current search is expected to be given by
;;    `isearch-forward';
;;  - the variable `isearch-error' is expected to be true
;;    only if `isearch-string' is an invalid regexp.

(defvar isearch-lazy-highlight-overlays nil)
(defvar isearch-lazy-highlight-wrapped nil)
(defvar isearch-lazy-highlight-start-limit nil)
(defvar isearch-lazy-highlight-end-limit nil)
(defvar isearch-lazy-highlight-start nil)
(defvar isearch-lazy-highlight-end nil)
(defvar isearch-lazy-highlight-timer nil)
(defvar isearch-lazy-highlight-last-string nil)
(defvar isearch-lazy-highlight-window nil)
(defvar isearch-lazy-highlight-window-group nil)
(defvar isearch-lazy-highlight-window-start nil)
(defvar isearch-lazy-highlight-window-end nil)
(defvar isearch-lazy-highlight-window-start-changed nil)
(defvar isearch-lazy-highlight-window-end-changed nil)
(defvar isearch-lazy-highlight-point-min nil)
(defvar isearch-lazy-highlight-point-max nil)
(defvar isearch-lazy-highlight-buffer nil)
(defvar isearch-lazy-highlight-case-fold-search nil)
(defvar isearch-lazy-highlight-invisible nil)
(defvar isearch-lazy-highlight-regexp nil)
(defvar isearch-lazy-highlight-lax-whitespace nil)
(defvar isearch-lazy-highlight-regexp-lax-whitespace nil)
(define-obsolete-variable-alias 'isearch-lazy-highlight-word
  'isearch-lazy-highlight-regexp-function "25.1")
(defvar isearch-lazy-highlight-regexp-function nil)
(defvar isearch-lazy-highlight-forward nil)
(defvar isearch-lazy-highlight-error nil)
(defvar isearch-lazy-count-current nil)
(defvar isearch-lazy-count-total nil)
(defvar isearch-lazy-count-invisible nil)
(defvar isearch-lazy-count-hash (make-hash-table))
(defvar lazy-count-update-hook nil
  "Hook run after new lazy count results are computed.")

(defun lazy-highlight-cleanup (&optional force procrastinate)
  "Stop lazy highlighting and remove extra highlighting from current buffer.
FORCE non-nil means do it whether or not `lazy-highlight-cleanup' is nil.
PROCRASTINATE non-nil means postpone cleanup to a later time.
This function is called when exiting an incremental search if
`lazy-highlight-cleanup' is non-nil."
  (interactive '(t))
  (when (and (or force lazy-highlight-cleanup) (not procrastinate))
    (while isearch-lazy-highlight-overlays
      (delete-overlay (car isearch-lazy-highlight-overlays))
      (setq isearch-lazy-highlight-overlays
            (cdr isearch-lazy-highlight-overlays))))
  (when isearch-lazy-highlight-timer
    (cancel-timer isearch-lazy-highlight-timer)
    (setq isearch-lazy-highlight-timer nil)))

(defun isearch-lazy-highlight-new-loop (&optional beg end)
  "Cleanup any previous `lazy-highlight' loop and begin a new one.
BEG and END specify the bounds within which highlighting should occur.
This is called when `isearch-update' is invoked (which can cause the
search string to change or the window to scroll).  It is also used
by other Emacs features."
  (when (and (null executing-kbd-macro)
             ;; This used to read `(sit-for 0)', but that has proved
             ;; unreliable when called from within
             ;; after-change-functions bound to certain special events.
             (redisplay)         ;make sure (window-start) is credible
             (or (not (equal isearch-string
                             isearch-lazy-highlight-last-string))
                 (not (memq (selected-window)
                            isearch-lazy-highlight-window-group))
		 (not (eq isearch-lazy-highlight-case-fold-search
			  isearch-case-fold-search))
		 (not (eq isearch-lazy-highlight-invisible
		          isearch-invisible))
		 (not (eq isearch-lazy-highlight-regexp
			  isearch-regexp))
		 (not (eq isearch-lazy-highlight-regexp-function
			  isearch-regexp-function))
		 (not (eq isearch-lazy-highlight-lax-whitespace
			  isearch-lax-whitespace))
		 (not (eq isearch-lazy-highlight-regexp-lax-whitespace
			  isearch-regexp-lax-whitespace))
		 (not (eq isearch-forward
			  isearch-lazy-highlight-forward))
		 ;; In case we are recovering from an error.
		 (not (equal isearch-error
			     isearch-lazy-highlight-error))
		 (if lazy-highlight-buffer
		     (not (= (point-min)
			     isearch-lazy-highlight-point-min))
		   (setq isearch-lazy-highlight-window-start-changed
			 (not (= (window-group-start)
			         isearch-lazy-highlight-window-start))))
		 (if lazy-highlight-buffer
		     (not (= (point-max)
			     isearch-lazy-highlight-point-max))
		   (setq isearch-lazy-highlight-window-end-changed
			 (not (= (window-group-end) ; Window may have been split/joined.
			         isearch-lazy-highlight-window-end))))))
    ;; something important did indeed change
    (lazy-highlight-cleanup t (not (equal isearch-string ""))) ;stop old timer
    (when isearch-lazy-count
      (when (or (equal isearch-string "")
                ;; Check if this place was reached by a condition above
                ;; other than changed window boundaries (that shouldn't
                ;; reset the counter)
                (and (not isearch-lazy-highlight-window-start-changed)
                     (not isearch-lazy-highlight-window-end-changed))
                ;; Also check for changes in buffer boundaries in
                ;; a possibly narrowed buffer in case lazy-highlight-buffer
                ;; is nil, thus the same check was not performed above
                (not (= (point-min)
                        isearch-lazy-highlight-point-min))
                (not (= (point-max)
                        isearch-lazy-highlight-point-max)))
        ;; Reset old counter before going to count new numbers
        (clrhash isearch-lazy-count-hash)
        (setq isearch-lazy-count-current nil
              isearch-lazy-count-total nil
              isearch-lazy-count-invisible nil)
        ;; Delay updating the message if possible, to avoid flicker
        (when (string-equal isearch-string "")
          (when (and isearch-mode (null isearch-message-function))
            (isearch-message))
          (run-hooks 'lazy-count-update-hook))))
    (setq isearch-lazy-highlight-window-start-changed nil)
    (setq isearch-lazy-highlight-window-end-changed nil)
    (setq isearch-lazy-highlight-error isearch-error)
    ;; It used to check for `(not isearch-error)' here, but actually
    ;; lazy-highlighting might find matches to highlight even when
    ;; `isearch-error' is non-nil.  (Bug#9918)
    (setq isearch-lazy-highlight-start-limit beg
	  isearch-lazy-highlight-end-limit end)
    (setq isearch-lazy-highlight-window       (selected-window)
          isearch-lazy-highlight-window-group (selected-window-group)
	  isearch-lazy-highlight-window-start (window-group-start)
	  isearch-lazy-highlight-window-end   (window-group-end)
	  isearch-lazy-highlight-point-min    (point-min)
	  isearch-lazy-highlight-point-max    (point-max)
	  isearch-lazy-highlight-buffer       lazy-highlight-buffer
	  ;; Start lazy-highlighting at the beginning of the found
	  ;; match (`isearch-other-end').  If no match, use point.
	  ;; One of the next two variables (depending on search direction)
	  ;; is used to define the starting position of lazy-highlighting
	  ;; and also to remember the current position of point between
	  ;; calls of `isearch-lazy-highlight-update', and another variable
	  ;; is used to define where the wrapped search must stop.
	  isearch-lazy-highlight-start        (or isearch-other-end (point))
	  isearch-lazy-highlight-end          (or isearch-other-end (point))
	  isearch-lazy-highlight-wrapped      nil
	  isearch-lazy-highlight-last-string  isearch-string
	  isearch-lazy-highlight-case-fold-search isearch-case-fold-search
	  isearch-lazy-highlight-invisible isearch-invisible
	  isearch-lazy-highlight-regexp       isearch-regexp
	  isearch-lazy-highlight-lax-whitespace   isearch-lax-whitespace
	  isearch-lazy-highlight-regexp-lax-whitespace isearch-regexp-lax-whitespace
	  isearch-lazy-highlight-regexp-function  isearch-regexp-function
	  isearch-lazy-highlight-forward      isearch-forward)
    ;; Extend start/end to match whole string at point (bug#19353)
    (if isearch-lazy-highlight-forward
        (setq isearch-lazy-highlight-start
	      (min (+ isearch-lazy-highlight-start
		      (1- (length isearch-lazy-highlight-last-string)))
		   (point-max)))
      (setq isearch-lazy-highlight-end
	    (max (- isearch-lazy-highlight-end
		    (1- (length isearch-lazy-highlight-last-string)))
		 (point-min))))
    (unless (equal isearch-string "")
      (setq isearch-lazy-highlight-timer
            (run-with-idle-timer (if (>= (length isearch-string)
                                         lazy-highlight-no-delay-length)
                                     0
                                   lazy-highlight-initial-delay)
                                 nil
                                 'isearch-lazy-highlight-start))))
  ;; Update the current match number only in isearch-mode and
  ;; unless isearch-mode is used specially with isearch-message-function
  (when isearch-lazy-count
    ;; Update isearch-lazy-count-current only when it was already set
    ;; at the end of isearch-lazy-highlight-buffer-update
    (when isearch-lazy-count-current
      (setq isearch-lazy-count-current
            (gethash (point) isearch-lazy-count-hash 0))
      (when (and isearch-mode (null isearch-message-function))
        (isearch-message))
      (run-hooks 'lazy-count-update-hook))))

(defun isearch-lazy-highlight-search (string bound)
  "Search ahead for the next or previous match, for lazy highlighting.
Attempt to do the search exactly the way the pending Isearch would."
  (condition-case nil
      (let ((case-fold-search isearch-lazy-highlight-case-fold-search)
	    (isearch-regexp isearch-lazy-highlight-regexp)
	    (isearch-regexp-function isearch-lazy-highlight-regexp-function)
	    (isearch-lax-whitespace
	     isearch-lazy-highlight-lax-whitespace)
	    (isearch-regexp-lax-whitespace
	     isearch-lazy-highlight-regexp-lax-whitespace)
	    (isearch-forward isearch-lazy-highlight-forward)
	    ;; Count all invisible matches, but highlight only
	    ;; matches that can be opened by visiting them later
	    (search-invisible
             (or (not (null isearch-lazy-count))
		 (and (eq isearch-lazy-highlight-invisible 'open)
                      'can-be-opened)))
	    (retry t)
	    (success nil))
	;; Use a loop like in `isearch-search'.
	(while retry
	  (setq success (isearch-search-string string bound t))
	  ;; Clear RETRY unless the search predicate says
	  ;; to skip this search hit.
	  (if (or (not success)
		  (= (match-beginning 0) (match-end 0))
		  (funcall isearch-filter-predicate
			   (match-beginning 0) (match-end 0)))
	      (setq retry nil)))
	success)
    (error nil)))

(defun isearch-lazy-highlight-match (mb me)
  (when (or (not isearch-lazy-count)
            ;; Recheck the match that possibly was intended
            ;; for counting only, but not for highlighting
            (let ((search-invisible
                   (and (eq isearch-lazy-highlight-invisible 'open)
                        'can-be-opened)))
              (funcall isearch-filter-predicate mb me)))
    (let ((ov (make-overlay mb me nil t nil)))
      (push ov isearch-lazy-highlight-overlays)
      ;; 1000 is higher than ediff's 100+,
      ;; but lower than isearch main overlay's 1001
      (overlay-put ov 'priority 1000)
      (overlay-put ov 'face 'lazy-highlight)
      (unless (or (eq isearch-lazy-highlight 'all-windows)
                  isearch-lazy-highlight-buffer)
        (overlay-put ov 'window (selected-window))))))

(defun isearch-lazy-highlight-start ()
  "Start a new lazy-highlight updating loop."
  (lazy-highlight-cleanup t) ;remove old overlays
  (isearch-lazy-highlight-update))

(defun isearch-lazy-highlight-update ()
  "Update highlighting of other matches for current search."
  (let ((max lazy-highlight-max-at-a-time)
        (looping t)
        nomore window-start window-end)
    (with-local-quit
      (save-selected-window
	(if (and (window-live-p isearch-lazy-highlight-window)
		 (not (memq (selected-window) isearch-lazy-highlight-window-group)))
	    (select-window isearch-lazy-highlight-window))
	(setq window-start (window-group-start))
	(setq window-end (window-group-end))
	(save-excursion
	  (save-match-data
	    (goto-char (if isearch-lazy-highlight-forward
			   isearch-lazy-highlight-end
			 isearch-lazy-highlight-start))
	    (while looping
	      (let* ((bound (if isearch-lazy-highlight-forward
		                (min (or isearch-lazy-highlight-end-limit (point-max))
			             (if isearch-lazy-highlight-wrapped
				         isearch-lazy-highlight-start
			               window-end))
		              (max (or isearch-lazy-highlight-start-limit (point-min))
			           (if isearch-lazy-highlight-wrapped
			               isearch-lazy-highlight-end
			             window-start))))
		     (found (isearch-lazy-highlight-search
			     isearch-lazy-highlight-last-string
			     bound)))
		(when max
		  (setq max (1- max))
		  (if (<= max 0)
		      (setq looping nil)))
		(if found
		    (let ((mb (match-beginning 0))
			  (me (match-end 0)))
		      (if (= mb me)	;zero-length match
			  (if isearch-lazy-highlight-forward
			      (if (= mb (if isearch-lazy-highlight-wrapped
					    isearch-lazy-highlight-start
					  window-end))
				  (setq found nil)
				(forward-char 1))
			    (if (= mb (if isearch-lazy-highlight-wrapped
					  isearch-lazy-highlight-end
					window-start))
				(setq found nil)
			      (forward-char -1)))

			;; non-zero-length match
			(isearch-lazy-highlight-match mb me))
		      ;; Remember the current position of point for
		      ;; the next call of `isearch-lazy-highlight-update'
		      ;; when `lazy-highlight-max-at-a-time' is too small.
		      (if isearch-lazy-highlight-forward
			  (setq isearch-lazy-highlight-end (point))
			(setq isearch-lazy-highlight-start (point)))))

		;; not found or zero-length match at the search bound
		(if (not found)
		    (if isearch-lazy-highlight-wrapped
			(setq looping nil
			      nomore  t)
		      (setq isearch-lazy-highlight-wrapped t)
		      (if isearch-lazy-highlight-forward
			  (progn
			    (setq isearch-lazy-highlight-end window-start)
			    (goto-char (max (or isearch-lazy-highlight-start-limit (point-min))
					    window-start)))
			(setq isearch-lazy-highlight-start window-end)
			(goto-char (min (or isearch-lazy-highlight-end-limit (point-max))
					window-end)))))))
	    (if nomore
		(when (or isearch-lazy-highlight-buffer
			  (and isearch-lazy-count (null isearch-lazy-count-current)))
		  (if isearch-lazy-highlight-forward
		      (setq isearch-lazy-highlight-end (point-min))
		    (setq isearch-lazy-highlight-start (point-max)))
		  (setq isearch-lazy-highlight-timer
			(run-at-time lazy-highlight-interval nil
				     'isearch-lazy-highlight-buffer-update)))
	      (setq isearch-lazy-highlight-timer
		    (run-at-time lazy-highlight-interval nil
				 'isearch-lazy-highlight-update)))))))))

(defun isearch-lazy-highlight-buffer-update ()
  "Update highlighting of other matches in the full buffer."
  (let ((max lazy-highlight-buffer-max-at-a-time)
        (looping t)
        nomore opoint window-start window-end)
    (with-local-quit
      (save-selected-window
	(if (and (window-live-p isearch-lazy-highlight-window)
		 (not (memq (selected-window) isearch-lazy-highlight-window-group)))
	    (select-window isearch-lazy-highlight-window))
	(setq opoint (point))
	(setq window-start (window-group-start))
	(setq window-end (window-group-end))
	(save-excursion
	  (save-match-data
	    (goto-char (if isearch-lazy-highlight-forward
			   isearch-lazy-highlight-end
			 isearch-lazy-highlight-start))
	    (while looping
	      (let* ((bound (if isearch-lazy-highlight-forward
				(or isearch-lazy-highlight-end-limit (point-max))
			      (or isearch-lazy-highlight-start-limit (point-min))))
		     (found (isearch-lazy-highlight-search
			     isearch-lazy-highlight-last-string
			     bound)))
		(when max
		  (setq max (1- max))
		  (if (<= max 0)
		      (setq looping nil)))
		(if found
		    (let ((mb (match-beginning 0))
			  (me (match-end 0)))
		      (if (= mb me)	;zero-length match
			  (if isearch-lazy-highlight-forward
			      (if (= mb (point-max))
				  (setq found nil)
				(forward-char 1))
			    (if (= mb (point-min))
				(setq found nil)
			      (forward-char -1)))
			(when isearch-lazy-count
			  ;; Count as invisible when can't open overlay,
			  ;; but don't leave search-invisible with the
			  ;; value `open' since then lazy-highlight
			  ;; will open all overlays with matches.
			  (if (not (let ((search-invisible
					  (if (eq isearch-lazy-highlight-invisible 'open)
					      'can-be-opened
					    isearch-lazy-highlight-invisible)))
				     (funcall isearch-filter-predicate mb me)))
			      (setq isearch-lazy-count-invisible
				    (1+ (or isearch-lazy-count-invisible 0)))
			    (setq isearch-lazy-count-total
				  (1+ (or isearch-lazy-count-total 0)))
			    (puthash (if isearch-lazy-highlight-forward me mb)
				     isearch-lazy-count-total
				     isearch-lazy-count-hash)))
			;; Don't highlight the match when this loop is used
			;; only to count matches or when matches were already
			;; highlighted within the current window boundaries
			;; by isearch-lazy-highlight-update
			(unless (or (not isearch-lazy-highlight-buffer)
				    (and (>= mb window-start) (<= me window-end)))
			  ;; non-zero-length match
			  (isearch-lazy-highlight-match mb me)))
		      ;; Remember the current position of point for
		      ;; the next call of `isearch-lazy-highlight-update'
		      ;; when `lazy-highlight-buffer-max-at-a-time' is too small.
		      (if isearch-lazy-highlight-forward
			  (setq isearch-lazy-highlight-end (point))
			(setq isearch-lazy-highlight-start (point)))))

		;; not found or zero-length match at the search bound
		(if (not found)
		    (setq looping nil
			  nomore  t))))
	    (if nomore
		(when isearch-lazy-count
		  (unless isearch-lazy-count-total
		    (setq isearch-lazy-count-total 0))
		  (setq isearch-lazy-count-current
			(gethash opoint isearch-lazy-count-hash 0))
                  (when (and isearch-mode (null isearch-message-function))
                    (isearch-message)))
	      (setq isearch-lazy-highlight-timer
		    (run-at-time lazy-highlight-interval nil
				 'isearch-lazy-highlight-buffer-update)))))
        (when (and nomore isearch-lazy-count)
          (run-hooks 'lazy-count-update-hook))))))


;; Reading from minibuffer with lazy highlight and match count

(defcustom minibuffer-lazy-count-format "%s "
  "Format of the total number of matches for the prompt prefix."
  :type '(choice (const :tag "Don't display a count" nil)
                 (string :tag "Display match count" "%s "))
  :group 'lazy-count
  :version "29.1")

(cl-defun minibuffer-lazy-highlight-setup
    (&key (highlight isearch-lazy-highlight)
          (cleanup lazy-highlight-cleanup)
          (transform #'identity)
          (filter nil)
          (regexp isearch-regexp)
          (regexp-function isearch-regexp-function)
          (case-fold isearch-case-fold-search)
          (lax-whitespace (if regexp
                              isearch-regexp-lax-whitespace
                            isearch-lax-whitespace)))
  "Set up minibuffer for lazy highlight of matches in the original window.

This function return a closure intended to be added to
`minibuffer-setup-hook'.  It accepts the following keyword
arguments, all of which have a default based on the current
isearch settings.

HIGHLIGHT: Whether to perform lazy highlight.
CLEANUP: Whether to clean up the lazy highlight when the minibuffer
exits.
TRANSFORM: A function taking one argument, the minibuffer contents,
and returning the `isearch-string' to use for lazy highlighting.
FILTER: A function to add to `isearch-filter-predicate'.
REGEXP: The value of `isearch-regexp' to use for lazy highlighting.
REGEXP-FUNCTION: The value of `isearch-regexp-function' to use for
lazy highlighting.
CASE-FOLD: The value of `isearch-case-fold' to use for lazy
highlighting.
LAX-WHITESPACE: The value of `isearch-lax-whitespace' and
`isearch-regexp-lax-whitespace' to use for lazy highlighting."
  (if (or (not highlight) (minibufferp))
      #'ignore
    (let ((unwind (make-symbol "minibuffer-lazy-highlight--unwind"))
          (after-change (make-symbol "minibuffer-lazy-highlight--after-change"))
          (display-count (make-symbol "minibuffer-lazy-highlight--display-count"))
          (buffer (current-buffer))
          overlay)
      (fset unwind
            (lambda ()
              (when filter
                (with-current-buffer buffer
                  (remove-function (local 'isearch-filter-predicate) filter)))
              (remove-hook 'lazy-count-update-hook display-count)
              (when overlay (delete-overlay overlay))
              (remove-hook 'after-change-functions after-change t)
              (remove-hook 'minibuffer-exit-hook unwind t)
              (let ((lazy-highlight-cleanup cleanup))
                (lazy-highlight-cleanup))))
      (fset after-change
            (lambda (_beg _end _len)
              (let ((inhibit-redisplay t) ;; Avoid cursor flickering
                    (string (minibuffer-contents)))
                (with-minibuffer-selected-window
                  (let* ((isearch-forward t)
                         (isearch-regexp regexp)
                         (isearch-regexp-function regexp-function)
                         (isearch-case-fold-search case-fold)
                         (isearch-lax-whitespace lax-whitespace)
                         (isearch-regexp-lax-whitespace lax-whitespace)
                         (isearch-string (funcall transform string)))
                    (isearch-lazy-highlight-new-loop))))))
      (fset display-count
            (lambda ()
              (overlay-put overlay 'before-string
                           (and isearch-lazy-count-total
                                (not isearch-error)
                                (format minibuffer-lazy-count-format
                                        isearch-lazy-count-total)))))
      (lambda ()
        (add-hook 'minibuffer-exit-hook unwind nil t)
        (add-hook 'after-change-functions after-change nil t)
        (when minibuffer-lazy-count-format
          (setq overlay (make-overlay (point-min) (point-min) (current-buffer) t))
          (add-hook 'lazy-count-update-hook display-count))
        (when filter
          (with-current-buffer buffer
            (add-function :after-while (local 'isearch-filter-predicate) filter)))
        (funcall after-change nil nil nil)))))


(defun isearch-search-fun-in-noncontiguous-region (search-fun bounds)
  "Return the function that searches inside noncontiguous regions.
A noncontiguous region is defined by the argument BOUNDS that
is a list of cons cells of the form (START . END)."
  (apply-partially
   #'search-within-boundaries
   search-fun
   (lambda (pos)
     (seq-some (lambda (b) (if isearch-forward
                               (and (>= pos (car b)) (< pos (cdr b)))
                             (and (> pos (car b)) (<= pos (cdr b)))))
               bounds))
   (lambda (pos)
     (let ((bounds (flatten-list bounds))
           found)
       (unless isearch-forward
         (setq bounds (nreverse bounds)))
       (while (and bounds (not found))
         (if (if isearch-forward (< pos (car bounds)) (> pos (car bounds)))
             (setq found (car bounds))
           (setq bounds (cdr bounds))))
       found))))

(defun isearch-search-fun-in-text-property (search-fun properties)
  "Return the function to search inside text that has the specified PROPERTIES.
The function will limit the search for matches only inside text which has
at least one of the text PROPERTIES.
The argument SEARCH-FUN provides the function to search text, and
defaults to the value of `isearch-search-fun-default' when nil."
  (setq properties (ensure-list properties))
  (apply-partially
   #'search-within-boundaries
   search-fun
   (lambda (pos)
     (let ((pos (if isearch-forward pos (max (1- pos) (point-min)))))
       (seq-some (lambda (property)
                   (get-text-property pos property))
                 properties)))
   (lambda (pos)
     (let ((pos-list (if isearch-forward
                         (mapcar (lambda (property)
                                   (next-single-property-change
                                    pos property))
                                 properties)
                       (mapcar (lambda (property)
                                 (previous-single-property-change
                                  pos property))
                               properties))))
       (setq pos-list (delq nil pos-list))
       (when pos-list (if isearch-forward
                          (seq-min pos-list)
                        (seq-max pos-list)))))))

(defun search-within-boundaries ( search-fun get-fun next-fun
                                  string &optional bound noerror count)
  (let* ((old (point))
         ;; Check if point is already on the property.
         (beg (when (funcall get-fun old) old))
         end found (i 0)
         (subregexp
          (and isearch-regexp
               (save-match-data
                 (catch 'subregexp
                   (while (string-match "\\^\\|\\$" string i)
                     (setq i (match-end 0))
                     (when (subregexp-context-p string (match-beginning 0))
                       ;; The ^/$ is not inside a char-range or escaped.
                       (throw 'subregexp t))))))))
    ;; Otherwise, try to search for the next property.
    (unless beg
      (setq beg (funcall next-fun old))
      (when beg
        (if (or (null bound)
                (if isearch-forward
                    (< beg bound)
                  (> beg bound)))
            (goto-char beg)
          (setq beg nil))))
    ;; Non-nil `beg' means there are more properties.
    (while (and beg (not found))
      ;; Search for the end of the current property.
      (setq end (funcall next-fun beg))
      ;; Handle ^/$ specially by matching in a temporary buffer.
      (if subregexp
          (let* ((prop-beg
                  (if (or (if isearch-forward (bobp) (eobp))
                          (null (funcall get-fun
                                         (+ (point)
                                            (if isearch-forward -1 1)))))
                      ;; Already at the beginning of the field.
                      beg
                    ;; Get the real beginning of the field when
                    ;; the search was started in the middle.
                    (let ((isearch-forward (not isearch-forward)))
                      ;; Search in the reverse direction.
                      (funcall next-fun beg))))
                 (substring (buffer-substring prop-beg end))
                 (offset (if isearch-forward prop-beg end))
                 match-data)
            (with-temp-buffer
              (insert substring)
              (goto-char (- beg offset -1))
              ;; Apply ^/$ regexp on the whole extracted substring.
              (setq found (funcall
                           (or search-fun (isearch-search-fun-default))
                           string (and bound (max (point-min)
                                                  (min (point-max)
                                                       (- bound offset -1))))
                           noerror count))
              ;; Adjust match data as if it's matched in original buffer.
              (when found
                (setq found (+ found offset -1)
                      match-data (mapcar (lambda (m) (+ m offset -1))
                                         (match-data)))))
            (when found (goto-char found))
            (when match-data (set-match-data
                              (mapcar #'copy-marker match-data))))
        (setq found (funcall
                     (or search-fun (isearch-search-fun-default))
                     string (if bound (if isearch-forward
                                          (min bound end)
                                        (max bound end))
                              end)
                     noerror count)))
      ;; Get the next text property.
      (unless found
        (setq beg (funcall next-fun end))
        (when beg
          (if (or (null bound)
                  (if isearch-forward
                      (< beg bound)
                    (> beg bound)))
              (goto-char beg)
            (setq beg nil)))))
    (unless found (goto-char old))
    found))


(defun isearch-resume (string regexp word forward message case-fold)
  "Resume an incremental search.
STRING is the string or regexp searched for.
REGEXP non-nil means the resumed search was a regexp search.
WORD non-nil means resume a word search.
FORWARD non-nil means resume a forward search.
MESSAGE is the echo-area message recorded for the search resumed.
CASE-FOLD non-nil means the search was case-insensitive."
  (isearch-mode forward regexp nil nil word)
  (setq isearch-string string
	isearch-message message
	isearch-case-fold-search case-fold)
  (isearch-search)
  (isearch-push-state)
  (isearch-update))


(defvar isearch-fold-quotes-mode--state)
(define-minor-mode isearch-fold-quotes-mode
  "Minor mode to aid searching for \\=` characters in help modes."
  :lighter ""
  (if isearch-fold-quotes-mode
      (setq-local isearch-fold-quotes-mode--state
                  (buffer-local-set-state
                   search-default-mode
                   (lambda (string &optional _lax)
                     (thread-last
                       (regexp-quote string)
                       (replace-regexp-in-string "`" "[`‘]")
                       (replace-regexp-in-string "'" "['’]")
                       (replace-regexp-in-string "\"" "[\"“”]")))))
    (buffer-local-restore-state isearch-fold-quotes-mode--state)))

(define-obsolete-function-alias 'isearch-mode-help #'isearch-describe-mode "29.1")

(provide 'isearch)

;;; isearch.el ends here
