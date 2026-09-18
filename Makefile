SHELL := /bin/bash
.DEFAULT_GOAL := help

SRC_FILES := install.sh $(wildcard src/*.sh) $(wildcard src/platform/*.sh)

.PHONY: help lint syntax check

help:
	@echo "ai-memory-manager - alvos disponiveis:"
	@echo "  make lint     Roda shellcheck em install.sh e src/"
	@echo "  make syntax   Verifica a sintaxe com bash -n"
	@echo "  make check    Roda lint + syntax (obrigatorio antes de PR)"
	@echo "  make help     Mostra esta ajuda"

lint:
	shellcheck $(SRC_FILES)

syntax:
	@for f in $(SRC_FILES); do bash -n "$$f" || exit 1; done
	@echo "syntax OK"

check: lint syntax
