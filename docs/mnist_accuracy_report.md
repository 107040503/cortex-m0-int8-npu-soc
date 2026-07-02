# MNIST INT8 Accuracy Report

This report uses the official MNIST IDX test set and a reproducible INT8 centroid classifier.
The classifier performs inference as INT8 matrix-style dot products, matching the NPU GEMM data path.

## Dataset

- Train images: 60000
- Test images: 10000
- Source: official MNIST IDX gzip files mirrored by Google/S3

## Accuracy

- Correct predictions: 8201/10000
- INT8 centroid classifier accuracy: 82.01%
- Software INT8 inference time for 10000 images: 5.1793 s
- Software throughput: 1930.7 images/s
- Weight quantization scale: 1.007874

## RTL/NPU Performance Mapping

- Tiles per image: 588
- Estimated total RTL cycles for 10000 images: 229320000
- Estimated RTL time at 200 MHz: 1.146600 s
- Estimated RTL throughput: 8721.4 FPS

## Notes

This is a real standard-dataset accuracy run without external ML packages.
A trained CNN/MLP would improve accuracy and can reuse the same INT8 matrix-multiply verification path.
