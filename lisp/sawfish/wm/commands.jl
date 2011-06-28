;; commands.jl -- manages commands
;;
;; Copyright (C) 2000 John Harper <john@dcs.warwick.ac.uk>
;;
;; This file is part of sawfish.
;;
;; sawfish is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; sawfish is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with sawfish; see the file COPYING.  If not, write to
;; the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.

(define-structure sawfish.wm.commands

    (export define-command
	    autoload-command
	    command-ref
	    command-type
	    command-class
	    apply-command
	    call-command
	    prefix-numeric-argument
	    commandp
	    command-documentation
	    report-commands

	    ;; autoloaded from with-output.jl
	    call-command-with-output-to-screen
	    define-command-to-screen)

    (open rep
	  rep.system
	  rep.regexp
	  rep.util.autoloader
	  rep.lang.doc
	  #|
	    Don't add more sawfish.wm.* here unless you know what
	    you're doing. Instead, embed 'require' in definition. It's
	    because this file is read from windows.jl. See windows.jl
	    for more.
	  |#
	  sawfish.wm.misc
	  sawfish.wm.gaol
	  sawfish.wm.events
	  sawfish.wm.windows.subrs
	  sawfish.wm.util.with-output)

  (defvar customize-command-classes '(default)
    "In configurator \"binding\" section, show commands of
these classes. For possible keys, see `command-classes-all'".)

  (defvar command-classes-all '(default advanced viewport deprecated)
    "List of all command classes.")

  (defvar pre-command-hook '()
    "Hook called before calling each command.")

  (defvar post-command-hook '()
    "Hook called after calling each command.")

  (defvar this-command nil
    "The command currently being called, or `nil' if no command is being
evaluated.")

  (defvar last-command nil
    "The command previously called.")

;;; defining commands

  ;; spec is cadr of old (interactive ...) style thing

  (define (getter name) (get name 'command-fun))
  (define (setter name fun) (put name 'command-fun fun))
  (define autoloader (make-autoloader getter setter))
  (define real-getter (autoloader-ref getter))

  (define (apply-command-keys name #!key spec type doc class)
    (when spec
      (put name 'command-spec spec))
    (when type
      (put name 'custom-command-args type))
    (when doc
      (put name 'command-doc doc))
    (when class
      (put name 'command-class class)))

  (define (define-command name fun . keys)
    "Define a window managed command called NAME (a symbol). The
function FUN will be called to execute the command. SPEC and TYPE may
be used to define the arguments expected by the command. (an
interactive specification and a custom-type specification respectively)."
    (setter name fun)
    (apply apply-command-keys name keys))

  (define (define-command-gaol name fun . keys)
    "Version of `define-commnad' which can be used in gaol.
You can't override an existing command."
    (when (and (not (boundp name))
	       (functionp fun))
      (make-variable-special name)
      (apply define-command name fun keys)))
  (gaol-add define-command-gaol)
  
  (define (autoload-command name module . keys)
    "Record that loading the module called MODULE (a symbol) will provde a
command called NAME (optionally whose arguments have custom-type TYPE)."
    (autoloader name module)
    (apply apply-command-keys name keys))

  ;; return the function associated with command NAME, or nil
  (define (command-ref name)
    (or (real-getter name)
	(condition-case nil
	    (user-eval name)
	  (error nil))))

  ;; return the spec associated with command NAME, or nil
  (define (command-spec name)
    (or (get name 'command-spec)
	(cadr (function-spec (command-ref name)))))

  (define (command-type name) (get name 'custom-command-args))
  (define (command-class name) (or (get name 'command-class) 'default))

  (define (commandp arg)
    "Return t if ARG names a command."
    (and (symbolp arg)
	 ;; check this first to avoid loading autoloads
	 (or (get arg 'command-fun)
	     (let ((fun (command-ref arg)))
	       (and fun (function-spec fun))))))

;;; calling commands

  (define (apply-command name args)
    "Apply the list of values ARGS to the command NAME."
    (let ((fun (command-ref name)))
      (or (functionp fun)
	  (error "Command has no function: %s" name))
      (apply fun args)))

  (define (call-command name #!optional pfx-arg)
    "Call the command NAME; optionally with the prefix argument PFX-ARG."

    ;; `name' is a lisp expression for commands with `type',
    ;; among others.
    
    ;; prefix
    (let ((this-command name))
      (unless pfx-arg (setq pfx-arg prefix-arg))
      (setq prefix-arg nil)
      (setq current-prefix-arg pfx-arg)

      ;; pre-command-hook is allowed to modifiy this-command
      ;; and current-prefix-arg. If this-command is set to nil the
      ;; command won't be called
      (call-hook 'pre-command-hook (list name))

      (setq name this-command)
      (setq pfx-arg current-prefix-arg)

      ;; call
      (cond ((null name))

	    ((commandp name)
	     ;; a named command
	     (command-ref name) ;so spec is loaded
	     (let ((spec (command-spec name))
		   args)
	       (when spec
		 (setq args (build-arg-list spec name)))
	       ;; reinitialize current-prefix-arg in case it got overwritten
	       (setq current-prefix-arg pfx-arg)
	       (apply-command name args)))

	    ((commandp (car name))
	     (apply-command (car name) (mapcar user-eval (cdr name))))

	    ((functionp name)
	     (let ((spec (function-spec name)))
	       (if spec
		   ;; function has an embedded spec, so use it
		   (let ((args (build-arg-list (cadr spec) name)))
		     (setq current-prefix-arg pfx-arg)
		     (apply name args))
		 ;; no spec, just call it
		 (name))))

	    (t (user-eval name)))		;just eval it

      ;; postfix
      (call-hook 'post-command-hook (list name))
      (setq last-command this-command)
      (setq current-prefix-arg nil)))

  (define-command 'call-command call-command
    #:spec "CEnter command:\nP")

;;; building command arg-list from spec strings

  (define arg-can-be-nil (make-fluid))

  (define (build-arg-list spec name)
    (cond ((stringp spec)
	   (let loop ((args '())
		      (point 0))
	     (cond ((>= point (length spec)) (nreverse args))
		   ((eql (aref spec point) #\newline)
		    (loop (cons nil args) (1+ point)))
		   (t
		    (let ((local nil)
			  (code nil)
			  (prompt nil))
		      (if (eql (aref spec point) #\%)
			  (progn
			    (setq local t)
			    (setq code (aref spec (1+ point)))
			    (setq point (+ point 2)))
			(setq code (aref spec point))
			(setq point (1+ point)))
		      (let ((end (if (string-match "(\n|$)" spec point)
				     (match-start)
				   (length spec))))
			(unless (= point end)
			  (setq prompt (substring spec point end)))
			(setq point (1+ end)))
		      (let (arg)
			(let-fluids ((arg-can-be-nil nil))
			  (setq arg (if local
					(local-codes code prompt)
				      (global-codes code prompt)))
			  (when (and (not (fluid arg-can-be-nil))
				     (null arg))
			    (error "Null argument to command: %s"
				   name)))
			(loop (cons arg args) point)))))))
	  ((functionp spec) (spec))
	  ((consp spec) (user-eval spec))))

;;; switching on spec codes

  ;; codes local to sawfish, i.e. "%X" case, where X is one of:
  (define (local-codes code prompt)
    (case code
      ((#\f)
       (input-focus))

      ((#\w)
       (current-event-window))

      ((#\W)
       (let ((w (current-event-window)))
	 (if (or (null w) (eq w 'root))
	     (input-focus)
	   w)))

      ((#\s)
       (require 'sawfish.wm.util.prompt)
       (prompt-for-workspace prompt))

      (t (error "Unknown spec: %%%c" code))))

  ;; general rep codes
  (define (global-codes code prompt)
    (case code
      ((#\a)
       (require 'sawfish.wm.util.prompt)
       (prompt-for-function prompt))

      ((#\C)
       (fluid-set arg-can-be-nil t)
       (require 'sawfish.wm.util.prompt)
       (prompt-for-command prompt))

      ((#\D)
       (require 'sawfish.wm.util.prompt)
       (prompt-for-directory prompt))

      ((#\e) (current-event))

      ((#\E) (current-event-string))

      ((#\f)
       (require 'sawfish.wm.util.prompt)
       (prompt-for-file prompt t))

      ((#\F)
       (require 'sawfish.wm.util.prompt)
       (prompt-for-file prompt))

      ((#\k)
       (require 'sawfish.wm.util.keymap)
       (read-event))

      ((#\n)
       (require 'sawfish.wm.util.prompt)
       (prompt-for-number prompt))

      ((#\N)
       (if current-prefix-arg
	   (prefix-numeric-argument current-prefix-arg)
	 (require 'sawfish.wm.util.prompt)
	 (prompt-for-number prompt)))

      ((#\p) (prefix-numeric-argument current-prefix-arg))

      ((#\P) (fluid-set arg-can-be-nil t) current-prefix-arg)

      ((#\s)
       (require 'sawfish.wm.util.prompt)
       (prompt-for-string prompt))

      ((#\S)
       (fluid-set arg-can-be-nil t)
       (require 'sawfish.wm.util.prompt)
       (prompt-for-symbol prompt))

      ((#\t) t)

      ((#\v)
       (require 'sawfish.wm.util.prompt)
       (prompt-for-variable prompt))

      (t (error "Unknown spec: %c" code))))

  (define (prefix-numeric-argument arg)
    (cond ((symbolp arg) (if (null arg) 1 -1))
	  ((numberp arg) arg)
	  ((consp arg) (car arg))
	  (t 1)))

;;; utilities

  ;; dig out the interactive spec from a function
  (define (function-spec fun)
    (and (closurep fun)
	 (let ((body (closure-function fun)))
	   (cond ((bytecodep body)
		  ;; interactive spec is 5th element of the vector
		  (and (>= (length body) 5) (list 'interactive (aref body 4))))
		 ((eq (car body) 'lambda)
		  ;; search for interactive decl at head of body
		  (let loop ((rest (cddr body)))
		    (cond ((stringp (car rest)) (loop (cdr rest)))
			  ((eq (caar rest) 'interactive) (car rest))
			  (t nil))))))))

  (define (command-documentation name)
    "Return the documentation associated with the command called NAME."
    (cond ((get name 'command-doc))
	  (t
	   (let ((value (command-ref name)))
	     ;; assume that the command has the same name as
	     ;; the underlying function
	     (or (documentation name nil value)
		 ;; XXX last chance, kludge by looking for the
		 ;; XXX name of the closure...
		 (and (closurep value) (closure-name value)
		      (documentation (intern (closure-name value))
				     nil value)))))))

  (define (report-commands #!optional type all)
    "Returns the list of commands. Each element is the symbol of
a command name, and they're sorted alphabetically.

The optional argument TYPE is for internal use. When it's non-nil,
(command-name #:type type-param) is returned for commands with
\"type\", instead of a symbol.

If the optional argument ALL is nil, returns commands only user wants,
i.e. those specified by `customize-command-class' are included. Else,
all commands are returned."
    (let ((classes (if all
		       command-classes-all
		     customize-command-classes)))
      (mapcar (lambda (sym)
		(let ((params (command-type sym)))
		  (if (and type params)
		      (list sym #:type params)
		    sym)))
	      (sort (apropos "" (lambda (x)
				  (and (commandp x)
				       (memq (command-class x) classes))))))))

;;; some default commands

  (define (run-shell-command command)
    "Execute a shell command in the background. This is a wrapper
command for the `system' function."
    (system (format nil "%s &" command)))

  (define-command 'run-shell-command run-shell-command
    #:spec "sCommand:"
    #:type `(and (labelled ,(_ "Command:") string))
    #:doc "Execute the given shell command in the background.")

  (define (command-sequence commands)
    "Invoke the list of commands, one by one."
    (mapc call-command commands))

  (define-command 'command-sequence command-sequence
    #:type `(and (quoted (list command ,(_ "Command")))))

  (define-command 'quit quit
    #:doc "Quit sawfish.")
  (define-command 'restart restart
    #:doc "Restart sawfish.")
  (define-command 'destroy-window destroy-window #:spec "%W"
    #:doc "Destroy a window.")
  (define-command 'kill-client x-kill-client #:spec "%W"
    #:doc "Kill the client that created the specified window.")
  (define-command 'no-operation nop)

  (define (call-command-with-output-to-screen command)
    "Prompt for a command, execute it, and print any output to the screen."
    (call-with-output-to-screen (lambda () (call-command command))))

  (define-command 'call-command-with-output-to-screen
    call-command-with-output-to-screen #:spec "CCommand:")

  (define (define-command-to-screen name fun #!rest keys)
    (apply define-command name (lambda args (with-output-to-screen
                                              (apply fun args))) keys))

  )
