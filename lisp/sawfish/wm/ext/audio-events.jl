;; audio-events.jl -- map wm actions to audio samples

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

;;;###autoload (defgroup audio "Sound" :require sawfish.wm.ext.audio-events)

(define-structure sawfish.wm.ext.audio-events

    (export audio-event-handler)

    (open rep
	  rep.system
	  sawfish.wm.custom
	  sawfish.wm.windows
	  sawfish.wm.state.maximize
	  sawfish.wm.util.play-audio)

  (define-structure-alias audio-events sawfish.wm.ext.audio-events)

  (defgroup audio "Sound" :require sawfish.wm.ext.audio-events)

  ;; XXX it would be cool to merge the customization with the GNOME sound prefs

  (defcustom audio-events-enabled nil
    "Play sound effects for window events."
    :type boolean
    :require sawfish.wm.ext.audio-events
    :group audio)

  (defvar audio-for-ignored-windows nil
    "Play sound effects for unmanaged windows.")

  ;; standard events are: iconified, uniconified, shaded, unshaded,
  ;; maximized, unmaximized, mapped, unmapped, mapped-transient,
  ;; unmapped-transient, switch-workspace, move-viewport, focused,
  ;; unfocused

  (defcustom audio-events-alist '((iconified . "iconify.wav")
				  (uniconified . "uniconify.wav")
				  (shaded . "shade.wav")
				  (unshaded . "unshade.wav")
				  (maximized . "maximize.wav")
				  (unmaximized . "unmaximize.wav")
				  (mapped . "map.wav")
				  (unmapped . "unmap.wav")
				  (mapped-transient . "map-transient.wav")
				  (unmapped-transient . "unmap-transient.wav")
                                  ;;(focused . "focused.wav")
                                  ;;(unfocused . "unfocused.wav")
				  (switch-workspace . "switch-workspace.wav")
				  (move-viewport . "move-viewport.wav"))
    nil
    :type* `(alist ((symbol iconified uniconified
			    shaded unshaded
			    maximized unmaximized
			    mapped unmapped
			    mapped-transient unmapped-transient
			    switch-workspace move-viewport
			    focused unfocused) ,(_ "Event"))
		   (file ,(_ "Audio file")))
    :widget-flags (expand-vertically)
    :depends audio-events-enabled
    :group audio)

  (defun audio-event-handler (event #!optional w)
    "Possibly play a sound sample for EVENT (a symbol) occurring on window W."
    (when (and audio-events-enabled
	       (or (null w)
		   (not (window-get w 'ignored))
		   audio-for-ignored-windows))
      (let
	  ((sample (cdr (assq event audio-events-alist))))
	(when sample
	  (require 'sawfish.wm.util.play-audio)
	  (play-sample sample)))))

;;; hooks

  (defun audio-state-change-fun (w states)
    (mapc (lambda (state)
	    (case state
	      ((iconified)
	       (audio-event-handler (if (window-get w 'iconified)
					'iconified 'uniconified) w))
	      ((shaded)
	       (audio-event-handler (if (window-get w 'shaded)
					'shaded 'unshaded) w))
	      ((maximized)
	       (audio-event-handler (if (window-maximized-p w)
					'maximized 'unmaximized) w)))) states))

  (call-after-state-changed '(iconified shaded maximized)
			    audio-state-change-fun)

  (defun audio-focus-in-fun (w)
    (audio-event-handler 'focused w))

  (add-hook 'focus-in-hook audio-focus-in-fun)

  (defun audio-focus-out-fun (w)
    (audio-event-handler 'unfocused w))

  (add-hook 'focus-out-hook audio-focus-out-fun)

  (defun audio-mapped-fun (w)
    (audio-event-handler (if (window-transient-p w)
			     'mapped-transient 'mapped) w))

  (add-hook 'map-notify-hook audio-mapped-fun)

  (defun audio-unmapped-fun (w)
    (audio-event-handler (if (window-transient-p w)
			     'unmapped-transient 'unmapped) w))

  (add-hook 'unmap-notify-hook audio-unmapped-fun)

  (defun audio-enter-ws-fun ()
    (audio-event-handler 'switch-workspace))

  (add-hook 'enter-workspace-hook audio-enter-ws-fun)

  (defun audio-move-vp-fun ()
    (audio-event-handler 'move-viewport))

  (add-hook 'viewport-moved-hook audio-move-vp-fun))
