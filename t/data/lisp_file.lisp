#!/usr/bin/env clisp
; This is a comment
;;; but this is documentation
#|
 | Is this a comment? It seems so.
 | #| Do they really nest? |#
 | Yes. This is still a comment.
 |#
(
  format t "Hello ~a!~%" (
    if ( > ( length *args* ) 0 ) ( first *args* ) "world"
  )
)
