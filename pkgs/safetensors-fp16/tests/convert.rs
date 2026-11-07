use std::collections::HashMap;
use std::path::Path;

use safetensors::tensor::{Dtype, SafeTensors, TensorView, serialize_to_file};
use safetensors_fp16::{convert, verify};
use tempfile::TempDir;

fn f32_bytes(values: &[f32]) -> Vec<u8> {
    values
        .iter()
        .flat_map(|value| value.to_le_bytes())
        .collect()
}

fn f16_bits(data: &[u8]) -> Vec<u16> {
    data.as_chunks::<2>()
        .0
        .iter()
        .map(|bytes| u16::from_le_bytes(*bytes))
        .collect()
}

/// F32の1次元テンソル1つだけを持つファイルを書く。
fn write_f32(path: &Path, values: &[f32]) {
    let data = f32_bytes(values);
    let view = TensorView::new(Dtype::F32, vec![values.len()], &data).unwrap();
    serialize_to_file([("weight", view)], None, path).unwrap();
}

/// F32の1次元テンソル1つを変換し、出力をF16のビット列として返す。
fn convert_f32(values: &[f32], allow_overflow: bool) -> anyhow::Result<Vec<u16>> {
    let dir = TempDir::new().unwrap();
    let src = dir.path().join("src.safetensors");
    let dst = dir.path().join("dst.safetensors");
    write_f32(&src, values);
    convert(&src, &dst, allow_overflow)?;
    let buffer = std::fs::read(&dst).unwrap();
    let tensors = SafeTensors::deserialize(&buffer).unwrap();
    Ok(f16_bits(tensors.tensor("weight").unwrap().data()))
}

#[test]
fn converts_only_f32() {
    let dir = TempDir::new().unwrap();
    let src = dir.path().join("src.safetensors");
    let dst = dir.path().join("dst.safetensors");

    let weight = f32_bytes(&[1.0, -2.0, 0.5, 65504.0, 0.0, -0.0]);
    let bf16 = vec![0x80, 0x3f, 0x00, 0xc0];
    let index: Vec<u8> = [7_i64, -1].iter().flat_map(|v| v.to_le_bytes()).collect();
    let metadata = HashMap::from([("format".to_owned(), "pt".to_owned())]);
    serialize_to_file(
        [
            (
                "weight",
                TensorView::new(Dtype::F32, vec![2, 3], &weight).unwrap(),
            ),
            (
                "bf16",
                TensorView::new(Dtype::BF16, vec![2], &bf16).unwrap(),
            ),
            (
                "index",
                TensorView::new(Dtype::I64, vec![2], &index).unwrap(),
            ),
        ],
        Some(metadata.clone()),
        &src,
    )
    .unwrap();

    convert(&src, &dst, false).unwrap();

    let buffer = std::fs::read(&dst).unwrap();
    let (_, header) = SafeTensors::read_metadata(&buffer).unwrap();
    assert_eq!(header.metadata(), &Some(metadata));
    let tensors = SafeTensors::deserialize(&buffer).unwrap();

    let converted = tensors.tensor("weight").unwrap();
    assert_eq!(converted.dtype(), Dtype::F16);
    assert_eq!(converted.shape(), [2, 3]);
    assert_eq!(
        f16_bits(converted.data()),
        [0x3c00, 0xc000, 0x3800, 0x7bff, 0x0000, 0x8000]
    );

    let kept = tensors.tensor("bf16").unwrap();
    assert_eq!((kept.dtype(), kept.data()), (Dtype::BF16, bf16.as_slice()));
    let kept = tensors.tensor("index").unwrap();
    assert_eq!((kept.dtype(), kept.data()), (Dtype::I64, index.as_slice()));

    verify(&src, &dst).unwrap();
}

/// ComfyUIがランタイムで行うキャストと一致することの根拠なので、
/// 丸めの境界を直接確かめる。
#[test]
fn rounds_to_nearest_even() {
    let ulp = 2_f32.powi(-10);
    let values = [
        // ちょうど中間なら仮数が偶数の側へ丸める。
        1.0 + ulp / 2.0,
        1.0 + ulp * 3.0 / 2.0,
        // 中間を少しでも超えれば上へ丸める。
        1.0 + ulp / 2.0 + 2_f32.powi(-20),
    ];
    assert_eq!(
        convert_f32(&values, false).unwrap(),
        [0x3c00, 0x3c02, 0x3c01]
    );
}

#[test]
fn rejects_overflow() {
    let dir = TempDir::new().unwrap();
    let src = dir.path().join("src.safetensors");
    let dst = dir.path().join("dst.safetensors");
    write_f32(&src, &[1.0, 70000.0]);
    assert!(convert(&src, &dst, false).is_err());
    assert!(!dst.exists());
}

#[test]
fn allows_overflow_when_requested() {
    assert_eq!(convert_f32(&[70000.0], true).unwrap(), [0x7c00]);
}

#[test]
fn keeps_existing_infinity_and_nan() {
    let bits = convert_f32(&[f32::INFINITY, f32::NAN], false).unwrap();
    assert_eq!(bits[0], 0x7c00);
    assert!(half::f16::from_bits(bits[1]).is_nan());
}

#[test]
fn verify_rejects_modified_contents() {
    let dir = TempDir::new().unwrap();
    let src = dir.path().join("src.safetensors");
    let dst = dir.path().join("dst.safetensors");
    write_f32(&src, &[1.0, 2.0, 3.0]);
    convert(&src, &dst, false).unwrap();

    let mut buffer = std::fs::read(&dst).unwrap();
    *buffer.last_mut().unwrap() ^= 0x01;
    std::fs::write(&dst, buffer).unwrap();

    assert!(verify(&src, &dst).is_err());
}
