(in-package #:with-c-syntax.core)

;;; Variables
(defvar *typedef-names* (make-hash-table :test 'eq)
  "* Value Type
a hashtable :: a symbol -> list of decl-specs

* Description
Holds definitions of typedefs.

* Notes
At the beginning of ~with-c-syntax~, it binds this variable to the
values they held. This behavior limits the scope of local typedefs
into the compilation unit.

* Affected By
~with-c-compilation-unit~.

* See Also
~find-typedef~, ~add-typedef~, ~remove-typedef~.
")

(defvar *struct-specs* (make-hash-table :test 'eq)
  "* Value Type
a hashtable :: a symbol -> a list of struct-spec.

* Description
Holds definitions of structs or unions.

* Notes
At the beginning of ~with-c-syntax~, it binds this variable to the
values they held. This behavior limits the scope of local struct/union
definitions into the compilation unit.

* Affected By
~with-c-compilation-unit~.

* See Also
~find-struct-spec~, ~add-struct-spec~, ~remove-struct-spec~
")

(defvar *dynamic-binding-requested* nil
  "* Value Type 
a list :: consistes of symbols.

* Description
Holds a list of symbols, which are pointed by a pointer.
If a pseudo-pointer is created for a symbol, the symbol is added to
here (because such a symbol must be handled *carefully*).

* Notes
At the beginning of ~with-c-syntax~, it binds this variable to nil.

* Affected By
~with-c-compilation-unit~.
")

(defvar *function-pointer-ids* nil
  "* Value Type
a list :: consists of symbols.

* Description
Holds a list of symbols, which are declared as a pointer
to a function.  (Because such a symbol is specially treated by the
function-calling expression.)

* Notes
At the beginning of ~with-c-syntax~, it binds this variable to nil.

* Affected By
~with-c-compilation-unit~.
")

(defvar *toplevel-entry-form* nil
  "* Value Type
a list

* Description
Holds a form inserted as an entry point.

This is used only when compiling a translation unit. Not used for
other cases.

* Notes
At the beginning of ~with-c-syntax~, it binds this variable to its
~entry-form~ argument.

* Affected By
~with-c-compilation-unit~.
")

(defmacro with-c-compilation-unit ((entry-form) &body body)
  "* Syntax
~with-c-compilation-unit~ (entry-forn) &body form* => result*

* Arguments and Values
- entry-form  :: a form
- forms       :: a implicit progn
- results     :: the values returned by forms

* Description
Establishes variable bindings for a new compilation.
"
  `(let ((*struct-specs* (copy-hash-table *struct-specs*))
         (*typedef-names* (copy-hash-table *typedef-names*))
         (*dynamic-binding-requested* nil)
         (*function-pointer-ids* nil)
         (*toplevel-entry-form* ,entry-form))
     ,@body))

;;; Lexer
(defun list-lexer (list)
  #'(lambda ()
      (let ((value (pop list)))
        (typecase value
          (null
           (values nil nil))
          (symbol
           (cond ((or (member value +operators+ :test #'eq)
                      (member value +keywords+ :test #'eq))
                  ;; They must be belongs this package.
                  ;; (done by the preprocessor)
                  (values value value))
                 ((gethash value *typedef-names*)
                  (values 'typedef-id value))
                 (t
                  (values 'id value))))
          (integer
           (values 'int-const value))
          (character
           (values 'char-const value))
          (float
           (values 'float-const value))
          (string
           (values 'string value))
          (list
           (values 'lisp-expression value))
          (t
           (error "Unexpected value ~S" value))))))

;;; Declarations
(defstruct decl-specs
  ;; Filled by the parser
  (type-spec nil)
  (storage-class nil)
  (qualifier nil)
  ;; Filled by 'finalize-decl-specs', and refered by 'finalize-init-declarator'
  (lisp-type t)             ; typename for Common Lisp
  (tag nil)		    ; struct/union/enum tag
  (typedef-init-decl nil)   ; typedef
  ;; Filled by 'finalize-decl-specs', and refered by 'expand-toplevel'
  (enum-bindings nil)       ; enum definition
  (struct-spec nil))	    ; struct/union definition

(defmethod make-load-form ((obj decl-specs) &optional environment)
  (make-load-form-saving-slots
   obj
   :slot-names '(type-spec storage-class qualifier
   		 lisp-type tag typedef-init-decl)
   :environment environment))

(defstruct init-declarator
  ;; Filled by the parser
  declarator
  (initializer nil)
  ;; Filled by 'finalize-init-declarator'
  (lisp-name)
  (lisp-initform)
  (lisp-type))

(defmethod make-load-form ((obj init-declarator) &optional environment)
  (make-load-form-saving-slots obj :environment environment))

(defstruct struct-or-union-spec
  type					; symbol. 'struct' or 'union'
  (id nil)
  ;; alist of (spec-qualifier-list . (struct-declarator ...))
  (struct-decl-list nil))

(defmethod make-load-form ((obj struct-or-union-spec) &optional environment)
  (make-load-form-saving-slots obj :environment environment))

(defstruct (spec-qualifier-list
             (:include decl-specs)))

(defmethod make-load-form ((obj spec-qualifier-list) &optional environment)
  (make-load-form-saving-slots
   obj
   :slot-names '(type-spec storage-class qualifier
   		 lisp-type tag typedef-init-decl)
   :environment environment))

(defstruct (struct-declarator
             (:include init-declarator))
  (bits nil))

(defmethod make-load-form ((obj struct-declarator) &optional environment)
  (make-load-form-saving-slots obj :environment environment))

(defstruct enum-spec
  (id nil)				; enum tag
  (enumerator-list nil))                ; list of enumerator

(defmethod make-load-form ((obj enum-spec) &optional environment)
  (make-load-form-saving-slots obj :environment environment))

(defstruct (enumerator
	     (:include init-declarator)))

(defmethod make-load-form ((obj enumerator) &optional environment)
  (make-load-form-saving-slots obj :environment environment))

;; typedefs
(defun find-typedef (name)
  "* Syntax
~find-typedef~ name => decl-spec

* Arguments and Values
- name      :: a symbol
- decl-spec :: a decl-specs instance, or nil.

* Description
Finds and returns a typedef definition. If no typedefs are found,
returns nil.

* Affected By
~with-c-compilation-unit~.
"
  (first (gethash name *typedef-names*)))

(defun add-typedef (name spec)
  "* Syntax
~add-typedef~ name spec => decl-spec

* Arguments and Values
- name      :: a symbol
- spec      :: a decl-specs instance, or a type specifier.
- decl-spec :: a decl-specs instance.

* Description
Establishes a new typedef definition named ~name~.

* Affected By
~with-c-compilation-unit~.
"
  (let ((dspecs
	 (typecase spec
	   (decl-specs spec)
	   (t (make-decl-specs :lisp-type spec)))))
    (push dspecs (gethash name *typedef-names*))
    dspecs))

(defun remove-typedef (name)
  "* Syntax
~remove-typedef~ name => decl-spec

* Arguments and Values
- name      :: a symbol
- decl-spec :: a decl-specs instance, or nil.

* Description
Removes a typedef definition named ~name~.

Returns the removed typedef definition. If no typedefs are found,
returns nil.

* Affected By
~with-c-compilation-unit~.
"
  (pop (gethash name *typedef-names*)))

;; structure information
(defstruct struct-spec
  struct-name	     ; user supplied struct tag (symbol)
  struct-type	     ; 'struct or 'union
  member-defs	     ; (:lisp-type ... :constness ... :decl-specs ...)
  ;; compile-time only
  (defined-in-this-unit nil)) ; T only when compiling this

(defmethod make-load-form ((sspec struct-spec) &optional environment)
  (make-load-form-saving-slots
   sspec
   :slot-names '(struct-name struct-type member-defs)
   :environment environment))

(defun find-struct-spec (name)
  "* Syntax
~find-struct-spec~ name => struct-spec

* Arguments and Values
- name      :: a symbol
- decl-spec :: a struct-spec instance, or nil.

* Description
Finds and returns a struct-spec. If no struct-specs are found, returns
nil.

* Affected By
~with-c-compilation-unit~.
"
  (first (gethash name *struct-specs*)))

(defun add-struct-spec (name sspec)
  "* Syntax
~add-struct-spec~ name sspec => struct-spec

* Arguments and Values
- name        :: a symbol.
- sspec       :: a struct-spec instance.
- struct-spec :: a struct-spec instance.

* Description
Establishes a new struct-spec definition named ~name~.

* Affected By
~with-c-compilation-unit~.
"
  (push sspec (gethash name *struct-specs*)))

(defun remove-struct-spec (name)
  "* Syntax
~remove-struct-spec~ name => struct-spec

* Arguments and Values
- name        :: a symbol
- struct-spec :: a struct-specs instance, or nil.

* Description
Removes a struct-spec definition named ~name~.

Returns the removed struct-spec definition. If no struct-specs are
found, returns nil.

* Affected By
~with-c-compilation-unit~.
"
  (pop (gethash name *struct-specs*)))

;; processes structure-spec 
(defun finalize-struct-spec (sspec dspecs)
  (setf (decl-specs-tag dspecs) (or (struct-or-union-spec-id sspec)
				    (gensym "unnamed-struct-"))
	(decl-specs-lisp-type dspecs) 'struct)
  ;; only declaration?
  (when (null (struct-or-union-spec-struct-decl-list sspec))
    (assert (struct-or-union-spec-id sspec)) ; this case is rejected by the parser.
    (return-from finalize-struct-spec dspecs))
  ;; Now defines a new struct.
  (loop for (spec-qual . struct-decls)
     in (struct-or-union-spec-struct-decl-list sspec)
     do (finalize-decl-specs spec-qual)
     ;; included definitions
     do (appendf (decl-specs-enum-bindings dspecs) 
		 (decl-specs-enum-bindings spec-qual))
     do (appendf (decl-specs-struct-spec dspecs) 
		 (decl-specs-struct-spec spec-qual))
     ;; this struct
     nconc
       (loop with tp = (decl-specs-lisp-type spec-qual)
	  with constness = (member '|const| (decl-specs-qualifier spec-qual))
	  for s-decl in struct-decls
	  as (decl-name . abst-decl) = (init-declarator-declarator s-decl)
	  as name = (or decl-name (gensym "unnamed-member-"))
	  as initform = (expand-init-declarator-init spec-qual abst-decl nil)
	  as bits = (struct-declarator-bits s-decl)
	  ;; NOTE: In C, max bits are limited to the normal type.
	  ;; http://stackoverflow.com/questions/2647320/struct-bitfield-max-size-c99-c
	  if (and bits
		  (not (subtypep `(signed-byte ,bits) tp))
		  (not (subtypep `(unsigned-byte ,bits) tp)))
	  do (error "invalid bitfield: ~A, ~A" tp s-decl) ; limit bits.
	  collect (list :lisp-type tp :constness constness
			:name name :initform initform
			:decl-specs spec-qual
                        :abst-declarator abst-decl))
     into member-defs
     finally
       (let ((sspec
	      (make-struct-spec
	       :struct-name (decl-specs-tag dspecs)
	       :struct-type (struct-or-union-spec-type sspec)
	       :member-defs member-defs
	       :defined-in-this-unit t)))
	 (add-struct-spec (decl-specs-tag dspecs) sspec)
	 ;; This sspec is treated by this dspecs
	 (push-right (decl-specs-struct-spec dspecs) sspec)))
    dspecs)

;; processes enum-spec 
(deftype enum ()
  'fixnum)

(defun finalize-enum-spec (espec dspecs)
  (setf (decl-specs-lisp-type dspecs) 'enum)
  (setf (decl-specs-tag dspecs)
	(or (enum-spec-id espec) (gensym "unnamed-enum-")))
  ;; addes values into lisp-decls
  (setf (decl-specs-enum-bindings dspecs)
	(loop as default-initform = 0 then `(1+ ,e-decl)
	   for e in (enum-spec-enumerator-list espec)
	   as e-decl = (init-declarator-declarator e)
	   as e-init = (init-declarator-initializer e)
	   collect (list e-decl (or e-init default-initform))))
  dspecs)

(defun finalize-type-spec (dspecs)
  (loop with numeric-symbols = nil
     with tp-list of-type list = (decl-specs-type-spec dspecs)
     initially
       (when (null tp-list)
	 (return dspecs))
     for tp in tp-list
     do (flet ((check-tp-list-length ()
		 (unless (length= 1 tp-list)
		   (error "invalid decl-spec (~A)" tp-list))))
	  (cond
	    ((eq tp '|void|)		; void
	     (check-tp-list-length)
	     (setf (decl-specs-lisp-type dspecs) nil)
	     (return dspecs))
	    ((struct-or-union-spec-p tp)	; struct / union
	     (check-tp-list-length)
	     (return (finalize-struct-spec tp dspecs)))
	    ((enum-spec-p tp)		; enum
	     (check-tp-list-length)
	     (return (finalize-enum-spec tp dspecs)))
	    ((listp tp)			; lisp type
	     (check-tp-list-length)
	     (assert (eq (first tp) '|__lisp_type|))
	     (setf (decl-specs-lisp-type dspecs) (second tp))
	     (return dspecs))
	    ((find-typedef tp)		; typedef name
	     (let* ((td-dspecs (find-typedef tp))
		    (n-entry (rassoc (decl-specs-lisp-type td-dspecs)
				     +numeric-types-alist+
				     :test #'equal)))
	       (if n-entry
		   ;; numeric. merge its contents.
		   (appendf numeric-symbols (car n-entry))
		   ;; non-numeric
		   (progn
		     (check-tp-list-length)
		     (setf (decl-specs-lisp-type dspecs)
			   (decl-specs-lisp-type td-dspecs)
			   (decl-specs-tag dspecs)
			   (decl-specs-tag td-dspecs)
			   (decl-specs-typedef-init-decl dspecs)
			   (decl-specs-typedef-init-decl td-dspecs))
		     (return dspecs)))))
	    (t				; numeric types
	     (push tp numeric-symbols))))
     finally
       (setf numeric-symbols (sort numeric-symbols #'string<))
       (setf (decl-specs-lisp-type dspecs)
             (if-let ((n-entry (assoc numeric-symbols
                                      +numeric-types-alist+
                                      :test #'equal)))
               (cdr n-entry)
               (error "invalid numeric type: ~A" numeric-symbols)))
       (return dspecs)))

(defun finalize-decl-specs (dspecs)
  (finalize-type-spec dspecs)
  (setf (decl-specs-qualifier dspecs)
	(remove-duplicates (decl-specs-qualifier dspecs)))
  (setf (decl-specs-storage-class dspecs)
	(if (> (length (decl-specs-storage-class dspecs)) 1)
	    (error "too many storage-class specified: ~A"
		   (decl-specs-storage-class dspecs))
	    (first (decl-specs-storage-class dspecs))))
  dspecs)

(defun array-dimension-combine (array-dimension-list init)
  (loop with init-dims = (dimension-list-max-dimensions init)
     for a-elem in array-dimension-list
     for i-elem = (pop init-dims)
     if (null i-elem)
     collect a-elem
     else if (eq a-elem '*)
     collect i-elem
     else if (<= i-elem a-elem)
     collect a-elem
     else
     do (warn "too much elements in an initializer (~S, ~S)"
              array-dimension-list init)
     and collect a-elem))

(defun setup-init-list (dims dspecs abst-declarator init)
  (let* ((default (expand-init-declarator-init dspecs
                   (nthcdr (length dims) abst-declarator)
                   nil))
         (ret (make-dimension-list dims default)))
    (labels ((var-init-setup (rest-dims subscripts abst-decls init)
               (if (null rest-dims)
                   (setf (apply #'ref-dimension-list ret subscripts)
                         (expand-init-declarator-init dspecs abst-decls init))
                   (loop for d from 0 below (car rest-dims)
                      for init-i in init
                      do (assert (eq :aref (first (car abst-decls))))
                      do (var-init-setup (cdr rest-dims)
                                         (append-item-to-right subscripts d)
                                         (cdr abst-decls) init-i)))))
      (var-init-setup dims () abst-declarator init))
    ret))

;; returns (values var-init var-type)
(defun expand-init-declarator-init (dspecs abst-declarator initializer
                                    &key (error-on-incompleted t))
  (ecase (car (first abst-declarator))
    (:pointer
     (let ((next-type
	    (nth-value 1 (expand-init-declarator-init
			  dspecs (cdr abst-declarator) nil
			  :error-on-incompleted nil))))
       (values (or initializer 0)
               `(pseudo-pointer ,next-type))))
    (:funcall
     (when (eq :aref (car (second abst-declarator)))
       (error "a function returning an array is not accepted"))
     (when (eq :funcall (car (second abst-declarator)))
       (error "a function returning a function is not accepted"))
     (when initializer
       (error "a function cannot take a initializer"))
     ;; TODO: includes returning type, and arg type
     (values nil 'function))
    (:aref
     (let* ((aref-type (decl-specs-lisp-type dspecs))
            (aref-dim                   ; reads abst-declarator
             (loop for (tp tp-args) in abst-declarator
                if (eq :funcall tp)
                do (error "an array of functions is not accepted")
                else if (eq :aref tp)
                collect (or tp-args '*)
                else if (eq :pointer tp)
                do (setf aref-type `(pseudo-pointer ,aref-type))
                  (loop-finish)
                else
                do (assert nil () "Unexpected internal type: ~S" tp)))
            (merged-dim
             (array-dimension-combine aref-dim initializer))
            (lisp-elem-type
             (if (subtypep aref-type 'number) aref-type t)) ; excludes compound types
            (var-type
             (if (and error-on-incompleted
                      (or (null aref-dim) (member '* aref-dim))
                      (null initializer))
                 (error "array's dimension cannot be specified (~S, ~S)"
                        aref-dim initializer)
                 `(simple-array ,lisp-elem-type ,merged-dim)))
            (var-init
             `(make-array ',merged-dim
                          :element-type ',lisp-elem-type
                          :initial-contents
                          ,(make-dimension-list-load-form
			    (setup-init-list merged-dim dspecs
					     abst-declarator initializer)
			    (length merged-dim)))))
       (values var-init var-type)))
    ((nil)
     (let ((var-type (decl-specs-lisp-type dspecs)))
       (cond
         ((null var-type)
          (error "a void variable cannot be initialized"))
         ((eq var-type 't)
          (values initializer var-type))
         ((subtypep var-type 'number) ; includes enum
          (values (or initializer 0) var-type))
         ((subtypep var-type 'struct)
          (let* ((sspec (find-struct-spec (decl-specs-tag dspecs)))
		 (var-init
		  (if (not sspec)
		      (if error-on-incompleted
			  (error "struct ~S not defined" (decl-specs-tag dspecs))
			  nil)
                      `(make-struct
                        ,(if (struct-spec-defined-in-this-unit sspec)
			     (find-struct-spec (struct-spec-struct-name sspec))
			     `',(struct-spec-struct-name sspec))
                        ,@(loop for init in initializer
                             for mem in (struct-spec-member-defs sspec)
                             collect (expand-init-declarator-init
                                      (getf mem :decl-specs)
                                      (getf mem :abst-declarator)
                                      init))))))
            (values var-init var-type)))
         (t             ; unknown type. Maybe user supplied lisp-type.
	  (values initializer var-type)))))))

(defun finalize-init-declarator (dspecs init-decl)
  (let* ((decl (init-declarator-declarator init-decl))
         (init (init-declarator-initializer init-decl))
         (var-name (first decl))
         (abst-decl (rest decl))
	 (storage-class (decl-specs-storage-class dspecs)))
    (when (and init
               (member storage-class '(|extern| |typedef|)))
      (error "This variable (~S) cannot have any initializers" storage-class))
    ;; expand typedef contents
    (when-let (td-init-decl (decl-specs-typedef-init-decl dspecs))
      (appendf abst-decl
               (cdr (init-declarator-declarator td-init-decl))))
    (multiple-value-bind (var-init var-type)
	(expand-init-declarator-init dspecs abst-decl init)
      (when (and (subtypep var-type 'function)
                 (not (member storage-class '(nil |extern| |static|))))
        (error "a function cannot have such storage-class: ~S" storage-class))
      (setf (init-declarator-lisp-name init-decl) var-name
	    (init-declarator-lisp-initform init-decl) var-init
	    (init-declarator-lisp-type init-decl) var-type)
      (when (and (listp var-type)
                 (eq 'pseudo-pointer (first var-type))
                 (subtypep (second var-type) 'function))
        (push var-name *function-pointer-ids*)))
    (when (eq '|typedef| storage-class)
      (setf (decl-specs-typedef-init-decl dspecs) init-decl)
      (add-typedef var-name dspecs))
    init-decl))

;;; Expressions
(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; These are directly called by the parser..
(defun concatinate-comma-list (lis op i)
  (declare (ignore op))
  (append-item-to-right lis i))

(defun lispify-unary (op)
  #'(lambda (_ exp)
      (declare (ignore _))
      `(,op ,exp)))

(defun lispify-binary (op)
  #'(lambda (exp1 _ exp2)
      (declare (ignore _))
      `(,op ,exp1 ,exp2)))
)

(defun lispify-type-name (qls abs)
  (setf qls (finalize-decl-specs qls))
  (if abs
      (let ((init-decl (make-init-declarator :declarator abs)))
	(finalize-init-declarator qls init-decl)
        (init-declarator-lisp-type init-decl))
      (decl-specs-lisp-type qls)))

(defun lispify-subscript (obj arg1 &rest args)
  (etypecase obj
    (pseudo-pointer
     (let ((deref-obj (pseudo-pointer-dereference (+ obj arg1))))
       (if (null args)
           deref-obj
           (apply #'lispify-subscript deref-obj args))))
    (array
     (apply #'aref obj arg1 args))))

(defun (setf lispify-subscript) (val obj arg1 &rest args)
  (etypecase obj
    (pseudo-pointer
     (symbol-macrolet 
         ((deref-obj (pseudo-pointer-dereference (+ obj arg1))))
       (if (null args)
           (setf deref-obj val)
           (setf (apply #'lispify-subscript deref-obj args) val))))
    (array
     (setf (apply #'aref obj arg1 args) val))))

(defun lispify-cast (type exp)
  (if (null type)
      `(progn ,exp (values))            ; like '(void)x;'
      `(coerce ,exp ',type)))

(defun lispify-address-of (exp)
  (cond ((symbolp exp)
	 (push exp *dynamic-binding-requested*)
	 (once-only ((val exp))
	   `(make-pseudo-pointer
	     (if (pseudo-pointer-pointable-p ,val)
		 ,val ',exp))))
        ((listp exp)
	 (destructuring-ecase exp
	   ((lispify-subscript obj &rest args)
	    (once-only (obj)
              `(if (arrayp ,obj)
		   (make-pseudo-pointer
		    (make-reduced-dimension-array ,obj ,@(butlast args))
		    ,(lastcar args))
                   (error "Getting a pointer to an array, but this is not an array: ~S"
                          ,obj))))
           ((struct-member obj mem)
	    (once-only (obj)
              `(if (typep ,obj 'struct)
		   (make-pseudo-pointer
		    (struct-member-vector ,obj)
		    (struct-member-index ,obj ,mem))
                   (error "Getting a pointer to a struct member, but this is not a struct: ~S"
                          ,obj))))
           ((pseudo-pointer-dereference obj)
            obj)))
	(t
	 (error "cannot take a pointer to form ~S" exp))))

(defun lispify-funcall (func-exp args)
  (if (and (symbolp func-exp)
           (not (member func-exp *function-pointer-ids*)))
      `(,func-exp ,@args)
      `(funcall ,func-exp ,@args)))

(defun lispify-offsetof (dspecs id)
  (setf dspecs (finalize-decl-specs dspecs))
  (when-let* ((tag (decl-specs-tag dspecs))
              (sspec (find-struct-spec tag))
              (entry
	       (loop for mem in (struct-spec-member-defs sspec)
                  until (eq (getf mem :name) id)
                  count mem)))
    (return-from lispify-offsetof entry))
  (error "Bad 'offsetof' usage"))

;;; Statements
(defstruct stat
  (code nil)
  (declarations nil)        ; list of 'init-declarator'
  (break-statements nil)    ; list of (go 'break), should be rewrited
  (continue-statements nil) ; list of (go 'continue), should be rewrited
  (case-label-list nil))    ; alist of (<gensym> . :exp <case-exp>)

(defun merge-stat (s1 s2 &key (merge-code nil))
  (make-stat :code (if merge-code (append (stat-code s1)
					  (stat-code s2))
		       nil)
	     :declarations (append (stat-declarations s1)
				   (stat-declarations s2))
	     :break-statements (append (stat-break-statements s1)
				       (stat-break-statements s2))
	     :continue-statements (append (stat-continue-statements s1)
					  (stat-continue-statements s2))
	     :case-label-list (append (stat-case-label-list s1)
				      (stat-case-label-list s2))))

(defun expand-if-statement (exp then-stat
			     &optional (else-stat nil))
  (let* ((stat (if else-stat
		   (merge-stat then-stat else-stat)
		   then-stat))
	 (then-tag (gensym "if-then-"))
	 (else-tag (gensym "if-else-"))
	 (end-tag (gensym "if-end-")))
    (setf (stat-code stat)
	  `((if ,exp (go ,then-tag) (go ,else-tag))
	    ,then-tag
	    ,@(stat-code then-stat)
	    (go ,end-tag)
	    ,else-tag
	    ,@(if else-stat (stat-code else-stat) nil)
	    (go ,end-tag)
	    ,end-tag))
    stat))

(defvar *unresolved-break-tag* (gensym "unresolved-break-"))

(defun make-stat-unresolved-break ()
  (let ((ret (list 'go *unresolved-break-tag*)))
    (make-stat :code (list ret)
	       :break-statements (list ret))))

(defun rewrite-break-statements (sym stat)
  (loop for i in (shiftf (stat-break-statements stat) nil)
     do (setf (second i) sym)
     count i))

(defvar *unresolved-continue-tag* (gensym "unresolved-continue-"))

(defun make-stat-unresolved-continue ()
  (let ((ret (list 'go *unresolved-continue-tag*)))
    (make-stat :code (list ret)
	       :continue-statements (list ret))))

(defun rewrite-continue-statements (sym stat)
  (loop for i in (shiftf (stat-continue-statements stat) nil)
     do (setf (second i) sym)
     count i))

(defun expand-loop (body-stat
		     &key (init nil) (cond t) (step nil)
		     (post-test-p nil))
  (let* ((loop-body-tag (gensym "loop-body-"))
	 (loop-step-tag (gensym "loop-step-"))
	 (loop-cond-tag (gensym "loop-cond-"))
	 (loop-end-tag (gensym "loop-end-"))
	 (used-breaks (rewrite-break-statements loop-end-tag body-stat))
	 (used-continues (rewrite-continue-statements loop-step-tag body-stat)))
    (setf (stat-code body-stat)
	  `((progn ,init)
	    ,(if post-test-p
		 `(go ,loop-body-tag)		; do-while
		 `(go ,loop-cond-tag))
	    ,loop-body-tag
	    ,@(stat-code body-stat)
	    ,@(if (plusp used-continues)
		  `(,loop-step-tag))
	    (progn ,step)
	    ,@(if post-test-p
		  nil
		  `(,loop-cond-tag))
	    (when (progn ,cond)
	      (go ,loop-body-tag))
	    ,@(if (plusp used-breaks)
		  `(,loop-end-tag))))
    body-stat))

(defun push-case-label (case-label-exp stat)
  (let ((go-tag-sym (gensym (format nil "case-~S-" case-label-exp))))
    (push (cons go-tag-sym case-label-exp)
          (stat-case-label-list stat))
    (push go-tag-sym (stat-code stat))))

(defun expand-switch (exp stat)
  (let* ((switch-end-tag (gensym "switch-end-"))
	 (default-supplied nil)
	 (jump-table			; create jump table with COND
	  (loop with default-clause = `(t (go ,switch-end-tag))
	     for (go-tag-sym . case-label-exp)
	     in (shiftf (stat-case-label-list stat) nil)

	     if (eq case-label-exp '|default|)
	     do (setf default-clause `(t (go ,go-tag-sym))
		      default-supplied t)
	     else
	     collect `(,case-label-exp (go ,go-tag-sym))
	     into clauses
	     finally
               (return `(case ,exp
                          ,@clauses
                          ,default-clause))))
	 (used-breaks (rewrite-break-statements switch-end-tag stat)))
    (setf (stat-code stat)
	  `(,jump-table
	    ,@(stat-code stat)
	    ,@(if (or (plusp used-breaks)
		      (not default-supplied))
		  `(,switch-end-tag))))
    stat))

;;; Translation Unit -- function definitions
(defstruct function-definition
  func-name
  storage-class
  func-args
  func-body
  lisp-type)

(defmacro get-varargs (dst)
  "* Syntax
~get-varargs~ place => obj

* Arguments and Values
- place :: a place
- obj   :: a list

* Description
Sets the variadic arguments of the with-c-syntax function to the
~place~.

If this is called outside of a variadic function, an error is
signaled.

* Notes
This is not intended for calling directly. The ~va_start~ proprocessor
macro uses this.

When defining a variadic function, a macro has same name is locally
established.
"
  (declare (ignore dst))
  (error "trying to get variadic args list out of variadic funcs"))

(defun lispify-function-definition (name body
                                    &key K&R-decls (return (make-decl-specs)))
  (let* ((func-name (first name))
         (func-param (getf (second name) :funcall))
         (variadic nil)
	 (omitted nil)
         (param-ids
          (loop for p in func-param
             if (eq p '|...|)
             do (setf variadic t) (loop-finish)
             else
             collect
	       (or (first (second p))	; first of declarator.
		   (let ((var (gensym "omitted-arg-")))
		     (push var omitted)
		     var))))
	 (return (finalize-decl-specs return))
	 (storage-class
	  (case (decl-specs-storage-class return)
	    (|static| '|static|)
	    ((nil) '|global|)
	    (t (error "Cannot define a function of storage-class: ~S"
		      (decl-specs-storage-class return))))))
    (when K&R-decls
      (let ((K&R-param-ids
             (loop for (dspecs init-decls) in K&R-decls
                unless (member (decl-specs-storage-class dspecs)
                               '(nil |auto| |register|) :test #'eq)
                do (error "Invalid storage-class for arguments")
		nconc (mapcar #'init-declarator-lisp-name init-decls))))
        (unless (equal K&R-param-ids param-ids)
          (error "prototype is not matched with k&r-style params"))))
    (let ((varargs-sym (gensym "varargs-"))
          (body (expand-toplevel-stat body))) 
      (make-function-definition
       :func-name func-name
       :storage-class storage-class
       :func-args `(,@param-ids ,@(if variadic `(&rest ,varargs-sym)))
       :func-body
       `((declare (ignore ,@omitted))
         ,(if variadic
              `(macrolet ((get-varargs (ap)
                            "locally established get-varargs macro."
                            `(setf ,ap ,',varargs-sym)))
                 ,body)
              body))
       :lisp-type `(function ',(mapcar (constantly t) param-ids)
                             ',(decl-specs-lisp-type return))))))

;;; Toplevel
(defun expand-toplevel-init-decls (init-decls
                                   mode storage-class
                                   dynamic-established-syms)
  (loop with lexical-binds = nil
     with dynamic-extent-vars = nil
     with special-vars = nil
     with global-defs = nil
     with global-symmacros = nil
     with typedef-names = nil
     with funcptr-syms = nil

     for i in init-decls
     as name = (init-declarator-lisp-name i)
     as init = (init-declarator-lisp-initform i)

     ;; function declarations
     if (subtypep (init-declarator-lisp-type i) 'function)
     do (unless (or (null init) (zerop init))
          (error "a function cannot have initializer (~S = ~S)" name init))
     else do
     ;; variables
       (when (member name *dynamic-binding-requested*)
         (push name dynamic-established-syms))
       (when (member name *function-pointer-ids*)
         (push name funcptr-syms))
       (ecase storage-class
         ;; 'auto' vars
         (|auto|
          (when (eq mode :translation-unit)
            (error "At top level, 'auto' variables are not accepted (~S)" name))
          (push `(,name ,init) lexical-binds))
         ;; 'register' vars
         (|register|
          (when (eq mode :translation-unit)
            (error "At top level, 'register' variables are not accepted (~S)" name))
          (push `(,name ,init) lexical-binds)
          (when (member name dynamic-established-syms :test #'eq)
            (warn "some variables are 'register', but its pointer is taken (~S)." name))
          (push name dynamic-extent-vars))
         ;; 'extern' vars.
         (|extern|
          (unless (or (null init) (zerop init))
            (error "an 'extern' variable cannot have initializer (~S = ~S)" name init)))
         ;; 'global' vars.
         (|global|
          (when (eq mode :statement)
            (error "In internal scope, no global vars cannot be defined (~S)." name))
	  (push name special-vars)
	  (push `(defparameter ,name ,init
		   "generated by with-c-syntax, for global")
		global-defs))
         ;; 'static' vars.
         (|static|
	  (ecase mode
	    (:statement
	     ;; initialized 'only-once'
	     (let ((st-sym (gensym (format nil "static-var-~S-storage-" name))))
	       (push `(,name (if (boundp ',st-sym)
                                 (symbol-value ',st-sym)
                                 (setf (symbol-value ',st-sym) ,init)))
                     lexical-binds)))
	    (:translation-unit
	     ;; gensym and symbol-macrolet
	     (let ((var-sym (gensym (format nil "static-var-~S-" name))))
	       (push var-sym special-vars)
	       (push `(defvar ,var-sym ,init
			"generated by with-c-syntax, for global-static")
		     global-defs)
	       (push `(,name ,var-sym) global-symmacros)))))
         ;; 'typedef' vars
         (|typedef|
          (push name typedef-names)
	  (when (eq mode :translation-unit)
	    (push `(add-typedef ',name ,(find-typedef name))
		  global-defs))))
     finally
       (return
         (values (nreverse lexical-binds)
                 (nreverse dynamic-extent-vars)
                 (nreverse special-vars)
                 (nreverse global-defs)
		 (nreverse global-symmacros)
                 (nreverse typedef-names)
                 (nreverse funcptr-syms)
                 dynamic-established-syms))))

;; mode is :statement or :translation-unit
(defun expand-toplevel (mode decls fdefs code)
  (let ((default-storage-class
         (ecase mode
           (:statement '|auto|) (:translation-unit '|global|)))
	;; used for :statement
        lexical-binds
        dynamic-extent-vars
	;; used for :translation-unit
        special-vars
        global-defs
        global-symmacros
	;; used for both
        cleanup-typedef-names
        cleanup-funcptr-syms
        cleanup-struct-specs
        cleanup-dynamic-established-syms
        func-defs
        local-funcs)
    ;; process decls
    (loop for (dspecs init-decls) in decls
       as storage-class = (or (decl-specs-storage-class dspecs)
                              default-storage-class)
       ;; enum consts
       do (ecase mode
	    (:statement
	     (appendf lexical-binds (decl-specs-enum-bindings dspecs)))
	    (:translation-unit
	     (loop for (name val) in (decl-specs-enum-bindings dspecs)
		collect `(defconstant ,name ,val
			   "generated by with-c-syntax, for global enum")
		into const-defs
		finally (appendf global-defs const-defs))))
       ;; structs
       do (appendf cleanup-struct-specs (decl-specs-struct-spec dspecs))
	 (loop for sspec in (decl-specs-struct-spec dspecs)
	    as sname = (struct-spec-struct-name sspec)
	    as defined-in ;; drops defined-in-this-unit flag here.
	      = (shiftf (struct-spec-defined-in-this-unit sspec) nil)
	    if (and defined-in
		    (eq mode :translation-unit))
	    collect `(add-struct-spec ',sname ,sspec) into defs
	    finally (appendf global-defs defs))
       ;; declarations
       do(multiple-value-bind 
               (lexical-binds-1 dynamic-extent-vars-1
                                special-vars-1 global-defs-1
				global-symmacros-1
                                typedef-names-1 funcptr-syms-1
                                dynamic-established-syms-1)
             (expand-toplevel-init-decls init-decls mode storage-class
                                         cleanup-dynamic-established-syms)
           (appendf lexical-binds lexical-binds-1)
           (appendf dynamic-extent-vars dynamic-extent-vars-1)
           (appendf special-vars special-vars-1)
           (appendf global-defs global-defs-1)
           (appendf global-symmacros global-symmacros-1)
           (appendf cleanup-typedef-names typedef-names-1)
           (appendf cleanup-funcptr-syms funcptr-syms-1)
           (setf cleanup-dynamic-established-syms dynamic-established-syms-1)))
    ;; functions
    (loop for fdef in fdefs
       as name = (function-definition-func-name fdef)
       as args = (function-definition-func-args fdef)
       as body = (function-definition-func-body fdef)
       do (ecase (function-definition-storage-class fdef)
            (|global|
             (push `(defun ,name ,args ,@body) func-defs))
            (|static|
             (push `(,name ,args ,@body) local-funcs))))
    (nreversef func-defs)
    (nreversef local-funcs)
    (when (and (eq mode :translation-unit)
	       lexical-binds)
      (warn "The expansion result uses lexically bound variables. This prevents top-level compilation. Sorry."))
    (prog1
        `(symbol-macrolet (,@global-symmacros)
	   (declare (special ,@special-vars))
	   (,@(if lexical-binds
		  `(let* (,@lexical-binds)
		     (declare (dynamic-extent ,@dynamic-extent-vars)))
		  '(progn))
	      ,@global-defs
	      (labels (,@local-funcs)
		,@func-defs
		(with-dynamic-bound-symbols (,@*dynamic-binding-requested*)
		  ,@code))))
      ;; drop expanded definitions
      (loop for sym in cleanup-typedef-names
         do (remove-typedef sym))
      (loop for c in cleanup-struct-specs
         do (remove-struct-spec (struct-spec-struct-name c)))
      ;; drop symbols specially treated in this unit.
      (loop for sym in cleanup-dynamic-established-syms
         do (deletef *dynamic-binding-requested*
                     sym :test #'eq :count 1))
      (loop for sym in cleanup-funcptr-syms
         do (deletef *function-pointer-ids*
                     sym :test #'eq :count 1)))))

(defun expand-toplevel-stat (stat)
  (expand-toplevel :statement
                   (stat-declarations stat)
		   nil
                   `((block nil (tagbody ,@(stat-code stat))))))

(defun expand-translation-unit (units)
  (loop for u in units
     if (function-definition-p u)
     collect u into fdefs
     else
     collect u into decls
     finally
       (return (expand-toplevel :translation-unit
                                decls fdefs
				`(,*toplevel-entry-form*)))))

;;; The parser
(define-parser *expression-parser*
  (:muffle-conflicts t)         ; for 'dangling else'.
  ;; http://www.swansontec.com/sopc.html
  (:precedence (;; Primary expression
		(:left \( \) [ ] \. -> ++ --)
		;; Unary
		(:right * & + - ! ~ ++ -- #+ignore(typecast) |sizeof|)
		;; Binary
		(:left * / %)
		(:left + -)
		(:left >> <<)
		(:left < > <= >=)
		(:left == !=)
		(:left &)
		(:left ^)
		(:left \|)
		(:left &&)
		(:left \|\|)
		;; Ternary
		(:right ? \:)
		;; Assignment
		(:right = += -= *= /= %= >>= <<= &= ^= \|=)
		;; Comma
		(:left \,)))
  ;; http://www.cs.man.ac.uk/~pjj/bnf/c_syntax.bnf
  (:terminals
   #.(append +operators+
	     +keywords+
	     '(id typedef-id
	       int-const char-const float-const
	       string lisp-expression)))
  (:start-symbol wcs-entry-point)

  ;; Our entry point.
  ;; top level forms in C, or statements
  (wcs-entry-point
   (translation-unit
    #'(lambda (us) (expand-translation-unit us)))
   (labeled-stat
    #'(lambda (st) (expand-toplevel-stat st)))
   ;; exp-stat is not included, because it is gramatically ambiguous.
   (compound-stat
    #'(lambda (st) (expand-toplevel-stat st)))
   (selection-stat
    #'(lambda (st) (expand-toplevel-stat st)))
   (iteration-stat
    #'(lambda (st) (expand-toplevel-stat st)))
   (jump-stat
    #'(lambda (st) (expand-toplevel-stat st))))


  (translation-unit
   (external-decl
    #'list)
   (translation-unit external-decl
    #'append-item-to-right))

  (external-decl
   function-definition
   decl)

  (function-definition
   (decl-specs declarator decl-list compound-stat
    #'(lambda (ret name k&r-decls body)
	(lispify-function-definition name body
				     :return ret
				     :K&R-decls k&r-decls)))
   (           declarator decl-list compound-stat
    #'(lambda (name k&r-decls body)
	(lispify-function-definition name body
				     :K&R-decls k&r-decls)))
   (decl-specs declarator           compound-stat
    #'(lambda (ret name body)
	(lispify-function-definition name body
				     :return ret)))
   (           declarator           compound-stat
    #'(lambda (name body)
	(lispify-function-definition name body))))

  (decl
   (decl-specs init-declarator-list \;
               #'(lambda (dcls inits _t)
                   (declare (ignore _t))
		   (setf dcls (finalize-decl-specs dcls))
		   `(,dcls
		     ,(mapcar #'(lambda (i) (finalize-init-declarator dcls i))
			      inits))))
   (decl-specs \;
               #'(lambda (dcls _t)
                   (declare (ignore _t))
		   (setf dcls (finalize-decl-specs dcls))
		   `(,dcls))))

  (decl-list
   (decl
    #'list)
   (decl-list decl
	      #'append-item-to-right))

  ;; returns a 'decl-specs' structure
  (decl-specs
   (storage-class-spec decl-specs
                       #'(lambda (cls dcls)
                           (push cls (decl-specs-storage-class dcls))
                           dcls))
   (storage-class-spec
    #'(lambda (cls)
	(make-decl-specs :storage-class `(,cls))))
   (type-spec decl-specs
              #'(lambda (tp dcls)
                  (push tp (decl-specs-type-spec dcls))
                  dcls))
   (type-spec
    #'(lambda (tp)
	(make-decl-specs :type-spec `(,tp))))
   (type-qualifier decl-specs
                   #'(lambda (qlr dcls)
                       (push qlr (decl-specs-qualifier dcls))
                       dcls))
   (type-qualifier
    #'(lambda (qlr)
	(make-decl-specs :qualifier `(,qlr)))))

  (storage-class-spec
   |auto| |register| |static| |extern| |typedef|) ; keywords

  (type-spec
   |void| |char| |short| |int| |long|   ; keywords
   |float| |double| |signed| |unsigned|
   struct-or-union-spec
   enum-spec
   typedef-name
   (|__lisp_type| lisp-expression)      ; extension
   (|__lisp_type| id))                  ; extension

  (type-qualifier
   |const| |volatile|)                  ; keywords

  ;; returns a struct-or-union-spec structure
  (struct-or-union-spec
   (struct-or-union id { struct-decl-list }
                    #'(lambda (kwd id _l decl _r)
                        (declare (ignore _l _r))
			(make-struct-or-union-spec
			 :type kwd :id id :struct-decl-list decl)))
   (struct-or-union    { struct-decl-list }
                    #'(lambda (kwd _l decl _r)
                        (declare (ignore _l _r))
			(make-struct-or-union-spec
			 :type kwd :struct-decl-list decl)))
   (struct-or-union id
                    #'(lambda (kwd id)
			(make-struct-or-union-spec
			 :type kwd :id id))))

  (struct-or-union
   |struct| |union|)                        ; keywords

  (struct-decl-list
   (struct-decl
    #'list)
   (struct-decl-list struct-decl
		     #'append-item-to-right))

  (init-declarator-list
   (init-declarator
    #'list)
   (init-declarator-list \, init-declarator
                         #'concatinate-comma-list))

  ;; returns an init-declarator structure
  (init-declarator
   (declarator
    #'(lambda (d)
	(make-init-declarator :declarator d)))
   (declarator = initializer
               #'(lambda (d _op i)
                   (declare (ignore _op))
		   (make-init-declarator :declarator d
					 :initializer i))))

  ;; returns (spec-qualifier-list . struct-declarator-list)
  (struct-decl
   (spec-qualifier-list struct-declarator-list \;
                        #'(lambda (qls dcls _t)
                            (declare (ignore _t))
			    (cons qls dcls))))

  ;; returns a spec-qualifier-list structure
  (spec-qualifier-list
   (type-spec spec-qualifier-list
	      #'(lambda (tp lis)
		  (push tp (spec-qualifier-list-type-spec lis))
		  lis))
   (type-spec
    #'(lambda (tp)
	(make-spec-qualifier-list :type-spec `(,tp))))
   (type-qualifier spec-qualifier-list
		   #'(lambda (ql lis)
		       (push ql (spec-qualifier-list-qualifier lis))
		       lis))
   (type-qualifier
    #'(lambda (ql)
	(make-spec-qualifier-list :qualifier `(,ql)))))

  (struct-declarator-list
   (struct-declarator
    #'list)
   (struct-declarator-list \, struct-declarator
			   #'concatinate-comma-list))

  ;; returns a struct-declarator structure
  (struct-declarator
   (declarator
    #'(lambda (d)
	(make-struct-declarator :declarator d)))
   (declarator \: const-exp
	       #'(lambda (d _c bits)
		   (declare (ignore _c))
		   (make-struct-declarator :declarator d :bits bits)))
   (\: const-exp
       #'(lambda (_c bits)
	   (declare (ignore _c))
	   (make-struct-declarator :bits bits))))

  ;; returns an enum-spec structure
  (enum-spec
   (|enum| id { enumerator-list }
         #'(lambda (_kwd id _l lis _r)
             (declare (ignore _kwd _l _r))
	     (make-enum-spec :id id :enumerator-list lis)))
   (|enum|    { enumerator-list }
         #'(lambda (_kwd _l lis _r)
             (declare (ignore _kwd _l _r))
	     (make-enum-spec :enumerator-list lis)))
   (|enum| id
         #'(lambda (_kwd id)
             (declare (ignore _kwd))
	     (make-enum-spec :id id))))

  (enumerator-list
   (enumerator
    #'list)
   (enumerator-list \, enumerator
                    #'concatinate-comma-list))

  ;; returns an enumerator structure
  (enumerator
   (id
    #'(lambda (id)
	(make-enumerator :declarator id)))
   (id = const-exp
       #'(lambda (id _op exp)
           (declare (ignore _op))
	   (make-enumerator :declarator id :initializer exp))))

  ;; returns like:
  ;; (name (:aref nil) (:funcall nil) (:aref 5) (:funcall int))
  ;; processed in 'expand-init-declarator-init'
  (declarator
   (pointer direct-declarator
    #'(lambda (ptr dcls)
        (append dcls ptr)))
   direct-declarator)

  (direct-declarator
   (id
    #'list)
   (\( declarator \)
    #'(lambda (_lp dcl _rp)
	(declare (ignore _lp _rp))
        dcl))
   (direct-declarator [ const-exp ]
    #'(lambda (dcl _lp params _rp)
	(declare (ignore _lp _rp))
        `(,@dcl (:aref ,params))))
   (direct-declarator [		  ]
    #'(lambda (dcl _lp _rp)
	(declare (ignore _lp _rp))
        `(,@dcl (:aref nil))))
   (direct-declarator \( param-type-list \)
    #'(lambda (dcl _lp params _rp)
	(declare (ignore _lp _rp))
        `(,@dcl (:funcall ,params))))
   (direct-declarator \( id-list \)
    #'(lambda (dcl _lp params _rp)
	(declare (ignore _lp _rp))
        `(,@dcl (:funcall
                 ;; make as a list of (decl-spec (id))
                 ,(mapcar #'(lambda (p) `(nil (,p))) params)))))
   (direct-declarator \(	 \)
    #'(lambda (dcl _lp _rp)
	(declare (ignore _lp _rp))
        `(,@dcl (:funcall nil)))))

  (pointer
   (* type-qualifier-list
    #'(lambda (_kwd qls)
        (declare (ignore _kwd))
        `((:pointer ,@qls))))
   (*
    #'(lambda (_kwd)
        (declare (ignore _kwd))
        `((:pointer))))
   (* type-qualifier-list pointer
    #'(lambda (_kwd qls ptr)
        (declare (ignore _kwd))
        `(,@ptr (:pointer ,@qls))))
   (*			  pointer
    #'(lambda (_kwd ptr)
        (declare (ignore _kwd))
        `(,@ptr (:pointer)))))
			  

  (type-qualifier-list
   (type-qualifier
    #'list)
   (type-qualifier-list type-qualifier
			#'append-item-to-right))

  (param-type-list
   param-list
   (param-list \, |...|
	       #'concatinate-comma-list))

  (param-list
   (param-decl
    #'list)
   (param-list \, param-decl
	       #'concatinate-comma-list))

  (param-decl
   (decl-specs declarator
	       #'list)
   (decl-specs abstract-declarator
	       #'list)
   (decl-specs
    #'list))

  (id-list
   (id
    #'list)
   (id-list \, id
    #'concatinate-comma-list))

  (initializer
   assignment-exp
   ({ initializer-list }
    #'(lambda (_lp inits _rp)
	(declare (ignore _lp _rp))
        inits))
   ({ initializer-list \, }
    #'(lambda (_lp inits _cm _rp)
	(declare (ignore _lp _cm _rp))
        inits)))

  (initializer-list
   (initializer
    #'list)
   (initializer-list \, initializer
    #'concatinate-comma-list))

  ;; see 'decl'
  (type-name
   (spec-qualifier-list abstract-declarator
			#'(lambda (qls abs)
			    (lispify-type-name qls abs)))
   (spec-qualifier-list
    #'(lambda (qls)
	(lispify-type-name qls nil))))

  ;; inserts 'nil' as a name
  (abstract-declarator
   (pointer
    #'(lambda (ptr)
	`(nil ,@ptr)))
   (pointer direct-abstract-declarator
    #'(lambda (ptr dcls)
	`(nil ,@dcls ,@ptr)))
   (direct-abstract-declarator
    #'(lambda (adecl)
	`(nil ,@adecl))))

  ;; see 'direct-declarator'
  (direct-abstract-declarator
   (\( abstract-declarator \)
    #'(lambda (_lp dcl _rp)
	(declare (ignore _lp _rp))
        dcl))
   (direct-abstract-declarator [ const-exp ]
    #'(lambda (dcls _lp params _rp)
	(declare (ignore _lp _rp))
        `(,@dcls (:aref ,params))))
   (			       [ const-exp ]
    #'(lambda (_lp params _rp)
	(declare (ignore _lp _rp))
        `((:aref ,params))))
   (direct-abstract-declarator [	   ]
    #'(lambda (dcls _lp _rp)
	(declare (ignore _lp _rp))
        `(,@dcls (:aref nil))))
   (			       [	   ]
    #'(lambda (_lp _rp)
	(declare (ignore _lp _rp))
        '((:aref nil))))
   (direct-abstract-declarator \( param-type-list \)
    #'(lambda (dcls _lp params _rp)
	(declare (ignore _lp _rp))
        `(,@dcls (:funcall ,params))))
   (			       \( param-type-list \)
    #'(lambda (_lp params _rp)
	(declare (ignore _lp _rp))
        `((:funcall ,params))))
   (direct-abstract-declarator \(		  \)
    #'(lambda (dcls _lp _rp)
	(declare (ignore _lp _rp))
        `(,@dcls (:funcall nil))))
   (			       \(		  \)
    #'(lambda (_lp _rp)
	(declare (ignore _lp _rp))
        '((:funcall nil)))))

  (typedef-name
   typedef-id)


  ;;; Statements: 'stat' structure
  (stat
   labeled-stat
   exp-stat 
   compound-stat
   selection-stat
   iteration-stat
   jump-stat)

  (labeled-stat
   (id \: stat
       #'(lambda (id _c stat)
	   (declare (ignore _c))
	   (push id (stat-code stat))
	   stat))
   (|case| const-exp \: stat
       #'(lambda (_k  exp _c stat)
	   (declare (ignore _k _c))
	   (push-case-label exp stat)
	   stat))
   (|default| \: stat
       #'(lambda (_k _c stat)
	   (declare (ignore _k _c))
	   (push-case-label '|default| stat)
	   stat)))

  (exp-stat
   (exp \;
	#'(lambda (exp _term)
	    (declare (ignore _term))
	    (make-stat :code (list exp))))
   (\;
    #'(lambda (_term)
	(declare (ignore _term))
	(make-stat))))

  (compound-stat
   ({ decl-list stat-list }
      #'(lambda (_op1 dcls stat _op2)
          (declare (ignore _op1 _op2))
	  (setf (stat-declarations stat)
		(append dcls (stat-declarations stat)))
	  stat))
   ({ stat-list }
      #'(lambda (op1 stat op2)
	  (declare (ignore op1 op2))
	  stat))
   ({ decl-list	}
      #'(lambda (_op1 dcls _op2)
	  (declare (ignore _op1 _op2))
	  (make-stat :declarations dcls)))
   ({ }
      #'(lambda (op1 op2)
	  (declare (ignore op1 op2))
	  (make-stat))))

  (stat-list
   stat
   (stat-list stat
    #'(lambda (st1 st2)
	(merge-stat st1 st2 :merge-code t))))

  (selection-stat
   (|if| \( exp \) stat
       #'(lambda (op lp exp rp stat)
	   (declare (ignore op lp rp))
	   (expand-if-statement exp stat)))
   (|if| \( exp \) stat |else| stat
       #'(lambda (op lp exp rp stat1 el stat2)
	   (declare (ignore op lp rp el))
	   (expand-if-statement exp stat1 stat2)))
   (|switch| \( exp \) stat
	   #'(lambda (_k _lp exp _rp stat)
	       (declare (ignore _k _lp _rp))
	       (expand-switch exp stat))))

  (iteration-stat
   (|while| \( exp \) stat
	  #'(lambda (_k _lp cond _rp body)
	      (declare (ignore _k _lp _rp))
	      (expand-loop body :cond cond)))
   (|do| stat |while| \( exp \) \;
     #'(lambda (_k1 body _k2 _lp cond _rp _t)
	 (declare (ignore _k1 _k2 _lp _rp _t))
	 (expand-loop body :cond cond :post-test-p t)))
   (|for| \( exp \; exp \; exp \) stat
	#'(lambda (_k _lp init _t1 cond _t2 step _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (expand-loop body :init init :cond cond :step step)))
   (|for| \( exp \; exp \;     \) stat
	#'(lambda (_k _lp init _t1 cond _t2      _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (expand-loop body :init init :cond cond)))
   (|for| \( exp \;     \; exp \) stat
	#'(lambda (_k _lp init _t1      _t2 step _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (expand-loop body :init init :step step)))
   (|for| \( exp \;     \;     \) stat
	#'(lambda (_k _lp init _t1      _t2      _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (expand-loop body :init init)))
   (|for| \(     \; exp \; exp \) stat
	#'(lambda (_k _lp      _t1 cond _t2 step _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (expand-loop body :cond cond :step step)))
   (|for| \(     \; exp \;     \) stat
	#'(lambda (_k _lp      _t1 cond _t2      _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (expand-loop body :cond cond)))
   (|for| \(     \;     \; exp \) stat
	#'(lambda (_k _lp      _t1      _t2 step _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (expand-loop body :step step)))
   (|for| \(     \;     \;     \) stat
	#'(lambda (_k _lp      _t1      _t2      _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (expand-loop body))))

  (jump-stat
   (|goto| id \;
	 #'(lambda (_k id _t)
	     (declare (ignore _k _t))
	     (make-stat :code (list `(go ,id)))))
   (|continue| \;
	     #'(lambda (_k _t)
		 (declare (ignore _k _t))
		 (make-stat-unresolved-continue)))
   (|break| \;
	  #'(lambda (_k _t)
	      (declare (ignore _k _t))
	      (make-stat-unresolved-break)))
   (|return| exp \;
	   #'(lambda (_k exp _t)
	       (declare (ignore _k _t))
	       ;; use the block of PROG
	       (make-stat :code (list `(return ,exp)))))
   (|return| \;
	   #'(lambda (_k _t)
	       (declare (ignore _k _t))
	       ;; use the block of PROG
	       (make-stat :code (list `(return (values)))))))


  ;;; Expressions
  (exp
   assignment-exp
   (exp |,| assignment-exp
	(lispify-binary 'progn)))

  ;; 'assignment-operator' is included here
  (assignment-exp
   conditional-exp
   (unary-exp = assignment-exp
	      #'(lambda (exp1 op exp2)
		  (declare (ignore op))
		  `(setf ,exp1 ,exp2)))
   (unary-exp *= assignment-exp
	      (lispify-binary 'mulf))
   (unary-exp /= assignment-exp
	      (lispify-binary 'divf))
   (unary-exp %= assignment-exp
	      (lispify-binary 'modf))
   (unary-exp += assignment-exp
	      (lispify-binary 'incf))
   (unary-exp -= assignment-exp
	      (lispify-binary 'decf))
   (unary-exp <<= assignment-exp
	      (lispify-binary 'ashf))
   (unary-exp >>= assignment-exp
	      (lispify-binary 'reverse-ashf))
   (unary-exp &= assignment-exp
	      (lispify-binary 'logandf))
   (unary-exp ^= assignment-exp
	      (lispify-binary 'logxorf))
   (unary-exp \|= assignment-exp
	      (lispify-binary 'logiorf)))

  (conditional-exp
   logical-or-exp
   (logical-or-exp ? exp |:| conditional-exp
		   #'(lambda (cnd op1 then-exp op2 else-exp)
		       (declare (ignore op1 op2))
		       `(if ,cnd ,then-exp ,else-exp))))

  (const-exp
   conditional-exp)

  (logical-or-exp
   logical-and-exp
   (logical-or-exp \|\| logical-and-exp
		   (lispify-binary 'or)))

  (logical-and-exp
   inclusive-or-exp
   (logical-and-exp && inclusive-or-exp
		    (lispify-binary 'and)))

  (inclusive-or-exp
   exclusive-or-exp
   (inclusive-or-exp \| exclusive-or-exp
		     (lispify-binary 'logior)))

  (exclusive-or-exp
   and-exp
   (exclusive-or-exp ^ and-exp
		     (lispify-binary 'logxor)))

  (and-exp
   equality-exp
   (and-exp & equality-exp
	    (lispify-binary 'logand)))

  (equality-exp
   relational-exp
   (equality-exp == relational-exp
		 (lispify-binary '=))
   (equality-exp != relational-exp
		 (lispify-binary '/=)))

  (relational-exp
   shift-expression
   (relational-exp < shift-expression
		   (lispify-binary '<))
   (relational-exp > shift-expression
		   (lispify-binary '>))
   (relational-exp <= shift-expression
		   (lispify-binary '<=))
   (relational-exp >= shift-expression
		   (lispify-binary '>=)))

  (shift-expression
   additive-exp
   (shift-expression << additive-exp
		     (lispify-binary 'ash))
   (shift-expression >> additive-exp
		     (lispify-binary 'reverse-ash)))

  (additive-exp
   mult-exp
   (additive-exp + mult-exp
		 (lispify-binary '+))
   (additive-exp - mult-exp
		 (lispify-binary '-)))

  (mult-exp
   cast-exp
   (mult-exp * cast-exp
	     (lispify-binary '*))
   (mult-exp / cast-exp
	     (lispify-binary '/))
   (mult-exp % cast-exp
	     (lispify-binary 'mod)))

  (cast-exp
   unary-exp
   (\( type-name \) cast-exp
       #'(lambda (op1 type op2 exp)
	   (declare (ignore op1 op2))
           (lispify-cast type exp))))

  ;; 'unary-operator' is included here
  (unary-exp
   postfix-exp
   (++ unary-exp
       (lispify-unary 'incf))
   (-- unary-exp
       (lispify-unary 'decf))
   (& cast-exp
      #'(lambda (_op exp)
          (declare (ignore _op))
	  (lispify-address-of exp)))
   (* cast-exp
      #'(lambda (_op exp)
          (declare (ignore _op))
          `(pseudo-pointer-dereference ,exp)))
   (+ cast-exp
      (lispify-unary '+))
   (- cast-exp
      (lispify-unary '-))
   (! cast-exp
      (lispify-unary 'not))
   (~ cast-exp
      (lispify-unary 'lognot))
   (|sizeof| unary-exp
	   #'(lambda (_op exp)
	       (declare (ignore _op))
	       ;; calculate runtime
	       `(if (arrayp ,exp)
		    (array-total-size ,exp)
		    1)))
   (|sizeof| \( type-name \)
	   #'(lambda (_op _lp tp _rp)
	       (declare (ignore _op _lp _rp))
	       ;; calculate compile-time
	       (if (subtypep tp 'array)
		   (destructuring-bind (a-type &optional e-type array-dim) tp
		     (declare (ignore a-type e-type))
		     (when (member-if-not #'numberp array-dim)
		       (error "The array dimension is incompleted: ~S" tp))
		     (apply #'* array-dim))
		   1))))

  (postfix-exp
   primary-exp
   (postfix-exp [ exp ]
		#'(lambda (exp op1 idx op2)
		    (declare (ignore op1 op2))
                    (if (and (listp exp) (eq (first exp) 'lispify-subscript))
			(append-item-to-right exp idx)
                        `(lispify-subscript ,exp ,idx))))
   (postfix-exp \( argument-exp-list \)
		#'(lambda (exp op1 args op2)
		    (declare (ignore op1 op2))
                    (lispify-funcall exp args)))
   (postfix-exp \( \)
		#'(lambda (exp op1 op2)
		    (declare (ignore op1 op2))
                    (lispify-funcall exp nil)))
   (postfix-exp \. id
		#'(lambda (exp _op id)
		    (declare (ignore _op))
		    `(struct-member ,exp ',id)))
   (postfix-exp -> id
		#'(lambda (exp _op id)
		    (declare (ignore _op))
		    `(struct-member (pseudo-pointer-dereference ,exp) ',id)))
   (postfix-exp ++
		#'(lambda (exp _op)
		    (declare (ignore _op))
		    `(post-incf ,exp 1)))
   (postfix-exp --
		#'(lambda (exp _op)
		    (declare (ignore _op))
		    `(post-incf ,exp -1))))

  (primary-exp
   id
   const
   string
   (\( exp \)
       #'(lambda  (_1 x _3)
	   (declare (ignore _1 _3))
	   x))
   lisp-expression			; added
   (|__offsetof| \( decl-specs \, id \)   ; added
                 #'(lambda (_op _lp dcl _cm id _rp)
                     (declare (ignore _op _lp _cm _rp))
                     (lispify-offsetof dcl id))))


  (argument-exp-list
   (assignment-exp
    #'list)
   (argument-exp-list \, assignment-exp
                      #'concatinate-comma-list))

  (const
   int-const
   char-const
   float-const
   #+ignore enumeration-const)		; currently unused
  )

;;; Macro interface
(defmacro with-c-syntax ((&key (keyword-case (readtable-case *readtable*)
					     keyword-case-supplied-p)
			       (entry-form nil entry-form-supplied-p)
			       (try-add-{} t try-add-{}-supplied-p))
			 &body body)
  "* Syntax
~with-c-syntax~ (&key keyword-case entry-form try-add-{}) form* => result*

* Arguments and Values
- keyword-case :: one of ~:upcase~, ~:downcase~, ~:preserve~, or
                  ~:invert~.  The default is the current readtable
                  case.
- entry-form :: a form.
- try-add-{} :: a boolean.
- forms   :: forms interpreted by this macro.
- results :: the values returned by the ~forms~

* Description
This macro is a entry point of the with-c-syntax system.  ~forms~ are
interpreted as C syntax, executed, and return values.

~keyword-case~ specifies case sensitibily. Especially, if ~:upcase~ is
specified, some case-insensitive feature is enabled for convenience.

~entry-form~ is inserted as a entry point when compiling a translation
unit.

If ~try-add-{}~ is t and an error occured at parsing, with-c-syntax
adds '{' and '}' into the head and tail of ~form~ respectively, and
tries to parse again.
"
  (labels ((expand-c-syntax (body retry-add-{})
	     (handler-case 
		 (with-c-compilation-unit (entry-form)
		   (parse-with-lexer
		    (list-lexer (preprocessor body
					      (if (eq keyword-case :upcase)
						  :upcase nil)))
		    *expression-parser*))
	       (yacc-parse-error (condition)
		 (if retry-add-{}
		     (expand-c-syntax (append '({) body '(})) nil)
		     (error condition))))))
    (cond
      ((null body) nil)
      ((and (length= 1 body)		; with-c-syntax is nested.
	    (eq (first (first body)) 'with-c-syntax))
       (destructuring-bind (_ (&rest keyargs) &body body2)
	   (first body)
	 (declare (ignore _))
	 `(with-c-syntax (,@keyargs
			  ,@(if keyword-case-supplied-p
				`(:keyword-case ,keyword-case))
			  ,@(if entry-form-supplied-p
				`(:entry-form ,entry-form))
			  ,@(if try-add-{}-supplied-p
				`(:try-add-{} ,try-add-{})))
	    ,@body2)))
      (t
       (expand-c-syntax body try-add-{})))))
