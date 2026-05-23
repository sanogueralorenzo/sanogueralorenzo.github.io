## Intro

**Site** is a custom Eleventy personal website with a sparse portfolio homepage, profile links, and a minimal posts section.

The website follows the visitor's system light or dark mode preference.
The profile portrait keeps a black shirt in light mode and switches to a white shirt in dark mode.

The `/unmade/` section is a scrollable archive of things that almost existed.
It uses Markdown entries in `site/src/unmade/entries` and the `unmade-post.njk` layout for full case pages.

## Quickstart

```shell
npm install
npm run dev
```

## Reference

- Build: `npm run build`
- Config: `site/.eleventy.js`
- Site data and homepage content: `site/src/_data/site.js`
- Layouts: `site/src/_includes`
- Posts: `site/src/posts`
- Unmade archive: `site/src/unmade`
- Assets: `site/src/assets`
- Static files: `site/src/static`
- Favicons and social share image: `site/src/static`
- Output: `site/_site`
