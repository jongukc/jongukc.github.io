# jongukc.github.io

Personal site. Markdown in, static HTML out, built with [pandoc](https://pandoc.org)
and `make`. Nothing else is needed.

## Build and preview

    make              # build the site into build/
    ./serve.sh 4000   # build, serve http://localhost:4000, rebuild site and CV on change
    make clean
    make cv           # typeset cv/ into files/cv-jonguk.pdf (needs TeX Live)

Pushing the `main` branch deploys `build/` to GitHub Pages
(`.github/workflows/pages.yml`).

## Layout

    pages/       Markdown pages. pages/foo.md -> /foo.html, pages/index.md -> /
    posts/       Blog posts. posts/foo.md -> /posts/foo/
    files/       Copied as is to /files/: figures, fonts, favicon, js, PGP key,
                 papers, slides, ...
    cv/          the CV in LaTeX: cv.tex (header, section order), cv.sty (look),
                 one .tex file per section. `make cv` writes files/cv-jonguk.pdf.
    templates/   page.html      the HTML shell around every page
                 post-item.md   one row of the /posts/ list
                 feed.xml, feed-entry.xml   the Atom feed (/feed.xml)
    style.css    stylesheet, served at /style.css (colors at the top)
    Makefile     site title and URL, build rules
    robots.txt, googleb2b385f4260df694.html   copied to the site root

`/posts/`, `/feed.xml` and `/sitemap.xml` are generated from the posts.

## Writing a post

Create `posts/<slug>.md` (the slug becomes the URL) with a YAML header:

    ---
    title: "Post title"
    description: "One sentence, used for the meta description and the feed."
    date: 2026-11-03
    author:             # optional
      - "Jonguk Cheong"
    published: false    # optional: drafts are left out of the build
    ---

Sections start at `##`. Figures live in `files/figs/<slug>/` and are
referenced as `/files/figs/<slug>/name.svg`. This is pandoc Markdown:
fenced code blocks with a language are highlighted, pipe tables, footnotes
and `$...$` math (MathJax) work.

## Publications and talks

They are plain lists in `pages/index.md`, one item per entry, lines ending
with a backslash:

    - **[Title](https://link)**\
      **Jonguk Cheong**, Coauthor, and Coauthor\
      *Venue Name (**ABBR**) 2026* — *Note*\
      [docs](/files/papers/x.pdf){.icon} [desktop_landscape](/files/slides/x.pdf){.icon} [format_quote](/files/bib/x.bib){.icon}

The last line is optional; each link text is a Material Symbols icon name.

## CV

`make cv` runs latexmk on `cv/cv.tex` and copies the result to
`files/cv-jonguk.pdf`, which is committed so the site build and the CI runner
need no TeX. Edit the section files (`education.tex`, `publications.tex`, ...)
and rebuild. Entries use two macros from `cv.sty`:

    \entry{Title}{Dates}{Subtitle}{Details}   education, projects, talks
    \pub{Title}{Authors}{Venue}                publications (\me is your name, bold)
    \note{Text}                                flush-right remark, inside Subtitle

A nested `itemize` after `\entry` adds bullet points under it. `\href` text is
underlined automatically.

## Theme

Colors are the `dalbit-mono` scheme, defined at the top of `style.css` as
`light-dark(<light>, <dark>)` pairs. The header toggle (`files/js/darkMode.js`)
remembers the choice in localStorage; without a choice the OS setting is used.
