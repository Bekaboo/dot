module.exports = {
  names: ["no-nbsp"],
  description: "Use regular spaces instead of non-breaking spaces",
  tags: ["whitespace"],
  parser: "none",
  function: (params, onError) => {
    params.lines.forEach((line, lineIndex) => {
      const endColumn = params.config.ignore_trailing ? line.trimEnd().length : line.length;
      for (const match of line.matchAll(/\u00a0/g)) {
        if (match.index >= endColumn) continue;

        onError({
          lineNumber: lineIndex + 1,
          range: [match.index + 1, 1],
          fixInfo: {
            editColumn: match.index + 1,
            deleteCount: 1,
            insertText: " ",
          },
        });
      }
    });
  },
};
