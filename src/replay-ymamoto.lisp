;;;
;;; YMamoto conversion functions for mumble output.  These functions
;;; produce hisoft-style assembly output, which can be assembled into
;;; a binary playable by the ymamoto playroutine.
;;;
;;; Julian Squires <tek@wiw.org> / 2004
;;;

(in-package :mumble)

(defparameter *ymamoto-frequency* 50)
(defvar *channel-delta* 0)
(defvar *total-frames* 0)

;;;; UTILITIES

(defun find-and-remove-loop (list)
  "Finds :loop in the list, and returns two values, the list with the
:loop removed, and the position of the loop.  Does not support
multiple loops."
  (aif (position :loop list)
       (values (remove :loop list) it)
       (values list 0)))


;;;; INPUT-RELATED FUNCTIONS

(defun make-ymamoto-channels ()
  (list
   (make-channel)
   (make-channel)
   (make-channel)))


(defun ymamoto-special-handler (stream channels)
  (read-char stream)
  (let ((next-char (read-char stream)))
    (cond ((char= next-char #\e)
	   ;; env follow
	   (format t "~&guilty env follow"))
	  ;; Something else?
	  (t (format t "~&Ignored special invocator: @~A" next-char)))))


;;;; OUTPUT FUNCTIONS

(defun ymamoto-output-note-helper (note-word frames stream
				   &optional (comma nil))
  (incf *channel-delta* frames)
  (multiple-value-bind (frames leftovers) (floor *channel-delta*)
    (setf *channel-delta* leftovers)
    (setf (ldb (byte 7 8) note-word) (1- frames))

    (when (plusp frames)
      (incf *total-frames* frames)
      (format stream (if comma ", $~X" "~&~8TDC.W $~X") note-word))))


(defun ymamoto-output-note (note channel stream)
  (let ((note-word 0)
	(frames (duration-to-frames (note-duration note)
				    (channel-tempo channel)
				    *ymamoto-frequency*))
	(staccato-frames 0))

    (cond ((eql (note-tone note) :rest)
	   (setf (ldb (byte 7 0) note-word) 127))
	  ((eql (note-tone note) :wait)
	   (setf (ldb (byte 7 0) note-word) 126))
	  (t
	   (when (/= (channel-staccato channel) 1)	   
	     (setf staccato-frames (- frames (* frames
						(channel-staccato channel))))
	     (when (< (- frames staccato-frames) 1)
	       (decf staccato-frames))
	     (setf frames (- frames staccato-frames)))

	   (setf (ldb (byte 7 0) note-word) (note-tone note))))

    (ymamoto-output-note-helper note-word frames stream)
    (when (plusp staccato-frames)
      (ymamoto-output-note-helper 127 staccato-frames stream t))))


(defun ymamoto-output-note-stream (notes stream)
  "Traverse a note-stream, keeping track of tempo and staccato
  settings, and output assembly directives for this note stream."
  (let ((channel (make-channel)))
    (setf *channel-delta* 0)
    (setf *total-frames* 0)
    (loop for note across notes
       do (case (music-command-type note)
	    (:note (ymamoto-note-output note channel stream))
	    (:arpeggio
	     (format stream "~&~8TDC.W $~X"
		     (logior (ash #b11000000 8) (music-command-value note))))
	    (:tempo
	     (setf (channel-tempo channel) (music-command-value note)))
	    (:staccato
	     (setf (channel-staccato channel) (music-command-value note)))))
    (format t "~&frames: ~A" *total-frames*)))


(defun output-ymamoto-header (stream)
  (format stream ";;; test song, in assembler form

	ORG 0
song_header:
        DC.L arpeggio_table     ; pointer to arpeggio table
        DC.L venv_table         ; pointer to volume envelope table
	DC.B 1			; number of tracks"))


(defun ymamoto-output-length-loop-list-table (stream name table)
  ;; note that the zeroth element of the table is skipped.
  (format stream "~&~A:~%~8TDC.B ~D" name (max 0 (1- (length table))))
  (do ((i 1 (1+ i)))
      ((>= i (length table)))
    (multiple-value-bind (list loop) (find-and-remove-loop (aref table i))
      (format stream "~&~8TDC.B ~A, ~A~{, ~D~}" (length list) loop list))))


;;;; HIGH-LEVEL

(defun mbl-to-ymamoto-file (mbl-file out-file)
  (let (tune)
    (with-open-file (stream mbl-file)
      (setf tune (parse-mumble-file stream)))
    (with-open-file (stream out-file
		     :direction :output
		     :if-exists :supersede)
      ;; simple header
      (output-ymamoto-header stream)
      ;; for n tracks
      (let ((track-num 1))
	(format stream "~&~8TDC.L track_~D" track-num))
      (ymamoto-output-length-loop-list-table
       stream "arpeggio_table" (tune-get-table tune :arpeggio))
      (ymamoto-output-length-loop-list-table
       stream "venv_table" (tune-get-table tune :volume-envelope))
      ;; for n tracks
      (let ((track-num 1))
	;; I bet the following could all be reduced to one big format
	;; statement.  Yuck.
	(format stream "~&track_~D:" track-num)
	(do ((c (tune-channels tune) (cdr c))
	     (ctr (char-code #\a) (1+ ctr)))
	    ((null c))
	  (format stream "~&~8TDC.L channel_~A" (code-char ctr)))
	(do ((c (tune-channels tune) (cdr c))
	     (ctr (char-code #\a) (1+ ctr)))
	    ((null c))
	  (format stream "~&channel_~A:" (code-char ctr))
	  (ymamoto-output-note-stream (channel-data-stream (car c)) stream)
	  (if (channel-loop-point (car c))
	      (format stream "~&~8TDC.W $8001")
	      (format stream "~&~8TDC.W $8000")))))))