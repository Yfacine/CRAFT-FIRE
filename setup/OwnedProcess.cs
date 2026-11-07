// Windows-only foundation runner. Compiled in the isolated D environment, never shipped.
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace PassAiFire.Execution {
 public sealed class StageResult {
  public int RootPid; public bool JobAssigned; public bool AtomicJobCreation; public bool RootExited; public bool TimedOut;
  public int ExitCode = -1; public bool CleanupRequested; public bool CleanupSucceeded;
  public uint ActiveAfter; public long ElapsedMilliseconds; public string Failure = "";
 }
 public static class OwnedStage {
  [StructLayout(LayoutKind.Sequential)] struct Security { public int Length; public IntPtr Descriptor; public int Inherit; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Startup {
   public int Size; public string Reserved, Desktop, Title;
   public uint X,Y,XSize,YSize,XChars,YChars,Fill,Flags; public short Show,ReservedBytes;
   public IntPtr ReservedPointer,Input,Output,Error;
  }
  [StructLayout(LayoutKind.Sequential)] struct StartupEx { public Startup Info; public IntPtr Attributes; }
  [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr Process,Thread; public uint Pid,Tid; }
  [StructLayout(LayoutKind.Sequential)] struct BasicLimits {
   public long ProcessTime,JobTime; public uint Flags; public UIntPtr MinWorking,MaxWorking;
   public uint ActiveLimit; public UIntPtr Affinity; public uint Priority,Scheduling;
  }
  [StructLayout(LayoutKind.Sequential)] struct Io { public ulong A,B,C,D,E,F; }
  [StructLayout(LayoutKind.Sequential)] struct Limits { public BasicLimits Basic; public Io Io; public UIntPtr ProcessMemory,JobMemory,PeakProcess,PeakJob; }
  [StructLayout(LayoutKind.Sequential)] struct Accounting { public long A,B,C,D; public uint Faults,Total,Active,Terminated; }
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateJobObjectW(IntPtr security,IntPtr name);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int kind,ref Limits data,uint length);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int kind,out Accounting data,uint length,IntPtr returned);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool IsProcessInJob(IntPtr process,IntPtr job,out bool member);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateJobObject(IntPtr job,uint code);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateProcess(IntPtr process,uint code);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr process,out uint code);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateFileW(string path,uint access,uint sharing,ref Security security,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcessW(string application,StringBuilder command,IntPtr processSecurity,IntPtr threadSecurity,bool inherit,uint flags,IntPtr environment,string directory,ref StartupEx startup,out ProcessInfo process);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,uint flags,ref IntPtr size);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,IntPtr attribute,IntPtr value,IntPtr size,IntPtr previous,IntPtr returned);
  [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
  static Exception Error(string operation) { return new Win32Exception(Marshal.GetLastWin32Error(),operation); }
  static uint Active(IntPtr job) {
   Accounting a; if(!QueryInformationJobObject(job,1,out a,(uint)Marshal.SizeOf(typeof(Accounting)),IntPtr.Zero)) throw Error("Query job accounting"); return a.Active;
  }
  static bool Drain(IntPtr job,IntPtr process,int milliseconds) {
   Stopwatch timer=Stopwatch.StartNew();
   do { if(Active(job)==0 && WaitForSingleObject(process,0)==0) return true; Thread.Sleep(20); } while(timer.ElapsedMilliseconds<milliseconds);
   return Active(job)==0 && WaitForSingleObject(process,0)==0;
  }
  // CommandLineToArgvW/MS C runtime quoting: preserve spaces, quotes, empty args and trailing slashes.
  public static string Quote(string value) {
   StringBuilder b=new StringBuilder("\""); int slashes=0;
   foreach(char c in value) {
    if(c=='\\') { slashes++; continue; }
    if(c=='\"') { b.Append('\\',slashes*2+1); b.Append(c); }
    else { b.Append('\\',slashes); b.Append(c); }
    slashes=0;
   }
   b.Append('\\',slashes*2); return b.Append('"').ToString();
  }
  public static StageResult Run(string executable,string[] arguments,string directory,string log,int timeoutMs,int graceMs,int cleanupMs) {
   StageResult r=new StageResult(); Stopwatch timer=Stopwatch.StartNew();
   IntPtr job=IntPtr.Zero,output=IntPtr.Zero,input=IntPtr.Zero,attributes=IntPtr.Zero,handles=IntPtr.Zero,jobList=IntPtr.Zero;
   ProcessInfo p=new ProcessInfo(); bool initialized=false;
   try {
    job=CreateJobObjectW(IntPtr.Zero,IntPtr.Zero); if(job==IntPtr.Zero) throw Error("Create job");
    Limits limits=new Limits(); limits.Basic.Flags=0x2000; // KILL_ON_JOB_CLOSE; no breakaway permitted.
    if(!SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf(typeof(Limits)))) throw Error("Set kill-on-close");
    Security security=new Security(); security.Length=Marshal.SizeOf(typeof(Security)); security.Inherit=1;
    output=CreateFileW(log,0x40000000,3,ref security,1,0,IntPtr.Zero);
    if(output==new IntPtr(-1)) { output=IntPtr.Zero; throw Error("Create new stage log"); }
    input=CreateFileW("NUL",0x80000000,3,ref security,3,0,IntPtr.Zero);
    if(input==new IntPtr(-1)) { input=IntPtr.Zero; throw Error("Open NUL input"); }
    IntPtr size=IntPtr.Zero; InitializeProcThreadAttributeList(IntPtr.Zero,2,0,ref size);
    attributes=Marshal.AllocHGlobal(size);
    if(!InitializeProcThreadAttributeList(attributes,2,0,ref size)) throw Error("Initialize creation attributes"); initialized=true;
    handles=Marshal.AllocHGlobal(IntPtr.Size*2); Marshal.WriteIntPtr(handles,0,output); Marshal.WriteIntPtr(handles,IntPtr.Size,input);
    if(!UpdateProcThreadAttribute(attributes,0,new IntPtr(0x20002),handles,new IntPtr(IntPtr.Size*2),IntPtr.Zero,IntPtr.Zero)) throw Error("Restrict inherited handles");
    jobList=Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(jobList,job);
    // JOB_LIST is applied atomically by CreateProcessW (Windows 10+). No create/assign orphan gap.
    if(!UpdateProcThreadAttribute(attributes,0,new IntPtr(0x2000d),jobList,new IntPtr(IntPtr.Size),IntPtr.Zero,IntPtr.Zero)) throw Error("Set atomic job creation attribute");
    StartupEx start=new StartupEx(); start.Info.Size=Marshal.SizeOf(typeof(StartupEx)); start.Info.Flags=0x100;
    start.Info.Input=input; start.Info.Output=output; start.Info.Error=output; start.Attributes=attributes;
    StringBuilder command=new StringBuilder(Quote(executable)); foreach(string argument in arguments) command.Append(" ").Append(Quote(argument));
    // Already in the job at birth; suspension also permits verification before any user code runs.
    if(!CreateProcessW(executable,command,IntPtr.Zero,IntPtr.Zero,true,0x08080004,IntPtr.Zero,directory,ref start,out p)) throw Error("Create suspended process");
    r.RootPid=unchecked((int)p.Pid); r.JobAssigned=true; r.AtomicJobCreation=true;
    bool member; if(!IsProcessInJob(p.Process,job,out member) || !member) throw Error("Verify created process job membership");
    if(ResumeThread(p.Thread)==0xffffffff) throw Error("Resume owned process");
    uint wait=WaitForSingleObject(p.Process,(uint)timeoutMs);
    if(wait==258) { r.TimedOut=true; r.Failure="TIMEOUT"; }
    else if(wait!=0) throw Error("Wait for root process");
    else if(!Drain(job,p.Process,graceMs)) r.Failure="DESCENDANTS_REMAINED";
   } catch(Exception e) { r.Failure=e.GetType().Name+": "+e.Message; }
   finally {
    try {
     if(p.Process!=IntPtr.Zero) {
      if(r.JobAssigned) {
       if(Active(job)>0) { r.CleanupRequested=true; if(!TerminateJobObject(job,124)) throw Error("Terminate owned job"); }
       r.CleanupSucceeded=Drain(job,p.Process,cleanupMs); r.ActiveAfter=Active(job);
      } else { r.CleanupRequested=true; if(!TerminateProcess(p.Process,125)) throw Error("Terminate unassigned suspended process"); r.CleanupSucceeded=WaitForSingleObject(p.Process,(uint)cleanupMs)==0; }
      r.RootExited=WaitForSingleObject(p.Process,0)==0; uint code;
      if(r.RootExited && GetExitCodeProcess(p.Process,out code)) r.ExitCode=unchecked((int)code);
      if(!r.RootExited || !r.CleanupSucceeded) r.Failure+=(r.Failure.Length>0?"; ":"")+"CLEANUP_FAILED";
      if(r.Failure.Length==0 && r.ExitCode!=0) r.Failure="EXIT_CODE_"+r.ExitCode;
     } else r.CleanupSucceeded=true;
    } catch(Exception e) { r.CleanupSucceeded=false; r.Failure+="; cleanup: "+e.Message; }
    // Closing the last noninherited job handle also protects abrupt owner-host termination.
    if(job!=IntPtr.Zero) CloseHandle(job);
    if(p.Thread!=IntPtr.Zero) CloseHandle(p.Thread); if(p.Process!=IntPtr.Zero) CloseHandle(p.Process);
    if(output!=IntPtr.Zero) CloseHandle(output); if(input!=IntPtr.Zero) CloseHandle(input);
    if(initialized) DeleteProcThreadAttributeList(attributes);
    if(attributes!=IntPtr.Zero) Marshal.FreeHGlobal(attributes); if(handles!=IntPtr.Zero) Marshal.FreeHGlobal(handles); if(jobList!=IntPtr.Zero) Marshal.FreeHGlobal(jobList);
    r.ElapsedMilliseconds=timer.ElapsedMilliseconds;
   }
   return r;
  }
 }
}
