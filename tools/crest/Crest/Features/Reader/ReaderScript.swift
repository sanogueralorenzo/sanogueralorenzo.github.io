enum BrowserReaderModeJavaScriptBridge {
    static let source = #"""
        const makeBridge = () => {
          const hostIdentifier = "crest-reader-mode-host";
          let host = null;
          let shadow = null;
          let articleRoot = null;
          let savedRootOverflow = null;
          let savedRootOverflowPriority = null;
          let bodyHadAriaHidden = false;
          let savedBodyAriaHidden = null;
          let savedBodyInert = false;

          const normalizedText = (element) =>
            (element?.innerText || element?.textContent || "")
              .replace(/\s+/g, " ")
              .trim();

          const articleCandidate = () => {
            if (!document.body) return null;
            const preferred = Array.from(document.querySelectorAll(
              "article, main, [role='main'], [itemprop='articleBody']"
            ));
            const candidates = [...new Set([...preferred, document.body])];
            let best = null;
            let bestScore = -Infinity;

            for (const element of candidates) {
              const text = normalizedText(element);
              const paragraphs = Array.from(element.querySelectorAll("p"))
                .filter((paragraph) => normalizedText(paragraph).length >= 40);
              const linkTextLength = Array.from(element.querySelectorAll("a"))
                .reduce((total, link) => total + normalizedText(link).length, 0);
              const hasEnoughContent =
                (text.length >= 500 && paragraphs.length >= 2) ||
                (text.length >= 350 && paragraphs.length >= 3);
              if (!hasEnoughContent) continue;

              const linkDensity = linkTextLength / Math.max(text.length, 1);
              const semanticBonus = element.matches(
                "article, [itemprop='articleBody']"
              ) ? 900 : element.matches("main, [role='main']") ? 450 : 0;
              const score = text.length + paragraphs.length * 120
                + semanticBonus - linkDensity * text.length * 2;
              if (score > bestScore) {
                best = element;
                bestScore = score;
              }
            }
            return best;
          };

          const safeURL = (value, allowedSchemes) => {
            if (!value) return null;
            try {
              const resolved = new URL(value, document.baseURI);
              return allowedSchemes.has(resolved.protocol) ? resolved.href : null;
            } catch (_) {
              return null;
            }
          };

          const sanitize = (source) => {
            const clone = source.cloneNode(true);
            clone.querySelectorAll(
              "script, style, noscript, template, iframe, frame, object, embed, " +
              "form, input, textarea, select, option, button, video, audio, canvas, " +
              "svg, dialog, [contenteditable]"
            ).forEach((element) => element.remove());

            const allowedTags = new Set([
              "ARTICLE", "SECTION", "DIV", "HEADER", "FOOTER", "ASIDE",
              "H1", "H2", "H3", "H4", "H5", "H6", "P", "BR", "HR",
              "BLOCKQUOTE", "PRE", "CODE", "KBD", "SAMP", "STRONG", "B",
              "EM", "I", "U", "S", "MARK", "SMALL", "SUB", "SUP", "SPAN",
              "UL", "OL", "LI", "DL", "DT", "DD", "FIGURE", "FIGCAPTION",
              "IMG", "A", "TIME", "TABLE", "THEAD", "TBODY", "TFOOT", "TR",
              "TH", "TD", "CAPTION"
            ]);
            const elements = Array.from(clone.querySelectorAll("*")).reverse();
            for (const element of elements) {
              if (!allowedTags.has(element.tagName)) {
                element.replaceWith(...element.childNodes);
                continue;
              }

              const href = element.tagName === "A"
                ? safeURL(element.getAttribute("href"), new Set(["http:", "https:", "mailto:", "tel:"]))
                : null;
              const src = element.tagName === "IMG"
                ? safeURL(element.getAttribute("src"), new Set(["http:", "https:", "data:", "blob:"]))
                : null;
              const alt = element.tagName === "IMG" ? element.getAttribute("alt") : null;
              const dateTime = element.tagName === "TIME" ? element.getAttribute("datetime") : null;
              const colSpan = ["TH", "TD"].includes(element.tagName)
                ? element.getAttribute("colspan") : null;
              const rowSpan = ["TH", "TD"].includes(element.tagName)
                ? element.getAttribute("rowspan") : null;
              for (const attribute of Array.from(element.attributes)) {
                element.removeAttribute(attribute.name);
              }
              if (href) {
                element.setAttribute("href", href);
                element.setAttribute("rel", "noopener");
              } else if (element.tagName === "A") {
                element.removeAttribute("href");
              }
              if (src) {
                element.setAttribute("src", src);
                element.setAttribute("loading", "lazy");
              } else if (element.tagName === "IMG") {
                element.remove();
                continue;
              }
              if (alt) element.setAttribute("alt", alt);
              if (dateTime) element.setAttribute("datetime", dateTime);
              if (colSpan) element.setAttribute("colspan", colSpan);
              if (rowSpan) element.setAttribute("rowspan", rowSpan);
            }
            return clone;
          };

          const articleTitle = (candidate) => {
            const heading = candidate.querySelector("h1") || document.querySelector("h1");
            const value = normalizedText(heading) || document.title.trim();
            return value || location.hostname;
          };

          const articleByline = (candidate) => {
            const element = candidate.querySelector(
              "[rel='author'], [itemprop='author'], .byline, .author"
            );
            const value = normalizedText(element);
            return value.length <= 160 ? value : "";
          };

          const availability = () => articleCandidate() !== null;

          const activate = () => {
            if (host?.isConnected) return true;
            const candidate = articleCandidate();
            if (!candidate || !document.documentElement) return false;

            const title = articleTitle(candidate);
            const byline = articleByline(candidate);
            const content = sanitize(candidate);
            const duplicateTitle = content.querySelector("h1");
            if (duplicateTitle && normalizedText(duplicateTitle) === title) {
              duplicateTitle.remove();
            }

            host = document.createElement("div");
            host.id = hostIdentifier;
            host.setAttribute("data-crest-reader-mode", "active");
            const hostStyles = {
              position: "fixed", inset: "0", zIndex: "2147483647",
              overflow: "auto", background: "Canvas", color: "CanvasText",
              colorScheme: "light dark", contain: "strict"
            };
            for (const [property, value] of Object.entries(hostStyles)) {
              const cssName = property.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);
              host.style.setProperty(cssName, value, "important");
            }

            shadow = host.attachShadow({ mode: "closed" });
            const style = document.createElement("style");
            style.textContent = `
              :host { color-scheme: light dark; }
              * { box-sizing: border-box; }
              .surface {
                min-height: 100%; padding: clamp(36px, 7vw, 96px) 24px 96px;
                background: #fbfaf7; color: #25231f;
                font-family: ui-serif, Georgia, Cambria, "Times New Roman", serif;
                font-size: clamp(18px, 1.1vw + 14px, 23px); line-height: 1.72;
              }
              main { max-width: 70ch; margin: 0 auto; }
              h1 {
                margin: 0 0 16px; color: inherit;
                font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
                font-size: clamp(38px, 5vw, 68px); line-height: 1.04;
                letter-spacing: -0.035em;
              }
              .byline {
                margin: 0 0 40px; color: #6f6a60;
                font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
                font-size: 0.76em; line-height: 1.4;
              }
              .article > :first-child { margin-top: 0; }
              p, ul, ol, blockquote, pre, figure, table { margin: 1.25em 0; }
              h2, h3, h4, h5, h6 {
                margin: 1.8em 0 0.55em; line-height: 1.18;
                font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
              }
              img { display: block; max-width: 100%; height: auto; margin: 1.6em auto; border-radius: 10px; }
              figure { margin-inline: 0; }
              figcaption { color: #6f6a60; font-size: 0.78em; line-height: 1.45; }
              a { color: #315f9a; text-decoration-thickness: 0.08em; text-underline-offset: 0.14em; }
              blockquote { margin-inline: 0; padding-left: 1.1em; border-left: 3px solid #c5bfb4; color: #58534c; }
              pre { overflow: auto; padding: 1em; border-radius: 8px; background: #efede8; font-size: 0.78em; }
              code, kbd, samp { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.86em; }
              table { width: 100%; border-collapse: collapse; font-size: 0.82em; }
              th, td { padding: 0.55em; border: 1px solid #d5d0c7; text-align: start; }
              @media (prefers-color-scheme: dark) {
                .surface { background: #1d1d1c; color: #e9e6df; }
                .byline, figcaption { color: #aaa49a; }
                a { color: #8bbcff; }
                blockquote { border-color: #656057; color: #c8c3ba; }
                pre { background: #2a2927; }
                th, td { border-color: #4c4944; }
              }
              @media (max-width: 600px) {
                .surface { padding: 32px 20px 72px; font-size: 19px; }
                h1 { font-size: 38px; }
              }
            `;
            const surface = document.createElement("div");
            surface.className = "surface";
            const main = document.createElement("main");
            main.setAttribute("role", "main");
            main.setAttribute("aria-label", readerModeLabel);
            const heading = document.createElement("h1");
            heading.textContent = title;
            main.appendChild(heading);
            if (byline) {
              const author = document.createElement("p");
              author.className = "byline";
              author.textContent = byline;
              main.appendChild(author);
            }
            articleRoot = document.createElement("div");
            articleRoot.className = "article";
            articleRoot.appendChild(content);
            main.appendChild(articleRoot);
            surface.appendChild(main);
            shadow.append(style, surface);

            savedRootOverflow = document.documentElement.style.getPropertyValue("overflow");
            savedRootOverflowPriority = document.documentElement.style.getPropertyPriority("overflow");
            bodyHadAriaHidden = document.body.hasAttribute("aria-hidden");
            savedBodyAriaHidden = document.body.getAttribute("aria-hidden");
            savedBodyInert = document.body.inert;
            document.body.setAttribute("aria-hidden", "true");
            document.body.inert = true;
            document.documentElement.style.setProperty("overflow", "hidden", "important");
            document.documentElement.appendChild(host);
            host.scrollTop = 0;
            return true;
          };

          const deactivate = () => {
            host?.remove();
            host = null;
            shadow = null;
            articleRoot = null;
            if (savedRootOverflow === null || savedRootOverflow === "") {
              document.documentElement?.style.removeProperty("overflow");
            } else {
              document.documentElement?.style.setProperty(
                "overflow", savedRootOverflow, savedRootOverflowPriority || ""
              );
            }
            savedRootOverflow = null;
            savedRootOverflowPriority = null;
            if (document.body) {
              if (bodyHadAriaHidden) {
                document.body.setAttribute("aria-hidden", savedBodyAriaHidden || "");
              } else {
                document.body.removeAttribute("aria-hidden");
              }
              document.body.inert = savedBodyInert;
            }
            bodyHadAriaHidden = false;
            savedBodyAriaHidden = null;
            savedBodyInert = false;
            return true;
          };

          const snapshot = () => ({
            isActive: Boolean(host?.isConnected && articleRoot),
            title: shadow?.querySelector("h1")?.textContent || "",
            text: articleRoot?.textContent?.replace(/\s+/g, " ").trim() || "",
            unsafeElementCount: articleRoot?.querySelectorAll(
              "script, style, iframe, frame, object, embed, form, input, textarea, " +
              "select, button, video, audio, canvas, svg, [onclick], [onload]"
            ).length || 0
          });

          return { document, availability, activate, deactivate, snapshot };
        };

        let bridge = globalThis.__crestReaderModeBridge;
        if (!bridge || bridge.document !== document) {
          globalThis.__crestReaderModeBridge = makeBridge();
        }
        const current = globalThis.__crestReaderModeBridge;
        switch (action) {
          case "availability": return current.availability();
          case "activate": return current.activate();
          case "deactivate": return current.deactivate();
          case "snapshot": return current.snapshot();
          default: return null;
        }
        """#
}
