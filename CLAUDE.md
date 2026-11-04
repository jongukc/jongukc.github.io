# CLAUDE.md

Personal academic site: Markdown built into static HTML by pandoc and GNU make,
deployed to GitHub Pages by `.github/workflows/pages.yml` on pushes to the
`pandoc` branch. No Ruby, Jekyll or Docker. The only tools are pandoc (3.1.3
locally and on the CI runner) and make.

## Commands

    make              # build into build/ (gitignored)
    ./serve.sh 4000   # build, serve on http://localhost:4000, rebuild on change
    make clean

## Layout

- `pages/*.md` -> `/<name>.html` (`index.md` -> `/`). `404.md` is the 404 page.
- `posts/<slug>.md` -> `/posts/<slug>/`. Front matter: `title`, `description`,
  `date` (ISO, used for sorting and display), optional `author` list,
  `published: false` to skip a draft.
- `files/` is copied verbatim to `/files/` (figures, fonts, favicon, js, PGP key).
- `style.css` -> `/style.css`. `robots.txt` and the Google verification file are
  copied to the root (`ROOT` in the Makefile).
- `templates/page.html` is the single pandoc template (header, nav, post
  header when `date` is set, footer). `post-item.md` renders one row of `/posts/`;
  `feed.xml` + `feed-entry.xml` render the Atom feed.
- The Makefile generates `/posts/`, `/feed.xml` and `/sitemap.xml` from the posts.

## Conventions

- Home page sections (profile, bio, publications, talks) are all in
  `pages/index.md`. Publications and talks are lists inside `::: {.pubs}`
  fenced divs; the first bold line of an item is its title. Icon links use
  `[icon_name](url){.icon}` (Material Symbols).
- The stylesheet is plain CSS. Colors are the dalbit-mono scheme as
  `light-dark()` custom properties at the top of `style.css`; dark mode is
  toggled by setting `color-theme` on `<html>` (`files/js/darkMode.js`).
- Pandoc runs with `implicit_figures` disabled so image alt text is not shown as
  a caption. Syntax highlighting uses pandoc's skylighting classes (`.kw`,
  `.st`, ...), styled in `style.css`.
