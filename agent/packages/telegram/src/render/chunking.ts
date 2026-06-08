// Chunking for service-rendered text. This is custom to pi-chat.

export function chunkText(text: string, limit: number): string[] {
	if (text.length <= limit) return [text];
	const normalized = text.replace(/\r\n/g, "\n");
	const paragraphs = normalized.split(/\n\n+/);
	const chunks: string[] = [];
	let current = "";

	const pushCurrent = () => {
		if (current.trim().length > 0) chunks.push(current);
		current = "";
	};

	const splitLongBlock = (block: string): string[] => {
		if (block.length <= limit) return [block];
		const lines = block.split("\n");
		const lineChunks: string[] = [];
		let lineCurrent = "";
		for (const line of lines) {
			const candidate = lineCurrent.length === 0 ? line : `${lineCurrent}\n${line}`;
			if (candidate.length <= limit) {
				lineCurrent = candidate;
				continue;
			}
			if (lineCurrent.length > 0) {
				lineChunks.push(lineCurrent);
				lineCurrent = "";
			}
			if (line.length <= limit) {
				lineCurrent = line;
				continue;
			}
			let remaining = line;
			while (remaining.length > limit) {
				let splitAt = remaining.lastIndexOf(" ", limit);
				if (splitAt < Math.floor(limit * 0.6)) splitAt = limit;
				lineChunks.push(remaining.slice(0, splitAt));
				remaining = remaining.slice(splitAt).trimStart();
			}
			lineCurrent = remaining;
		}
		if (lineCurrent.length > 0) lineChunks.push(lineCurrent);
		return lineChunks;
	};

	for (const paragraph of paragraphs) {
		if (!paragraph) continue;
		for (const part of splitLongBlock(paragraph)) {
			const candidate = current.length === 0 ? part : `${current}\n\n${part}`;
			if (candidate.length <= limit) current = candidate;
			else {
				pushCurrent();
				current = part;
			}
		}
	}
	pushCurrent();
	return chunks.length > 0 ? chunks : [normalized.slice(0, limit)];
}
