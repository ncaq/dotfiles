import process from "node:process";

/**
 * 必須の環境変数を読みます。
 * 未設定や空文字列ならどの変数が足りないのかを示して失敗します。
 */
export function requireEnv(name: string): string {
  const value = process.env[name];
  if (value == null || value === "") {
    throw new Error(`環境変数${name}が設定されていません`);
  }
  return value;
}

/** 必須の環境変数を整数として読みます。 */
export function requireIntegerEnv(name: string): number {
  const value = Number(requireEnv(name));
  if (!Number.isInteger(value)) {
    throw new Error(`環境変数${name}が整数ではありません`);
  }
  return value;
}
