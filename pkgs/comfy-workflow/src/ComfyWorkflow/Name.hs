-- | コマンドラインのフラグ名を決める。
--
-- ウィジェット名をそのままフラグにすると衝突する。
-- ポジティブとネガティブの両方が`CLIPTextEncode`の`text`で、
-- どちらも`--text`になってしまう。
--
-- 衝突したものだけノードのタイトルへ譲る。
-- `Positive Prompt`と`Negative Prompt`という表示名が既に付いているので、
-- `--positive-prompt`と`--negative-prompt`になる。
--
-- タイトルが日本語だとASCIIの名前を作れないので、
-- その場合はノードIDまで落ちる。
-- 落ちてもフラグ名は`--help`に出るので、
-- 読めば分かる状態は保たれる。
module ComfyWorkflow.Name
  ( slug
  , candidates
  , resolveNames
  ) where

import Data.Text (intercalate, isPrefixOf, split, toLower)
import Himari

-- | フラグに使えるASCIIの名前へ落とす。作れなければ空文字列。
--
-- 英字で始まらないものは作れなかったものとして扱う。
-- `参考画像2`のようなタイトルからは`2`しか残らず、
-- `--2`というフラグは負の数と区別が付かない。
--
-- 扱うのがASCIIの英数字だけなので、文字の判定も範囲で書く。
slug :: Text -> Text
slug text = if startsWithLetter then name else ""
 where
  pieces = filter (/= mempty) (split (not . isAsciiWord) text)
  name = intercalate "-" (fmap toLower pieces)
  startsWithLetter = maybe False (isAsciiLetter . fst) (uncons name)
  isAsciiLetter c = c `elem` ['a' .. 'z'] || c `elem` ['A' .. 'Z']
  isAsciiWord c = isAsciiLetter c || c `elem` ['0' .. '9']

-- | そのパラメータに使える名前を、望ましい順に並べる。
candidates :: Text -> Text -> Text -> [Text]
candidates nodeId title widget =
  -- 前に出たものと同じ名前は落とす。
  [name | (position, name) <- zip [0 :: Int ..] usable, name `notElem` take position usable]
 where
  names =
    [ slug widget
    , slug title
    , slug title <> "-" <> slug widget
    , "node" <> nodeId <> "-" <> slug widget
    ]
  -- 空のものと、タイトルの分が空で`-`から始まってしまったものを落とす。
  usable = filter (\name -> name /= mempty && not ("-" `isPrefixOf` name)) names

-- | 候補の並びから、重複しないフラグ名を決める。
--
-- 望ましい順に見て、
-- その段で1つしか名乗り手のいない名前だけを確定させる。
-- 衝突したものは次の段へ持ち越す。
--
-- `reserved`は`--seed`のような全体のオプションが先に取っている名前で、
-- 最初から使用済みとして扱う。
-- パラメータ側に譲らせるのは、
-- ワークフローが増えるたびに全体のオプションの名前が変わる方が困るからである。
--
-- 候補の末尾にはノードIDを含む名前があるので、
-- 普通はそこで分かれる。
--
-- それでも決まらないのは、
-- 同じノードの同じウィジェットを2度書いた場合だけである。
-- その場合は`unnamed`に位置を付けた名前へ落とす。
-- どちらを採っても書き込む先は同じなので、
-- 名前が読めることより重複しないことを優先する。
resolveNames :: [Text] -> [[Text]] -> [Text]
resolveNames reserved candidateLists =
  [ fromMaybe ("unnamed" <> convert (show position)) (resolved ^. at position)
  | position <- positions
  ]
 where
  positions = [0 .. length candidateLists - 1]
  depth = maximum (0 : fmap length candidateLists)
  resolved :: Map Int Text
  (resolved, _) = foldl' step (mempty, reserved) [0 .. depth - 1]
  step (done, taken) level =
    let pending =
          [ (position, name)
          | (position, names) <- zip positions candidateLists
          , hasn't (ix position) done
          , Just name <- [names ^? ix level]
          ]
        claimants name = length (filter ((== name) . snd) pending)
        claim (done', taken') (position, name)
          | claimants name == 1 && name `notElem` taken' =
              (done' & at position ?~ name, name : taken')
          | otherwise = (done', taken')
     in foldl' claim (done, taken) pending
