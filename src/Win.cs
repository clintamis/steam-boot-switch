using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

internal static class Win {
    internal sealed class Window {
        public IntPtr Handle; public string Title; public string Name;
        public int Left,Top,Right,Bottom;
    }
    // Cache short-lived PID names instead of opening every visible process on every
    // 250 ms Big Picture scan. Refresh names explicitly for game-safety decisions.
    private sealed class CachedName { public string Value; public DateTime Until; }
    private static readonly Dictionary<uint,CachedName> NameCache=new Dictionary<uint,CachedName>();
    private static DateTime nextCachePrune=DateTime.MinValue;
    private static readonly HashSet<string> SafeFullscreenNames=new HashSet<string>(
        new string[]{"steam","steamwebhelper","explorer","searchhost","applicationframehost",
            "shellexperiencehost","textinputhost","startmenuexperiencehost","runtimebroker",
            "lockapp","systemsettings","widgetservice","widgets","dwm","screenclippinghost",
            "chatgpt","taskmgr","securityhealthsystray","chrome","msedge","firefox","brave","opera","vivaldi"},
        StringComparer.OrdinalIgnoreCase);
    private static string GetProcessName(uint pid,bool fresh) {
        DateTime now=DateTime.UtcNow;
        CachedName entry;
        if(!fresh && NameCache.TryGetValue(pid,out entry) && entry.Until>now) return entry.Value;
        string name="";
        try { using(Process p=Process.GetProcessById((int)pid)) name=p.ProcessName.ToLowerInvariant(); }
        catch { NameCache.Remove(pid); return ""; }
        NameCache[pid]=new CachedName{Value=name,Until=now.AddSeconds(2)};
        if(now>=nextCachePrune){
            var stale=new List<uint>();
            foreach(var pair in NameCache) if(pair.Value.Until<=now)stale.Add(pair.Key);
            foreach(uint key in stale)NameCache.Remove(key);
            nextCachePrune=now.AddSeconds(30);
        }
        return name;
    }
    private delegate bool EnumWindowCallback(IntPtr h,IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)] private struct Rect {public int Left,Top,Right,Bottom;}
    [StructLayout(LayoutKind.Sequential)] private struct LastInputInfo {public uint cbSize;public uint dwTime;}
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowCallback callback,IntPtr param);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr h,StringBuilder builder,int max);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] private static extern int GetWindowThreadProcessId(IntPtr h,out uint pid);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h,out Rect r);
    [DllImport("user32.dll")] private static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h,int action);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
    [DllImport("user32.dll")] private static extern bool GetLastInputInfo(ref LastInputInfo info);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    private static readonly Dictionary<IntPtr,Config> PendingLayout=new Dictionary<IntPtr,Config>();
    internal const uint QuietHideFlags=0x0080|0x0010|0x0004|0x0002|0x0001;
    public static long LastInputTick() {
        LastInputInfo info=new LastInputInfo();info.cbSize=(uint)Marshal.SizeOf(typeof(LastInputInfo));
        return GetLastInputInfo(ref info)?(long)info.dwTime:-1L;
    }
    public static List<Window> Scan() {return Scan(false);}
    public static List<Window> Scan(bool freshProcessNames) {
        List<Window> found=new List<Window>();
        // Keep the delegate rooted across this synchronous native enumeration.
        EnumWindowCallback cb=delegate(IntPtr h,IntPtr ignored){
            if(!IsWindowVisible(h))return true;
            int n=GetWindowTextLength(h);if(n<1 || n>2048)return true;
            var b=new StringBuilder(n+2);GetWindowText(h,b,b.Capacity);
            uint pid;GetWindowThreadProcessId(h,out pid);
            string name=GetProcessName(pid,freshProcessNames);
            Rect r;
            if(!GetWindowRect(h,out r))return true;
            found.Add(new Window {Handle=h,Title=b.ToString(),Name=name,Left=r.Left,Top=r.Top,Right=r.Right,Bottom=r.Bottom});
            return true;
        };
        EnumWindows(cb,IntPtr.Zero);GC.KeepAlive(cb);
        return found;
    }
    public static bool BigPicture(List<Window> ws) {
        foreach(var w in ws)if((w.Name=="steam"||w.Name=="steamwebhelper")&&
            w.Title.IndexOf("big picture",StringComparison.OrdinalIgnoreCase)>=0)return true;
        return false;
    }
    private static bool IsSteamDesktop(Window w){
        if(w.Name!="steam"&&w.Name!="steamwebhelper")return false;
        if(w.Title.IndexOf("big picture",StringComparison.OrdinalIgnoreCase)>=0)return false;
        return w.Title=="Steam"||w.Title.StartsWith("Steam -",StringComparison.OrdinalIgnoreCase)||
            w.Title.StartsWith("Steam |",StringComparison.OrdinalIgnoreCase)||w.Title.StartsWith("Steam:",StringComparison.OrdinalIgnoreCase);
    }
    public static List<IntPtr> HideDesktop(List<Window> ws,bool resize,Config c){
        return HideDesktop(ws,resize,c,delegate(IntPtr h){return SetWindowPos(h,IntPtr.Zero,0,0,0,0,QuietHideFlags);});
    }
    internal static List<IntPtr> HideDesktop(List<Window> ws,bool resize,Config c,Func<IntPtr,bool> hide){
        List<IntPtr> hidden=new List<IntPtr>();
        foreach(var w in ws){
            if(!IsSteamDesktop(w))continue;
            // Hide only: never maximize/restore/show a background Steam window.
            if(hide(w.Handle)){
                hidden.Add(w.Handle);
                if(resize)PendingLayout[w.Handle]=c;
            }
        }
        return hidden;
    }
    internal static bool CanApplyLayout(IntPtr target,IntPtr foreground){return target!=IntPtr.Zero && target==foreground;}
    internal static Config TakePendingLayout(IntPtr target,IntPtr foreground){
        Config c;
        if(!CanApplyLayout(target,foreground)||!PendingLayout.TryGetValue(target,out c))return null;
        PendingLayout.Remove(target);return c;
    }
    public static void ApplyPendingDesktopLayout(List<Window> ws){
        foreach(var w in ws){
            if(!IsSteamDesktop(w))continue;
            Config c=TakePendingLayout(w.Handle,GetForegroundWindow());
            if(c==null)continue;
            bool maximized=IsZoomed(w.Handle);
            // Only the Steam window the user has already brought forward is resized.
            {
                Screen primary=Screen.PrimaryScreen;
                Screen screen=Screen.FromHandle(w.Handle);
                if(screen.DeviceName!=primary.DeviceName){
                    int width=Math.Max(640,w.Right-w.Left),height=Math.Max(480,w.Bottom-w.Top);
                    var b=primary.WorkingArea;
                    int x=Math.Max(b.Left,Math.Min(b.Right-80,b.Left+(b.Width-width)/2));
                    int y=Math.Max(b.Top,Math.Min(b.Bottom-80,b.Top+(b.Height-height)/2));
                    SetWindowPos(w.Handle,IntPtr.Zero,x,y,width,height,0x0014);
                }
                if(!CanApplyLayout(w.Handle,GetForegroundWindow()))continue;
                if(c.windowSizeMode=="Maximize")ShowWindow(w.Handle,3);
                else if(c.windowSizeMode=="Custom"){
                    if(maximized)ShowWindow(w.Handle,9);
                    var b=primary.WorkingArea;
                    SetWindowPos(w.Handle,IntPtr.Zero,b.Left+(b.Width-c.windowWidth)/2,
                        b.Top+(b.Height-c.windowHeight)/2,c.windowWidth,c.windowHeight,0x0014);
                }
            }
        }
        var stale=new List<IntPtr>();
        foreach(var h in PendingLayout.Keys)if(!IsWindow(h))stale.Add(h);
        foreach(var h in stale)PendingLayout.Remove(h);
    }
    public static void RestoreHidden(IEnumerable<IntPtr> handles){
        foreach(var h in handles)if(IsWindow(h))ShowWindow(h,4); // SW_SHOWNOACTIVATE
    }
    public static bool IsFullScreen(Window w){
        foreach(var screen in Screen.AllScreens){var b=screen.Bounds;
            if(Math.Abs(w.Left-b.Left)<=4&&Math.Abs(w.Top-b.Top)<=4&&
               Math.Abs(w.Right-b.Right)<=4&&Math.Abs(w.Bottom-b.Bottom)<=4)return true;}
        return false;
    }
    public static bool IsAllowedFullScreen(string name){
        return SafeFullscreenNames.Contains(name);
    }
}
