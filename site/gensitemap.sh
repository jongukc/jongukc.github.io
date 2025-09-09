#!/bin/bash

declare root="https://TODO"

cat << __HEADER__
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
__HEADER__

find . -type f -iname '*.html' -printf "<url>
    <loc>${root}/%P</loc>
    <lastmod>%TY-%Tm-%Td</lastmod>
</url>\n"

cat << __FOOTER__
</urlset>
__FOOTER__
