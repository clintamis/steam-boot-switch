using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using Microsoft.Win32;

internal static class Program {
    private static string SteamFolder() {
        string path=null;
        try {using(RegistryKey k=Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam"))if(k!=null)path=k.GetValue("SteamPath") as string;}catch{}
        if(string.IsNullOrEmpty(path))try{using(RegistryKey k=Registry.LocalMachine.OpenSubKey(@"SOFTWARE\WOW6432Node\Valve\Steam"))if(k!=null)path=k.GetValue("InstallPath") as string;}catch{}
        if(!string.IsNullOrEmpty(path)&&File.Exists(Path.Combine(path,"steam.exe")))return path;
        try{foreach(Process p in Process.GetProcessesByName("steam")){try{string f=Path.GetDirectoryName(p.MainModule.FileName);if(File.Exists(Path.Combine(f,"steam.exe")))return f;}catch{}finally{p.Dispose();}}}catch{}
        path=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),"Steam");
        return File.Exists(Path.Combine(path,"steam.exe"))?path:null;
    }
    private static void Worker(bool autoPowerOff) {
        // Hosted in a separate *native executable* process so the main monitor can
        // kill/restart it if a native HidD_GetFeature call blocks indefinitely.
        // No PowerShell, no injected drivers, no background process-per-sample.
        int undocked=0,docked=0;
        bool armed=false,attempted=false;
        string steam=SteamFolder();
        GameGuard guard=steam==null?null:new GameGuard(steam);
        SteamLogReader slotEvents=null;
        int undockedSteamCount=-1;
        if(autoPowerOff && steam!=null){
            DateTime boot=DateTime.Now.AddMilliseconds(-unchecked((uint)Environment.TickCount));
            slotEvents=new SteamLogReader(Path.Combine(steam,"logs","controller_ui.txt"),boot);
        }
        while(true) {
            if(slotEvents!=null)slotEvents.Update();
            SteamPuckShutdownNative.Report report;
            try {report=SteamPuckShutdownNative.CheckDock();}
            catch(Exception ex){Console.WriteLine("PUCK|UNKNOWN|"+ex.GetType().Name);Console.Out.Flush();Thread.Sleep(1400);continue;}
            bool positive=report.DockResponseConfirmed;
            // A refused query isn't conclusive proof of undocking; it is used
            // only as a tentative baseline. A fresh positive + unique *active*
            // Puck slot must also be found before any shutdown is authorized.
            bool noDock=report.MatchingControlInterfaces==1 &&
                (report.State=="QUERY_REFUSED"||report.State=="NO_DOCK_REPLY");
            if(positive){docked++;undocked=0;}
            else if(noDock){
                undocked++;docked=0;
                // A genuine undocked baseline resets the per-dock one-shot latch.
                // If Steam starts late, retry arming until its log is known.
                if(undocked==3)attempted=false;
                if(undocked>=3 && !armed && !attempted){
                    // Record a stable, verified Steam count before docking.
                    // A false dock reply alone isn't proof a controller moved.
                    undockedSteamCount=slotEvents!=null&&slotEvents.Known?slotEvents.Count:-1;
                    armed=undockedSteamCount>=0;
                }
            }
            else{docked=0;undocked=0;armed=false;attempted=false;undockedSteamCount=-1;}
            string status=positive?"DOCK":noDock?"NO_DOCK":report.State=="NO_CONTROL_INTERFACE"?"NO_DOCK":"UNKNOWN";
            // An absent Puck is no docking trigger, but is a known no-dock
            // state for the main controller-counting logic.
            Console.WriteLine("PUCK|"+status+"|"+report.State);
            Console.Out.Flush();
            if(autoPowerOff && positive && docked>=2 && armed && !attempted){
                // Consume the only attempt for this docking cycle even on failure.
                attempted=true;armed=false;
                string reason=null;
                try {reason=guard==null?"Steam not located":guard.UnsafeReason();}
                catch(Exception ex){reason="Game-guard failed: "+ex.GetType().Name;}
                if(reason==null && (slotEvents==null || !slotEvents.Known ||
                    undockedSteamCount<0 || slotEvents.Count<=undockedSteamCount)){
                    reason="No newly connected Steam slot since the confirmed undocked baseline";
                }
                if(reason!=null)Console.WriteLine("EVENT|AUTO POWER-OFF SKIPPED: "+reason);
                else try {
                    SteamPuckShutdownNative.ShutdownReport off=SteamPuckShutdownNative.PowerOffOnceIfDocked();
                    Console.WriteLine("EVENT|AUTO POWER-OFF: "+off.State+"; "+off.Reason);
                }catch(Exception ex){Console.WriteLine("EVENT|AUTO POWER-OFF FAILED: "+ex.Message);}
                Console.Out.Flush();
            }
            // After a stable dock has been handled, reduce Puck HID enumeration
            // by ~39%. Stay at normal cadence while waiting to detect a dock.
            int pauseMs=(positive && docked>=3 && (!autoPowerOff || attempted))?2300:1400;
            Thread.Sleep(pauseMs);
        }
    }
    private static bool RequestSteamUri(string uri){
        try{Process.Start(new ProcessStartInfo(uri){UseShellExecute=true});return true;}
        catch(Exception ex){Log.Write("STEAM URI FAILED: "+ex.Message);return false;}
    }
    private static bool SteamRunning(){
        try{Process[] pp=Process.GetProcessesByName("steam");bool yes=pp.Length>0;foreach(var p in pp)p.Dispose();return yes;}
        catch{return false;}
    }
    private static void RunWatcher(bool monitorOnly){
        Config c;
        try{c=Config.Load(Path.Combine(Log.Root,"config.json"));}
        catch(Exception ex){Log.Write("INVALID CONFIG: "+ex.Message+"; using defaults but DISABLING auto-exit and power commands.");c=new Config();c.autoExitOnDisconnect=false;c.autoPowerOffOnDock=false;}
        Log.Write("Started Steam Boot Switch v1.1.0; monitorOnly="+monitorOnly+"; autoOpenOnStartup="+c.autoOpenOnStartup+"; gameGuard=steam-processes; cleanup=no-activate; undockMode="+c.undockBigPictureMode+"; autoExit="+c.autoExitOnDisconnect+
            "; autoPowerOffOnDock="+c.autoPowerOffOnDock+"; grace="+c.disconnectGraceSeconds+"s.");
        string steam=SteamFolder();
        if(steam==null){Log.Write("Steam folder unavailable, cannot safely detect sessions.");return;}
        DateTime boot=DateTime.Now;
        // On Windows the tick counter is uint32 and can wrap; the log reader
        // only accepts fresh controller events *after its own startup* for fail-safe
        // reconnect tracking. At first launch, bootstrap up to 1 day of history
        // only if the initial boot time can be retrieved.
        try{
            uint tick=unchecked((uint)Environment.TickCount);
            boot=DateTime.Now.AddMilliseconds(-tick);
        }catch{}
        SteamLogReader slots=new SteamLogReader(Path.Combine(steam,"logs","controller_ui.txt"),boot);
        GameGuard games=new GameGuard(steam);
        List<IntPtr> bootHidden=new List<IntPtr>();
        DateTime start=DateTime.UtcNow,bootEnd=start.AddSeconds(c.startupWindowSeconds),steamDeadline=bootEnd.AddSeconds(120);
        DateTime nextController=DateTime.MinValue,lastLaunch=DateTime.MinValue,disconnectAt=DateTime.MinValue;
        DateTime cleanupAt=DateTime.MinValue,cleanupDeadline=DateTime.MinValue;
        bool previousGeneric=false,pendingOpen=false,startupChosen=false;
        bool lastReliablePresent=false,lastReliableSeen=false;
        bool seenBp=false,lastBp=false;
        long inputAtDisconnect=-1;
        int launches=0,generic=-1,steamEffective=-1;
        string lastStatus="";
        PuckUndockDetector undockShadow=new PuckUndockDetector();
        UndockLaunchGate undockOpen=new UndockLaunchGate();
        undockOpen.SetMode(c.undockBigPictureMode);
        string configPath=Path.Combine(Log.Root,"config.json");
        DateTime nextModeCheck=DateTime.MinValue;
        DateTime configStamp=File.Exists(configPath)?File.GetLastWriteTimeUtc(configPath):DateTime.MinValue;
        int lastPuckGeneration=-1;
        Log.Write("PUCK UNDOCK: mode="+undockOpen.Mode+"; real lifts validated twice in Alpha 4.3, but refused HID replies remain observational.");
        DateTime nextStatus=DateTime.MinValue;
        using(PuckSupervisor puck=new PuckSupervisor(Process.GetCurrentProcess().MainModule.FileName,c.autoPowerOffOnDock)){
            while(!File.Exists(Path.Combine(Log.Root,"stop.flag"))){
                DateTime now=DateTime.UtcNow;
                try{
                    puck.Maintain();
                    if(now>=nextModeCheck){
                        nextModeCheck=now.AddSeconds(2);
                        try{
                            DateTime currentStamp=File.Exists(configPath)?File.GetLastWriteTimeUtc(configPath):DateTime.MinValue;
                            if(currentStamp!=configStamp){
                                // Hot-reload ONLY this opt-in feature; all existing options
                                // retain the startup config and existing Puck-worker settings.
                                Config changed=Config.Load(configPath);
                                configStamp=currentStamp;
                                if(undockOpen.SetMode(changed.undockBigPictureMode))
                                    Log.Write("PUCK UNDOCK: mode changed to "+undockOpen.Mode+"; pending open canceled; re-dock before next test.");
                            }
                        }catch(Exception ex){
                            undockOpen.SetMode("Disabled");
                            Log.Write("PUCK UNDOCK: invalid/unreadable settings, auto-open DISABLED: "+ex.Message);
                        }
                    }
                    if(now>=nextController){
                        slots.Update();
                        generic=SbsGenericHid.Count();
                        nextController=DateTime.UtcNow.AddMilliseconds(1400);
                    }
                    // Reuse the sidecar's existing samples; never issue extra HID
                    // requests. A worker restart cancels all pending launches.
                    PuckSnapshot puckSample=puck.Snapshot();
                    if(puckSample.Generation!=lastPuckGeneration){
                        undockOpen.Cancel();lastPuckGeneration=puckSample.Generation;
                    }
                    string undockEvent=undockShadow.Observe(puckSample);
                    if(undockEvent!=null){
                        if(undockEvent=="DOCK_BASELINE"){
                            undockOpen.DockBaseline(slots.ConnectedEvents);
                            Log.Write("PUCK UNDOCK: DOCK_BASELINE; Steam connect sequence="+slots.ConnectedEvents+"; mode="+undockOpen.Mode);
                        }else if(undockEvent=="UNDOCK_CANDIDATE"){
                            string decision=undockOpen.Candidate(now);
                            Log.Write("PUCK UNDOCK: UNDOCK_CANDIDATE; "+decision+"; Steam connect baseline captured on dock.");
                        }else{
                            undockOpen.Cancel();
                            Log.Write("PUCK UNDOCK: "+undockEvent+"; pending action canceled.");
                        }
                    }
                    bool genericPresent=generic>0,genericKnown=generic>=0;
                    bool puckReady=puck.Ready;
                    int rawCount=slots.Count;
                    int excluded=puckReady&&puck.Docked&&rawCount>0?1:0;
                    steamEffective=slots.Known?ControllerCounts.Effective(rawCount,puckReady,puck.Docked):0;
                    bool present=genericPresent||(slots.Known&&steamEffective>0);
                    // Controller count must be known and dock baseline stable
                    // before changes are allowed to trigger automatic exit.
                    bool fullyKnown=genericKnown&&slots.Known&&puckReady;
                    // Avoid building the same formatted state 4 times/second in BP.
                    // Decision logic still runs at its normal scan cadence.
                    if(now>=nextStatus){
                        nextStatus=now.AddMilliseconds(950);
                        string status="Generic="+generic+" SteamRaw="+rawCount+" SteamEffective="+steamEffective+
                            " DockExcluded="+excluded+" PuckReady="+puckReady+" PuckState="+puck.State+
                            " SteamKnown="+slots.Known+"; slots="+slots.States;
                        if(status!=lastStatus){Log.Write("STATE: "+status);lastStatus=status;}
                    }
                    List<Win.Window> windows=Win.Scan();
                    Win.ApplyPendingDesktopLayout(windows);
                    bool bp=Win.BigPicture(windows);
                    bool trustedOffDock=puckSample.Fresh && puck.Ready &&
                        puckSample.State=="NO_DOCK" && puckSample.ConsecutiveNoDock>=3 &&
                        (puckSample.HardwareState=="QUERY_REFUSED" || puckSample.HardwareState=="NO_DOCK_REPLY");
                    if(undockOpen.Pending){
                        // Avoid process enumeration during the typical 25s connection wait.
                        bool steamForUndock=undockOpen.ConnectionReady(slots.Known,slots.ConnectedEvents) && SteamRunning();
                        string openDecision=undockOpen.Tick(now,trustedOffDock,bp,steamForUndock,
                            slots.Known,slots.ConnectedEvents,pendingOpen);
                        if(openDecision=="OPEN"){
                            // Never steal focus from an active game or unknown full-screen app.
                            string reason=null;
                            try{reason=games.UnsafeReason();}
                            catch(Exception ex){reason="game safety check failed: "+ex.GetType().Name;}
                            if(reason!=null)Log.Write("PUCK UNDOCK: Open Big Picture skipped: "+reason);
                            else{
                                // Do not pre-hide Steam desktop here: if the URI never
                                // opens BP, no window should be left invisible. The
                                // existing BP-detected cleanup runs on the next scan.
                                bool launched=RequestSteamUri("steam://open/bigpicture");
                                if(launched){startupChosen=true;lastLaunch=now;} // Avoid duplicate startup URI.
                                Log.Write("PUCK UNDOCK: ACTION Open Big Picture ("+undockOpen.Mode+"); uriDispatched="+launched);
                            }
                        }else if(openDecision!=null){Log.Write("PUCK UNDOCK: "+openDecision);}
                    }
                    if(c.autoOpenOnStartup&&!monitorOnly&&now<=bootEnd&&!startupChosen&&present){
                        // Real generic gamepads can start immediately. Steam-only
                        // devices require stable dock detection to avoid false
                        // charging-only startup launches.
                        if(genericPresent||puckReady){startupChosen=true;pendingOpen=true;
                            Log.Write("STARTUP: Active controller confirmed.");}
                    }
                    if(c.autoOpenOnStartup&&!monitorOnly&&pendingOpen){
                        if(bp){pendingOpen=false;bootHidden.Clear();Log.Write("STARTUP SUCCESS: Big Picture detected.");}
                        else if(now>=steamDeadline||launches>=6){pendingOpen=false;Win.RestoreHidden(bootHidden);bootHidden.Clear();Log.Write("STARTUP TIMEOUT; restored hidden Steam windows.");}
                        else if(SteamRunning()&&(now-lastLaunch).TotalSeconds>=12){
                            launches++;lastLaunch=now;
                            if(c.cleanupSteamWindow&&c.preHideSteamDesktop)bootHidden.AddRange(Win.HideDesktop(windows,false,c));
                            RequestSteamUri("steam://open/bigpicture");Log.Write("ACTION: Open Big Picture, attempt "+launches+"/6.");
                        }
                    }
                    // Only compare two *validated* controller states. A single
                    // interim Puck sample can temporarily make Ready=false;
                    // carry the last validated count across that transition.
                    // A restarted/failed worker clears the baseline entirely.
                    if(!puckReady && (!puck.Fresh || puck.State=="UNKNOWN"))lastReliableSeen=false;
                    bool confirmedLastDisconnect=fullyKnown&&lastReliableSeen&&lastReliablePresent&&!present;
                    bool genericOnlyDisconnect=puckReady&&!slots.Known&&genericKnown&&previousGeneric&&!genericPresent;
                    if(c.autoExitOnDisconnect){
                        if(present&&fullyKnown){disconnectAt=DateTime.MinValue;inputAtDisconnect=-1;}
                        else if((confirmedLastDisconnect||genericOnlyDisconnect)&&bp&&disconnectAt==DateTime.MinValue){
                            disconnectAt=now;inputAtDisconnect=Win.LastInputTick();
                            Log.Write("Last active controller disconnected. Waiting "+c.disconnectGraceSeconds+"s.");
                        }
                        if(disconnectAt!=DateTime.MinValue){
                            bool knownForExit=fullyKnown||(puckReady&&!slots.Known&&genericKnown);
                            if(!bp||present||!knownForExit){
                                disconnectAt=DateTime.MinValue;Log.Write("Disconnect countdown canceled: state uncertain or controller returned.");
                            }else if(c.mouseActivityCancelsExit && (inputAtDisconnect<0||Win.LastInputTick()!=inputAtDisconnect)){
                                disconnectAt=DateTime.MinValue;Log.Write("Disconnect countdown canceled: mouse/keyboard activity.");
                            }else if((now-disconnectAt).TotalSeconds>=c.disconnectGraceSeconds){
                                disconnectAt=DateTime.MinValue;
                                // Process-name cache is for display polling only.
                                // Force fresh names/handles before any exit action.
                                string unsafeReason=games.UnsafeReason();
                                if(unsafeReason!=null)Log.Write("Disconnect ignored: "+unsafeReason+" (no deferred exit).");
                                else if(!puck.Ready||present){Log.Write("Disconnect canceled: latest state uncertain.");}
                                else{
                                    if(c.cleanupSteamWindow&&c.preHideSteamDesktop)Win.HideDesktop(windows,false,c);
                                    RequestSteamUri("steam://close/bigpicture");
                                    Log.Write("ACTION: Exit Big Picture using Steam URI; Steam stays running.");
                                    if(c.cleanupSteamWindow){cleanupAt=now.AddMilliseconds(c.cleanupDelayMs);cleanupDeadline=now.AddSeconds(18);}
                                }
                            }
                        }
                    }
                    if(fullyKnown){lastReliablePresent=present;lastReliableSeen=true;}
                    if(bp){seenBp=true;
                        if(c.cleanupSteamWindow&&c.preHideSteamDesktop)Win.HideDesktop(windows,false,c);
                    }else if(lastBp&&seenBp&&c.cleanupSteamWindow&&cleanupAt==DateTime.MinValue){
                        cleanupAt=now.AddMilliseconds(c.cleanupDelayMs);cleanupDeadline=now.AddSeconds(18);
                        Log.Write("Steam desktop cleanup queued after manual Big Picture exit.");
                    }
                    if(cleanupAt!=DateTime.MinValue&&now>=cleanupAt){
                        if(bp){if(now>=cleanupDeadline){cleanupAt=DateTime.MinValue;Log.Write("CLEANUP ABANDONED: Big Picture remains visible.");}}
                        else{
                            List<IntPtr> hidden=Win.HideDesktop(windows,true,c);
                            if(hidden.Count>0){Log.Write("CLEANUP COMPLETE: Steam desktop window hidden; Steam remains running.");cleanupAt=DateTime.MinValue;}
                            else if(now>=cleanupDeadline){cleanupAt=DateTime.MinValue;Log.Write("CLEANUP ABANDONED: Steam desktop window not found.");}
                        }
                    }
                    previousGeneric=genericPresent;lastBp=bp;
                }catch(Exception ex){
                    Log.Write("WARN: skipped cycle: "+ex.GetType().Name+": "+ex.Message);
                    disconnectAt=DateTime.MinValue;
                }
                Thread.Sleep(lastBp||pendingOpen||undockOpen.Pending||cleanupAt!=DateTime.MinValue?250:850);
            }
        }
        Log.Write("Stop flag received; native watcher exiting.");
    }
    // Pure software regression tests. Invoked by the installer before it touches
    // the running version; no HID device, Steam URI or window is accessed.
    private static bool SelfTest() {
        bool counts=ControllerCounts.Effective(1,true,true)==0 &&
            ControllerCounts.Effective(1,true,false)==1 &&
            ControllerCounts.Effective(2,true,true)==1 &&
            ControllerCounts.Effective(2,true,false)==2 &&
            ControllerCounts.Effective(1,false,true)==1 &&
            ControllerCounts.Effective(0,true,true)==0;
        bool steamEvents=false, startupSettings=false;
        string testFile=Path.GetTempFileName();
        try {
            File.WriteAllText(testFile,"{}");
            bool legacyStartup=Config.Load(testFile).autoOpenOnStartup;
            File.WriteAllText(testFile,"{\"autoOpenOnStartup\":false,\"undockBigPictureMode\":\"Disabled\",\"autoPowerOffOnDock\":true}");
            Config personal=Config.Load(testFile);
            startupSettings=legacyStartup && !personal.autoOpenOnStartup && personal.autoPowerOffOnDock && personal.undockBigPictureMode=="Disabled";
            string stamp=DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            SteamLogReader test=new SteamLogReader(testFile,DateTime.Now.AddMinutes(-1));
            File.WriteAllText(testFile,"["+stamp+"] Controller 2 connected, configuring it now...\n");
            test.Update();
            bool first=test.Known && test.Count==1 && test.States.IndexOf("2=ON",StringComparison.Ordinal)>=0;
            test.Update();
            bool noDuplicate=test.Count==1 && test.ConnectedEvents==1;
            File.AppendAllText(testFile,"["+stamp+"] Controller 2 connected, configuring it now...\n"+
                "["+stamp+"] Controller 5 connected, configuring it now...\n");
            test.Update();
            bool two=test.Count==2 && test.ConnectedEvents==2;
            File.AppendAllText(testFile,"["+stamp+"] Controller 2 disconnected\n");
            test.Update();
            bool one=test.Count==1 && test.States.IndexOf("2=OFF",StringComparison.Ordinal)>=0;
            steamEvents=first&&noDuplicate&&two&&one;
        }finally{try{File.Delete(testFile);}catch{}}
        // All tests below exercise only synthetic samples; never touch HID.
        bool undockTest=TestUndockDetector();
        bool activationTest=TestUndockActivation();
        bool quietCleanup=(Win.QuietHideFlags&0x0010)!=0 && (Win.QuietHideFlags&0x0080)!=0 &&
            (Win.QuietHideFlags&0x0040)==0 && Win.CanApplyLayout(new IntPtr(1),new IntPtr(1)) &&
            !Win.CanApplyLayout(new IntPtr(1),new IntPtr(2)) && !Win.CanApplyLayout(IntPtr.Zero,IntPtr.Zero);
        return counts&&steamEvents&&TestSteamGameGuard()&&undockTest&&activationTest&&startupSettings&&quietCleanup&&TestQuietCleanup();
    }
    private static bool TestQuietCleanup(){
        var desktop=new IntPtr(123);var bp=new IntPtr(124);var editor=new IntPtr(125);
        var windows=new List<Win.Window>{
            new Win.Window{Handle=desktop,Name="steamwebhelper",Title="Steam"},
            new Win.Window{Handle=bp,Name="steamwebhelper",Title="Steam Big Picture"},
            new Win.Window{Handle=editor,Name="editor",Title="My document"}};
        var calls=new List<IntPtr>();var c=new Config();
        var hidden=Win.HideDesktop(windows,true,c,delegate(IntPtr h){calls.Add(h);return true;});
        if(calls.Count!=1||calls[0]!=desktop||hidden.Count!=1)return false;
        if(Win.TakePendingLayout(desktop,editor)!=null)return false;
        if(Win.TakePendingLayout(desktop,desktop)!=c)return false;
        if(Win.TakePendingLayout(desktop,desktop)!=null)return false;
        hidden=Win.HideDesktop(windows,true,c,delegate(IntPtr h){return false;});
        if(hidden.Count!=0||Win.TakePendingLayout(desktop,desktop)!=null)return false;
        return true;
    }
    private static bool TestSteamGameGuard(){
        string add="[2026-10-25 15:26:27] AppID 2054970 adding PID 8568 as a tracked process \"game.exe\"\n";
        string del="[2026-10-25 15:27:15] AppID 2054970 no longer tracking PID 8568, exit code 0\n";
        DateTime started=new DateTime(2026,10,25,15,26,26);
        Func<int,DateTime?> live=delegate(int pid){return started;};
        // Games remain protected without a fullscreen window (windowed/minimized included).
        if(GameGuard.ReadSteamGames(new StringReader(add),live)==null)return false;
        if(GameGuard.ReadSteamGames(new StringReader(add+del),live)!=null)return false;
        if(GameGuard.ReadSteamGames(new StringReader(add+"[2026-10-25 15:27:15] Game 2054970 going away; no longer tracking PID 8568\n"),live)!=null)return false;
        if(GameGuard.ReadSteamGames(new StringReader(add),delegate(int pid){return null;})!=null)return false;
        // A stale PID now belonging to a desktop application is not a running game.
        if(GameGuard.ReadSteamGames(new StringReader(add),delegate(int pid){return started.AddHours(1);})!=null)return false;
        if(GameGuard.ReadSteamGames(new StringReader(add),delegate(int pid){throw new UnauthorizedAccessException();})==null)return false;
        // Big Picture/UI activity without a tracked process is not a game session.
        if(GameGuard.ReadSteamGames(new StringReader("[2026-10-25 15:28:00] SSGL: UI mode (7->4)\n"),live)!=null)return false;
        // A process removal for a different app must not erase the active game.
        if(GameGuard.ReadSteamGames(new StringReader(add+del.Replace("2054970","123")),live)==null)return false;
        if(GameGuard.ReadSteamGames(new StringReader(add.Replace("2054970","18446744073709551600")),live)==null)return false;
        if(GameGuard.ReadSteamGames(new StringReader(add.Replace("2026-10-25","bad-date!!")),live)==null)return false;
        if(GameGuard.ReadSteamGames(new StringReader(add.Replace("8568","bad-pid")),live)==null)return false;
        if(GameGuard.ReadSteamGames(new StringReader(add+del+add),live)==null)return false;
        return true;
    }
    private static PuckSnapshot Sample(int generation,long number,string state,string hardware,int docks,int noDocks){
        return new PuckSnapshot{Generation=generation,Sequence=number,State=state,
            HardwareState=hardware,ConsecutiveDock=docks,ConsecutiveNoDock=noDocks,
            Fresh=true,ReceivedAt=DateTime.UtcNow.AddSeconds(number*2)};
    }
    private static bool TestUndockDetector(){
        PuckUndockDetector a=new PuckUndockDetector();
        // Never generate an undock if no verified dock baseline occurred.
        if(a.Observe(Sample(1,1,"NO_DOCK","QUERY_REFUSED",0,1))!=null)return false;
        if(a.Observe(Sample(1,2,"NO_DOCK","QUERY_REFUSED",0,2))!=null)return false;
        if(a.Observe(Sample(1,3,"NO_DOCK","QUERY_REFUSED",0,3))!=null)return false;
        if(a.Observe(Sample(1,4,"DOCK","DOCK_REPLY_CONFIRMED",1,0))!=null)return false;
        if(a.Observe(Sample(1,5,"DOCK","DOCK_REPLY_CONFIRMED",2,0))!="DOCK_BASELINE")return false;
        // A transient one-sample query refusal must not fire.
        if(a.Observe(Sample(1,6,"NO_DOCK","QUERY_REFUSED",0,1))!=null)return false;
        if(a.Observe(Sample(1,7,"DOCK","DOCK_REPLY_CONFIRMED",1,0))!=null)return false;
        if(a.Observe(Sample(1,8,"DOCK","DOCK_REPLY_CONFIRMED",2,0))!=null)return false;
        if(a.Observe(Sample(1,9,"NO_DOCK","QUERY_REFUSED",0,1))!=null)return false;
        if(a.Observe(Sample(1,10,"NO_DOCK","QUERY_REFUSED",0,2))!=null)return false;
        if(a.Observe(Sample(1,11,"NO_DOCK","QUERY_REFUSED",0,3))!="UNDOCK_CANDIDATE")return false;
        if(a.Observe(Sample(1,12,"NO_DOCK","QUERY_REFUSED",0,4))!=null)return false;
        // Unknown response disarms, receiver removal cannot masquerade as lift.
        PuckUndockDetector b=new PuckUndockDetector();
        b.Observe(Sample(2,1,"DOCK","DOCK_REPLY_CONFIRMED",1,0));
        b.Observe(Sample(2,2,"DOCK","DOCK_REPLY_CONFIRMED",2,0));
        if(b.Observe(Sample(2,3,"NO_DOCK","NO_CONTROL_INTERFACE",0,1))!="ABORTED_UNTRUSTED")return false;
        if(b.Observe(Sample(2,4,"NO_DOCK","QUERY_REFUSED",0,2))!=null)return false;
        if(b.Observe(Sample(2,5,"NO_DOCK","QUERY_REFUSED",0,3))!=null)return false;
        // Restarting the sidecar discards all prior dock evidence.
        PuckUndockDetector c=new PuckUndockDetector();
        c.Observe(Sample(3,1,"DOCK","DOCK_REPLY_CONFIRMED",1,0));
        c.Observe(Sample(3,2,"DOCK","DOCK_REPLY_CONFIRMED",2,0));
        if(c.Observe(Sample(4,1,"NO_DOCK","QUERY_REFUSED",0,1))!=null)return false;
        if(c.Observe(Sample(4,2,"NO_DOCK","QUERY_REFUSED",0,2))!=null)return false;
        if(c.Observe(Sample(4,3,"NO_DOCK","QUERY_REFUSED",0,3))!=null)return false;
        // An ambiguous middle sample also disarms.
        PuckUndockDetector d=new PuckUndockDetector();
        d.Observe(Sample(5,1,"DOCK","DOCK_REPLY_CONFIRMED",1,0));
        d.Observe(Sample(5,2,"DOCK","DOCK_REPLY_CONFIRMED",2,0));
        d.Observe(Sample(5,3,"NO_DOCK","QUERY_REFUSED",0,1));
        if(d.Observe(Sample(5,4,"UNKNOWN","ACCESS_BLOCKED",0,0))!="ABORTED_UNKNOWN")return false;
        if(d.Observe(Sample(5,5,"NO_DOCK","QUERY_REFUSED",0,1))!=null)return false;
        return true;
    }
    private static bool TestUndockActivation(){
        DateTime t=DateTime.UtcNow;
        UndockLaunchGate g=new UndockLaunchGate();
        g.DockBaseline(3);
        if(g.Candidate(t)!="DISABLED")return false;
        g.SetMode("OnConnection");
        if(g.Candidate(t)!="WAITING_CONNECTION")return false;
        if(g.Tick(t,true,false,true,true,3,false)!=null)return false;
        if(g.Tick(t.AddSeconds(1),true,false,true,false,4,false)!=null)return false;
        if(g.Tick(t.AddSeconds(2),true,false,true,true,4,false)!="OPEN")return false;
        if(g.Tick(t.AddSeconds(3),true,false,true,true,5,false)!=null)return false;
        g.DockBaseline(4);
        if(g.Candidate(t.AddSeconds(4))!="COOLDOWN")return false;
        if(g.Candidate(t.AddSeconds(18))!="WAITING_CONNECTION")return false;
        if(g.Tick(t.AddSeconds(19),false,false,true,true,5,false)!="CANCELED_PUCK_UNCERTAIN")return false;
        g.DockBaseline(5);
        if(g.Candidate(t.AddSeconds(20))!="WAITING_CONNECTION")return false;
        if(g.Tick(t.AddSeconds(46),true,false,true,true,6,false)!="TIMED_OUT")return false;
        g.SetMode("Immediate");
        g.DockBaseline(5);
        if(g.Candidate(t.AddSeconds(50))!="WAITING_STEAM")return false;
        if(g.Tick(t.AddSeconds(51),true,false,false,false,5,false)!=null)return false;
        if(g.Tick(t.AddSeconds(52),true,false,true,false,5,false)!="OPEN")return false;
        g.DockBaseline(6);
        if(g.Candidate(t.AddSeconds(53))!="COOLDOWN")return false;
        if(!UndockLaunchGate.ValidMode("Disabled") || UndockLaunchGate.ValidMode("AThing"))return false;
        return true;
    }
    [STAThread]private static int Main(string[] args){
        try{
            bool worker=false,auto=false,monitor=false;
            foreach(string arg in args){
                if(arg=="--puck-worker")worker=true;
                else if(arg=="--auto-power-off")auto=true;
                else if(arg=="--monitor-only")monitor=true;
            }
            if(args.Length>=2 && args[0]=="--selftest") {
                bool ok=SelfTest();
                File.WriteAllText(args[1],ok?
                    "SELFTEST PASS - dock accounting, controller events, Steam game processes, startup settings, undock transitions, and launch gate":
                    "SELFTEST FAILED - controller and window checks did not pass");
                return ok?0:7;
            }
            if(worker){Worker(auto);return 0;}
            string mutexName=@"Local\SteamBootSwitchNativeAlpha4";
            if(File.Exists(Path.Combine(Log.Root,"qa-install.marker"))) mutexName+="_V110_QA";
            using(Mutex m=new Mutex(false,mutexName)){
                bool owned=false;
                try{owned=m.WaitOne(0,false);}catch(AbandonedMutexException){owned=true;}
                if(!owned)return 0;
                try{RunWatcher(monitor);}finally{m.ReleaseMutex();}
            }
            return 0;
        }catch(Exception ex){Log.Write("FATAL native watcher: "+ex);return 1;}
    }
}
