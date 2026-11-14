.PHONY: all
all: format-check lint test

.PHONY: format-check
format-check:
	stylua . --check

.PHONY: format
format:
	stylua .

.PHONY: lint
lint:
	luacheck -q .

# Tests live under `tests/`, split by what they cover:
#
#   tests/plugin     builtin plugins under `lua/my/plugin`
#   tests/utils      utility modules under `lua/my/utils`
#
# Third-party plugin tests and end-to-end tests go to `tests/thirdparty` and
# `tests/e2e` when they are introduced.
.PHONY: test
test:
	nvim --clean --headless -u tests/minimal_init.lua \
		+"PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }" \
		+qa!

# Examples:
# test-file-plugin:winbar:bar (will run `tests/plugin/winbar/bar_spec.lua`)
# test-file-utils:str (will run `tests/utils/str_spec.lua`)
.PHONY: test-file-%
test-file-%:
	nvim --clean --headless -u tests/minimal_init.lua \
		+"lua require('plenary.busted').run('tests/$(subst :,/,$*)_spec.lua')" \
		+qa!
