const noNumberedHeadings = require("./.config/markdownlint/no-numbered-headings.cjs");
const tightLists = require("./.config/markdownlint/tight-lists.cjs");
const noNbsp = require("./.config/markdownlint/no-nbsp.cjs");

module.exports = {
  config: {
    default: false,
    MD009: {
      br_spaces: 0,
      code_blocks: true,
    },
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
    "no-nbsp": {
      ignore_trailing: true,
    },
  },
  customRules: [noNumberedHeadings, tightLists, noNbsp],
};
