module.exports = {
  names: ["no-numbered-headings"],
  description: "Headings must not start with numbering",
  tags: ["headings"],
  parser: "none",
  function: (params, onError) => {
    params.lines.forEach((line, index) => {
      const match = line.match(/^(#{1,6}\s+)\d+\.\s+/);
      if (!match) return;

      const prefixLength = match[1].length;
      onError({
        lineNumber: index + 1,
        detail: "Remove the numeric prefix from the heading",
        context: line,
        range: [prefixLength + 1, match[0].length - prefixLength],
        fixInfo: {
          editColumn: prefixLength + 1,
          deleteCount: match[0].length - prefixLength,
        },
      });
    });
  },
};
