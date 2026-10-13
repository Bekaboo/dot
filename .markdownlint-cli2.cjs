const noNumberedHeadings = require("./.config/markdownlint/no-numbered-headings.cjs");
const tightLists = require("./.config/markdownlint/tight-lists.cjs");
const noNbsp = require("./.config/markdownlint/no-nbsp.cjs");
const alignedTables = require("./.config/markdownlint/aligned-tables.cjs");

module.exports = {
  config: {
    default: false,
    MD009: {
      br_spaces: 0,
      code_blocks: true,
    },
    MD022: true,
    MD030: {
      severity: "warning",
      ul_single: 1,
      ol_single: 1,
      ul_multi: 1,
      ol_multi: 1,
    },
    MD041: false,
    "no-numbered-headings": {
      severity: "warning",
    },
    "tight-lists": {
      severity: "warning",
    },
    "no-nbsp": {
      ignore_trailing: true,
    },
    "aligned-tables": {
      severity: "warning",
    },
  },
  customRules: [noNumberedHeadings, tightLists, noNbsp, alignedTables],
};
