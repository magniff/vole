# python-ext

A CPython extension module written in Vole. Python imports `vole_hello`
and calls its one function:

```python
>>> import vole_hello
>>> vole_hello.hello()
hello from vole
```

There is no C shim and nothing is generated: `Python.h` supplies the C
API declarations, Vole defines the module's exported entry point and
method, and the Python interpreter resolves the CPython symbols when it
loads the `.so`.

| file | what it is |
|---|---|
| `vole_hello.vl` | the whole module: `hello()`, its method table, and `PyInit_vole_hello` |
| `Makefile` | builds the extension for a chosen Python, then checks the import |
| `test_vole_hello.py` | imports the module, checks its documentation and calls `hello()` |

## Build and run

From this folder (from a built tree, `volec` is `../../target/volec`):

```sh
make
make check
```

`make` asks Python for its include directory, extension suffix and shared
linker command, compiles `vole_hello.vl` to an object with `volec -c`, and
links the `.so`. It picks `python3.14` when present, otherwise `python3`;
choose another explicitly when needed:

```sh
make PYTHON=/usr/bin/python3
```

The successful check prints the call's output:

```
hello from vole
```

Use the same interpreter for manual imports; the extension suffix is
specific to its version and ABI:

```sh
PYTHONPATH=. python3.14 -c 'import vole_hello; vole_hello.hello()'
```

Expected output:

```
hello from vole
```

The module and function also carry their documentation:

```python
>>> vole_hello.__doc__
'A minimal Vole extension module.'
>>> vole_hello.hello.__doc__
'Print hello from Vole.'
```

### In an editor

`volec check` needs the same include directory as the build (`volec
check -I "$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["include"])')"
vole_hello.vl`), and so does the language server: in VS Code, set
`vole.includePaths` to that directory (`.vscode/settings.json`;
[docs/lsp.md](../../docs/lsp.md#c-imports-0252)). Then the file's errors
show as you type, F12 on `"Python.h"` opens the header and F12 on
`py::PySys_WriteStdout` its declaration in `sysmodule.h`. Without it the
import is `header not found: Python.h`, and the errors that do not
depend on the header are still shown.

## How it works

### Python's declarations, imported

```tach
import "Python.h" as py;
import "stdlib.h" as c;
```

The header gives the same names the C API uses: `PyObject`,
`PyMethodDef`, `PyModuleDef`, `PyModule_Create2`,
`PySys_WriteStdout`, `Py_BuildValue`, `METH_NOARGS` and
`PYTHON_API_VERSION`. Constants and object-like macros arrive as Vole
constants; function-like macros and `static inline` helpers do not, so
the module calls real exported functions.

### The single Python-visible function

```tach
extern "C" fn hello(self: *py::PyObject, args: *py::PyObject) -> *py::PyObject {
    unsafe {
        py::PySys_WriteStdout(c"hello from vole\n");
        py::Py_BuildValue(c"")
    }
}
```

`extern "C"` gives it C's convention and an unmangled symbol, which is
what a `PyCFunction` needs. `PySys_WriteStdout` writes through Python's
`sys.stdout`, so Python-level redirection applies. `Py_BuildValue("")`
returns a new reference to `None`; returning it is the C API's way of
saying a function produced no value. A null return would mean an
exception instead.

### The module entry point

Importing `vole_hello` makes CPython look up `PyInit_vole_hello` with
`dlsym`. That function allocates a two-entry `PyMethodDef` table (the
second entry is the zeroed terminator) and a `PyModuleDef`, fills them,
and returns `PyModule_Create2(def, PYTHON_API_VERSION)`:

```tach
extern "C" fn PyInit_vole_hello() -> *py::PyObject {
    let methods = unsafe { c::calloc(2, size_of(py::PyMethodDef) as u64) as *py::PyMethodDef };
    let def = unsafe { c::calloc(1, size_of(py::PyModuleDef) as u64) as *py::PyModuleDef };
    // ... fill methods and def ...
    unsafe { py::PyModule_Create2(def, py::PYTHON_API_VERSION) }
}
```

The definitions are allocated rather than static for a concrete reason:
CPython keeps those pointers for the interpreter's lifetime, and Vole
does not accept a function reference in a static initializer (`'hello'
is not a constant`) or a cast from an integer to a function pointer.
`calloc` both provides zeroed storage—so the unused slots, traversal,
clear and free callbacks stay `NULL`—and makes the intentional one-time
leak explicit. `PyModule_Create2` initializes `m_base` itself, so the
zeroed base is correct.

### Building the shared object

`Makefile` uses the target Python's own answers instead of hard-coded
flags:

- `sysconfig.get_paths()["include"]` is the `Python.h` directory;
- `sysconfig.get_config_var("EXT_SUFFIX")` gives the ABI-specific
  filename Python will import (`.cpython-314-darwin.so` here);
- `sysconfig.get_config_var("LDSHARED")` gives the platform's shared
  linker (`clang -bundle -undefined dynamic_lookup` on macOS,
  `gcc -shared` on Linux).

The extension is deliberately not linked against `libpython`. On macOS,
`-undefined dynamic_lookup` leaves the CPython symbols for the running
interpreter to supply; on Linux the interpreter's exported symbols do
the same. `cc` is therefore not asked to find a Python library.

## Limitations

- This is the full CPython C API, not the limited/stable ABI: rebuild the
  extension for each Python minor version and implementation.
- One function, no module state, no subinterpreter or free-threaded-build
  testing.
- The method and module definitions are intentionally never freed; they
  live as long as the interpreter.
- Vole's C interop targets macOS and Linux; this example was built and
  imported with Python 3.14.8 on macOS arm64.

## Verified

`make check` builds the object with Vole 0.25.1, links it with the
Python 3.14 `LDSHARED`, imports the result, checks the module and
function documentation, and calls `hello()`:

```
hello from vole
```
