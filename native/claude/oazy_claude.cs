// Oazy Claude: Claude Code in an Oazy glass window.
//
// The page (ui/claude.html) is a chat: your folders, your conversations,
// Claude's replies as they stream, a card for every file it reads or edits
// and every command it runs, and Allow / Deny when it asks. Underneath it's
// the Claude Code you already have installed, signed in as you, run headless:
//
//   claude -p --input-format stream-json --output-format stream-json --verbose
//          --include-partial-messages --permission-prompt-tool stdio
//
// One claude process per conversation, in the conversation's folder. This
// file only starts it, pipes its JSON lines to the page ("c" + line) and the
// page's lines back to it; the page speaks Claude Code's stream-json itself
// (messages, control requests for permissions, interrupt, mode and model).
// Past conversations come from Claude Code's own transcripts in
// ~/.claude/projects, so everything here also resumes in the terminal.
//
// Like Oazy Terminal, Oazy compiles this file on first use with the .NET
// Framework csc.exe that comes with Windows, so it must stay C# 5.
//
// Usage: OazyClaude.exe --data <dir> [--accent <hex>] [--cwd <dir>]
//                       [--terminal <OazyTerminal.exe> --terminal-data <dir>]
//        OazyClaude.exe --selftest <out dir>
//        OazyClaude.exe --mock-claude      (a stand-in for claude, for the self-test)
// A second launch hands its folder to the running window over a named pipe.

using System;
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
using Microsoft.Web.WebView2.Core;

namespace OazyClaude
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

		[StructLayout(LayoutKind.Sequential)]
		public struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags, uCount, dwTimeout; }

		[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
		[DllImport("dwmapi.dll")] public static extern int DwmExtendFrameIntoClientArea(IntPtr h, ref MARGINS m);
		[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
		[DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
		[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
		[DllImport("user32.dll")] public static extern bool ReleaseCapture();
		[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
		[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
		[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);
		[DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
		[DllImport("user32.dll")] public static extern int GetSystemMetricsForDpi(int index, uint dpi);
		[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
		[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
		[DllImport("user32.dll")] public static extern bool FlashWindowEx(ref FLASHWINFO info);
		[DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
		[DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int index, IntPtr value);
		[DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
		public static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IShellItem item);
	}

	// The Windows folder picker (IFileOpenDialog with FOS_PICKFOLDERS), the
	// modern one with the address bar, rather than WinForms' tree of folders.
	[ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
	class FileOpenDialogCo { }

	[ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
	interface IFileOpenDialog
	{
		[PreserveSig] int Show(IntPtr parent);
		void SetFileTypes(uint count, IntPtr specs);
		void SetFileTypeIndex(uint index);
		void GetFileTypeIndex(out uint index);
		void Advise(IntPtr sink, out uint cookie);
		void Unadvise(uint cookie);
		void SetOptions(uint fos);
		void GetOptions(out uint fos);
		void SetDefaultFolder(IShellItem item);
		void SetFolder(IShellItem item);
		void GetFolder(out IShellItem item);
		void GetCurrentSelection(out IShellItem item);
		void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
		void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string name);
		void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
		void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string text);
		void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
		void GetResult(out IShellItem item);
	}

	[ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
	interface IShellItem
	{
		void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
		void GetParent(out IShellItem parent);
		void GetDisplayName(uint sigdn, [MarshalAs(UnmanagedType.LPWStr)] out string name);
	}

	static class Json
	{
		public static readonly JavaScriptSerializer S = new JavaScriptSerializer { MaxJsonLength = int.MaxValue, RecursionLimit = 100 };

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

		public static Dictionary<string, object> Parse(string s)
		{
			try { return S.DeserializeObject(s) as Dictionary<string, object>; } catch { return null; }
		}

		public static Dictionary<string, object> Load(string path)
		{
			try
			{
				if (File.Exists(path))
				{
					Dictionary<string, object> d = Parse(File.ReadAllText(path, Encoding.UTF8));
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

	static class Program
	{
		[STAThread]
		static int Main(string[] args)
		{
			string data = "", accent = "", selftest = "", cwd = "", terminal = "", terminalData = "";
			for (int i = 0; i < args.Length; i++)
			{
				string a = args[i];
				bool more = i + 1 < args.Length;
				if (a == "--mock-claude") return Mock.Run();
				if (a == "--data" && more) data = args[++i];
				else if (a == "--accent" && more) accent = args[++i];
				else if (a == "--selftest" && more) selftest = args[++i];
				else if (a == "--cwd" && more) cwd = args[++i];
				else if (a == "--terminal" && more) terminal = args[++i];
				else if (a == "--terminal-data" && more) terminalData = args[++i];
			}
			if (selftest != "") data = Path.Combine(Path.GetTempPath(), "OazyClaudeSelftest-" + Process.GetCurrentProcess().Id);
			if (data == "") data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Oazy", "Claude");
			data = Path.GetFullPath(data);

			string pipe = "OazyClaude-" + App.Hash(Environment.UserName + "|" + data.ToLowerInvariant());
			bool first;
			Mutex single = new Mutex(true, "Local\\" + pipe, out first);
			if (!first && selftest == "")
			{
				if (Forward(pipe, cwd)) return 0;
			}
			try { if (!Native.SetProcessDpiAwarenessContext(new IntPtr(-4))) Native.SetProcessDPIAware(); }
			catch { try { Native.SetProcessDPIAware(); } catch { } }
			Application.EnableVisualStyles();
			Application.SetCompatibleTextRenderingDefault(false);
			App.TerminalExe = terminal;
			App.TerminalData = terminalData;
			int code = App.Run(data, accent, pipe, cwd, selftest);
			GC.KeepAlive(single);
			// As in Oazy Terminal: leave before CLR shutdown finalizes WebView2's
			// COM objects off their thread.
			try { single.ReleaseMutex(); } catch { }
			Native.TerminateProcess(Native.GetCurrentProcess(), (uint)code);
			return code;
		}

		static bool Forward(string pipe, string cwd)
		{
			for (int attempt = 0; attempt < 3; attempt++)
			{
				try
				{
					using (NamedPipeClientStream c = new NamedPipeClientStream(".", pipe, PipeDirection.Out))
					{
						c.Connect(1000);
						try { Native.AllowSetForegroundWindow(-1); } catch { }
						byte[] bytes = Encoding.UTF8.GetBytes(Json.S.Serialize(Json.Obj("cwd", cwd)) + "\n");
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

	// --- The app as a whole --------------------------------------------------------------

	static class App
	{
		public const string UiHost = "oazy.example";
		public const string PageUrl = "https://oazy.example/claude.html";
		public const string Name = "Claude";

		public static string Data, Ui, Accent = "#38d6c4", Version = "", TerminalExe = "", TerminalData = "";
		public static CoreWebView2Environment Env;
		public static SynchronizationContext Sync;
		public static ChatWindow Window;
		public static Dictionary<string, object> Prefs;
		public static Selftest Test;
		public static bool Quitting { get { return quitting; } }
		static ApplicationContext ctx;
		static bool prefsDirty, quitting;
		static string pipeName;

		public static int Run(string data, string accent, string pipe, string cwd, string selftest)
		{
			Data = data;
			pipeName = pipe;
			Ui = Path.Combine(Path.GetDirectoryName(Application.ExecutablePath), "ui");
			try { Directory.CreateDirectory(Data); }
			catch (Exception e)
			{
				MessageBox.Show("Claude can't use its settings folder:\n" + Data + "\n\n" + e.Message, Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
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

			SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());
			Sync = SynchronizationContext.Current;
			ctx = new ApplicationContext();
			System.Windows.Forms.Timer saveTimer = new System.Windows.Forms.Timer { Interval = 2000 };
			saveTimer.Tick += delegate { SaveNow(); };
			saveTimer.Start();
			if (selftest != "") Test = new Selftest(selftest);
			else StartPipe();
			Start(cwd);
			Application.Run(ctx);
			SaveNow();
			if (Test != null) Test.Exited();
			return Test != null ? Test.ExitCode : 0;
		}

		static async void Start(string cwd)
		{
			try
			{
				CoreWebView2EnvironmentOptions opts = new CoreWebView2EnvironmentOptions("--enable-features=OverlayScrollbar");
				Env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(Data, "webview"), opts);
			}
			catch (Exception e)
			{
				MessageBox.Show("Claude couldn't start its renderer.\n\n" + e.Message, Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
				ctx.ExitThread();
				return;
			}
			Env.BrowserProcessExited += delegate(object o, CoreWebView2BrowserProcessExitedEventArgs e)
			{
				if (!quitting && e.BrowserProcessExitKind != CoreWebView2BrowserProcessExitKind.Normal) Quit();
			};
			if (Test != null) { Test.Begin(); return; }
			OpenWindow(cwd, null);
		}

		public static ChatWindow OpenWindow(string cwd, Rectangle? bounds)
		{
			if (!bounds.HasValue)
			{
				object[] b = Prefs.ContainsKey("bounds") ? Prefs["bounds"] as object[] : null;
				if (b != null && b.Length == 4)
				{
					try { bounds = new Rectangle(Convert.ToInt32(b[0]), Convert.ToInt32(b[1]), Convert.ToInt32(b[2]), Convert.ToInt32(b[3])); } catch { }
				}
			}
			ChatWindow w = new ChatWindow(cwd, bounds, Test == null && Json.Bool(Prefs, "max"));
			Window = w;
			w.FormClosed += delegate { Quit(); };
			w.Show();
			w.Activate();
			return w;
		}

		public static void Quit()
		{
			if (quitting) return;
			quitting = true;
			SaveNow();
			if (Window != null) { try { Window.Close(); } catch { } }
			ctx.ExitThread();
		}

		static void NoRuntime()
		{
			DialogResult r = MessageBox.Show(
				"Claude runs on the Microsoft Edge WebView2 Runtime, which isn't installed on this PC.\n\nOpen the download page now?",
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
			if (Window == null) return;
			foreach (string line in text.Split('\n'))
			{
				Dictionary<string, object> m = Json.Parse(line);
				if (m == null) continue;
				Window.BringUp();
				if (Json.Str(m, "cwd") != "") Window.Post(Json.Obj("t", "open", "cwd", Json.Str(m, "cwd")));
			}
		}

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
	}

	// --- Claude Code: finding it, and one conversation's process ----------------------

	static class Cli
	{
		// PATH as it is now: the process's own, plus the user's and the machine's
		// from the registry, so a Claude Code installed after Oazy started is found.
		public static string FreshPath()
		{
			List<string> parts = new List<string>();
			foreach (string p in new string[] {
				Environment.GetEnvironmentVariable("PATH"),
				Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User),
				Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.Machine) })
			{
				if (string.IsNullOrEmpty(p)) continue;
				foreach (string d in Environment.ExpandEnvironmentVariables(p).Split(';'))
				{
					string t = d.Trim().Trim('"');
					if (t != "" && !parts.Contains(t)) parts.Add(t);
				}
			}
			return string.Join(";", parts.ToArray());
		}

		// Where claude is, first match wins: one you picked yourself, the native
		// installer's, anything on PATH (the user's and the machine's as they are
		// now), npm / pnpm / bun / scoop / volta / winget, the old local install,
		// then the copy the Claude desktop app keeps for its own Claude Code.
		public static string Find()
		{
			string over = Environment.GetEnvironmentVariable("OAZY_CLAUDE");
			if (!string.IsNullOrEmpty(over) && File.Exists(over)) return over;
			string picked = App.Prefs != null ? Json.Str(App.Prefs, "claudePath") : "";
			if (picked != "" && File.Exists(picked)) return picked;
			string home = App.Home();
			string roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
			string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
			string hit = First(new string[] { Path.Combine(home, ".local\\bin\\claude.exe") });
			if (hit != null) return hit;
			List<string> dirs = new List<string>(FreshPath().Split(';'));
			dirs.AddRange(new string[] {
				Path.Combine(roaming, "npm"), Path.Combine(local, "pnpm"), Path.Combine(home, ".bun\\bin"),
				Path.Combine(home, "scoop\\shims"), Path.Combine(local, "Volta\\bin"), Path.Combine(local, "Microsoft\\WinGet\\Links"),
				Path.Combine(home, ".claude\\local"), Path.Combine(home, ".claude\\local\\node_modules\\.bin"),
				Path.Combine(home, "AppData\\Roaming\\npm"),
			});
			foreach (string dir in dirs)
			{
				if (dir == "") continue;
				// The Claude desktop app's own folder holds Claude.exe, which isn't the CLI.
				string d = dir.ToLowerInvariant();
				if (d.Contains("anthropicclaude") || d.Contains("\\windowsapps\\claude")) continue;
				foreach (string f in new string[] { "claude.exe", "claude.cmd", "claude.bat" })
				{
					try
					{
						string p = Path.Combine(dir, f);
						if (File.Exists(p)) return p;
					}
					catch { }
				}
			}
			return Bundled(roaming, local);
		}

		static string First(string[] paths)
		{
			foreach (string p in paths) if (File.Exists(p)) return p;
			return null;
		}

		// The Claude desktop app downloads Claude Code into a claude-code folder
		// of its own (one folder per version); the newest one there.
		static string Bundled(string roaming, string local)
		{
			List<string> roots = new List<string> { Path.Combine(roaming, "Claude"), Path.Combine(local, "AnthropicClaude"), Path.Combine(local, "Claude") };
			try
			{
				foreach (string pkg in Directory.GetDirectories(Path.Combine(local, "Packages"), "*Claude*"))
					roots.Add(Path.Combine(pkg, "LocalCache\\Roaming\\Claude"));
			}
			catch { }
			string best = "";
			DateTime bestAt = DateTime.MinValue;
			int budget = 400;
			foreach (string r in roots) Scan(r, 0, ref budget, ref best, ref bestAt);
			return best;
		}

		static void Scan(string dir, int depth, ref int budget, ref string best, ref DateTime bestAt)
		{
			if (depth > 4 || --budget < 0 || !Directory.Exists(dir)) return;
			try
			{
				if (dir.ToLowerInvariant().Contains("claude-code"))
				{
					string p = Path.Combine(dir, "claude.exe");
					if (File.Exists(p))
					{
						DateTime at = File.GetLastWriteTimeUtc(p);
						if (at > bestAt) { best = p; bestAt = at; }
					}
				}
				foreach (string sub in Directory.GetDirectories(dir))
				{
					string n = Path.GetFileName(sub).ToLowerInvariant();
					// Electron's own folders are big and never hold it.
					if (n == "cache" || n == "code cache" || n == "gpucache" || n == "indexeddb" || n == "local storage" || n == "logs" || n == "crashpad" || n == "blob_storage" || n == "service worker" || n == "session storage") continue;
					Scan(sub, depth + 1, ref budget, ref best, ref bestAt);
				}
			}
			catch { }
		}

		public static string Quote(string s)
		{
			if (s == "") return "\"\"";
			if (s.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) return s;
			return "\"" + s.Replace("\\\"", "\\\\\"").Replace("\"", "\\\"") + "\"";
		}

		// Where Claude Code keeps its transcripts.
		public static string ConfigDir()
		{
			string d = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
			return !string.IsNullOrEmpty(d) ? d : Path.Combine(App.Home(), ".claude");
		}
	}

	class Session
	{
		readonly ChatWindow win;
		readonly object writeLock = new object();
		Process proc;
		Stream input;
		readonly StringBuilder err = new StringBuilder();
		public readonly int Id;
		static int nextId = 1;
		public bool Exited;

		public Session(ChatWindow w) { win = w; Id = nextId++; }

		// Returns null, or why it couldn't start.
		public string Start(string exe, string cwd, string resume, string model, string mode)
		{
			List<string> args = new List<string> {
				"-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
				"--include-partial-messages", "--permission-prompt-tool", "stdio",
				// Questions come as plain replies here; the card for them is Claude Code's own UI.
				"--disallowedTools", "AskUserQuestion",
			};
			if (resume != "") { args.Add("--resume"); args.Add(resume); }
			if (model != "") { args.Add("--model"); args.Add(model); }
			if (mode != "" && mode != "default") { args.Add("--permission-mode"); args.Add(mode); }
			StringBuilder line = new StringBuilder();
			foreach (string a in args) line.Append(' ').Append(Cli.Quote(a));

			ProcessStartInfo si = new ProcessStartInfo();
			string ext = Path.GetExtension(exe).ToLowerInvariant();
			if (ext == ".cmd" || ext == ".bat")
			{
				si.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
				si.Arguments = "/d /s /c \"" + Cli.Quote(exe) + line + "\"";
			}
			else
			{
				si.FileName = exe;
				si.Arguments = line.ToString().TrimStart();
				if (App.Test != null && exe == Application.ExecutablePath) si.Arguments = "--mock-claude " + si.Arguments;
			}
			si.WorkingDirectory = Directory.Exists(cwd) ? cwd : App.Home();
			si.UseShellExecute = false;
			si.CreateNoWindow = true;
			si.RedirectStandardInput = true;
			si.RedirectStandardOutput = true;
			si.RedirectStandardError = true;
			si.StandardOutputEncoding = new UTF8Encoding(false);
			si.StandardErrorEncoding = new UTF8Encoding(false);
			si.EnvironmentVariables["PATH"] = Cli.FreshPath();
			si.EnvironmentVariables["CLAUDE_CODE_ENTRYPOINT"] = "oazy-claude";
			try
			{
				proc = Process.Start(si);
				input = proc.StandardInput.BaseStream;
			}
			catch (Exception e) { return e.Message; }

			Thread rd = new Thread(ReadOut);
			rd.IsBackground = true;
			rd.Name = "claude out";
			rd.Start();
			Thread re = new Thread(ReadErr);
			re.IsBackground = true;
			re.Name = "claude err";
			re.Start();
			return null;
		}

		void ReadOut()
		{
			try
			{
				StreamReader r = proc.StandardOutput;
				string line;
				while ((line = r.ReadLine()) != null)
				{
					if (line.Length == 0 || line[0] != '{') continue;
					string l = line;
					App.Sync.Post(delegate { win.FromClaude(this, l); }, null);
				}
			}
			catch { }
			int code = -1;
			try { proc.WaitForExit(3000); code = proc.ExitCode; } catch { }
			string tail;
			lock (err) tail = err.ToString();
			App.Sync.Post(delegate { Exited = true; win.ClaudeExited(this, code, tail); }, null);
		}

		void ReadErr()
		{
			try
			{
				StreamReader r = proc.StandardError;
				string line;
				while ((line = r.ReadLine()) != null)
				{
					lock (err)
					{
						err.AppendLine(line);
						if (err.Length > 6000) err.Remove(0, err.Length - 4000);
					}
				}
			}
			catch { }
		}

		public bool Write(string line)
		{
			if (input == null || Exited) return false;
			byte[] b = new UTF8Encoding(false).GetBytes(line.Replace("\r", "").Replace("\n", " ") + "\n");
			try
			{
				lock (writeLock)
				{
					input.Write(b, 0, b.Length);
					input.Flush();
				}
				return true;
			}
			catch { return false; }
		}

		public void Kill()
		{
			Exited = true;
			try { if (input != null) input.Close(); } catch { }
			try
			{
				if (proc != null && !proc.HasExited)
				{
					// The whole tree: cmd.exe, node and whatever Claude was running.
					Process.Start(new ProcessStartInfo("taskkill", "/T /F /PID " + proc.Id) { CreateNoWindow = true, UseShellExecute = false });
				}
			}
			catch { try { proc.Kill(); } catch { } }
		}
	}

	// --- Past conversations, from Claude Code's transcripts --------------------------------

	static class Transcripts
	{
		// The latest conversations across every folder: {id, cwd, title, at}.
		public static List<object> Recent(int max)
		{
			List<object> list = new List<object>();
			string root = Path.Combine(Cli.ConfigDir(), "projects");
			if (!Directory.Exists(root)) return list;
			List<FileInfo> files = new List<FileInfo>();
			try
			{
				foreach (string d in Directory.GetDirectories(root))
					foreach (string f in Directory.GetFiles(d, "*.jsonl")) files.Add(new FileInfo(f));
			}
			catch { }
			files.Sort(delegate(FileInfo a, FileInfo b) { return b.LastWriteTimeUtc.CompareTo(a.LastWriteTimeUtc); });
			foreach (FileInfo f in files)
			{
				if (list.Count >= max) break;
				Dictionary<string, object> s = Peek(f);
				if (s != null) list.Add(s);
			}
			return list;
		}

		static Dictionary<string, object> Peek(FileInfo f)
		{
			string cwd = "", title = "", first = "";
			bool sidechain = false;
			try
			{
				using (FileStream fs = new FileStream(f.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
				using (StreamReader r = new StreamReader(fs, Encoding.UTF8))
				{
					string line;
					int n = 0;
					while ((line = r.ReadLine()) != null && n++ < 400 && fs.Position < 2 * 1024 * 1024)
					{
						if (line.IndexOf("\"type\":\"summary\"") >= 0 || line.IndexOf("\"type\":\"custom-title\"") >= 0 || line.IndexOf("\"type\":\"ai-title\"") >= 0)
						{
							Dictionary<string, object> m = Json.Parse(line);
							string t = Json.Str(m, "customTitle") != "" ? Json.Str(m, "customTitle") : (Json.Str(m, "aiTitle") != "" ? Json.Str(m, "aiTitle") : Json.Str(m, "summary"));
							if (t != "") title = t;
							continue;
						}
						if (first != "" && cwd != "" && n > 60) break;
						if (line.IndexOf("\"type\":\"user\"") < 0) continue;
						Dictionary<string, object> u = Json.Parse(line);
						if (u == null) continue;
						if (Json.Bool(u, "isSidechain")) { sidechain = true; continue; }
						if (cwd == "") cwd = Json.Str(u, "cwd");
						if (first == "" && !Json.Bool(u, "isMeta")) first = UserText(u);
					}
				}
			}
			catch { return null; }
			// Subagents' transcripts and empty sessions aren't conversations.
			if (sidechain && first == "") return null;
			if (first == "" && title == "") return null;
			string id = Path.GetFileNameWithoutExtension(f.Name);
			if (title == "") title = first;
			title = title.Replace('\n', ' ').Trim();
			if (title.Length > 90) title = title.Substring(0, 90);
			return Json.Obj("id", id, "cwd", cwd, "title", title, "at", (long)(f.LastWriteTimeUtc - new DateTime(1970, 1, 1)).TotalMilliseconds);
		}

		// What the person typed in a transcript's user line ("" for tool results and Claude Code's own notes).
		static string UserText(Dictionary<string, object> u)
		{
			Dictionary<string, object> msg = u.ContainsKey("message") ? u["message"] as Dictionary<string, object> : null;
			if (msg == null) return "";
			object c = msg.ContainsKey("content") ? msg["content"] : null;
			string text = "";
			if (c is string) text = (string)c;
			else if (c is object[])
			{
				foreach (object o in (object[])c)
				{
					Dictionary<string, object> b = o as Dictionary<string, object>;
					if (b != null && Json.Str(b, "type") == "text") { text = Json.Str(b, "text"); break; }
				}
			}
			text = text.Trim();
			if (text.StartsWith("<") || text.StartsWith("Caveat:") || text.StartsWith("[Request interrupted")) return "";
			return text;
		}

		// A conversation's lines for the page to draw (user and assistant, not
		// subagents'), the last `max` of them.
		public static List<string> Lines(string id, int max)
		{
			List<string> lines = new List<string>();
			string root = Path.Combine(Cli.ConfigDir(), "projects");
			string file = null;
			try
			{
				foreach (string d in Directory.GetDirectories(root))
				{
					string p = Path.Combine(d, id + ".jsonl");
					if (File.Exists(p)) { file = p; break; }
				}
			}
			catch { }
			if (file == null) return lines;
			try
			{
				using (FileStream fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
				{
					// Long conversations: the last 16 MB is plenty to read back.
					if (fs.Length > 16L * 1024 * 1024) fs.Seek(-16L * 1024 * 1024, SeekOrigin.End);
					using (StreamReader r = new StreamReader(fs, Encoding.UTF8))
					{
						string line;
						while ((line = r.ReadLine()) != null)
						{
							if (line.IndexOf("\"isSidechain\":true") >= 0) continue;
							if (line.IndexOf("\"type\":\"user\"") < 0 && line.IndexOf("\"type\":\"assistant\"") < 0) continue;
							lines.Add(line);
							if (lines.Count > max) lines.RemoveAt(0);
						}
					}
				}
			}
			catch { }
			return lines;
		}
	}

	// --- The window ---------------------------------------------------------------------

	class ChatWindow : Form
	{
		const int WM_GETMINMAXINFO = 0x24, WM_NCCALCSIZE = 0x83, WM_NCHITTEST = 0x84, WM_DPICHANGED = 0x2E0, WM_MOVE = 0x3, WM_ACTIVATE = 0x6, WM_NCLBUTTONDOWN = 0xA1;
		const int HTCLIENT = 1, HTCAPTION = 2, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14;

		CoreWebView2Controller view;
		bool ready, glass, closing, nativeDrag, active;
		readonly List<object> outbox = new List<object>();
		readonly bool startMaximized;
		readonly string startCwd;
		Session session;
		bool busy, closeConfirmed;

		public ChatWindow(string cwd, Rectangle? bounds, bool maximized)
		{
			startCwd = cwd;
			startMaximized = maximized;
			Text = App.Name;
			BackColor = Color.Black;
			FormBorderStyle = FormBorderStyle.Sizable;
			StartPosition = FormStartPosition.Manual;
			try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

			Rectangle work = Screen.FromPoint(Cursor.Position).WorkingArea;
			float scale = DpiScale();
			int w = (int)(1180 * scale), h = (int)(800 * scale);
			w = Math.Min(w, work.Width - 40);
			h = Math.Min(h, work.Height - 40);
			Rectangle r = new Rectangle(work.Left + (work.Width - w) / 2, work.Top + (work.Height - h) / 2, w, h);
			if (bounds.HasValue && bounds.Value.Width > 300 && bounds.Value.Height > 200 && Screen.FromRectangle(bounds.Value).WorkingArea.IntersectsWith(bounds.Value))
				r = bounds.Value;
			Bounds = r;
			MinimumSize = new Size((int)(460 * scale), (int)(360 * scale));
		}

		static float DpiScale()
		{
			using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) return Math.Max(1f, g.DpiX / 96f);
		}

		float Scale_ { get { try { return Native.GetDpiForWindow(Handle) / 96f; } catch { return 1f; } } }

		// --- Window frame (the same frame as Oazy Terminal's) ---------------------------------

		protected override CreateParams CreateParams
		{
			get
			{
				CreateParams cp = base.CreateParams;
				cp.Style &= ~0x00C00000;
				cp.Style |= 0x00040000 | 0x00080000 | 0x00020000 | 0x00010000;
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
			if (startMaximized) SetMaximized(true);
			RefreshFrame();
			BeginInvoke((Action)RefreshFrame);
			Init();
		}

		void RefreshFrame()
		{
			int color = unchecked((int)0xFFFFFFFF);
			Native.DwmSetWindowAttribute(Handle, 35, ref color, 4);
			long style = Native.GetWindowLongPtr(Handle, -16).ToInt64() & ~0x00C00000L;
			Native.SetWindowLongPtr(Handle, -16, new IntPtr(style));
			Native.SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020);
		}

		int TopStrip { get { return Maximized ? 0 : Math.Max(1, (int)Math.Round(3 * Scale_)); } }

		protected override void WndProc(ref Message m)
		{
			switch (m.Msg)
			{
				case WM_NCCALCSIZE:
					if (m.WParam != IntPtr.Zero)
					{
						Native.NCCALCSIZE_PARAMS p = (Native.NCCALCSIZE_PARAMS)Marshal.PtrToStructure(m.LParam, typeof(Native.NCCALCSIZE_PARAMS));
						Native.RECT whole = p.r0;
						int top = p.r0.Top;
						base.WndProc(ref m);
						p = (Native.NCCALCSIZE_PARAMS)Marshal.PtrToStructure(m.LParam, typeof(Native.NCCALCSIZE_PARAMS));
						// Maximized (by hand), no borders at all: the window is the work area.
						if (zoomed) p.r0 = whole;
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
					if (zoomed) Bounds = Screen.FromHandle(Handle).WorkingArea;
					DoLayout();
					m.Result = IntPtr.Zero;
					return;
				case 0x112: // WM_SYSCOMMAND: maximize and restore (title double-click, Win+Up) by hand
					{
						int sc = (int)(m.WParam.ToInt64() & 0xFFF0);
						if (sc == 0xF030 && !Native.IsIconic(Handle)) { SetMaximized(!zoomed); return; }
						if (sc == 0xF120 && zoomed && !Native.IsIconic(Handle)) { SetMaximized(false); return; }
					}
					break;
				case 0x1A: // WM_SETTINGCHANGE: the work area moved (taskbar)
					base.WndProc(ref m);
					if (zoomed && m.WParam.ToInt64() == 0x2F) Bounds = Screen.FromHandle(Handle).WorkingArea;
					return;
				case WM_MOVE:
					base.WndProc(ref m);
					if (view != null) try { view.NotifyParentWindowPositionChanged(); } catch { }
					return;
				case WM_ACTIVATE:
					base.WndProc(ref m);
					active = (m.WParam.ToInt64() & 0xFFFF) != 0;
					if (active) FocusPage();
					Post(Json.Obj("t", "active", "on", active));
					return;
			}
			base.WndProc(ref m);
		}

		// --- Maximized ---------------------------------------------------------------------
		// Oazy maximizes by hand: the window takes exactly the work area, flush on the
		// taskbar, and stays a normal window to Windows. A real maximized window got a
		// dark caption-high strip painted across its top by DWM and stopped short of the
		// taskbar.
		bool zoomed, zooming;
		Rectangle unzoomed, lastNormal;

		// The last size and place as a plain window: a real maximize (snap) has
		// already left it by the time Oazy takes over.
		void NoteNormal()
		{
			if (IsHandleCreated && WindowState == FormWindowState.Normal && !zoomed && !zooming) lastNormal = Bounds;
		}

		protected override void OnLocationChanged(EventArgs e)
		{
			base.OnLocationChanged(e);
			NoteNormal();
		}

		public bool Maximized { get { return zoomed; } }

		public void SetMaximized(bool on)
		{
			if (on == zoomed || !IsHandleCreated) return;
			zooming = true;
			Rectangle from = WindowState == FormWindowState.Normal ? Bounds : lastNormal;
			if (WindowState != FormWindowState.Normal) WindowState = FormWindowState.Normal;
			// Square and without Windows' 1px outline while it fills the screen.
			int corner = on ? 1 : 2, border = on ? unchecked((int)0xFFFFFFFE) : unchecked((int)0xFFFFFFFF);
			Native.DwmSetWindowAttribute(Handle, 33, ref corner, 4);
			Native.DwmSetWindowAttribute(Handle, 34, ref border, 4);
			if (on)
			{
				unzoomed = from.Width > 0 ? from : Bounds;
				zoomed = true;
				Bounds = Screen.FromHandle(Handle).WorkingArea;
			}
			else
			{
				zoomed = false;
				Bounds = unzoomed;
			}
			zooming = false;
			Native.SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020);
			DoLayout();
			Post(Json.Obj("t", "win", "max", Maximized));
		}

		// Where the window goes back to, for saving.
		Rectangle NormalBounds { get { return zoomed ? unzoomed : (WindowState == FormWindowState.Normal ? Bounds : RestoreBounds); } }

		// Dragging the title of a maximized window brings it back to its own size
		// under the pointer once the pointer moves, and keeps dragging; a click or
		// double-click leaves it as it is.
		System.Windows.Forms.Timer dragWatch;

		void BeginDrag()
		{
			if (!zoomed)
			{
				Native.ReleaseCapture();
				Native.SendMessage(Handle, WM_NCLBUTTONDOWN, new IntPtr(HTCAPTION), IntPtr.Zero);
				return;
			}
			Point start = Cursor.Position;
			if (dragWatch == null)
			{
				dragWatch = new System.Windows.Forms.Timer { Interval = 15 };
				dragWatch.Tick += delegate
				{
					if ((Control.MouseButtons & MouseButtons.Left) == 0 || !zoomed) { dragWatch.Stop(); return; }
					Point c = Cursor.Position, from = (Point)dragWatch.Tag;
					int slop = (int)Math.Round(6 * Scale_);
					if (Math.Abs(c.X - from.X) < slop && Math.Abs(c.Y - from.Y) < slop) return;
					dragWatch.Stop();
					Rectangle full = Bounds, r = unzoomed;
					double at = full.Width > 0 ? (double)(from.X - full.Left) / full.Width : 0.5;
					SetMaximized(false);
					Bounds = new Rectangle(c.X - (int)(r.Width * at), c.Y - (from.Y - full.Top), r.Width, r.Height);
					Native.ReleaseCapture();
					Native.SendMessage(Handle, WM_NCLBUTTONDOWN, new IntPtr(HTCAPTION), IntPtr.Zero);
				};
			}
			dragWatch.Tag = start;
			dragWatch.Start();
		}

		protected override void OnResize(EventArgs e)
		{
			base.OnResize(e);
			bool min = WindowState == FormWindowState.Minimized;
			NoteNormal();
			if (WindowState == FormWindowState.Maximized && !zooming && IsHandleCreated)
				BeginInvoke((Action)delegate { SetMaximized(true); });
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
			// Closing mid-reply stops Claude; the page asks first.
			if (busy && !closeConfirmed && ready && e.CloseReason == CloseReason.UserClosing && App.Test == null && !App.Quitting)
			{
				e.Cancel = true;
				Post(Json.Obj("t", "confirmClose"));
				BringUp();
				return;
			}
			closing = true;
			SaveBounds();
			base.OnFormClosing(e);
		}

		protected override void OnFormClosed(FormClosedEventArgs e)
		{
			if (session != null) session.Kill();
			if (view != null) try { view.Close(); } catch { }
			base.OnFormClosed(e);
		}

		void SaveBounds()
		{
			if (App.Test != null) return;
			Rectangle b = NormalBounds;
			App.SetPref("bounds", new object[] { b.X, b.Y, b.Width, b.Height });
			App.SetPref("max", zoomed);
			App.SaveNow();
		}

		// --- The page ---------------------------------------------------------------------

		async void Init()
		{
			try { view = await App.Env.CreateCoreWebView2ControllerAsync(Handle); }
			catch (Exception ex)
			{
				MessageBox.Show(this, "Couldn't create the Claude window.\n\n" + ex.Message, App.Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
				Close();
				return;
			}
			if (closing) { view.Close(); return; }
			view.DefaultBackgroundColor = Color.Transparent;
			CoreWebView2 cw = view.CoreWebView2;
			CoreWebView2Settings s = cw.Settings;
			s.AreDefaultContextMenusEnabled = true;
			s.AreDefaultScriptDialogsEnabled = false;
			s.IsStatusBarEnabled = false;
			s.IsZoomControlEnabled = true;
			s.AreDevToolsEnabled = Environment.GetEnvironmentVariable("OAZY_CLAUDE_DEVTOOLS") == "1";
			try { s.AreBrowserAcceleratorKeysEnabled = false; } catch { }
			try { s.IsSwipeNavigationEnabled = false; } catch { }
			try { s.IsGeneralAutofillEnabled = false; s.IsPasswordAutosaveEnabled = false; } catch { }
			nativeDrag = false;
			try { s.IsNonClientRegionSupportEnabled = true; nativeDrag = true; } catch { }
			cw.SetVirtualHostNameToFolderMapping(App.UiHost, App.Ui, CoreWebView2HostResourceAccessKind.Allow);
			cw.WebMessageReceived += OnMessage;
			cw.NewWindowRequested += delegate(object o, CoreWebView2NewWindowRequestedEventArgs e) { e.Handled = true; OpenUrl(e.Uri); };
			cw.NavigationStarting += delegate(object o, CoreWebView2NavigationStartingEventArgs e)
			{
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

		void Reply(Dictionary<string, object> m, Dictionary<string, object> r)
		{
			r["t"] = "reply";
			r["rid"] = Json.Int(m, "rid");
			Post(r);
		}

		// A line from claude, straight to the page.
		public void FromClaude(Session s, string line)
		{
			if (s != session || view == null || closing) return;
			try { view.CoreWebView2.PostWebMessageAsString("c" + line); } catch { }
			if (App.Test != null) App.Test.Line(line);
		}

		public void ClaudeExited(Session s, int code, string err)
		{
			if (s != session) return;
			session = null;
			busy = false;
			if (!closing) Post(Json.Obj("t", "exit", "code", code, "err", err));
		}

		void OnMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
		{
			Dictionary<string, object> m = Json.Parse(e.WebMessageAsJson);
			if (m == null) return;
			switch (Json.Str(m, "t"))
			{
				case "ready":
					ready = true;
					{
						string exe = App.Test != null ? Application.ExecutablePath : Cli.Find();
						Post(Json.Obj("t", "init", "glass", glass, "accent", App.Accent, "nativeDrag", nativeDrag, "version", App.Version,
							"prefs", App.Prefs, "home", App.Home(), "claude", exe, "cwd", startCwd,
							"terminal", App.TerminalExe != "" && File.Exists(App.TerminalExe), "selftest", App.Test != null));
					}
					foreach (object o in outbox) Post(o);
					outbox.Clear();
					Post(Json.Obj("t", "win", "max", Maximized));
					Post(Json.Obj("t", "active", "on", active));
					FocusPage();
					SendRecents();
					if (App.Test != null) App.Test.PageReady(this);
					break;
				case "start":
					{
						// A conversation's process: a new one, or a past one resumed.
						if (session != null) { session.Kill(); session = null; }
						string exe = App.Test != null ? Application.ExecutablePath : Cli.Find();
						if (exe == "") { Reply(m, Json.Obj("ok", false, "error", "missing")); break; }
						Session s = new Session(this);
						string error = s.Start(exe, Json.Str(m, "cwd"), Json.Str(m, "resume"), Json.Str(m, "model"), Json.Str(m, "mode"));
						if (error != null) { Reply(m, Json.Obj("ok", false, "error", error)); break; }
						session = s;
						Reply(m, Json.Obj("ok", true, "id", s.Id));
					}
					break;
				case "line":
					if (session == null || !session.Write(Json.Str(m, "line"))) Post(Json.Obj("t", "exit", "code", -1, "err", ""));
					break;
				case "stop":
					if (session != null) { session.Kill(); session = null; }
					busy = false;
					break;
				case "busy": busy = Json.Bool(m, "on"); break;
				case "recents": SendRecents(); break;
				case "findClaude": Reply(m, Json.Obj("claude", Cli.Find())); break;
				case "pickClaude":
					using (OpenFileDialog d = new OpenFileDialog { Title = "Find Claude Code (claude.exe or claude.cmd)", Filter = "Claude Code|claude.exe;claude.cmd;claude.bat|Programs|*.exe;*.cmd;*.bat", CheckFileExists = true })
					{
						string from = Path.Combine(App.Home(), ".local\\bin");
						d.InitialDirectory = Directory.Exists(from) ? from : App.Home();
						if (d.ShowDialog(this) == DialogResult.OK)
						{
							App.SetPref("claudePath", d.FileName);
							App.SaveNow();
						}
					}
					Reply(m, Json.Obj("claude", Cli.Find()));
					break;
				case "history":
					{
						string id = Json.Str(m, "id");
						Dictionary<string, object> req = m;
						ThreadPool.QueueUserWorkItem(delegate
						{
							List<string> lines = Transcripts.Lines(id, 600);
							App.Sync.Post(delegate { Reply(req, Json.Obj("lines", lines.ToArray())); }, null);
						});
					}
					break;
				case "pickFolder":
					{
						string picked = PickFolder(Json.Str(m, "from"));
						Reply(m, Json.Obj("path", picked ?? ""));
					}
					break;
				case "folderExists":
					Reply(m, Json.Obj("ok", Json.Str(m, "path") != "" && Directory.Exists(Json.Str(m, "path"))));
					break;
				case "terminal": OpenTerminal(Json.Str(m, "cwd"), Json.Str(m, "args")); break;
				case "explore":
					{
						string p = Json.Str(m, "path");
						if (Directory.Exists(p)) try { Process.Start("explorer.exe", "\"" + p + "\""); } catch { }
					}
					break;
				case "open": OpenUrl(Json.Str(m, "url")); break;
				case "copy": SetClipboard(Json.Str(m, "text")); break;
				case "prefs":
					{
						Dictionary<string, object> p = m.ContainsKey("prefs") ? m["prefs"] as Dictionary<string, object> : null;
						if (p != null) foreach (KeyValuePair<string, object> kv in p) App.SetPref(kv.Key, kv.Value);
					}
					break;
				case "title":
					{
						string t = Json.Str(m, "text");
						Text = t == "" ? App.Name : App.Name + " - " + t;
					}
					break;
				case "attention":
					if (!active)
					{
						Native.FLASHWINFO f = new Native.FLASHWINFO { hwnd = Handle, dwFlags = 3 | 12, uCount = 0, dwTimeout = 0 };
						f.cbSize = (uint)Marshal.SizeOf(f);
						Native.FlashWindowEx(ref f);
					}
					break;
				case "drag":
					BeginDrag();
					break;
				case "cmd":
					switch (Json.Str(m, "cmd"))
					{
						case "minimize": WindowState = FormWindowState.Minimized; break;
						case "maximize": SetMaximized(!zoomed); break;
						case "close": Close(); break;
						case "forceClose": closeConfirmed = true; Close(); break;
					}
					break;
				case "test":
					if (App.Test != null) App.Test.FromPage(this, m);
					break;
			}
		}

		void SendRecents()
		{
			ThreadPool.QueueUserWorkItem(delegate
			{
				List<object> list = Transcripts.Recent(40);
				App.Sync.Post(delegate { Post(Json.Obj("t", "recents", "list", list.ToArray())); }, null);
			});
		}

		string PickFolder(string from)
		{
			try
			{
				IFileOpenDialog d = (IFileOpenDialog)new FileOpenDialogCo();
				d.SetOptions(0x20 | 0x40 | 0x800); // PICKFOLDERS, FORCEFILESYSTEM, PATHMUSTEXIST
				d.SetTitle("Choose a folder for Claude to work in");
				d.SetOkButtonLabel("Work here");
				if (Directory.Exists(from))
				{
					try
					{
						IShellItem start;
						Native.SHCreateItemFromParsingName(from, IntPtr.Zero, typeof(IShellItem).GUID, out start);
						d.SetFolder(start);
					}
					catch { }
				}
				if (d.Show(Handle) != 0) return null;
				IShellItem item;
				d.GetResult(out item);
				string path;
				item.GetDisplayName(0x80058000, out path); // SIGDN_FILESYSPATH
				return path;
			}
			catch
			{
				using (FolderBrowserDialog f = new FolderBrowserDialog { Description = "Choose a folder for Claude to work in", SelectedPath = from })
					return f.ShowDialog(this) == DialogResult.OK ? f.SelectedPath : null;
			}
		}

		// The whole session in a terminal: Oazy Terminal when Oazy handed us one,
		// else a plain console window.
		void OpenTerminal(string cwd, string args)
		{
			string exe = Cli.Find();
			if (exe == "" && args != "install") return;
			if (!Directory.Exists(cwd)) cwd = App.Home();
			string sys = Environment.GetFolderPath(Environment.SpecialFolder.System);
			string run;
			string title = "Claude Code";
			if (args == "install")
			{
				// Says what it's doing first: the download itself is silent for a while.
				run = Cli.Quote(Path.Combine(sys, "WindowsPowerShell\\v1.0\\powershell.exe")) + " -NoExit -NoProfile -ExecutionPolicy Bypass -Command \"" +
					"Write-Host 'Installing Claude Code. This downloads it from claude.ai and takes a minute or two...'; Write-Host ''; " +
					"$ProgressPreference = 'SilentlyContinue'; irm https://claude.ai/install.ps1 | iex; Write-Host ''; " +
					"Write-Host 'All set. Go back to the Claude app: it finds Claude Code by itself, then asks you to sign in once.'\"";
				title = "Install Claude Code";
			}
			else run = Cli.Quote(Path.Combine(sys, "cmd.exe")) + " /k " + Cli.Quote(exe) + (args != "" ? " " + args : "");
			try
			{
				if (App.TerminalExe != "" && File.Exists(App.TerminalExe))
				{
					string a = (App.TerminalData != "" ? "--data " + Cli.Quote(App.TerminalData) + " " : "") + "--accent " + Cli.Quote(App.Accent) +
						" --cwd " + Cli.Quote(cwd) + " --title " + Cli.Quote(title) + " --run " + Cli.Quote(run);
					Process.Start(new ProcessStartInfo(App.TerminalExe, a) { UseShellExecute = false });
					return;
				}
				ProcessStartInfo si = new ProcessStartInfo(Path.Combine(sys, "cmd.exe"), "/k " + (args == "install" ? run : Cli.Quote(exe) + (args != "" ? " " + args : "")));
				si.WorkingDirectory = cwd;
				si.UseShellExecute = true;
				Process.Start(si);
			}
			catch (Exception e) { Post(Json.Obj("t", "toast", "text", "Couldn't open a terminal: " + e.Message)); }
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

		public bool TestHasSession { get { return session != null; } }
	}

	// --- Self-test: the real window and page, on a stand-in for claude (CI) -------------

	class Selftest
	{
		readonly string dir;
		readonly List<string> log = new List<string>();
		public int ExitCode = 1;
		ChatWindow win;
		bool pageOk, permissionOk, replyOk, done;
		int lines;
		string work;

		public Selftest(string outDir)
		{
			dir = outDir;
			Directory.CreateDirectory(dir);
		}

		void Log(string s) { log.Add(DateTime.Now.ToString("HH:mm:ss.fff") + " " + s); }

		public void Begin()
		{
			Log("runtime " + App.Version);
			System.Windows.Forms.Timer timeout = new System.Windows.Forms.Timer { Interval = 90000 };
			timeout.Tick += delegate { Log("timed out"); Finish(); };
			timeout.Start();
			work = Path.Combine(Path.GetTempPath(), "oazy-claude-project");
			try
			{
				Directory.CreateDirectory(work);
				File.WriteAllText(Path.Combine(work, "app.js"), "function greet(name) {\n  return 'Hi ' + name;\n}\n");
			}
			catch { }
			Rectangle wa = Screen.PrimaryScreen.WorkingArea;
			Rectangle r = new Rectangle(wa.Left + 20, wa.Top + 20, Math.Min(1280, wa.Width - 40), Math.Min(820, wa.Height - 40));
			win = App.OpenWindow(work, r);
		}

		public void PageReady(ChatWindow w) { pageOk = true; Log("page ready"); Run(); }

		public void Line(string line) { lines++; }

		public void FromPage(ChatWindow w, Dictionary<string, object> m)
		{
			string what = Json.Str(m, "what");
			Log("page says " + what + " " + Json.Str(m, "detail"));
			if (what == "permission") permissionOk = true;
			if (what == "done") replyOk = Json.Str(m, "detail").Contains("greet");
		}

		async void Run()
		{
			await Task.Delay(2500);
			Shot("claude-home.png");
			win.Post(Json.Obj("t", "test", "action", "send", "text", "Add a goodbye function next to greet in app.js"));
			for (int i = 0; i < 40 && !permissionOk; i++) await Task.Delay(250);
			await Task.Delay(900);
			Shot("claude-permission.png");
			win.Post(Json.Obj("t", "test", "action", "allow"));
			for (int i = 0; i < 60 && !replyOk; i++) await Task.Delay(250);
			await Task.Delay(1200);
			Shot("claude-chat.png");
			win.Post(Json.Obj("t", "test", "action", "expand"));
			await Task.Delay(800);
			Shot("claude-tool-open.png");
			win.Post(Json.Obj("t", "test", "action", "menu", "which", "model"));
			await Task.Delay(700);
			Shot("claude-model-menu.png");
			Log(lines + " lines from claude");
			Finish();
		}

		public void Exited()
		{
			Log("message loop ended, exiting with " + ExitCode);
			try { File.WriteAllLines(Path.Combine(dir, "claude-selftest.log"), log.ToArray()); } catch { }
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
			ExitCode = pageOk && permissionOk && replyOk ? 0 : 1;
			Log("page=" + pageOk + " permission=" + permissionOk + " reply=" + replyOk + " -> " + (ExitCode == 0 ? "PASS" : "FAIL"));
			try { File.WriteAllLines(Path.Combine(dir, "claude-selftest.log"), log.ToArray()); } catch { }
			App.Quit();
		}
	}

	// --- A stand-in for claude, for the self-test ----------------------------------------
	// Speaks just enough stream-json: streams a reply, runs a command, asks to
	// edit a file and waits for the answer, the way Claude Code does.

	static class Mock
	{
		static Stream outs;
		static string sid = "5f0c2a8e-0a1b-4c2d-9e3f-0123456789ab";

		static void Emit(object o)
		{
			byte[] b = new UTF8Encoding(false).GetBytes(Json.S.Serialize(o) + "\n");
			outs.Write(b, 0, b.Length);
			outs.Flush();
		}

		static void Ev(object e) { Emit(Json.Obj("type", "stream_event", "event", e, "session_id", sid, "parent_tool_use_id", null)); }

		static void Stream_(int index, string text)
		{
			Ev(Json.Obj("type", "content_block_start", "index", index, "content_block", Json.Obj("type", "text", "text", "")));
			string[] words = text.Split(' ');
			for (int i = 0; i < words.Length; i++)
			{
				Ev(Json.Obj("type", "content_block_delta", "index", index, "delta", Json.Obj("type", "text_delta", "text", (i > 0 ? " " : "") + words[i])));
				Thread.Sleep(18);
			}
			Ev(Json.Obj("type", "content_block_stop", "index", index));
		}

		static void Tool(string msg, int index, string id, string name, Dictionary<string, object> input)
		{
			Ev(Json.Obj("type", "content_block_start", "index", index, "content_block", Json.Obj("type", "tool_use", "id", id, "name", name, "input", Json.Obj())));
			Ev(Json.Obj("type", "content_block_stop", "index", index));
			Emit(Json.Obj("type", "assistant", "session_id", sid, "parent_tool_use_id", null, "message",
				Json.Obj("id", msg, "role", "assistant", "content", new object[] { Json.Obj("type", "tool_use", "id", id, "name", name, "input", input) })));
		}

		static void Result(string id, string text)
		{
			Emit(Json.Obj("type", "user", "session_id", sid, "parent_tool_use_id", null, "message",
				Json.Obj("role", "user", "content", new object[] { Json.Obj("type", "tool_result", "tool_use_id", id, "content", text) })));
		}

		public static int Run()
		{
			outs = Console.OpenStandardOutput();
			StreamReader input = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false));
			string cwd = Directory.GetCurrentDirectory();
			Emit(Json.Obj("type", "system", "subtype", "init", "session_id", sid, "cwd", cwd, "model", "claude-opus-5-5", "permissionMode", "default", "tools", new object[] { "Bash", "Read", "Edit", "Write" }));
			string line;
			while ((line = input.ReadLine()) != null)
			{
				Dictionary<string, object> m = Json.Parse(line);
				if (m == null) continue;
				string type = Json.Str(m, "type");
				if (type == "control_request")
				{
					Emit(Json.Obj("type", "control_response", "response", Json.Obj("subtype", "success", "request_id", Json.Str(m, "request_id"), "response", Json.Obj())));
					continue;
				}
				if (type != "user") continue;
				Ev(Json.Obj("type", "message_start", "message", Json.Obj("id", "msg_1", "model", "claude-opus-5-5")));
				Stream_(0, "I'll look at **app.js** first, then add the function right after `greet`.");
				Tool("msg_1", 1, "toolu_1", "Bash", Json.Obj("command", "type app.js", "description", "Show app.js"));
				Ev(Json.Obj("type", "message_stop"));
				Thread.Sleep(300);
				Result("toolu_1", "function greet(name) {\n  return 'Hi ' + name;\n}");
				Ev(Json.Obj("type", "message_start", "message", Json.Obj("id", "msg_2", "model", "claude-opus-5-5")));
				Tool("msg_2", 0, "toolu_2", "Edit", Json.Obj("file_path", Path.Combine(cwd, "app.js"),
					"old_string", "function greet(name) {\n  return 'Hi ' + name;\n}",
					"new_string", "function greet(name) {\n  return 'Hi ' + name;\n}\n\nfunction goodbye(name) {\n  return 'Bye ' + name;\n}"));
				Emit(Json.Obj("type", "control_request", "request_id", "perm-1", "request", Json.Obj("subtype", "can_use_tool", "tool_name", "Edit",
					"input", Json.Obj("file_path", Path.Combine(cwd, "app.js")), "tool_use_id", "toolu_2",
					"permission_suggestions", new object[] { Json.Obj("type", "setMode", "mode", "acceptEdits", "destination", "session") })));
				// Wait for Allow or Deny.
				bool allowed = false;
				while ((line = input.ReadLine()) != null)
				{
					Dictionary<string, object> r = Json.Parse(line);
					if (r == null || Json.Str(r, "type") != "control_response") continue;
					allowed = line.Contains("\"allow\"");
					break;
				}
				Result("toolu_2", allowed ? "The file app.js has been updated." : "The user doesn't want to proceed with this tool use.");
				Ev(Json.Obj("type", "message_stop"));
				Ev(Json.Obj("type", "message_start", "message", Json.Obj("id", "msg_3", "model", "claude-opus-5-5")));
				Stream_(0, allowed
					? "Done. `app.js` now has a **goodbye** function next to greet:\n\n```js\nfunction goodbye(name) {\n  return 'Bye ' + name;\n}\n```\n\n- Same shape as `greet`\n- No other files touched"
					: "Okay, I left app.js as it was.");
				Ev(Json.Obj("type", "message_stop"));
				Emit(Json.Obj("type", "result", "subtype", "success", "is_error", false, "session_id", sid, "num_turns", 3, "duration_ms", 4200, "result", "Done"));
			}
			return 0;
		}
	}
}
