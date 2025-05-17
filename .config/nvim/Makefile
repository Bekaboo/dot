.PHONY: all
all: format lint

.PHONY: format-check
format-check:
	stylua . --check

.PHONY: format
format:
	stylua .

.PHONY: lint
lint:
	luacheck -q .
