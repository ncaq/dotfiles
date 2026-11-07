-- | コマンドラインの組み立てのテスト。
--
-- 全体のオプションと`reservedFlags`は手で揃える約束なので、
-- 片方だけを追加や改名した時にここで落ちるようにする。
module Spec.CliSpec (tests) where

import ComfyWorkflow.Cli
import ComfyWorkflow.Parameter (reservedFlags)
import Himari
import Options.Applicative (defaultPrefs, execParserPure, getParseResult)
import Test.Sandwich

-- | パラメータの無いワークフローのコマンドラインに引数を通し、受理されたかを返す。
--
-- `ParserResult`の`Success`はaesonともsandwichとも名前が被るので`getParseResult`で見る。
accepts :: [String] -> Bool
accepts args = isJust (getParseResult (execParserPure defaultPrefs (optionsParser "x" []) args))

tests :: TopSpec
tests = describe "Cli" do
  describe "optionsParser" do
    it "reservedFlagsの名前を全体のオプションとして受け付ける" do
      -- `--help`は`helper`が処理して成功にはならないので外す。
      -- 値を取るものと取らないものがあるので、どちらかの形で通れば良い。
      for_ (filter (/= "help") reservedFlags) \flag -> do
        let long = "--" <> convert flag
        (accepts [long] || accepts [long, "1"]) `shouldBe` True
    it "知らないフラグは弾く" do
      accepts ["--bogus"] `shouldBe` False
      accepts ["--bogus", "1"] `shouldBe` False
    it "引数が無くても通る" do
      accepts [] `shouldBe` True
