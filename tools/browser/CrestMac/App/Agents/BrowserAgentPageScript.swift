import Foundation

/// A script Crest runs for an agent in the agent's own world of a page, the
/// same on both engines: reading the page as an outline, finding the element
/// a uid names, filling a field, or looking for text. Each is the body of an
/// async function; its arguments are written into it as JSON.
struct BrowserAgentPageScript {
    // MARK: - Static Variables

    /// What every script shares: the elements the latest outline named, by
    /// uid, which a new document starts empty.
    private static let state = #"""
        const state = (globalThis.__crestAgent ??= { document: null, uids: new Map(), elements: new WeakMap(), next: 1 });
        if (state.document !== document) {
          state.document = document; state.uids = new Map(); state.elements = new WeakMap(); state.next = 1;
        }
        const element = (uid) => {
          const found = state.uids.get(uid)?.deref();
          return found && found.isConnected ? found : null;
        };
        """#

    /// The page as an accessibility outline: each meaningful element's role,
    /// name and state with a uid, and the text between them, within a bound.
    /// A password field's value is never part of it.
    static let snapshot = Self(
        source: state + #"""
            const limit = 60000;
            const lines = [];
            let size = 0;
            let truncated = false;
            const roles = { A: "link", BUTTON: "button", SELECT: "combobox", TEXTAREA: "textbox", IMG: "img", NAV: "navigation",
              MAIN: "main", HEADER: "banner", FOOTER: "contentinfo", ASIDE: "complementary", FORM: "form", TABLE: "table",
              TR: "row", TD: "cell", TH: "columnheader", UL: "list", OL: "list", LI: "listitem", DIALOG: "dialog",
              SUMMARY: "button", DETAILS: "group", OPTION: "option", IFRAME: "iframe", H1: "heading", H2: "heading",
              H3: "heading", H4: "heading", H5: "heading", H6: "heading", PROGRESS: "progressbar" };
            const inputs = { checkbox: "checkbox", radio: "radio", button: "button", submit: "button", reset: "button",
              image: "button", range: "slider", number: "spinbutton", search: "searchbox", file: "button", color: "button" };
            const interactive = new Set(["link", "button", "combobox", "textbox", "searchbox", "checkbox", "radio", "slider",
              "spinbutton", "option", "tab", "menuitem", "menuitemcheckbox", "menuitemradio", "switch", "treeitem"]);
            const landmarks = new Set(["heading", "img", "navigation", "main", "banner", "contentinfo", "complementary",
              "form", "table", "row", "cell", "columnheader", "list", "listitem", "dialog", "group", "iframe", "region",
              "progressbar", "alert", "status", "tablist", "menu", "tree", "grid"]);
            const roleOf = (node) => {
              const explicit = node.getAttribute("role")?.split(" ")[0];
              if (explicit) return explicit;
              if (node.tagName === "INPUT") return inputs[node.type] ?? "textbox";
              if (node.tagName === "A" && !node.hasAttribute("href")) return null;
              if (node.tagName === "SECTION" && (node.hasAttribute("aria-label") || node.hasAttribute("aria-labelledby"))) return "region";
              if (node.isContentEditable && node.parentElement?.isContentEditable !== true) return "textbox";
              return roles[node.tagName] ?? null;
            };
            const clean = (text) => (text ?? "").replace(/\s+/g, " ").trim().slice(0, 200);
            const nameOf = (node, role) => {
              const label = node.getAttribute("aria-label");
              if (label) return clean(label);
              const by = node.getAttribute("aria-labelledby");
              if (by) return clean(by.split(" ").map((id) => document.getElementById(id)?.textContent).join(" "));
              // A label's own words, not those of a control inside it, such as a menu's options.
              const own = (label) => [...label.childNodes].filter((child) => child.nodeType === Node.TEXT_NODE ||
                (child.nodeType === Node.ELEMENT_NODE && !child.matches("input, select, textarea, button"))).map((child) => child.textContent).join(" ");
              if (node.labels?.length) return clean([...node.labels].map(own).join(" "));
              if (node.alt) return clean(node.alt);
              if (["link", "button", "heading", "option", "tab", "menuitem", "cell", "columnheader", "listitem", "treeitem"].includes(role))
                return clean(node.innerText ?? node.textContent);
              return clean(node.title || node.placeholder || "");
            };
            const hidden = (node) => {
              if (node.getAttribute("aria-hidden") === "true" || node.hidden) return true;
              if (node.checkVisibility) return !node.checkVisibility({ checkOpacity: false, checkVisibilityCSS: true });
              const style = getComputedStyle(node);
              return style.display === "none" || style.visibility === "hidden";
            };
            const uidOf = (node) => {
              let uid = state.elements.get(node);
              if (!uid) {
                uid = "e" + state.next++;
                state.elements.set(node, uid);
                state.uids.set(uid, new WeakRef(node));
              }
              return uid;
            };
            const emit = (depth, line) => {
              if (truncated) return;
              size += line.length + depth * 2 + 1;
              if (size > limit) { truncated = true; return; }
              lines.push("  ".repeat(depth) + line);
            };
            const describe = (node, role) => {
              const parts = [`- ${role}`];
              const name = nameOf(node, role);
              if (name) parts.push(JSON.stringify(name));
              parts.push(`[uid=${uidOf(node)}]`);
              if (role === "heading") parts.push(`[level=${node.tagName.slice(1) || node.getAttribute("aria-level") || 2}]`);
              if (node.disabled || node.getAttribute("aria-disabled") === "true") parts.push("[disabled]");
              if (node.checked || node.getAttribute("aria-checked") === "true") parts.push("[checked]");
              if (node.getAttribute("aria-expanded")) parts.push(`[expanded=${node.getAttribute("aria-expanded")}]`);
              if (node.selected || node.getAttribute("aria-selected") === "true") parts.push("[selected]");
              if (node === document.activeElement) parts.push("[focused]");
              if (node.tagName === "A" && node.href) parts.push(`[href=${node.href.slice(0, 300)}]`);
              if (node.tagName === "INPUT" && node.type === "password") parts.push("[password]");
              else if ("value" in node && ["textbox", "searchbox", "combobox", "spinbutton", "slider"].includes(role) && node.value)
                parts.push(`[value=${JSON.stringify(String(node.value).slice(0, 200))}]`);
              return parts.join(" ");
            };
            const walk = (node, depth) => {
              for (const child of node.childNodes) {
                if (truncated) return;
                if (child.nodeType === Node.TEXT_NODE) {
                  const text = clean(child.textContent);
                  if (text) emit(depth, `- text ${JSON.stringify(text)}`);
                  continue;
                }
                if (child.nodeType !== Node.ELEMENT_NODE) continue;
                if (["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "SVG", "HEAD", "META", "LINK"].includes(child.tagName.toUpperCase())) continue;
                if (hidden(child)) continue;
                const role = roleOf(child);
                if (role && (interactive.has(role) || landmarks.has(role))) {
                  emit(depth, describe(child, role));
                  // A control's own text is its name; its children add nothing.
                  if (!interactive.has(role) || role === "listitem") walk(child, depth + 1);
                  if (child.shadowRoot) walk(child.shadowRoot, depth + 1);
                } else {
                  walk(child, depth);
                  if (child.shadowRoot) walk(child.shadowRoot, depth);
                }
              }
            };
            walk(document.body ?? document.documentElement, 0);
            return { url: location.href, title: document.title, outline: lines.join("\n"), truncated };
            """#)

    // MARK: - Variables

    let source: String

    // MARK: - Actions - Elements

    /// Scrolls the element `uid` names into view and answers where it is in
    /// the viewport, in CSS pixels, with its role and name; or an error.
    static func locate(_ uid: String) -> Self {
        Self(
            source: state + """
                const target = element(\(json(uid)));
                if (!target) return { error: "unknown" };
                target.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
                const box = target.getBoundingClientRect();
                return { x: box.left + box.width / 2, y: box.top + box.height / 2, left: box.left, top: box.top,
                  width: box.width, height: box.height, viewportWidth: innerWidth, viewportHeight: innerHeight,
                  tag: target.tagName.toLowerCase(), editable: target.isContentEditable || ["INPUT", "TEXTAREA"].includes(target.tagName),
                  menu: target.tagName === "SELECT" };
                """)
    }

    /// Readies the element `uid` names for new text: focuses it and selects
    /// what it holds, so typing replaces it; or chooses the menu option whose
    /// label or value is `value`.
    static func prepareFill(_ uid: String, value: String) -> Self {
        Self(
            source: state + """
                const target = element(\(json(uid)));
                if (!target) return { error: "unknown" };
                const value = \(json(value));
                if (target.tagName === "SELECT") {
                  const option = [...target.options].find((item) => item.label === value || item.value === value || item.text.trim() === value);
                  if (!option) return { error: "option" };
                  target.value = option.value;
                  target.dispatchEvent(new Event("input", { bubbles: true }));
                  target.dispatchEvent(new Event("change", { bubbles: true }));
                  return { chosen: option.label || option.text };
                }
                if (!(target.isContentEditable || ["INPUT", "TEXTAREA"].includes(target.tagName))) return { error: "editable" };
                target.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
                target.focus();
                if (target.isContentEditable) {
                  const range = document.createRange();
                  range.selectNodeContents(target);
                  const selection = getSelection();
                  selection.removeAllRanges();
                  selection.addRange(range);
                  if (!value) document.execCommand("delete");
                } else {
                  target.select?.();
                  if (!value) {
                    const prototype = target.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
                    Object.getOwnPropertyDescriptor(prototype, "value").set.call(target, "");
                    target.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "deleteContentBackward" }));
                  }
                }
                return { ready: true };
                """)
    }

    /// The page's readable text as Markdown, within `limit` characters:
    /// headings, paragraphs, list items, quotes, code and links, leaving out
    /// what the page hides and every form field's value, a password's above
    /// all.
    static func readText(limit: Int) -> Self {
        Self(
            source: """
                const limit = \(limit);
                const skipped = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "SVG", "CANVAS", "IFRAME", "INPUT",
                  "TEXTAREA", "SELECT", "OPTION"]);
                const blocks = new Set(["P", "DIV", "SECTION", "ARTICLE", "MAIN", "HEADER", "FOOTER", "ASIDE", "NAV",
                  "FIGURE", "FIGCAPTION", "TABLE", "TR", "UL", "OL", "DL", "DT", "DD", "FORM", "FIELDSET", "DETAILS", "SUMMARY"]);
                const out = [];
                let size = 0;
                let truncated = false;
                const push = (text) => {
                  if (truncated) return;
                  if (size + text.length > limit) { out.push(text.slice(0, limit - size)); truncated = true; size = limit; return; }
                  out.push(text); size += text.length;
                };
                const hidden = (node) => {
                  if (node.hidden || node.getAttribute("aria-hidden") === "true") return true;
                  if (!node.checkVisibility) return false;
                  // A display: contents wrapper has no box of its own, so only the visibility it
                  // passes down, its own or an ancestor's, hides what it holds.
                  const style = getComputedStyle(node);
                  if (style.display === "contents") return style.visibility !== "visible";
                  return !node.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true, opacityProperty: true,
                    visibilityProperty: true });
                };
                const inline = (node) => {
                  if (node.nodeType === Node.TEXT_NODE) return node.textContent.replace(/\\s+/g, " ");
                  if (node.nodeType !== Node.ELEMENT_NODE || skipped.has(node.tagName) || hidden(node)) return "";
                  const text = [...node.childNodes].map(inline).join("");
                  if (node.tagName === "A" && node.href && text.trim()) return `[${text.trim()}](${node.href})`;
                  if (node.tagName === "IMG") return node.alt ? `![${node.alt}]` : "";
                  if (node.tagName === "CODE") return text ? "`" + text + "`" : "";
                  if (node.tagName === "BR") return "\\n";
                  if (node.tagName === "STRONG" || node.tagName === "B") return text.trim() ? `**${text.trim()}**` : text;
                  return text;
                };
                const walk = (node, depth) => {
                  if (truncated || node.nodeType !== Node.ELEMENT_NODE || skipped.has(node.tagName) || hidden(node)) return;
                  const tag = node.tagName;
                  const heading = /^H([1-6])$/.exec(tag);
                  if (heading) { const text = inline(node).trim(); if (text) push("#".repeat(+heading[1]) + " " + text + "\\n\\n"); return; }
                  if (tag === "LI") {
                    // A nested list follows its item, indented, rather than running into its text.
                    const own = [...node.childNodes].filter((child) => !["UL", "OL"].includes(child.tagName)).map(inline).join("").trim();
                    if (own) push("  ".repeat(Math.max(depth, 0)) + "- " + own + "\\n");
                    for (const child of node.children) if (["UL", "OL"].includes(child.tagName)) walk(child, depth);
                    return;
                  }
                  if (tag === "PRE") { push("```\\n" + node.innerText + "\\n```\\n\\n"); return; }
                  if (tag === "BLOCKQUOTE") { const text = inline(node).trim(); if (text) push("> " + text + "\\n\\n"); return; }
                  if (tag === "UL" || tag === "OL") { for (const child of node.children) walk(child, depth + 1); push("\\n"); return; }
                  const hasBlocks = [...node.children].some((child) => blocks.has(child.tagName) || /^H[1-6]$/.test(child.tagName)
                    || ["LI", "PRE", "BLOCKQUOTE", "UL", "OL"].includes(child.tagName));
                  if (!hasBlocks) { const text = inline(node).trim(); if (text) push(text + "\\n\\n"); return; }
                  for (const child of node.childNodes) {
                    if (child.nodeType === Node.TEXT_NODE) { const text = child.textContent.trim(); if (text) push(text + "\\n\\n"); }
                    else walk(child, depth);
                  }
                };
                if (document.body) walk(document.body, -1);
                return { url: location.href, title: document.title, text: out.join("").replace(/\\n{3,}/g, "\\n\\n").trim(), truncated };
                """)
    }

    /// Whether the page shows `text` now, or, without text, whether it has
    /// finished loading.
    static func shows(_ text: String?) -> Self {
        Self(
            source: """
                const text = \(json(text));
                if (text === null) return document.readyState === "complete";
                return (document.body?.innerText ?? "").includes(text);
                """)
    }

    private static func json(_ value: String?) -> String {
        guard let value else { return "null" }
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
