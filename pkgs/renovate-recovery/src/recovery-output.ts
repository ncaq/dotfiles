/**
 * Claude Codeが書いた結果のファイルを、投稿してよいものか判定する規則。
 *
 * 結果のファイルはClaude Codeが書ける作業ツリーの中にあります。
 * 仕込まれた指示に従ったClaude Codeが、
 * ファイルを`/proc/self/environ`などへのシンボリックリンクに置き換えると、
 * 投稿のステップがリンクをたどって秘密を公開してしまいます。
 * 投稿のステップはClaude Codeの権限の規則の外で動くので、ここで確かめます。
 *
 * ファイルシステムに触れない判定だけをここに置いて、テストできるようにしています。
 */

import path from "node:path";

/** 結果として読み込むファイルの大きさの上限。PRのコメントの上限より十分小さくします。 */
export const MAX_RESULT_BYTES = 32 * 1024;

/** 結果のファイルの情報のうち、判定に使うもの。 */
export interface ResultFileInfo {
  /** `lstat`で見た種類が通常のファイルか。シンボリックリンクなら`false`。 */
  readonly isRegularFile: boolean;
  /** リンクを全て解決した実際のパス。 */
  readonly realPath: string;
  /** バイト数。 */
  readonly size: number;
}

/**
 * 結果のファイルを読んでよいか判定します。
 * 読んでよければ`undefined`を、読まない時はその理由を返します。
 *
 * `allowedDirRealPath`はリンクを解決した後の、結果を置いてよいディレクトリのパスです。
 * ディレクトリ自体がリンクに置き換えられた場合にも備えて、
 * ファイルの実際のパスがその中にあることを確かめます。
 */
export function rejectResultFile(
  info: ResultFileInfo,
  allowedDirRealPath: string,
): string | undefined {
  if (!info.isRegularFile) {
    return "結果のファイルが通常のファイルではありません";
  }
  const relative = path.relative(allowedDirRealPath, info.realPath);
  if (relative === "" || relative.startsWith("..") || path.isAbsolute(relative)) {
    return "結果のファイルが結果を置くディレクトリの外にあります";
  }
  if (MAX_RESULT_BYTES < info.size) {
    return `結果のファイルが${MAX_RESULT_BYTES}バイトを超えています`;
  }
  return undefined;
}
