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

-- | 仕様が決めている値の置かれ方。
--
-- 幅を1つでも間違えると、その型の値より後ろの全ての位置がずれる。
-- 本番コードは整数の幅をHaskellの型から導くので、
-- 仕様のバイト数をここに数値で書いて突き合わせる。
layouts :: [(GgufValueType, GgufLayout)]
layouts =
  [ (GgufUInt8, GgufFixedWidth 1)
  , (GgufInt8, GgufFixedWidth 1)
  , (GgufUInt16, GgufFixedWidth 2)
  , (GgufInt16, GgufFixedWidth 2)
  , (GgufUInt32, GgufFixedWidth 4)
  , (GgufInt32, GgufFixedWidth 4)
  , (GgufFloat32, GgufFixedWidth 4)
  , (GgufBool, GgufFixedWidth 1)
  , (GgufString, GgufLengthPrefixed)
  , (GgufArray, GgufElements)
  , (GgufUInt64, GgufFixedWidth 8)
  , (GgufInt64, GgufFixedWidth 8)
  , (GgufFloat64, GgufFixedWidth 8)
  ]

tests :: TopSpec
tests = do
  describe "GgufValueType" do
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
  describe "layout" do
    -- 表に漏れがあると構築子の数と合わなくなるので、表の長さも固定する。
    it "全ての構築子を表に載せている" do
      fmap fst layouts `shouldBe` [minBound .. maxBound]
    for_ layouts \(valueType, expected) ->
      it (show valueType <> " -> " <> show expected) do
        layout valueType `shouldBe` expected
