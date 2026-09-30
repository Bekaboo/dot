const noNumberedHeadings = require("./.config/markdownlint/no-numbered-headings.cjs");
const tightLists = require("./.config/markdownlint/tight-lists.cjs");

module.exports = {
  config: {
    default: false,
    MD022: true,
    MD030: {
      ul_single: 1,
      ol_single: 1,
      ul_multi: 1,
      ol_multi: 1,
    },
    MD041: false,
    "no-numbered-headings": true,
    "tight-lists": true,
  },
  customRules: [noNumberedHeadings, tightLists],
};
