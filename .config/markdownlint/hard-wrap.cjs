const protectedTokenTypes = new Set([
  "link", "image", "autolink", "literalAutolink", "codeText", "htmlText",
  "characterEscape", "characterReference",
]);
const linePrefixPattern = /^(?:[ \t]*>[ \t]?)*[ \t]*(?:(?:[-+*]|\d+[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)?/;
const hardBreakPattern = /(?: {2,}|\\)$/;
const blockStartPattern = /^(?:#{1,6}(?:\s|$)|>|[-+*]\s|\d+[.)]\s|`{3,}|~{3,}|(?:[-*_][ \t]*){3,}$|=+[ \t]*$)/;

function* walkTokens(tokens) {
  for (const token of tokens) {
    yield token;
    yield* walkTokens(token.children);
  }
}

function createSource(lines) {
  let offset = 0;
  const starts = lines.map((line) => {
    const start = offset;
    offset += line.length + 1;
    return start;
  });
  return {
    text: lines.join("\n"),
    starts,
    range: (token) => ({
      start: starts[token.startLine - 1] + token.startColumn - 1,
      end: starts[token.endLine - 1] + token.endColumn - 1,
    }),
  };
}

function findParagraphs(tokens) {
  return [...walkTokens(tokens)].filter((token) => token.type === "paragraph");
}

function findWikiLinkRanges(text) {
  // Wiki links are an extension, so the Markdown parser treats them as text.
  return [...text.matchAll(/(?<!\\)\[\[(?:\\[\s\S]|(?!\]\])[\s\S])*\]\]/g)]
    .map((match) => ({ start: match.index, end: match.index + match[0].length }));
}

function collectProtectedRanges(paragraph, source) {
  const range = source.range(paragraph);
  const text = source.text.slice(range.start, range.end);
  const extensionRanges = [
    ...findWikiLinkRanges(text),
    // Preserve the existing support for inline math without parsing its contents.
    ...[...text.matchAll(/(?<!\\)(\${1,2})(?!\$)(?:\\[\s\S]|[^$])*?\1(?!\$)/g)]
      .map((match) => ({ start: match.index, end: match.index + match[0].length })),
  ];
  return [
    ...[...walkTokens(paragraph.children)]
      .filter((token) => protectedTokenTypes.has(token.type))
      .map(source.range),
    ...extensionRanges.map(({ start, end }) => ({
      start: range.start + start,
      end: range.start + end,
    })),
  ];
}

function getLineLayout(text, offset) {
  const prefix = text.match(linePrefixPattern)[0];
  const suffix = text.match(hardBreakPattern)?.[0] ?? "";
  return {
    text,
    offset,
    prefix,
    continuation: prefix.replace(/[^ \t>]/g, " "),
    content: text.slice(prefix.length, text.length - suffix.length),
    suffix,
  };
}

function findSafeBreaks(layout, protectedRanges) {
  return [...layout.content.matchAll(/[ \t]+/g)]
    .map((match) => ({ start: match.index, end: match.index + match[0].length }))
    .filter(({ start, end }) => {
      const absoluteStart = layout.offset + layout.prefix.length + start;
      const absoluteEnd = layout.offset + layout.prefix.length + end;
      if (protectedRanges.some((range) => absoluteStart < range.end && absoluteEnd > range.start)) return false;
      return !blockStartPattern.test(layout.content.slice(end));
    });
}

function wrapLine(layout, breaks, limit) {
  const output = [];
  let start = 0;
  let prefix = layout.prefix;
  let nextBreak = 0;

  while (prefix.length + layout.content.length - start > limit) {
    while (nextBreak < breaks.length && breaks[nextBreak].start <= start) nextBreak += 1;
    if (nextBreak === breaks.length) break;

    // If the next atom exceeds the limit, keep it whole on its own line.
    let chosen = nextBreak;
    while (chosen + 1 < breaks.length && prefix.length + breaks[chosen + 1].start - start <= limit) chosen += 1;
    const boundary = breaks[chosen];
    output.push(prefix + layout.content.slice(start, boundary.start));
    start = boundary.end;
    prefix = layout.continuation;
    nextBreak = chosen + 1;
  }
  output.push(prefix + layout.content.slice(start) + layout.suffix);
  return output.join("\n");
}

function reportFix(lineNumber, original, formatted, limit, onError) {
  onError({
    lineNumber,
    detail: `Expected: ${limit}; Actual: ${original.length}`,
    fixInfo: { editColumn: 1, deleteCount: original.length, insertText: formatted },
  });
}

module.exports = {
  names: ["hard-wrap"],
  description: "Wrap prose at the configured line length",
  tags: ["line_length"],
  parser: "micromark",
  function: (params, onError) => {
    const limit = params.config.line_length ?? 79;
    const source = createSource(params.lines);
    for (const paragraph of findParagraphs(params.parsers.micromark.tokens)) {
      const protectedRanges = collectProtectedRanges(paragraph, source);
      for (let lineNumber = paragraph.startLine; lineNumber <= paragraph.endLine; lineNumber += 1) {
        const original = params.lines[lineNumber - 1];
        if (original.length <= limit) continue;

        const layout = getLineLayout(original, source.starts[lineNumber - 1]);
        const breaks = findSafeBreaks(layout, protectedRanges);
        const formatted = wrapLine(layout, breaks, limit);
        if (formatted === original) continue;

        reportFix(lineNumber, original, formatted, limit, onError);
      }
    }
  },
};
