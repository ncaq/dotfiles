module.exports = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    // URLやMarkdownのリンクなど改行出来ない要素が頻繁に頻繁に出現するため無効にする。
    "footer-max-line-length": [0, "always"],
  },
};
