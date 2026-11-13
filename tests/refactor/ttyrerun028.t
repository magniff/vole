## (0.28.0) A build with errors that read std lazily is made again with
## std whole (front/modules/std2lazy.vl): the run made again has this
## run's form, a terminal's on a terminal (it was the plain form: the
## second run took itself for a volec inside a volec).
% sh tty.sh "$COMPILER" bad.vl -o bad | cat -v | sed 's/in [0-9.]*s/in Ts/'
^[[1;31merror[type error]^[[0m^[[1m: expected 'i32', got '&str'^[[0m
 ^[[1;34m-->^[[0m bad.vl:2:18
  ^[[1;34m|^[[0m
^[[1;34m2 |^[[0m     let x: i32 = "a";
  ^[[1;34m|^[[0m                  ^[[1;31m^^^^[[0m
    ^[[1;32mChecking^[[0m bad.vl ... ^[[31m1 error^[[0m
      ^[[1;31mFailed^[[0m bad: 1 error in Ts
% sh tty.sh "$COMPILER" --color=never bad.vl -o bad
error[type error]: expected 'i32', got '&str'
 --> bad.vl: line 2, column 18
$ bad.vl -o bad
bad.vl:2:18: error[type error] expected 'i32', got '&str'
[exit 1]
