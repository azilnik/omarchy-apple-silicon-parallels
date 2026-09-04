# Convenience targets for building and releasing the image.
# Usage: make refresh | make image VERSION=0.1.0 | make test ZIP=dist/... | make release VERSION=0.1.0

.PHONY: help refresh image test release lint bundle tui-test

help:
	@echo "make refresh              — update builder VM + install payload, gate on verify (Tier 1)"
	@echo "make image VERSION=x.y.z  — clone, sysprep, compact, package a signed image"
	@echo "make test ZIP=<path>      — Tier 2 cold-import simulation"
	@echo "make release VERSION=x.y.z— upload to R2, update latest.json, tag"
	@echo "make bundle               — inline lib/tui.sh into install.sh"
	@echo "make tui-test             — headless installer + TUI checks (no VM, no network)"
	@echo "make lint                 — shellcheck + install.sh/lib drift check"

refresh:
	./build/refresh.sh

image:
	@test -n "$(VERSION)" || { echo "set VERSION=x.y.z"; exit 1; }
	./build/package.sh $(VERSION)

test:
	@test -n "$(ZIP)" || { echo "set ZIP=dist/omarchy-parallels-vX.Y.Z.zip"; exit 1; }
	./test/run-tests.sh $(ZIP)

release:
	@test -n "$(VERSION)" || { echo "set VERSION=x.y.z"; exit 1; }
	./build/release.sh $(VERSION)

bundle:
	./build/bundle.sh

tui-test:
	./test/tui/run-tui-tests.sh

# Same severity and exclusions as .github/workflows/shellcheck.yml, so a green local lint
# means a green CI lint.
lint:
	./build/bundle.sh --check
	shellcheck --severity=warning -e SC1091 -e SC2029 -e SC2154 -e SC2034 -e SC2012 \
	  install.sh host/*.sh build/refresh.sh build/sysprep.sh build/package.sh build/release.sh \
	  build/bundle.sh build/vm-ssh guest/*.sh test/run-tests.sh test/tui/harness.sh test/tui/run-tui-tests.sh
	shellcheck --severity=warning -e SC1091 -e SC2034 -e SC2154 -s bash lib/tui.sh
