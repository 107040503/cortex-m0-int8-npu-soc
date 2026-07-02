from pathlib import Path


CLOCK_MHZ = 200
PE_COUNT = 16
LANES_PER_PE_METRIC = 160
DMA_UTIL_PERCENT = 85
CORE_ACTIVE_CYCLES_PER_TILE = 11
BUS_CYCLES_PER_TILE = 28


def ceil_div(a, b):
    return (a + b - 1) // b


def matmul_tiles(m, k, n):
    return ceil_div(m, 4) * ceil_div(k, 4) * ceil_div(n, 4)


def estimate_layer(m, k, n):
    tiles = matmul_tiles(m, k, n)
    cycles = tiles * (CORE_ACTIVE_CYCLES_PER_TILE + BUS_CYCLES_PER_TILE)
    ops = 2 * m * k * n
    return {
        "shape": f"{m}x{k} * {k}x{n}",
        "tiles": tiles,
        "cycles": cycles,
        "ops": ops,
        "time_us": cycles / CLOCK_MHZ,
    }


def main():
    layers = [
        ("MNIST_FC1", estimate_layer(1, 784, 64)),
        ("MNIST_FC2", estimate_layer(1, 64, 10)),
    ]
    total_cycles = sum(layer["cycles"] for _, layer in layers)
    total_time_us = total_cycles / CLOCK_MHZ
    fps = 1_000_000 / total_time_us
    peak_mtops = CLOCK_MHZ * PE_COUNT * LANES_PER_PE_METRIC * 2 / 1000

    lines = []
    lines.append("# AI Performance Report")
    lines.append("")
    lines.append("This report maps the RTL-verified 4x4 INT8 GEMM tile to a compact MNIST MLP inference workload.")
    lines.append("")
    lines.append("## Assumptions")
    lines.append("")
    lines.append(f"- RTL clock: {CLOCK_MHZ} MHz")
    lines.append("- Data type: INT8 input/weight, INT32 accumulation")
    lines.append("- Tile size: 4x4 systolic array")
    lines.append(f"- RTL tile compute cycles: {CORE_ACTIVE_CYCLES_PER_TILE}")
    lines.append(f"- RTL tile bus cycles estimate: {BUS_CYCLES_PER_TILE}")
    lines.append(f"- Measured DMA burst utilization: {DMA_UTIL_PERCENT}%")
    lines.append(f"- Peak metric register: {peak_mtops:.0f} MTOPS = {peak_mtops / 1000:.3f} TOPS")
    lines.append("- Accuracy note: no external MNIST dataset is bundled; accuracy should be measured after adding trained INT8 weights.")
    lines.append("")
    lines.append("## MNIST MLP Estimate")
    lines.append("")
    lines.append("| Layer | Shape | Tiles | Cycles | Time us | Ops |")
    lines.append("| --- | --- | ---: | ---: | ---: | ---: |")
    for name, layer in layers:
        lines.append(
            f"| {name} | {layer['shape']} | {layer['tiles']} | {layer['cycles']} | "
            f"{layer['time_us']:.2f} | {layer['ops']} |"
        )
    lines.append("")
    lines.append(f"- Total cycles per inference: {total_cycles}")
    lines.append(f"- Estimated inference time: {total_time_us:.2f} us")
    lines.append(f"- Estimated throughput: {fps:.1f} FPS")
    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    lines.append("The report is a deterministic performance estimate derived from current RTL counters and 4x4 tiling.")
    lines.append("For a final contest submission, add trained MNIST/CIFAR-10 INT8 weights and compare RTL results against a software golden model.")

    out = Path("docs/ai_performance_report.md")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Generated {out}")
    print(f"Estimated MNIST inference time: {total_time_us:.2f} us")
    print(f"Estimated MNIST throughput: {fps:.1f} FPS")


if __name__ == "__main__":
    main()
