# sh tty.sh CMD...: CMD with stdin, stdout and stderr on a pseudo-terminal
# (script(1): macOS's, or util-linux's -c), its output with CR LF as LF and
# without the `^D` (and backspaces) macOS's script echoes for stdin's end.
if [ "$(uname -s)" = Darwin ]; then
    script -q /dev/null "$@" </dev/null
else
    script -qec "$*" /dev/null </dev/null
fi | tr -d '\r\010' | sed '1s/^^D//'
