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
        .map((token) => ({
          token,
          cells: token.children.map((cell) =>
            cell.children.find((child) => child.type === "tableContent")?.text ?? "",
          ),
          dividers: token.children
            .flatMap((cell) => cell.children)
            .filter((child) => child.type === "tableCellDivider")
            .map((child) => displayWidth(
              params.lines[child.startLine - 1].slice(0, child.startColumn - 1),
            )),
        }));
      const headerDividers = rows[0].dividers;
      const isAligned = rows.every(({ dividers }) =>
        dividers.length === headerDividers.length &&
        dividers.every((column, index) => column === headerDividers[index]),
      );
      if (isAligned) continue;

      const delimiter = rows[1];
      const columnCount = delimiter.cells.length;
      const markers = delimiter.cells.map((cell) => ({
        left: cell.startsWith(":") ? ":" : "",
        right: cell.endsWith(":") ? ":" : "",
      }));
      const widths = markers.map(({ left, right }) => 3 + left.length + right.length);

      for (const row of rows) {
        if (row === delimiter) continue;

        row.cells.forEach((cell, index) => {
          widths[index] = Math.max(widths[index] ?? 3, displayWidth(cell));
        });
      }

      for (const row of rows) {
        const cells = row === delimiter
          ? markers.map(({ left, right }, index) =>
            left + "-".repeat(widths[index] - left.length - right.length) + right,
          )
          : Array.from(
            { length: Math.max(columnCount, row.cells.length) },
            (_, index) => {
              const cell = row.cells[index] ?? "";
              return cell + " ".repeat(widths[index] - displayWidth(cell));
            },
          );
        const formatted = "| " + cells.join(" | ") + " |";
        const line = params.lines[row.token.startLine - 1];
        const leadingWhitespace = row.token.text.match(/^[ \t]*/)[0].length;
        const startIndex = row.token.startColumn - 1 + leadingWhitespace;
        if (line.slice(startIndex) === formatted) continue;

        if (row === delimiter) {
          const padded = "| " + row.cells.map((cell, index) =>
            cell + " ".repeat(Math.max(0, widths[index] - displayWidth(cell))),
          ).join(" | ") + " |";
          if (line.slice(startIndex) === padded) continue;
        }

        onError({
          lineNumber: row.token.startLine,
          detail: "Align table column pipes",
          fixInfo: {
            editColumn: startIndex + 1,
            deleteCount: line.length - startIndex,
            insertText: formatted,
          },
        });
      }
    }
  },
};
