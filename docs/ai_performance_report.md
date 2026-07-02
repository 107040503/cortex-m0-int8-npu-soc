# AI Performance Report

This report maps the RTL-verified 4x4 INT8 GEMM tile to a compact MNIST MLP inference workload.

## Assumptions

- RTL clock: 200 MHz
- Data type: INT8 input/weight, INT32 accumulation
- Tile size: 4x4 systolic array
- RTL tile compute cycles: 11
- RTL tile bus cycles estimate: 28
- Measured DMA burst utilization: 85%
- Peak metric register: 1024 MTOPS = 1.024 TOPS
- Accuracy note: no external MNIST dataset is bundled; accuracy should be measured after adding trained INT8 weights.

## MNIST MLP Estimate

| Layer | Shape | Tiles | Cycles | Time us | Ops |
| --- | --- | ---: | ---: | ---: | ---: |
| MNIST_FC1 | 1x784 * 784x64 | 3136 | 122304 | 611.52 | 100352 |
| MNIST_FC2 | 1x64 * 64x10 | 48 | 1872 | 9.36 | 1280 |

- Total cycles per inference: 124176
- Estimated inference time: 620.88 us
- Estimated throughput: 1610.6 FPS

## Interpretation

The report is a deterministic performance estimate derived from current RTL counters and 4x4 tiling.
For a final contest submission, add trained MNIST/CIFAR-10 INT8 weights and compare RTL results against a software golden model.
