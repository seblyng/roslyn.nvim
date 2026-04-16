export NVIM_RUNNER_VERSION := v0.12.1
export NVIM_TEST_VERSION ?= v0.12.1

nvim-test:
	git clone https://github.com/lewis6991/nvim-test
	nvim-test/bin/nvim-test --init

.PHONY: test
test: nvim-test
	nvim-test/bin/nvim-test test \
		--lpath=$(PWD)/lua/?.lua
