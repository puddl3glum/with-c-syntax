(in-package :with-c-syntax)

;;; Constants
(alexandria:define-constant +operators+
    '(|,|
      = *= /= %= += -= <<= >>= &= ^= \|=
      ? |:|
      \|\|
      &&
      \|
      ^
      &
      == !=
      < > <= >=
      >> <<
      + -
      * / %
      \( \)
      ++ -- sizeof
      & * + - ~ !
      [ ] \. ->
      )
  :test 'equal)

(alexandria:define-constant +keywords+
    '(\;
      auto register static extern typedef
      void char short int long float double signed unsigned
      const volatile
      struct union
      enum
      |...|
      case default
      { }
      if else switch
      while do for
      goto continue break return
      )
  :test 'equal)

;;; Lexer
(defvar *enum-declarations-alist* nil
  "list of (symbol initform)")

(defun list-lexer (list)
  #'(lambda ()
      (let ((value (pop list)))
	(cond ((null value)
	       (values nil nil))
	      ((symbolp value)
	       (let ((op (or (member value +operators+
				     :test #'string=
				     :key #'symbol-name)
			     (member value +keywords+
				     :test #'string=
				     :key #'symbol-name)))
		     (en (member value *enum-declarations-alist*
				 :key #'car)))
		 (cond (op
			;; returns the symbol of our package.
			(values (car op) value))
		       (en
			(values 'enumeration-const value))
		       (t
			(values 'id value)))))
	      ((integerp value)
	       (values 'int-const value))
	      ((characterp value)
	       (values 'char-const value))
	      ((floatp value)
	       (values 'float-const value))
	      ((stringp value)
	       (values 'string value))
	      ((listp value)
	       (values 'lisp-expression value))
	      (t
	       (error "Unexpected value ~S" value))))))

;;; Variables, works with the parser.
(defvar *toplevel-bindings* nil)
(defvar *dynamic-binding-required* nil)
(defvar *w-c-s-structs* nil)            ; TODO: remove this?

;;; Functions used by the parser.

;; for declarations 
(defstruct decl-specs
  (type-spec nil)
  (storage-class nil)
  (qualifier nil)
  lisp-type
  (w-c-s-type-tag nil)			; enum, struct
  (lisp-bindings nil)			; enum
  (lisp-constructor-spec nil)		; struct
  (lisp-field-spec nil))		; struct

(defstruct init-declarator
  declarator
  (initializer nil)
  (lisp-name)
  (lisp-initform)
  (lisp-type))

(defstruct struct-or-union-spec
  type					; symbol. 'struct' or 'union'
  (id nil)
  ;; alist of (spec-qualifier-list . (struct-declarator ...))
  (struct-decl-list nil))

(defstruct (spec-qualifier-list
             (:include decl-specs))
  )

(defstruct (struct-declarator
             (:include init-declarator))
  (bits nil))


(defstruct enum-spec
  (id nil)				; enum tag
  ;; list of enumerator
  (enumerator-list nil))

(defstruct (enumerator
	     (:include init-declarator))
  )

(defvar *default-decl-specs*
  (make-decl-specs :type-spec '(int)
		   :lisp-type 'fixnum))

(defstruct w-c-s-struct-constructor-spec
  struct-name
  field-count)				; includes struct-tag field

(defstruct w-c-s-struct-field-spec
  field-name
  struct-name
  index
  constness
  decl-specs)                           ; TODO: remove this?

(defun w-c-s-struct-constructor-name (struct-name)
  (intern (concatenate 'string "MAKE-" (symbol-name struct-name))))

;; NOTE: In C, max bits are limited to the normal type.
;; http://stackoverflow.com/questions/2647320/struct-bitfield-max-size-c99-c
(defun finalize-struct-spec (sspec dspecs)
  (setf (decl-specs-lisp-type dspecs) '(vector)) ; default type
  (setf (decl-specs-w-c-s-type-tag dspecs)
	(or (struct-or-union-spec-id sspec)
	    (gensym "unnamed-struct")))
  ;; only declaration?
  (when (null (struct-or-union-spec-struct-decl-list sspec))
    (return-from finalize-struct-spec sspec))
  ;; fields
  (loop with struct-name = (decl-specs-w-c-s-type-tag dspecs)
     with struct-type = (struct-or-union-spec-type sspec)
     with field-count = 1		; 0 is assigned to struct-tag
     for (spec-qual . struct-decls)
     in (struct-or-union-spec-struct-decl-list sspec)
     do (finalize-decl-specs spec-qual)
     ;; other struct
     do (appendf (decl-specs-lisp-bindings dspecs)
		 (decl-specs-lisp-bindings spec-qual))
       (appendf	(decl-specs-lisp-constructor-spec dspecs)
		(decl-specs-lisp-constructor-spec spec-qual))
       (appendf (decl-specs-lisp-field-spec dspecs)
		(decl-specs-lisp-field-spec spec-qual))
     ;; this struct
     nconc
       (loop with tp = (decl-specs-lisp-type spec-qual)
	  with constness = (member 'const (decl-specs-qualifier spec-qual))
	  for index from 0
	  for s-decl in struct-decls
	  as name = (or (car (init-declarator-declarator s-decl))
			(gensym "(unnamed field)"))
	  as bits = (struct-declarator-bits s-decl)
	  if (and bits
		  (not (subtypep `(signed-byte ,bits) tp))
		  (not (subtypep `(unsigned-byte ,bits) tp)))
	  do (error "invalid bitfield: ~A, ~A" tp s-decl) ; limit bits.
	  collect
	    (make-w-c-s-struct-field-spec
	     :field-name name
	     :struct-name struct-name
	     :index (ecase struct-type
		      (struct (prog1 field-count (incf field-count)))
		      (union (prog1 1 (setf field-count 2) )))
	     :constness constness
             :decl-specs spec-qual))
     into fields
     finally
       (let ((ctr (make-w-c-s-struct-constructor-spec
                   :struct-name struct-name :field-count field-count)))
         (setf (decl-specs-lisp-type dspecs)
               `(vector * ,field-count))
         (append-item-to-right-f
          (decl-specs-lisp-constructor-spec dspecs)
          ctr)
         (appendf (decl-specs-lisp-field-spec dspecs)
                  fields)
         (push `(,struct-name :constructor ,ctr
                              :fields ,fields)
               *w-c-s-structs*)))
  dspecs)

;; TODO: consider enum-name's scope. If using deftype, it is global!
(defun finalize-enum-spec (espec dspecs)
  (setf (decl-specs-lisp-type dspecs) 'fixnum)
  (setf (decl-specs-w-c-s-type-tag dspecs)
	(or (enum-spec-id espec) (gensym "unnamed-enum")))
  ;; addes values into lisp-decls
  (setf (decl-specs-lisp-bindings dspecs)
	(loop as default-initform = 0 then `(1+ ,e-decl)
	   for e in (enum-spec-enumerator-list espec)
	   as e-decl = (init-declarator-declarator e)
	   as e-init = (init-declarator-initializer e)
	   collect (list e-decl (or e-init default-initform))))
  dspecs)

(defun finalize-type-spec (dspecs)
  (loop with numeric-type = nil 
     with numeric-signedness = nil	; 'signed, 'unsigned, or nil
     with numeric-length = 0		; -1(short), 1(long), 2(long long), or 0
     with tp-list = (decl-specs-type-spec dspecs)
       
     for tp in tp-list

     if (eq tp 'void)			; void
     do (unless (= 1 (length tp-list))
	  (error "invalid decl-spec (~A)" tp-list))
       (setf (decl-specs-lisp-type dspecs) nil)
       (return dspecs)

     else if (struct-or-union-spec-p tp) ; struct / union
     do (unless (= 1 (length tp-list))
	  (error "invalid decl-spec (~A)" tp-list))
       (return (finalize-struct-spec tp dspecs))

     else if (enum-spec-p tp)	; enum
     do (unless (= 1 (length tp-list))
	  (error "invalid decl-spec (~A)" tp-list))
       (return (finalize-enum-spec tp dspecs))

     ;; numeric types
     else if (member tp '(float double int char))
     do (when numeric-type
	  (error "invalid decl-spec (~A)" tp-list))
       (setf numeric-type tp)
     ;; numeric variants
     else if (member tp '(signed unsigned))
     do (when numeric-signedness
	  (error "invalid decl-spec (~A)" tp-list))
       (setf numeric-signedness tp)
     else if (eq tp 'long)
     do (unless (<= 0 numeric-length 1)
	  (error "invalid decl-spec (~A)" tp-list))
       (incf numeric-length)
     else if (eq tp 'short)
     do (unless (= 0 numeric-length)
	  (error "invalid decl-spec (~A)" tp-list))
       (decf numeric-length)

     else
     do (assert nil)
       
     finally
       (setf (decl-specs-lisp-type dspecs)
	     (ecase numeric-type
	       (float
		(when (or numeric-signedness
			  (not (member numeric-length '(-1 0))))
		  (error "invalid decl-spec (~A)" tp-list))
		(if (eq numeric-length -1)
		    'short-float 'single-float))
	       (double
		(when (or numeric-signedness
			  (not (member numeric-length '(0 1))))
		  (error "invalid decl-spec (~A)" tp-list))
		(if (eq numeric-length 1)
		    'long-float 'double-float))
	       (char
		(when (not (= 0 numeric-length))
		  (error "invalid decl-spec (~A)" tp-list))
		(if (eq 'unsigned numeric-signedness) ; raw 'char' is signed
		    '(unsigned-byte 8)
		    '(signed-byte 8)))
	       ((int nil)
		(if (eq 'unsigned numeric-signedness)
		    (ecase numeric-length
		      (2 '(unsigned-byte 64))
		      (1 '(unsigned-byte 32))
		      (0 'fixnum)	; FIXME: consider unsigned?
		      (-1 '(unsigned-byte 16)))
		    (ecase numeric-length
		      (2 '(signed-byte 64))
		      (1 '(signed-byte 32))
		      (0 'fixnum)
		      (-1 '(signed-byte 16)))))))
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

(defun array-dimension-resolve (a-spec init)
  (let ((a-dim (third a-spec))
        dim-table) 	; (depth . max-len)
    (labels ((dim-calc (depth lis)
               (let ((old-max (cdr (assoc depth dim-table))))
                 (when (or (null old-max)
                           (> (length lis) old-max))
                   (setf dim-table
                         (acons depth (length lis) dim-table))))
               (loop for i in lis
                  when (and i (listp i))
                  do (dim-calc (1+ depth) i))))
      (dim-calc 0 init))
    (setf dim-table (sort dim-table #'< :key #'car))
    (loop for depth from 0
       for a-elem in a-dim
         as (_ . i-elem) = (assoc depth dim-table)
         if (null i-elem)
         collect a-elem
         else if (eq a-elem '*)
         collect i-elem
         else if (<= i-elem a-elem)
         collect a-elem
         else
         do (warn "too much elements in an initializer (~S, ~S)"
                  a-spec init)
       and collect a-elem)))

(defun make-dimension-list (dims &optional default)
  (if dims
      (loop for i from 0 below (car dims)
         collect (make-dimension-list (cdr dims) default))
      default))

(defun ref-dimension-list (lis dim-1 &rest dims)
  (if (null dims)
      (nth dim-1 lis)
      (apply #'ref-dimension-list (nth dim-1 lis) (car dims) (cdr dims))))

(defun (setf ref-dimension-list) (val lis dim-1 &rest dims)
  (if (null dims)
      (setf (nth dim-1 lis) val)
      (setf (apply #'ref-dimension-list (nth dim-1 lis) (car dims) (cdr dims))
            val)))
  
(defun setup-init-list (dims init default dspecs abst-declarator)
  (let ((ret (make-dimension-list dims default)))
    (labels ((var-init-setup (dims rev-aref init abst-decls)
               (if (null dims)
                   (setf (apply #'ref-dimension-list ret (reverse rev-aref))
                         (expand-init-declarator-init dspecs abst-decls init))
                   (loop for i from 0 below (car dims)
                      for init-i in init
                      do (var-init-setup (cdr dims) (cons i rev-aref) init-i (cdr abst-decls))))))
      (var-init-setup dims () init abst-declarator))
    ret))

(defun make-dimension-list-cloner (lis)
  (if (or (null lis)
          (atom lis)
          ;; dirty!!
          (and (listp lis)
               (first lis)
               (symbolp (first lis))
               (string= "MAKE-" (symbol-name (first lis))
                        :end1 5 :end2 5)))
      lis
      `(list ,@(loop for i in lis
                  collect (make-dimension-list-cloner i)))))
  

(defun expand-init-declarator-init (dspecs abst-declarator initializer)
  (let* ((var-type (ecase (car (first abst-declarator))
                     (:pointer
                      'pseudo-pointer) ; TODO: includes 'what it points'
                     (:funcall
                      (when (eq :aref (car (second abst-declarator)))
                        (error "a function returning an array is not accepted"))
                      (when (eq :funcall (car (second abst-declarator)))
                        (error "a function returning a function is not accepted"))
                      'function)         ; TODO: includes returning type, and arg type
                     (:aref
                      (loop with aref-type = (decl-specs-lisp-type dspecs)
                         for (tp tp-args) in abst-declarator
                         if (eq :funcall tp)
                         do (error "an array of functions is not accepted")
                         else if (eq :aref tp)
                         collect (or tp-args '*) into aref-dim
                         else if (eq :pointer tp)
                         do (setf aref-type 'pseudo-pointer) (loop-finish)
			 else
			 do (assert nil)
                         finally
                           (return `(simple-array ,aref-type ,aref-dim))))
                     ((nil)
		      (let ((dspecs-type (decl-specs-lisp-type dspecs)))
			(when (null dspecs-type)
			  (error "a void variable cannot be initialized"))
			dspecs-type))))
         (var-init (case (car (first abst-declarator))
		     (:pointer
                      initializer)
		     (:funcall
		      (unless (null initializer)
			(error "a function cannot take a initializer")))
		     (:aref
		      (let ((array-dim (third var-type)))
			(when (and (or (null array-dim)
				       (member '* array-dim))
				   (null initializer))
			  (error "array's dimension cannot be specified (~S, ~S)"
				 var-type initializer))
                        (let* ((merged-dim (array-dimension-resolve var-type initializer))
                               (init-list (setup-init-list merged-dim initializer
                                                           (expand-init-declarator-init
                                                            dspecs
                                                            (nthcdr (length merged-dim) abst-declarator)
                                                            nil)
                                                           dspecs (cdr abst-declarator))))
                          `(make-array ',merged-dim
                                       :element-type t ;; ',(second var-type)
                                       :initial-contents
                                       ,(make-dimension-list-cloner init-list)))))
		     (t
		      (cond
			((subtypep var-type 'number) ; includes enum
			 (or initializer 0))
			((subtypep var-type '(vector)) ; w-c-s-struct
                         (loop with name = (decl-specs-w-c-s-type-tag dspecs)
                            with struct-info = (assoc name *w-c-s-structs*)
                            for i in initializer
                            for fs in (getf (cdr struct-info) :fields)
                            collect (expand-init-declarator-init
                                     (w-c-s-struct-field-spec-decl-specs fs)
                                     (cdr abst-declarator) i)
                            into inits
                            finally
                              (return `(,(w-c-s-struct-constructor-name name)
                                         ,@inits))))
			(t (error "Internal error: unknown type ~S" var-type)))))))
    (values var-init var-type)))


(defun finalize-init-declarator (dspecs init-decl)
  (let* ((decl (init-declarator-declarator init-decl))
         (init (init-declarator-initializer init-decl))
         (var-name (first decl))
	 (storage-class (decl-specs-storage-class dspecs)))
    (when (and init
	       (eq 'extern storage-class))
      (error "an extern variable cannot have any initializers"))
    (when (and (eq :funcall (car (second decl)))
	       (not (member storage-class '(nil extern))))
      (error "a function cannot have storage-class except 'extern'"))
    (multiple-value-bind (var-init var-type)
	(expand-init-declarator-init dspecs (cdr decl) init)
      (setf (init-declarator-lisp-name init-decl) var-name
	    (init-declarator-lisp-initform init-decl) var-init
	    (init-declarator-lisp-type init-decl) var-type)
    init-decl)))

;; for expressions
(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; These are directly called by the parser..
(defun lispify-unary (op)
  #'(lambda (_ exp)
      (declare (ignore _))
      `(,op ,exp)))

(defun lispify-binary (op)
  #'(lambda (exp1 _ exp2)
      (declare (ignore _))
      `(,op ,exp1 ,exp2)))

(defun lispify-post-increment (op)
  #'(lambda (exp _)
      (declare (ignore _))
      (let ((tmp (gensym)))
	`(let ((,tmp ,exp))
	   (setf ,exp (,op ,tmp 1))
	   ,tmp))))

(defun lispify-augmented-assignment (op)
  #'(lambda (exp1 _ exp2)
      (declare (ignore _))
      (let ((tmp (gensym)))
	`(let ((,tmp ,exp1))
	   (setf ,exp1
		 (,op ,tmp ,exp2))))))
)

(defun ash-right (i c)
  (ash i (- c)))

(defun lispify-type-name (qls abs)
  (setf qls (finalize-decl-specs qls))
  (if abs
      (let ((init-decl (make-init-declarator :declarator abs)))
	(setf init-decl (finalize-init-declarator qls init-decl))
        (init-declarator-lisp-type init-decl))
      (decl-specs-lisp-type qls)))


;; for statements
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

(defun extract-if-statement (exp then-stat
			     &optional (else-stat nil))
  (let* ((stat (if else-stat
		   (merge-stat then-stat else-stat)
		   then-stat))
	 (then-tag (gensym "(if then)"))
	 (else-tag (gensym "(if else)"))
	 (end-tag (gensym "(if end)")))
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

(defvar *unresolved-break-tag* (gensym "unresolved break"))

(defun make-stat-unresolved-break ()
  (let ((ret (list 'go *unresolved-break-tag*)))
    (make-stat :code (list ret)
	       :break-statements (list ret))))

(defun rewrite-break-statements (sym stat)
  (loop for i in (stat-break-statements stat)
     do (setf (second i) sym))
  (setf (stat-break-statements stat) nil))

(defvar *unresolved-continue-tag* (gensym "unresolved continue"))

(defun make-stat-unresolved-continue ()
  (let ((ret (list 'go *unresolved-continue-tag*)))
    (make-stat :code (list ret)
	       :continue-statements (list ret))))

(defun rewrite-continue-statements (sym stat)
  (loop for i in (stat-continue-statements stat)
     do (setf (second i) sym))
  (setf (stat-continue-statements stat) nil))

(defun extract-loop (body-stat
		     &key (init nil) (cond t) (step nil)
		     (post-test-p nil))
  (let ((loop-body-tag (gensym "(loop body)"))
	(loop-step-tag (gensym "(loop step)"))
	(loop-cond-tag (gensym "(loop cond)"))
	(loop-end-tag (gensym "(loop end)")))
    (rewrite-break-statements loop-end-tag body-stat)
    (rewrite-continue-statements loop-step-tag body-stat)
    (setf (stat-code body-stat)
	  `((progn ,init)
	    ,(if post-test-p
		 `(go ,loop-body-tag)		; do-while
		 `(go ,loop-cond-tag))
	    ,loop-body-tag
	    ,@(stat-code body-stat)
	    ,loop-step-tag
	    (progn ,step)
	    ,loop-cond-tag
	    (when (progn ,cond)
	      (go ,loop-body-tag))
	    ,loop-end-tag))
    body-stat))

(defun push-case-label (case-label-exp stat)
  (let ((go-tag-sym (gensym (format nil "(case ~S)" case-label-exp))))
    (setf (stat-case-label-list stat)
	  (acons go-tag-sym case-label-exp
		 (stat-case-label-list stat)))
    (push go-tag-sym (stat-code stat))))

(defun extract-switch (exp stat)
  (let* ((exp-sym (gensym "(switch cond)"))
	 (end-tag (gensym "(switch end)"))
	 (jump-table			; create jump table with COND
	  (loop with default-clause =`(t (go ,end-tag))
	     for (go-tag-sym . case-label-exp)
	     in (stat-case-label-list stat)

	     if (eq case-label-exp 'default)
	     do (setf default-clause `(t (go ,go-tag-sym)))
	     else
	     collect `((eql ,exp-sym ,case-label-exp) (go ,go-tag-sym))
	     into clauses
	     finally
               (return
                 `(let ((,exp-sym ,exp))
                    (cond
                      ,@clauses
                      ,default-clause))))))
    (rewrite-break-statements end-tag stat)
    (setf (stat-case-label-list stat) nil)
    (setf (stat-code stat)
	  `(,jump-table
	    ,@(stat-code stat)
	    ,end-tag))
    stat))

;;: Toplevel
;; returns (values auto-binds register-binds static-binds
;;                 extern-binds global-binds enum-const-binds
;;                 constructors fields)
(defun expand-decl-bindings (declaration-list default-storage-class)
  (loop for (dspecs init-decls) in declaration-list
     as storage-class = (decl-specs-storage-class dspecs)
     as (var-binds func-binds)
       = (loop for i in init-decls
	    as b = (list (init-declarator-lisp-name i)
			 (init-declarator-lisp-initform i))
	    if (subtypep (init-declarator-lisp-type i) 'function)
	    collect b into func-binds
	    else
	    collect b into var-binds
	    finally (return (list var-binds func-binds)))
     if (or (eq storage-class 'auto)
            (and (null storage-class) (eq default-storage-class 'auto)))
       nconc var-binds into auto-binds
     if (eq storage-class 'register)
       nconc var-binds into register-binds
     if (eq storage-class 'extern)
       nconc var-binds into extern-binds
     if (and (null storage-class) (eq default-storage-class 'global))
       nconc var-binds into global-binds
     if (eq storage-class 'static)
       nconc var-binds into static-binds

     append func-binds into extern-binds

     append (decl-specs-lisp-bindings dspecs) into enum-const-binds
     append (decl-specs-lisp-constructor-spec dspecs) into constructors
     append (decl-specs-lisp-field-spec dspecs) into fields
     finally
       (return (values auto-binds register-binds extern-binds
                       global-binds static-binds enum-const-binds
                       constructors fields))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun w-c-s-struct-tag (obj)
    (aref obj 0))

  (defun (setf w-c-s-struct-tag) (val obj)
    (setf (aref obj 0) val))

  (defun w-c-s-struct-constructor (size tag &rest args)
    (loop with ret = (make-array `(,size))
       initially (setf (w-c-s-struct-tag ret) tag)
       for idx from 1 below size
       for arg in args
       do (setf (aref ret idx) arg)
       finally (return ret)))

  (defun maybe-w-c-s-struct-p (obj)
    (and (arrayp obj)
	 (plusp (length obj))
	 (symbolp (w-c-s-struct-tag obj)))))

(defun fbinding-func-names (fbinds)
  (loop for f in fbinds
     collect (first f)))

(defun expand-constructor-spec (constructors)
  (loop for ctor in constructors
     as struct-name = (w-c-s-struct-constructor-spec-struct-name ctor)
     as field-count = (w-c-s-struct-constructor-spec-field-count ctor)
     as func-name = (w-c-s-struct-constructor-name struct-name)
     collect `(,func-name
		(&rest args)
                (apply #'w-c-s-struct-constructor
                       ,field-count ',struct-name args))))

(defun expand-field-spec (fields)
  (let ((fields-table (make-hash-table :test 'eq))
        (func-arg 'arg)
        (func-newval 'newval))
    (flet ((expand-to-flet-body (clauses default)
             `(if (maybe-w-c-s-struct-p ,func-arg)
                  (case (w-c-s-struct-tag ,func-arg)
                    ,@clauses
                    (t ,default))
                  ,default)))
      ;; collect with their names
      (loop for f in fields
         as name = (w-c-s-struct-field-spec-field-name f)
         do (push f (gethash name fields-table)))
      ;; expand to flet func
      (loop for k being the hash-key of fields-table using (hash-value vals)
         as func-name = k
         as (func-body-r func-body-w) = 
           (loop with case-default-r = `(,func-name ,func-arg)
              with case-default-w = `(setf ,case-default-r ,func-newval)
              for v in vals
              as struct-name = (w-c-s-struct-field-spec-struct-name v)
              as index = (w-c-s-struct-field-spec-index v)
	      as constness = (w-c-s-struct-field-spec-constness v)
              as access-form = `(aref ,func-arg ,index)
              as case-clause-r = `(,struct-name ,access-form)
              as case-clause-w = `(,struct-name (setf ,access-form ,func-newval))
              collect case-clause-r into case-body-r
              if (not constness)
	      collect case-clause-w into case-body-w
              finally (return
                        (list (expand-to-flet-body case-body-r case-default-r)
                              (expand-to-flet-body case-body-w case-default-w))))
         collect `(,func-name (,func-arg) ,func-body-r)
         collect `((setf ,func-name) (,func-newval ,func-arg) ,func-body-w)))))

(defun expand-toplevel-stat (stat &key bindings entry-point)
    ;; TODO: support all
    (multiple-value-bind (autos registers externs globals statics enum-consts
                                ctors flds)
        (expand-decl-bindings (stat-declarations stat) 'auto)
      (let* ((lexical-binds
              (nconc autos registers
                     bindings
                     (if entry-point (copy-list *toplevel-bindings*))))
             (flet-funcs
              (nconc (expand-constructor-spec ctors)
                     (expand-field-spec flds)))
             (flet-names (fbinding-func-names flet-funcs))
	     (register-vars (mapcar #'first registers))
             (bad-pointers (intersection *dynamic-binding-required* register-vars))
             (special-vars nil)
             (global-defs nil)
             (sym-macros nil))
        ;; 'register' vars
        (when bad-pointers
          (warn "some variables are 'register', but its pointer is taken (~S)."
                bad-pointers))
        ;; 'extern' vars.
        (loop for (var init) in externs
           unless (or (null init) (zerop init))
           do (error "an 'extern' variable cannot have initializer (~S = ~S)" var init))
        ;; 'global' vars.
        (when globals
          (error "In internal scope, no global vars cannot be defined (~S)." globals))
        ;; 'static' vars.
        (loop for (var init) in statics
           as st-sym = (gensym (format nil "symbol-for-static-var ~S" var))
           do (push st-sym special-vars)
           do (push `(defvar ,st-sym ,init "generated by with-c-syntax, for static") global-defs)
           do (push `(,var ,st-sym) sym-macros))
        ;; enum consts
        (nconcf sym-macros enum-consts)
        ;; TODO: if no pointers used, we can remove some facilities.
        (prog1
            `(flet (,@flet-funcs)
               (declare (ignorable
                         ,@(mapcar #'(lambda (x) `(function ,x)) flet-names)))
               (symbol-macrolet ,sym-macros
                 (declare (special ,@special-vars))
                 ,@global-defs
                 (let* ,lexical-binds
		   (declare (dynamic-extent ,@register-vars))
                   (with-dynamic-bound-symbols ,*dynamic-binding-required*
                     (block nil (tagbody ,@(stat-code stat)))))))
          (setf *dynamic-binding-required* nil)
          ;; TODO: remove them
          (setf *enum-declarations-alist* nil)))))

(defstruct function-definition
  lisp-code
  lisp-type)

(defun lispify-function-definition (name body &key
                                                (return *default-decl-specs*)
                                                (K&R-decls nil))
  (let* ((func-name (first name))
         (func-param (getf (second name) :funcall))
         (param-ids
          (loop for (dspec tspecs) in func-param
             collect (first tspecs))))
    (setf return (finalize-decl-specs return))
    (when K&R-decls
      (let* ((K&R-param-ids
              (mapcar #'first (expand-decl-bindings K&R-decls 'auto))))
        (unless (equal K&R-param-ids param-ids)
          (error "prototype is not matched with k&r-style params"))))
    (make-function-definition
     :lisp-code `((defun ,func-name ,param-ids
                    ,(expand-toplevel-stat
                      body
		      :bindings		; TODO: check this is required or not
                      (mapcar #'(lambda (p) (list p p)) param-ids))))
     :lisp-type `(function ',(mapcar (constantly t) param-ids)
                           ',(decl-specs-lisp-type return)))))

(defun expand-translation-unit (units)
  (loop
     for u in units
     if (function-definition-p u)
     append (function-definition-lisp-code u) into codes
     else
     collect u into decls
     finally
       (multiple-value-bind (autos registers externs globals statics enum-consts
                                   ctors flds)
           (expand-decl-bindings decls 'global)
         (let* ((lexical-binds
                 (copy-list *toplevel-bindings*))
                (flet-funcs
                 (nconc (expand-constructor-spec ctors)
                        (expand-field-spec flds)))
                (flet-names (fbinding-func-names flet-funcs))
                (special-vars nil)
                (global-defs nil)
                (sym-macros nil))
           ;; 'auto' and 'register'
           (when (or autos registers)
             (error "At top level, 'auto' or 'register' variables are not accepted (~S)"
                    (append autos registers)))
           ;; 'extern' vars.
           (loop for (var init) in externs
              unless (or (null init) (zerop init))
              do (error "an 'extern' variable cannot have initializer (~S = ~S)" var init))
           ;; 'global' vars.
           (loop for (var init) in globals
              do (push var special-vars)
              do (push `(defvar ,var ,init "generated by with-c-syntax, for global") global-defs))
           ;; 'static' vars.
           (loop for (var init) in statics
              as st-sym = (gensym (format nil "symbol-for-static-var ~S" var))
              do (push st-sym special-vars)
              do (push `(defvar ,st-sym ,init "generated by with-c-syntax, for static") global-defs)
              do (push `(,var ,st-sym) sym-macros))
           ;; enum consts
           (nconcf sym-macros enum-consts)
           ;; TODO: support all
           (return
             `(flet (,@flet-funcs)
                (declare (ignorable
                          ,@(mapcar #'(lambda (x) `(function ,x)) flet-names)))
                (symbol-macrolet ,sym-macros
                  (declare (special ,@special-vars))
                  ,@global-defs
                  (let* ,lexical-binds
                    (with-dynamic-bound-symbols ,*dynamic-binding-required*
                      (block nil ,@codes))))))))))

;;; The parser
(define-parser *expression-parser*
  (:muffle-conflicts t)

  (:start-symbol w-c-s-entry-point)

  ;; http://www.swansontec.com/sopc.html
  (:precedence (;; Primary expression
		(:left \( \) [ ] \. -> ++ --)
		;; Unary
		(:right * & + - ! ~ ++ -- #+ignore(typecast) sizeof)
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
		(:left \,)
		))

  ;; http://www.cs.man.ac.uk/~pjj/bnf/c_syntax.bnf
  (:terminals
   #.(append +operators+
	     +keywords+
	     '(enumeration-const id
	       int-const char-const float-const
	       string)
	     '(lisp-expression)))

  ;; Our entry point.
  ;; top level forms in C, or statements
  (w-c-s-entry-point
   (translation-unit
    #'(lambda (us) (expand-translation-unit us)))
   (labeled-stat
    #'(lambda (st) (expand-toplevel-stat st :entry-point t)))
   ;; exp-stat is not included, because it is gramatically ambiguous.
   (compound-stat
    #'(lambda (st) (expand-toplevel-stat st :entry-point t)))
   (selection-stat
    #'(lambda (st) (expand-toplevel-stat st :entry-point t)))
   (iteration-stat
    #'(lambda (st) (expand-toplevel-stat st :entry-point t)))
   (jump-stat
    #'(lambda (st) (expand-toplevel-stat st :entry-point t))))


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

  ;; returns 'decl-specs' structure
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
   auto register static extern typedef) ; keywords

  (type-spec
   void char short int long float double signed unsigned ; keywords
   struct-or-union-spec
   enum-spec
   typedef-name)                        ; not supported -- TODO!!

  (type-qualifier
   const volatile)                      ; keywords

  ;; returns struct-or-union-spec structure
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
   struct union)                        ; keywords

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

  ;; returns init-declarator structure
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

  ;; returns spec-qualifier-list structure
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

  ;; returns struct-declarator structure
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

  ;; returns enum-spec structure
  (enum-spec
   (enum id { enumerator-list }
         #'(lambda (_kwd id _l lis _r)
             (declare (ignore _kwd _l _r))
	     (make-enum-spec :id id :enumerator-list lis)))
   (enum    { enumerator-list }
         #'(lambda (_kwd _l lis _r)
             (declare (ignore _kwd _l _r))
	     (make-enum-spec :enumerator-list lis)))
   (enum id
         #'(lambda (_kwd id)
             (declare (ignore _kwd))
	     (make-enum-spec :id id))))

  (enumerator-list
   (enumerator
    #'list)
   (enumerator-list \, enumerator
                    #'concatinate-comma-list))

  ;; returns enumerator structure
  (enumerator
   (id
    #'(lambda (id)
	(make-enumerator :declarator id)))
   (id = const-exp
       #'(lambda (id _op exp)
           (declare (ignore _op))
	   (make-enumerator :declarator id :initializer exp))))

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

  ;; returns a struct, if initializer-list is used.
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

  ;; returns like:
  ;; (:aref nil) (:funcall nil) (:aref 5 :funcall (int))
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


  ;; ;; TODO
  ;; (typedef-name
  ;;  id)


  ;;; Statements: 'stat' structure
  ;; 
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
   (case const-exp \: stat
       #'(lambda (_k  exp _c stat)
	   (declare (ignore _k _c))
	   (push-case-label exp stat)
	   stat))
   (default \: stat
       #'(lambda (_k _c stat)
	   (declare (ignore _k _c))
	   (push-case-label 'default stat)
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
   (if \( exp \) stat
       #'(lambda (op lp exp rp stat)
	   (declare (ignore op lp rp))
	   (extract-if-statement exp stat)))
   (if \( exp \) stat else stat
       #'(lambda (op lp exp rp stat1 el stat2)
	   (declare (ignore op lp rp el))
	   (extract-if-statement exp stat1 stat2)))
   (switch \( exp \) stat
	   #'(lambda (_k _lp exp _rp stat)
	       (declare (ignore _k _lp _rp))
	       (extract-switch exp stat))))

  (iteration-stat
   (while \( exp \) stat
	  #'(lambda (_k _lp cond _rp body)
	      (declare (ignore _k _lp _rp))
	      (extract-loop body :cond cond)))
   (do stat while \( exp \) \;
     #'(lambda (_k1 body _k2 _lp cond _rp _t)
	 (declare (ignore _k1 _k2 _lp _rp _t))
	 (extract-loop body :cond cond :post-test-p t)))
   (for \( exp \; exp \; exp \) stat
	#'(lambda (_k _lp init _t1 cond _t2 step _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (extract-loop body :init init :cond cond :step step)))
   (for \( exp \; exp \;     \) stat
	#'(lambda (_k _lp init _t1 cond _t2      _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (extract-loop body :init init :cond cond)))
   (for \( exp \;     \; exp \) stat
	#'(lambda (_k _lp init _t1      _t2 step _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (extract-loop body :init init :step step)))
   (for \( exp \;     \;     \) stat
	#'(lambda (_k _lp init _t1      _t2      _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (extract-loop body :init init)))
   (for \(     \; exp \; exp \) stat
	#'(lambda (_k _lp      _t1 cond _t2 step _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (extract-loop body :cond cond :step step)))
   (for \(     \; exp \;     \) stat
	#'(lambda (_k _lp      _t1 cond _t2      _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (extract-loop body :cond cond)))
   (for \(     \;     \; exp \) stat
	#'(lambda (_k _lp      _t1      _t2 step _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (extract-loop body :step step)))
   (for \(     \;     \;     \) stat
	#'(lambda (_k _lp      _t1      _t2      _rp body)
	    (declare (ignore _k _lp _t1 _t2 _rp))
	    (extract-loop body))))

  (jump-stat
   (goto id \;
	 #'(lambda (_k id _t)
	     (declare (ignore _k _t))
	     (make-stat :code (list `(go ,id)))))
   (continue \;
	     #'(lambda (_k _t)
		 (declare (ignore _k _t))
		 (make-stat-unresolved-continue)))
   (break \;
	  #'(lambda (_k _t)
	      (declare (ignore _k _t))
	      (make-stat-unresolved-break)))
   (return exp \;
	   #'(lambda (_k exp _t)
	       (declare (ignore _k _t))
	       ;; use the block of PROG
	       (make-stat :code (list `(return ,exp)))))
   (return \;
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
	      (lispify-augmented-assignment '*))
   (unary-exp /= assignment-exp
	      (lispify-augmented-assignment '/))
   (unary-exp %= assignment-exp
	      (lispify-augmented-assignment 'mod))
   (unary-exp += assignment-exp
	      (lispify-augmented-assignment '+))
   (unary-exp -= assignment-exp
	      (lispify-augmented-assignment '-))
   (unary-exp <<= assignment-exp
	      (lispify-augmented-assignment 'ash))
   (unary-exp >>= assignment-exp
	      (lispify-augmented-assignment 'ash-right))
   (unary-exp &= assignment-exp
	      (lispify-augmented-assignment 'logand))
   (unary-exp ^= assignment-exp
	      (lispify-augmented-assignment 'logxor))
   (unary-exp \|= assignment-exp
	      (lispify-augmented-assignment 'logior)))

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
		     (lispify-binary 'ash-right)))

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
   (\( type-name \) cast-exp		; TODO: type-name must be defined
       #'(lambda (op1 type op2 exp)
	   (declare (ignore op1 op2))
	   `(coerce ,exp ',type))))

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
          ;; TODO: consider it. We should this exp is setf-able or not?
          (if (symbolp exp)
              (progn
                (push exp *dynamic-binding-required*)
                `(make-pseudo-pointer* ,exp ',exp))
              `(make-pseudo-pointer ,exp))))a
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
   (sizeof unary-exp			; TODO: add struct
	   #'(lambda (_op exp)
	       (declare (ignore _op))
	       `(if (arrayp ,exp)
		    (array-total-size ,exp)
		    1)))
   (sizeof \( type-name \)		; TODO: add struct
	   #'(lambda (_op _lp tp _rp)
	       (declare (ignore _op _lp _rp))
	       (if (subtypep tp 'array)
		   (array-total-size (make-array (third tp)))
		   1))))

  (postfix-exp
   primary-exp
   (postfix-exp [ exp ]			; TODO: compound with multi-dimention
		#'(lambda (exp op1 idx op2)
		    (declare (ignore op1 op2))
                    (if (and (listp exp) (eq (first exp) 'aref))
                        (destructuring-bind (op exp &rest args) exp
                          `(,op ,exp ,@args ,idx))
                        `(aref ,exp ,idx))))
   (postfix-exp \( argument-exp-list \)
		#'(lambda (exp op1 args op2)
		    (declare (ignore op1 op2))
		    `(,exp ,@args)))
   (postfix-exp \( \)
		#'(lambda (exp op1 op2)
		    (declare (ignore op1 op2))
		    `(,exp)))
   (postfix-exp \. id
		#'(lambda (exp _op id) ; id is assumed as a reader
		    (declare (ignore _op))
		    `(,id ,exp)))
   (postfix-exp -> id
		#'(lambda (exp _op id) ; id is assumed as a reader
		    (declare (ignore _op))
		    `(,id (pseudo-pointer-dereference ,exp))))
   (postfix-exp ++
                (lispify-post-increment '+))
   (postfix-exp --
                (lispify-post-increment '-)))

  (primary-exp
   id
   const*
   string
   (\( exp \)
       #'(lambda  (_1 x _3)
	   (declare (ignore _1 _3))
	   x))
   lisp-expression)			; added

  (argument-exp-list
   (assignment-exp
    #'list)
   (argument-exp-list \, assignment-exp
                      #'concatinate-comma-list))

  (const*
   int-const
   char-const
   float-const
   enumeration-const)			; TODO
  )

;;; Expander
(defun c-expression-tranform (bindings form)
  (let* ((*enum-declarations-alist* nil)
	 (*toplevel-bindings* bindings)
	 (*dynamic-binding-required* nil)
         (*w-c-s-structs* nil)
	 (lisp-exp (parse-with-lexer (list-lexer form)
                                     *expression-parser*)))
    lisp-exp))

;;; Macro interface
(defmacro with-c-syntax ((&rest bindings) &body body)
  (c-expression-tranform bindings body))
