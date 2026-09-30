const noNumberedHeadings = require("./.config/markdownlint/no-numbered-headings.cjs");
const tightLists = require("./.config/markdownlint/tight-lists.cjs");

module.exports = {
  config: {
    default: false,
    MD022: true,
    MD041: false,
    "no-numbered-headings": true,
    "tight-lists": true,
  },
  customRules: [noNumberedHeadings, tightLists],
};
