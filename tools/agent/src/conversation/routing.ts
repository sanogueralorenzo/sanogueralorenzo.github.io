export function maySwitchContext(text: string): boolean {
  return /\b(?:open|switch|move|go|jump|change|checkout|resume|return|back|pick up|continue)\b.{0,100}\b(?:project|repo(?:sitory)?|folder|directory|conversation|session|thread|chat)\b|\b(?:project|repo(?:sitory)?|folder|directory|conversation|session|thread|chat)\b.{0,100}\b(?:open|switch|resume|continue|return)\b|\b(?:back to|resume|pick up)\b/i.test(text);
}

export function requiresHandoff(text: string): boolean {
  return /^\s*(?:(?:please|can you|could you|would you|i want to|i'd like to)\s+)?(?:go to|switch to|move to|change to|return to|take me back to|resume|checkout)\b/i.test(text)
    || /^\s*(?:(?:please|can you|could you|would you)\s+)?open\s+(?:(?:this|the|a|my)\s+)?(?:project|repo(?:sitory)?|folder|directory|conversation|session|thread|chat)\b/i.test(text);
}
