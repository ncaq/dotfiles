-- | 形式で決まっている値のテスト。
--
-- fixtureは本番と同じ`encodeValueType`で型IDを書くので、
-- `GgufValueType`の構築子の順番が仕様とずれていても、
-- 本番コードとテスト用のGGUFが同じずれたIDを書いて位置のテストは通ってしまう。
-- 型IDの対応はここで本番コードに頼らずに固定する。
module Spec.Gguf.FormatSpec (tests) where

import Himari
import PatchGgufChatTemplate.Gguf.Format
import Test.Sandwich

tests :: TopSpec
tests = describe "GgufValueType" do
  for_ [minBound .. maxBound] \valueType ->
    it ("型IDへ書いて読み戻すと元に戻る: " <> show valueType) do
      decodeValueType (encodeValueType valueType) `shouldBe` Just valueType
  -- 往復だけでは構築子の並びがどこから始まるかを固定できないので、
  -- 仕様の両端のIDを数値で書いて起点と終点を留める。
  it "型IDは0のuint8から始まる" do
    encodeValueType GgufUInt8 `shouldBe` 0
  it "型IDは12のfloat64で終わる" do
    encodeValueType GgufFloat64 `shouldBe` 12
  it "13以降の型IDは知らない" do
    decodeValueType 13 `shouldBe` Nothing
