const { realpathSync } = require("node:fs");
const { createRequire } = require("node:module");

const cliRequire = createRequire(realpathSync(process.argv[1]));
const markdownlintRequire = createRequire(cliRequire.resolve("markdownlint"));
const displayWidth = markdownlintRequire("string-width").default;

function* findTables(tokens) {
  for (const token of tokens) {
    if (token.type === "table") {
      yield token;
      continue;
    }

    yield* findTables(token.children);
  }
}

function formatRow(cells, widths) {
  return "| " + cells.map((cell, index) =>
    cell + " ".repeat(Math.max(0, widths[index] - displayWidth(cell))),
  ).join(" | ") + " |";
}

module.exports = {
  names: ["aligned-tables"],
  description: "Table column pipes must be visually aligned",
  tags: ["table", "whitespace"],
  parser: "micromark",
  function: (params, onError) => {
    for (const table of findTables(params.parsers.micromark.tokens)) {
      const rows = table.children
        .flatMap((token) => token.children)
        .filter((token) => token.type === "tableRow" || token.type === "tableDelimiterRow")
        .map((token) => {
          const line = params.lines[token.startLine - 1];
          const startIndex = token.startColumn - 1 + token.text.match(/^[ \t]*/)[0].length;
          return {
            lineNumber: token.startLine,
            startIndex,
            text: line.slice(startIndex),
            cells: token.children.map((cell) =>
              cell.children.find((child) => child.type === "tableContent")?.text ?? "",
            ),
            dividers: token.children
              .flatMap((cell) => cell.children)
              .filter((child) => child.type === "tableCellDivider")
              .map((child) => displayWidth(line.slice(0, child.startColumn - 1))),
          };
        });
      const headerDividers = rows[0].dividers;
      if (rows.every(({ dividers }) =>
        dividers.length === headerDividers.length &&
        dividers.every((column, index) => column === headerDividers[index]),
      )) continue;

      const delimiter = rows[1];
      const widths = delimiter.cells.map((cell) => 3 + cell.replace(/-/g, "").length);
      for (const row of rows) {
        if (row === delimiter) continue;

        row.cells.forEach((cell, index) => {
          widths[index] = Math.max(widths[index] ?? 3, displayWidth(cell));
        });
      }

      for (const row of rows) {
        const cells = Array.from(
          { length: Math.max(delimiter.cells.length, row.cells.length) },
          (_, index) => row.cells[index] ?? "",
        );
        const padded = formatRow(cells, widths);
        if (row.text === padded) continue;

        const formatted = row === delimiter
          ? formatRow(cells.map((cell, index) => cell.replace(
            /-+/, "-".repeat(widths[index] - cell.replace(/-/g, "").length),
          )), widths)
          : padded;
        if (row.text === formatted) continue;

        onError({
          lineNumber: row.lineNumber,
          detail: "Align table column pipes",
          fixInfo: {
            editColumn: row.startIndex + 1,
            deleteCount: row.text.length,
            insertText: formatted,
          },
        });
      }
    }
  },
};
