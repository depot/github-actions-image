.PHONY: build
build: apply-patch

.PHONY: generate-patch
generate-patch:
	diff -uraN upstream/images/linux generated > depot.patch

.PHONY: apply-patch
apply-patch:
	rm -rf generated
	cp -r upstream/images/linux generated
	patch -d generated -p1 < depot.patch
