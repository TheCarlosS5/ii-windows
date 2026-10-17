# Puts a process (and every child it starts later) in a Job with a hard CPU cap and one core,
# to emulate a slow PC. Usage: . slowjob.ps1; $job = New-SlowJob -CoreSpeed 35 -Cores 2 (each core at 35 %); Add-ToSlowJob $job $pid
Add-Type -Namespace SlowPc -Name Job -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct CPU_RATE { public uint ControlFlags; public uint CpuRate; }
[StructLayout(LayoutKind.Sequential)] public struct BASIC_LIMIT {
  public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
  public System.UIntPtr MinimumWorkingSetSize; public System.UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit;
  public System.UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass; }
[DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr CreateJobObject(System.IntPtr a, string n);
[DllImport("kernel32.dll")] public static extern bool SetInformationJobObject(System.IntPtr j, int cls, ref CPU_RATE i, uint n);
[DllImport("kernel32.dll")] public static extern bool SetInformationJobObject(System.IntPtr j, int cls, ref BASIC_LIMIT i, uint n);
[DllImport("kernel32.dll")] public static extern bool AssignProcessToJobObject(System.IntPtr j, System.IntPtr p);
[DllImport("kernel32.dll")] public static extern System.IntPtr OpenProcess(uint a, bool i, int pid);
'@
function New-SlowJob([int]$CoreSpeed = 35, [int]$Cores = 2) {
    $j = [SlowPc.Job]::CreateJobObject([IntPtr]::Zero, $null)
    $r = New-Object SlowPc.Job+CPU_RATE
    $r.ControlFlags = 0x1 -bor 0x4   # ENABLE | HARD_CAP
    $r.CpuRate = [uint32]([Math]::Max(1, $Cores * $CoreSpeed * 100 / [Environment]::ProcessorCount)) # % of the whole machine x100
    if (-not [SlowPc.Job]::SetInformationJobObject($j, 15, [ref]$r, 8)) { throw "cpu rate failed" }
    $b = New-Object SlowPc.Job+BASIC_LIMIT
    $b.LimitFlags = 0x10              # JOB_OBJECT_LIMIT_AFFINITY
    $b.Affinity = [UIntPtr][uint64]([Math]::Pow(2, $Cores) - 1)
    if (-not [SlowPc.Job]::SetInformationJobObject($j, 2, [ref]$b, [uint32][Runtime.InteropServices.Marshal]::SizeOf($b))) { throw "affinity failed" }
    $j
}
function Add-ToSlowJob($j, [int]$procId) {
    $h = [SlowPc.Job]::OpenProcess(0x1F0FFF, $false, $procId)
    if (-not [SlowPc.Job]::AssignProcessToJobObject($j, $h)) { throw "assign failed" }
}
