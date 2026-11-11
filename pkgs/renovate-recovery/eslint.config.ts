import path from "node:path";
import { fileURLToPath } from "node:url";
import { configs as eslintConfigs } from "@eslint/js";
import { defineConfig, includeIgnoreFile } from "eslint/config";
import eslintConfigPrettier from "eslint-config-prettier";
import { createTypeScriptImportResolver } from "eslint-import-resolver-typescript";
import { flatConfigs as importPluginConfig } from "eslint-plugin-import-x";
import node from "eslint-plugin-n";
import { default as tseslint } from "typescript-eslint";

/** ES Modulesだと使用できない変数のエミュレート。 */
const __filename: string = fileURLToPath(import.meta.url);
/** ES Modulesだと使用できない変数のエミュレート。 */
const __dirname: string = path.dirname(__filename);
/** そのプロジェクトの.gitignoreのパス。 */
const gitignorePath: string = path.resolve(__dirname, ".gitignore");

/** ESLintが使用する設定を定義。 */
const config: ReturnType<typeof defineConfig> = defineConfig(
  // どのプロジェクトでも共通して適用するルール。
  // `.gitignore`から無視するべきファイルを継承。
  // `gitignoreResolution: true`でignoreファイル自身からの相対パスとして解決する、
  // 本来のgitignore挙動にします。
  includeIgnoreFile(gitignorePath, { gitignoreResolution: true }),
  eslintConfigPrettier, // prettierと競合しないようにします。
  importPluginConfig.recommended, // importの推奨プリセット。
  importPluginConfig.typescript, // importのTypeScript向け推奨プリセット。
  {
    rules: {
      // 名前別だけではなくカテゴリ別にもソートします。
      "import-x/order": ["error", { alphabetize: { order: "asc", orderImportKind: "asc" } }],
    },
    settings: {
      // TypeScriptのimportを柔軟に解決できるようにします。
      "import-x/resolver-next": [
        createTypeScriptImportResolver({
          alwaysTryTypes: true,
        }),
      ],
    },
  },
  // ESLint全体の推奨プリセット。
  eslintConfigs.recommended,
  // typescript-eslintの推奨プリセット。
  tseslint.configs.recommendedTypeChecked,
  tseslint.configs.stylisticTypeChecked,
  {
    rules: {
      // 使ってないシンボルはアンダースコア始めにすることで警告を回避します。
      "@typescript-eslint/no-unused-vars": [
        "warn",
        {
          argsIgnorePattern: "^_",
          caughtErrorsIgnorePattern: "^_",
          destructuredArrayIgnorePattern: "^_",
          varsIgnorePattern: "^_",
        },
      ],
    },
  },
  {
    // TypeScript向けのルール。
    files: ["**/*.{ts,tsx,cts,mts}"],
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: __dirname,
      },
    },
    rules: {
      // 関数には基本的に明示的な型アノテーションを要求。
      "@typescript-eslint/explicit-function-return-type": [
        "error",
        {
          allowExpressions: true, // インラインな関数式にはいちいち要求しません。
        },
      ],
    },
  },
  {
    // TypeScriptルールでJavaScriptもlintします。
    // 主に`@ts-check`を有効にしている環境を想定しています。
    // 厳密には個別にルールを管理するべきなのですが、
    // あまり生のJavaScriptを書かないので、
    // TypeScriptルールプリセットを流用します。
    files: ["**/*.{js,jsx,cjs,mjs}"],
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: __dirname,
      },
    },
  },
  {
    // Node.js向けのルール。
    plugins: { n: node },
    extends: ["n/recommended-module"],
    rules: {
      // 複雑な設定下でのimportを解決できないため無効化します。
      // eslint-plugin-import-xに任せます。
      "n/no-missing-import": "off",
      // Node.jsビルトインのモジュールをimportする時にprefixを強制して依存をわかりやすくします。
      "n/prefer-node-protocol": "error",
      // Promise APIを優先して使用します。
      "n/prefer-promises/dns": "error",
      "n/prefer-promises/fs": "error",
      // Web標準としてほぼ全ランタイムにグローバルで存在するものはグローバルを使います。
      "n/prefer-global/console": "error",
      "n/prefer-global/crypto": "error",
      "n/prefer-global/text-decoder": "error",
      "n/prefer-global/text-encoder": "error",
      "n/prefer-global/timers": "error",
      "n/prefer-global/url": "error",
      "n/prefer-global/url-search-params": "error",
      // Node.js固有のグローバルはimportを強制して依存を明示します。
      "n/prefer-global/buffer": ["error", "never"],
      "n/prefer-global/process": ["error", "never"],
    },
  },
);
// ESLintの設定をエクスポート。
// 型アノテーションとdefault exportが両立できないため分けています。
export default config;
