;; animation/setup.jl -- Set up animation feature.

;; Copyright (C) 2000 John Harper <john@dcs.warwick.ac.uk>

;; This file is part of sawfish.

;; sawfish is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; sawfish is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with sawfish; see the file COPYING.  If not, write to
;; the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.

(define-structure sawfish.wm.animation.setup

    (export define-window-animator
	    autoload-window-animator
	    run-window-animator
	    record-window-animator)

    (open rep
	  rep.system
	  sawfish.wm.windows
	  sawfish.wm.custom
	  rep.util.autoloader)
  ;; For backward compatibility.
  (define-structure-alias window-anim sawfish.wm.animation.setup)

  (define window-animators nil
    "List of all possible window animation types.")

  (defgroup animation "Animation" :group appearance)

  (defcustom default-window-animator 'none
    "Animation when an window is iconified."
    :type (choice none solid wireframe cross elliptical draft)
    :tooltip "Can be overriden from \"Window Rules\"."
    :group (appearance animation))

;;; animator registration

  (define (define-window-animator name fun)
    "Define a window animator called NAME (a symbol) that is managed by
function FUN. FUN is called as (FUN WINDOW OP [ACTION]) when it should change
the state of an animation sequence. OP may be one of the symbols `start',
`stop'."
    (put name 'window-animator fun)
    (unless (memq name window-animators)
      (setq window-animators (cons name (delq name window-animators)))
;;      (custom-set-property 'default-window-animator
;;			   ':options window-animators)
      ))

  (define (getter name) (get name 'window-animator))

  (define autoload-window-animator
    (make-autoloader getter define-window-animator))

  (define window-animator (autoloader-ref getter))

;;; running animators

  (define (run-window-animator w action)
    "Invoke an animation for ACTION on window W."
    (let ((running (window-get w 'running-animator)))
      (when running
	(running w 'stop)))
    (let ((animator (or (window-get w 'animator) default-window-animator)))
      (when animator
	((window-animator animator) w 'start action))))

  (define (record-window-animator w animator)
    "Note that window W currently has an animation running; being controlled
by animator function ANIMATOR."
    (window-put w 'running-animator animator))

;;; init

  ;; for the hardcore
  (define-window-animator 'none nop)

  ;; in the window-state-change-hook
  (define (window-anim-initiator w states)
    ;; XXX select a state if >1? (never currently happens?)
    (run-window-animator w (car states)))

  (add-hook 'window-state-change-hook window-anim-initiator))
