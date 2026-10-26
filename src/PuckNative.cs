// Windows-only, experimental 2026 Steam Controller Puck shutdown test.
// Uses GetAttributes (0x83) to confirm dock and active Puck slot, then a
// SINGLE fixed power-off feature report (0x9F + ASCII 'off!').
// Device protocol sources:
// https://github.com/fraustiz/steam-controller-battery/blob/main/src/hid.rs
// https://github.com/tkubicz/steam-controller-bridge/blob/main/crates/controller/steam-controller-protocol/src/lib.rs
// Native hardware write is experimental and untested alongside Steam on Windows.
// Does not change pairing, configuration, firmware, haptics, Steam, or Windows settings.
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class SteamPuckShutdownNative
{
    private const ushort VID_VALVE = 0x28DE;
    private const ushort PID_PUCK = 0x1304;
    private const ushort PID_CONTROLLER = 0x1302;
    private const uint DIGCF_PRESENT = 0x00000002;
    private const uint DIGCF_DEVICEINTERFACE = 0x00000010;
    private const uint GENERIC_READ = 0x80000000;
    private const uint GENERIC_WRITE = 0x40000000;
    private const uint SHARE_READ_WRITE = 3;
    private const uint OPEN_EXISTING = 3;
    private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

    [StructLayout(LayoutKind.Sequential)]
    private struct SP_DEVICE_INTERFACE_DATA
    {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct HIDD_ATTRIBUTES
    {
        public int Size;
        public ushort VendorID;
        public ushort ProductID;
        public ushort VersionNumber;
    }

    [DllImport("hid.dll")] private static extern void HidD_GetHidGuid(out Guid HidGuid);
    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr SetupDiGetClassDevs(ref Guid classGuid, IntPtr enumerator, IntPtr parent, uint flags);
    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiEnumDeviceInterfaces(IntPtr deviceInfoSet, IntPtr deviceInfoData,
        ref Guid interfaceClassGuid, uint memberIndex, ref SP_DEVICE_INTERFACE_DATA interfaceData);
    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr deviceInfoSet,
        ref SP_DEVICE_INTERFACE_DATA interfaceData, IntPtr deviceInterfaceDetailData,
        uint deviceInterfaceDetailDataSize, out uint requiredSize, IntPtr deviceInfoData);
    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr deviceInfoSet);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFile(string fileName, uint desiredAccess, uint shareMode,
        IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);
    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetAttributes(SafeFileHandle hidDeviceObject, ref HIDD_ATTRIBUTES attributes);
    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetPreparsedData(SafeFileHandle hidDeviceObject, out IntPtr preparsedData);
    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_FreePreparsedData(IntPtr preparsedData);
    [DllImport("hid.dll")]
    private static extern int HidP_GetCaps(IntPtr preparsedData, IntPtr capabilities);
    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_SetFeature(SafeFileHandle hidDeviceObject, byte[] reportBuffer, int reportBufferLength);
    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetFeature(SafeFileHandle hidDeviceObject, byte[] reportBuffer, int reportBufferLength);

    public sealed class Report
    {
        public string State = "UNKNOWN";
        public string Reason = "Not queried";
        public int MatchingControlInterfaces;
        public int FeatureReportLength;
        public bool DockResponseConfirmed;
    }

    private sealed class InterfaceInfo
    {
        public string Path;
        public int FeatureLength;
        public int InputLength;
    }

    private static bool GetInterfaceProperties(string path, out ushort vid, out ushort pid,
        out ushort usagePage, out ushort usage, out ushort featureLength, out ushort inputLength)
    {
        vid = pid = usagePage = usage = featureLength = inputLength = 0;
        using (SafeFileHandle h = CreateFile(path, 0, SHARE_READ_WRITE, IntPtr.Zero,
            OPEN_EXISTING, 0, IntPtr.Zero))
        {
            if (h.IsInvalid) return false;
            HIDD_ATTRIBUTES a = new HIDD_ATTRIBUTES();
            a.Size = Marshal.SizeOf(typeof(HIDD_ATTRIBUTES));
            if (!HidD_GetAttributes(h, ref a)) return false;
            vid = a.VendorID; pid = a.ProductID;
            if (vid != VID_VALVE || (pid != PID_PUCK && pid != PID_CONTROLLER)) return true;
            IntPtr pp = IntPtr.Zero;
            if (!HidD_GetPreparsedData(h, out pp) || pp == IntPtr.Zero) return false;
            try
            {
                IntPtr caps = Marshal.AllocHGlobal(128);
                try
                {
                    for (int j = 0; j < 128; j++) Marshal.WriteByte(caps, j, 0);
                    int status = HidP_GetCaps(pp, caps);
                    if (status < 0) return false;
                    // HIDP_CAPS starts with Usage, UsagePage, InputReportLength,
                    // OutputReportLength, FeatureReportLength (all USHORT).
                    usage = unchecked((ushort)Marshal.ReadInt16(caps, 0));
                    usagePage = unchecked((ushort)Marshal.ReadInt16(caps, 2));
                    inputLength = unchecked((ushort)Marshal.ReadInt16(caps, 4));
                    featureLength = unchecked((ushort)Marshal.ReadInt16(caps, 8));
                    return true;
                }
                finally { Marshal.FreeHGlobal(caps); }
            }
            finally { HidD_FreePreparsedData(pp); }
        }
    }

    private static System.Collections.Generic.List<InterfaceInfo> FindPuckControls(out string failure)
    {
        failure = "";
        var result = new System.Collections.Generic.List<InterfaceInfo>();
        Guid hidGuid;
        HidD_GetHidGuid(out hidGuid);
        IntPtr set = SetupDiGetClassDevs(ref hidGuid, IntPtr.Zero, IntPtr.Zero,
            DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (set == INVALID_HANDLE_VALUE)
        {
            failure = "SetupAPI enumeration failed (Win32=" + Marshal.GetLastWin32Error() + ")";
            return result;
        }
        try
        {
            for (uint n = 0; n < 128; n++)
            {
                SP_DEVICE_INTERFACE_DATA data = new SP_DEVICE_INTERFACE_DATA();
                data.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref hidGuid, n, ref data))
                {
                    int err = Marshal.GetLastWin32Error();
                    if (err != 259) failure = "SetupAPI interface enumeration error " + err;
                    break;
                }
                uint bytesRequired;
                SetupDiGetDeviceInterfaceDetail(set, ref data, IntPtr.Zero, 0,
                    out bytesRequired, IntPtr.Zero);
                if (bytesRequired < 8 || bytesRequired > 16384) continue;
                IntPtr p = Marshal.AllocHGlobal((int)bytesRequired);
                try
                {
                    Marshal.WriteInt32(p, IntPtr.Size == 8 ? 8 : 6);
                    uint ignore;
                    if (!SetupDiGetDeviceInterfaceDetail(set, ref data, p, bytesRequired,
                        out ignore, IntPtr.Zero)) continue;
                    // For the Unicode detail struct, DevicePath begins at offset 4;
                    // the cbSize is 8 on 64-bit Windows and 6 on 32-bit Windows.
                    string path = Marshal.PtrToStringUni(IntPtr.Add(p, 4));
                    if (String.IsNullOrEmpty(path)) continue;
                    ushort vid, pid, page, usage, len, inputLen;
                    if (!GetInterfaceProperties(path, out vid, out pid, out page,
                        out usage, out len, out inputLen)) continue;
                    if (vid == VID_VALVE && pid == PID_PUCK && page == 0xFF00 && usage == 0x0002)
                    {
                        result.Add(new InterfaceInfo { Path = path, FeatureLength = len, InputLength = inputLen });
                    }
                }
                finally { Marshal.FreeHGlobal(p); }
            }
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
        return result;
    }

    // Only reads HID input from the Puck's vendor pairing slots. All opens are
    // GENERIC_READ with shared access. Never writes to a pairing slot.
    private static System.Collections.Generic.List<InterfaceInfo> FindPuckSlots(out string failure)
    {
        failure = "";
        var result = new System.Collections.Generic.List<InterfaceInfo>();
        Guid hidGuid;
        HidD_GetHidGuid(out hidGuid);
        IntPtr set = SetupDiGetClassDevs(ref hidGuid, IntPtr.Zero, IntPtr.Zero,
            DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (set == INVALID_HANDLE_VALUE) { failure = "SetupAPI failure"; return result; }
        try
        {
            for (uint n = 0; n < 256; n++)
            {
                SP_DEVICE_INTERFACE_DATA data = new SP_DEVICE_INTERFACE_DATA();
                data.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref hidGuid, n, ref data))
                    break;
                uint bytesRequired;
                SetupDiGetDeviceInterfaceDetail(set, ref data, IntPtr.Zero, 0,
                    out bytesRequired, IntPtr.Zero);
                if (bytesRequired < 8 || bytesRequired > 16384) continue;
                IntPtr p = Marshal.AllocHGlobal((int)bytesRequired);
                try
                {
                    Marshal.WriteInt32(p, IntPtr.Size == 8 ? 8 : 6);
                    uint ignore;
                    if (!SetupDiGetDeviceInterfaceDetail(set, ref data, p, bytesRequired,
                        out ignore, IntPtr.Zero)) continue;
                    string path = Marshal.PtrToStringUni(IntPtr.Add(p, 4));
                    if (String.IsNullOrEmpty(path)) continue;
                    ushort vid, pid, page, usage, featureLen, inputLen;
                    if (!GetInterfaceProperties(path, out vid, out pid, out page,
                        out usage, out featureLen, out inputLen)) continue;
                    if (vid == VID_VALVE && (pid == PID_PUCK || pid == PID_CONTROLLER) &&
                        page == 0xFF00 && usage == 0x0001 && inputLen >= 2 && inputLen <= 512)
                    {
                        result.Add(new InterfaceInfo { Path = path,
                            FeatureLength = featureLen, InputLength = inputLen });
                    }
                }
                finally { Marshal.FreeHGlobal(p); }
            }
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
        return result;
    }

    public static Report CheckDock()
    {
        Report r = new Report();
        string error;
        var controls = FindPuckControls(out error);
        r.MatchingControlInterfaces = controls.Count;
        if (controls.Count == 0)
        {
            r.State = "NO_CONTROL_INTERFACE";
            r.Reason = error.Length > 0 ? error : "No 28DE:1304 vendor FF00/0002 HID control interface found";
            return r;
        }
        if (controls.Count != 1)
        {
            r.State = "AMBIGUOUS_MULTIPLE_PUCKS";
            r.Reason = "More than one control interface; cannot associate replies with a single Puck";
            return r;
        }
        InterfaceInfo chosen = controls[0];
        r.FeatureReportLength = chosen.FeatureLength;
        if (chosen.FeatureLength < 4 || chosen.FeatureLength > 512)
        {
            r.State = "UNSUPPORTED_REPORT_LENGTH";
            r.Reason = "Feature report length from HID caps: " + chosen.FeatureLength;
            return r;
        }
        // Open only the Puck's vendor control interface, shared with Steam.
        using (SafeFileHandle h = CreateFile(chosen.Path, GENERIC_READ | GENERIC_WRITE,
            SHARE_READ_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero))
        {
            if (h.IsInvalid)
            {
                r.State = "ACCESS_BLOCKED";
                r.Reason = "Puck control interface could not be opened for feature query, Win32="
                    + Marshal.GetLastWin32Error();
                return r;
            }
            byte[] query = new byte[chosen.FeatureLength];
            query[0] = 0x01; // controller channel
            query[1] = 0x83; // read attributes only
            if (!HidD_SetFeature(h, query, query.Length))
            {
                r.State = "QUERY_REFUSED";
                r.Reason = "Get Attributes request not accepted, Win32=" + Marshal.GetLastWin32Error();
                return r;
            }
            int unexpected = 0;
            for (int n = 0; n < 20; n++)
            {
                byte[] reply = new byte[chosen.FeatureLength];
                reply[0] = 0x01;
                if (HidD_GetFeature(h, reply, reply.Length) &&
                    reply.Length >= 4 && reply[1] == 0x83)
                {
                    int len = Math.Min((int)reply[2], reply.Length - 3);
                    for (int i = 3; i + 5 <= 3 + len; i += 5)
                    {
                        int attr = reply[i];
                        ushort product = (ushort)(reply[i + 1] | (reply[i + 2] << 8));
                        if (attr == 0x01 && product == PID_CONTROLLER)
                        {
                            r.State = "DOCK_REPLY_CONFIRMED";
                            r.DockResponseConfirmed = true;
                            r.Reason = "Puck control interface replied to Get Attributes with Steam Controller PID 1302";
                            return r;
                        }
                    }
                    unexpected++;
                }
                System.Threading.Thread.Sleep(10);
            }
            r.State = unexpected > 0 ? "UNRECOGNIZED_REPLY" : "NO_DOCK_REPLY";
            r.Reason = unexpected > 0
                ? "Get Attributes replied but did not contain the expected Steam Controller PID"
                : "No validated dock reply; could mean undocked, controller awake, busy or query failure";
            return r;
        }
    }


    public sealed class ShutdownReport
    {
        public string State = "NOT_ATTEMPTED";
        public string Reason = "";
        public bool DockConfirmed;
        public int PairingSlotInterfaces;
        public int ResponsiveSlots;
        public int BlockedSlots;
        public bool CommandSubmitted;
    }

    // 0x83 replies with a five-byte attribute for product ID 0x1302 on the
    // currently responsive 0xFF00/0x0001 Puck controller slot. We do not read
    // joystick data (Steam may hold that stream) or guess at an active slot.
    private static bool IsResponsiveControllerSlot(SafeFileHandle h, int length)
    {
        byte[] query = new byte[length];
        query[0] = 0x01;
        query[1] = 0x83; // Get Attributes (not configuration)
        if (!HidD_SetFeature(h, query, query.Length)) return false;
        for (int trial = 0; trial < 20; trial++)
        {
            byte[] reply = new byte[length];
            reply[0] = 0x01;
            if (HidD_GetFeature(h, reply, reply.Length) &&
                reply.Length >= 4 && reply[1] == 0x83)
            {
                int n = Math.Min((int)reply[2], reply.Length - 3);
                for (int i = 3; i + 5 <= 3 + n; i += 5)
                {
                    ushort product = (ushort)(reply[i + 1] | (reply[i + 2] << 8));
                    if (reply[i] == 0x01 && product == PID_CONTROLLER) return true;
                }
            }
            System.Threading.Thread.Sleep(10);
        }
        return false;
    }

    public static ShutdownReport PowerOffOnceIfDocked()
    {
        ShutdownReport r = new ShutdownReport();
        Report dock = CheckDock();
        r.DockConfirmed = dock.DockResponseConfirmed;
        if (!dock.DockResponseConfirmed)
        {
            r.State = "DOCK_NOT_CONFIRMED";
            r.Reason = "No validated Puck dock reply: " + dock.State + "; " + dock.Reason;
            return r;
        }
        string problem;
        var candidates = FindPuckSlots(out problem);
        // Puck-only, not Bluetooth or directly wired; do not attempt on ambiguous
        // setups (multiple Pucks or too many HID slot interfaces).
        var slots = new System.Collections.Generic.List<InterfaceInfo>();
        foreach (InterfaceInfo candidate in candidates)
        {
            ushort vid, pid, page, usage, featureLen, inputLen;
            if (!GetInterfaceProperties(candidate.Path, out vid, out pid, out page,
                out usage, out featureLen, out inputLen)) continue;
            if (vid == VID_VALVE && pid == PID_PUCK && page == 0xFF00 && usage == 0x0001)
                slots.Add(candidate);
        }
        r.PairingSlotInterfaces = slots.Count;
        if (slots.Count < 1 || slots.Count > 4)
        {
            r.State = "SLOT_COUNT_UNSUPPORTED";
            r.Reason = "Expected 1-4 Puck slot collections; found " + slots.Count + ". " + problem;
            return r;
        }
        InterfaceInfo responsive = null;
        foreach (InterfaceInfo slot in slots)
        {
            if (slot.FeatureLength != 64)
            {
                r.State = "UNEXPECTED_FEATURE_LENGTH";
                r.Reason = "Expected exact 64-byte Puck feature reports; found " + slot.FeatureLength;
                return r;
            }
            using (SafeFileHandle h = CreateFile(slot.Path, GENERIC_READ | GENERIC_WRITE,
                SHARE_READ_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero))
            {
                if (h.IsInvalid) { r.BlockedSlots++; continue; }
                if (IsResponsiveControllerSlot(h, slot.FeatureLength))
                {
                    r.ResponsiveSlots++;
                    responsive = slot;
                }
            }
        }
        if (r.BlockedSlots != 0 || r.ResponsiveSlots != 1 || responsive == null)
        {
            r.State = "CANNOT_VERIFY_UNIQUE_ACTIVE_SLOT";
            r.Reason = "Responsive=" + r.ResponsiveSlots + ", blocked=" + r.BlockedSlots +
                ". Steam may own the HID interface. No shutdown command was sent.";
            return r;
        }
        // Reopen the exact slot and recheck it immediately before the write.
        using (SafeFileHandle h = CreateFile(responsive.Path, GENERIC_READ | GENERIC_WRITE,
            SHARE_READ_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero))
        {
            if (h.IsInvalid || !IsResponsiveControllerSlot(h, 64))
            {
                r.State = "TARGET_CHANGED_OR_BLOCKED";
                r.Reason = "Active Puck slot could not be reconfirmed. No shutdown command was sent.";
                return r;
            }
            // ONE write per user-confirmed invocation. NO automatic retries.
            // Exact fixed packet from the Steam Controller 2026 protocol:
            // 01 9F 04 6F 66 66 21 00 ... (64 bytes total)
            byte[] off = new byte[64];
            off[0] = 0x01;
            off[1] = 0x9F;
            off[2] = 0x04;
            off[3] = (byte)'o'; off[4] = (byte)'f';
            off[5] = (byte)'f'; off[6] = (byte)'!';
            if (HidD_SetFeature(h, off, off.Length))
            {
                r.CommandSubmitted = true;
                r.State = "POWER_OFF_REPORT_SUBMITTED";
                r.Reason = "Windows accepted one fixed 0x9F off! feature report. This does NOT prove the controller stayed off.";
            }
            else
            {
                r.State = "POWER_OFF_WRITE_REJECTED";
                r.Reason = "Windows rejected fixed 0x9F feature report, Win32=" + Marshal.GetLastWin32Error();
            }
            return r;
        }
    }

}

// Same HID enumeration API as the validated Puck probes, but restricted to
// Generic Desktop joystick/gamepad usage. This avoids permanent WMI runtimes.
public static class SbsGenericHid {
    private const uint PRESENT=0x2, DEVINTERFACE=0x10, SHARE=3, OPEN=3;
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    private struct Data {public int Size;public System.Guid Guid;public int Flags;public System.IntPtr Reserved;}
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    private struct Attributes {public int Size;public ushort Vendor;public ushort Product;public ushort Revision;}
    [System.Runtime.InteropServices.DllImport("hid.dll")]private static extern void HidD_GetHidGuid(out System.Guid id);
    [System.Runtime.InteropServices.DllImport("setupapi.dll",SetLastError=true)]
    private static extern System.IntPtr SetupDiGetClassDevs(ref System.Guid id,System.IntPtr enumerator,System.IntPtr parent,uint flags);
    [System.Runtime.InteropServices.DllImport("setupapi.dll",SetLastError=true)]
    private static extern bool SetupDiEnumDeviceInterfaces(System.IntPtr set,System.IntPtr data,ref System.Guid id,uint index,ref Data di);
    [System.Runtime.InteropServices.DllImport("setupapi.dll",SetLastError=true,CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern bool SetupDiGetDeviceInterfaceDetail(System.IntPtr set,ref Data di,System.IntPtr detail,uint capacity,out uint length,System.IntPtr info);
    [System.Runtime.InteropServices.DllImport("setupapi.dll")]
    private static extern bool SetupDiDestroyDeviceInfoList(System.IntPtr set);
    [System.Runtime.InteropServices.DllImport("kernel32.dll",SetLastError=true,CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string path,uint access,uint share,System.IntPtr security,uint creation,uint flags,System.IntPtr template);
    [System.Runtime.InteropServices.DllImport("hid.dll",SetLastError=true)]
    private static extern bool HidD_GetAttributes(Microsoft.Win32.SafeHandles.SafeFileHandle h,ref Attributes a);
    [System.Runtime.InteropServices.DllImport("hid.dll",SetLastError=true)]
    private static extern bool HidD_GetPreparsedData(Microsoft.Win32.SafeHandles.SafeFileHandle h,out System.IntPtr pp);
    [System.Runtime.InteropServices.DllImport("hid.dll",SetLastError=true)]
    private static extern bool HidD_FreePreparsedData(System.IntPtr pp);
    [System.Runtime.InteropServices.DllImport("hid.dll")]
    private static extern int HidP_GetCaps(System.IntPtr pp,System.IntPtr caps);
    // Return -1 on enumeration failure: unknown must NEVER authorize exit.
    public static int Count(){
        System.Guid id;HidD_GetHidGuid(out id);
        System.IntPtr set=SetupDiGetClassDevs(ref id,System.IntPtr.Zero,System.IntPtr.Zero,PRESENT|DEVINTERFACE);
        if(set==new System.IntPtr(-1))return -1;
        int count=0;
        try {
            for(uint i=0;i<256;i++){
                Data data=new Data();data.Size=System.Runtime.InteropServices.Marshal.SizeOf(typeof(Data));
                if(!SetupDiEnumDeviceInterfaces(set,System.IntPtr.Zero,ref id,i,ref data)){
                    if(System.Runtime.InteropServices.Marshal.GetLastWin32Error()!=259)return -1;
                    break;
                }
                uint required;
                SetupDiGetDeviceInterfaceDetail(set,ref data,System.IntPtr.Zero,0,out required,System.IntPtr.Zero);
                if(required<8 || required>16384)continue;
                System.IntPtr buffer=System.Runtime.InteropServices.Marshal.AllocHGlobal((int)required);
                try{
                    System.Runtime.InteropServices.Marshal.WriteInt32(buffer,System.IntPtr.Size==8?8:6);
                    uint ignored;
                    if(!SetupDiGetDeviceInterfaceDetail(set,ref data,buffer,required,out ignored,System.IntPtr.Zero))continue;
                    string path=System.Runtime.InteropServices.Marshal.PtrToStringUni(System.IntPtr.Add(buffer,4));
                    if(string.IsNullOrEmpty(path))continue;
                    using(var h=CreateFile(path,0,SHARE,System.IntPtr.Zero,OPEN,0,System.IntPtr.Zero)){
                        if(h.IsInvalid)continue;
                        Attributes a=new Attributes();a.Size=System.Runtime.InteropServices.Marshal.SizeOf(typeof(Attributes));
                        if(!HidD_GetAttributes(h,ref a)||a.Vendor==0x28DE)continue;
                        System.IntPtr pp;
                        if(!HidD_GetPreparsedData(h,out pp)||pp==System.IntPtr.Zero)continue;
                        try{
                            System.IntPtr caps=System.Runtime.InteropServices.Marshal.AllocHGlobal(128);
                            try{
                                for(int k=0;k<128;k++)System.Runtime.InteropServices.Marshal.WriteByte(caps,k,0);
                                if(HidP_GetCaps(pp,caps)<0)continue;
                                ushort usage=unchecked((ushort)System.Runtime.InteropServices.Marshal.ReadInt16(caps,0));
                                ushort page=unchecked((ushort)System.Runtime.InteropServices.Marshal.ReadInt16(caps,2));
                                if(page==1 && (usage==4 || usage==5))count++;
                            }finally{System.Runtime.InteropServices.Marshal.FreeHGlobal(caps);}
                        }finally{HidD_FreePreparsedData(pp);}
                    }
                }finally{System.Runtime.InteropServices.Marshal.FreeHGlobal(buffer);}
            }
        }finally{SetupDiDestroyDeviceInfoList(set);}
        return count;
    }
}
