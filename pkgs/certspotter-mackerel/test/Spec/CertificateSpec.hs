-- | 証明書のJSONの読み方のテスト。
--
-- 読めない時に例外で落ちず、理由を返すことを固定する。
-- 落ちるとイベント自体が記録されず、発行に気付けなくなる。
module Spec.CertificateSpec (tests) where

import CertspotterMackerel.Certificate (Certificate (..), readCertificate)
import Fixture
import Himari
import Test.Sandwich

-- | 中身を書いたファイルを証明書として読む。
readContent :: (MonadUnliftIO m) => String -> m (Either Text Certificate)
readContent content =
  withWorkspace \workspace -> do
    let path = workspace.root </> "content.json"
    liftIO (writeFile path content)
    readCertificate path

tests :: TopSpec
tests = describe "readCertificate" do
  it "dns_namesを読む" do
    withWorkspace \workspace ->
      readCertificate workspace.certificate
        >>= (`shouldBe` Right (Certificate ["ncaq.net", "*.ncaq.net"]))
  it "dns_namesが無ければSANが無いものとして読む" do
    readContent "{\"not_before\":\"2026-11-01T00:00:00Z\"}" >>= (`shouldBe` Right (Certificate []))
  it "ファイルが無ければ理由を返す" do
    withWorkspace \workspace ->
      readCertificate (workspace.root </> "missing.json") >>= (`shouldBe` True) . isLeft
  it "JSONでなければ理由を返す" do
    readContent "not json" >>= (`shouldBe` True) . isLeft
  it "dns_namesが配列でなければ理由を返す" do
    readContent "{\"dns_names\":\"ncaq.net\"}" >>= (`shouldBe` True) . isLeft
  it "オブジェクトでなければ理由を返す" do
    readContent "[]" >>= (`shouldBe` True) . isLeft
