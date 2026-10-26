import vole_hello

assert vole_hello.__doc__ == "A minimal Vole extension module."
assert vole_hello.hello.__doc__ == "Print hello from Vole."

vole_hello.hello()
