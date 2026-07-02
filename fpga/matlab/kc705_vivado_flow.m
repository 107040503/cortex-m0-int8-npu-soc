function kc705_vivado_flow(action)
%KC705_VIVADO_FLOW MATLAB entrypoint for the KC705 Vivado automation.
if nargin < 1 || strlength(string(action)) == 0
    action = "check";
end
action = lower(string(action));

switch action
    case "check"
        runPowerShell("check_kc705_env.ps1", "");
        ver;
    case "gen_mem"
        kc705_generate_demo_mem();
    case {"setup", "synth", "impl", "program", "capture", "gui"}
        runPowerShell("run_vivado_kc705.ps1", "-Action " + action);
    case "summarize_reports"
        kc705_summarize_reports();
    otherwise
        error("Unknown action: %s", action);
end
end

function runPowerShell(scriptName, args)
root = repo_root();
scriptPath = fullfile(root, "scripts", scriptName);
if ~isfile(scriptPath)
    error("Script not found: %s", scriptPath);
end
cmd = sprintf('powershell -ExecutionPolicy Bypass -File "%s" %s', scriptPath, args);
status = system(cmd);
if status ~= 0
    error("Command failed with exit code %d: %s", status, cmd);
end
end

function root = repo_root()
thisFile = mfilename("fullpath");
root = fullfile(fileparts(thisFile), "..", "..");
root = char(java.io.File(root).getCanonicalPath());
end
