.PHONY: setup clean clean-all

# Full setup: pull duniverse, vendor deps, apply patches, test build
setup:
	bash scripts/setup-monorepo.sh

# Clean build artifacts (keeps vendored sources)
clean:
	rm -rf _build/ _build-*
	find benchmarks -name "*.build-failed" -delete 2>/dev/null || true

# Clean everything (vendored sources + build artifacts)
# After this, run `make setup` to re-populate
clean-all: clean
	rm -rf duniverse/ vendor/
