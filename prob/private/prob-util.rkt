#lang racket/base
(require math/distributions
         racket/contract/base
         "prob-hooks.rkt"
         "util.rkt")
(provide rejection-sample
         (contract-out
          [mem (-> procedure? procedure?)])
         ERP)

;; Rejection sampling

(define (rejection-sample thunk pred [project values])
  (let ([v (thunk)])
    (if (pred v)
        (project v)
        (rejection-sample thunk pred project))))

;; mem and ERP wrappers

;; NOTE: enum-ERP knows about discrete dists by tag
;; FIXME: add discrete-dist? to math/distributions
(define (mem f) ((current-mem) f))
(define (ERP tag dist) ((current-ERP) tag dist))

;; ==  Finite distributions ==

(provide
 (contract-out
  [flip
   (->* [] [probability?] boolean?)]
  [d2
   (->* [] [probability?] (or/c 1 0))])
 discrete)

;; flip : Prob -> (U #t #f)
(define (flip [prob 1/2])
  (positive?
   (ERP `(flip ,prob)
        (make-dist bernoulli #:params (prob) #:enum 2))))

;; d2 : Prob -> (U 1 0)
(define (d2 [prob 1/2])
  (bernoulli prob))

(define (bernoulli [prob 1/2])
  (inexact->exact
   (ERP `(bernoulli ,prob)
        (make-dist bernoulli #:params (prob) #:enum 2))))

;; Used in #:params, syntactically required to be identifier.
(define ZERO 0.0)

;; discrete : Nat -> Nat
;; discrete : (listof (list A Prob))) -> A
(define discrete
  (case-lambda
    [(n/vals)
     (cond [(and (list? n/vals) (pair? n/vals))
            (inexact->exact
             (floor
              (ERP `(discrete ,n/vals)
                   (make-dist uniform #:params (ZERO n/vals) #:enum n/vals))))]
           [(exact-positive-integer? n/vals)
            (let ([n (length n/vals)])
              (list-ref n/vals
                        (inexact->exact
                         (floor
                          (ERP `(discrete ,n/vals)
                               (make-dist uniform #:params (ZERO n) #:enum n))))))]
           [else
            (raise-argument-error 'discrete
              "(or/c exact-positive-integer? (and/c list? pair?))" 0 n/vals)])]
    [(vals probs)
     (unless (and (list? vals) (pair? vals))
       (raise-argument-error 'discrete "(and/c list? pair?)" 0 vals probs))
     (unless (and (list? probs) (pair? probs) (andmap real? probs) (andmap positive? probs))
       (raise-argument-error 'discrete "(non-empty-listof (>/c 0))" 1 vals probs))
     (unless (= (length vals) (length probs))
       (error 'discrete
              "values and probability weights have different lengths\n  values: ~e\n  weights: ~e"
              vals probs))
     (define n (length vals))
     (lookup-discrete vals probs 
                      (ERP `(discrete ,vals ,probs)
                           (make-dist uniform #:params (ZERO n) #:enum n)))]))

(define (lookup-discrete vals probs p)
  (cond [(null? vals)
         (error 'discrete "internal error: out of values")]
        [(< p (car probs))
         (car vals)]
        [else (lookup-discrete (cdr vals) (cdr probs) (- p (car probs)))]))

;; == Countable distributions ==

(provide
 (contract-out
  [geometric
   (->* [] [probability?]
        exact-nonnegative-integer?)]
  [poisson
   (->* [(>/c 0)] []
        exact-nonnegative-integer?)]
  [binomial
   (->* [exact-nonnegative-integer? probability?] []
        exact-nonnegative-integer?)]))

;; binomial : Nat Prob -> Integer
;; FIXME: discretizable
(define (binomial n p)
  (inexact->exact
   (ERP `(binomial ,n ,p)
        (make-dist binomial #:params (n p) #:enum (add1 n)))))

;; geometric : Prob -> Integer
;; FIXME: discretizable
(define (geometric [p 1/2])
  (inexact->exact
   (ERP `(geometric ,p)
        (make-dist geometric #:params (p) #:enum 'lazy))))

;; poisson : Real -> Integer
;; FIXME: probably discretizable (???)
(define (poisson mean)
  (inexact->exact
   (ERP `(poisson ,mean)
        (make-dist poisson #:params (mean) #:enum 'lazy))))

;; == Continuous distributions ==

(provide
 (contract-out
  [beta
   (-> (>/c 0) (>/c 0)
       real?)]
  [cauchy
   (->* [] [real? (>/c 0)]
        real?)]
  [exponential
   (->* [] [(>/c 0)]
        real?)]
  [gamma
   (->* [] [(>/c 0) (>/c 0)]
        real?)]
  [logistic
   (->* [] [real? (>/c 0)]
        real?)]
  [normal
   (->* [] [real? (>/c 0)]
        real?)]
  [uniform
   (->* [] [real? real?]
        real?)]
  ))

;; beta : PositiveReal PositiveReal -> Real in [0,1]
(define (beta a b)
  (ERP `(beta ,a ,b)
       (make-dist beta #:params (a b) #:enum #f)))

(define (cauchy [mode 0] [scale 1])
  (ERP `(cauchy ,mode ,scale)
       (make-dist cauchy #:params (mode scale) #:enum #f)))

;; exponential : PositiveReal -> PositiveReal
;; NOTE: mean aka scale = 1/rate
(define (exponential mean)
  (ERP `(exponential ,mean)
       (make-dist exponential #:params (mean) #:enum #f)))

;; gamma : PositiveReal PositiveReal -> Real
;; NOTE: scale = 1/rate
(define (gamma [shape 1] [scale 1])
  (ERP `(gamma ,shape ,scale)
       (make-dist gamma #:params (shape scale) #:enum #f)))

;; logistic : Real Real -> Real
(define (logistic [mean 0] [scale 1])
  (ERP `(logistic ,mean ,scale)
       (make-dist logistic #:params (mean scale) #:enum #f)))

;; normal : Real PositiveReal -> Real
;; NOTE: stddev = (sqrt variance)
(define (normal [mean 0] [stddev 1])
  (ERP `(normal ,mean ,stddev)
       (make-dist normal #:params (mean stddev) #:enum #f)))

;; uniform : Real Real -> Real
(define uniform
  (case-lambda
    [() (uniform 0 1)]
    [(max) (uniform 0 max)]
    [(min max)
     (ERP `(uniform ,min ,max)
          (make-dist uniform #:params (min max) #:enum #f))]))