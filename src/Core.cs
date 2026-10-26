// Steam Boot Switch native alpha 4. C# 5 / .NET Framework 4.x, Windows only.
// Only the UI/settings installer uses PowerShell; this watcher never does.
using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Collections.Generic;
using System.Threading;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;
using Microsoft.Win32;

internal sealed class Config {
    public bool autoOpenOnStartup { get; set; }
    public int startupWindowSeconds { get; set; }
    public int disconnectGraceSeconds { get; set; }
    public bool mouseActivityCancelsExit { get; set; }
    public bool cleanupSteamWindow { get; set; }
    public bool autoExitOnDisconnect { get; set; }
    public bool preHideSteamDesktop { get; set; }
    public int cleanupDelayMs { get; set; }
    public string windowSizeMode { get; set; }
    public int windowWidth { get; set; }
    public int windowHeight { get; set; }
    public bool autoPowerOffOnDock { get; set; }
    // Disabled by default for all upgrades. Accepted: Disabled, Immediate, OnConnection.
    public string undockBigPictureMode { get; set; }
    public Config() {
        autoOpenOnStartup=true;
        startupWindowSeconds=120; disconnectGraceSeconds=5;
        mouseActivityCancelsExit=true; cleanupSteamWindow=true;
        autoExitOnDisconnect=true; preHideSteamDesktop=true;
        cleanupDelayMs=0; windowSizeMode="Preserve";windowWidth=1300;windowHeight=900;
        autoPowerOffOnDock=false;undockBigPictureMode="Disabled";
    }
    public static Config Load(string path) {
        Config c=new Config();
        if (!File.Exists(path)) return c;
        c=new JavaScriptSerializer().Deserialize<Config>(File.ReadAllText(path));
        if(c!=null && c.undockBigPictureMode==null)c.undockBigPictureMode="Disabled";
        if(c==null || !UndockLaunchGate.ValidMode(c.undockBigPictureMode) || c.startupWindowSeconds<15 || c.startupWindowSeconds>600 ||
           c.disconnectGraceSeconds<1 || c.cleanupDelayMs<0 || c.cleanupDelayMs>3000 ||
           (c.windowSizeMode!="Preserve" && c.windowSizeMode!="Maximize" && c.windowSizeMode!="Custom") ||
           c.windowWidth<640 || c.windowHeight<480 || c.windowWidth>7680 || c.windowHeight>4320)
            throw new InvalidDataException("Invalid configuration. Auto-exit disabled until corrected.");
        return c;
    }
}

internal static class Log {
    private static readonly object Gate=new object();
    internal static string Root=AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
    internal static string Watcher=Path.Combine(Root,"watcher.log");
    private static readonly Encoding Utf8NoBom=new UTF8Encoding(false);
    public static void Write(string message) {
        lock(Gate) try {
            Directory.CreateDirectory(Root);
            if(File.Exists(Watcher) && new FileInfo(Watcher).Length>=524288) {
                if(File.Exists(Watcher+".2")) File.Delete(Watcher+".2");
                if(File.Exists(Watcher+".1")) File.Move(Watcher+".1",Watcher+".2");
                File.Move(Watcher,Watcher+".1");
            }
            File.AppendAllText(Watcher,"["+DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")+"] "+message+Environment.NewLine,Utf8NoBom);
        } catch { /* no log error is allowed to kill the watcher */ }
    }
}

internal sealed class SteamLogReader {
    private readonly string path;
    private readonly DateTime minStamp;
    private int activeCount=0;
    private long connectedEvents=0;
    private bool stateTextDirty=true;
    private string cachedStates="";
    private readonly Dictionary<int,bool> states=new Dictionary<int,bool>();
    private long lastOffset=-1;
    private DateTime lastFileStamp=DateTime.MinValue;
    private string fragment="";
    private bool known=false;
    private bool missing=false;
    public SteamLogReader(string filename,DateTime bootTime) {path=filename;minStamp=bootTime.AddSeconds(-5);}
    public bool Known { get {return known && !missing;} }
    public int Count {get{return activeCount;} }
    // Monotonic accepted Steam connect transitions since this watcher started.
    // Unlike SteamEffective, it cannot increase merely from removing the Puck exclusion.
    public long ConnectedEvents {get{return connectedEvents;} }
    public string States {
        get {
            if(stateTextDirty){
                cachedStates=string.Join(", ",states.OrderBy(x=>x.Key)
                    .Select(x=>x.Key+"="+(x.Value?"ON":"OFF")).ToArray());
                stateTextDirty=false;
            }
            return cachedStates;
        }
    }
    private static DateTime ParseStamp(string line) {
        DateTime dt;
        if (line.Length<21 || line[0]!='[' || !DateTime.TryParseExact(line.Substring(1,19),"yyyy-MM-dd HH:mm:ss",
            System.Globalization.CultureInfo.InvariantCulture,System.Globalization.DateTimeStyles.None,out dt)) return DateTime.MinValue;
        return dt;
    }
    private void Accept(string line) {
        DateTime dt=ParseStamp(line);
        if(dt<minStamp) return;
        // Exact Steam UI event prefix; gamepad slot IDs can be reused after reboot.
        int pos=line.IndexOf("Controller ",StringComparison.OrdinalIgnoreCase);
        if(pos<0) return;
        string rest=line.Substring(pos+11);
        int end=rest.IndexOf(' ');
        int slot;
        if(end<1 || end>4 || !int.TryParse(rest.Substring(0,end),out slot) || slot<0 || slot>64) return;
        string eventText=rest.Substring(end+1);
        bool connected;
        if(eventText.StartsWith("connected",StringComparison.OrdinalIgnoreCase))connected=true;
        else if(eventText.StartsWith("disconnected",StringComparison.OrdinalIgnoreCase))connected=false;
        else return;
        bool previous;
        bool hadPrevious=states.TryGetValue(slot,out previous);
        if(connected && (!hadPrevious || !previous))connectedEvents++;
        if(hadPrevious){
            if(previous!=connected)activeCount+=connected?1:-1;
        }else if(connected)activeCount++;
        states[slot]=connected;
        stateTextDirty=true;
        known=true;
    }
    public void Update() {
        if(!File.Exists(path)) {missing=true;return;}
        try {
            using(FileStream fs=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)) {
                DateTime stamp=File.GetCreationTimeUtc(path);
                if(lastOffset<0 || fs.Length<lastOffset || stamp!=lastFileStamp) {
                    // Only the tail once; subsequent reads consume appended bytes.
                    states.Clear();activeCount=0;stateTextDirty=true;known=false;fragment="";
                    lastOffset=Math.Max(0,fs.Length-262144);
                    lastFileStamp=stamp;
                    fs.Seek(lastOffset,SeekOrigin.Begin);
                    if(lastOffset>0) {int b;while((b=fs.ReadByte())>=0){lastOffset++;if(b==10)break;}}
                }
                long delta=fs.Length-lastOffset;
                if(delta<=0){missing=false;return;}
                if(delta>1048576) {lastOffset=-1;missing=true;return;}
                fs.Seek(lastOffset,SeekOrigin.Begin);
                byte[] bytes=new byte[(int)delta];int read=0;
                while(read<bytes.Length) {int r=fs.Read(bytes,read,bytes.Length-read);if(r==0)break;read+=r;}
                lastOffset+=read;
                string combined=fragment+Encoding.UTF8.GetString(bytes,0,read);
                string[] lines=combined.Split('\n');
                for(int j=0;j<lines.Length-1;j++)Accept(lines[j].TrimEnd('\r'));
                fragment=lines[lines.Length-1];if(fragment.Length>8192)fragment="";
                missing=false;
            }
        } catch {missing=true;}
    }
}

internal sealed class GameGuard {
    private readonly string file;
    public GameGuard(string steamFolder) {file=Path.Combine(steamFolder,"logs","gameprocess_log.txt");}
    private sealed class TrackedGame {
        public string App; public DateTime Added;
    }
    private static DateTime? RunningSince(int pid) {
        try {using(Process p=Process.GetProcessById(pid))return p.HasExited?(DateTime?)null:p.StartTime;}
        catch(ArgumentException){return null;} // The process has exited.
        // Access failures propagate: unknown game state must not authorize an action.
    }
    public string UnsafeReason() {
        if(!File.Exists(file))return "Steam game process log missing";
        try {
            // Read from the beginning: tail-only reads can miss a long-running game's launch.
            using(FileStream fs=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)) {
                if(fs.Length>16777216)return "Steam game process log too large to verify safely";
                using(StreamReader sr=new StreamReader(fs)) {
                    return ReadSteamGames(sr,RunningSince);
                }
            }
        }catch{return "Steam game process log unreadable";}
    }
    // No window geometry or overlay-process heuristic: only Steam-tracked processes.
    internal static string ReadSteamGames(TextReader reader,Func<int,DateTime?> runningSince) {
        var tracked=new Dictionary<int,TrackedGame>();
        string line;
        while((line=reader.ReadLine())!=null) {
            var add=System.Text.RegularExpressions.Regex.Match(line,@"AppID\s+(\d+)\s+adding PID\s+(\d+)\s+as a tracked process");
            if(add.Success){
                int pid; DateTime stamp;
                if(!int.TryParse(add.Groups[2].Value,out pid) || pid<=0 || line.Length<21 || line[0]!='[' ||
                   !DateTime.TryParseExact(line.Substring(1,19),"yyyy-MM-dd HH:mm:ss",
                       System.Globalization.CultureInfo.InvariantCulture,System.Globalization.DateTimeStyles.None,out stamp))
                    return "Steam game process entry could not be verified";
                tracked[pid]=new TrackedGame{App=add.Groups[1].Value,Added=stamp};
                continue;
            }
            var del=System.Text.RegularExpressions.Regex.Match(line,@"(?:AppID|Game)\s+(\d+)(?:\s+going away;)?\s+no longer tracking PID\s+(\d+)");
            if(del.Success){
                int pid; TrackedGame prior;
                if(int.TryParse(del.Groups[2].Value,out pid) && tracked.TryGetValue(pid,out prior) && prior.App==del.Groups[1].Value)tracked.Remove(pid);
            } else if(line.Contains("adding PID") || line.Contains("no longer tracking PID")) {
                return "Unrecognized Steam game process entry";
            }
        }
        foreach(var pair in tracked) {
            try {
                DateTime? since=runningSince(pair.Key);
                // Log timestamps have one-second precision. A later start means PID reuse.
                if(since.HasValue && since.Value<=pair.Value.Added.AddSeconds(2))
                    return "Steam game PID "+pair.Key+" running (AppID "+pair.Value.App+")";
            }catch{return "Steam-tracked process could not be verified (PID "+pair.Key+")";}
        }
        return null;
    }
}

internal sealed class PuckSupervisor : IDisposable {
    private Process proc;
    private readonly string exe;
    private readonly bool powerOff;
    private DateTime lastReceived=DateTime.MinValue;
    private DateTime lastRestart=DateTime.MinValue;
    private DateTime lastFaultLog=DateTime.MinValue;
    private readonly object gate=new object();
    private string state="UNKNOWN";
    private int consecutiveDock=0;
    private int consecutiveNoDock=0;
    private DateTime lastDock=DateTime.MinValue;
    private string lastObserved="";
    private string lastHardwareState="UNKNOWN";
    private int workerGeneration=0;
    private long sampleNumber=0;
    public PuckSupervisor(string exePath,bool autoShutdown){exe=exePath;powerOff=autoShutdown;}
    private void OnLine(object sender,DataReceivedEventArgs e){
        if(e.Data==null || !Object.ReferenceEquals(sender,proc))return;
        string[] p=e.Data.Split('|');
        if(p.Length>=3 && p[0]=="PUCK"){
            lock(gate){
                lastReceived=DateTime.UtcNow;
                if(p[1]=="DOCK") {consecutiveDock++;consecutiveNoDock=0;lastDock=DateTime.UtcNow;}
                else if(p[1]=="NO_DOCK") {consecutiveNoDock++;consecutiveDock=0;}
                else {consecutiveDock=0;consecutiveNoDock=0;}
                state=p[1];
                lastHardwareState=p[2];
                sampleNumber++;
                if(state!=lastObserved){Log.Write("PUCK NATIVE: "+state+"; "+p[2]);lastObserved=state;}
            }
        }else if(p.Length>=2 && p[0]=="EVENT") Log.Write("PUCK NATIVE EVENT: "+e.Data.Substring(6));
    }
    private void Reset(){lock(gate){
        workerGeneration++;
        state="UNKNOWN";lastHardwareState="UNKNOWN";
        lastReceived=DateTime.MinValue;consecutiveDock=0;consecutiveNoDock=0;
        lastDock=DateTime.MinValue;sampleNumber=0;
    }}
    private void Start(){
        lastRestart=DateTime.UtcNow;
        Reset();
        try{
            ProcessStartInfo psi=new ProcessStartInfo(exe,"--puck-worker"+(powerOff?" --auto-power-off":""));
            psi.UseShellExecute=false;psi.CreateNoWindow=true;psi.RedirectStandardOutput=true;psi.RedirectStandardError=true;
            proc=new Process();proc.StartInfo=psi;
            proc.OutputDataReceived+=OnLine;
            proc.ErrorDataReceived+=delegate(object sender,DataReceivedEventArgs e){if(!string.IsNullOrEmpty(e.Data))Log.Write("PUCK NATIVE STDERR: "+e.Data);};
            proc.Start();proc.BeginOutputReadLine();proc.BeginErrorReadLine();
            Log.Write("PUCK NATIVE: worker PID="+proc.Id+", autoPowerOff="+powerOff);
        }catch(Exception ex){Log.Write("PUCK NATIVE START FAILED: "+ex.Message);DisposeProcess();}
    }
    private void DisposeProcess(){
        try{if(proc!=null && !proc.HasExited)proc.Kill();}catch{}
        try{if(proc!=null)proc.Dispose();}catch{}
        proc=null;
    }
    public void Maintain(){
        bool broken=proc==null;
        if(!broken)try{broken=proc.HasExited;}catch{broken=true;}
        if(!broken)lock(gate){broken=(DateTime.UtcNow-lastReceived).TotalSeconds>9 && (DateTime.UtcNow-lastRestart).TotalSeconds>9;}
        if(broken && (DateTime.UtcNow-lastRestart).TotalSeconds>=5){
            if((DateTime.UtcNow-lastFaultLog).TotalSeconds>10){Log.Write("PUCK NATIVE: worker exited/stalled; restarting. Dock state UNKNOWN until fresh readings.");lastFaultLog=DateTime.UtcNow;}
            DisposeProcess();Start();
        }
    }
    public PuckSnapshot Snapshot(){lock(gate){return new PuckSnapshot {
        Generation=workerGeneration, Sequence=sampleNumber,
        State=state, HardwareState=lastHardwareState,
        ConsecutiveDock=consecutiveDock, ConsecutiveNoDock=consecutiveNoDock,
        Fresh=(DateTime.UtcNow-lastReceived).TotalSeconds<5.5,
        ReceivedAt=lastReceived
    };}}
    public bool Fresh {get{lock(gate){return (DateTime.UtcNow-lastReceived).TotalSeconds<5.5;}}}
    public bool Ready {get{lock(gate){return (DateTime.UtcNow-lastReceived).TotalSeconds<7 && (consecutiveDock>=2 || consecutiveNoDock>=2) && state!="UNKNOWN";}}}
    public bool Docked {get{lock(gate){return Ready && state=="DOCK" && consecutiveDock>=2;}}}
    public bool CanTrustNoDock {get{lock(gate){return Ready && state=="NO_DOCK" && consecutiveNoDock>=2;}}}
    public string State {get{lock(gate){return state;}}}
    public void Dispose(){DisposeProcess();}
}

internal static class ControllerCounts {
    public static int Effective(int raw,bool puckReady,bool docked) {
        return Math.Max(0,raw-(puckReady&&docked&&raw>0?1:0));
    }
}

// No hardware commands are made by this detector. It is an *observational*
// state machine fed only by the already-running Puck supervisor. A refusal
// is NOT proof of a physical undock; Alpha 4.3 logs candidates for validation.
internal sealed class PuckSnapshot {
    public int Generation;
    public long Sequence;
    public string State;
    public string HardwareState;
    public int ConsecutiveDock;
    public int ConsecutiveNoDock;
    public bool Fresh;
    public DateTime ReceivedAt;
}
internal sealed class PuckUndockDetector {
    private int generation=-1;
    private long lastSequence=-1;
    private bool anchored=false;
    private bool latched=false;
    private DateTime lastConfirmedDock=DateTime.MinValue;

    public string Observe(PuckSnapshot s) {
        if(s==null) return null;
        if(s.Generation!=generation){
            // On worker restarts, ignore all prior observations. In particular,
            // never interpret a post-restart refusal as a real dock-to-undock.
            generation=s.Generation;lastSequence=-1;anchored=false;latched=false;
            lastConfirmedDock=DateTime.MinValue;
        }
        if(!s.Fresh || s.State=="UNKNOWN"){
            bool wasAnchored=anchored&&!latched;
            anchored=false;lastSequence=s.Sequence;
            return wasAnchored?"ABORTED_UNKNOWN":null;
        }
        if(s.Sequence<=lastSequence)return null;
        lastSequence=s.Sequence;
        if(s.State=="DOCK"){
            if(s.ConsecutiveDock<2)return null;
            bool newlyAnchored=!anchored||latched;
            anchored=true;latched=false;lastConfirmedDock=s.ReceivedAt;
            return newlyAnchored?"DOCK_BASELINE":null;
        }
        // 'NO_CONTROL_INTERFACE' may mean the receiver was unplugged. An
        // unrecognized reply or any access error is unknown, not an undock.
        bool refused=s.State=="NO_DOCK" &&
           (s.HardwareState=="QUERY_REFUSED"||s.HardwareState=="NO_DOCK_REPLY");
        if(!refused){
            bool wasAnchored=anchored&&!latched;
            anchored=false;
            return wasAnchored?"ABORTED_UNTRUSTED":null;
        }
        if(!anchored || latched)return null;
        if(s.ConsecutiveNoDock>=3 &&
           (s.ReceivedAt-lastConfirmedDock).TotalSeconds>=2.0){
            latched=true;
            return "UNDOCK_CANDIDATE";
        }
        return null;
    }
}

// Software-only actuation gate. All actions run in Program's watcher, never in
// the Puck worker. Controller evidence is the monotonic Steam log connection
// sequence, not the dock-excluded controller count or any generic gamepad.
internal sealed class UndockLaunchGate {
    private string mode="Disabled";
    private bool dockBaseline=false, pending=false;
    private long baselineConnections=0;
    private DateTime deadline=DateTime.MinValue;
    private DateTime cooldownUntil=DateTime.MinValue;
    public static bool ValidMode(string m) {return m=="Disabled"||m=="Immediate"||m=="OnConnection";}
    public string Mode {get{return mode;}}
    public bool Pending {get{return pending;}}
    public bool ConnectionReady(bool logKnown,long currentConnections) {
        return mode!="OnConnection" || (logKnown && currentConnections>baselineConnections);
    }
    public bool SetMode(string newMode) {
        if(!ValidMode(newMode))newMode="Disabled";
        if(newMode==mode)return false;
        mode=newMode;pending=false;return true;
    }
    public void Cancel(){pending=false;}
    public void DockBaseline(long connectedEvents) {
        pending=false;dockBaseline=true;baselineConnections=connectedEvents;
    }
    public string Candidate(DateTime now) {
        if(mode=="Disabled")return "DISABLED";
        if(!dockBaseline)return "NO_BASELINE";
        if(now<cooldownUntil)return "COOLDOWN";
        pending=true;deadline=now.AddSeconds(mode=="OnConnection"?25:12);
        return mode=="OnConnection"?"WAITING_CONNECTION":"WAITING_STEAM";
    }
    // A null result means keep waiting; other results consume this candidate.
    public string Tick(DateTime now,bool puckVerifiedOffDock,bool bigPicture,
        bool steamRunning,bool steamLogKnown,long currentConnections,bool startupBusy) {
        if(!pending)return null;
        if(!puckVerifiedOffDock){pending=false;return "CANCELED_PUCK_UNCERTAIN";}
        if(bigPicture){pending=false;return "ALREADY_OPEN";}
        if(startupBusy){pending=false;return "STARTUP_OWNS_OPEN";}
        if(now>=deadline){pending=false;return "TIMED_OUT";}
        if(!ConnectionReady(steamLogKnown,currentConnections))return null;
        if(!steamRunning)return null;
        pending=false;cooldownUntil=now.AddSeconds(15);return "OPEN";
    }
}
