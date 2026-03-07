## Intro

**site** contains the static website content, templates, and generation config.

---

## Quickstart

### Run local site server

```shell
hugo server
```

### Build static output

```shell
hugo --minify
```

## Reference

- Theme/module source is declared in `config/_default/config.yaml` and `go.mod`.
- Main directories:
  - `content/`: posts/pages.
  - `layouts/`: template overrides.
  - `assets/` + `static/`: styles and static files.
  - `public/`: generated output.
