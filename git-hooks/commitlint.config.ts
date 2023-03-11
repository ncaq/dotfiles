/* eslint-disable import/no-import-module-exports */
import type { UserConfig } from "@commitlint/types";
import { RuleConfigSeverity } from "@commitlint/types";

const Configuration: UserConfig = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    // URLやMarkdownのリンクなど改行出来ない要素が頻繁に頻繁に出現するため緩める。
    "body-max-line-length": [RuleConfigSeverity.Disabled],
    "footer-max-line-length": [RuleConfigSeverity.Disabled],
    // 関数などの識別子などを直接コミットメッセージのタイトルに書きたいので無効にする。
    "subject-case": [RuleConfigSeverity.Disabled],
  },
};

module.exports = Configuration;
