/* eslint-disable import/no-import-module-exports */
import type { RulesConfig, UserConfig } from "@commitlint/types";
import { RuleConfigSeverity } from "@commitlint/types";
import { plugin as userPlugin, RulesConfig as UserRulesConfig } from "./src/@commitlint/rules/index";

const rules: Partial<RulesConfig & UserRulesConfig> = {
  // 日本語なども含めた可読文字で終わることを求める。
  "subject-alnum-stop": [RuleConfigSeverity.Error, "never"],

  // URLやMarkdownのリンクなど改行出来ない要素が頻繁に頻繁に出現するため緩める。
  "body-max-line-length": [RuleConfigSeverity.Disabled],
  "footer-max-line-length": [RuleConfigSeverity.Disabled],
  // 関数などの識別子などを直接コミットメッセージのタイトルに書きたいので無効にする。
  "subject-case": [RuleConfigSeverity.Disabled],
};

const Configuration: UserConfig = {
  extends: ["@commitlint/config-conventional"],
  rules,
  plugins: [userPlugin],
};

module.exports = Configuration;
