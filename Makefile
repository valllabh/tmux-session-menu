.PHONY: help install uninstall test lint

help:
	@echo "targets:"
	@echo "  install    copy the script and add a source line to ~/.bashrc"
	@echo "  uninstall  remove the source line and installed script"
	@echo "  test       run the test suite against an isolated tmux socket"
	@echo "  lint       run shellcheck if available"

install:
	@bash scripts/install.sh

uninstall:
	@bash scripts/uninstall.sh

test:
	@echo "# bash"; bash test/test.sh
	@if command -v zsh >/dev/null 2>&1; then echo "# zsh"; zsh test/test.zsh; \
	else echo "# zsh not installed, skipping zsh tests"; fi

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -S warning tmux-session-menu.sh scripts/*.sh test/test.sh; \
	else \
		echo "shellcheck not installed, skipping"; \
	fi
	@if command -v zsh >/dev/null 2>&1; then zsh -n tmux-session-menu.plugin.zsh && echo "zsh -n: plugin OK"; fi
