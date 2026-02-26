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

**Tech Stack**: Jekyll 3.9.3, Minima theme (remote), SASS, Liquid templates

**Key Directories**:

- `_posts/` - Blog posts in Markdown
- `_data/papers.yaml` - Publications data (rendered by `_includes/pub.html`)
- `_layouts/` - Page templates (base.html → home.html/post.html/page.html)
- `_includes/` - Reusable components (bio.md, profile.md, pub.html, header/footer)
- `_sass/custom/` - Custom styles (dark mode toggle, fonts)
- `assets/js/darkMode.js` - Dark mode toggle with localStorage persistence

**Content Flow**:

1. Homepage (`index.md`) uses `home` layout
2. `home.html` includes bio, profile, and publications sections
3. Publications render from `_data/papers.yaml` via `_includes/pub.html`

## Git Workflow

- `jekyll` branch: Main source, auto-deploys via GitHub Actions
- Feature branches (like `posts`) merge into `jekyll`
