// UniGetUIPortable: readable Windows NativeAOT launcher and scoped TraceGuard.
// Copyright (c) 2026. Released under MIT (see legal/LAUNCHER-LICENSE.txt).
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

internal static class Program
{
    const string AppRelative = "App/UniGetUI";
    static string Root = "";
    static string Data = "";
    static string Guard = "";
    static string App = "";

    [DllImport("user32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
    static extern int MessageBoxW(nint hWnd, string text, string caption, uint type);

    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool CreateDirectoryW(string path, nint securityAttributes);

    static int Main(string[] args)
    {
        // Return a known nonzero code to validate GUI-subsystem process handling in CI.
        if (args.Length == 1 && args[0] == "--traceguard-exit-probe")
            return 7;
        if (args.Length == 1 && args[0] == "--traceguard-self-test")
            return SelfTest() ? 0 : 2;
        if (args.Length == 1 && args[0] == "--traceguard-powershell-self-test")
            return PowerShellScopeSelfTest() ? 0 : 3;
        Root = Path.GetFullPath(AppContext.BaseDirectory);
        Data = Path.Combine(Root, "Data");
        Guard = Path.Combine(Data, "TraceGuard");
        App = Path.Combine(Root, AppRelative);
        try
        {
            if (!Directory.Exists(App) || !File.Exists(Path.Combine(App, "UniGetUI.exe")))
                throw new IOException("UniGetUI.exe is missing from App/UniGetUI.");
            AssertSafePath(Root);
            AssertSafePath(App);
            AssertSafePath(Data);
            Directory.CreateDirectory(Data);
            Directory.CreateDirectory(Guard);
            using var mutex = new Mutex(false, "Local\\UniGetUIPortable_" + HashString(Root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).ToUpperInvariant())[..24]);
            bool acquired;
            try { acquired = mutex.WaitOne(0); }
            catch (AbandonedMutexException) { acquired = true; }
            if (!acquired)
                throw new IOException("This portable UniGetUI copy is already running. Close it first.");
            try { return Launch(args); }
            finally { mutex.ReleaseMutex(); }
        }
        catch (Exception ex)
        {
            WriteLog("FATAL " + ex);
            MessageBoxW(0, ex.Message + "\n\nSee Data\\TraceGuard\\launcher.log", "UniGetUI Portable - safe stop", 0x10);
            return 1;
        }
    }

    static int Launch(string[] args)
    {
        string statePath = Path.Combine(Guard, "session.json");
        RecoverInterruptedSession(statePath);
        string runtimeSettings = Path.Combine(App, "Settings");
        string savedSettings = Path.Combine(Data, "Settings");
        // The upstream app requires Settings beside its EXE; never modify its executable.
        // The canonical saved copy stays under Data, even while the app is running.
        if (Directory.Exists(runtimeSettings))
        {
            Mirror(runtimeSettings, savedSettings, Path.Combine(Guard, "Conflicts"), true);
            RemoveCapturedTree(runtimeSettings, savedSettings);
        }
        Directory.CreateDirectory(savedSettings);
        Mirror(savedSettings, runtimeSettings, Path.Combine(Guard, "Conflicts"), false);
        File.WriteAllText(Path.Combine(App, "ForceUniGetUIPortable"), "");
        string instanceFile = Path.Combine(Guard, "instance-id.txt");
        if (!File.Exists(instanceFile)) File.WriteAllText(instanceFile, Guid.NewGuid().ToString("N"));
        string id = File.ReadAllText(instanceFile).Trim();
        if (id.Length != 32 || !Guid.TryParseExact(id, "N", out _))
            throw new IOException("Invalid TraceGuard instance id. Refusing to change credential namespace.");
        var scopes = GetScopes();
        var journal = new Journal(Environment.MachineName, Environment.UserName, DateTime.UtcNow,
            scopes.Select(s => MakeScopeState(s.Key, s.Value)).ToList());
        SaveJournal(statePath, journal); // written before starting any external processes
        // PSResourceGet and PackageManagement are shared Windows-user state, not
        // UniGetUI-owned profiles. Only provision a saved copy when the host path
        // was completely absent before launch. Never replace an existing host path.
        journal = RestoreSharedPowerShellScopes(journal, statePath);
        using var process = new Process();
        process.StartInfo.FileName = Path.Combine(App, "UniGetUI.exe");
        process.StartInfo.WorkingDirectory = App;
        process.StartInfo.UseShellExecute = false;
        process.StartInfo.Environment["UNIGETUI_GITHUB_TOKEN_NAMESPACE"] = "portable-" + id;
        foreach (var argument in args) process.StartInfo.ArgumentList.Add(argument);
        bool started = false;
        try
        {
            if (!process.Start()) throw new IOException("UniGetUI did not start.");
            started = true;
            WriteLog("Started upstream UniGetUI PID " + process.Id);
            // Periodically checkpoint new / modified data while the app is running.
            // If a file is locked or changes during copying, leave it for the next pass.
            while (!process.WaitForExit(15000))
                TryCheckpoint(runtimeSettings, savedSettings);
            // A bounded settle interval for last-moment releases of application files.
            Thread.Sleep(1000);
            Mirror(runtimeSettings, savedSettings, Path.Combine(Guard, "Conflicts"), true);
            RemoveCapturedTree(runtimeSettings, savedSettings);
            CaptureExternal(journal);
            File.Delete(statePath);
            WriteLog("Clean shutdown; data preserved, exit=" + process.ExitCode);
            return process.ExitCode;
        }
        catch
        {
            WriteLog("Incomplete session. Runtime Settings and session journal intentionally retained for recovery.");
            throw;
        }
        finally
        {
            if (!started) TryCheckpoint(runtimeSettings, savedSettings);
        }
    }

    static void RecoverInterruptedSession(string journalPath)
    {
        string runtime = Path.Combine(App, "Settings");
        if (Directory.Exists(runtime))
        {
            WriteLog("Recovering Settings left by interrupted launch.");
            Mirror(runtime, Path.Combine(Data, "Settings"), Path.Combine(Guard, "Conflicts"), true);
            RemoveCapturedTree(runtime, Path.Combine(Data, "Settings"));
        }
        if (!File.Exists(journalPath)) return;
        Journal? journal = JsonSerializer.Deserialize(File.ReadAllText(journalPath), AppJsonContext.Default.Journal);
        if (journal is null) throw new IOException("Cannot read TraceGuard recovery journal.");
        if (!string.Equals(journal.Machine, Environment.MachineName, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(journal.User, Environment.UserName, StringComparison.OrdinalIgnoreCase))
        {
            WriteLog("Previous journal is from another Windows account/machine; external cleanup skipped.");
            File.Move(journalPath, Path.Combine(Guard, "session-other-host-" + DateTime.UtcNow.Ticks + ".json"));
            return;
        }
        CaptureExternal(journal);
        File.Delete(journalPath);
    }

    static Dictionary<string, string> GetScopes()
    {
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string common = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        // Exact known app-owned scopes, never parent trees like AppData or ProgramData.
        return new Dictionary<string, string> {
            ["LocalAppData_UniGetUI"] = Path.Combine(local, "UniGetUI"),
            ["LocalAppData_Devolutions_Pinget"] = Path.Combine(local, "Devolutions", "Pinget"),
            ["AppData_UniGetUI"] = Path.Combine(roaming, "UniGetUI"),
            ["Temp_UniGetUI"] = Path.Combine(Path.GetTempPath(), "UniGetUI"),
            ["ProgramData_UniGetUI"] = Path.Combine(common, "UniGetUI"),
            ["LocalAppData_PSResourceGet"] = Path.Combine(local, "PSResourceGet"),
            ["LocalAppData_PackageManagement"] = Path.Combine(local, "PackageManagement")
        };
    }

    static bool IsSharedPowerShellScope(string key) =>
        key is "LocalAppData_PSResourceGet" or "LocalAppData_PackageManagement";

    static ScopeState MakeScopeState(string key, string path)
    {
        bool existed = Directory.Exists(path);
        if (!existed) return new ScopeState(key, path, false, new List<string>(), false);
        if (IsSharedPowerShellScope(key))
        {
            // These locations belong to PowerShell itself and may be used by
            // unrelated software. Never snapshot or migrate a pre-existing root.
            WriteLog("HOST PROTECTED pre-existing shared PowerShell path: " + path);
            return new ScopeState(key, path, true, new List<string>(), true);
        }
        try { return new ScopeState(key, path, true, Snapshot(path), false); }
        catch (Exception ex)
        {
            WriteLog("HOST PROTECTED unreadable scope (observe only): " + path + ": " + ex.Message);
            return new ScopeState(key, path, true, new List<string>(), true);
        }
    }

    static List<string> Snapshot(string scope)
    {
        // Track paths, including completely empty directories, but never follow junctions.
        var items = new List<string>();
        foreach (string path in SafeEntries(scope))
        {
            if (items.Count >= 100000)
                throw new IOException("Too many external paths to snapshot safely: " + scope);
            items.Add(Path.GetRelativePath(scope, path));
        }
        return items;
    }

    static void CaptureExternal(Journal journal, Dictionary<string, string>? allowed = null)
    {
        var allowedScopes = allowed ?? GetScopes();
        foreach (ScopeState entry in journal.Scopes)
        {
            if (entry.SkipCapture) { WriteLog("HOST PROTECTED inaccessible scope: " + entry.Path); continue; }
            if (!allowedScopes.TryGetValue(entry.Key, out string? expected) ||
                !string.Equals(expected, entry.Path, StringComparison.OrdinalIgnoreCase))
            {
                WriteLog("HOST PROTECTED scope path mismatch: " + entry.Path);
                continue;
            }
            if (!Directory.Exists(entry.Path)) continue;
            if (IsSharedPowerShellScope(entry.Key) && entry.ExistedBefore)
            {
                WriteLog("HOST PROTECTED existing shared PowerShell state: " + entry.Path);
                continue;
            }
            if (entry.Key == "LocalAppData_PackageManagement" && HasInstalledProviders(entry.Path))
            {
                // PowerShell's ProviderAssemblies are installed CurrentUser
                // components. Taking them offline may break other applications.
                WriteLog("HOST PROTECTED installed PackageManagement provider assemblies: " + entry.Path);
                continue;
            }
            try
            {
                AssertSafePath(entry.Path);
                string dest = Path.Combine(Guard, "External", entry.Key);
                if (!entry.ExistedBefore)
                {
                    Mirror(entry.Path, dest, Path.Combine(Guard, "Conflicts"), true);
                    if (IsSharedPowerShellScope(entry.Key))
                        RemoveCapturedTreeNonRecursive(entry.Path, dest);
                    else
                        RemoveCapturedTree(entry.Path, dest);
                    WriteLog("Captured new external directory: " + entry.Key);
                }
                else
                {
                    // A pre-existing host profile must remain. Only new children are captured.
                    // Existing files, including modified ones, belong to the host and are not moved.
                    var old = new HashSet<string>(entry.Preexisting, StringComparer.OrdinalIgnoreCase);
                    var newer = SafeEntries(entry.Path).Where(p => !old.Contains(Path.GetRelativePath(entry.Path, p))).ToList();
                    foreach (string dir in newer.Where(Directory.Exists))
                        Directory.CreateDirectory(Path.Combine(dest, Path.GetRelativePath(entry.Path, dir)));
                    foreach (string file in newer.Where(File.Exists))
                    {
                        string rel = Path.GetRelativePath(entry.Path, file);
                        CopyOne(file, Path.Combine(dest, rel), Path.Combine(Guard, "Conflicts"), rel, true);
                    }
                    // Verify each new file survives bit-for-bit before deleting its host copy.
                    foreach (string file in newer.Where(File.Exists))
                    {
                        string rel = Path.GetRelativePath(entry.Path, file);
                        if (!SameBytes(file, Path.Combine(dest, rel)))
                            throw new IOException("Unverified new host file left untouched: " + rel);
                    }
                    foreach (string file in newer.Where(File.Exists)) File.Delete(file);
                    foreach (string dir in newer.Where(Directory.Exists).OrderByDescending(p => p.Length))
                    {
                        if (Directory.Exists(dir)) Directory.Delete(dir, false); // never recursive into host data
                    }
                    if (newer.Count > 0) WriteLog("Captured newly created items under protected host scope: " + entry.Key);
                }
            }
            catch (Exception ex)
            {
                WriteLog("External recovery pending: " + entry.Key + ": " + ex.Message);
                throw;
            }
        }
    }

    // Shared PowerShell storage can belong to other programs. We only restore
    // a previous portable copy if that entire host root was absent at launch.
    // The durable session journal exists before any rehydration happens.
    static Journal RestoreSharedPowerShellScopes(Journal journal, string journalPath,
        Dictionary<string, string>? allowed = null)
    {
        var allowedScopes = allowed ?? GetScopes();
        var states = journal.Scopes.ToList();
        bool changed = false;
        for (int i = 0; i < states.Count; i++)
        {
            ScopeState entry = states[i];
            if (!IsSharedPowerShellScope(entry.Key) || entry.ExistedBefore || entry.SkipCapture)
                continue;
            if (!allowedScopes.TryGetValue(entry.Key, out string? expected) ||
                !string.Equals(entry.Path, expected, StringComparison.OrdinalIgnoreCase))
                throw new IOException("Shared PowerShell scope unexpectedly changed: " + entry.Key);
            string saved = Path.Combine(Guard, "External", entry.Key);
            if (!Directory.Exists(saved)) continue; // first launch: let PowerShell create it
            if (entry.Key == "LocalAppData_PackageManagement" && HasInstalledProviders(saved))
            {
                WriteLog("HOST PROTECTED saved PackageManagement provider assemblies: " + saved);
                states[i] = entry with { SkipCapture = true };
                changed = true;
                continue;
            }
            AssertSafePath(saved);
            AssertSafePath(entry.Path);
            // Win32 CreateDirectoryW fails atomically if another program created
            // the root since our snapshot. Do not merge with that host data.
            if (!CreateDirectoryW(entry.Path, 0))
            {
                int error = Marshal.GetLastWin32Error();
                if (error != 183) throw new IOException("Cannot safely create PowerShell session root: " + entry.Path + "; Win32=" + error);
                WriteLog("HOST PROTECTED PowerShell root appeared during launch: " + entry.Path);
                states[i] = entry with { SkipCapture = true };
                changed = true;
                continue;
            }
            Mirror(saved, entry.Path, Path.Combine(Guard, "Conflicts"), true);
            AssertTreeMatches(saved, entry.Path);
            WriteLog("Rehydrated captured PowerShell state for session: " + entry.Key);
        }
        if (changed)
        {
            var updated = journal with { Scopes = states };
            SaveJournal(journalPath, updated);
            return updated;
        }
        return journal;
    }

    static bool HasInstalledProviders(string root)
    {
        string providerAssemblies = Path.Combine(root, "ProviderAssemblies");
        if (!Directory.Exists(providerAssemblies)) return false;
        try { return SafeEntries(providerAssemblies).Any(File.Exists); }
        catch (Exception ex)
        {
            WriteLog("HOST PROTECTED unreadable provider assemblies: " + ex.Message);
            return true;
        }
    }

    static void AssertTreeMatches(string source, string destination)
    {
        if (!Directory.Exists(source) || !Directory.Exists(destination))
            throw new IOException("Source or destination folder missing during copy verification.");
        foreach (string item in SafeEntries(source))
        {
            string target = Path.Combine(destination, Path.GetRelativePath(source, item));
            if (Directory.Exists(item))
            {
                if (!Directory.Exists(target)) throw new IOException("Missing empty folder: " + target);
            }
            else if (!File.Exists(target) || !SameBytes(item, target))
                throw new IOException("Unverified PowerShell state: " + target);
        }
    }

    static void RemoveCapturedTreeNonRecursive(string source, string destination)
    {
        // Fail safely if a concurrent process introduces anything not captured.
        // Unlike Directory.Delete(..., true), this will not remove surprise files.
        AssertSafePath(source);
        AssertTreeMatches(source, destination);
        var paths = SafeEntries(source).ToList();
        foreach (string file in paths.Where(File.Exists))
        {
            string target = Path.Combine(destination, Path.GetRelativePath(source, file));
            if (!SameBytes(file, target)) throw new IOException("External file changed during cleanup: " + file);
            File.Delete(file);
        }
        foreach (string dir in paths.Where(Directory.Exists).OrderByDescending(x => x.Length))
            Directory.Delete(dir, false);
        Directory.Delete(source, false);
    }

    // Monotonic merging: never silently overwrite conflicting content; preserves empty directories.
    static void Mirror(string source, string destination, string conflicts, bool verifyAfterCopy)
    {
        if (!Directory.Exists(source)) { Directory.CreateDirectory(destination); return; }
        AssertSafePath(source);
        AssertSafePath(destination);
        Directory.CreateDirectory(destination);
        var entries = SafeEntries(source).ToList();
        foreach (string dir in entries.Where(Directory.Exists))
        {
            string rel = Path.GetRelativePath(source, dir);
            Directory.CreateDirectory(Path.Combine(destination, rel));
        }
        foreach (string file in entries.Where(File.Exists))
        {
            string rel = Path.GetRelativePath(source, file);
            CopyOne(file, Path.Combine(destination, rel), conflicts, rel, verifyAfterCopy);
        }
    }

    static void CopyOne(string file, string target, string conflicts, string rel, bool verifyAfterCopy)
    {
        AssertSafePath(file);
        AssertSafePath(target);
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        if (File.Exists(target))
        {
            var s = new FileInfo(file); var t = new FileInfo(target);
            if (s.Length == t.Length && s.LastWriteTimeUtc == t.LastWriteTimeUtc && SameBytes(file, target)) return;
            bool incomingNewer = s.LastWriteTimeUtc >= t.LastWriteTimeUtc;
            if (!incomingNewer)
            {
                PreserveConflict(file, conflicts, rel, "incoming-older");
                return;
            }
            PreserveConflict(target, conflicts, rel, "replaced-existing");
        }
        string temp = target + ".unigetui-tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            File.Copy(file, temp);
            File.SetLastWriteTimeUtc(temp, File.GetLastWriteTimeUtc(file));
            if (verifyAfterCopy && !SameBytes(file, temp))
                throw new IOException("Copy changed during verification: " + rel);
            File.Move(temp, target, true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }

    static void TryCheckpoint(string runtime, string saved)
    {
        try { if (Directory.Exists(runtime)) Mirror(runtime, saved, Path.Combine(Guard, "Conflicts"), true); }
        catch (Exception ex) { WriteLog("Checkpoint deferred (open/modified files): " + ex.Message); }
    }

    static void PreserveConflict(string file, string conflicts, string rel, string reason)
    {
        string relSafe = rel.Replace(':', '_');
        string output = Path.Combine(conflicts, reason, DateTime.UtcNow.ToString("yyyyMMddHHmmssfff") + "-" + Guid.NewGuid().ToString("N"), relSafe);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        File.Copy(file, output);
        if (!SameBytes(file, output)) throw new IOException("Conflict backup verification failed: " + rel);
    }

    static bool SameBytes(string a, string b)
    {
        using var fa = File.OpenRead(a); using var fb = File.OpenRead(b);
        if (fa.Length != fb.Length) return false;
        return SHA256.HashData(fa).AsSpan().SequenceEqual(SHA256.HashData(fb));
    }
    static void RemoveCapturedTree(string path, string destination)
    {
        if (!Directory.Exists(path)) return;
        AssertSafePath(path);
        foreach (string item in SafeEntries(path))
        {
            string rel = Path.GetRelativePath(path, item);
            string copied = Path.Combine(destination, rel);
            if (Directory.Exists(item))
            {
                if (!Directory.Exists(copied)) throw new IOException("Captured empty folder missing: " + rel);
            }
            else if (!File.Exists(copied) || !SameBytes(item, copied))
            {
                // A newer target or simultaneous write must never make us discard source data.
                throw new IOException("Unverified source remains; not deleting: " + rel);
            }
        }
        Directory.Delete(path, true);
    }
    static IEnumerable<string> SafeEntries(string path)
    {
        foreach (string entry in Directory.EnumerateFileSystemEntries(path))
        {
            AssertSafePath(entry);
            yield return entry;
            if (Directory.Exists(entry))
                foreach (string child in SafeEntries(entry)) yield return child;
        }
    }
    static void AssertSafePath(string path)
    {
        // Assert on each existing path element, including directories and files.
        string p = Path.GetFullPath(path);
        while (!string.IsNullOrEmpty(p))
        {
            if (File.Exists(p) || Directory.Exists(p))
            {
                if ((File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Refusing to follow symlink/junction: " + p);
            }
            string? parent = Path.GetDirectoryName(p);
            if (parent == null || parent == p) break;
            p = parent;
        }
    }
    static void SaveJournal(string path, Journal data)
    {
        string temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(data, AppJsonContext.Default.Journal), new UTF8Encoding(false));
        File.Move(temp, path, true);
    }
    static string HashString(string s) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(s))).ToLowerInvariant();
    static void WriteLog(string value)
    {
        try
        {
            string folder = string.IsNullOrWhiteSpace(Guard) ? Path.Combine(Path.GetTempPath(), "UniGetUIPortable") : Guard;
            Directory.CreateDirectory(folder);
            File.AppendAllText(Path.Combine(folder, "launcher.log"), DateTime.UtcNow.ToString("O") + " " + value + Environment.NewLine);
        }
        catch { /* Diagnostics must never delete user data or conceal initial error. */ }
    }
    internal record ScopeState(string Key, string Path, bool ExistedBefore, List<string> Preexisting, bool SkipCapture);
    internal record Journal(string Machine, string User, DateTime StartedUtc, List<ScopeState> Scopes);

    static bool PowerShellScopeSelfTest()
    {
        try
        {
            string t = Path.Combine(Path.GetTempPath(), "UniGetUIPortablePowerShellSelfTest-" + Guid.NewGuid().ToString("N"));
            try
            {
                Root = t; Data = Path.Combine(t, "Data"); Guard = Path.Combine(Data, "TraceGuard");
                App = Path.Combine(t, "App", "UniGetUI");
                string host = Path.Combine(t, "HostLocalAppData");
                string resource = Path.Combine(host, "PSResourceGet");
                string management = Path.Combine(host, "PackageManagement");
                var allowed = new Dictionary<string, string> {
                    ["LocalAppData_PSResourceGet"] = resource,
                    ["LocalAppData_PackageManagement"] = management
                };
                // First launch: an absent root is eligible for session capture.
                var newState = MakeScopeState("LocalAppData_PSResourceGet", resource);
                if (newState.ExistedBefore || newState.SkipCapture) throw new Exception("Missing root treated as pre-existing");
                Directory.CreateDirectory(Path.Combine(resource, "empty", "deep"));
                File.WriteAllText(Path.Combine(resource, "PSResourceRepository.xml"), "test-repositories");
                var first = new Journal(Environment.MachineName, Environment.UserName,
                    DateTime.UtcNow, new List<ScopeState> { newState });
                CaptureExternal(first, allowed);
                string saved = Path.Combine(Guard, "External", "LocalAppData_PSResourceGet");
                if (Directory.Exists(resource) || !File.Exists(Path.Combine(saved, "PSResourceRepository.xml")) ||
                    !Directory.Exists(Path.Combine(saved, "empty", "deep")))
                    throw new Exception("New PSResourceGet root or empty directories not captured");
                // Next launch: rehydrate only when host root remains absent.
                var next = new Journal(Environment.MachineName, Environment.UserName,
                    DateTime.UtcNow, new List<ScopeState> { MakeScopeState("LocalAppData_PSResourceGet", resource) });
                string journalPath = Path.Combine(Guard, "session-test.json");
                SaveJournal(journalPath, next);
                next = RestoreSharedPowerShellScopes(next, journalPath, allowed);
                if (File.ReadAllText(Path.Combine(resource, "PSResourceRepository.xml")) != "test-repositories" ||
                    !Directory.Exists(Path.Combine(resource, "empty", "deep")))
                    throw new Exception("Restoration lost PowerShell repository or empty folder");
                File.WriteAllText(Path.Combine(resource, "PSResourceRepository.xml"), "updated-repositories");
                File.SetLastWriteTimeUtc(Path.Combine(resource, "PSResourceRepository.xml"), DateTime.UtcNow.AddSeconds(2));
                CaptureExternal(next, allowed);
                if (Directory.Exists(resource) ||
                    File.ReadAllText(Path.Combine(saved, "PSResourceRepository.xml")) != "updated-repositories")
                    throw new Exception("Updated portable PowerShell repository was not retained");
                // Existing host settings must never be displaced or overwritten.
                Directory.CreateDirectory(resource);
                File.WriteAllText(Path.Combine(resource, "PSResourceRepository.xml"), "host-own-settings");
                var protectedState = MakeScopeState("LocalAppData_PSResourceGet", resource);
                if (!protectedState.ExistedBefore || !protectedState.SkipCapture)
                    throw new Exception("Pre-existing PSResourceGet host state is not protected");
                var protectedSession = new Journal(Environment.MachineName, Environment.UserName,
                    DateTime.UtcNow, new List<ScopeState> { protectedState });
                protectedSession = RestoreSharedPowerShellScopes(protectedSession, journalPath, allowed);
                CaptureExternal(protectedSession, allowed);
                if (File.ReadAllText(Path.Combine(resource, "PSResourceRepository.xml")) != "host-own-settings" ||
                    File.ReadAllText(Path.Combine(saved, "PSResourceRepository.xml")) != "updated-repositories")
                    throw new Exception("Existing host profile was modified");
                // A root created after our snapshot is treated as a collision.
                Directory.Delete(resource, true);
                var collision = new Journal(Environment.MachineName, Environment.UserName,
                    DateTime.UtcNow, new List<ScopeState> { MakeScopeState("LocalAppData_PSResourceGet", resource) });
                SaveJournal(journalPath, collision);
                Directory.CreateDirectory(resource);
                File.WriteAllText(Path.Combine(resource, "unrelated.txt"), "other-process");
                collision = RestoreSharedPowerShellScopes(collision, journalPath, allowed);
                CaptureExternal(collision, allowed);
                if (!File.Exists(Path.Combine(resource, "unrelated.txt")) || !collision.Scopes[0].SkipCapture)
                    throw new Exception("Unrelated PowerShell collision was not protected");
                // ProviderAssemblies contains installed Windows-user components.
                Directory.CreateDirectory(Path.Combine(management, "ProviderAssemblies", "NuGet"));
                File.WriteAllText(Path.Combine(management, "ProviderAssemblies", "NuGet", "provider.dll"), "fixture");
                var managementPreexisting = MakeScopeState("LocalAppData_PackageManagement", management);
                if (!managementPreexisting.SkipCapture) throw new Exception("Host provider assembly not protected");
                Directory.Delete(management, true);
                var managementNew = new Journal(Environment.MachineName, Environment.UserName,
                    DateTime.UtcNow, new List<ScopeState> { MakeScopeState("LocalAppData_PackageManagement", management) });
                Directory.CreateDirectory(Path.Combine(management, "ProviderAssemblies", "NuGet"));
                File.WriteAllText(Path.Combine(management, "ProviderAssemblies", "NuGet", "provider.dll"), "fixture");
                CaptureExternal(managementNew, allowed);
                if (!File.Exists(Path.Combine(management, "ProviderAssemblies", "NuGet", "provider.dll")))
                    throw new Exception("Installed CurrentUser provider unexpectedly removed");
                // An empty newly created PackageManagement tree is preserved.
                Directory.Delete(management, true);
                var emptyManagement = new Journal(Environment.MachineName, Environment.UserName,
                    DateTime.UtcNow, new List<ScopeState> { MakeScopeState("LocalAppData_PackageManagement", management) });
                Directory.CreateDirectory(Path.Combine(management, "cache", "nested", "empty"));
                CaptureExternal(emptyManagement, allowed);
                if (Directory.Exists(management) || !Directory.Exists(Path.Combine(Guard, "External", "LocalAppData_PackageManagement", "cache", "nested", "empty")))
                    throw new Exception("Empty PackageManagement folders not captured");
                // Crash recovery uses the same saved snapshot and capture routine.
                Directory.Delete(resource, true);
                var interrupted = new Journal(Environment.MachineName, Environment.UserName,
                    DateTime.UtcNow, new List<ScopeState> { MakeScopeState("LocalAppData_PSResourceGet", resource) });
                Directory.CreateDirectory(resource);
                File.WriteAllText(Path.Combine(resource, "PSResourceRepository.xml"), "after-crash");
                CaptureExternal(interrupted, allowed);
                if (Directory.Exists(resource) || File.ReadAllText(Path.Combine(saved, "PSResourceRepository.xml")) != "after-crash")
                    throw new Exception("PowerShell trace crash recovery failed");
            }
            finally { if (Directory.Exists(t)) Directory.Delete(t, true); }
            Console.WriteLine("PowerShell TraceGuard self-test PASS: capture, rehydration, host protection, collision, providers, empty folders, recovery");
            return true;
        }
        catch (Exception ex) { Console.Error.WriteLine("PowerShell TraceGuard self-test FAIL: " + ex); return false; }
    }

    static bool SelfTest()
    {
        try
        {
            string t = Path.Combine(Path.GetTempPath(), "UniGetUIPortableSelfTest-" + Guid.NewGuid().ToString("N"));
            try
            {
                Root = t; Data = Path.Combine(t, "Data"); Guard = Path.Combine(Data, "TraceGuard");
                App = Path.Combine(t, "App", "UniGetUI");
                string s = Path.Combine(t, "source"), d = Path.Combine(t, "dest");
                Directory.CreateDirectory(Path.Combine(s, "nested", "empty", "deeper"));
                Directory.CreateDirectory(Path.Combine(s, "filled"));
                File.WriteAllText(Path.Combine(s, "filled", "test.txt"), "hello");
                Mirror(s, d, Path.Combine(Guard, "Conflicts"), true);
                if (!Directory.Exists(Path.Combine(d, "nested", "empty", "deeper"))) throw new Exception("Nested empty directory lost");
                if (File.ReadAllText(Path.Combine(d, "filled", "test.txt")) != "hello") throw new Exception("File copy failed");
                File.WriteAllText(Path.Combine(d, "filled", "test.txt"), "newer");
                File.SetLastWriteTimeUtc(Path.Combine(d, "filled", "test.txt"), DateTime.UtcNow.AddMinutes(2));
                Mirror(s, d, Path.Combine(Guard, "Conflicts"), true);
                if (File.ReadAllText(Path.Combine(d, "filled", "test.txt")) != "newer") throw new Exception("Newer target overwritten");
                string external = Path.Combine(t, "external");
                Directory.CreateDirectory(Path.Combine(external, "a", "b"));
                Mirror(external, Path.Combine(Data, "TraceGuard", "External", "test"), Path.Combine(Guard, "Conflicts"), true);
                if (!Directory.Exists(Path.Combine(Guard, "External", "test", "a", "b"))) throw new Exception("External empty directory lost");
                RemoveCapturedTree(external, Path.Combine(Guard, "External", "test"));
                if (Directory.Exists(external)) throw new Exception("External cleanup failed");
                // Recovery of uncommitted app Settings into Data.
                Directory.CreateDirectory(Path.Combine(App, "Settings", "crash", "empty"));
                Mirror(Path.Combine(App, "Settings"), Path.Combine(Data, "Settings"), Path.Combine(Guard, "Conflicts"), true);
                if (!Directory.Exists(Path.Combine(Data, "Settings", "crash", "empty"))) throw new Exception("Crash recovery failed");
            }
            finally { if (Directory.Exists(t)) Directory.Delete(t, true); }
            // Do not report PASS until temporary test data has been removed successfully.
            Console.WriteLine("TraceGuard self-test PASS: files, nested empty folders, conflicts, external recovery, crash recovery");
            return true;
        }
        catch (Exception ex) { Console.Error.WriteLine("TraceGuard self-test FAIL: " + ex); return false; }
    }
}

[JsonSourceGenerationOptions(WriteIndented = true)]
[JsonSerializable(typeof(Program.Journal))]
internal partial class AppJsonContext : JsonSerializerContext { }
