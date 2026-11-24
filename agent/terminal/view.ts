import { Editor, Markdown, ScrollView, VStack, stripTerminalSequences, truncateToWidth, visibleWidth, wrapTextWithAnsi,
  type MarkdownTheme, type TuiAltScreen, type TuiMouseEvent } from "@earendil-works/pi-tui";

const style = (open: number, close = 39) => (text: string) => `\x1b[${open}m${text}\x1b[${close}m`;
export const bold = style(1, 22);
export const dim = style(2, 22);
export const yellow = style(33);
const cyan = style(36);
const underline = style(4, 24);

const markdownTheme: MarkdownTheme = {
  heading: bold, link: cyan, linkUrl: dim, code: cyan, codeBlock: cyan, codeBlockBorder: dim,
  quote: dim, quoteBorder: dim, hr: dim, listBullet: cyan, bold, italic: style(3, 23),
  strikethrough: style(9, 29), underline,
};

export function clean(text: string) {
  return stripTerminalSequences(text).replace(/\r\n?/g, "\n").replaceAll("\t", "    ")
    .replace(/[\x00-\x09\x0b-\x1f\x7f-\x9f]/g, "");
}

export function compact(text: string) {
  return clean(text).replace(/\s+/g, " ").trim();
}

export function quotePreview(text: string) {
  return dim(`> ${truncateToWidth(compact(text), 72, "…")}`);
}

export type Button = { id: string; label: string; run: () => void; focused?: boolean };
type Line = string | Button[];

export class Panel {
  lines: Line[] = [];
  private hits = new Map<number, { start: number; end: number; run: () => void }[]>();

  render(width: number) {
    this.hits.clear();
    const output: string[] = [];
    for (const line of this.lines) {
      if (typeof line === "string") {
        output.push(truncateToWidth(line, width));
        continue;
      }
      let text = "";
      let x = 0;
      let hits: { start: number; end: number; run: () => void }[] = [];
      const flush = () => {
        this.hits.set(output.length, hits);
        output.push(text);
        text = "";
        x = 0;
        hits = [];
      };
      for (const button of line) {
        const label = truncateToWidth(`[${button.focused ? "› " : ""}${button.label}]`, width);
        const length = visibleWidth(label);
        if (x && x + 2 + length > width) flush();
        if (x) { text += "  "; x += 2; }
        hits.push({ start: x, end: x + length, run: button.run });
        text += (button.focused ? bold : cyan)(label);
        x += length;
      }
      if (text) flush();
    }
    return output;
  }

  handleMouse(event: TuiMouseEvent) {
    if (event.type !== "click" || event.button !== "left") return;
    const hit = this.hits.get(event.y)?.find(item => event.x >= item.start && event.x < item.end);
    if (!hit) return;
    hit.run();
    return { handled: true };
  }

  invalidate() { this.hits.clear(); }
}

type Block = {
  id?: string;
  header?: string;
  text?: string;
  detail?: string;
  quote?: string;
  user?: boolean;
  markdown?: boolean;
  focused?: boolean;
  select?: () => void;
};

class Transcript {
  blocks: Block[] = [];
  positions = new Map<string, number>();
  private hits: (() => void)[] = [];
  private markdown = new Map<string, Markdown>();

  render(width: number) {
    const lines: string[] = [];
    const markdown = new Map<string, Markdown>();
    const margin = width > 2 ? 2 : 0;
    const contentWidth = width - margin;
    this.positions.clear();
    this.hits = [];
    for (const block of this.blocks) {
      if (block.id) this.positions.set(block.id, lines.length);
      const start = lines.length;
      if (block.header) lines.push(truncateToWidth(block.header, contentWidth, "…"));
      if (block.quote) lines.push(truncateToWidth(quotePreview(block.quote), contentWidth, "…"));
      if (block.text) {
        const text = clean(block.text);
        if (block.markdown && block.id) {
          const content = this.markdown.get(block.id) ?? new Markdown(text, 0, 0, markdownTheme);
          content.setText(text);
          markdown.set(block.id, content);
          lines.push(...content.render(contentWidth));
        } else {
          const bar = block.user && contentWidth > 2 ? dim("│ ") : "";
          lines.push(...wrapTextWithAnsi(text, contentWidth - visibleWidth(bar)).map(line => bar + line));
        }
      }
      if (block.detail) lines.push(dim(truncateToWidth(compact(block.detail), contentWidth, "…")));
      for (let index = start; index < lines.length; index++) {
        if (margin) lines[index] = (block.focused && index === start ? bold("› ") : "  ") + lines[index];
        if (block.select) this.hits[index] = block.select;
      }
      lines.push("");
    }
    this.markdown = markdown;
    return lines;
  }

  handleMouse(event: TuiMouseEvent) {
    if (event.type !== "click" || event.button !== "left") return;
    const select = this.hits[event.y];
    if (!select) return;
    select();
    return { handled: true };
  }

  invalidate() { this.markdown.clear(); }
}

export function terminalView(tui: TuiAltScreen, compose: () => void) {
  const top = new Panel();
  const footer = new Panel();
  const transcript = new Transcript();
  const scroll = new ScrollView(transcript, { primary: true, follow: "end" });
  const editor = new class extends Editor {
    handleMouse(event: TuiMouseEvent) {
      if (event.type === "click" && event.button === "left") compose();
      return super.handleMouse(event);
    }
  }(tui, {
    borderColor: dim,
    selectList: { selectedPrefix: cyan, selectedText: cyan, description: dim, scrollInfo: dim, noMatch: dim },
  }, { paddingX: 1 });
  tui.setLayoutRoot(new VStack([top, { component: scroll, basis: 0, grow: 1 }, footer, editor]));
  return { top, footer, transcript, scroll, editor };
}
