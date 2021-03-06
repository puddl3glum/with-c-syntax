(in-package #:with-c-syntax.stdlib)

(eval-when (:compile-toplevel :load-toplevel :execute)
(defun mantissa-radix-change (mantissa from-radix to-radix)
  (+ (floor (* (1- mantissa)
               (log from-radix to-radix)))
     (if (= from-radix to-radix) 1 0)))

(defun signed-byte-max (bits)
  (1- (expt 2 (1- bits))))

(defun signed-byte-min (bits)
  (- (expt 2 (1- bits))))

(defun unsigned-byte-max (bits)
  (1- (expt 2 bits))))

(defun add-preprocessor-macro-with-upcase (name val)
  (add-preprocessor-macro name val)
  (add-preprocessor-macro (string-upcase name) val :upcase))

(defun add-predefined-typedef-and-aliases (sym type)
  (add-typedef sym type)		; typedefs name -> type
  ;; adds package-free alias
  (add-preprocessor-macro-with-upcase (symbol-name sym) sym))

(define-condition library-macro-error (with-c-syntax-error)
  ((name :initarg :name
         :reader library-macro-error-name)
   (args :initarg :args
         :reader library-macro-error-args))
  (:report
   (lambda (condition stream)
     (format stream "~A: bad args: ~A"
             (library-macro-error-name condition)
             (library-macro-error-args condition)))))
