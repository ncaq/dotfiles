import { RuleConfig, RuleConfigQuality, Plugin } from "@commitlint/types";
import { subjectAlnumStop } from "./subject-alnum-stop";

export const plugin: Plugin = {
  rules: {
    "subject-alnum-stop": subjectAlnumStop,
  },
};

export type RulesConfig<V = RuleConfigQuality.User> = {
  "subject-alnum-stop": RuleConfig<V, RegExp | undefined>;
};
