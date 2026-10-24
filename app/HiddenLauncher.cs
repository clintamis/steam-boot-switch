// Windows-subsystem launcher for a background watcher under Task Scheduler.
// IMPORTANT: the launcher must stay alive while the PowerShell watcher runs.
// Task Scheduler may supervise the launched process tree; exiting immediately
// can leave a successful task result even when the watcher disappears.
using System;
using System.Diagnostics;
using System.IO;

class HiddenLauncher {
    // Bootstrap launcher for Steam Boot Switch v1.0.0.
    private static readonly object Gate = new object();
    private static string folder;
    private static void Log(string message) {
        try {
            lock (Gate) {
                string log = Path.Combine(folder, "launcher.log");
                if (File.Exists(log) && new FileInfo(log).Length >= 524288) {
                    string one = log + ".1", two = log + ".2";
                    if (File.Exists(two)) File.Delete(two);
                    if (File.Exists(one)) File.Move(one, two);
                    File.Move(log, one);
                }
                File.AppendAllText(log, DateTime.Now.ToString("s") + " " + message + Environment.NewLine);
            }
        } catch { }
    }
    [STAThread]
    static void Main(string[] args) {
        folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SteamControllerBootMode");
        try {
            string watcher = Path.Combine(folder, "SteamControllerBootMode.ps1");
            if (!File.Exists(watcher)) { Log("ERROR: Watcher script missing: " + watcher); Environment.ExitCode = 2; return; }
            string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(ps)) { Log("ERROR: Windows PowerShell missing: " + ps); Environment.ExitCode = 3; return; }
            bool monitorOnly = args.Length > 0 && args[0].Equals("MonitorOnly", StringComparison.OrdinalIgnoreCase);
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = ps;
            info.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + watcher + "\"" + (monitorOnly ? " -MonitorOnly" : "");
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.WindowStyle = ProcessWindowStyle.Hidden;
            info.WorkingDirectory = folder;
            info.RedirectStandardError = true;
            info.RedirectStandardOutput = true;
            Log("LAUNCH: " + info.Arguments);
            using (Process child = new Process()) {
                child.StartInfo = info;
                child.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) {
                    if (e.Data != null) Log("POWERSHELL ERROR: " + e.Data);
                };
                child.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) {
                    if (e.Data != null) Log("POWERSHELL OUTPUT: " + e.Data);
                };
                if (!child.Start()) { Log("ERROR: Process.Start returned false"); Environment.ExitCode = 4; return; }
                Log("WATCHER PID: " + child.Id);
                child.BeginErrorReadLine();
                child.BeginOutputReadLine();
                child.WaitForExit(); // Keep scheduled task alive while watcher is running.
                Log("WATCHER EXIT: " + child.ExitCode);
                Environment.ExitCode = child.ExitCode;
            }
        } catch (Exception error) {
            Log("LAUNCHER ERROR: " + error.ToString());
            Environment.ExitCode = 1;
        }
    }
}
