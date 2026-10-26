# Build the Vole extension module for the Python that runs it.
#
#   make                         builds ./vole_hello.<python-suffix>.so
#   make check                   imports it and calls hello()
#   make PYTHON=/path/to/python3 check
#
# VOLEC defaults to the compiler in the built tree.

VOLEC ?= ../../target/volec
PYTHON ?= $(shell command -v python3.14 2>/dev/null \
	|| command -v python3 2>/dev/null || echo python3)

PY_INCLUDE := $(shell $(PYTHON) -c \
	'import sysconfig; print(sysconfig.get_paths()["include"])')
PY_SUFFIX := $(shell $(PYTHON) -c \
	'import sysconfig; print(sysconfig.get_config_var("EXT_SUFFIX"))')
PY_LDSHARED := $(shell $(PYTHON) -c \
	'import sysconfig; print(sysconfig.get_config_var("LDSHARED"))')

MODULE := vole_hello$(PY_SUFFIX)

all: $(MODULE)

vole_hello.o: vole_hello.vl
	$(VOLEC) -O2 -c -I $(PY_INCLUDE) vole_hello.vl -o $@

$(MODULE): vole_hello.o
	$(PY_LDSHARED) vole_hello.o -o $@

check: $(MODULE)
	PYTHONPATH=. $(PYTHON) test_vole_hello.py

clean:
	rm -f vole_hello.o vole_hello*.so

.PHONY: all check clean
