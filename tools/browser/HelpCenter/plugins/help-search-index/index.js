const fs = require('node:fs/promises');
const path = require('node:path');

function parseFrontMatter(source) {
  const match = source.match(/^---\s*\n([\s\S]*?)\n---\s*\n/);
  if (!match) return {attributes: {}, body: source};

  const attributes = {};
  for (const line of match[1].split('\n')) {
    const separator = line.indexOf(':');
    if (separator === -1) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (value.startsWith('[') && value.endsWith(']')) {
      value = value.slice(1, -1).split(',').map((item) => item.trim().replace(/^['"]|['"]$/g, ''));
    }
    attributes[key] = value;
  }
  return {attributes, body: source.slice(match[0].length)};
}

function plainText(markdown) {
  return markdown
    .replace(/^import .*$/gm, ' ')
    .replace(/^export .*$/gm, ' ')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/<[^>]+>/g, ' ')
    .replace(/[#{>*_~|]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

async function markdownFiles(directory) {
  const entries = await fs.readdir(directory, {withFileTypes: true});
  const files = [];
  for (const entry of entries) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await markdownFiles(absolute));
    if (entry.isFile() && /\.mdx?$/.test(entry.name)) files.push(absolute);
  }
  return files.sort();
}

module.exports = function helpSearchIndex(context) {
  const docsDirectory = path.join(context.siteDir, 'docs');
  return {
    name: 'help-search-index',
    async loadContent() {
      const files = await markdownFiles(docsDirectory);
      return Promise.all(files.map(async (file) => {
        const source = await fs.readFile(file, 'utf8');
        const {attributes, body} = parseFrontMatter(source);
        const relative = path.relative(docsDirectory, file).replace(/\\/g, '/').replace(/\.mdx?$/, '');
        const slug = attributes.slug || `/${relative.replace(/\/index$/, '')}`;
        const normalizedSlug = slug === '/' ? '/' : `/${slug.replace(/^\/+|\/+$/g, '')}/`;
        const text = plainText(body);
        return {
          title: attributes.title || relative.split('/').pop(),
          description: attributes.description || text.slice(0, 180),
          keywords: Array.isArray(attributes.keywords) ? attributes.keywords : [],
          slug: normalizedSlug,
          text,
        };
      }));
    },
    async contentLoaded({content, actions}) {
      actions.setGlobalData(content);
    },
  };
};
