import message from "@commitlint/message";
import type { SyncRule } from "@commitlint/types";

/**
 * `subject-full-stop`の拡張。
 * 日本語の句読点も含めて制御する。
 * 句読点など記号は無しがデフォルト。
 */
export const subjectAlnumStop: SyncRule<RegExp | undefined> = (
  parsed,
  when = "always",
  value = /[^\p{Letter}\p{Number}]/u
) => {
  let colonIndex = parsed.header.indexOf(":");
  if (colonIndex > 0 && colonIndex === parsed.header.length - 1) {
    return [true];
  }

  const input = parsed.header;

  const negated = when === "never";
  const hasStop = value.test(input[input.length - 1]);

  return [negated ? !hasStop : hasStop, message(["subject", negated ? "may not" : "must", "end with alnum stop"])];
};
