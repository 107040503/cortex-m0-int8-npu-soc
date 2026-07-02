#include "npu_golden_model.h"

void npu_matmul_4x4_plain(const int8_t a[16],
                          const int8_t b[16],
                          uint16_t pe_mask,
                          int32_t c[16]) {
    for (int row = 0; row < 4; ++row) {
        for (int col = 0; col < 4; ++col) {
            const int idx = row * 4 + col;
            int32_t acc = 0;
            for (int k = 0; k < 4; ++k) {
                acc += static_cast<int32_t>(a[row * 4 + k]) *
                       static_cast<int32_t>(b[k * 4 + col]);
            }
            c[idx] = (pe_mask & (1u << idx)) ? acc : 0;
        }
    }
}

#ifdef NPU_DPI_BUILD
#include "svdpi.h"

static int8_t read_i8(const svOpenArrayHandle arr, int index) {
    const signed char *ptr =
        static_cast<const signed char *>(svGetArrElemPtr1(arr, index));
    return ptr == nullptr ? 0 : static_cast<int8_t>(*ptr);
}

static void write_i32(const svOpenArrayHandle arr, int index, int32_t value) {
    int *ptr = static_cast<int *>(svGetArrElemPtr1(arr, index));
    if (ptr != nullptr) {
        *ptr = static_cast<int>(value);
    }
}

extern "C" void npu_matmul_4x4_ref(const svOpenArrayHandle a_handle,
                                    const svOpenArrayHandle b_handle,
                                    unsigned short pe_mask,
                                    const svOpenArrayHandle c_handle) {
    int8_t a[16];
    int8_t b[16];
    int32_t c[16];

    for (int i = 0; i < 16; ++i) {
        a[i] = read_i8(a_handle, i);
        b[i] = read_i8(b_handle, i);
    }

    npu_matmul_4x4_plain(a, b, pe_mask, c);

    for (int i = 0; i < 16; ++i) {
        write_i32(c_handle, i, c[i]);
    }
}
#endif
