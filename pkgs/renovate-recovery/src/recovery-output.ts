/**
 * Claude Codeが書いた結果のファイルを、投稿してよいものか判定する規則。
 *
 * 結果のファイルはClaude Codeが書ける作業ツリーの中にあります。
 * 仕込まれた指示に従ったClaude Codeが、
 * ファイルやディレクトリを`/proc/self/environ`などへのリンクに置き換えると、
 * 投稿のステップがリンクをたどって秘密を公開してしまいます。
 * 投稿のステップはClaude Codeの権限の規則の外で動くので、ここで確かめます。
 *
 * ファイルシステムに触れない判定だけをここに置いて、テストできるようにしています。
 * ファイル自体がリンクの場合は、開く時の`O_NOFOLLOW`で拒否します。
 */

/** 結果として読み込むファイルの大きさの上限。PRのコメントの上限より十分小さくします。 */
export const MAX_RESULT_BYTES = 32 * 1024;

/** 結果を置くディレクトリを`lstat`で見た情報のうち、判定に使うもの。 */
export interface ResultDirInfo {
  /** リンクではないディレクトリか。 */
  readonly isDirectory: boolean;
}

/** 開いた結果のファイルのハンドルを`stat`で見た情報のうち、判定に使うもの。 */
export interface ResultFileInfo {
  /** 通常のファイルか。 */
  readonly isFile: boolean;
  /** ハードリンクの数。外のファイルへのハードリンクを読まないために見ます。 */
  readonly nlink: number;
  /** バイト数。 */
  readonly size: number;
}

/**
 * 結果を置くディレクトリを使ってよいか判定します。
 * 使ってよければ`undefined`を、使わない時はその理由を返します。
 */
export function rejectResultDir(info: ResultDirInfo): string | undefined {
  if (!info.isDirectory) {
    return "結果を置くディレクトリがリンクに置き換えられているか、ディレクトリではありません";
  }
  return undefined;
}

/**
 * 開いた結果のファイルを読んでよいか判定します。
 * 読んでよければ`undefined`を、読まない時はその理由を返します。
 */
export function rejectResultFile(info: ResultFileInfo): string | undefined {
  if (!info.isFile) {
    return "結果のファイルが通常のファイルではありません";
  }
  if (info.nlink !== 1) {
    return "結果のファイルが他のファイルとハードリンクで繋がっています";
  }
  if (MAX_RESULT_BYTES < info.size) {
    return `結果のファイルが${MAX_RESULT_BYTES}バイトを超えています`;
  }
  return undefined;
}
