.PHONY: setup clean clean-all

# Full setup: pull duniverse, vendor deps, apply patches, install rocq, test build
setup:
	bash scripts/setup-monorepo.sh

# Clean build artifacts (keeps vendored sources and rocq install)
clean:
	rm -rf _build/ _build-*
	find benchmarks -name "*.build-failed" -delete 2>/dev/null || true

# Clean everything (vendored sources + build artifacts + rocq install)
# After this, run `make setup` to re-populate
clean-all: clean
	rm -rf duniverse/ vendor/ _rocq_prefix/
	@# Remove the symlink created for rocq .vo compilation
	@LINK_DIR="$$(dirname "$$(pwd)")/install/default/lib/rocq-runtime"; \
	 if [ -L "$$LINK_DIR" ]; then rm -f "$$LINK_DIR"; echo "Removed $$LINK_DIR symlink"; fi
