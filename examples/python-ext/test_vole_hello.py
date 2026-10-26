"""Check the Vole extension module through a real Python import."""

import subprocess
import sys

import vole_hello

assert vole_hello.__doc__ == "A minimal Vole extension module."
assert vole_hello.hello.__doc__ == "Print hello from Vole."

result = subprocess.run(
    [sys.executable, "-c", "import vole_hello; assert vole_hello.hello() is None"],
    check=True,
    capture_output=True,
    text=True,
)
assert result.stdout == "hello from vole\n", result.stdout
print("python extension ok: hello from vole")
