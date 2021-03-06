;;;
;;; Mumble main body.
;;; Julian Squires / 2004
;;;

(in-package :mumble)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defvar *replay-map* nil))

(defstruct replay
  (name) (special-handler) (channel-creator) (output-fn))

(defun register-replay (name special-handler channel-creator output-fn)
  (let ((replay (make-replay :name name :special-handler special-handler
			     :channel-creator channel-creator
			     :output-fn output-fn)))
    (aif (position name *replay-map* :test #'equal :key #'replay-name)
	 (setf (nth it *replay-map*) replay)
	 (push replay *replay-map*))))

(defun set-tune-replay (name tune)
  (dolist (replay *replay-map*)
    (when (equal name (replay-name replay))
      (setf (tune-replay tune) replay)
      (return)))
  (equal (replay-name (tune-replay tune)) name))

;;;; HIGH-LEVEL

(defun compile-mumble (in-file out-file)
  (with-open-file (stream in-file)
    (let ((tune (parse-mumble-file stream)))
      (funcall (replay-output-fn (tune-replay tune)) tune out-file))))
