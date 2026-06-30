# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a personal academic portfolio/blog built with Jekyll, deployed to GitHub Pages. The site showcases research publications and blog posts.

## Commands

```bash
# Install dependencies
./script/bootstrap

# Run local dev server (http://localhost:4000)
./script/server

# Build static site to _site/
./script/build

# Alternative: Docker development
docker-compose up
```

Note: Changes to `_config.yml` require restarting the server.

## Architecture

**Tech Stack**: Jekyll 3.9.3, Minima theme (remote, custom skin), SASS, Liquid templates

**Layout hierarchy**: `base.html` → `home.html` / `post.html` / `page.html`

**Homepage rendering** (`index.md` → `home` layout):
1. Profile image + `_includes/content/profile.md`
2. Bio section from `_includes/content/bio.md`
3. Publications from `_data/papers.yaml`, with conference metadata resolved via `_data/conf.yaml`, rendered by `_includes/pub.html`

**Publications data model** (`_data/papers.yaml`):
- Each entry has: `title`, `authors`, `conf` (key into `conf.yaml`), `year`, optional `paper`/`slide`/`bibtex` filenames, optional `note`
- Author matching: the site author name (`site.author.name`) is auto-bolded in author lists
- Paper/slide/bib files live in `/papers/`, `/slides/`, `/bib/` respectively

**Styles**: Custom Minima skin (`minima.skin: custom` in `_config.yml`). SASS entry point is `_sass/main.scss`, which imports `_variables`, `_base`, `_layout`, and components (`toggle`, `cursor`, `fonts`). Dark mode toggle in `assets/js/darkMode.js` with localStorage persistence.

## Git Workflow

- `jekyll` branch: Main source, auto-deploys via GitHub Actions on push
- Feature branches merge into `jekyll`
