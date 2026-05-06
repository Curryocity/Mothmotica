ODIN ?= odin
PYTHON ?= python3

.PHONY: cli gui imgui-deps clean

cli:
	$(ODIN) build src -out:mothmotica-cli

imgui-deps:
	cd third_party/odin-imgui && $(PYTHON) build.py

gui: cli
	$(ODIN) build gui -out:mothmotica-gui

clean:
	rm -f src.bin mothmotica-cli mothmotica-cli.exe mothmotica-gui mothmotica-gui.exe
