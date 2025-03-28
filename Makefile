export NVIM_RUNNER_VERSION := v0.11.0
export NVIM_TEST_VERSION ?= v0.11.0

nvim-test:
	git clone https://github.com/lewis6991/nvim-test
	nvim-test/bin/nvim-test --init

.PHONY: test
test: nvim-test
	nvim-test/bin/nvim-test test \
		--lpath=$(PWD)/lua/?.lua
