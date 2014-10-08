(in-package #:with-c-syntax)

(defmacro eval-equal* (val form)
  (let ((exp (gensym)) (ret (gensym)))
    `(let ((,exp ,val)
	   (,ret ,form))
       (assert (equal ,exp ,ret)
	       ()
	       "eval-equal error: expected ~S, returned ~S~% form ~S"
	       ,exp ,ret ',form))))

(defmacro eval-equal (val (&rest wcs-args) &body body)
  `(eval-equal* ,val (with-c-syntax (,@wcs-args) ,@body)))

(defmacro assert-compile-error (() &body body)
  `(assert
    (nth-value
     1
     (ignore-errors
       (c-expression-tranform ',body
                              (or (getf (first *current-c-reader*) :case)
                                  (readtable-case *readtable*))
			      nil)))))

(defmacro assert-runtime-error (() &body body)
  `(assert
    (nth-value
     1 
     (ignore-errors (with-c-syntax () ,@body)))))

(defmacro muffle-unused-code-warning (&body body)
  `(locally
       (declare
        #+sbcl(sb-ext:muffle-conditions sb-ext:code-deletion-note))
     ,@body))
