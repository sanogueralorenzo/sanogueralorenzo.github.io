const fs = require('node:fs/promises');
const path = require('node:path');

const textExtensions = new Set(['.css', '.html', '.js', '.json', '.map', '.xml']);

async function filesUnder(directory) {
  const entries = await fs.readdir(directory, {withFileTypes: true});
  const files = [];

  for (const entry of entries) {
    const candidate = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await filesUnder(candidate));
    if (entry.isFile() && textExtensions.has(path.extname(entry.name))) files.push(candidate);
  }

  return files;
}

async function main() {
  const outputDirectory = path.resolve(process.argv[2]);
  const siteDirectory = process.cwd();
  const siteDirectoryPatterns = new Set([
    siteDirectory,
    siteDirectory.replaceAll(path.sep, '/'),
    siteDirectory.replaceAll(path.sep, '\\'),
  ]);

  for (const file of await filesUnder(outputDirectory)) {
    const original = await fs.readFile(file, 'utf8');
    let sanitized = original;

    for (const siteDirectoryPattern of siteDirectoryPatterns) {
      sanitized = sanitized.replaceAll(siteDirectoryPattern, '@site');
    }

    if (sanitized !== original) await fs.writeFile(file, sanitized);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
