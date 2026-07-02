function kc705_generate_demo_mem(outDir)
%KC705_GENERATE_DEMO_MEM Regenerate the Cortex-M0/NPU demo memory image.
if nargin < 1 || strlength(string(outDir)) == 0
    outDir = fullfile(repo_root(), "fpga", "vivado", "mem");
end
if ~isfolder(outDir)
    mkdir(outDir);
end

words = containers.Map("KeyType", "double", "ValueType", "char");
program = [
    "00001000"
    "00000009"
    "491e481d"
    "491e6081"
    "491e60c1"
    "491e6101"
    "21006141"
    "210162c1"
    "21036301"
    "68416001"
    "40112202"
    "d0fa2900"
    "6b414a18"
    "69c36051"
    "6a036093"
    "6b0360d3"
    "49156113"
    "e7fe6011"
];
for idx = 1:numel(program)
    words(idx - 1) = char(program(idx));
end

literalBase = hex2dec("20");
literals = ["10000000", "00000100", "00000200", "00000300", "0000ffff", "00000400", "cafe0001"];
for idx = 1:numel(literals)
    words(literalBase + idx - 1) = char(literals(idx));
end

aBase = hex2dec("100") / 4;
bBase = hex2dec("200") / 4;
resultBase = hex2dec("400") / 4;
aWords = ["04030201", "020100ff", "0100fe05", "02fd0103"];
bWords = ["ff020001", "03000102", "000104ff", "0103fe00"];
for idx = 1:numel(aWords)
    words(aBase + idx - 1) = char(aWords(idx));
    words(bBase + idx - 1) = char(bWords(idx));
end
for idx = 0:4
    words(resultBase + idx) = char("00000000");
end

memPath = fullfile(outDir, "cortex_m0_npu_demo.mem");
fid = fopen(memPath, "w");
cleanup = onCleanup(@() fclose(fid));
addresses = sort(cell2mat(keys(words)));
lastAddress = -2;
for idx = 1:numel(addresses)
    address = addresses(idx);
    if address ~= lastAddress + 1
        fprintf(fid, "@%08x\n", address);
    end
    fprintf(fid, "%s\n", words(address));
    lastAddress = address;
end

expected = struct();
expected.a_base = "0x00000100";
expected.b_base = "0x00000200";
expected.c_base = "0x00000300";
expected.result_base = "0x00000400";
expected.done_sentinel = "0xcafe0001";
expected.c_matrix_int32 = [2, 6, 17, 9, -2, 0, 5, 3, 1, -4, 13, -10, 8, -15, 9, 2];
expected.min_peak_mtops = 1000;
expected.expected_dma_read_beats = 8;
expected.expected_dma_write_beats = 16;
expected.min_dma_util_percent = 80;
jsonPath = fullfile(outDir, "cortex_m0_npu_expected.json");
fidJson = fopen(jsonPath, "w");
jsonCleanup = onCleanup(@() fclose(fidJson));
fprintf(fidJson, "%s\n", jsonencode(expected, "PrettyPrint", true));

fprintf("Generated %s\n", memPath);
fprintf("Generated %s\n", jsonPath);
end

function root = repo_root()
thisFile = mfilename("fullpath");
root = fullfile(fileparts(thisFile), "..", "..");
root = char(java.io.File(root).getCanonicalPath());
end
