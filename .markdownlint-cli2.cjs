const noNumberedHeadings = require("./.config/markdownlint/no-numbered-headings.cjs");

module.exports = {
  config: {
    default: false,
    MD022: true,
    "no-numbered-headings": true,
  },
  customRules: [noNumberedHeadings],
};
