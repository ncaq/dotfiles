-- | device-mapperの名前として使える文字列の検査。
module RemovableCrypt.DeviceMapperName
  ( validDeviceMapperName
  ) where

import Data.Char (isAscii, isAsciiLower, isAsciiUpper, isDigit)
import Data.Text qualified as T
import Himari

-- | 英数字で始まり、英数字と`#+-.:=@_`だけからなるか。
--
-- マッパーの名前はそのままマウントポイントやデバイスのパスの一部になる。
-- `/`や`..`が入るとルートの権限で意図しない場所を触ることになるので、
-- 引数で受け取った時点で弾く。
-- `lib/removable-crypt.nix`のオプションの型も同じ規則で検査している。
validDeviceMapperName :: Text -> Bool
validDeviceMapperName name = case T.uncons name of
  Just (initial, rest) -> alphanumeric initial && T.all allowed rest
  Nothing -> False
 where
  alphanumeric character = isAsciiLower character || isAsciiUpper character || isDigit character
  allowed character = alphanumeric character || (isAscii character && T.elem character "#+-.:=@_")
