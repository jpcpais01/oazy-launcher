// Oazy Terminal: PowerShell, Command Prompt, WSL, Git Bash and Claude Code in
// an Oazy glass window.
//
// Every shell runs on a Windows pseudoconsole (ConPTY), so programs see a
// real VT terminal: truecolor, mouse, the alternate screen, bracketed paste,
// Unicode. The window is a borderless WinForms form with an acrylic backdrop
// and one transparent WebView2 showing ui/term.html, which draws tabs, split
// panes and the terminals themselves with xterm.js.
//
// The page and this file talk with postMessage. Terminal traffic is plain
// strings ("o<id>:<text>" out, "i<id>:<text>" in, "a<id>:<chars>" to say
// output was drawn); everything else is one JSON object per message
// ({"t": "<type>", ...}).
//
// Like the shell companion and Oazy Browser, Oazy compiles this file on first
// use with the .NET Framework csc.exe that comes with Windows, so it must stay
// C# 5. It references Microsoft.Web.WebView2.Core.dll; Oazy extracts that DLL
// and WebView2Loader.dll next to the compiled exe.
//
// Usage: OazyTerminal.exe --data <dir> [--accent <hex>] [--new-window]
//                         [--profile <id>] [--cwd <dir>] [--run <command line>] [--title <text>]
//        OazyTerminal.exe --selftest <out dir>
// A second launch hands its tab to the running terminal over a named pipe.

using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;
using Microsoft.Web.WebView2.Core;

namespace OazyTerminal
{
	static class Native
	{
		[DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
		[DllImport("kernel32.dll")] public static extern bool TerminateProcess(IntPtr process, uint code);

		[StructLayout(LayoutKind.Sequential)]
		public struct RECT { public int Left, Top, Right, Bottom; }

		[StructLayout(LayoutKind.Sequential)]
		public struct MARGINS { public int Left, Right, Top, Bottom; }

		[StructLayout(LayoutKind.Sequential)]
		public struct MINMAXINFO { public Point Reserved, MaxSize, MaxPosition, MinTrackSize, MaxTrackSize; }

		[StructLayout(LayoutKind.Sequential)]
		public struct NCCALCSIZE_PARAMS
		{
			public RECT r0, r1, r2;
			public IntPtr pos;
		}

		[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
		[DllImport("dwmapi.dll")] public static extern int DwmExtendFrameIntoClientArea(IntPtr h, ref MARGINS m);
		[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
		[DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
		[DllImport("user32.dll")] public static extern bool ReleaseCapture();
		[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
		[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
		[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);
		[DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
		[DllImport("user32.dll")] public static extern int GetSystemMetricsForDpi(int index, uint dpi);
		[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
		[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
		[DllImport("user32.dll")] public static extern bool FlashWindowEx(ref FLASHWINFO info);
		[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
		[DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
		[DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int index, IntPtr value);

		[StructLayout(LayoutKind.Sequential)]
		public struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags, uCount, dwTimeout; }

		// --- Pseudoconsoles ------------------------------------------------------------

		[StructLayout(LayoutKind.Sequential)]
		public struct COORD { public short X, Y; }

		[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
		public struct STARTUPINFO
		{
			public int cb;
			public IntPtr lpReserved, lpDesktop, lpTitle;
			public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
			public short wShowWindow, cbReserved2;
			public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
		}

		[StructLayout(LayoutKind.Sequential)]
		public struct STARTUPINFOEX
		{
			public STARTUPINFO StartupInfo;
			public IntPtr lpAttributeList;
		}

		[StructLayout(LayoutKind.Sequential)]
		public struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

		public const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000, CREATE_UNICODE_ENVIRONMENT = 0x00000400;
		public const int STARTF_USESTDHANDLES = 0x00000100;
		public static readonly IntPtr PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = new IntPtr(0x00020016);

		[DllImport("kernel32.dll", SetLastError = true)] public static extern int CreatePseudoConsole(COORD size, IntPtr input, IntPtr output, uint flags, out IntPtr pc);
		[DllImport("kernel32.dll", SetLastError = true)] public static extern int ResizePseudoConsole(IntPtr pc, COORD size);
		[DllImport("kernel32.dll", SetLastError = true)] public static extern void ClosePseudoConsole(IntPtr pc);
		[DllImport("kernel32.dll", SetLastError = true)] public static extern bool CreatePipe(out IntPtr read, out IntPtr write, IntPtr attrs, int size);
		[DllImport("kernel32.dll", SetLastError = true)] public static extern bool CloseHandle(IntPtr h);
		[DllImport("kernel32.dll", SetLastError = true)] public static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
		[DllImport("kernel32.dll", SetLastError = true)] public static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attr, IntPtr value, IntPtr size, IntPtr prev, IntPtr retSize);
		[DllImport("kernel32.dll", SetLastError = true)] public static extern void DeleteProcThreadAttributeList(IntPtr list);
		[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
		public static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr procAttrs, IntPtr threadAttrs, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFOEX si, out PROCESS_INFORMATION pi);
		[DllImport("kernel32.dll", SetLastError = true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
		[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
	}

	static class Json
	{
		public static readonly JavaScriptSerializer S = new JavaScriptSerializer { MaxJsonLength = int.MaxValue, RecursionLimit = 64 };

		public static string Str(Dictionary<string, object> d, string k)
		{
			object v;
			return d != null && d.TryGetValue(k, out v) && v != null ? Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture) : "";
		}

		public static int Int(Dictionary<string, object> d, string k)
		{
			object v;
			if (d == null || !d.TryGetValue(k, out v) || v == null) return 0;
			try { return Convert.ToInt32(v, System.Globalization.CultureInfo.InvariantCulture); } catch { return 0; }
		}

		public static bool Bool(Dictionary<string, object> d, string k)
		{
			object v;
			return d != null && d.TryGetValue(k, out v) && v is bool && (bool)v;
		}

		public static Dictionary<string, object> Obj(params object[] kv)
		{
			Dictionary<string, object> d = new Dictionary<string, object>();
			for (int i = 0; i + 1 < kv.Length; i += 2) d[(string)kv[i]] = kv[i + 1];
			return d;
		}

		public static Dictionary<string, object> Load(string path)
		{
			try
			{
				if (File.Exists(path))
				{
					Dictionary<string, object> d = S.DeserializeObject(File.ReadAllText(path, Encoding.UTF8)) as Dictionary<string, object>;
					if (d != null) return d;
				}
			}
			catch { }
			return new Dictionary<string, object>();
		}

		public static void Save(string path, object data)
		{
			try
			{
				string tmp = path + ".tmp";
				File.WriteAllText(tmp, S.Serialize(data), new UTF8Encoding(false));
				if (File.Exists(path)) File.Replace(tmp, path, null);
				else File.Move(tmp, path);
			}
			catch { }
		}
	}

	// What a new tab runs: a profile, or a command line of its own.
	class Launch
	{
		public string Profile = "", Cwd = "", Run = "", Title = "";

		public object ToJson() { return Json.Obj("profile", Profile, "cwd", Cwd, "run", Run, "title", Title); }

		public static Launch FromJson(Dictionary<string, object> d)
		{
			return new Launch { Profile = Json.Str(d, "profile"), Cwd = Json.Str(d, "cwd"), Run = Json.Str(d, "run"), Title = Json.Str(d, "title") };
		}

		public bool Empty { get { return Profile == "" && Cwd == "" && Run == "" && Title == ""; } }
	}

	static class Program
	{
		[STAThread]
		static int Main(string[] args)
		{
			string data = "", accent = "", selftest = "";
			bool newWindow = false;
			Launch launch = new Launch();
			for (int i = 0; i < args.Length; i++)
			{
				string a = args[i];
				bool more = i + 1 < args.Length;
				if (a == "--data" && more) data = args[++i];
				else if (a == "--accent" && more) accent = args[++i];
				else if (a == "--selftest" && more) selftest = args[++i];
				else if (a == "--profile" && more) launch.Profile = args[++i];
				else if (a == "--cwd" && more) launch.Cwd = args[++i];
				else if (a == "--run" && more) launch.Run = args[++i];
				else if (a == "--title" && more) launch.Title = args[++i];
				else if (a == "--new-window") newWindow = true;
			}
			if (selftest != "") data = Path.Combine(Path.GetTempPath(), "OazyTerminalSelftest-" + Process.GetCurrentProcess().Id);
			if (data == "") data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Oazy", "Terminal");
			data = Path.GetFullPath(data);

			string pipe = "OazyTerminal-" + App.Hash(Environment.UserName + "|" + data.ToLowerInvariant());
			bool first;
			Mutex single = new Mutex(true, "Local\\" + pipe, out first);
			if (!first && selftest == "")
			{
				if (Forward(pipe, newWindow, launch)) return 0;
				// The running copy isn't answering; carry on as a second one.
			}
			try { if (!Native.SetProcessDpiAwarenessContext(new IntPtr(-4))) Native.SetProcessDPIAware(); }
			catch { try { Native.SetProcessDPIAware(); } catch { } }
			Application.EnableVisualStyles();
			Application.SetCompatibleTextRenderingDefault(false);
			int code = App.Run(data, accent, pipe, launch, selftest);
			GC.KeepAlive(single);
			// Everything is saved, every shell closed and every WebView gone. Leave
			// now rather than let CLR shutdown finalize WebView2's COM objects off
			// their STA thread, which crashes (0xC0000005) on the way out.
			try { single.ReleaseMutex(); } catch { }
			Native.TerminateProcess(Native.GetCurrentProcess(), (uint)code);
			return code;
		}

		static bool Forward(string pipe, bool newWindow, Launch launch)
		{
			for (int attempt = 0; attempt < 3; attempt++)
			{
				try
				{
					using (NamedPipeClientStream c = new NamedPipeClientStream(".", pipe, PipeDirection.Out))
					{
						c.Connect(1000);
						// Let the running terminal bring its window to the front.
						try { Native.AllowSetForegroundWindow(-1); } catch { }
						string text = Json.S.Serialize(Json.Obj("window", newWindow, "tab", launch.ToJson())) + "\n";
						byte[] bytes = Encoding.UTF8.GetBytes(text);
						c.Write(bytes, 0, bytes.Length);
						c.Flush();
						return true;
					}
				}
				catch { Thread.Sleep(300); }
			}
			return false;
		}
	}

	// --- The terminal as a whole: profiles, prefs, windows ------------------------------

	static class App
	{
		public const string UiHost = "oazy.example";
		public const string PageUrl = "https://oazy.example/term.html";
		public const string Name = "Oazy Terminal";

		public static string Data, Ui, Accent = "#38d6c4", Version = "";
		public static CoreWebView2Environment Env;
		public static SynchronizationContext Sync;
		public static readonly List<TermWindow> Windows = new List<TermWindow>();
		public static TermWindow LastActive;
		public static Dictionary<string, object> Prefs;
		public static List<Dictionary<string, object>> ProfileList;
		public static Selftest Test;
		public static bool Quitting { get { return quitting; } }
		static ApplicationContext ctx;
		static bool prefsDirty, quitting;
		static string pipeName;

		public static int Run(string data, string accent, string pipe, Launch launch, string selftest)
		{
			Data = data;
			pipeName = pipe;
			Ui = Path.Combine(Path.GetDirectoryName(Application.ExecutablePath), "ui");
			try { Directory.CreateDirectory(Data); }
			catch (Exception e)
			{
				MessageBox.Show("Oazy Terminal can't use its settings folder:\n" + Data + "\n\n" + e.Message, Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
				return 2;
			}
			try { Version = CoreWebView2Environment.GetAvailableBrowserVersionString(); }
			catch (Exception) { Version = ""; }
			if (string.IsNullOrEmpty(Version))
			{
				NoRuntime();
				return 3;
			}

			Prefs = Json.Load(Path.Combine(Data, "prefs.json"));
			if (accent != "") { Prefs["accent"] = accent; prefsDirty = true; }
			Accent = Json.Str(Prefs, "accent") != "" ? Json.Str(Prefs, "accent") : Accent;
			ProfileList = Profiles.Detect();

			SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());
			Sync = SynchronizationContext.Current;
			ctx = new ApplicationContext();
			System.Windows.Forms.Timer saveTimer = new System.Windows.Forms.Timer { Interval = 2000 };
			saveTimer.Tick += delegate { SaveNow(); };
			saveTimer.Start();
			if (selftest != "") Test = new Selftest(selftest);
			else StartPipe();
			Start(launch);
			Application.Run(ctx);
			SaveNow();
			if (Test != null) Test.Exited();
			return Test != null ? Test.ExitCode : 0;
		}

		static async void Start(Launch launch)
		{
			try
			{
				CoreWebView2EnvironmentOptions opts = new CoreWebView2EnvironmentOptions("--enable-features=OverlayScrollbar");
				Env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(Data, "webview"), opts);
			}
			catch (Exception e)
			{
				MessageBox.Show("Oazy Terminal couldn't start its renderer.\n\n" + e.Message, Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
				ctx.ExitThread();
				return;
			}
			Env.BrowserProcessExited += OnBrowserExited;
			if (Test != null) { Test.Begin(); return; }
			OpenWindow(launch, null);
		}

		public static TermWindow OpenWindow(Launch launch, Rectangle? bounds)
		{
			if (!bounds.HasValue && Windows.Count == 0)
			{
				object[] b = Prefs.ContainsKey("bounds") ? Prefs["bounds"] as object[] : null;
				if (b != null && b.Length == 4)
				{
					try { bounds = new Rectangle(Convert.ToInt32(b[0]), Convert.ToInt32(b[1]), Convert.ToInt32(b[2]), Convert.ToInt32(b[3])); } catch { }
				}
			}
			TermWindow w = new TermWindow(launch, bounds, Windows.Count == 0 && Json.Bool(Prefs, "max"));
			Windows.Add(w);
			LastActive = w;
			w.FormClosed += delegate
			{
				Windows.Remove(w);
				if (LastActive == w) LastActive = Windows.Count > 0 ? Windows[Windows.Count - 1] : null;
				if (Windows.Count == 0) Quit();
			};
			w.Show();
			w.Activate();
			return w;
		}

		public static void Quit()
		{
			if (quitting) return;
			quitting = true;
			SaveNow();
			foreach (TermWindow w in Windows.ToArray()) { try { w.Close(); } catch { } }
			ctx.ExitThread();
		}

		static void OnBrowserExited(object sender, CoreWebView2BrowserProcessExitedEventArgs e)
		{
			if (quitting || e.BrowserProcessExitKind == CoreWebView2BrowserProcessExitKind.Normal) return;
			// The renderer died under us. The shells can't be drawn any more; end
			// cleanly rather than leave windows that look alive.
			Quit();
		}

		static void NoRuntime()
		{
			DialogResult r = MessageBox.Show(
				"Oazy Terminal runs on the Microsoft Edge WebView2 Runtime, which isn't installed on this PC.\n\nOpen the download page now?",
				Name, MessageBoxButtons.YesNo, MessageBoxIcon.Information);
			if (r == DialogResult.Yes)
			{
				try { Process.Start("https://go.microsoft.com/fwlink/p/?LinkId=2124703"); } catch { }
			}
		}

		public static void SetPref(string key, object value)
		{
			Prefs[key] = value;
			prefsDirty = true;
		}

		public static void SaveNow()
		{
			if (!prefsDirty) return;
			prefsDirty = false;
			Json.Save(Path.Combine(Data, "prefs.json"), Prefs);
		}

		// --- Single instance -----------------------------------------------------------

		static void StartPipe()
		{
			Thread t = new Thread(delegate()
			{
				while (!quitting)
				{
					try
					{
						using (NamedPipeServerStream s = new NamedPipeServerStream(pipeName, PipeDirection.In, 1))
						{
							s.WaitForConnection();
							using (StreamReader r = new StreamReader(s, Encoding.UTF8))
							{
								string text = r.ReadToEnd();
								Sync.Post(delegate { OnForward(text); }, null);
							}
						}
					}
					catch { Thread.Sleep(500); }
				}
			});
			t.IsBackground = true;
			t.Name = "Oazy pipe";
			t.Start();
		}

		static void OnForward(string text)
		{
			if (Env == null) return;
			foreach (string line in text.Split('\n'))
			{
				if (line.Trim() == "") continue;
				Dictionary<string, object> m;
				try { m = Json.S.DeserializeObject(line) as Dictionary<string, object>; } catch { continue; }
				if (m == null) continue;
				Launch l = Launch.FromJson(m.ContainsKey("tab") ? m["tab"] as Dictionary<string, object> : null);
				if (Json.Bool(m, "window") || LastActive == null) OpenWindow(l, null);
				else
				{
					LastActive.OpenTab(l);
					LastActive.BringUp();
				}
			}
		}

		// --- Helpers ----------------------------------------------------------------

		public static string Hash(string s)
		{
			using (MD5 md5 = MD5.Create())
			{
				byte[] h = md5.ComputeHash(Encoding.UTF8.GetBytes(s));
				StringBuilder sb = new StringBuilder();
				for (int i = 0; i < 8; i++) sb.Append(h[i].ToString("x2"));
				return sb.ToString();
			}
		}

		public static string Home()
		{
			string h = Environment.GetEnvironmentVariable("USERPROFILE");
			return string.IsNullOrEmpty(h) ? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) : h;
		}

		// The real Windows build (Environment.OSVersion says 9200 to apps without
		// a compatibility manifest). xterm.js wraps lines the way ConPTY does by it.
		public static int WindowsBuild()
		{
			try
			{
				using (RegistryKey k = Registry.LocalMachine.OpenSubKey("SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion"))
				{
					int b;
					if (k != null && int.TryParse(Convert.ToString(k.GetValue("CurrentBuildNumber")), out b)) return b;
				}
			}
			catch { }
			return Environment.OSVersion.Version.Build;
		}

		public static Dictionary<string, object> FindProfile(string id)
		{
			foreach (Dictionary<string, object> p in ProfileList) if (Json.Str(p, "id") == id) return p;
			return null;
		}

		public static string DefaultProfile()
		{
			string id = Json.Str(Prefs, "defaultProfile");
			if (id != "" && FindProfile(id) != null) return id;
			return Json.Str(ProfileList[0], "id");
		}
	}

	// --- Profiles: the shells this PC has -----------------------------------------------

	static class Profiles
	{
		public static List<Dictionary<string, object>> Detect()
		{
			List<Dictionary<string, object>> list = new List<Dictionary<string, object>>();
			string sys = Environment.GetFolderPath(Environment.SpecialFolder.System);
			string pwsh = FindPwsh();
			if (pwsh != null) list.Add(Make("pwsh", "PowerShell", Quote(pwsh) + " -NoLogo", "pwsh"));
			list.Add(Make("powershell", pwsh != null ? "Windows PowerShell" : "PowerShell", Quote(Path.Combine(sys, "WindowsPowerShell\\v1.0\\powershell.exe")) + " -NoLogo", "powershell"));
			list.Add(Make("cmd", "Command Prompt", Quote(Path.Combine(sys, "cmd.exe")), "cmd"));
			string wsl = Path.Combine(sys, "wsl.exe");
			if (File.Exists(wsl))
			{
				foreach (string d in WslDistros())
					list.Add(Make("wsl:" + d, Pretty(d), Quote(wsl) + " -d " + Quote(d) + " --cd ~", "linux"));
			}
			string bash = FindGitBash();
			if (bash != null) list.Add(Make("gitbash", "Git Bash", Quote(bash) + " --login -i", "git"));
			string claude = FindOnPath(new string[] { "claude.exe", "claude.cmd" }, new string[] { Path.Combine(App.Home(), ".local\\bin\\claude.exe") });
			if (claude != null)
			{
				list.Add(Make("claude", "Claude Code", Quote(Path.Combine(sys, "cmd.exe")) + " /k claude", "claude"));
			}
			return list;
		}

		static Dictionary<string, object> Make(string id, string name, string cmd, string icon)
		{
			return Json.Obj("id", id, "name", name, "cmd", cmd, "icon", icon);
		}

		public static string Quote(string s)
		{
			return s.IndexOf(' ') >= 0 || s.IndexOf('\t') >= 0 ? "\"" + s + "\"" : s;
		}

		static string Pretty(string distro)
		{
			// "Ubuntu-24.04" reads better as "Ubuntu 24.04".
			return distro.Replace('-', ' ').Replace('_', ' ');
		}

		static string FindPwsh()
		{
			string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
			foreach (string v in new string[] { "7", "7-preview", "8", "8-preview" })
			{
				string p = Path.Combine(pf, "PowerShell", v, "pwsh.exe");
				if (File.Exists(p)) return p;
			}
			string apps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft\\WindowsApps\\pwsh.exe");
			if (File.Exists(apps)) return apps;
			return FindOnPath(new string[] { "pwsh.exe" }, null);
		}

		static string FindGitBash()
		{
			foreach (RegistryHive hive in new RegistryHive[] { RegistryHive.LocalMachine, RegistryHive.CurrentUser })
			{
				try
				{
					using (RegistryKey root = RegistryKey.OpenBaseKey(hive, RegistryView.Registry64))
					using (RegistryKey k = root.OpenSubKey("SOFTWARE\\GitForWindows"))
					{
						string dir = k != null ? k.GetValue("InstallPath") as string : null;
						if (!string.IsNullOrEmpty(dir) && File.Exists(Path.Combine(dir, "bin\\bash.exe"))) return Path.Combine(dir, "bin\\bash.exe");
					}
				}
				catch { }
			}
			foreach (string root in new string[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs") })
			{
				string p = Path.Combine(root, "Git\\bin\\bash.exe");
				if (File.Exists(p)) return p;
			}
			return null;
		}

		static List<string> WslDistros()
		{
			List<string> names = new List<string>();
			try
			{
				using (RegistryKey k = Registry.CurrentUser.OpenSubKey("Software\\Microsoft\\Windows\\CurrentVersion\\Lxss"))
				{
					if (k == null) return names;
					string def = k.GetValue("DefaultDistribution") as string;
					foreach (string sub in k.GetSubKeyNames())
					{
						using (RegistryKey d = k.OpenSubKey(sub))
						{
							string name = d != null ? d.GetValue("DistributionName") as string : null;
							if (string.IsNullOrEmpty(name) || name.StartsWith("docker-desktop", StringComparison.OrdinalIgnoreCase)) continue;
							if (sub == def) names.Insert(0, name);
							else names.Add(name);
						}
					}
				}
			}
			catch { }
			return names;
		}

		public static string FindOnPath(string[] files, string[] extra)
		{
			if (extra != null) foreach (string e in extra) if (File.Exists(e)) return e;
			string path = Environment.GetEnvironmentVariable("PATH") ?? "";
			foreach (string dir in path.Split(';'))
			{
				string d = dir.Trim().Trim('"');
				if (d == "") continue;
				foreach (string f in files)
				{
					try
					{
						string p = Path.Combine(Environment.ExpandEnvironmentVariables(d), f);
						if (File.Exists(p)) return p;
					}
					catch { }
				}
			}
			return null;
		}
	}

	// --- One shell on a pseudoconsole ----------------------------------------------------

	class Pty
	{
		// Output not yet drawn by the page, in chars. Past this the reader waits,
		// so a flood (a big `dir /s`) can't run ahead of the screen.
		const int HighWater = 2 * 1024 * 1024;

		public readonly int Id;
		public readonly TermWindow Owner;
		public int Pid;
		IntPtr pc, process;
		FileStream input;
		readonly object gate = new object();
		readonly StringBuilder pending = new StringBuilder();
		readonly BlockingCollection<byte[]> writes = new BlockingCollection<byte[]>();
		readonly ManualResetEvent room = new ManualResetEvent(true);
		int unacked;
		bool posted, closed;
		Thread reader;

		public Pty(int id, TermWindow owner)
		{
			Id = id;
			Owner = owner;
		}

		// Starts `cmdline` in `cwd`. Returns null, or why it couldn't.
		public string Start(string cmdline, string cwd, int cols, int rows)
		{
			IntPtr inRead, inWrite, outRead, outWrite;
			if (!Native.CreatePipe(out inRead, out inWrite, IntPtr.Zero, 0)) return "couldn't create a pipe";
			if (!Native.CreatePipe(out outRead, out outWrite, IntPtr.Zero, 0))
			{
				Native.CloseHandle(inRead);
				Native.CloseHandle(inWrite);
				return "couldn't create a pipe";
			}
			int hr = Native.CreatePseudoConsole(Size(cols, rows), inRead, outWrite, 0, out pc);
			// The pseudoconsole keeps its own copies of its ends.
			Native.CloseHandle(inRead);
			Native.CloseHandle(outWrite);
			if (hr != 0)
			{
				Native.CloseHandle(inWrite);
				Native.CloseHandle(outRead);
				return "this version of Windows has no pseudoconsole (0x" + hr.ToString("x8") + ")";
			}

			IntPtr size = IntPtr.Zero;
			Native.InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
			IntPtr attrs = Marshal.AllocHGlobal(size);
			IntPtr env = IntPtr.Zero;
			string error = null;
			try
			{
				if (!Native.InitializeProcThreadAttributeList(attrs, 1, 0, ref size)) error = "attribute list";
				else if (!Native.UpdateProcThreadAttribute(attrs, 0, Native.PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, pc, new IntPtr(IntPtr.Size), IntPtr.Zero, IntPtr.Zero)) error = "pseudoconsole attribute";
				else
				{
					Native.STARTUPINFOEX si = new Native.STARTUPINFOEX();
					si.StartupInfo.cb = Marshal.SizeOf(typeof(Native.STARTUPINFOEX));
					// Null std handles, so the shell can't pick up ours (Oazy may
					// have started us with pipes) instead of the pseudoconsole.
					si.StartupInfo.dwFlags = Native.STARTF_USESTDHANDLES;
					si.lpAttributeList = attrs;
					env = Environment_();
					if (string.IsNullOrEmpty(cwd) || !Directory.Exists(cwd)) cwd = App.Home();
					Native.PROCESS_INFORMATION pi;
					if (!Native.CreateProcessW(null, new StringBuilder(cmdline), IntPtr.Zero, IntPtr.Zero, false,
						Native.EXTENDED_STARTUPINFO_PRESENT | Native.CREATE_UNICODE_ENVIRONMENT, env, cwd, ref si, out pi))
						error = new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()).Message;
					else
					{
						process = pi.hProcess;
						Pid = pi.dwProcessId;
						Native.CloseHandle(pi.hThread);
					}
				}
			}
			finally
			{
				Native.DeleteProcThreadAttributeList(attrs);
				Marshal.FreeHGlobal(attrs);
				if (env != IntPtr.Zero) Marshal.FreeHGlobal(env);
			}
			if (error != null)
			{
				Native.ClosePseudoConsole(pc);
				pc = IntPtr.Zero;
				Native.CloseHandle(inWrite);
				Native.CloseHandle(outRead);
				return error;
			}

			input = new FileStream(new SafeFileHandle(inWrite, true), FileAccess.Write, 1, false);
			FileStream output = new FileStream(new SafeFileHandle(outRead, true), FileAccess.Read, 1, false);
			reader = new Thread(delegate() { Read(output); }) { IsBackground = true, Name = "pty out " + Id };
			reader.Start();
			Thread writer = new Thread(Write_) { IsBackground = true, Name = "pty in " + Id };
			writer.Start();
			Thread waiter = new Thread(Wait) { IsBackground = true, Name = "pty wait " + Id };
			waiter.Start();
			return null;
		}

		static Native.COORD Size(int cols, int rows)
		{
			return new Native.COORD { X = (short)Math.Max(2, Math.Min(2000, cols)), Y = (short)Math.Max(1, Math.Min(1000, rows)) };
		}

		// The shell gets Oazy's environment, saying it's on a truecolor terminal.
		static IntPtr Environment_()
		{
			SortedDictionary<string, string> vars = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
			foreach (DictionaryEntry e in Environment.GetEnvironmentVariables()) vars[(string)e.Key] = (string)e.Value;
			vars["COLORTERM"] = "truecolor";
			vars["TERM_PROGRAM"] = "OazyTerminal";
			vars["TERM_PROGRAM_VERSION"] = "1";
			// Godot's own leftovers mean nothing to a shell.
			vars.Remove("GODOT_SILENCE_ROOT_WARNING");
			StringBuilder sb = new StringBuilder();
			foreach (KeyValuePair<string, string> kv in vars)
			{
				if (kv.Key == "" || kv.Key.IndexOf('=') > 0) continue;
				sb.Append(kv.Key).Append('=').Append(kv.Value).Append('\0');
			}
			sb.Append('\0');
			return Marshal.StringToHGlobalUni(sb.ToString());
		}

		void Read(FileStream output)
		{
			byte[] buf = new byte[65536];
			char[] chars = new char[65536 + 8];
			Decoder dec = new UTF8Encoding(false).GetDecoder();
			try
			{
				while (true)
				{
					room.WaitOne();
					int n;
					try { n = output.Read(buf, 0, buf.Length); } catch { break; }
					if (n <= 0) break;
					int c = dec.GetChars(buf, 0, n, chars, 0, false);
					if (c == 0) continue;
					lock (gate)
					{
						pending.Append(chars, 0, c);
						unacked += c;
						if (unacked > HighWater) room.Reset();
						if (!posted)
						{
							posted = true;
							App.Sync.Post(delegate { Flush(); }, null);
						}
					}
				}
			}
			finally { try { output.Dispose(); } catch { } }
		}

		void Flush()
		{
			string text;
			lock (gate)
			{
				posted = false;
				if (pending.Length == 0) return;
				text = pending.ToString();
				pending.Clear();
			}
			Owner.SendOutput(Id, text);
		}

		// The page drew `chars` of output.
		public void Ack(int chars)
		{
			lock (gate)
			{
				unacked = Math.Max(0, unacked - chars);
				if (unacked <= HighWater / 2) room.Set();
			}
		}

		void Wait()
		{
			Native.WaitForSingleObject(process, 0xFFFFFFFF);
			uint code;
			if (!Native.GetExitCodeProcess(process, out code)) code = 0;
			// Let the last of its output through the pseudoconsole, then close
			// it, which ends the output pipe and so the reader.
			Thread.Sleep(120);
			room.Set();
			ClosePc();
			if (reader != null) reader.Join(3000);
			App.Sync.Post(delegate
			{
				Flush();
				Owner.SessionExited(this, unchecked((int)code));
			}, null);
		}

		void ClosePc()
		{
			IntPtr h;
			lock (gate)
			{
				h = pc;
				pc = IntPtr.Zero;
			}
			if (h != IntPtr.Zero) try { Native.ClosePseudoConsole(h); } catch { }
			writes.CompleteAdding();
		}

		void Write_()
		{
			try
			{
				foreach (byte[] b in writes.GetConsumingEnumerable())
				{
					input.Write(b, 0, b.Length);
					input.Flush();
				}
			}
			catch { }
			try { input.Dispose(); } catch { }
		}

		public void Send(string text)
		{
			if (closed || writes.IsAddingCompleted) return;
			try { writes.Add(Encoding.UTF8.GetBytes(text)); } catch { }
		}

		public void Resize(int cols, int rows)
		{
			lock (gate)
			{
				if (pc != IntPtr.Zero) Native.ResizePseudoConsole(pc, Size(cols, rows));
			}
		}

		// Ends the shell and everything it started in this pane.
		public void Kill()
		{
			if (closed) return;
			closed = true;
			IntPtr p = process;
			ThreadPool.QueueUserWorkItem(delegate
			{
				room.Set();
				ClosePc();
				if (p != IntPtr.Zero && Native.WaitForSingleObject(p, 1500) != 0) Native.TerminateProcess(p, 1);
			});
		}

		public bool Closed { get { return closed; } }
	}

	// --- A terminal window -----------------------------------------------------------------

	class TermWindow : Form
	{
		const int WM_GETMINMAXINFO = 0x24, WM_NCCALCSIZE = 0x83, WM_NCHITTEST = 0x84, WM_DPICHANGED = 0x2E0, WM_MOVE = 0x3, WM_ACTIVATE = 0x6, WM_NCLBUTTONDOWN = 0xA1;
		const int HTCLIENT = 1, HTCAPTION = 2, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14;

		CoreWebView2Controller view;
		bool ready, glass, closing, closeConfirmed, nativeDrag, active;
		readonly List<object> outbox = new List<object>();
		readonly Dictionary<int, Pty> ptys = new Dictionary<int, Pty>();
		readonly List<Launch> launches = new List<Launch>();
		readonly bool startMaximized;
		string title = App.Name;

		public TermWindow(Launch launch, Rectangle? bounds, bool maximized)
		{
			startMaximized = maximized;
			launches.Add(launch);
			Text = App.Name;
			BackColor = Color.Black;
			FormBorderStyle = FormBorderStyle.Sizable;
			StartPosition = FormStartPosition.Manual;
			try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

			Rectangle work = Screen.FromPoint(Cursor.Position).WorkingArea;
			float scale = DpiScale();
			int w = (int)(1100 * scale), h = (int)(700 * scale);
			w = Math.Min(w, work.Width - 40);
			h = Math.Min(h, work.Height - 40);
			Rectangle r = new Rectangle(work.Left + (work.Width - w) / 2, work.Top + (work.Height - h) / 2, w, h);
			if (bounds.HasValue && bounds.Value.Width > 300 && bounds.Value.Height > 200 && Screen.FromRectangle(bounds.Value).WorkingArea.IntersectsWith(bounds.Value))
				r = bounds.Value;
			else if (App.Windows.Count > 0)
				r.Offset((int)(32 * scale * App.Windows.Count), (int)(32 * scale * App.Windows.Count));
			Bounds = r;
			MinimumSize = new Size((int)(420 * scale), (int)(260 * scale));
		}

		static float DpiScale()
		{
			using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) return Math.Max(1f, g.DpiX / 96f);
		}

		float Scale_ { get { try { return Native.GetDpiForWindow(Handle) / 96f; } catch { return 1f; } } }

		// --- Window frame (the same frame as Oazy Browser's) ----------------------------------

		protected override CreateParams CreateParams
		{
			get
			{
				CreateParams cp = base.CreateParams;
				cp.Style &= ~0x00C00000;                                   // WS_CAPTION
				cp.Style |= 0x00040000 | 0x00080000 | 0x00020000 | 0x00010000; // THICKFRAME, SYSMENU, MINIMIZEBOX, MAXIMIZEBOX
				return cp;
			}
		}

		protected override void OnHandleCreated(EventArgs e)
		{
			base.OnHandleCreated(e);
			int dark = 1;
			Native.DwmSetWindowAttribute(Handle, 20, ref dark, 4);
			int round = 2;
			Native.DwmSetWindowAttribute(Handle, 33, ref round, 4);
			// Acrylic behind the whole window (Windows 11 22H2+), Mica before that.
			int acrylic = 3;
			glass = Native.DwmSetWindowAttribute(Handle, 38, ref acrylic, 4) == 0;
			if (!glass)
			{
				int mica = 1;
				glass = Native.DwmSetWindowAttribute(Handle, 1029, ref mica, 4) == 0;
			}
			if (glass)
			{
				Native.MARGINS m = new Native.MARGINS { Left = -1, Right = -1, Top = -1, Bottom = -1 };
				Native.DwmExtendFrameIntoClientArea(Handle, ref m);
			}
			else BackColor = Color.FromArgb(10, 18, 24);
			Native.SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020);
		}

		protected override void OnShown(EventArgs e)
		{
			base.OnShown(e);
			if (startMaximized) WindowState = FormWindowState.Maximized;
			RefreshFrame();
			BeginInvoke((Action)RefreshFrame);
			Init();
		}

		// Until the frame is recalculated once the window is on screen, DWM keeps
		// painting a dark caption strip across the top of the glass (as in Oazy Browser).
		void RefreshFrame()
		{
			int color = unchecked((int)0xFFFFFFFF); // DWMWA_COLOR_DEFAULT
			Native.DwmSetWindowAttribute(Handle, 35, ref color, 4);
			long style = Native.GetWindowLongPtr(Handle, -16).ToInt64() & ~0x00C00000L;
			Native.SetWindowLongPtr(Handle, -16, new IntPtr(style));
			Native.SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020);
		}

		bool Maximized { get { return IsHandleCreated && Native.IsZoomed(Handle); } }

		int TopStrip { get { return Maximized ? 0 : Math.Max(1, (int)Math.Round(3 * Scale_)); } }

		protected override void WndProc(ref Message m)
		{
			switch (m.Msg)
			{
				case WM_NCCALCSIZE:
					if (m.WParam != IntPtr.Zero)
					{
						Native.NCCALCSIZE_PARAMS p = (Native.NCCALCSIZE_PARAMS)Marshal.PtrToStructure(m.LParam, typeof(Native.NCCALCSIZE_PARAMS));
						int top = p.r0.Top;
						base.WndProc(ref m);
						p = (Native.NCCALCSIZE_PARAMS)Marshal.PtrToStructure(m.LParam, typeof(Native.NCCALCSIZE_PARAMS));
						// Keep Windows' side and bottom borders (resizing, shadow), drop the title bar.
						p.r0.Top = top;
						if (Native.IsZoomed(m.HWnd))
						{
							Rectangle wa = Screen.FromHandle(m.HWnd).WorkingArea;
							p.r0.Left = wa.Left;
							p.r0.Top = wa.Top;
							p.r0.Right = wa.Right;
							p.r0.Bottom = wa.Bottom;
						}
						Marshal.StructureToPtr(p, m.LParam, false);
						m.Result = IntPtr.Zero;
						return;
					}
					break;
				case WM_NCHITTEST:
					base.WndProc(ref m);
					if (m.Result.ToInt32() == HTCLIENT && !Maximized)
					{
						Point pt = PointToClient(new Point((short)(m.LParam.ToInt64() & 0xFFFF), (short)((m.LParam.ToInt64() >> 16) & 0xFFFF)));
						int edge = (int)Math.Round(6 * Scale_);
						if (pt.Y < edge)
							m.Result = new IntPtr(pt.X < edge * 2 ? HTTOPLEFT : (pt.X > ClientSize.Width - edge * 2 ? HTTOPRIGHT : HTTOP));
					}
					return;
				case WM_GETMINMAXINFO:
					base.WndProc(ref m);
					{
						Screen sc = Screen.FromHandle(m.HWnd);
						uint dpi = Native.GetDpiForWindow(m.HWnd);
						int fx = Native.GetSystemMetricsForDpi(32, dpi) + Native.GetSystemMetricsForDpi(92, dpi);
						int fy = Native.GetSystemMetricsForDpi(33, dpi) + Native.GetSystemMetricsForDpi(92, dpi);
						Native.MINMAXINFO mm = (Native.MINMAXINFO)Marshal.PtrToStructure(m.LParam, typeof(Native.MINMAXINFO));
						Rectangle wa = sc.WorkingArea, mon = sc.Bounds;
						mm.MaxPosition = new Point(wa.Left - mon.Left - fx, wa.Top - mon.Top - fy);
						mm.MaxSize = new Point(wa.Width + fx * 2, wa.Height + fy * 2);
						Marshal.StructureToPtr(mm, m.LParam, false);
					}
					return;
				case WM_DPICHANGED:
					Native.RECT r = (Native.RECT)Marshal.PtrToStructure(m.LParam, typeof(Native.RECT));
					Native.SetWindowPos(Handle, IntPtr.Zero, r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top, 0x0004 | 0x0010);
					DoLayout();
					m.Result = IntPtr.Zero;
					return;
				case WM_MOVE:
					base.WndProc(ref m);
					if (view != null) try { view.NotifyParentWindowPositionChanged(); } catch { }
					return;
				case 0x86: // WM_NCACTIVATE
					// Activating repaints the caption DWM keeps for the window; -1 skips
					// that, so no dark title strip shows over the glass.
					m.LParam = new IntPtr(-1);
					base.WndProc(ref m);
					return;
				case WM_ACTIVATE:
					base.WndProc(ref m);
					active = (m.WParam.ToInt64() & 0xFFFF) != 0;
					if (active)
					{
						App.LastActive = this;
						FocusPage();
					}
					Post(Json.Obj("t", "active", "on", active));
					return;
			}
			base.WndProc(ref m);
		}

		// DWM paints its dark caption strip again after maximizing or restoring;
		// recalculating the frame clears it (FrameFix off only to test that).
		public static bool FrameFix = true;
		FormWindowState shownState = FormWindowState.Normal;

		protected override void OnResize(EventArgs e)
		{
			base.OnResize(e);
			bool min = WindowState == FormWindowState.Minimized;
			if (WindowState != shownState && IsHandleCreated)
			{
				shownState = WindowState;
				if (!min && FrameFix) BeginInvoke((Action)RefreshFrame);
			}
			if (view != null) try { view.IsVisible = !min; } catch { }
			if (!min) DoLayout();
			Post(Json.Obj("t", "win", "max", Maximized));
		}

		void DoLayout()
		{
			if (view == null || !IsHandleCreated || WindowState == FormWindowState.Minimized) return;
			Size cs = ClientSize;
			int top = TopStrip;
			try { view.Bounds = new Rectangle(0, top, cs.Width, Math.Max(0, cs.Height - top)); } catch { }
		}

		public void BringUp()
		{
			if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
			Native.SetForegroundWindow(Handle);
			Activate();
		}

		void FocusPage()
		{
			if (view == null) return;
			try { view.MoveFocus(CoreWebView2MoveFocusReason.Programmatic); } catch { }
		}

		protected override void OnFormClosing(FormClosingEventArgs e)
		{
			// Closing a window full of shells by accident hurts; the page asks first.
			int live = 0;
			foreach (Pty p in ptys.Values) if (!p.Closed) live++;
			if (live > 1 && !closeConfirmed && ready && e.CloseReason == CloseReason.UserClosing && App.Test == null && !App.Quitting)
			{
				e.Cancel = true;
				Post(Json.Obj("t", "confirmClose", "count", live));
				BringUp();
				return;
			}
			closing = true;
			if (App.Windows.Count == 1) SaveBounds();
			base.OnFormClosing(e);
		}

		protected override void OnFormClosed(FormClosedEventArgs e)
		{
			foreach (Pty p in ptys.Values) p.Kill();
			ptys.Clear();
			if (view != null) try { view.Close(); } catch { }
			base.OnFormClosed(e);
		}

		void SaveBounds()
		{
			Rectangle b = WindowState == FormWindowState.Normal ? Bounds : RestoreBounds;
			App.SetPref("bounds", new object[] { b.X, b.Y, b.Width, b.Height });
			App.SetPref("max", WindowState == FormWindowState.Maximized);
			App.SaveNow();
		}

		// --- The page ---------------------------------------------------------------------

		async void Init()
		{
			try { view = await App.Env.CreateCoreWebView2ControllerAsync(Handle); }
			catch (Exception ex)
			{
				MessageBox.Show(this, "Couldn't create the terminal window.\n\n" + ex.Message, App.Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
				Close();
				return;
			}
			if (closing) { view.Close(); return; }
			view.DefaultBackgroundColor = Color.Transparent;
			CoreWebView2 cw = view.CoreWebView2;
			CoreWebView2Settings s = cw.Settings;
			s.AreDefaultContextMenusEnabled = false;
			s.AreDefaultScriptDialogsEnabled = false;
			s.IsStatusBarEnabled = false;
			s.IsZoomControlEnabled = false;
			s.AreDevToolsEnabled = Environment.GetEnvironmentVariable("OAZY_TERMINAL_DEVTOOLS") == "1";
			try { s.AreBrowserAcceleratorKeysEnabled = false; } catch { }
			try { s.IsPinchZoomEnabled = false; } catch { }
			try { s.IsSwipeNavigationEnabled = false; } catch { }
			try { s.IsGeneralAutofillEnabled = false; s.IsPasswordAutosaveEnabled = false; } catch { }
			nativeDrag = false;
			try { s.IsNonClientRegionSupportEnabled = true; nativeDrag = true; } catch { }
			cw.SetVirtualHostNameToFolderMapping(App.UiHost, App.Ui, CoreWebView2HostResourceAccessKind.Allow);
			cw.WebMessageReceived += OnMessage;
			cw.NewWindowRequested += delegate(object o, CoreWebView2NewWindowRequestedEventArgs e) { e.Handled = true; OpenUrl(e.Uri); };
			cw.NavigationStarting += delegate(object o, CoreWebView2NavigationStartingEventArgs e)
			{
				// The window never leaves its own page; links open outside.
				if (!e.Uri.StartsWith(App.PageUrl)) { e.Cancel = true; OpenUrl(e.Uri); }
			};
			DoLayout();
			cw.Navigate(App.PageUrl);
		}

		public void Post(object msg)
		{
			if (!ready || view == null)
			{
				if (outbox.Count < 200) outbox.Add(msg);
				return;
			}
			try { view.CoreWebView2.PostWebMessageAsJson(Json.S.Serialize(msg)); } catch { }
		}

		public void SendOutput(int id, string text)
		{
			if (!ready || view == null || closing) return;
			try { view.CoreWebView2.PostWebMessageAsString("o" + id + ":" + text); } catch { }
		}

		public void OpenTab(Launch l)
		{
			if (!ready) { launches.Add(l); return; }
			Post(Json.Obj("t", "open", "tab", l.ToJson()));
		}

		void OnMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
		{
			string str = null;
			try { str = e.TryGetWebMessageAsString(); } catch { }
			if (str != null)
			{
				// Terminal traffic: "i<id>:<text>" typed, "a<id>:<chars>" drawn.
				int colon = str.IndexOf(':');
				if (colon < 2) return;
				int id;
				if (!int.TryParse(str.Substring(1, colon - 1), out id)) return;
				Pty p;
				if (!ptys.TryGetValue(id, out p)) return;
				if (str[0] == 'i') p.Send(str.Substring(colon + 1));
				else if (str[0] == 'a')
				{
					int n;
					if (int.TryParse(str.Substring(colon + 1), out n)) p.Ack(n);
				}
				return;
			}
			Dictionary<string, object> m;
			try { m = Json.S.DeserializeObject(e.WebMessageAsJson) as Dictionary<string, object>; } catch { return; }
			if (m == null) return;
			switch (Json.Str(m, "t"))
			{
				case "ready":
					ready = true;
					{
						List<object> tabs = new List<object>();
						foreach (Launch l in launches) tabs.Add(l.ToJson());
						launches.Clear();
						Post(Json.Obj("t", "init", "glass", glass, "accent", App.Accent, "nativeDrag", nativeDrag, "version", App.Version,
							"profiles", App.ProfileList.ToArray(), "defaultProfile", App.DefaultProfile(), "prefs", App.Prefs, "tabs", tabs.ToArray(),
							"build", App.WindowsBuild(), "selftest", App.Test != null));
					}
					foreach (object o in outbox) Post(o);
					outbox.Clear();
					Post(Json.Obj("t", "win", "max", Maximized));
					Post(Json.Obj("t", "active", "on", active));
					FocusPage();
					if (App.Test != null) App.Test.PageReady(this);
					break;
				case "spawn": Spawn(m); break;
				case "resize":
					{
						Pty p;
						if (ptys.TryGetValue(Json.Int(m, "id"), out p)) p.Resize(Json.Int(m, "cols"), Json.Int(m, "rows"));
					}
					break;
				case "kill":
					{
						Pty p;
						int id = Json.Int(m, "id");
						if (ptys.TryGetValue(id, out p)) { p.Kill(); ptys.Remove(id); }
					}
					break;
				case "title":
					title = Json.Str(m, "text");
					Text = title == "" ? App.Name : title + " - " + App.Name;
					break;
				case "copy":
					SetClipboard(Json.Str(m, "text"));
					break;
				case "paste":
					Post(Json.Obj("t", "paste", "id", Json.Int(m, "id"), "text", ClipboardText()));
					break;
				case "open": OpenUrl(Json.Str(m, "url")); break;
				case "prefs":
					{
						Dictionary<string, object> p = m.ContainsKey("prefs") ? m["prefs"] as Dictionary<string, object> : null;
						if (p != null)
						{
							foreach (KeyValuePair<string, object> kv in p) App.SetPref(kv.Key, kv.Value);
							foreach (TermWindow w in App.Windows) if (w != this) w.Post(Json.Obj("t", "prefs", "prefs", p));
						}
					}
					break;
				case "bell":
					if (!active)
					{
						Native.FLASHWINFO f = new Native.FLASHWINFO { hwnd = Handle, dwFlags = 3 | 12, uCount = 0, dwTimeout = 0 };
						f.cbSize = (uint)Marshal.SizeOf(f);
						Native.FlashWindowEx(ref f);
					}
					break;
				case "drag":
					Native.ReleaseCapture();
					Native.SendMessage(Handle, WM_NCLBUTTONDOWN, new IntPtr(HTCAPTION), IntPtr.Zero);
					break;
				case "cmd": Command(Json.Str(m, "cmd")); break;
				case "test":
					if (App.Test != null) App.Test.FromPage(this, m);
					break;
			}
		}

		void Command(string cmd)
		{
			switch (cmd)
			{
				case "minimize": WindowState = FormWindowState.Minimized; break;
				case "maximize": WindowState = WindowState == FormWindowState.Maximized ? FormWindowState.Normal : FormWindowState.Maximized; break;
				case "close": Close(); break;
				case "forceClose": closeConfirmed = true; Close(); break;
				case "newWindow": App.OpenWindow(new Launch(), null); break;
				case "settingsFile":
					try { Process.Start("explorer.exe", "/select,\"" + Path.Combine(App.Data, "prefs.json") + "\""); } catch { }
					break;
			}
		}

		void Spawn(Dictionary<string, object> m)
		{
			int id = Json.Int(m, "id");
			if (ptys.ContainsKey(id)) return;
			string run = Json.Str(m, "run");
			string cmdline = run;
			if (cmdline == "")
			{
				Dictionary<string, object> prof = App.FindProfile(Json.Str(m, "profile"));
				if (prof == null) prof = App.FindProfile(App.DefaultProfile());
				cmdline = Json.Str(prof, "cmd");
			}
			string cwd = Json.Str(m, "cwd");
			if (cwd == "") cwd = Json.Str(App.Prefs, "startDir");
			if (cwd != "") cwd = Environment.ExpandEnvironmentVariables(cwd);
			Pty p = new Pty(id, this);
			string error = p.Start(cmdline, cwd, Json.Int(m, "cols"), Json.Int(m, "rows"));
			if (error != null)
			{
				Post(Json.Obj("t", "failed", "id", id, "error", error, "cmd", cmdline));
				return;
			}
			ptys[id] = p;
			Post(Json.Obj("t", "started", "id", id, "pid", p.Pid));
		}

		public void SessionExited(Pty p, int code)
		{
			Pty cur;
			if (ptys.TryGetValue(p.Id, out cur) && cur == p) ptys.Remove(p.Id);
			if (!closing) Post(Json.Obj("t", "exit", "id", p.Id, "code", code));
		}

		static void OpenUrl(string url)
		{
			if (string.IsNullOrEmpty(url)) return;
			if (!url.StartsWith("http://") && !url.StartsWith("https://") && !url.StartsWith("mailto:")) return;
			try { Process.Start(url); } catch { }
		}

		static void SetClipboard(string text)
		{
			if (string.IsNullOrEmpty(text)) return;
			for (int i = 0; i < 5; i++)
			{
				try { Clipboard.SetText(text, TextDataFormat.UnicodeText); return; }
				catch { Thread.Sleep(40); }
			}
		}

		static string ClipboardText()
		{
			for (int i = 0; i < 5; i++)
			{
				try
				{
					if (Clipboard.ContainsText(TextDataFormat.UnicodeText)) return Clipboard.GetText(TextDataFormat.UnicodeText);
					if (Clipboard.ContainsFileDropList())
					{
						// Copied files paste as their paths, ready for a command (or Claude).
						List<string> paths = new List<string>();
						foreach (string f in Clipboard.GetFileDropList()) paths.Add(f.IndexOf(' ') >= 0 ? "\"" + f + "\"" : f);
						return string.Join(" ", paths.ToArray());
					}
					return "";
				}
				catch { Thread.Sleep(40); }
			}
			return "";
		}

		// --- Self-test hooks ------------------------------------------------------------------

		public void TestSend(int id, string text)
		{
			Pty p;
			if (ptys.TryGetValue(id, out p)) p.Send(text);
		}

		public IEnumerable<int> TestIds() { return new List<int>(ptys.Keys); }
	}

	// --- Self-test: proves the terminal works on a real Windows box (CI) ----------------

	class Selftest
	{
		readonly string dir;
		readonly List<string> log = new List<string>();
		public int ExitCode = 1;
		TermWindow win;
		bool pageOk, echoOk, colorOk, done;
		string lastBuffer = "";
		System.Windows.Forms.Timer timeout;

		public Selftest(string outDir)
		{
			dir = outDir;
			Directory.CreateDirectory(dir);
		}

		void Log(string s) { log.Add(DateTime.Now.ToString("HH:mm:ss.fff") + " " + s); }

		public void Begin()
		{
			Log("runtime " + App.Version + ", Windows build " + App.WindowsBuild());
			foreach (Dictionary<string, object> p in App.ProfileList) Log("profile " + Json.Str(p, "id") + ": " + Json.Str(p, "cmd"));
			timeout = new System.Windows.Forms.Timer { Interval = 90000 };
			timeout.Tick += delegate { Log("timed out"); Finish(); };
			timeout.Start();
			Rectangle work = Screen.PrimaryScreen.WorkingArea;
			Rectangle r = new Rectangle(work.Left + 20, work.Top + 20, Math.Min(1280, work.Width - 40), Math.Min(800, work.Height - 40));
			win = App.OpenWindow(new Launch { Profile = "powershell" }, r);
		}

		public void PageReady(TermWindow w) { pageOk = true; Log("page ready"); Run(); }

		public void FromPage(TermWindow w, Dictionary<string, object> m)
		{
			string what = Json.Str(m, "what");
			if (what == "buffer") lastBuffer = Json.Str(m, "text");
			else Log("page says " + what + " " + Json.Str(m, "detail"));
		}

		async void Run()
		{
			// Let PowerShell start, then type into it like a person would.
			await Task.Delay(4000);
			int id = First();
			Log("typing into pane " + id);
			win.TestSend(id, "Write-Host 'OAZY-' -NoNewline; Write-Host 'TERMINAL-OK' -ForegroundColor Cyan\r");
			await Task.Delay(1500);
			// Truecolor and Unicode: a gradient bar, box drawing and an emoji.
			win.TestSend(id, "$e=[char]27; -join (0..59 | % { \"$e[48;2;$([int](20+$_*3));$([int](200-$_*2));$([int](190+$_))m \" }) + \"$e[0m\"; '╭─ Oazy ─╮ ✓ 🌴 ünïcødé'\r");
			await Task.Delay(1500);
			win.Post(Json.Obj("t", "test", "action", "buffer"));
			await Task.Delay(800);
			echoOk = lastBuffer.Contains("OAZY-TERMINAL-OK");
			colorOk = lastBuffer.Contains("ünïcødé");
			Log("echo " + echoOk + ", unicode " + colorOk);
			Shot("terminal-powershell.png");
			// A split pane with Command Prompt, and a second tab.
			win.Post(Json.Obj("t", "test", "action", "split", "profile", "cmd"));
			await Task.Delay(3000);
			Shot("terminal-split.png");
			win.Post(Json.Obj("t", "test", "action", "menu"));
			await Task.Delay(1200);
			Shot("terminal-menu.png");
			win.Post(Json.Obj("t", "test", "action", "closeMenu"));
			win.Post(Json.Obj("t", "test", "action", "find", "q", "TERMINAL"));
			await Task.Delay(1200);
			Shot("terminal-find.png");
			Finish();
		}

		int First()
		{
			foreach (int id in win.TestIds()) return id;
			return 0;
		}

		public void Exited()
		{
			Log("message loop ended, exiting with " + ExitCode);
			try { File.WriteAllLines(Path.Combine(dir, "terminal-selftest.log"), log.ToArray()); } catch { }
		}

		void Shot(string name)
		{
			try
			{
				Rectangle b = win.Bounds;
				using (Bitmap bmp = new Bitmap(b.Width, b.Height))
				{
					using (Graphics g = Graphics.FromImage(bmp)) g.CopyFromScreen(b.Location, Point.Empty, b.Size);
					bmp.Save(Path.Combine(dir, name), System.Drawing.Imaging.ImageFormat.Png);
				}
				Log("saved " + name);
			}
			catch (Exception e) { Log("screenshot failed: " + e.Message); }
		}

		void Finish()
		{
			if (done) return;
			done = true;
			ExitCode = pageOk && echoOk && colorOk ? 0 : 1;
			Log("page=" + pageOk + " echo=" + echoOk + " unicode=" + colorOk + " -> " + (ExitCode == 0 ? "PASS" : "FAIL"));
			if (ExitCode != 0) Log("buffer: " + lastBuffer);
			try { File.WriteAllLines(Path.Combine(dir, "terminal-selftest.log"), log.ToArray()); } catch { }
			App.Quit();
		}
	}
}
