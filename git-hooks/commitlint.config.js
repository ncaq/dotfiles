module.exports = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    // URLやMarkdownのリンクなど改行出来ない要素が頻繁に頻繁に出現するため無効にする。
    "body-max-line-length": [0, "always"],
    "footer-max-line-length": [0, "always"],
    // 関数などの識別子などを直接コミットメッセージのタイトルに書きたいので無効にする。
    "subject-case": [0, "always"],
  },
};
