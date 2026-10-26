// Oazy Browser: Chromium, through the WebView2 runtime that ships with
// Windows 11, inside an Oazy glass window.
//
// The window is a borderless WinForms form with an acrylic backdrop. Its top
// strip (tabs, address bar, panels) is a transparent WebView2 showing
// ui/chrome.html; every tab is its own WebView2 below it. Both talk to this
// file with postMessage, one JSON object per message ({"t": "<type>", ...}).
//
// Like the shell companion, Oazy compiles this file on first use with the
// .NET Framework csc.exe that comes with Windows, so it must stay C# 5. It
// references Microsoft.Web.WebView2.Core.dll; Oazy extracts that DLL and
// WebView2Loader.dll next to the compiled exe.
//
// Usage: OazyBrowser.exe --data <dir> [--accent <hex>] [--new-window] [url]
//        OazyBrowser.exe --data <dir> --app <id>     (a web app, see WebApps)
//        OazyBrowser.exe --data <dir> --signin <email|-> --result <file>   (Oazy's
//            Google sign-in, see SignInJob; --signout signs every app out)
//        OazyBrowser.exe --selftest <out dir>
// A second launch hands its url to the running browser over a named pipe.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Pipes;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;

namespace OazyBrowser
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
		[DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
		[DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int index, IntPtr value);
		[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
		[DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
		[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetProp(IntPtr h, string name, IntPtr value);
		[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
		[DllImport("user32.dll")] public static extern bool ReleaseCapture();
		[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
		[DllImport("user32.dll")] public static extern short GetKeyState(int vk);
		[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
		[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);
		[DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
		[DllImport("user32.dll")] public static extern int GetSystemMetricsForDpi(int index, uint dpi);
		[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
		[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
		[DllImport("user32.dll")] public static extern bool GetCursorPos(out Point p);
		[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
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

	static class Program
	{
		[STAThread]
		static int Main(string[] args)
		{
			string data = "", accent = "", selftest = "", app = "", signin = null, result = "";
			bool newWindow = false, signout = false;
			List<string> urls = new List<string>();
			for (int i = 0; i < args.Length; i++)
			{
				string a = args[i];
				if (a == "--data" && i + 1 < args.Length) data = args[++i];
				else if (a == "--accent" && i + 1 < args.Length) accent = args[++i];
				else if (a == "--selftest" && i + 1 < args.Length) selftest = args[++i];
				else if (a == "--app" && i + 1 < args.Length) app = args[++i];
				else if (a == "--signin" && i + 1 < args.Length) signin = args[++i];
				else if (a == "--signout") signout = true;
				else if (a == "--result" && i + 1 < args.Length) result = args[++i];
				else if (a == "--new-window") newWindow = true;
				else if (a.Trim() != "") urls.Add(a.Trim());
			}
			if (selftest != "") data = Path.Combine(Path.GetTempPath(), "OazyBrowserSelftest-" + Process.GetCurrentProcess().Id);
			if (data == "") data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Oazy", "Browser");
			data = Path.GetFullPath(data);

			string pipe = "OazyBrowser-" + App.Hash(Environment.UserName + "|" + data.ToLowerInvariant());
			bool first;
			Mutex single = new Mutex(true, "Local\\" + pipe, out first);
			if (signout) { App.SignInMode = "signout"; App.SignInResult = result; }
			else if (signin != null) { App.SignInMode = "signin"; App.SignInHint = signin.Trim() == "-" ? "" : signin.Trim(); App.SignInResult = result; }
			if (!first && selftest == "")
			{
				if (Forward(pipe, newWindow, urls, app)) return 0;
				// The running copy isn't answering; carry on as a second one.
			}
			try { if (!Native.SetProcessDpiAwarenessContext(new IntPtr(-4))) Native.SetProcessDPIAware(); }
			catch { try { Native.SetProcessDPIAware(); } catch { } }
			try { ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11; } catch { }
			Application.EnableVisualStyles();
			Application.SetCompatibleTextRenderingDefault(false);
			int code = App.Run(data, accent, pipe, urls, newWindow, selftest, app);
			GC.KeepAlive(single);
			// Everything is saved and every WebView closed. Leave now rather than
			// let CLR shutdown finalize WebView2's COM objects off their STA
			// thread, which crashes (0xC0000005) on the way out.
			try { single.ReleaseMutex(); } catch { }
			Native.TerminateProcess(Native.GetCurrentProcess(), (uint)code);
			return code;
		}

		static bool Forward(string pipe, bool newWindow, List<string> urls, string app)
		{
			for (int attempt = 0; attempt < 3; attempt++)
			{
				try
				{
					using (NamedPipeClientStream c = new NamedPipeClientStream(".", pipe, PipeDirection.Out))
					{
						c.Connect(1000);
						// Let the running browser bring its window to the front.
						try { Native.AllowSetForegroundWindow(-1); } catch { }
						StringBuilder sb = new StringBuilder();
						// Result file first: the line's ends get trimmed and the hint can be empty.
						if (App.SignInMode != "") sb.Append(App.SignInMode).Append('\t').Append(App.SignInResult.Replace("\t", " ")).Append('\t').Append(App.SignInHint).Append('\n');
						else if (app != "") sb.Append("app\t").Append(app).Append('\n');
						else if (urls.Count == 0) sb.Append(newWindow ? "window\t\n" : "open\t\n");
						foreach (string u in urls) sb.Append(newWindow ? "window\t" : "open\t").Append(u.Replace("\n", " ")).Append('\n');
						byte[] bytes = Encoding.UTF8.GetBytes(sb.ToString());
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

	// --- The browser as a whole: profile, windows, history, downloads ----------------

	static class App
	{
		public const string UiHost = "oazy.example";
		public const string MediaHost = "media.oazy.example";
		public const string ChromeUrl = "https://oazy.example/chrome.html";
		public const string NewTabUrl = "https://oazy.example/newtab.html";
		public const string AppChromeUrl = "https://oazy.example/app.html";
		public const string Name = "Oazy Browser";

		public static string Data, Ui, Media, Accent = "#38d6c4", Version = "";
		// Asked for on the command line: "signin" or "signout" (see SignInJob).
		public static string SignInMode = "", SignInHint = "", SignInResult = "";
		public static CoreWebView2Environment Env;
		public static SynchronizationContext Sync;
		public static readonly List<BrowserWindow> Windows = new List<BrowserWindow>();
		public static BrowserWindow LastActive;
		public static Dictionary<string, object> Prefs;
		public static readonly List<string> Closed = new List<string>();
		public static Selftest Test;
		static ApplicationContext ctx;
		static System.Windows.Forms.Timer saveTimer;
		static bool sessionDirty, prefsDirty, quitting;
		static string pipeName;

		public static readonly string[][] Engines = new string[][]
		{
			// id, name, search, suggest (OpenSearch JSON)
			new string[] { "google", "Google", "https://www.google.com/search?q=", "https://suggestqueries.google.com/complete/search?client=firefox&ie=utf-8&oe=utf-8&q=" },
			new string[] { "bing", "Bing", "https://www.bing.com/search?q=", "https://api.bing.com/osjson.aspx?query=" },
			new string[] { "duckduckgo", "DuckDuckGo", "https://duckduckgo.com/?q=", "https://duckduckgo.com/ac/?type=list&q=" },
			new string[] { "brave", "Brave", "https://search.brave.com/search?q=", "https://search.brave.com/api/suggest?q=" },
		};

		public static int Run(string data, string accent, string pipe, List<string> urls, bool newWindow, string selftest, string app)
		{
			Data = data;
			pipeName = pipe;
			string bin = Path.GetDirectoryName(Application.ExecutablePath);
			Ui = Path.Combine(bin, "ui");
			Media = Path.Combine(Data, "media");
			try
			{
				Directory.CreateDirectory(Path.Combine(Media, "icons"));
				Directory.CreateDirectory(Path.Combine(Media, "snaps"));
				foreach (string f in Directory.GetFiles(Path.Combine(Media, "snaps"))) { try { File.Delete(f); } catch { } }
			}
			catch (Exception e)
			{
				MessageBox.Show("Oazy Browser can't use its profile folder:\n" + Data + "\n\n" + e.Message, Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
				return 2;
			}
			try { Version = CoreWebView2Environment.GetAvailableBrowserVersionString(); }
			catch (Exception)
			{
				Version = "";
			}
			if (string.IsNullOrEmpty(Version))
			{
				NoRuntime();
				return 3;
			}

			Prefs = Json.Load(Path.Combine(Data, "prefs.json"));
			if (accent != "") { Prefs["accent"] = accent; prefsDirty = true; }
			Accent = Json.Str(Prefs, "accent") != "" ? Json.Str(Prefs, "accent") : Accent;
			History.Load();
			Downloads.Load();

			SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());
			Sync = SynchronizationContext.Current;
			ctx = new ApplicationContext();
			saveTimer = new System.Windows.Forms.Timer { Interval = 1500 };
			saveTimer.Tick += delegate { SaveNow(); };
			saveTimer.Start();
			if (selftest != "") Test = new Selftest(selftest);
			else StartPipe();
			Start(urls, newWindow, app);
			Application.Run(ctx);
			SaveNow();
			if (Test != null) Test.Exited();
			return Test != null ? Test.ExitCode : 0;
		}

		static async void Start(List<string> urls, bool newWindow, string app)
		{
			try
			{
				CoreWebView2EnvironmentOptions opts = new CoreWebView2EnvironmentOptions("--enable-features=OverlayScrollbar");
				Env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(Data, "webview"), opts);
			}
			catch (Exception e)
			{
				MessageBox.Show("Oazy Browser couldn't start Chromium.\n\n" + e.Message, Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
				ctx.ExitThread();
				return;
			}
			Env.BrowserProcessExited += OnBrowserExited;
			if (Test != null)
			{
				Test.Begin();
				return;
			}
			// A web app or a sign-in opens on its own; your browser tabs wait until you open the browser.
			if (SignInMode != "") { SignIn(SignInMode == "signout", SignInHint, SignInResult); return; }
			if (WebApps.Find(app) != null) { OpenApp(WebApps.Find(app)); return; }
			OpenBrowser(urls, newWindow);
		}

		static bool sessionLoaded;

		static void OpenBrowser(List<string> urls, bool newWindow)
		{
			bool restored = false;
			if (!sessionLoaded && !newWindow && Json.Bool(Prefs, "no_restore") == false) restored = RestoreSession();
			sessionLoaded = true;
			if (!restored) OpenWindow(urls.Count > 0 ? urls : new List<string> { "" }, 0, null, false);
			else foreach (string u in urls) LastActive.AddTab(FixUrl(u), true, -1);
		}

		// The window of a web app, brought up if it's already open.
		public static BrowserWindow OpenApp(WebAppDef a)
		{
			foreach (BrowserWindow w in Windows)
				if (w.WebApp == a) { w.BringUp(); return w; }
			Rectangle? bounds = null;
			bool max = false;
			Dictionary<string, object> saved = Prefs.ContainsKey("app_" + a.Id) ? Prefs["app_" + a.Id] as Dictionary<string, object> : null;
			if (saved != null)
			{
				object[] b = saved.ContainsKey("bounds") ? saved["bounds"] as object[] : null;
				if (b != null && b.Length == 4)
					try { bounds = new Rectangle(Convert.ToInt32(b[0]), Convert.ToInt32(b[1]), Convert.ToInt32(b[2]), Convert.ToInt32(b[3])); } catch { }
				max = Json.Bool(saved, "max");
			}
			return OpenWindow(new List<string> { a.Url }, 0, bounds, max, a);
		}

		// The most recent ordinary browser window, if any.
		public static BrowserWindow LastBrowser()
		{
			if (LastActive != null && LastActive.WebApp == null) return LastActive;
			for (int i = Windows.Count - 1; i >= 0; i--) if (Windows[i].WebApp == null) return Windows[i];
			return null;
		}

		// Opens a url in the browser proper (from a web app's window).
		public static void OpenInBrowser(string url)
		{
			BrowserWindow w = LastBrowser();
			if (w == null) { OpenBrowser(new List<string> { url }, false); return; }
			w.AddTab(FixUrl(url), true, -1);
			w.BringUp();
		}

		static bool RestoreSession()
		{
			Dictionary<string, object> s = Json.Load(Path.Combine(Data, "session.json"));
			object[] wins = s.ContainsKey("windows") ? s["windows"] as object[] : null;
			if (wins == null || wins.Length == 0) return false;
			int before = Windows.Count;
			int opened = 0;
			foreach (object o in wins)
			{
				Dictionary<string, object> w = o as Dictionary<string, object>;
				if (w == null) continue;
				object[] tabs = w.ContainsKey("tabs") ? w["tabs"] as object[] : null;
				if (tabs == null || tabs.Length == 0) continue;
				List<string> list = new List<string>();
				foreach (object t in tabs) list.Add(Convert.ToString(t));
				Rectangle? bounds = null;
				object[] b = w.ContainsKey("bounds") ? w["bounds"] as object[] : null;
				if (b != null && b.Length == 4)
				{
					try { bounds = new Rectangle(Convert.ToInt32(b[0]), Convert.ToInt32(b[1]), Convert.ToInt32(b[2]), Convert.ToInt32(b[3])); } catch { }
				}
				OpenWindow(list, Json.Int(w, "active"), bounds, Json.Bool(w, "max"));
				opened++;
			}
			return opened > 0 && Windows.Count > before;
		}

		public static BrowserWindow OpenWindow(List<string> urls, int active, Rectangle? bounds, bool maximized)
		{
			return OpenWindow(urls, active, bounds, maximized, null);
		}

		public static BrowserWindow OpenWindow(List<string> urls, int active, Rectangle? bounds, bool maximized, WebAppDef app)
		{
			return OpenWindow(urls, active, bounds, maximized, app, null, null);
		}

		public static BrowserWindow OpenWindow(List<string> urls, int active, Rectangle? bounds, bool maximized, WebAppDef app, Form owner, SignInJob job)
		{
			BrowserWindow w = new BrowserWindow(urls, active, bounds, maximized, app);
			w.Job = job;
			if (owner != null && !owner.IsDisposed)
			{
				// A site's sign-in popup sits over the window that asked for it.
				w.Owner = owner;
				Rectangle o = owner.Bounds;
				Rectangle wa = Screen.FromRectangle(o).WorkingArea;
				Rectangle r = w.Bounds;
				r.X = Math.Max(wa.Left, Math.Min(wa.Right - r.Width, o.Left + (o.Width - r.Width) / 2));
				r.Y = Math.Max(wa.Top, Math.Min(wa.Bottom - r.Height, o.Top + (o.Height - r.Height) / 2));
				w.Bounds = r;
			}
			Windows.Add(w);
			LastActive = w;
			w.FormClosed += delegate
			{
				Windows.Remove(w);
				if (LastActive == w) LastActive = Windows.Count > 0 ? Windows[Windows.Count - 1] : null;
				if (Windows.Count == 0) Quit();
				else SessionChanged();
			};
			w.Show();
			w.Activate();
			return w;
		}

		// Oazy's own sign-in (or sign-out) window. One at a time: asking again
		// brings the open one up.
		public static void SignIn(bool signOut, string hint, string result)
		{
			foreach (BrowserWindow x in Windows)
				if (x.Job != null && !x.Job.Finished) { x.BringUp(); return; }
			SignInJob job = new SignInJob(signOut, hint, result);
			OpenWindow(new List<string> { job.StartUrl() }, 0, null, false, WebApps.SignInDef, null, job);
		}

		public static void Quit()
		{
			if (quitting) return;
			quitting = true;
			SaveNow();
			// Close every window (and with it every WebView) before the message
			// loop ends; leaving them to finalizers crashes on the way out.
			foreach (BrowserWindow w in Windows.ToArray()) { try { w.Close(); } catch { } }
			ctx.ExitThread();
		}

		static void OnBrowserExited(object sender, CoreWebView2BrowserProcessExitedEventArgs e)
		{
			if (quitting || e.BrowserProcessExitKind == CoreWebView2BrowserProcessExitKind.Normal) return;
			// Chromium died under us: come back with the same tabs.
			SaveNow();
			try { Process.Start(Application.ExecutablePath, "--data \"" + Data + "\""); } catch { }
			quitting = true;
			ctx.ExitThread();
		}

		static void NoRuntime()
		{
			DialogResult r = MessageBox.Show(
				"Oazy Browser runs on the Microsoft Edge WebView2 Runtime, which isn't installed on this PC.\n\nOpen the download page now?",
				Name, MessageBoxButtons.YesNo, MessageBoxIcon.Information);
			if (r == DialogResult.Yes)
			{
				try { Process.Start("https://go.microsoft.com/fwlink/p/?LinkId=2124703"); } catch { }
			}
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
				int tab = line.IndexOf('\t');
				if (tab < 0) continue;
				string kind = line.Substring(0, tab), url = line.Substring(tab + 1).Trim();
				BrowserWindow last = LastBrowser();
				if (kind == "app")
				{
					if (WebApps.Find(url) != null) OpenApp(WebApps.Find(url));
				}
				else if (kind == "signin" || kind == "signout")
				{
					string[] parts = url.Split('\t');
					SignIn(kind == "signout", parts.Length > 1 ? parts[1].Trim() : "", parts[0].Trim());
				}
				else if (!sessionLoaded || last == null)
				{
					// Only web apps were open: this is the browser's first window.
					OpenBrowser(url == "" ? new List<string>() : new List<string> { url }, kind == "window");
				}
				else if (kind == "window" || (kind == "open" && url == ""))
				{
					OpenWindow(new List<string> { url }, 0, null, false);
				}
				else
				{
					last.AddTab(FixUrl(url), true, -1);
					last.BringUp();
				}
			}
		}

		// --- Settings, session ----------------------------------------------------------

		public static string Engine()
		{
			string id = Json.Str(Prefs, "engine");
			foreach (string[] e in Engines) if (e[0] == id) return id;
			return "google";
		}

		public static string[] EngineInfo()
		{
			string id = Engine();
			foreach (string[] e in Engines) if (e[0] == id) return e;
			return Engines[0];
		}

		public static void SetPref(string key, object value)
		{
			Prefs[key] = value;
			prefsDirty = true;
		}

		public static List<object> Pinned()
		{
			object v;
			if (Prefs.TryGetValue("pinned", out v))
			{
				object[] arr = v as object[];
				if (arr != null) return new List<object>(arr);
				List<object> l = v as List<object>;
				if (l != null) return l;
			}
			return new List<object>();
		}

		public static bool IsPinned(string url)
		{
			if (url == "") return false;
			foreach (object o in Pinned())
			{
				Dictionary<string, object> p = o as Dictionary<string, object>;
				if (p != null && SameSite(Json.Str(p, "url"), url)) return true;
			}
			return false;
		}

		public static void SetPinned(string url, string title, bool on)
		{
			List<object> list = Pinned();
			list.RemoveAll(delegate(object o)
			{
				Dictionary<string, object> p = o as Dictionary<string, object>;
				return p == null || SameSite(Json.Str(p, "url"), url);
			});
			if (on) list.Add(Json.Obj("url", url, "title", title));
			SetPref("pinned", list.ToArray());
			BroadcastNtp();
		}

		static bool SameSite(string a, string b)
		{
			return a.TrimEnd('/').Equals(b.TrimEnd('/'), StringComparison.OrdinalIgnoreCase);
		}

		public static void SessionChanged() { sessionDirty = true; }

		public static void SaveNow()
		{
			if (Test != null) return;
			if (prefsDirty)
			{
				prefsDirty = false;
				Json.Save(Path.Combine(Data, "prefs.json"), Prefs);
			}
			if (sessionDirty && Windows.Count > 0)
			{
				sessionDirty = false;
				List<object> wins = new List<object>();
				foreach (BrowserWindow w in Windows)
				{
					// A web app keeps only where its window was; it isn't part of the session.
					if (w.WebApp != null)
					{
						if (!w.WebApp.Popup) { Prefs["app_" + w.WebApp.Id] = w.SessionInfo(); prefsDirty = true; }
					}
					else wins.Add(w.SessionInfo());
				}
				if (wins.Count > 0 && sessionLoaded) Json.Save(Path.Combine(Data, "session.json"), Json.Obj("windows", wins.ToArray()));
			}
			if (prefsDirty)
			{
				prefsDirty = false;
				Json.Save(Path.Combine(Data, "prefs.json"), Prefs);
			}
			History.SaveIfDirty();
			Downloads.SaveIfDirty();
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

		// What you typed in the address bar -> a URL to open.
		public static string FixUrl(string text)
		{
			string t = (text ?? "").Trim();
			if (t == "") return NewTabUrl;
			string lower = t.ToLowerInvariant();
			if (lower.StartsWith("http://") || lower.StartsWith("https://") || lower.StartsWith("file:") || lower.StartsWith("about:") ||
				lower.StartsWith("edge://") || lower.StartsWith("view-source:") || lower.StartsWith("data:") || lower.StartsWith("mailto:"))
				return t;
			if (t.Length > 2 && char.IsLetter(t[0]) && t[1] == ':' && (t[2] == '\\' || t[2] == '/'))
				return new Uri(t).AbsoluteUri;
			if (t.StartsWith("\\\\")) return new Uri(t).AbsoluteUri;
			if (t.IndexOf(' ') < 0)
			{
				string host = t;
				int cut = host.IndexOfAny(new char[] { '/', '?', '#' });
				if (cut >= 0) host = host.Substring(0, cut);
				string port = "";
				int colon = host.LastIndexOf(':');
				if (colon > 0) { port = host.Substring(colon + 1); host = host.Substring(0, colon); }
				bool portOk = port == "" || IsDigits(port);
				if (portOk && (host.ToLowerInvariant() == "localhost" || IsIp(host))) return "http://" + t;
				int dot = host.LastIndexOf('.');
				if (portOk && dot > 0 && dot < host.Length - 2)
				{
					string tld = host.Substring(dot + 1);
					bool alpha = true;
					foreach (char c in tld) if (!char.IsLetter(c)) alpha = false;
					if (alpha && host.IndexOf('@') < 0) return "https://" + t;
				}
			}
			return SearchUrl(t);
		}

		public static string SearchUrl(string q)
		{
			return EngineInfo()[2] + Uri.EscapeDataString(q);
		}

		static bool IsDigits(string s)
		{
			if (s == "") return false;
			foreach (char c in s) if (c < '0' || c > '9') return false;
			return true;
		}

		static bool IsIp(string s)
		{
			string[] parts = s.Split('.');
			if (parts.Length != 4) return false;
			foreach (string p in parts) { int n; if (!int.TryParse(p, out n) || n < 0 || n > 255) return false; }
			return true;
		}

		public static string HostOf(string url)
		{
			try { return new Uri(url).Host.ToLowerInvariant(); } catch { return ""; }
		}

		// The cached favicon for a site, if we have one.
		public static string IconFile(string url)
		{
			string host = HostOf(url);
			if (host.StartsWith("www.")) host = host.Substring(4);
			return host == "" ? "" : Path.Combine(Media, "icons", Hash(host) + ".png");
		}

		public static string IconDataUrl(string url)
		{
			string f = IconFile(url);
			try
			{
				if (f != "" && File.Exists(f)) return "data:image/png;base64," + Convert.ToBase64String(File.ReadAllBytes(f));
			}
			catch { }
			return "";
		}

		public static string IconHttpUrl(string url)
		{
			string f = IconFile(url);
			if (f == "" || !File.Exists(f)) return "";
			return "https://" + MediaHost + "/icons/" + Path.GetFileName(f) + "?v=" + File.GetLastWriteTimeUtc(f).Ticks;
		}

		public static void BroadcastNtp()
		{
			foreach (BrowserWindow w in Windows) w.RefreshNtp();
		}

		// Tiles for the new tab page: pinned sites, then where you go most.
		public static object[] Tiles()
		{
			List<object> tiles = new List<object>();
			HashSet<string> seen = new HashSet<string>();
			foreach (object o in Pinned())
			{
				Dictionary<string, object> p = o as Dictionary<string, object>;
				if (p == null) continue;
				string url = Json.Str(p, "url");
				seen.Add(HostOf(url));
				tiles.Add(Json.Obj("url", url, "title", Json.Str(p, "title"), "icon", IconDataUrl(url), "pinned", true));
			}
			HashSet<string> hidden = new HashSet<string>();
			object hv;
			if (Prefs.TryGetValue("hidden_sites", out hv) && hv is object[]) foreach (object h in (object[])hv) hidden.Add(Convert.ToString(h));
			foreach (Dictionary<string, object> h in History.Top(24))
			{
				if (tiles.Count >= 10) break;
				string url = Json.Str(h, "u");
				string host = HostOf(url);
				if (host == "" || seen.Contains(host) || hidden.Contains(host)) continue;
				seen.Add(host);
				tiles.Add(Json.Obj("url", url, "title", Json.Str(h, "t"), "icon", IconDataUrl(url), "pinned", false));
			}
			return tiles.ToArray();
		}

		public static void HideSite(string url)
		{
			List<object> list = new List<object>();
			object hv;
			if (Prefs.TryGetValue("hidden_sites", out hv) && hv is object[]) list.AddRange((object[])hv);
			string host = HostOf(url);
			if (host != "" && !list.Contains(host)) list.Add(host);
			SetPref("hidden_sites", list.ToArray());
			SetPinned(url, "", false);
		}
	}

	// --- History: where you've been, for suggestions and the new tab page ----------

	static class History
	{
		const int Max = 4000;
		static List<Dictionary<string, object>> items = new List<Dictionary<string, object>>();
		static Dictionary<string, Dictionary<string, object>> byUrl = new Dictionary<string, Dictionary<string, object>>();
		static bool dirty;

		static string File_ { get { return Path.Combine(App.Data, "history.json"); } }

		public static void Load()
		{
			Dictionary<string, object> d = Json.Load(File_);
			object[] arr = d.ContainsKey("items") ? d["items"] as object[] : null;
			if (arr == null) return;
			foreach (object o in arr)
			{
				Dictionary<string, object> h = o as Dictionary<string, object>;
				if (h == null || Json.Str(h, "u") == "" || byUrl.ContainsKey(Json.Str(h, "u"))) continue;
				items.Add(h);
				byUrl[Json.Str(h, "u")] = h;
			}
		}

		public static void SaveIfDirty()
		{
			if (!dirty || App.Test != null) return;
			dirty = false;
			Json.Save(File_, Json.Obj("items", items.ToArray()));
		}

		static long Now() { return (long)(DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalSeconds; }

		public static void Visit(string url, string title)
		{
			if (!url.StartsWith("http://") && !url.StartsWith("https://")) return;
			if (url.StartsWith("https://" + App.UiHost)) return;
			Dictionary<string, object> h;
			if (byUrl.TryGetValue(url, out h))
			{
				items.Remove(h);
				h["n"] = Json.Int(h, "n") + 1;
			}
			else
			{
				h = Json.Obj("u", url, "t", title, "n", 1);
				byUrl[url] = h;
			}
			if (title != "") h["t"] = title;
			h["at"] = Now();
			items.Insert(0, h);
			while (items.Count > Max)
			{
				byUrl.Remove(Json.Str(items[items.Count - 1], "u"));
				items.RemoveAt(items.Count - 1);
			}
			dirty = true;
		}

		public static void Title(string url, string title)
		{
			Dictionary<string, object> h;
			if (title != "" && byUrl.TryGetValue(url, out h)) { h["t"] = title; dirty = true; }
		}

		public static void Remove(string url)
		{
			Dictionary<string, object> h;
			if (byUrl.TryGetValue(url, out h)) { items.Remove(h); byUrl.Remove(url); dirty = true; }
		}

		public static void Clear()
		{
			items.Clear();
			byUrl.Clear();
			dirty = true;
		}

		// Most visited, one entry per site, recent visits weigh more.
		public static List<Dictionary<string, object>> Top(int n)
		{
			long now = Now();
			Dictionary<string, double> score = new Dictionary<string, double>();
			Dictionary<string, Dictionary<string, object>> best = new Dictionary<string, Dictionary<string, object>>();
			foreach (Dictionary<string, object> h in items)
			{
				string host = App.HostOf(Json.Str(h, "u"));
				if (host == "") continue;
				double age = Math.Max(0, now - Convert.ToInt64(h.ContainsKey("at") ? h["at"] : 0)) / 86400.0;
				double s = Json.Int(h, "n") / (1.0 + age / 7.0);
				double cur;
				score.TryGetValue(host, out cur);
				score[host] = cur + s;
				Dictionary<string, object> b;
				// The site's front page beats a deep link as the tile's target.
				if (!best.TryGetValue(host, out b) || Json.Str(h, "u").Length < Json.Str(b, "u").Length) best[host] = h;
			}
			List<string> hosts = new List<string>(score.Keys);
			hosts.Sort(delegate(string a, string b) { return score[b].CompareTo(score[a]); });
			List<Dictionary<string, object>> outList = new List<Dictionary<string, object>>();
			foreach (string host in hosts)
			{
				if (outList.Count >= n) break;
				outList.Add(best[host]);
			}
			return outList;
		}

		public static List<Dictionary<string, object>> Search(string q, int n)
		{
			List<Dictionary<string, object>> outList = new List<Dictionary<string, object>>();
			string[] words = q.ToLowerInvariant().Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
			if (words.Length == 0) return outList;
			List<KeyValuePair<double, Dictionary<string, object>>> scored = new List<KeyValuePair<double, Dictionary<string, object>>>();
			foreach (Dictionary<string, object> h in items)
			{
				string u = Json.Str(h, "u").ToLowerInvariant();
				string bare = u.Replace("https://", "").Replace("http://", "").Replace("www.", "");
				string t = Json.Str(h, "t").ToLowerInvariant();
				bool all = true;
				double s = Json.Int(h, "n");
				foreach (string w in words)
				{
					if (bare.StartsWith(w)) s += 40;
					else if (bare.Contains(w)) s += 10;
					else if (t.Contains(w)) s += 6;
					else { all = false; break; }
				}
				if (all) scored.Add(new KeyValuePair<double, Dictionary<string, object>>(s - bare.Length * 0.05, h));
			}
			scored.Sort(delegate(KeyValuePair<double, Dictionary<string, object>> a, KeyValuePair<double, Dictionary<string, object>> b) { return b.Key.CompareTo(a.Key); });
			foreach (KeyValuePair<double, Dictionary<string, object>> kv in scored)
			{
				if (outList.Count >= n) break;
				outList.Add(kv.Value);
			}
			return outList;
		}

		public static object[] List(string q, int n)
		{
			List<object> outList = new List<object>();
			string needle = (q ?? "").ToLowerInvariant().Trim();
			foreach (Dictionary<string, object> h in items)
			{
				if (outList.Count >= n) break;
				if (needle != "" && !Json.Str(h, "u").ToLowerInvariant().Contains(needle) && !Json.Str(h, "t").ToLowerInvariant().Contains(needle)) continue;
				string u = Json.Str(h, "u");
				outList.Add(Json.Obj("url", u, "title", Json.Str(h, "t"), "at", h.ContainsKey("at") ? h["at"] : 0, "icon", App.IconHttpUrl(u)));
			}
			return outList.ToArray();
		}
	}

	// --- Downloads: one list for every window ------------------------------------------

	class Download
	{
		public int Id;
		public CoreWebView2DownloadOperation Op;
		public string Path = "", Url = "", State = "progress";
		public long Received, Total, LastBytes;
		public double Speed;
		public DateTime LastTick = DateTime.UtcNow;
		public long Finished;
	}

	static class Downloads
	{
		public static readonly List<Download> Items = new List<Download>();
		static int nextId = 1;
		static bool dirty, saveDirty;
		static System.Windows.Forms.Timer tick;

		public static void Load()
		{
			Dictionary<string, object> d = Json.Load(System.IO.Path.Combine(App.Data, "downloads.json"));
			object[] arr = d.ContainsKey("items") ? d["items"] as object[] : null;
			if (arr == null) return;
			foreach (object o in arr)
			{
				Dictionary<string, object> h = o as Dictionary<string, object>;
				if (h == null) continue;
				Download x = new Download { Id = nextId++, Path = Json.Str(h, "path"), Url = Json.Str(h, "url"), State = Json.Str(h, "state") };
				x.Total = x.Received = h.ContainsKey("size") ? Convert.ToInt64(h["size"]) : 0;
				x.Finished = h.ContainsKey("at") ? Convert.ToInt64(h["at"]) : 0;
				if (x.State == "done" && !File.Exists(x.Path)) x.State = "gone";
				Items.Add(x);
			}
		}

		public static void SaveIfDirty()
		{
			if (!saveDirty || App.Test != null) return;
			saveDirty = false;
			List<object> list = new List<object>();
			foreach (Download x in Items)
			{
				if (x.State == "progress" || x.State == "paused" || list.Count >= 40) continue;
				list.Add(Json.Obj("path", x.Path, "url", x.Url, "state", x.State, "size", x.Total, "at", x.Finished));
			}
			Json.Save(System.IO.Path.Combine(App.Data, "downloads.json"), Json.Obj("items", list.ToArray()));
		}

		public static void Start(CoreWebView2DownloadStartingEventArgs e, BrowserWindow from)
		{
			// Oazy draws its own downloads; Chromium's bubble stays hidden.
			e.Handled = true;
			CoreWebView2DownloadOperation op = e.DownloadOperation;
			Download d = new Download { Id = nextId++, Op = op, Path = e.ResultFilePath, Url = op.Uri };
			try { d.Total = (long)(op.TotalBytesToReceive ?? 0); } catch { }
			Items.Insert(0, d);
			op.BytesReceivedChanged += delegate
			{
				d.Received = op.BytesReceived;
				try { d.Total = (long)(op.TotalBytesToReceive ?? 0); } catch { }
				dirty = true;
			};
			op.StateChanged += delegate
			{
				d.Path = op.ResultFilePath;
				switch (op.State)
				{
					case CoreWebView2DownloadState.Completed:
						d.State = "done";
						d.Received = d.Total = Math.Max(d.Received, op.BytesReceived);
						d.Finished = (long)(DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalSeconds;
						foreach (BrowserWindow w in App.Windows) w.Post(Json.Obj("t", "dlDone", "name", System.IO.Path.GetFileName(d.Path)));
						break;
					case CoreWebView2DownloadState.Interrupted:
						d.State = op.InterruptReason == CoreWebView2DownloadInterruptReason.UserCanceled ? "cancelled" : (op.CanResume ? "paused" : "failed");
						break;
					default:
						d.State = "progress";
						break;
				}
				saveDirty = true;
				Push();
			};
			EnsureTick();
			if (from != null) from.Post(Json.Obj("t", "dlStarted"));
			Push();
		}

		static void EnsureTick()
		{
			if (tick != null) return;
			tick = new System.Windows.Forms.Timer { Interval = 400 };
			tick.Tick += delegate
			{
				DateTime now = DateTime.UtcNow;
				foreach (Download d in Items)
				{
					if (d.State != "progress") { d.Speed = 0; continue; }
					double dt = (now - d.LastTick).TotalSeconds;
					if (dt <= 0) continue;
					double inst = (d.Received - d.LastBytes) / dt;
					d.Speed = d.Speed <= 0 ? inst : d.Speed * 0.7 + inst * 0.3;
					d.LastBytes = d.Received;
					d.LastTick = now;
				}
				if (dirty) { dirty = false; Push(); }
			};
			tick.Start();
		}

		public static object Snapshot()
		{
			List<object> list = new List<object>();
			int active = 0;
			long got = 0, total = 0;
			foreach (Download d in Items)
			{
				if (d.State == "progress")
				{
					active++;
					got += d.Received;
					total += Math.Max(d.Total, d.Received);
				}
				list.Add(Json.Obj("id", d.Id, "name", System.IO.Path.GetFileName(d.Path), "url", d.Url, "state", d.State,
					"received", d.Received, "total", d.Total, "speed", (long)d.Speed, "at", d.Finished));
			}
			return Json.Obj("t", "downloads", "items", list.ToArray(), "active", active,
				"progress", total > 0 ? (double)got / total : (active > 0 ? -1.0 : 0.0));
		}

		public static void Push()
		{
			object s = Snapshot();
			foreach (BrowserWindow w in App.Windows) w.Post(s);
		}

		public static void Act(int id, string action)
		{
			Download d = Items.Find(delegate(Download x) { return x.Id == id; });
			if (d == null && action != "clear") return;
			try
			{
				switch (action)
				{
					case "open":
						if (File.Exists(d.Path)) Process.Start(new ProcessStartInfo(d.Path) { UseShellExecute = true });
						break;
					case "show":
						if (File.Exists(d.Path)) Process.Start("explorer.exe", "/select,\"" + d.Path + "\"");
						else if (Directory.Exists(System.IO.Path.GetDirectoryName(d.Path))) Process.Start("explorer.exe", "\"" + System.IO.Path.GetDirectoryName(d.Path) + "\"");
						break;
					case "cancel":
						if (d.Op != null) d.Op.Cancel();
						break;
					case "pause":
						if (d.Op != null) { d.Op.Pause(); d.State = "paused"; }
						break;
					case "resume":
						if (d.Op != null && d.Op.CanResume) { d.Op.Resume(); d.State = "progress"; }
						break;
					case "retry":
						if (d.Url != "" && App.LastActive != null) App.LastActive.AddTab(d.Url, false, -1);
						Items.Remove(d);
						break;
					case "remove":
						if (d.State == "progress" && d.Op != null) d.Op.Cancel();
						Items.Remove(d);
						break;
					case "clear":
						Items.RemoveAll(delegate(Download x) { return x.State != "progress" && x.State != "paused"; });
						break;
				}
			}
			catch { }
			saveDirty = true;
			Push();
		}
	}

	// --- Web apps: a site in its own window, wearing Oazy's look -------------------------
	// The site does all the work; Oazy adds a style sheet and a script (ui/apps)
	// that only restyle and rearrange what's there. The script finds its way
	// around the page by what things are (the prompt box, the media) rather
	// than by Google's class names, and if it can't, the site shows as it is.

	class WebAppDef
	{
		public string Id, Name, Url, Script, Style;
		public string[] Hosts;
		public Color A, B;
		// A small window of its own for signing in (SignInDef), not an app you keep.
		public bool Popup;
	}

	static class WebApps
	{
		public static readonly WebAppDef[] All =
		{
			new WebAppDef
			{
				Id = "flow", Name = "Flow", Url = "https://flow.google.com/u/0/",
				Hosts = new string[] { "flow.google.com", "flow.google", "labs.google" },
				Script = "flow.js", Style = "flow.css",
				A = Color.FromArgb(124, 108, 255), B = Color.FromArgb(38, 92, 214),
			},
		};

		// Signing in happens on Google's account pages, inside the app's window.
		static readonly string[] SignIn = { "accounts.google.com", "accounts.youtube.com", "gds.google.com" };
		// Other sites' sign-in pages, which get the same small Oazy window when a
		// site opens them as a popup ("Sign in with ...").
		static readonly string[] OtherSignIn = { "login.microsoftonline.com", "login.live.com", "appleid.apple.com", "discord.com", "www.facebook.com", "api.twitter.com", "x.com" };

		// The small Oazy window that sign-ins open in: Oazy's own Google sign-in
		// (SignInJob), and the popups sites open to sign you in. It wears a light
		// look (ui/apps/signin.*) on Google's account pages, which go dark to match.
		public static readonly WebAppDef SignInDef = new WebAppDef
		{
			Id = "signin", Name = "Sign in", Url = "",
			Hosts = SignIn, Script = "signin.js", Style = "signin.css", Popup = true,
			A = Color.FromArgb(56, 214, 196), B = Color.FromArgb(24, 120, 150),
		};

		public static bool IsSignIn(string url)
		{
			return HostIn(App.HostOf(url), SignIn);
		}

		// Whether a window a page opens is a sign-in popup (rather than a link
		// meant for a tab): a sign-in page, or anything opened with a size, the
		// way sites open "Sign in with Google" (often via a page of their own
		// that forwards to Google).
		public static bool WantsPopup(CoreWebView2NewWindowRequestedEventArgs e)
		{
			string url = e.Uri ?? "";
			if (HostIn(App.HostOf(url), SignIn)) return true;
			string host = App.HostOf(url);
			if (HostIn(host, OtherSignIn) && (url.Contains("oauth") || url.Contains("login") || url.Contains("authorize") || url.Contains("auth"))) return true;
			if (url.StartsWith("https://github.com/login", StringComparison.OrdinalIgnoreCase)) return true;
			try { return e.WindowFeatures != null && e.WindowFeatures.HasSize && (url == "" || url.StartsWith("about:") || url.StartsWith("http")); }
			catch { return false; }
		}

		public static WebAppDef Find(string id)
		{
			foreach (WebAppDef a in All) if (a.Id == id) return a;
			return null;
		}

		static bool HostIn(string host, string[] list)
		{
			foreach (string h in list) if (host == h || host.EndsWith("." + h)) return true;
			return false;
		}

		public static bool Owns(WebAppDef a, string url)
		{
			return HostIn(App.HostOf(url), a.Hosts);
		}

		// Whether a page belongs in the app's window (else the browser opens it).
		public static bool Stays(WebAppDef a, string url)
		{
			if (string.IsNullOrEmpty(url) || url.StartsWith("about:") || url.StartsWith("blob:") || url.StartsWith("data:")) return true;
			string host = App.HostOf(url);
			return HostIn(host, a.Hosts) || HostIn(host, SignIn);
		}

		static string Read(string name)
		{
			try { return File.ReadAllText(Path.Combine(App.Ui, "apps", name), Encoding.UTF8); } catch { return ""; }
		}

		// Oazy's typeface for the injected look, inlined: the site's page can't
		// fetch it from Oazy's own host. If its policy blocks data: fonts, the
		// style sheet falls back to Segoe UI.
		static string fontFace;
		static string FontFace()
		{
			if (fontFace != null) return fontFace;
			try
			{
				byte[] b = File.ReadAllBytes(Path.Combine(App.Ui, "fonts", "Geist-Variable.woff2"));
				fontFace = "@font-face{font-family:\"Oazy Geist\";font-weight:100 900;font-style:normal;src:url(data:font/woff2;base64," + Convert.ToBase64String(b) + ") format(\"woff2\")}\n";
			}
			catch { fontFace = ""; }
			return fontFace;
		}

		// The script that goes into every document: the app's script, handed its
		// style sheet and settings, in a closure of its own.
		public static string Bootstrap(WebAppDef a, bool on, string accent, bool test)
		{
			string config = Json.S.Serialize(Json.Obj("id", a.Id, "hosts", a.Hosts, "on", on, "accent", accent, "test", test, "css", FontFace() + Read(a.Style)));
			return "(function () {\n'use strict';\nconst OAZY = " + config + ";\n" + Read(a.Script) + "\n})();";
		}

		// The window's own icon (Alt+Tab, Windows' taskbar): a glass tile with a spark.
		public static Icon MakeIcon(WebAppDef a)
		{
			using (Bitmap bmp = new Bitmap(64, 64))
			{
				using (Graphics g = Graphics.FromImage(bmp))
				{
					g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
					using (System.Drawing.Drawing2D.GraphicsPath tile = Rounded(new RectangleF(3, 3, 58, 58), 16))
					using (System.Drawing.Drawing2D.LinearGradientBrush fill = new System.Drawing.Drawing2D.LinearGradientBrush(new PointF(0, 3), new PointF(0, 61), a.A, a.B))
						g.FillPath(fill, tile);
					PointF[] star = new PointF[8];
					for (int i = 0; i < 8; i++)
					{
						double ang = Math.PI / 4 * i - Math.PI / 2;
						float r = i % 2 == 0 ? 20f : 6.5f;
						star[i] = new PointF(32 + (float)Math.Cos(ang) * r, 32 + (float)Math.Sin(ang) * r);
					}
					using (SolidBrush white = new SolidBrush(Color.White)) g.FillPolygon(white, star);
				}
				return Icon.FromHandle(bmp.GetHicon());
			}
		}

		static System.Drawing.Drawing2D.GraphicsPath Rounded(RectangleF r, float rad)
		{
			System.Drawing.Drawing2D.GraphicsPath p = new System.Drawing.Drawing2D.GraphicsPath();
			float d = rad * 2;
			p.AddArc(r.Left, r.Top, d, d, 180, 90);
			p.AddArc(r.Right - d, r.Top, d, d, 270, 90);
			p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
			p.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
			p.CloseFigure();
			return p;
		}
	}

	// --- Signing in to Oazy with Google ----------------------------------------------
	// Oazy (Settings, Start) asks for this with --signin <email> --result <file>.
	// Google's own pages do the signing in, in a small Oazy window; the email
	// (picked from your Chrome accounts in Oazy) is filled in for you. Every web
	// page in Oazy shares this profile, so once it's done the browser, Flow and
	// any other web app are signed in too. Then the account (name, email, photo)
	// is read from Google the way Chrome itself does (ListAccounts, with this
	// profile's cookies) and written to the result file for Oazy's profile.
	// Nothing about your password ever passes through Oazy.
	//
	// --signout does the reverse: Google's sign-out page, then this profile's
	// Google cookies cleared, so nothing in Oazy stays signed in.

	class SignInJob
	{
		public const string DoneUrl = "https://oazy.example/signin-done.html";
		// Where Google sends you once you're in; reaching it means it worked.
		const string Landing = "https://myaccount.google.com/?utm_source=oazy";
		public readonly bool SignOut;
		public readonly string Hint, Result;
		public bool Finished;
		bool loggedOut;

		public SignInJob(bool signOut, string hint, string result)
		{
			SignOut = signOut;
			Hint = hint ?? "";
			Result = result ?? "";
		}

		public string StartUrl()
		{
			if (SignOut) return "https://accounts.google.com/Logout?hl=" + Lang();
			string cont = Uri.EscapeDataString(Landing);
			if (Hint != "") return "https://accounts.google.com/AccountChooser?Email=" + Uri.EscapeDataString(Hint) + "&continue=" + cont + "&hl=" + Lang();
			return "https://accounts.google.com/ServiceLogin?continue=" + cont + "&hl=" + Lang();
		}

		static string Lang()
		{
			try { return Uri.EscapeDataString(System.Globalization.CultureInfo.CurrentUICulture.Name); } catch { return "en"; }
		}

		// Called as the window's page starts going somewhere. True when it's handled.
		public bool Navigating(BrowserWindow w, Tab t, CoreWebView2NavigationStartingEventArgs e)
		{
			if (Finished || SignOut) return false;
			if (App.HostOf(e.Uri) != "myaccount.google.com") return false;
			// Signed in: Google's cookies are set by now. Stay put and look the account up.
			e.Cancel = true;
			Finish(w, t);
			return true;
		}

		public void Navigated(BrowserWindow w, Tab t, bool ok)
		{
			if (Finished || !SignOut || loggedOut) return;
			if (!WebApps.IsSignIn(t.Url) && !t.Url.StartsWith("https://www.google.")) return;
			loggedOut = true;
			FinishSignOut(w, t);
		}

		async void Finish(BrowserWindow w, Tab t)
		{
			Finished = true;
			Dictionary<string, object> acc = null;
			try { acc = await GoogleAccount(t.W, Hint); } catch { }
			if (acc == null) acc = Json.Obj("email", Hint, "name", "", "photo", "");
			acc["ok"] = true;
			Write(acc);
			Dictionary<string, object> page = new Dictionary<string, object>(acc);
			page["accent"] = App.Accent;
			if (App.Test != null) page["test"] = true;
			w.ShowPage(DoneUrl + "#" + Uri.EscapeDataString(Json.S.Serialize(page)));
		}

		async void FinishSignOut(BrowserWindow w, Tab t)
		{
			Finished = true;
			try
			{
				// Google's page signs you out on Google's side; clearing the cookies
				// makes sure nothing in Oazy holds on to a session.
				List<CoreWebView2Cookie> all = await t.W.CookieManager.GetCookiesAsync(null);
				foreach (CoreWebView2Cookie c in all)
				{
					string d = (c.Domain ?? "").TrimStart('.').ToLowerInvariant();
					if (d == "google.com" || d.EndsWith(".google.com") || d.StartsWith("google.") || d.Contains(".google.") || d == "youtube.com" || d.EndsWith(".youtube.com"))
						t.W.CookieManager.DeleteCookie(c);
				}
			}
			catch { }
			Write(Json.Obj("ok", true, "signedOut", true));
			w.ShowPage(DoneUrl + "#" + Uri.EscapeDataString(Json.S.Serialize(Json.Obj("signedOut", true, "accent", App.Accent))));
		}

		// The window closed: if it wasn't done, Oazy hears that you closed it.
		public void Closed()
		{
			if (Finished) return;
			Finished = true;
			Write(Json.Obj("ok", false, "cancelled", true));
		}

		void Write(Dictionary<string, object> m)
		{
			if (Result == "") return;
			try
			{
				string tmp = Result + ".tmp";
				File.WriteAllText(tmp, Json.S.Serialize(m), new UTF8Encoding(false));
				if (File.Exists(Result)) File.Delete(Result);
				File.Move(tmp, Result);
			}
			catch { }
		}

		// The signed-in Google account (the one matching `hint`, else the first),
		// from Google's account list, as Chrome reads it: {name, email, photo}.
		public static async Task<Dictionary<string, object>> GoogleAccount(CoreWebView2 w, string hint)
		{
			if (w == null) return null;
			const string Url = "https://accounts.google.com/ListAccounts?gpsia=1&source=ChromiumBrowser&json=standard";
			List<CoreWebView2Cookie> cookies = await w.CookieManager.GetCookiesAsync(Url);
			StringBuilder jar = new StringBuilder();
			foreach (CoreWebView2Cookie c in cookies)
			{
				if (jar.Length > 0) jar.Append("; ");
				jar.Append(c.Name).Append('=').Append(c.Value);
			}
			string ua = "";
			try { ua = w.Settings.UserAgent; } catch { }
			string header = jar.ToString();
			string text = await Task.Run<string>(new Func<string>(delegate
			{
				string r = Fetch(Url, header, ua, true);
				if (Parse(r, hint) == null) r = Fetch(Url, header, ua, false);
				return r;
			}));
			return Parse(text, hint);
		}

		static string Fetch(string url, string cookies, string ua, bool post)
		{
			try
			{
				HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
				req.Method = post ? "POST" : "GET";
				req.Timeout = 15000;
				req.AllowAutoRedirect = false;
				if (ua != "") req.UserAgent = ua;
				req.Headers["Cookie"] = cookies;
				if (post)
				{
					byte[] body = Encoding.ASCII.GetBytes(" ");
					req.ContentType = "application/x-www-form-urlencoded";
					req.ContentLength = body.Length;
					using (Stream s = req.GetRequestStream()) s.Write(body, 0, body.Length);
				}
				using (HttpWebResponse res = (HttpWebResponse)req.GetResponse())
				using (StreamReader r = new StreamReader(res.GetResponseStream(), Encoding.UTF8))
					return r.ReadToEnd();
			}
			catch { return ""; }
		}

		// ["gaia.l.a.r", [["gaia.l.a", 1, "Name", "email", "photo url", ...], ...]]
		public static Dictionary<string, object> Parse(string text, string hint)
		{
			if (string.IsNullOrEmpty(text)) return null;
			int start = text.IndexOf('[');
			if (start < 0) return null;
			object[] root;
			try { root = Json.S.DeserializeObject(text.Substring(start)) as object[]; } catch { return null; }
			if (root == null || root.Length < 2 || !(root[1] is object[])) return null;
			Dictionary<string, object> first = null;
			foreach (object o in (object[])root[1])
			{
				object[] a = o as object[];
				if (a == null || a.Length < 4) continue;
				string name = a[2] as string ?? "", email = a[3] as string ?? "", photo = a.Length > 4 ? a[4] as string ?? "" : "";
				if (email.IndexOf('@') < 0) continue;
				// Accounts Google remembers but you've signed out of come last.
				bool signedOut = a.Length > 14 && a[14] != null && Convert.ToString(a[14]) == "1";
				Dictionary<string, object> acc = Json.Obj("name", name, "email", email, "photo", photo);
				if (hint != "" && email.Equals(hint, StringComparison.OrdinalIgnoreCase)) return acc;
				if (first == null && !signedOut) first = acc;
			}
			return first;
		}
	}

	// --- A tab ------------------------------------------------------------------------

	class Tab
	{
		static int nextId = 1;
		public readonly int Id = nextId++;
		public CoreWebView2Controller C;
		public CoreWebView2 W;
		public Task Ready;
		// Opened but never shown (restored sessions): nothing loads until you look.
		public string Pending;
		public string Url = "", Title = "", Icon = "";
		public bool Loading, Audio, Muted, Crashed, Transparent;
		public int Opener;
		public string ScriptId, SignInScriptId;
		// Google's account pages asked to draw dark (see BrowserWindow.SetDark).
		public bool Dark;

		public bool IsNtp
		{
			get
			{
				string u = W != null ? Url : (Pending ?? Url);
				return u == "" || u.StartsWith(App.NewTabUrl, StringComparison.OrdinalIgnoreCase);
			}
		}

		public string ShownUrl { get { return W != null ? Url : (Pending ?? Url); } }
	}

	// --- A browser window ------------------------------------------------------------------

	class BrowserWindow : Form
	{
		// A web app's window (WebApps) has a slim title bar instead of tabs and
		// an address bar, and Oazy's look laid over the site.
		public readonly WebAppDef WebApp;
		// Oazy's own sign-in, when this window is one (SignInJob).
		public SignInJob Job;
		bool look;
		bool IsPopup { get { return WebApp != null && WebApp.Popup; } }
		int ChromeDip { get { return WebApp != null ? 40 : 88; } }
		string ChromePage { get { return WebApp != null ? App.AppChromeUrl : App.ChromeUrl; } }
		const int WM_GETMINMAXINFO = 0x24, WM_NCCALCSIZE = 0x83, WM_NCHITTEST = 0x84, WM_DPICHANGED = 0x2E0, WM_MOVE = 0x3, WM_ACTIVATE = 0x6, WM_NCLBUTTONDOWN = 0xA1;
		const int HTCLIENT = 1, HTCAPTION = 2, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14;

		readonly Panel contentPanel = new Panel();
		CoreWebView2Controller chrome;
		IntPtr chromeHwnd;
		bool pageHidden, chromeTall;
		bool chromeReady, glass, overlay, fullscreen, findOpen, closing, nativeDrag;
		int extraDip;
		readonly List<object> outbox = new List<object>();
		public readonly List<Tab> Tabs = new List<Tab>();
		public Tab Active;
		bool preFullZoom;
		Rectangle preFullBounds;
		int snapCount;
		string suggestFor = "";
		readonly List<string> initialUrls;
		readonly int initialActive;

		public BrowserWindow(List<string> urls, int active, Rectangle? bounds, bool maximized, WebAppDef app)
		{
			WebApp = app;
			initialUrls = urls;
			initialActive = active;
			Text = app != null ? app.Name : App.Name;
			if (app != null) look = !Json.Bool(App.Prefs, "app_" + app.Id + "_plain");
			BackColor = Color.Black;
			FormBorderStyle = FormBorderStyle.Sizable;
			StartPosition = FormStartPosition.Manual;
			KeyPreview = false;
			try { Icon = app != null && !app.Popup ? WebApps.MakeIcon(app) : Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
			contentPanel.BackColor = Color.Black;
			Controls.Add(contentPanel);

			Rectangle work = Screen.FromPoint(Cursor.Position).WorkingArea;
			float scale = DpiScale(work);
			int w = (int)((app != null ? (app.Popup ? 480 : 1440) : 1320) * scale), h = (int)((app != null ? (app.Popup ? 700 : 900) : 860) * scale);
			w = Math.Min(w, work.Width - 40);
			h = Math.Min(h, work.Height - 40);
			Rectangle r = new Rectangle(work.Left + (work.Width - w) / 2, work.Top + (work.Height - h) / 2, w, h);
			if (bounds.HasValue && bounds.Value.Width > 300 && bounds.Value.Height > 200 && Screen.FromRectangle(bounds.Value).WorkingArea.IntersectsWith(bounds.Value))
				r = bounds.Value;
			else if (App.Windows.Count > 0 && app == null)
				r.Offset((int)(32 * scale * App.Windows.Count), (int)(32 * scale * App.Windows.Count));
			Bounds = r;
			if (maximized) StartMaximized(r);
			MinimumSize = app != null && app.Popup ? new Size((int)(360 * scale), (int)(420 * scale)) : new Size((int)(560 * scale), (int)(380 * scale));
		}

		static float DpiScale(Rectangle area)
		{
			using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) return Math.Max(1f, g.DpiX / 96f);
		}

		float Scale_ { get { try { return Native.GetDpiForWindow(Handle) / 96f; } catch { return 1f; } } }

		// --- Window frame ------------------------------------------------------------------
		// A resizable window with no caption: Windows still gives it snapping, the
		// shadow, rounded corners and side borders, and our chrome draws the rest.

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
			// Tells Oazy's shell this window draws its own title bar, so it leaves
			// the caption colour alone (it would show as a dark strip on the glass).
			Native.SetProp(Handle, "OazyGlass", new IntPtr(1));
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
			else
			{
				BackColor = Color.FromArgb(10, 18, 24);
				contentPanel.BackColor = BackColor;
			}
			Native.SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020);
		}

		protected override void OnShown(EventArgs e)
		{
			base.OnShown(e);
			ApplyLook();
			RefreshFrame();
			BeginInvoke((Action)delegate { RefreshFrame(); KickFrame(); });
			Init();
		}

		// Until the frame is recalculated once the window is on screen, DWM keeps
		// painting a dark caption strip across the top of the glass (behind the
		// tabs), even though the window has no title bar.
		void RefreshFrame()
		{
			int color = unchecked((int)0xFFFFFFFF); // DWMWA_COLOR_DEFAULT
			Native.DwmSetWindowAttribute(Handle, 35, ref color, 4);
			long style = Native.GetWindowLongPtr(Handle, -16).ToInt64() & ~0x00C00000L;
			Native.SetWindowLongPtr(Handle, -16, new IntPtr(style));
			Native.SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020);
		}

		int TopStrip { get { return fullscreen || Maximized ? 0 : Math.Max(1, (int)Math.Round(3 * Scale_)); } }

		protected override void WndProc(ref Message m)
		{
			switch (m.Msg)
			{
				case WM_NCCALCSIZE:
					if (m.WParam != IntPtr.Zero)
					{
						if (fullscreen) { m.Result = IntPtr.Zero; return; }
						Native.NCCALCSIZE_PARAMS p = (Native.NCCALCSIZE_PARAMS)Marshal.PtrToStructure(m.LParam, typeof(Native.NCCALCSIZE_PARAMS));
						Native.RECT whole = p.r0;
						int top = p.r0.Top;
						base.WndProc(ref m);
						p = (Native.NCCALCSIZE_PARAMS)Marshal.PtrToStructure(m.LParam, typeof(Native.NCCALCSIZE_PARAMS));
						// Maximized (by hand), no borders at all: the window is the work area.
						if (zoomed) p.r0 = whole;
						// Keep Windows' side and bottom borders (resizing, shadow), drop the title bar.
						p.r0.Top = top;
						if (Native.IsZoomed(m.HWnd))
						{
							// Maximised, the client is exactly the work area (the frame hangs off-screen).
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
					if (m.Result.ToInt32() == HTCLIENT && !fullscreen && !Maximized)
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
						// Without a caption Windows would maximise over the taskbar; keep to the
						// work area, with the frame hanging off the edges as usual.
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
					if (zoomed) Place(WorkArea);
					else Native.SetWindowPos(Handle, IntPtr.Zero, r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top, 0x0004 | 0x0010);
					DoLayout();
					m.Result = IntPtr.Zero;
					return;
				case 0x112: // WM_SYSCOMMAND: maximize, restore and move by hand
					{
						int sc = (int)(m.WParam.ToInt64() & 0xFFF0);
						bool mouse = (m.WParam.ToInt64() & 0xF) == HTCAPTION, iconic = Native.IsIconic(Handle);
						// A title double-click toggles; Win+Up only maximizes.
						if (sc == 0xF030 && !iconic) { SetMaximized(mouse ? !zoomed : true); return; }
						if (sc == 0xF120 && zoomed && !iconic) { SetMaximized(false); return; }
						// Dragging the title (the page's own drag regions) of a maximized window.
						if (sc == 0xF010 && mouse && zoomed) { WatchDrag(); return; }
					}
					break;
				case 0x1A: // WM_SETTINGCHANGE: the work area moved (taskbar)
					base.WndProc(ref m);
					if (zoomed && m.WParam.ToInt64() == 0x2F) Place(WorkArea);
					return;
				case WM_MOVE:
					base.WndProc(ref m);
					if (chrome != null) try { chrome.NotifyParentWindowPositionChanged(); } catch { }
					if (Active != null && Active.C != null) try { Active.C.NotifyParentWindowPositionChanged(); } catch { }
					return;
				case 0x86: // WM_NCACTIVATE
					// Activating repaints the caption DWM keeps for the window; -1 skips
					// that, so no dark title strip shows over the glass.
					m.LParam = new IntPtr(-1);
					base.WndProc(ref m);
					return;
				case WM_ACTIVATE:
					base.WndProc(ref m);
					// Activating lifts the window to the front too, so a click on the part of
					// it showing behind another window (a maximized one under a smaller one)
					// always brings it forward, whichever part of it took the click.
					if ((m.WParam.ToInt64() & 0xFFFF) != 0 && WindowState != FormWindowState.Minimized)
						Native.SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010 | 0x0200);
					bool on = (m.WParam.ToInt64() & 0xFFFF) != 0;
					if (on) App.LastActive = this;
					Post(Json.Obj("t", "active", "on", on));
					return;
			}
			base.WndProc(ref m);
		}

		// --- Maximized ---------------------------------------------------------------------
		// Oazy maximizes by hand: the window takes exactly the work area, flush on the
		// taskbar, and stays a normal window to Windows. A real maximized window got a
		// dark caption-high strip painted across its top by DWM and stopped short of the
		// taskbar. Every way in (the button, a title double-click, Win+Up, snapping to the
		// top, opening maximized) and out (the button, dragging the title, Win+arrows)
		// comes through here.
		bool zoomed, zooming;
		Rectangle unzoomed, lastNormal;

		public bool Maximized { get { return zoomed; } }

		Rectangle WorkArea { get { return Screen.FromHandle(Handle).WorkingArea; } }

		// Opening maximized: the window is made at the work area straight away, so it
		// never shows at its own size first.
		void StartMaximized(Rectangle normal)
		{
			unzoomed = normal;
			zoomed = true;
			Bounds = Screen.FromRectangle(normal).WorkingArea;
		}

		// Moves or sizes the window without it counting as the user's doing.
		void Place(Rectangle r)
		{
			bool was = zooming;
			zooming = true;
			Bounds = r;
			zooming = was;
		}

		// Square and without Windows' 1px outline while it fills the screen. The
		// "OazyMax" mark tells Oazy's taskbar to dock under it as it would under a
		// maximized window.
		void ApplyLook()
		{
			if (!IsHandleCreated) return;
			Native.SetProp(Handle, "OazyMax", new IntPtr(zoomed ? 1 : 0));
			int corner = zoomed ? 1 : 2, border = zoomed ? unchecked((int)0xFFFFFFFE) : unchecked((int)0xFFFFFFFF);
			Native.DwmSetWindowAttribute(Handle, 33, ref corner, 4);
			Native.DwmSetWindowAttribute(Handle, 34, ref border, 4);
		}

		public void SetMaximized(bool on)
		{
			if (on == zoomed || !IsHandleCreated) return;
			bool was = zooming;
			zooming = true;
			Rectangle from = WindowState == FormWindowState.Normal ? Bounds : lastNormal;
			if (WindowState != FormWindowState.Normal) WindowState = FormWindowState.Normal;
			if (on)
			{
				unzoomed = from.Width > 0 ? from : Bounds;
				zoomed = true;
				ApplyLook();
				Bounds = WorkArea;
			}
			else
			{
				zoomed = false;
				ApplyLook();
				Bounds = unzoomed;
			}
			zooming = was;
			KickFrame();
			DoLayout();
			PostWinState();
		}

		// Windows moved or sized a maximized window itself (Win+arrows, a snap layout):
		// it isn't maximized any more.
		void CheckZoom()
		{
			if (!zoomed || zooming || !IsHandleCreated || WindowState != FormWindowState.Normal || Bounds == WorkArea) return;
			zoomed = false;
			ApplyLook();
			KickFrame();
			DoLayout();
			PostWinState();
		}

		// DWM can keep a stale frame (the dark caption-high strip) until the frame is
		// recalculated with a real size change: a 1px nudge and back does that.
		void KickFrame()
		{
			if (!IsHandleCreated || WindowState == FormWindowState.Minimized) return;
			bool was = zooming;
			zooming = true;
			Rectangle b = Bounds;
			const uint flags = 0x0004 | 0x0010 | 0x0020 | 0x0200; // no z-order, no activate, frame changed
			Native.SetWindowPos(Handle, IntPtr.Zero, b.X, b.Y, b.Width, b.Height + 1, flags);
			Native.SetWindowPos(Handle, IntPtr.Zero, b.X, b.Y, b.Width, b.Height, flags);
			zooming = was;
		}

		// The last size and place as a plain window: a real maximize (snap) has
		// already left it by the time Oazy takes over.
		void NoteNormal()
		{
			if (IsHandleCreated && WindowState == FormWindowState.Normal && !zoomed && !zooming && !fullscreen) lastNormal = Bounds;
		}

		protected override void OnLocationChanged(EventArgs e)
		{
			base.OnLocationChanged(e);
			CheckZoom();
			NoteNormal();
		}

		// Where the window goes back to, for saving.
		Rectangle NormalBounds { get { return zoomed ? unzoomed : (WindowState == FormWindowState.Normal ? Bounds : RestoreBounds); } }

		// Dragging the title of a maximized window brings it back to its own size
		// under the pointer once the pointer moves, and keeps dragging; a click or
		// double-click leaves it as it is.
		System.Windows.Forms.Timer dragWatch;

		void BeginDrag()
		{
			if (zoomed) { WatchDrag(); return; }
			Native.ReleaseCapture();
			Native.SendMessage(Handle, WM_NCLBUTTONDOWN, new IntPtr(HTCAPTION), IntPtr.Zero);
		}

		void WatchDrag()
		{
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
					Place(new Rectangle(c.X - (int)(r.Width * at), c.Y - (from.Y - full.Top), r.Width, r.Height));
					Native.ReleaseCapture();
					Native.SendMessage(Handle, WM_NCLBUTTONDOWN, new IntPtr(HTCAPTION), IntPtr.Zero);
				};
			}
			dragWatch.Tag = Cursor.Position;
			dragWatch.Start();
		}

		// Recalculate the frame on every state change, in case DWM brings its
		// caption strip back.
		FormWindowState shownState = FormWindowState.Normal;

		protected override void OnResize(EventArgs e)
		{
			base.OnResize(e);
			bool min = WindowState == FormWindowState.Minimized;
			CheckZoom();
			NoteNormal();
			if (WindowState == FormWindowState.Maximized && !zooming && IsHandleCreated)
				BeginInvoke((Action)delegate { SetMaximized(true); });
			if (WindowState != shownState && IsHandleCreated)
			{
				shownState = WindowState;
				if (!min) BeginInvoke((Action)delegate { RefreshFrame(); KickFrame(); });
			}
			if (chrome != null) try { chrome.IsVisible = !min; } catch { }
			if (Active != null && Active.C != null) try { Active.C.IsVisible = !min && !pageHidden; } catch { }
			if (!min) DoLayout();
			PostWinState();
			App.SessionChanged();
		}

		protected override void OnMove(EventArgs e)
		{
			base.OnMove(e);
			App.SessionChanged();
		}

		HashSet<IntPtr> Children()
		{
			HashSet<IntPtr> set = new HashSet<IntPtr>();
			for (IntPtr h = Native.GetWindow(Handle, 5); h != IntPtr.Zero; h = Native.GetWindow(h, 2)) set.Add(h);
			return set;
		}

		void PostWinState()
		{
			Post(Json.Obj("t", "win", "max", Maximized, "full", fullscreen));
		}

		void DoLayout()
		{
			if (!IsHandleCreated || WindowState == FormWindowState.Minimized) return;
			Size cs = ClientSize;
			int top = TopStrip;
			int ch = fullscreen ? 0 : (int)Math.Round((ChromeDip + extraDip) * Scale_);
			ch = Math.Min(ch, cs.Height - top);
			contentPanel.Bounds = new Rectangle(0, top + ch, cs.Width, Math.Max(0, cs.Height - top - ch));
			if (chrome != null)
			{
				try { chrome.Bounds = chromeTall ? new Rectangle(0, top, cs.Width, cs.Height - top) : new Rectangle(0, top, cs.Width, ch); } catch { }
				// Over the page while a panel is open (the page hides under its still).
				if (chromeTall && chromeHwnd != IntPtr.Zero) Native.SetWindowPos(chromeHwnd, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
			}
			if (Active != null && Active.C != null && WindowState != FormWindowState.Minimized)
				try { Active.C.IsVisible = !pageHidden; } catch { }
			foreach (Tab t in Tabs)
				if (t.C != null) try { t.C.Bounds = new Rectangle(Point.Empty, contentPanel.ClientSize); } catch { }
		}

		public void BringUp()
		{
			if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
			Native.SetForegroundWindow(Handle);
			Activate();
		}

		void SetFullscreen(bool on)
		{
			if (on == fullscreen) return;
			if (on)
			{
				preFullZoom = zoomed;
				if (WindowState != FormWindowState.Normal) WindowState = FormWindowState.Normal;
				zoomed = false;
				preFullBounds = Bounds;
				fullscreen = true;
				int square = 1, none = unchecked((int)0xFFFFFFFE);
				Native.DwmSetWindowAttribute(Handle, 33, ref square, 4);
				Native.DwmSetWindowAttribute(Handle, 34, ref none, 4);
				Bounds = Screen.FromHandle(Handle).Bounds;
			}
			else
			{
				fullscreen = false;
				int round = preFullZoom ? 1 : 2, border = preFullZoom ? unchecked((int)0xFFFFFFFE) : unchecked((int)0xFFFFFFFF);
				Native.DwmSetWindowAttribute(Handle, 33, ref round, 4);
				Native.DwmSetWindowAttribute(Handle, 34, ref border, 4);
				Bounds = preFullBounds;
				zoomed = preFullZoom;
			}
			Native.SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020);
			DoLayout();
			PostWinState();
		}

		protected override void OnFormClosing(FormClosingEventArgs e)
		{
			closing = true;
			// The last browser window's tabs are the session to come back to.
			int browsers = 0;
			foreach (BrowserWindow x in App.Windows) if (x.WebApp == null) browsers++;
			if (WebApp != null || browsers == 1) App.SessionChanged();
			App.SaveNow();
			base.OnFormClosing(e);
		}

		protected override void OnFormClosed(FormClosedEventArgs e)
		{
			if (Job != null) Job.Closed();
			foreach (Tab t in Tabs) if (t.C != null) try { t.C.Close(); } catch { }
			if (chrome != null) try { chrome.Close(); } catch { }
			base.OnFormClosed(e);
		}

		public object SessionInfo()
		{
			List<object> urls = new List<object>();
			foreach (Tab t in Tabs) urls.Add(t.IsNtp ? "" : t.ShownUrl);
			Rectangle b = fullscreen ? (preFullZoom ? unzoomed : preFullBounds) : NormalBounds;
			return Json.Obj("tabs", urls.ToArray(), "active", Math.Max(0, Tabs.IndexOf(Active)),
				"bounds", new object[] { b.X, b.Y, b.Width, b.Height }, "max", fullscreen ? preFullZoom : zoomed);
		}

		// --- Chrome (tabs, address bar, panels) --------------------------------------------------

		async void Init()
		{
			try
			{
				// The chrome sits straight on the window (not in a panel) so its
				// app-region drag areas move the window itself.
				HashSet<IntPtr> before = Children();
				chrome = await App.Env.CreateCoreWebView2ControllerAsync(Handle);
				foreach (IntPtr h in Children()) if (!before.Contains(h)) chromeHwnd = h;
			}
			catch (Exception ex)
			{
				MessageBox.Show(this, "Couldn't create the browser window.\n\n" + ex.Message, App.Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
				Close();
				return;
			}
			if (closing) { chrome.Close(); return; }
			chrome.DefaultBackgroundColor = Color.Transparent;
			CoreWebView2 cw = chrome.CoreWebView2;
			CoreWebView2Settings s = cw.Settings;
			s.AreDefaultContextMenusEnabled = false;
			s.AreDefaultScriptDialogsEnabled = true;
			s.IsStatusBarEnabled = false;
			s.IsZoomControlEnabled = false;
			s.AreDevToolsEnabled = Environment.GetEnvironmentVariable("OAZY_BROWSER_DEVTOOLS") == "1";
			try { s.AreBrowserAcceleratorKeysEnabled = false; } catch { }
			try { s.IsPinchZoomEnabled = false; } catch { }
			try { s.IsSwipeNavigationEnabled = false; } catch { }
			try { s.IsGeneralAutofillEnabled = false; s.IsPasswordAutosaveEnabled = false; } catch { }
			nativeDrag = false;
			try { s.IsNonClientRegionSupportEnabled = true; nativeDrag = true; } catch { }
			cw.SetVirtualHostNameToFolderMapping(App.UiHost, App.Ui, CoreWebView2HostResourceAccessKind.Allow);
			cw.SetVirtualHostNameToFolderMapping(App.MediaHost, App.Media, CoreWebView2HostResourceAccessKind.Allow);
			cw.WebMessageReceived += OnChromeMessage;
			cw.NewWindowRequested += delegate(object o, CoreWebView2NewWindowRequestedEventArgs e) { e.Handled = true; AddTab(e.Uri, true, -1); };
			cw.NavigationStarting += delegate(object o, CoreWebView2NavigationStartingEventArgs e)
			{
				// The chrome never leaves its own page.
				if (!e.Uri.StartsWith(ChromePage)) e.Cancel = true;
			};
			chrome.AcceleratorKeyPressed += OnAccelerator;
			DoLayout();
			cw.Navigate(ChromePage);

			for (int i = 0; i < initialUrls.Count; i++)
			{
				string u = initialUrls[i];
				AddTab(u == "" ? App.NewTabUrl : App.FixUrl(u), i == Math.Min(initialActive, initialUrls.Count - 1), -1);
			}
			// A site's popup gets its page from the site (AdoptPopup).
			if (Tabs.Count == 0 && !IsPopup) AddTab(App.NewTabUrl, true, -1);
		}

		public void Post(object msg)
		{
			if (!chromeReady || chrome == null)
			{
				if (outbox.Count < 200) outbox.Add(msg);
				return;
			}
			try { chrome.CoreWebView2.PostWebMessageAsJson(Json.S.Serialize(msg)); } catch { }
		}

		void OnChromeMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
		{
			Dictionary<string, object> m;
			try { m = Json.S.DeserializeObject(e.WebMessageAsJson) as Dictionary<string, object>; } catch { return; }
			if (m == null) return;
			string t = Json.Str(m, "t");
			Tab tab = TabById(Json.Int(m, "id"));
			switch (t)
			{
				case "ready":
					chromeReady = true;
					Post(Json.Obj("t", "init", "glass", glass, "accent", App.Accent, "engine", App.Engine(), "engines", EngineList(),
						"restore", !Json.Bool(App.Prefs, "no_restore"), "version", App.Version, "nativeDrag", nativeDrag,
						"app", WebApp != null ? WebApp.Name : "", "look", look, "popup", IsPopup));
					foreach (object o in outbox) Post(o);
					outbox.Clear();
					PostWinState();
					PushTabs();
					PushNav();
					Post(Downloads.Snapshot());
					if (Active != null && Active.IsNtp) FocusOmnibox();
					if (App.Test != null) App.Test.ChromeReady(this);
					break;
				case "newTab": AddTab(App.NewTabUrl, true, -1); break;
				case "closeTab": if (tab != null) CloseTab(tab); break;
				case "activate": if (tab != null) Activate(tab); break;
				case "moveTab":
					if (tab != null)
					{
						int to = Math.Max(0, Math.Min(Tabs.Count - 1, Json.Int(m, "to")));
						Tabs.Remove(tab);
						Tabs.Insert(to, tab);
						PushTabs();
						App.SessionChanged();
					}
					break;
				case "tabMenu": TabCommand(tab, Json.Str(m, "cmd")); break;
				case "navigate":
					{
						string text = Json.Str(m, "text");
						string url = Json.Str(m, "url") != "" ? Json.Str(m, "url") : App.FixUrl(text);
						if (Json.Bool(m, "newTab")) AddTab(url, true, -1);
						else Navigate(Active, url);
					}
					break;
				case "suggest": Suggest(Json.Str(m, "q")); break;
				case "cmd": Command(Json.Str(m, "cmd"), m); break;
				case "snapshot": Snapshot(); break;
				case "overlay": SetOverlay(Json.Bool(m, "on")); break;
				case "layout":
					extraDip = Math.Max(0, Math.Min(200, Json.Int(m, "extra")));
					DoLayout();
					break;
				case "drag":
					BeginDrag();
					break;
				case "download": Downloads.Act(Json.Int(m, "dl"), Json.Str(m, "action")); break;
				case "history":
					Post(Json.Obj("t", "history", "items", History.List(Json.Str(m, "q"), 300)));
					break;
				case "historyRemove":
					History.Remove(Json.Str(m, "url"));
					Post(Json.Obj("t", "history", "items", History.List(Json.Str(m, "q"), 300)));
					App.BroadcastNtp();
					break;
				case "find": Find(m); break;
				case "focusContent": FocusContent(); break;
				case "look": SetLook(Json.Bool(m, "on")); break;
				case "openInBrowser": if (Active != null) App.OpenInBrowser(Active.ShownUrl); break;
				case "test":
					if (App.Test != null) App.Test.FromChrome(this, m);
					break;
			}
		}

		static object[] EngineList()
		{
			List<object> list = new List<object>();
			foreach (string[] e in App.Engines) list.Add(Json.Obj("id", e[0], "name", e[1]));
			return list.ToArray();
		}

		void FocusOmnibox()
		{
			if (chrome == null) return;
			try { chrome.MoveFocus(CoreWebView2MoveFocusReason.Programmatic); } catch { }
			Post(Json.Obj("t", "focusOmnibox"));
		}

		void FocusContent()
		{
			if (Active == null || Active.C == null) return;
			try { Active.C.MoveFocus(CoreWebView2MoveFocusReason.Programmatic); } catch { }
		}

		// --- Tabs ---------------------------------------------------------------------------

		Tab TabById(int id)
		{
			foreach (Tab t in Tabs) if (t.Id == id) return t;
			return null;
		}

		public Tab AddTab(string url, bool activate, int index)
		{
			Tab t = new Tab { Pending = string.IsNullOrEmpty(url) ? App.NewTabUrl : url };
			t.Url = t.Pending;
			if (Active != null) t.Opener = Active.Id;
			if (index < 0 || index > Tabs.Count) index = Tabs.Count;
			Tabs.Insert(index, t);
			if (activate) Activate(t);
			else PushTabs();
			App.SessionChanged();
			return t;
		}

		Task Ensure(Tab t)
		{
			if (t.Ready == null) t.Ready = Create(t);
			return t.Ready;
		}

		async Task Create(Tab t)
		{
			CoreWebView2Controller c;
			try { c = await App.Env.CreateCoreWebView2ControllerAsync(contentPanel.Handle); }
			catch (Exception) { t.Crashed = true; PushTabs(); return; }
			if (closing || !Tabs.Contains(t)) { c.Close(); return; }
			t.C = c;
			t.W = c.CoreWebView2;
			c.Bounds = new Rectangle(Point.Empty, contentPanel.ClientSize);
			c.IsVisible = t == Active && WindowState != FormWindowState.Minimized && !pageHidden;
			SetupTab(t);
			SetTransparent(t, Glassy(t.ShownUrl));
			if (WebApp != null) await InjectApp(t);
			if (WebApp != null && !IsPopup) await InjectSignIn(t);
			if (t.Pending != null)
			{
				string url = t.Pending;
				t.Pending = null;
				Navigate(t, url);
			}
		}

		void SetupTab(Tab t)
		{
			CoreWebView2 w = t.W;
			CoreWebView2Controller c = t.C;
			w.Settings.IsStatusBarEnabled = true;
			w.Settings.AreDevToolsEnabled = true;
			w.SetVirtualHostNameToFolderMapping(App.UiHost, App.Ui, CoreWebView2HostResourceAccessKind.DenyCors);
			// The self-test can't sign in to a web app; it gets a stand-in page on the app's own host.
			if (WebApp != null && !IsPopup && App.Test != null)
				w.SetVirtualHostNameToFolderMapping(WebApp.Hosts[0], Path.Combine(App.Ui, "apps"), CoreWebView2HostResourceAccessKind.Allow);
			c.AcceleratorKeyPressed += OnAccelerator;
			c.ZoomFactorChanged += delegate { if (t == Active) PushNav(); };
			c.GotFocus += delegate { if (t == Active) Post(Json.Obj("t", "contentFocus")); };
			w.SourceChanged += delegate
			{
				t.Url = w.Source;
				SetTransparent(t, Glassy(t.Url));
				if (t == Active) PushNav();
				PushTabs();
				App.SessionChanged();
			};
			w.DocumentTitleChanged += delegate
			{
				t.Title = w.DocumentTitle;
				History.Title(w.Source, t.Title);
				if (t == Active) UpdateTitle();
				PushTabs();
			};
			w.NavigationStarting += delegate(object o, CoreWebView2NavigationStartingEventArgs e)
			{
				t.Loading = true;
				t.Crashed = false;
				SetTransparent(t, Glassy(e.Uri));
				SetDark(t, WebApp != null && look && WebApps.IsSignIn(e.Uri));
				if (Job != null && Job.Navigating(this, t, e)) return;
				// Links out of a web app open in the browser proper.
				if (WebApp != null && !IsPopup && e.IsUserInitiated && !WebApps.Stays(WebApp, e.Uri) && e.Uri.StartsWith("http", StringComparison.OrdinalIgnoreCase))
				{
					e.Cancel = true;
					t.Loading = false;
					App.OpenInBrowser(e.Uri);
					return;
				}
				if (t == Active) PushNav();
				PushTabs();
			};
			w.NavigationCompleted += delegate(object o, CoreWebView2NavigationCompletedEventArgs e)
			{
				t.Loading = false;
				if (e.IsSuccess && !IsPopup) History.Visit(w.Source, w.DocumentTitle);
				if (t.Dark) SetDark(t, true, true);
				if (Job != null) Job.Navigated(this, t, e.IsSuccess);
				if (t == Active) PushNav();
				PushTabs();
				if (App.Test != null) App.Test.Navigated(this, t, e.IsSuccess);
			};
			w.HistoryChanged += delegate { if (t == Active) PushNav(); };
			w.WindowCloseRequested += delegate { CloseTab(t); };
			w.NewWindowRequested += async delegate(object o, CoreWebView2NewWindowRequestedEventArgs e)
			{
				// "Sign in with ..." popups get a small Oazy window of their own,
				// still connected to the page that opened them.
				if (!IsPopup && WebApps.WantsPopup(e))
				{
					CoreWebView2Deferral pd = e.GetDeferral();
					try
					{
						BrowserWindow pw = App.OpenWindow(new List<string>(), 0, null, false, WebApps.SignInDef, this, null);
						CoreWebView2 nw = await pw.AdoptPopup(e.Uri ?? "");
						if (nw != null)
						{
							e.NewWindow = nw;
							e.Handled = true;
						}
						else pw.Close();
					}
					catch { }
					finally { pd.Complete(); }
					return;
				}
				// A web app's links to other sites open in the browser proper.
				if (WebApp != null && !WebApps.Stays(WebApp, e.Uri))
				{
					e.Handled = true;
					App.OpenInBrowser(e.Uri);
					return;
				}
				// Popups and target=_blank links open as tabs next to this one, still
				// connected to their opener (sign-in popups need that).
				CoreWebView2Deferral def = e.GetDeferral();
				try
				{
					Tab nt = new Tab { Opener = t.Id, Url = e.Uri ?? "" };
					Tabs.Insert(Math.Min(Tabs.Count, Tabs.IndexOf(t) + 1 + CountOpened(t)), nt);
					Activate(nt);
					await Ensure(nt);
					if (nt.W != null)
					{
						e.NewWindow = nt.W;
						e.Handled = true;
					}
				}
				catch { }
				finally { def.Complete(); }
			};
			w.ContainsFullScreenElementChanged += delegate { if (t == Active) SetFullscreen(w.ContainsFullScreenElement); };
			w.ProcessFailed += delegate(object o, CoreWebView2ProcessFailedEventArgs e)
			{
				if (e.ProcessFailedKind == CoreWebView2ProcessFailedKind.RenderProcessExited || e.ProcessFailedKind == CoreWebView2ProcessFailedKind.RenderProcessUnresponsive)
				{
					t.Crashed = true;
					t.Loading = false;
					PushTabs();
					if (t == Active) PushNav();
				}
			};
			w.WebMessageReceived += delegate(object o, CoreWebView2WebMessageReceivedEventArgs e)
			{
				// A web app's script reports how its look went (nothing it says is acted on
				// beyond showing it).
				if (WebApp != null && !IsPopup && WebApps.Owns(WebApp, e.Source)) { OnAppMessage(t, e.WebMessageAsJson); return; }
				// Only Oazy's own pages (the new tab page) may talk to the browser.
				if (!e.Source.StartsWith("https://" + App.UiHost + "/", StringComparison.OrdinalIgnoreCase)) return;
				OnPageMessage(t, e.WebMessageAsJson);
			};
			try
			{
				w.DownloadStarting += delegate(object o, CoreWebView2DownloadStartingEventArgs e) { Downloads.Start(e, this); };
			}
			catch { }
			try
			{
				w.FaviconChanged += delegate { LoadFavicon(t); };
			}
			catch { }
			try
			{
				w.IsDocumentPlayingAudioChanged += delegate { t.Audio = w.IsDocumentPlayingAudio; PushTabs(); };
				w.IsMutedChanged += delegate { t.Muted = w.IsMuted; PushTabs(); };
			}
			catch { }
			try
			{
				w.ContextMenuRequested += delegate(object o, CoreWebView2ContextMenuRequestedEventArgs e) { OnContextMenu(t, e); };
			}
			catch { }
			try
			{
				w.Find.MatchCountChanged += delegate { if (t == Active) PostFind(); };
				w.Find.ActiveMatchIndexChanged += delegate { if (t == Active) PostFind(); };
			}
			catch { }
		}

		int CountOpened(Tab opener)
		{
			int n = 0;
			for (int i = Tabs.IndexOf(opener) + 1; i < Tabs.Count && Tabs[i].Opener == opener.Id; i++) n++;
			return n;
		}

		void SetTransparent(Tab t, bool on)
		{
			if (t.C == null || t.Transparent == on) return;
			t.Transparent = on;
			try { t.C.DefaultBackgroundColor = on ? Color.Transparent : (WebApp != null ? Color.FromArgb(12, 17, 21) : Color.White); } catch { }
		}

		// Whether this page sits straight on the window's glass: the new tab page,
		// and a web app's own site while it wears Oazy's look.
		bool Glassy(string url)
		{
			if (url == null) return false;
			if (url == "" || url.StartsWith(App.NewTabUrl, StringComparison.OrdinalIgnoreCase)) return WebApp == null;
			// Google's account pages (dark, see SetDark) and Oazy's own sign-in pages.
			if (WebApp != null && look && (WebApps.IsSignIn(url) || url.StartsWith(SignInJob.DoneUrl, StringComparison.OrdinalIgnoreCase))) return true;
			return WebApp != null && look && WebApps.Owns(WebApp, url);
		}

		// Oazy's look over a web app on or off (Ctrl+Shift+O, or the title bar).
		void SetLook(bool on)
		{
			if (WebApp == null || on == look) return;
			look = on;
			App.SetPref("app_" + WebApp.Id + "_plain", !on);
			foreach (Tab t in Tabs)
			{
				if (t.W == null) continue;
				InjectApp(t);
				if (!IsPopup) InjectSignIn(t);
				SetTransparent(t, Glassy(t.Url));
				SetDark(t, look && WebApps.IsSignIn(t.Url));
				try { t.W.ExecuteScriptAsync("window.dispatchEvent(new CustomEvent('oazy:look', { detail: " + (on ? "true" : "false") + " }))"); } catch { }
			}
			Post(Json.Obj("t", "look", "on", look));
		}

		// The web app's style and script go in before the site's own code runs,
		// in every document the tab loads. Re-added when the look changes.
		async Task InjectApp(Tab t)
		{
			if (WebApp == null || t.W == null) return;
			try
			{
				if (t.ScriptId != null) t.W.RemoveScriptToExecuteOnDocumentCreated(t.ScriptId);
				t.ScriptId = null;
				string id = await t.W.AddScriptToExecuteOnDocumentCreatedAsync(WebApps.Bootstrap(WebApp, look, App.Accent, App.Test != null));
				t.ScriptId = id;
			}
			catch { }
		}

		// Google's sign-in pages in an app's own window get the sign-in look too.
		async Task InjectSignIn(Tab t)
		{
			if (t.W == null) return;
			try
			{
				if (t.SignInScriptId != null) t.W.RemoveScriptToExecuteOnDocumentCreated(t.SignInScriptId);
				t.SignInScriptId = null;
				t.SignInScriptId = await t.W.AddScriptToExecuteOnDocumentCreatedAsync(WebApps.Bootstrap(WebApps.SignInDef, look, App.Accent, App.Test != null));
			}
			catch { }
		}

		// Google's account pages follow the system's light or dark; in Oazy's
		// windows they're asked for dark, so they sit on the glass like the rest.
		// Only this tab is affected, not the browser's other pages.
		void SetDark(Tab t, bool on) { SetDark(t, on, false); }

		void SetDark(Tab t, bool on, bool force)
		{
			if (t.W == null || (t.Dark == on && !force)) return;
			t.Dark = on;
			string features = on ? "[{\"name\":\"prefers-color-scheme\",\"value\":\"dark\"}]" : "[]";
			try { t.W.CallDevToolsProtocolMethodAsync("Emulation.setEmulatedMedia", "{\"features\":" + features + "}"); } catch { }
		}

		// A sign-in popup's page: the WebView the site's window.open() gets.
		public async Task<CoreWebView2> AdoptPopup(string url)
		{
			Tab t = new Tab { Url = url };
			Tabs.Add(t);
			Activate(t);
			await Ensure(t);
			if (t.W != null) SetDark(t, look && (url == "" || url.StartsWith("about:") || WebApps.IsSignIn(url)));
			return t.W;
		}

		// Oazy's sign-in shows how it went on a page of its own (ui/signin-done.html).
		public void ShowPage(string url)
		{
			if (Active == null) return;
			SetTransparent(Active, true);
			Navigate(Active, url);
		}

		async void LoadFavicon(Tab t)
		{
			if (t.W == null) return;
			string page = t.W.Source;
			try
			{
				if (string.IsNullOrEmpty(t.W.FaviconUri)) { t.Icon = ""; PushTabs(); return; }
				using (Stream s = await t.W.GetFaviconAsync(CoreWebView2FaviconImageFormat.Png))
				{
					if (s == null) return;
					MemoryStream ms = new MemoryStream();
					await s.CopyToAsync(ms);
					if (ms.Length == 0) return;
					string file = App.IconFile(page);
					if (file == "") return;
					File.WriteAllBytes(file, ms.ToArray());
					t.Icon = App.IconHttpUrl(page);
					PushTabs();
				}
			}
			catch { }
		}

		public void Activate(Tab t)
		{
			if (t == null || !Tabs.Contains(t)) return;
			Tab old = Active;
			Active = t;
			if (old != null && old != t && old.C != null) try { old.C.IsVisible = false; } catch { }
			if (old != null && old != t && findOpen) StopFind(old);
			PushTabs();
			PushNav();
			UpdateTitle();
			App.SessionChanged();
			if (t.C != null)
			{
				if (WindowState != FormWindowState.Minimized && !pageHidden) t.C.IsVisible = true;
				if (t.IsNtp) FocusOmnibox(); else FocusContent();
			}
			else
			{
				Ensure(t).ContinueWith(delegate(Task x)
				{
					if (Active == t && t.C != null && t.IsNtp) FocusOmnibox();
				}, TaskScheduler.FromCurrentSynchronizationContext());
				if (t.IsNtp) FocusOmnibox();
			}
		}

		public void CloseTab(Tab t)
		{
			if (t == null || !Tabs.Contains(t)) return;
			if (!t.IsNtp)
			{
				App.Closed.Add(t.ShownUrl);
				if (App.Closed.Count > 25) App.Closed.RemoveAt(0);
			}
			int i = Tabs.IndexOf(t);
			Tabs.Remove(t);
			if (Tabs.Count == 0)
			{
				Close();
				return;
			}
			if (t == Active)
			{
				// Back to the tab that opened it, like Chrome; otherwise the neighbour.
				Tab next = null;
				if (t.Opener != 0 && i < Tabs.Count && Tabs[i].Opener != t.Opener) next = TabById(t.Opener);
				if (next == null) next = Tabs[Math.Min(i, Tabs.Count - 1)];
				Activate(next);
			}
			if (t.C != null) try { t.C.Close(); } catch { }
			PushTabs();
			App.SessionChanged();
		}

		void TabCommand(Tab t, string cmd)
		{
			if (t == null) return;
			switch (cmd)
			{
				case "reload": if (t.W != null) t.W.Reload(); break;
				case "duplicate": AddTab(t.IsNtp ? App.NewTabUrl : t.ShownUrl, true, Tabs.IndexOf(t) + 1); break;
				case "mute":
					if (t.W != null) try { t.W.IsMuted = !t.W.IsMuted; } catch { }
					break;
				case "close": CloseTab(t); break;
				case "closeOthers":
					foreach (Tab o in Tabs.ToArray()) if (o != t) CloseTab(o);
					break;
				case "closeRight":
					for (int i = Tabs.Count - 1; i > Tabs.IndexOf(t); i--) CloseTab(Tabs[i]);
					break;
				case "window":
					if (Tabs.Count > 1)
					{
						string url = t.IsNtp ? "" : t.ShownUrl;
						CloseTab(t);
						App.OpenWindow(new List<string> { url }, 0, null, false);
					}
					break;
			}
		}

		void Navigate(Tab t, string url)
		{
			if (t == null) return;
			if (t.W == null)
			{
				t.Pending = url;
				t.Url = url;
				Ensure(t);
				return;
			}
			try { t.W.Navigate(url); }
			catch (ArgumentException) { try { t.W.Navigate(App.SearchUrl(url)); } catch { } }
			if (t == Active && !App.NewTabUrl.Equals(url)) FocusContent();
		}

		void UpdateTitle()
		{
			// A web app's window keeps its name, so Oazy's taskbar knows it.
			if (WebApp != null) { Text = WebApp.Name; return; }
			string title = Active == null || Active.IsNtp ? "New tab" : (Active.Title != "" ? Active.Title : DisplayUrl(Active.ShownUrl));
			Text = title + " - " + App.Name;
		}

		static string DisplayUrl(string url)
		{
			if (url.StartsWith(App.NewTabUrl)) return "";
			string u = url;
			if (u.StartsWith("https://")) u = u.Substring(8);
			else if (u.StartsWith("http://")) u = u.Substring(7);
			if (u.StartsWith("www.")) u = u.Substring(4);
			if (u.EndsWith("/") && u.IndexOf('/') == u.Length - 1) u = u.Substring(0, u.Length - 1);
			return u;
		}

		void PushTabs()
		{
			List<object> list = new List<object>();
			foreach (Tab t in Tabs)
			{
				string title = t.IsNtp ? "New tab" : (t.Title != "" ? t.Title : DisplayUrl(t.ShownUrl));
				list.Add(Json.Obj("id", t.Id, "title", title, "url", t.ShownUrl, "icon", t.Icon != "" ? t.Icon : App.IconHttpUrl(t.ShownUrl),
					"loading", t.Loading, "audio", t.Audio, "muted", t.Muted, "ntp", t.IsNtp, "crashed", t.Crashed));
			}
			Post(Json.Obj("t", "tabs", "tabs", list.ToArray(), "active", Active != null ? Active.Id : 0));
		}

		void PushNav()
		{
			Tab t = Active;
			if (t == null) return;
			string url = t.ShownUrl;
			string kind = url.StartsWith("https://") ? "https" : (url.StartsWith("http://") ? "http" : (url.StartsWith("file:") ? "file" : "other"));
			if (t.IsNtp) kind = "ntp";
			bool back = false, fwd = false;
			double zoom = 1;
			if (t.W != null) { back = t.W.CanGoBack; fwd = t.W.CanGoForward; }
			if (t.C != null) zoom = t.C.ZoomFactor;
			Post(Json.Obj("t", "nav", "id", t.Id, "url", t.IsNtp ? "" : url, "display", DisplayUrl(url), "host", App.HostOf(url), "kind", kind,
				"back", back, "fwd", fwd, "loading", t.Loading, "zoom", Math.Round(zoom * 100), "pinned", App.IsPinned(url), "crashed", t.Crashed));
		}

		// --- Address bar suggestions -------------------------------------------------------------

		async void Suggest(string q)
		{
			suggestFor = q;
			List<object> local = new List<object>();
			foreach (Dictionary<string, object> h in History.Search(q, 5))
			{
				string u = Json.Str(h, "u");
				local.Add(Json.Obj("kind", "history", "text", Json.Str(h, "t"), "url", u, "icon", App.IconHttpUrl(u)));
			}
			Post(Json.Obj("t", "suggest", "q", q, "local", local.ToArray(), "remote", new object[0], "url", App.FixUrl(q)));
			if (q.Trim().Length < 2) return;
			string[] engine = App.EngineInfo();
			try
			{
				await Task.Delay(120);
				if (suggestFor != q) return;
				using (WebClient wc = new WebClient())
				{
					wc.Encoding = Encoding.UTF8;
					wc.Headers[HttpRequestHeader.UserAgent] = "Mozilla/5.0 OazyBrowser";
					string body = await wc.DownloadStringTaskAsync(new Uri(engine[3] + Uri.EscapeDataString(q)));
					if (suggestFor != q) return;
					object[] arr = Json.S.DeserializeObject(body) as object[];
					List<object> remote = new List<object>();
					if (arr != null && arr.Length > 1 && arr[1] is object[])
					{
						foreach (object s in (object[])arr[1])
						{
							string text = s as string;
							if (text == null)
							{
								Dictionary<string, object> d = s as Dictionary<string, object>;
								text = d != null ? Json.Str(d, "phrase") : null;
							}
							if (string.IsNullOrEmpty(text) || text.Equals(q, StringComparison.OrdinalIgnoreCase)) continue;
							remote.Add(Json.Obj("kind", "search", "text", text, "url", App.SearchUrl(text)));
							if (remote.Count >= 5) break;
						}
					}
					Post(Json.Obj("t", "suggest", "q", q, "local", local.ToArray(), "remote", remote.ToArray(), "url", App.FixUrl(q)));
				}
			}
			catch { }
		}

		// --- Panels over the page ---------------------------------------------------------------
		// Menus and lists open inside the chrome's own WebView, stretched over the
		// page, with a still of the page underneath so nothing seems to move.

		async void Snapshot()
		{
			Tab t = Active;
			int n = ++snapCount;
			if (t == null || t.W == null || t.Crashed)
			{
				Post(Json.Obj("t", "snapshot", "url", ""));
				return;
			}
			string dir = Path.Combine(App.Media, "snaps");
			string name = "w" + GetHashCode().ToString("x") + "-" + n + (t.IsNtp ? ".png" : ".jpg");
			string file = Path.Combine(dir, name);
			try
			{
				using (FileStream fs = File.Create(file))
					await t.W.CapturePreviewAsync(t.IsNtp ? CoreWebView2CapturePreviewImageFormat.Png : CoreWebView2CapturePreviewImageFormat.Jpeg, fs);
				foreach (string old in Directory.GetFiles(dir, "w" + GetHashCode().ToString("x") + "-*"))
					if (old != file) try { File.Delete(old); } catch { }
				if (n == snapCount) Post(Json.Obj("t", "snapshot", "url", "https://" + App.MediaHost + "/snaps/" + name));
			}
			catch { Post(Json.Obj("t", "snapshot", "url", "")); }
		}

		// The chrome grows over the page first and the page hides a moment later,
		// once the chrome has drawn the still in its place; closing runs backwards.
		async void SetOverlay(bool on)
		{
			if (on == overlay) return;
			overlay = on;
			if (on)
			{
				chromeTall = true;
				DoLayout();
				await Task.Delay(90);
				if (!overlay) return;
				pageHidden = true;
				DoLayout();
			}
			else
			{
				pageHidden = false;
				DoLayout();
				await Task.Delay(60);
				if (overlay) return;
				chromeTall = false;
				DoLayout();
				FocusContent();
			}
		}

		// --- Find in page -------------------------------------------------------------------------

		async void Find(Dictionary<string, object> m)
		{
			Tab t = Active;
			string action = Json.Str(m, "action");
			if (action == "open" || action == "close")
			{
				findOpen = action == "open";
				extraDip = findOpen ? 44 : 0;
				DoLayout();
				if (!findOpen) { if (t != null) StopFind(t); FocusContent(); }
				return;
			}
			if (t == null || t.W == null) return;
			try
			{
				if (action == "next") t.W.Find.FindNext();
				else if (action == "prev") t.W.Find.FindPrevious();
				else
				{
					string q = Json.Str(m, "q");
					if (q == "") { t.W.Find.Stop(); Post(Json.Obj("t", "find", "count", 0, "index", -1)); return; }
					CoreWebView2FindOptions o = App.Env.CreateFindOptions();
					o.FindTerm = q;
					o.IsCaseSensitive = false;
					o.ShouldHighlightAllMatches = true;
					o.SuppressDefaultFindDialog = true;
					await t.W.Find.StartAsync(o);
					PostFind();
				}
			}
			catch { }
		}

		void StopFind(Tab t)
		{
			if (t.W == null) return;
			try { t.W.Find.Stop(); } catch { }
		}

		void PostFind()
		{
			if (Active == null || Active.W == null) return;
			try { Post(Json.Obj("t", "find", "count", Active.W.Find.MatchCount, "index", Active.W.Find.ActiveMatchIndex)); } catch { }
		}

		// --- Commands and shortcuts ----------------------------------------------------------------

		static readonly string[] AppCommands = { "back", "forward", "reload", "hardReload", "stop", "closeTab", "closeWindow", "nextTab", "prevTab",
			"fullscreen", "zoomIn", "zoomOut", "zoomReset", "print", "devtools", "minimize", "maximize", "close", "downloadsFolder", "tab", "look" };

		void Command(string cmd, Dictionary<string, object> m)
		{
			Tab t = Active;
			if (WebApp != null && Array.IndexOf(AppCommands, cmd) < 0)
			{
				// Browser things asked of a web app's window go to the browser.
				if (cmd == "newTab" || cmd == "newWindow" || cmd == "focusOmnibox") App.OpenInBrowser("");
				return;
			}
			switch (cmd)
			{
				case "back": if (t != null && t.W != null && t.W.CanGoBack) t.W.GoBack(); break;
				case "forward": if (t != null && t.W != null && t.W.CanGoForward) t.W.GoForward(); break;
				case "reload":
					if (t == null) break;
					if (t.W == null) Ensure(t);
					else if (t.Crashed || t.W.Source == "about:blank") Navigate(t, t.Url);
					else t.W.Reload();
					break;
				case "hardReload":
					if (t != null && t.W != null) try { t.W.CallDevToolsProtocolMethodAsync("Page.reload", "{\"ignoreCache\":true}"); } catch { t.W.Reload(); }
					break;
				case "stop": if (t != null && t.W != null) t.W.Stop(); break;
				case "newTab": AddTab(App.NewTabUrl, true, -1); break;
				case "closeTab": CloseTab(t); break;
				case "reopenTab":
					if (App.Closed.Count > 0)
					{
						string url = App.Closed[App.Closed.Count - 1];
						App.Closed.RemoveAt(App.Closed.Count - 1);
						AddTab(url, true, -1);
					}
					break;
				case "newWindow": App.OpenWindow(new List<string> { "" }, 0, null, false); break;
				case "closeWindow": Close(); break;
				case "nextTab": if (Tabs.Count > 1) Activate(Tabs[(Tabs.IndexOf(t) + 1) % Tabs.Count]); break;
				case "prevTab": if (Tabs.Count > 1) Activate(Tabs[(Tabs.IndexOf(t) - 1 + Tabs.Count) % Tabs.Count]); break;
				case "focusOmnibox": FocusOmnibox(); break;
				case "find": Post(Json.Obj("t", "openFind")); break;
				case "fullscreen": SetFullscreen(!fullscreen); break;
				case "history": Post(Json.Obj("t", "openPanel", "name", "history")); break;
				case "downloads": Post(Json.Obj("t", "openPanel", "name", "downloads")); break;
				case "zoomIn": if (t != null && t.C != null) t.C.ZoomFactor = Math.Min(5, Step(t.C.ZoomFactor, 1)); break;
				case "zoomOut": if (t != null && t.C != null) t.C.ZoomFactor = Math.Max(0.25, Step(t.C.ZoomFactor, -1)); break;
				case "zoomReset": if (t != null && t.C != null) t.C.ZoomFactor = 1; break;
				case "print":
					if (t != null && t.W != null) try { t.W.ShowPrintUI(CoreWebView2PrintDialogKind.Browser); } catch { t.W.ExecuteScriptAsync("window.print()"); }
					break;
				case "devtools": if (t != null && t.W != null) t.W.OpenDevToolsWindow(); break;
				case "pin":
					if (t != null && !t.IsNtp)
					{
						bool on = !App.IsPinned(t.ShownUrl);
						App.SetPinned(t.ShownUrl, t.Title, on);
						PushNav();
						Post(Json.Obj("t", "toast", "text", on ? "Pinned to your new tab page" : "Unpinned from your new tab page"));
					}
					break;
				case "engine":
					App.SetPref("engine", Json.Str(m, "value"));
					foreach (BrowserWindow w in App.Windows) w.Post(Json.Obj("t", "engine", "engine", App.Engine()));
					App.BroadcastNtp();
					break;
				case "restore":
					App.SetPref("no_restore", !Json.Bool(m, "value"));
					break;
				case "clearData": ClearData(); break;
				case "look": SetLook(!look); break;
				case "minimize": WindowState = FormWindowState.Minimized; break;
				case "maximize":
					if (fullscreen) SetFullscreen(false);
					else SetMaximized(!zoomed);
					break;
				case "close": Close(); break;
				case "openUrl":
					{
						string url = Json.Str(m, "url");
						if (url != "") { if (Json.Bool(m, "newTab")) AddTab(url, true, -1); else Navigate(t, url); }
					}
					break;
				case "downloadsFolder":
					try
					{
						string dir = t != null && t.W != null ? t.W.Profile.DefaultDownloadFolderPath : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
						Process.Start("explorer.exe", "\"" + dir + "\"");
					}
					catch { }
					break;
				case "tab":
					{
						int n = Json.Int(m, "value");
						if (Tabs.Count > 0) Activate(n >= 9 ? Tabs[Tabs.Count - 1] : Tabs[Math.Min(n - 1, Tabs.Count - 1)]);
					}
					break;
			}
		}

		static double Step(double z, int dir)
		{
			double[] steps = { 0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5 };
			if (dir > 0) { foreach (double s in steps) if (s > z + 0.001) return s; return 5; }
			for (int i = steps.Length - 1; i >= 0; i--) if (steps[i] < z - 0.001) return steps[i];
			return 0.25;
		}

		async void ClearData()
		{
			try
			{
				if (Active != null && Active.W != null) await Active.W.Profile.ClearBrowsingDataAsync();
			}
			catch { }
			History.Clear();
			App.BroadcastNtp();
			Post(Json.Obj("t", "toast", "text", "Browsing data cleared"));
		}

		static bool Down(int vk) { return (Native.GetKeyState(vk) & 0x8000) != 0; }

		void OnAccelerator(object sender, CoreWebView2AcceleratorKeyPressedEventArgs e)
		{
			if (e.KeyEventKind != CoreWebView2KeyEventKind.KeyDown && e.KeyEventKind != CoreWebView2KeyEventKind.SystemKeyDown) return;
			bool ctrl = Down(0x11), shift = Down(0x10), alt = Down(0x12);
			uint vk = e.VirtualKey;
			bool repeat = e.PhysicalKeyStatus.WasKeyDown != 0;
			bool fromChrome = sender == chrome;
			string cmd = null;
			Dictionary<string, object> arg = null;
			if (ctrl && !alt)
			{
				switch (vk)
				{
					case 0x54: cmd = shift ? "reopenTab" : "newTab"; break;            // T
					case 0x57: cmd = shift ? "closeWindow" : "closeTab"; break;        // W
					case 0x73: cmd = "closeTab"; break;                                // F4
					case 0x4E: if (!shift) cmd = "newWindow"; break;                   // N
					case 0x09: cmd = shift ? "prevTab" : "nextTab"; break;             // Tab
					case 0x22: cmd = "nextTab"; break;                                 // PgDn
					case 0x21: cmd = "prevTab"; break;                                 // PgUp
					case 0x4C: cmd = "focusOmnibox"; break;                            // L
					case 0x4B: cmd = "focusOmnibox"; break;                            // K
					case 0x52: cmd = shift ? "hardReload" : "reload"; break;           // R
					case 0x4F: if (shift) cmd = "look"; break;                         // Shift+O
					case 0x74: cmd = "hardReload"; break;                              // F5
					case 0x46: cmd = "find"; break;                                    // F
					case 0x48: cmd = "history"; break;                                 // H
					case 0x4A: cmd = "downloads"; break;                               // J
					case 0x44: cmd = "pin"; break;                                     // D
					case 0x50: if (fromChrome) cmd = "print"; break;                   // P
					case 0xBB: case 0x6B: if (fromChrome) cmd = "zoomIn"; break;       // + (page handles its own)
					case 0xBD: case 0x6D: if (fromChrome) cmd = "zoomOut"; break;
					case 0x30: case 0x60: if (fromChrome) cmd = "zoomReset"; break;
					default:
						if (vk >= 0x31 && vk <= 0x39) { cmd = "tab"; arg = Json.Obj("value", (int)(vk - 0x30)); }
						break;
				}
			}
			else if (alt && !ctrl)
			{
				if (vk == 0x25) cmd = "back";
				else if (vk == 0x27) cmd = "forward";
				else if (vk == 0x44) cmd = "focusOmnibox";                             // Alt+D
				else if (vk == 0x24) { cmd = "openUrl"; arg = Json.Obj("url", App.NewTabUrl); } // Alt+Home
			}
			else if (!ctrl && !alt)
			{
				if (vk == 0x74) cmd = shift ? "hardReload" : "reload";                 // F5
				else if (vk == 0x7A) cmd = "fullscreen";                               // F11
				else if (vk == 0x75) cmd = "focusOmnibox";                             // F6
				else if (vk == 0x1B && fullscreen && !fromChrome && Active != null && Active.W != null && !Active.W.ContainsFullScreenElement) cmd = "fullscreen";
				else if (vk == 0xA6) cmd = "back";                                     // browser keys
				else if (vk == 0xA7) cmd = "forward";
				else if (vk == 0xA8) cmd = "reload";
			}
			if (cmd == null) return;
			if (repeat && cmd != "nextTab" && cmd != "prevTab" && cmd != "zoomIn" && cmd != "zoomOut") { e.Handled = true; return; }
			e.Handled = true;
			Command(cmd, arg);
		}

		void OnContextMenu(Tab t, CoreWebView2ContextMenuRequestedEventArgs e)
		{
			IList<CoreWebView2ContextMenuItem> items = e.MenuItems;
			if (!e.ContextMenuTarget.HasLinkUri) return;
			string link = e.ContextMenuTarget.LinkUri;
			int at = 0;
			for (int i = 0; i < items.Count; i++)
			{
				if (items[i].Name == "openLinkInNewWindow")
				{
					at = i;
					items.RemoveAt(i);
					break;
				}
			}
			if (WebApp != null)
			{
				CoreWebView2ContextMenuItem browserItem = App.Env.CreateContextMenuItem("Open link in Oazy Browser", null, CoreWebView2ContextMenuItemKind.Command);
				browserItem.CustomItemSelected += delegate { Sync(delegate { App.OpenInBrowser(link); }); };
				items.Insert(Math.Min(at, items.Count), browserItem);
				return;
			}
			CoreWebView2ContextMenuItem tabItem = App.Env.CreateContextMenuItem("Open link in new tab", null, CoreWebView2ContextMenuItemKind.Command);
			tabItem.CustomItemSelected += delegate { Sync(delegate { AddTab(link, false, Tabs.IndexOf(t) + 1 + CountOpened(t)); }); };
			CoreWebView2ContextMenuItem winItem = App.Env.CreateContextMenuItem("Open link in new window", null, CoreWebView2ContextMenuItemKind.Command);
			winItem.CustomItemSelected += delegate { Sync(delegate { App.OpenWindow(new List<string> { link }, 0, null, false); }); };
			items.Insert(Math.Min(at, items.Count), winItem);
			items.Insert(Math.Min(at, items.Count), tabItem);
		}

		static void Sync(Action a)
		{
			App.Sync.Post(delegate { a(); }, null);
		}

		// --- Web apps ----------------------------------------------------------------------------

		void OnAppMessage(Tab t, string json)
		{
			Dictionary<string, object> m;
			try { m = Json.S.DeserializeObject(json) as Dictionary<string, object>; } catch { return; }
			if (m == null || Json.Str(m, "oazyApp") != WebApp.Id) return;
			if (Json.Str(m, "t") == "look")
			{
				// Shown in the title bar: whether the look found its way around the page.
				Post(Json.Obj("t", "appStatus", "ok", Json.Bool(m, "ok"), "found", Json.Str(m, "found"), "on", look));
				if (App.Test != null) App.Test.AppLook(this, m);
			}
		}

		// --- The new tab page ----------------------------------------------------------------

		void OnPageMessage(Tab t, string json)
		{
			Dictionary<string, object> m;
			try { m = Json.S.DeserializeObject(json) as Dictionary<string, object>; } catch { return; }
			if (m == null) return;
			switch (Json.Str(m, "t"))
			{
				case "signinDone":
					// Oazy's sign-in page has shown how it went; the window's job is done.
					if (Job != null) Close();
					break;
				case "ntpReady":
					SendNtp(t);
					if (App.Test != null) App.Test.NtpReady(this);
					break;
				case "search":
					{
						string q = Json.Str(m, "q");
						if (q.Trim() != "") Navigate(t, App.FixUrl(q));
					}
					break;
				case "focusOmnibox":
					FocusOmnibox();
					Post(Json.Obj("t", "typeOmnibox", "text", Json.Str(m, "text")));
					break;
				case "pin": App.SetPinned(Json.Str(m, "url"), Json.Str(m, "title"), Json.Bool(m, "on")); break;
				case "hide": App.HideSite(Json.Str(m, "url")); break;
				case "addSite":
					{
						string url = App.FixUrl(Json.Str(m, "url"));
						if (url.StartsWith("http")) App.SetPinned(url, Json.Str(m, "title") != "" ? Json.Str(m, "title") : App.HostOf(url), true);
					}
					break;
			}
		}

		void SendNtp(Tab t)
		{
			if (t.W == null) return;
			string[] e = App.EngineInfo();
			try
			{
				t.W.PostWebMessageAsJson(Json.S.Serialize(Json.Obj("t", "ntp", "tiles", App.Tiles(), "engine", e[1], "accent", App.Accent)));
			}
			catch { }
		}

		public void RefreshNtp()
		{
			foreach (Tab t in Tabs) if (t.W != null && t.IsNtp) SendNtp(t);
		}

		// --- Self-test hooks ------------------------------------------------------------------

		public void TestOpenPanel(string name) { Post(Json.Obj("t", "openPanel", "name", name)); }
		public void TestNavigate(string url) { Navigate(Active, url); }
		public void TestShowChrome(bool on) { try { chrome.IsVisible = on; } catch { } }
		public void TestShowPage(bool on) { try { Active.C.IsVisible = on; } catch { } }
		public void TestLook(bool on) { SetLook(on); }
	}

	// --- Self-test: proves the browser works on a real Windows box (CI) ------------------

	class Selftest
	{
		readonly string dir;
		readonly List<string> log = new List<string>();
		public int ExitCode = 1;
		BrowserWindow win, appWin, signWin;
		bool chromeOk, ntpOk, pageOk, glassOk, appOk, done;
		int step, retries;
		const string TestUrl = "https://en.wikipedia.org/wiki/Oasis";
		System.Windows.Forms.Timer timeout;

		public Selftest(string outDir)
		{
			dir = outDir;
			Directory.CreateDirectory(dir);
		}

		void Log(string s) { log.Add(DateTime.Now.ToString("HH:mm:ss.fff") + " " + s); }

		public void Begin()
		{
			Log("runtime " + App.Version);
			timeout = new System.Windows.Forms.Timer { Interval = 120000 };
			timeout.Tick += delegate { Log("timed out at step " + step); Finish(); };
			timeout.Start();
			Rectangle work = Screen.PrimaryScreen.WorkingArea;
			Rectangle r = new Rectangle(work.Left + 20, work.Top + 20, Math.Min(1400, work.Width - 40), Math.Min(880, work.Height - 40));
			win = App.OpenWindow(new List<string> { "" }, 0, r, false);
		}

		public void ChromeReady(BrowserWindow w) { chromeOk = true; Log("chrome ready"); Next(); }
		public void NtpReady(BrowserWindow w) { if (!ntpOk) { ntpOk = true; Log("new tab page ready"); Next(); } }

		public void Navigated(BrowserWindow w, Tab t, bool ok)
		{
			if (step == 6) Log("sign-in window: " + ok + " " + t.Url);
			if (step != 2 || t.IsNtp) return;
			Log("page loaded: " + ok + " " + t.Url);
			// A navigation that gets cancelled or blips on the network reports
			// failure straight away; give the page a couple more tries.
			if (!ok && ++retries <= 2) { RetryLater(); return; }
			pageOk = ok;
			Next();
		}

		async void RetryLater()
		{
			await Task.Delay(1500);
			win.TestNavigate(TestUrl);
		}

		public void FromChrome(BrowserWindow w, Dictionary<string, object> m) { Log("chrome says " + Json.Str(m, "what")); }

		async void Next()
		{
			if (step == 0 && chromeOk && ntpOk)
			{
				step = 1;
				await Task.Delay(1500);
				Shot("browser-newtab.png");
				// The bare window behind the chrome and the page, to check the glass.
				win.TestShowChrome(false);
				win.TestShowPage(false);
				await Task.Delay(600);
				Shot("browser-backdrop.png");
				glassOk = EvenGlass("browser-backdrop.png");
				// Maximized (as Windows does it, e.g. Win+Up): Oazy takes over and the
				// window fills exactly the work area, with even glass along the top.
				Rectangle normal = win.Bounds;
				win.WindowState = FormWindowState.Maximized;
				await Task.Delay(1500);
				Shot("browser-max.png");
				Rectangle wa = Screen.FromHandle(win.Handle).WorkingArea;
				bool flush = win.Maximized && win.WindowState == FormWindowState.Normal && win.Bounds == wa;
				Log("maximized " + win.Maximized + ", bounds " + win.Bounds + " vs work area " + wa);
				glassOk = EvenGlass("browser-max.png") && flush && glassOk;
				win.SetMaximized(false);
				await Task.Delay(1500);
				Shot("browser-restored.png");
				Log("restored to " + win.Bounds + " (was " + normal + ")");
				glassOk = EvenGlass("browser-restored.png") && win.Bounds == normal && !win.Maximized && glassOk;
				win.TestShowChrome(true);
				await Task.Delay(400);
				Shot("browser-chrome-only.png");
				win.TestShowPage(true);
				step = 2;
				win.TestNavigate(TestUrl);
			}
			else if (step == 2)
			{
				step = 3;
				await Task.Delay(2500);
				Shot("browser-page.png");
				win.AddTab("https://example.com", true, -1);
				await Task.Delay(2500);
				win.TestOpenPanel("menu");
				await Task.Delay(1200);
				Shot("browser-menu.png");
				win.TestOpenPanel("");
				await Task.Delay(500);
				win.TestOpenPanel("downloads");
				await Task.Delay(1000);
				Shot("browser-downloads.png");
				win.TestOpenPanel("");
				// A web app, on a stand-in for its site: the slim window and the look.
				step = 4;
				WebAppDef flow = WebApps.Find("flow");
				Rectangle bounds = win.Bounds;
				// Screenshots are taken off the screen, so the browser steps aside.
				win.WindowState = FormWindowState.Minimized;
				appWin = App.OpenWindow(new List<string> { "https://" + flow.Hosts[0] + "/flow-mock.html" }, 0, bounds, false, flow);
				appWin.TopMost = true;
				await Task.Delay(20000);
				if (step == 4) { Log("the web app's look never reported"); Shot(appWin, "flow-app.png"); Finish(); }
			}
			else if (step == 5)
			{
				await Task.Delay(1800);
				Shot(appWin, "flow-app.png");
				appWin.TestLook(false);
				await Task.Delay(1800);
				Shot(appWin, "flow-plain.png");
				// Oazy's sign-in window on Google's real page (signed out, so the
				// email step), then how a finished sign-in looks. Only screenshots:
				// whether Google answers a CI runner doesn't decide the test.
				step = 6;
				appWin.WindowState = FormWindowState.Minimized;
				SignInJob job = new SignInJob(false, "", "");
				signWin = App.OpenWindow(new List<string> { job.StartUrl() }, 0, null, false, WebApps.SignInDef, null, job);
				signWin.TopMost = true;
				await Task.Delay(9000);
				Shot(signWin, "signin-google.png");
				signWin.ShowPage(SignInJob.DoneUrl + "#" + Uri.EscapeDataString(Json.S.Serialize(Json.Obj("name", "Oazy Tester", "email", "tester@gmail.com", "photo", "", "accent", App.Accent, "test", true))));
				await Task.Delay(2500);
				Shot(signWin, "signin-done.png");
				Finish();
			}
		}

		public void AppLook(BrowserWindow w, Dictionary<string, object> m)
		{
			Log("web app look: ok=" + Json.Bool(m, "ok") + " found=" + Json.Str(m, "found"));
			if (step != 4 || w != appWin) return;
			appOk = Json.Bool(m, "ok") && Json.Str(m, "found").Contains("prompt") && Json.Str(m, "found").Contains("media");
			step = 5;
			Next();
		}

		public void Exited()
		{
			Log("message loop ended, exiting with " + ExitCode);
			try { File.WriteAllLines(Path.Combine(dir, "browser-selftest.log"), log.ToArray()); } catch { }
		}

		// The bare window should be one even sheet of glass from the top edge down,
		// with no caption strip behind the tabs.
		bool EvenGlass(string name)
		{
			try
			{
				using (Bitmap bmp = new Bitmap(Path.Combine(dir, name)))
				{
					int x = bmp.Width * 6 / 10, dy = 0;
					Color top = bmp.GetPixel(x, dy + 12), below = bmp.GetPixel(x, Math.Min(dy + 80, bmp.Height - 1));
					int diff = Math.Abs(top.R - below.R) + Math.Abs(top.G - below.G) + Math.Abs(top.B - below.B);
					Log(name + " glass top vs below: " + diff);
					return diff < 30;
				}
			}
			catch (Exception e) { Log("glass check failed: " + e.Message); return false; }
		}

		void Shot(string name) { Shot(win, name); }

		void Shot(BrowserWindow of, string name)
		{
			try
			{
				Rectangle b = of.Bounds;
				using (Bitmap bmp = new Bitmap(b.Width, b.Height))
				{
					using (Graphics g = Graphics.FromImage(bmp)) g.CopyFromScreen(b.Location, Point.Empty, b.Size);
					bmp.Save(Path.Combine(dir, name), System.Drawing.Imaging.ImageFormat.Png);
					// A column of pixels down the empty part of the tab strip, for the log.
					List<string> col = new List<string>();
					for (int y = 0; y < Math.Min(80, b.Height); y += 4)
					{
						Color c = bmp.GetPixel(b.Width * 6 / 10, y);
						col.Add(y + ":" + c.R + "," + c.G + "," + c.B);
					}
					Log(name + " column " + string.Join(" ", col.ToArray()));
				}
				Log("saved " + name);
			}
			catch (Exception e) { Log("screenshot failed: " + e.Message); }
		}

		void Finish()
		{
			if (done) return;
			done = true;
			ExitCode = chromeOk && ntpOk && pageOk && glassOk && appOk ? 0 : 1;
			Log("chrome=" + chromeOk + " ntp=" + ntpOk + " page=" + pageOk + " glass=" + glassOk + " app=" + appOk + " -> " + (ExitCode == 0 ? "PASS" : "FAIL"));
			try { File.WriteAllLines(Path.Combine(dir, "browser-selftest.log"), log.ToArray()); } catch { }
			App.Quit();
		}
	}
}
