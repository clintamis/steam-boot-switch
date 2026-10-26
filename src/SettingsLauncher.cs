// Minimal Windows GUI entry point for Steam Boot Switch settings.
// It only starts the WPF settings process on demand. No resident process or polling.
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Settings.ps1");
        if (!File.Exists(script)) {
            MessageBox.Show("Settings files are missing. Run Steam Boot Switch Setup again to repair the installation.", "Steam Boot Switch");
            return 2;
        }
        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            @"System32\WindowsPowerShell\v1.0\powershell.exe");
        if (!File.Exists(ps)) ps = "powershell.exe";
        var info = new ProcessStartInfo();
        info.FileName = ps;
        info.Arguments = "-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" +
            script.Replace("\"", "") + "\"";
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        try
        {
            using (var child = Process.Start(info))
            {
                if (child == null) return 3;
                return 0; // GUI owns its lifetime, launcher closes immediately.
            }
        }
        catch (Exception)
        {
            MessageBox.Show("Settings could not start. Check that Windows PowerShell is available, or run Setup again to repair the installation.", "Steam Boot Switch");
            return 4;
        }
    }
}
