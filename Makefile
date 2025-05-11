.EXPORT_ALL_VARIABLES:

ANSIBLE_FORCE_COLOR=true
ANSIBLE_DISPLAY_SKIPPED_HOSTS=false

TEMPLATEFILES=$(wildcard slides/template/*)
.PHONY: dev-server
dev-server:
	@cd slides && bs serve

slides/dist/presentation.html: $(TEMPLATEFILES) slides/presentation.md
	@cd slides && bs export

slides/pdf/presentation.pdf: slides/dist/presentation.html
	@cd slides && decktape -p 1000 dist/presentation.html pdf/presentation.pdf

.PHONY: slides
slides: slides/dist/presentation.html

.PHONY: pdf
pdf: slides/pdf/presentation.pdf

bin/generate: generate.go
	go build -o bin/ generate.go

.PHONY: generate
generate: bin/generate
