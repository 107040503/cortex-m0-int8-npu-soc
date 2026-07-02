function summary = kc705_summarize_reports(reportsDir)
%KC705_SUMMARIZE_REPORTS Extract a compact JSON summary from Vivado reports.
if nargin < 1 || strlength(string(reportsDir)) == 0
    reportsDir = fullfile(repo_root(), "fpga", "vivado", "reports");
end

summary = struct();
summary.reports_dir = string(reportsDir);
summary.synth_timing_summary = parseTiming(fullfile(reportsDir, "synth_timing_summary.rpt"));
summary.impl_timing_summary = parseTiming(fullfile(reportsDir, "impl_timing_summary.rpt"));
summary.synth_utilization = parseUtilization(fullfile(reportsDir, "synth_utilization.rpt"));
summary.impl_utilization = parseUtilization(fullfile(reportsDir, "impl_utilization.rpt"));

outPath = fullfile(reportsDir, "kc705_summary.json");
if ~isfolder(reportsDir)
    mkdir(reportsDir);
end
fid = fopen(outPath, "w");
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s\n", jsonencode(summary, "PrettyPrint", true));
fprintf("Wrote %s\n", outPath);
end

function timing = parseTiming(path)
timing = struct("path", string(path), "exists", isfile(path), "wns", NaN, "tns", NaN);
if ~isfile(path)
    return;
end
text = fileread(path);
match = regexp(text, ...
    "(?m)^\s*([-+]?\d+\.?\d*)\s+([-+]?\d+\.?\d*)\s+\d+\s+\d+\s+[-+]?\d+\.?\d*\s+[-+]?\d+\.?\d*", ...
    "tokens", "once");
if ~isempty(match)
    timing.wns = str2double(match{1});
    timing.tns = str2double(match{2});
end
end

function util = parseUtilization(path)
util = struct("path", string(path), "exists", isfile(path), "slice_lut", NaN, "slice_registers", NaN, "block_ram_tile", NaN, "dsp", NaN);
if ~isfile(path)
    return;
end
text = fileread(path);
util.slice_lut = firstToken(text, "\|\s*Slice LUTs\*?\s*\|\s*([0-9,]+)");
util.slice_registers = firstToken(text, "\|\s*Slice Registers\s*\|\s*([0-9,]+)");
util.block_ram_tile = firstToken(text, "\|\s*Block RAM Tile\s*\|\s*([0-9,]+)");
util.dsp = firstToken(text, "\|\s*DSPs\s*\|\s*([0-9,]+)");
end

function value = firstToken(text, pattern)
match = regexp(text, pattern, "tokens", "once");
if isempty(match)
    value = NaN;
else
    value = str2double(strrep(match{1}, ",", ""));
end
end

function root = repo_root()
thisFile = mfilename("fullpath");
root = fullfile(fileparts(thisFile), "..", "..");
root = char(java.io.File(root).getCanonicalPath());
end
