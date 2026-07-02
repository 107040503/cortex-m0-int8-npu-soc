#include "npu_golden_model.h"

#include <array>
#include <cstdint>
#include <iostream>

static bool check_case(const char *name,
                       const std::array<int8_t, 16> &a,
                       const std::array<int8_t, 16> &b,
                       uint16_t mask,
                       const std::array<int32_t, 16> &expected) {
    int32_t got[16] = {};
    npu_matmul_4x4_plain(a.data(), b.data(), mask, got);

    bool pass = true;
    for (int i = 0; i < 16; ++i) {
        if (got[i] != expected[i]) {
            std::cerr << "FAIL " << name << " C[" << i << "] got="
                      << got[i] << " expected=" << expected[i] << "\n";
            pass = false;
        }
    }
    if (pass) {
        std::cout << "PASS " << name << "\n";
    }
    return pass;
}

int main() {
    const std::array<int8_t, 16> a = {
        1, 2, 3, 4,
        -1, 0, 1, 2,
        5, -2, 0, 1,
        3, 1, -3, 2
    };
    const std::array<int8_t, 16> b = {
        1, 0, 2, -1,
        2, 1, 0, 3,
        -1, 4, 1, 0,
        0, -2, 3, 1
    };
    const std::array<int32_t, 16> full = {
        2, 6, 17, 9,
        -2, 0, 5, 3,
        1, -4, 13, -10,
        8, -15, 9, 2
    };
    const std::array<int32_t, 16> single = {
        2, 0, 0, 0,
        0, 0, 0, 0,
        0, 0, 0, 0,
        0, 0, 0, 0
    };

    const std::array<int8_t, 16> zero = {};
    const std::array<int32_t, 16> zero_expected = {};

    bool ok = true;
    ok &= check_case("signed_basic", a, b, 0xffff, full);
    ok &= check_case("single_pe_mask", a, b, 0x0001, single);
    ok &= check_case("zero_matrix", zero, b, 0xffff, zero_expected);

    if (!ok) {
        return 1;
    }
    std::cout << "PASS npu_golden_selftest\n";
    return 0;
}
