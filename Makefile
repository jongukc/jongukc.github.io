# Builds the site into build/ with pandoc. See README.md for the layout.

SITE_TITLE = Jonguk Cheong
SITE_URL   = https://jongukc.github.io

BUILD    = build
TEMPLATE = templates/page.html
# Footer date: the last commit, or today outside a git checkout.
UPDATED := $(shell git log -1 --format=%cs 2>/dev/null || date +%F)
NOW     := $(shell date -u +%FT%TZ)

# ---- Sources ----------------------------------------------------------------
PAGES := $(wildcard pages/*.md)
# Posts without `published: false`, newest first by the `date:` front-matter field.
POSTS := $(shell for f in $$(grep -L '^published: *false' posts/*.md); do \
             echo "$$(grep -m1 '^date:' $$f) $$f"; done | sort -r | awk '{print $$NF}')
FILES := $(shell find files -type f)
ROOT  := style.css robots.txt googleb2b385f4260df694.html

# ---- Outputs ----------------------------------------------------------------
PAGE_OUT := $(patsubst pages/%.md,$(BUILD)/%.html,$(PAGES))
POST_OUT := $(patsubst posts/%.md,$(BUILD)/posts/%/index.html,$(POSTS))
COPY_OUT := $(addprefix $(BUILD)/,$(FILES) $(ROOT))

# implicit_figures is off so an image's alt text stays alt text (not a caption).
PANDOC = pandoc --from markdown-implicit_figures --to html5 --mathjax --wrap=none \
         --template $(TEMPLATE) \
         -V site-title="$(SITE_TITLE)" -V site-url=$(SITE_URL) -V updated=$(UPDATED)

.PHONY: all cv clean
.DELETE_ON_ERROR:

all: $(PAGE_OUT) $(POST_OUT) $(COPY_OUT) $(BUILD)/posts/index.html $(BUILD)/feed.xml $(BUILD)/sitemap.xml

# pages/foo.md -> /foo.html   (pages/index.md -> /)
$(BUILD)/%.html: pages/%.md $(TEMPLATE)
	@mkdir -p $(@D)
	$(PANDOC) -V url=/$(subst index.html,,$(@F)) $< -o $@

# posts/foo.md -> /posts/foo/
$(BUILD)/posts/%/index.html: posts/%.md $(TEMPLATE)
	@mkdir -p $(@D)
	$(PANDOC) -V url=/posts/$*/ $< -o $@

# files/** and the root files are copied as they are
$(BUILD)/%: %
	@mkdir -p $(@D)
	cp $< $@

# /posts/ : one line per post, rendered through templates/post-item.md
$(BUILD)/posts/index.html: $(POSTS) $(TEMPLATE) templates/post-item.md
	@mkdir -p $(@D)
	{ echo '# Posts'; echo; echo '::: {.post-list}'; \
	  for p in $(POSTS); do \
	    pandoc $$p --to markdown --wrap=none --template templates/post-item.md \
	      -V url=/posts/$$(basename $$p .md)/; \
	  done; echo ':::'; } | $(PANDOC) -M title=Posts -V url=/posts/ -o $@

# Atom feed: each post through templates/feed-entry.xml, wrapped by templates/feed.xml
$(BUILD)/feed.xml: $(POSTS) templates/feed.xml templates/feed-entry.xml
	@mkdir -p $(@D)
	{ echo '```{=html}'; \
	  for p in $(POSTS); do \
	    pandoc $$p --to html5 --template templates/feed-entry.xml \
	      -V site-url=$(SITE_URL) -V url=/posts/$$(basename $$p .md)/; \
	  done; echo '```'; } | pandoc --to html5 --template templates/feed.xml \
	    -M title="$(SITE_TITLE)" -V site-url=$(SITE_URL) -V now=$(NOW) -o $@

$(BUILD)/sitemap.xml: $(POSTS)
	@mkdir -p $(@D)
	{ echo '<?xml version="1.0" encoding="utf-8"?>'; \
	  echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'; \
	  for u in / /posts/ $(patsubst posts/%.md,/posts/%/,$(POSTS)); do \
	    echo "  <url><loc>$(SITE_URL)$$u</loc></url>"; \
	  done; echo '</urlset>'; } > $@

# ---- CV ----------------------------------------------------------------------
# `make cv` typesets cv/cv.tex into files/cv-jonguk.pdf (needs TeX Live: pdflatex
# and latexmk). LaTeX scratch files go to a temporary directory, so nothing else
# is left behind (on an error, the message is printed first). The PDF is
# committed: the site build and CI need no TeX.
CV_PDF := files/cv-jonguk.pdf

cv: $(CV_PDF)

$(CV_PDF): $(wildcard cv/*)
	tmp=$$(mktemp -d) && trap 'rm -r "$$tmp"' EXIT && \
	  if latexmk -pdf -silent -cd -outdir="$$tmp" cv/cv.tex; then cp "$$tmp"/cv.pdf $@; \
	  else grep -A2 '^!' "$$tmp"/cv.log; exit 1; fi

clean:
	rm -rf $(BUILD)
