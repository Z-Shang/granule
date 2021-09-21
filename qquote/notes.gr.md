# Notes of Quasi Quoted Code (Boxed Code)

## Syntax Introduced
As inspired by [Najd 2015], the syntax chosen for the `Box` operation as described in [Davies 1999]
(quasiquote in most Lisps)
is represented as:
```
-- Box
[| expr : t |] : `t
```

together with unboxing via binding:
~~~granule
foo : `(Int -> Int)
foo = [| \(n : Int) -> n + 1 |]

bar : forall {a, b : Type} . `(a -> b) -> a -> b
bar [f] a = f a

foobar : Int -> Int
foobar = bar foo
~~~

## Bib
[Najd 2015] @article{article,
author = {Najd, Shayan and Lindley, Sam and Svenningsson, Josef and Wadler, Philip},
year = {2015},
month = {07},
pages = {},
title = {Everything old is new again: Quoted Domain Specific Languages}
}

[Davies 1999] @article{article,
author = {Davies, Rowan and Pfenning, Frank},
year = {1999},
month = {09},
pages = {},
title = {A Modal Analysis of Staged Computation},
volume = {48},
journal = {Journal of the ACM},
doi = {10.1145/382780.382785}
}
