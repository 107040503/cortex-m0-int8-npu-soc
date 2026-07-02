import gzip
import math
import struct
import time
import urllib.request
from pathlib import Path


DATA_DIR = Path("data/mnist")
REPORT = Path("docs/mnist_accuracy_report.md")
BASE_URLS = [
    "https://storage.googleapis.com/cvdf-datasets/mnist/",
    "https://ossci-datasets.s3.amazonaws.com/mnist/",
]
FILES = {
    "train_images": "train-images-idx3-ubyte.gz",
    "train_labels": "train-labels-idx1-ubyte.gz",
    "test_images": "t10k-images-idx3-ubyte.gz",
    "test_labels": "t10k-labels-idx1-ubyte.gz",
}
IMAGE_SIZE = 28 * 28


def download_file(name):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    path = DATA_DIR / name
    if path.exists() and path.stat().st_size > 0:
        return path

    last_error = None
    for base in BASE_URLS:
        url = base + name
        try:
            print(f"Downloading {url}", flush=True)
            req = urllib.request.Request(url, headers={"User-Agent": "codex-mnist-eval"})
            with urllib.request.urlopen(req, timeout=30) as response:
                with path.open("wb") as f:
                    while True:
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        f.write(chunk)
            if path.stat().st_size == 0:
                raise RuntimeError("downloaded file is empty")
            return path
        except Exception as exc:
            last_error = exc
            if path.exists():
                path.unlink()
    raise RuntimeError(f"Unable to download {name}: {last_error}")


def read_images(path):
    with gzip.open(path, "rb") as f:
        magic, count, rows, cols = struct.unpack(">IIII", f.read(16))
        if magic != 2051:
            raise ValueError(f"Bad image magic {magic} in {path}")
        data = f.read()
    if len(data) != count * rows * cols:
        raise ValueError(f"Bad image payload length in {path}")
    return count, rows * cols, data


def read_labels(path):
    with gzip.open(path, "rb") as f:
        magic, count = struct.unpack(">II", f.read(8))
        if magic != 2049:
            raise ValueError(f"Bad label magic {magic} in {path}")
        data = f.read()
    if len(data) != count:
        raise ValueError(f"Bad label payload length in {path}")
    return count, data


def train_centroids(image_count, images, labels):
    sums = [[0 for _ in range(IMAGE_SIZE)] for _ in range(10)]
    counts = [0 for _ in range(10)]

    for img_idx in range(image_count):
        label = labels[img_idx]
        counts[label] += 1
        base = img_idx * IMAGE_SIZE
        cls_sums = sums[label]
        for pix_idx in range(IMAGE_SIZE):
            cls_sums[pix_idx] += images[base + pix_idx] - 128

    centroids = [[0 for _ in range(IMAGE_SIZE)] for _ in range(10)]
    max_abs = 1
    for cls in range(10):
        denom = counts[cls]
        for pix_idx in range(IMAGE_SIZE):
            value = sums[cls][pix_idx] / denom
            centroids[cls][pix_idx] = value
            max_abs = max(max_abs, abs(value))

    scale = max_abs / 127.0
    weights = [[0 for _ in range(IMAGE_SIZE)] for _ in range(10)]
    bias = [0 for _ in range(10)]
    for cls in range(10):
        norm2 = 0
        for pix_idx in range(IMAGE_SIZE):
            q = int(round(centroids[cls][pix_idx] / scale))
            if q < -128:
                q = -128
            if q > 127:
                q = 127
            weights[cls][pix_idx] = q
            norm2 += q * q
        bias[cls] = -norm2 // 2
    return weights, bias, scale


def infer_one(image, weights, bias):
    best_cls = 0
    best_score = None
    for cls in range(10):
        score = bias[cls]
        w = weights[cls]
        for pix_idx in range(IMAGE_SIZE):
            score += (image[pix_idx] - 128) * w[pix_idx]
        if best_score is None or score > best_score:
            best_score = score
            best_cls = cls
    return best_cls


def evaluate(test_count, test_images, test_labels, weights, bias):
    correct = 0
    start = time.perf_counter()
    for img_idx in range(test_count):
        base = img_idx * IMAGE_SIZE
        pred = infer_one(test_images[base:base + IMAGE_SIZE], weights, bias)
        if pred == test_labels[img_idx]:
            correct += 1
    elapsed = time.perf_counter() - start
    return correct, elapsed


def estimate_npu_cycles(num_images):
    clock_mhz = 200
    tiles_per_image = math.ceil(1 / 4) * math.ceil(784 / 4) * math.ceil(10 / 4)
    cycles_per_tile = 11 + 28
    cycles = num_images * tiles_per_image * cycles_per_tile
    time_s = cycles / (clock_mhz * 1_000_000)
    fps = num_images / time_s
    return tiles_per_image, cycles, time_s, fps


def main():
    paths = {key: download_file(name) for key, name in FILES.items()}
    train_count, train_size, train_images = read_images(paths["train_images"])
    train_label_count, train_labels = read_labels(paths["train_labels"])
    test_count, test_size, test_images = read_images(paths["test_images"])
    test_label_count, test_labels = read_labels(paths["test_labels"])

    if train_size != IMAGE_SIZE or test_size != IMAGE_SIZE:
        raise ValueError("Only 28x28 MNIST images are supported")
    if train_count != train_label_count or test_count != test_label_count:
        raise ValueError("Image/label count mismatch")

    print("Training INT8 centroid classifier...", flush=True)
    weights, bias, scale = train_centroids(train_count, train_images, train_labels)
    print("Evaluating official MNIST test set...", flush=True)
    correct, sw_elapsed = evaluate(test_count, test_images, test_labels, weights, bias)
    accuracy = correct / test_count
    tiles_per_image, cycles, hw_time_s, hw_fps = estimate_npu_cycles(test_count)

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# MNIST INT8 Accuracy Report",
        "",
        "This report uses the official MNIST IDX test set and a reproducible INT8 centroid classifier.",
        "The classifier performs inference as INT8 matrix-style dot products, matching the NPU GEMM data path.",
        "",
        "## Dataset",
        "",
        f"- Train images: {train_count}",
        f"- Test images: {test_count}",
        "- Source: official MNIST IDX gzip files mirrored by Google/S3",
        "",
        "## Accuracy",
        "",
        f"- Correct predictions: {correct}/{test_count}",
        f"- INT8 centroid classifier accuracy: {accuracy * 100:.2f}%",
        f"- Software INT8 inference time for {test_count} images: {sw_elapsed:.4f} s",
        f"- Software throughput: {test_count / sw_elapsed:.1f} images/s",
        f"- Weight quantization scale: {scale:.6f}",
        "",
        "## RTL/NPU Performance Mapping",
        "",
        f"- Tiles per image: {tiles_per_image}",
        f"- Estimated total RTL cycles for {test_count} images: {cycles}",
        f"- Estimated RTL time at 200 MHz: {hw_time_s:.6f} s",
        f"- Estimated RTL throughput: {hw_fps:.1f} FPS",
        "",
        "## Notes",
        "",
        "This is a real standard-dataset accuracy run without external ML packages.",
        "A trained CNN/MLP would improve accuracy and can reuse the same INT8 matrix-multiply verification path.",
    ]
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Generated {REPORT}")
    print(f"MNIST INT8 accuracy: {accuracy * 100:.2f}%")
    print(f"Estimated RTL throughput: {hw_fps:.1f} FPS")


if __name__ == "__main__":
    main()
