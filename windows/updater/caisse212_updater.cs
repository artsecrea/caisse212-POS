// caisse212 updater window. Built by build_windows.ps1 with the .NET Framework
// csc.exe that ships with Windows (C# 5 — no newer syntax), shipped as
// updater\caisse212-updater.exe and run from a copy in %TEMP% so it never
// overwrites itself.
//
// Same steps as the old .bat (UpdateService.windowsUpdaterScript), done in
// process so no console window ever opens: wait for the POS to exit, back up,
// copy the new build, roll back on failure, refresh support\ when that tool
// is idle, relaunch. The log keeps the .bat's wording.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows.Forms;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        var a = new Args(args);
        if (a.Has("elevate")) return Elevate(args);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        var form = new UpdaterForm(a);
        Application.Run(form);
        return form.ExitCode;
    }

    // Relaunches this exe elevated with the same arguments (minus --elevate).
    // 0 = started, 2 = UAC declined, 1 = anything else. The POS waits for this
    // answer before it exits, so a refused prompt keeps the till running.
    static int Elevate(string[] args)
    {
        var rest = new StringBuilder();
        foreach (var arg in args)
        {
            if (arg == "--elevate") continue;
            rest.Append(Quote(arg)).Append(' ');
        }
        try
        {
            var psi = new ProcessStartInfo(Application.ExecutablePath, rest.ToString());
            psi.UseShellExecute = true;
            psi.Verb = "runas";
            Process.Start(psi);
            return 0;
        }
        catch (Win32Exception e)
        {
            return e.NativeErrorCode == 1223 ? 2 : 1;
        }
        catch (Exception)
        {
            return 1;
        }
    }

    // Windows command-line quoting (CommandLineToArgvW rules).
    static string Quote(string s)
    {
        if (s.Length > 0 && s.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) return s;
        var sb = new StringBuilder("\"");
        int slashes = 0;
        foreach (var c in s)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') sb.Append('\\', slashes * 2 + 1);
            else sb.Append('\\', slashes);
            slashes = 0;
            sb.Append(c);
        }
        sb.Append('\\', slashes * 2);
        return sb.Append('"').ToString();
    }
}

class Args
{
    readonly Dictionary<string, string> _values = new Dictionary<string, string>();

    public Args(string[] args)
    {
        for (int i = 0; i < args.Length; i++)
        {
            if (!args[i].StartsWith("--")) continue;
            var key = args[i].Substring(2);
            var hasValue = i + 1 < args.Length && !args[i + 1].StartsWith("--");
            _values[key] = hasValue ? args[++i] : "";
        }
    }

    public bool Has(string key) { return _values.ContainsKey(key); }

    public string Get(string key)
    {
        string v;
        return _values.TryGetValue(key, out v) ? v : null;
    }
}

class Texts
{
    public string Title, Version, Closing, Backup, Installing, Restarting, Failed, DoNotTurnOff;
    public bool Rtl;

    public static Texts For(string lang)
    {
        switch ((lang ?? "").ToLowerInvariant())
        {
            case "en":
                return new Texts
                {
                    Title = "Updating caisse212",
                    Version = "Version {0}",
                    Closing = "Closing the till…",
                    Backup = "Backing up the current version…",
                    Installing = "Installing… {0}%",
                    Restarting = "Restarting the till…",
                    Failed = "The update failed — going back to the previous version",
                    DoNotTurnOff = "Do not turn off the computer.",
                };
            case "ar":
                return new Texts
                {
                    Title = "تحديث caisse212",
                    Version = "الإصدار {0}",
                    Closing = "جارٍ إغلاق نقطة البيع…",
                    Backup = "جارٍ حفظ نسخة احتياطية…",
                    Installing = "جارٍ التثبيت… {0}%",
                    Restarting = "جارٍ إعادة التشغيل…",
                    Failed = "فشل التحديث — العودة إلى الإصدار السابق",
                    DoNotTurnOff = "لا تطفئ الجهاز.",
                    Rtl = true,
                };
            case "es":
                return new Texts
                {
                    Title = "Actualizando caisse212",
                    Version = "Versión {0}",
                    Closing = "Cerrando la caja…",
                    Backup = "Guardando la versión actual…",
                    Installing = "Instalando… {0}%",
                    Restarting = "Reiniciando la caja…",
                    Failed = "La actualización falló: se vuelve a la versión anterior",
                    DoNotTurnOff = "No apague el equipo.",
                };
            default:
                return new Texts
                {
                    Title = "Mise à jour de caisse212",
                    Version = "Version {0}",
                    Closing = "Fermeture de la caisse…",
                    Backup = "Sauvegarde de la version actuelle…",
                    Installing = "Installation… {0}%",
                    Restarting = "Redémarrage de la caisse…",
                    Failed = "La mise à jour a échoué — retour à la version précédente",
                    DoNotTurnOff = "N'éteignez pas l'ordinateur.",
                };
        }
    }
}

class UpdaterForm : Form
{
    public int ExitCode;

    readonly Args _a;
    readonly Texts _t;
    readonly Label _status;
    readonly ProgressBar _bar;

    readonly string _source, _appDir, _exePath, _extract, _log, _backup, _marker, _testRelaunch;
    readonly int _pid;

    static readonly string[] SkipExt = { ".db", ".db-wal", ".db-shm" };

    public UpdaterForm(Args a)
    {
        _a = a;
        _t = Texts.For(a.Get("lang"));
        // The KDS ships this same updater; --app-name puts its name on the window.
        var appName = a.Get("app-name");
        if (!string.IsNullOrEmpty(appName)) _t.Title = _t.Title.Replace("caisse212", appName);
        _source = a.Get("source");
        _appDir = a.Get("app-dir");
        _exePath = a.Get("exe");
        _extract = a.Get("extract") ?? _source;
        var tmp = a.Get("tmp") ?? Path.GetTempPath();
        _log = Path.Combine(tmp, "caisse212-update.log");
        _backup = Path.Combine(tmp, "caisse212-update-backup");
        _marker = a.Get("marker") ?? Path.Combine(tmp, "caisse212-update.ready");
        _testRelaunch = a.Get("test-relaunch");
        int.TryParse(a.Get("pid") ?? "0", out _pid);

        Text = string.IsNullOrEmpty(appName) ? "caisse212" : appName;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        ControlBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        TopMost = true;
        ClientSize = new Size(480, 190);
        BackColor = Color.White;
        Font = new Font("Segoe UI", 10f);
        if (_t.Rtl)
        {
            RightToLeft = RightToLeft.Yes;
            RightToLeftLayout = true;
        }

        var accent = Color.FromArgb(25, 118, 210);
        var title = new Label
        {
            Text = _t.Title,
            Font = new Font("Segoe UI Semibold", 15f),
            ForeColor = accent,
            AutoSize = false,
            Bounds = new Rectangle(24, 18, 432, 34),
        };
        var version = new Label
        {
            Text = string.Format(_t.Version, a.Get("version") ?? ""),
            ForeColor = Color.DimGray,
            AutoSize = false,
            Bounds = new Rectangle(24, 52, 432, 22),
        };
        _status = new Label
        {
            Text = _t.Closing,
            AutoSize = false,
            Bounds = new Rectangle(24, 90, 432, 24),
        };
        _bar = new ProgressBar
        {
            Style = ProgressBarStyle.Marquee,
            MarqueeAnimationSpeed = 30,
            Bounds = new Rectangle(24, 118, 432, 18),
        };
        var hint = new Label
        {
            Text = _t.DoNotTurnOff,
            ForeColor = Color.Gray,
            Font = new Font("Segoe UI", 8.5f),
            AutoSize = false,
            Bounds = new Rectangle(24, 150, 432, 22),
        };
        Controls.AddRange(new Control[] { title, version, _status, _bar, hint });

        Shown += delegate
        {
            var worker = new Thread(Run) { IsBackground = true };
            worker.Start();
        };
    }

    void Ui(Action action)
    {
        try
        {
            if (IsHandleCreated) BeginInvoke(action);
        }
        catch (Exception) { }
    }

    void Status(string text) { Ui(delegate { _status.Text = text; }); }

    void Progress(int done, int total)
    {
        var pct = total == 0 ? 100 : (int)(done * 100L / total);
        Ui(delegate
        {
            if (_bar.Style != ProgressBarStyle.Continuous) _bar.Style = ProgressBarStyle.Continuous;
            _bar.Value = Math.Max(0, Math.Min(100, pct));
            _status.Text = string.Format(_t.Installing, pct);
        });
    }

    void Log(string line)
    {
        try
        {
            File.AppendAllText(_log, "[" + DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss,ff") + "] " + line + "\r\n");
        }
        catch (Exception) { }
    }

    void Run()
    {
        try
        {
            try { File.WriteAllText(_log, ""); } catch (Exception) { }
            Log("waiting for pid " + _pid);
            WaitForExit();
            Thread.Sleep(1000);

            // The exe the NEW build ships (see the .bat for why a rename matters).
            string newExe = null;
            var exes = Directory.GetFiles(_source, "*.exe", SearchOption.TopDirectoryOnly);
            if (exes.Length == 1) newExe = Path.GetFileName(exes[0]);

            Status(_t.Backup);
            Log("backup");
            try
            {
                if (Directory.Exists(_backup)) Directory.Delete(_backup, true);
                CopyTree(_appDir, _backup, Path.Combine(_appDir, "support"), null);
            }
            catch (Exception e)
            {
                Log("backup failed, aborting (no changes): " + e.Message);
                Fail(_exePath);
                return;
            }

            Log("apply");
            try
            {
                CopyTree(_source, _appDir, Path.Combine(_source, "support"), Progress);
            }
            catch (Exception e)
            {
                Log("copy failed, rolling back: " + e.Message);
                try { CopyTree(_backup, _appDir, null, null); }
                catch (Exception r) { Log("rollback incomplete: " + r.Message); }
                Fail(_exePath);
                return;
            }

            // The remote-support tool may be mid-session; its exe is then
            // locked, so it is refreshed only when idle.
            var srcSupport = Path.Combine(_source, "support");
            if (Directory.Exists(srcSupport))
            {
                if (Process.GetProcessesByName("caisse212-support").Length > 0 ||
                    Process.GetProcessesByName("caisse212-tech").Length > 0)
                {
                    Log("support tool running, kept as is");
                }
                else
                {
                    try { CopyTree(srcSupport, Path.Combine(_appDir, "support"), null, null); }
                    catch (Exception e) { Log("support copy incomplete: " + e.Message); }
                }
            }

            Log("ok");
            TryDelete(delegate { File.Delete(_marker); });
            TryDelete(delegate { Directory.Delete(_backup, true); });
            TryDelete(delegate { Directory.Delete(_extract, true); });

            var relaunch = _exePath;
            if (newExe != null && File.Exists(Path.Combine(_appDir, newExe)))
            {
                relaunch = Path.Combine(_appDir, newExe);
                if (!string.Equals(newExe, Path.GetFileName(_exePath), StringComparison.OrdinalIgnoreCase))
                    TryDelete(delegate { File.Delete(_exePath); });
            }
            Status(_t.Restarting);
            Ui(delegate { _bar.Value = 100; });
            Relaunch(relaunch);
            Thread.Sleep(1200);
        }
        catch (Exception e)
        {
            Log("updater error: " + e);
            Relaunch(_exePath);
            ExitCode = 1;
        }
        Ui(Close);
    }

    void Fail(string exe)
    {
        ExitCode = 1;
        Ui(delegate
        {
            _status.ForeColor = Color.Firebrick;
            _status.Text = _t.Failed;
            _bar.Style = ProgressBarStyle.Continuous;
            _bar.Value = 0;
        });
        Thread.Sleep(3000);
        Relaunch(exe);
        Ui(Close);
    }

    // The POS must be gone: its files are locked until it exits, and its
    // single-instance mutex would make the relaunch quit.
    void WaitForExit()
    {
        if (_pid <= 0) return;
        try
        {
            var p = Process.GetProcessById(_pid);
            if (!p.WaitForExit(30000))
            {
                Log("still running, killing");
                try { p.Kill(); } catch (Exception) { }
                p.WaitForExit(5000);
                Thread.Sleep(2000);
            }
        }
        catch (ArgumentException) { } // already gone
        catch (Exception e) { Log("wait: " + e.Message); }
    }

    void Relaunch(string exe)
    {
        if (_testRelaunch != null)
        {
            File.AppendAllText(_testRelaunch, "RELAUNCH=" + exe + "\r\n");
            return;
        }
        try
        {
            // explorer.exe starts the POS as the signed-in user even when this
            // updater runs elevated.
            Process.Start(new ProcessStartInfo("explorer.exe", "\"" + exe + "\"") { UseShellExecute = false });
        }
        catch (Exception e)
        {
            Log("relaunch failed: " + e.Message);
            try { Process.Start(exe); } catch (Exception) { }
        }
    }

    static void TryDelete(Action action)
    {
        try { action(); } catch (Exception) { }
    }

    // Additive copy (like robocopy /E /IS /IT): overwrites every file, never
    // deletes destination files the source lacks, skips local databases.
    // A locked file is retried 3 times, 2s apart, then the copy fails.
    static void CopyTree(string from, string to, string excludeDir, Action<int, int> progress)
    {
        var files = new List<string>();
        Collect(from, excludeDir, files);
        Directory.CreateDirectory(to);
        foreach (var dir in Directory.GetDirectories(from, "*", SearchOption.AllDirectories))
        {
            if (Excluded(dir, excludeDir)) continue;
            Directory.CreateDirectory(Path.Combine(to, dir.Substring(from.Length).TrimStart('\\', '/')));
        }
        for (int i = 0; i < files.Count; i++)
        {
            var src = files[i];
            var dst = Path.Combine(to, src.Substring(from.Length).TrimStart('\\', '/'));
            for (int attempt = 0; ; attempt++)
            {
                try
                {
                    if (File.Exists(dst)) File.SetAttributes(dst, FileAttributes.Normal);
                    File.Copy(src, dst, true);
                    break;
                }
                catch (Exception)
                {
                    if (attempt >= 3) throw;
                    Thread.Sleep(2000);
                }
            }
            if (progress != null) progress(i + 1, files.Count);
        }
    }

    static void Collect(string dir, string excludeDir, List<string> into)
    {
        if (Excluded(dir, excludeDir)) return;
        foreach (var f in Directory.GetFiles(dir))
        {
            var ext = Path.GetExtension(f).ToLowerInvariant();
            if (Array.IndexOf(SkipExt, ext) >= 0) continue;
            into.Add(f);
        }
        foreach (var d in Directory.GetDirectories(dir)) Collect(d, excludeDir, into);
    }

    static bool Excluded(string dir, string excludeDir)
    {
        if (excludeDir == null) return false;
        var d = Path.GetFullPath(dir).TrimEnd('\\');
        var x = Path.GetFullPath(excludeDir).TrimEnd('\\');
        return d.Equals(x, StringComparison.OrdinalIgnoreCase) ||
               d.StartsWith(x + "\\", StringComparison.OrdinalIgnoreCase);
    }
}
