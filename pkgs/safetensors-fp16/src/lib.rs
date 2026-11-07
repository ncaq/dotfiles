//! safetensorsのF32テンソルだけをF16へ変換する。
//!
//! ComfyUIはモデルをmmapで読み、
//! CPU側の重みをファイル上のdtypeのまま保持してキャストしない。
//! 計算dtypeがfp16でもファイルがfp32ならホストが抱える量は倍になり、
//! 14.29Bパラメータのモデルではメモリを食い尽くす。
//! ファイル側を事前にfp16へ落とすことでこれを半分にする。
//!
//! fp32からfp16への丸めはIEEE 754のround-to-nearest-evenで、
//! ComfyUIがランタイムで行うキャストとビット単位で一致するため、
//! 生成結果は変わらない。
//!
//! 読み書きは本家のsafetensors crateに任せる。
//! 読み込みはmmapした領域をゼロコピーで参照し、
//! 書き込みは`View::data`をテンソルごとに呼んで順に書き出すので、
//! そこで変換すれば同時にメモリへ載るのは変換中の1テンソル分で済む。
//! Pythonバインディングの`save_file`は全テンソルの辞書を要求するため、
//! 数十GBのモデルには使えない。

use std::borrow::Cow;
use std::cell::OnceCell;
use std::collections::BTreeSet;
use std::fs::File;
use std::path::Path;

use anyhow::{Context, Result, bail, ensure};
use half::f16;
use memmap2::Mmap;
use safetensors::tensor::{Dtype, SafeTensors, TensorView, View, serialize_to_file};

/// ファイルをmmapする。
///
/// なぜunsafeなmmapを使うか:
///   `SafeTensors::deserialize`と`SafeTensors::read_metadata`はファイル全体の`&[u8]`を要求する。
///   数十GBを読み込むわけにはいかないので、
///   この形で渡すにはmmapするしかない。
///
///   unsafeを避けるなら、
///   ヘッダだけを読んで公開されている`Metadata`のDeserializeで検証し、
///   テンソルの中身は`read_exact_at`で1つずつ読む形にもできる。
///   しかしその場合は`read_metadata`が行っている検査のうち、
///   ヘッダ長の上限(定数が非公開)と、
///   ファイルサイズがヘッダとデータ領域の合計に一致することを自分で書き直すことになる。
///   また`View::data`は`Result`を返せないので、
///   そこで起きたI/Oエラーを持ち回って後から失敗させる仕組みも要る。
///   ヘッダ処理を自前で持たないためにcrateへ任せたのに、
///   unsafeを1つ消すためにそれを戻すのは割に合わない。
///
///   mmapのcrateにはsafeなAPIを名乗るものもあるが、
///   どれも内部で同じunsafeを隠しているだけで、
///   下に書いた前提が要ることは変わらない。
fn map(path: &Path) -> Result<Mmap> {
    let file = File::open(path).with_context(|| format!("failed to open {}", path.display()))?;
    // SAFETY: mmapしている間にファイルが書き換えられたり切り詰められたりすると未定義動作になる。
    // `lib/convert-safetensors-fp16.nix`から呼ばれる時、
    // 入力はNix storeの読み取り専用のファイルか、
    // 直前の`convert`が書き終えた`$out`で、
    // どちらもこのプロセスが動いている間に書き換えられることはない。
    // それ以外の使い方をする時も、
    // 処理中のファイルを他から書き換えないことを呼び出し側の前提とする。
    unsafe { Mmap::map(&file) }.with_context(|| format!("failed to mmap {}", path.display()))
}

/// 変換後のdtypeを返す。F32だけがF16になる。
fn converted_dtype(dtype: Dtype) -> Dtype {
    if dtype == Dtype::F32 {
        Dtype::F16
    } else {
        dtype
    }
}

/// F32のテンソルのバイト列を値の列として読む。
///
/// 長さが4の倍数であることは`SafeTensors::deserialize`がshapeとの整合で検証済み。
fn f32_values(data: &[u8]) -> impl Iterator<Item = f32> + '_ {
    data.as_chunks::<4>()
        .0
        .iter()
        .map(|bytes| f32::from_le_bytes(*bytes))
}

/// F32をF16へ変換しながら書き出すためのテンソル。
///
/// `View::data`は`Result`を返せないので、
/// オーバーフローは`overflow`へ記録しておき書き終えてから失敗させる。
struct Fp16View<'a> {
    name: &'a str,
    tensor: TensorView<'a>,
    allow_overflow: bool,
    overflow: &'a OnceCell<String>,
}

impl View for Fp16View<'_> {
    fn dtype(&self) -> Dtype {
        converted_dtype(self.tensor.dtype())
    }

    fn shape(&self) -> &[usize] {
        self.tensor.shape()
    }

    fn data(&self) -> Cow<'_, [u8]> {
        let data = self.tensor.data();
        if self.tensor.dtype() != Dtype::F32 {
            return Cow::Borrowed(data);
        }
        let mut converted = Vec::with_capacity(data.len() / 2);
        for value in f32_values(data) {
            let half = f16::from_f32(value);
            // 入力に元からあるinfやNaNは対象外で、
            // 有限の値が新たにinfへ潰れた時だけ記録する。
            if !self.allow_overflow && half.is_infinite() && value.is_finite() {
                // 最初に見つかったテンソルだけを報告すれば十分なので、2つ目以降の失敗は無視する。
                _ = self.overflow.set(self.name.to_owned());
            }
            converted.extend_from_slice(&half.to_le_bytes());
        }
        Cow::Owned(converted)
    }

    fn data_len(&self) -> usize {
        let len = self.tensor.data().len();
        if self.tensor.dtype() == Dtype::F32 {
            len / 2
        } else {
            len
        }
    }
}

/// srcのF32テンソルだけをF16へ変換してdstへ書く。
///
/// fp16の表現範囲を超えて新たにinfになる要素があれば、
/// `allow_overflow`が無い限り失敗させてdstを消す。
/// 静かにinfへ潰れた重みは壊れたモデルになるので、
/// bf16にするかfp32のままにするかを人間が判断すべきだからである。
pub fn convert(src: &Path, dst: &Path, allow_overflow: bool) -> Result<()> {
    let buffer = map(src)?;
    let (_, metadata) = SafeTensors::read_metadata(&buffer)?;
    let tensors = SafeTensors::deserialize(&buffer)?;
    let overflow = OnceCell::new();
    let views = tensors.iter().map(|(name, tensor)| {
        let view = Fp16View {
            name,
            tensor,
            allow_overflow,
            overflow: &overflow,
        };
        (name, view)
    });
    serialize_to_file(views, metadata.metadata().clone(), dst)
        .with_context(|| format!("failed to write {}", dst.display()))?;
    if let Some(name) = overflow.get() {
        std::fs::remove_file(dst)?;
        bail!("{name}: F32 values overflow to infinity in F16; pass --allow-overflow to accept");
    }
    Ok(())
}

/// dstがsrcを変換したものであることを全要素の突き合わせで確かめる。
///
/// サイズが合っていてもデータが1テンソル分ずれている、
/// という最も危険な失敗を検出するために中身まで比較する。
/// 比較はビットパターンで行うのでNaNの自己不一致は起きない。
pub fn verify(src: &Path, dst: &Path) -> Result<()> {
    let src_buffer = map(src)?;
    let dst_buffer = map(dst)?;
    let (_, src_metadata) = SafeTensors::read_metadata(&src_buffer)?;
    let (_, dst_metadata) = SafeTensors::read_metadata(&dst_buffer)?;
    ensure!(
        src_metadata.metadata() == dst_metadata.metadata(),
        "__metadata__ differs"
    );

    let src_tensors = SafeTensors::deserialize(&src_buffer)?;
    let dst_tensors = SafeTensors::deserialize(&dst_buffer)?;
    let src_names: BTreeSet<&str> = src_tensors.names().into_iter().collect();
    let dst_names: BTreeSet<&str> = dst_tensors.names().into_iter().collect();
    ensure!(
        src_names == dst_names,
        "tensor names differ: missing={:?} extra={:?}",
        src_names.difference(&dst_names).collect::<Vec<_>>(),
        dst_names.difference(&src_names).collect::<Vec<_>>(),
    );

    for (name, src_tensor) in src_tensors.iter() {
        let dst_tensor = dst_tensors.tensor(name)?;
        ensure!(
            src_tensor.shape() == dst_tensor.shape(),
            "{name}: shape {:?} became {:?}",
            src_tensor.shape(),
            dst_tensor.shape(),
        );
        let expected = converted_dtype(src_tensor.dtype());
        ensure!(
            dst_tensor.dtype() == expected,
            "{name}: dtype {} became {} instead of {expected}",
            src_tensor.dtype(),
            dst_tensor.dtype(),
        );
        let same = if src_tensor.dtype() == Dtype::F32 {
            let dst_values = dst_tensor.data().as_chunks::<2>().0;
            f32_values(src_tensor.data())
                .zip(dst_values)
                .all(|(value, bytes)| f16::from_f32(value).to_bits() == u16::from_le_bytes(*bytes))
        } else {
            src_tensor.data() == dst_tensor.data()
        };
        ensure!(same, "{name}: contents differ");
    }
    Ok(())
}
