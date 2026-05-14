.PHONY: help build-all clean refresh-patches

require-upstream:
	@if [ -z "$(UPSTREAM)" ]; then \
	  echo "UPSTREAM=<tag> is required, e.g. make build-all UPSTREAM=v1.4.0" >&2; \
	  exit 2; \
	fi

help:
	@echo "Targets:"
	@echo "  build-all UPSTREAM=<tag>   build every supported architecture locally"
	@echo "  clean                      remove out/"
	@echo "  refresh-patches DIR=<path> regenerate patches/ from a working clone"

build-all: require-upstream
	scripts/build.sh $(UPSTREAM) linux amd64
	scripts/build.sh $(UPSTREAM) linux arm64
	scripts/build.sh $(UPSTREAM) linux arm     7
	scripts/build.sh $(UPSTREAM) linux arm     6
	scripts/build.sh $(UPSTREAM) linux mipsle  softfloat
	scripts/build.sh $(UPSTREAM) linux mips    softfloat
	scripts/build.sh $(UPSTREAM) linux riscv64

clean:
	rm -rf out/

# Regenerate the patch series from a working clone where you've made changes.
# DIR must point to a clone of fosrl/newt with your edits committed on top of
# the upstream base; the script picks the first commit not in upstream/HEAD.
refresh-patches:
	@if [ -z "$(DIR)" ]; then \
	  echo "DIR=<path to your newt working clone> is required" >&2; \
	  exit 2; \
	fi
	rm -f patches/*.patch
	cd $(DIR) && \
	  BASE=$$(git merge-base HEAD origin/main) && \
	  git format-patch "$$BASE..HEAD" -o $(CURDIR)/patches
	@echo "Refreshed patches:"
	@ls patches/
