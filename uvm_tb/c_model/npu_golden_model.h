#ifndef NPU_GOLDEN_MODEL_H
#define NPU_GOLDEN_MODEL_H

#include <cstdint>

void npu_matmul_4x4_plain(const int8_t a[16],
                          const int8_t b[16],
                          uint16_t pe_mask,
                          int32_t c[16]);

#endif
