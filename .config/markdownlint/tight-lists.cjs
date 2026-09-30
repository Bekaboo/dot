const listOpenTypes = new Set(["bullet_list_open", "ordered_list_open"]);
const listCloseTypes = new Set(["bullet_list_close", "ordered_list_close"]);

module.exports = {
  names: ["tight-lists"],
  description: "Lists must not contain unnecessary blank lines",
  tags: ["bullet", "ol", "ul"],
  parser: "markdownit",
  function: (params, onError) => {
    const lists = [];
    const items = [];
    const reportBlankLinesBefore = (startLineIndex, detail) => {
      for (let lineIndex = startLineIndex - 1; lineIndex >= 0; lineIndex -= 1) {
        if (params.lines[lineIndex].trim()) break;

        onError({
          lineNumber: lineIndex + 1,
          detail,
          fixInfo: {
            deleteCount: -1,
          },
        });
      }
    };

    for (const token of params.parsers.markdownit.tokens) {
      if (listOpenTypes.has(token.type)) {
        const parentItem = items.at(-1);
        const isDirectChild = parentItem && token.level === parentItem.token.level + 1;
        if (
          isDirectChild &&
          parentItem.directParagraphs === 1 &&
          !parentItem.hasSeparatedParagraph
        ) {
          reportBlankLinesBefore(
            token.map[0],
            "Remove the blank line before the nested list",
          );
        }

        lists.push([]);
        continue;
      }

      if (token.type === "list_item_open") {
        const item = {
          token,
          directParagraphs: 0,
          hasSeparatedParagraph: false,
        };
        lists.at(-1).push(item);
        items.push(item);
        continue;
      }

      if (token.type === "paragraph_open") {
        const item = items.at(-1);
        if (!item) continue;

        const isDirectChild = token.level === item.token.level + 1;
        if (isDirectChild) item.directParagraphs += 1;

        const isPrimaryParagraph = isDirectChild && item.directParagraphs === 1;
        if (isPrimaryParagraph) continue;

        const paragraphStart = token.map[0];
        if (paragraphStart === 0 || params.lines[paragraphStart - 1].trim()) continue;

        for (const ancestorItem of items) {
          ancestorItem.hasSeparatedParagraph = true;
        }
        continue;
      }

      if (token.type === "list_item_close") {
        items.pop();
        continue;
      }

      if (!listCloseTypes.has(token.type)) continue;

      const list = lists.pop();
      for (let index = 1; index < list.length; index += 1) {
        const previousItem = list[index - 1];
        if (previousItem.hasSeparatedParagraph) continue;

        const nextItem = list[index];
        reportBlankLinesBefore(
          nextItem.token.map[0],
          "Remove the blank line between adjacent list items",
        );
      }
    }
  },
};
