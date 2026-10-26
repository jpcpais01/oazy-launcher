// Oazy Files: your folders in an Oazy glass window.
//
// The window is a borderless WinForms form with an acrylic backdrop (the same
// frame as Oazy Terminal) and one transparent WebView2 showing ui/files.html,
// which draws the tabs, the sidebar, the folder views and every menu. This
// file does the work the page can't: reading folders, Windows' own icons and
// thumbnails, opening files, and copying, moving and deleting through the
// shell (so the Recycle Bin, Undo in Windows Explorer and its conflict
// prompts all behave as usual).
//
// The page and this file talk with postMessage, one JSON object per message
// ({"t": "<type>", ...}). Requests that answer carry "rid" and get
// {"t": "reply", "rid": ...} back. Icons and thumbnails are images from
// https://oazy-icons.example/i?p=<path>&s=<px>&k=<cache key>&th=<0|1>,
// rendered here on STA threads with IShellItemImageFactory.
//
// Like the shell companion, Oazy Browser and Oazy Terminal, Oazy compiles
// this file on first use with the .NET Framework csc.exe that comes with
// Windows, so it must stay C# 5.
//
// Usage: OazyFiles.exe --data <dir> [--accent <hex>] [--new-window] [<folder or file>]
//        OazyFiles.exe --selftest <out dir>
// A second launch hands its folder to the running one over a named pipe.

using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.IO.Compression;
using System.IO.Pipes;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;
using Microsoft.Web.WebView2.Core;

namespace OazyFiles
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
		[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetProp(IntPtr h, string name, IntPtr value);
		[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
		[DllImport("user32.dll")] public static extern bool ReleaseCapture();
		[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
		[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
		[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);
		[DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
		[DllImport("user32.dll")] public static extern int GetSystemMetricsForDpi(int index, uint dpi);
		[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
		[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
		[DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
		[DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int index, IntPtr value);
		[DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
		[DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);

		// --- Shell file operations --------------------------------------------------------

		[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
		public struct SHFILEOPSTRUCT
		{
			public IntPtr hwnd;
			public uint wFunc;
			public string pFrom;
			public string pTo;
			public ushort fFlags;
			public bool fAnyOperationsAborted;
			public IntPtr hNameMappings;
			public string lpszProgressTitle;
		}

		public const uint FO_MOVE = 1, FO_COPY = 2, FO_DELETE = 3;
		public const ushort FOF_RENAMEONCOLLISION = 0x8, FOF_NOCONFIRMATION = 0x10, FOF_ALLOWUNDO = 0x40,
			FOF_NOCONFIRMMKDIR = 0x200, FOF_WANTNUKEWARNING = 0x4000;

		[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SHFileOperation(ref SHFILEOPSTRUCT op);
		[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern bool SHObjectProperties(IntPtr hwnd, uint type, string name, string page);

		[DllImport("shell32.dll")]
		public static extern int SHGetKnownFolderPath([MarshalAs(UnmanagedType.LPStruct)] Guid id, uint flags, IntPtr token, out IntPtr path);

		[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
		public struct SHFILEINFO
		{
			public IntPtr hIcon;
			public int iIcon;
			public uint dwAttributes;
			[MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szDisplayName;
			[MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string szTypeName;
		}

		public const uint SHGFI_TYPENAME = 0x400, SHGFI_USEFILEATTRIBUTES = 0x10;

		[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
		public static extern IntPtr SHGetFileInfo(string path, uint attrs, ref SHFILEINFO info, uint size, uint flags);

		// --- Icons and thumbnails ---------------------------------------------------------

		[StructLayout(LayoutKind.Sequential)]
		public struct SIZE { public int cx, cy; }

		[ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
		public interface IShellItemImageFactory
		{
			[PreserveSig] int GetImage(SIZE size, int flags, out IntPtr bitmap);
		}

		public const int SIIGBF_RESIZETOFIT = 0, SIIGBF_ICONONLY = 4, SIIGBF_THUMBNAILONLY = 8;

		[DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
		public static extern void SHCreateItemFromParsingName(string path, IntPtr bindCtx, [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
			[MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory item);

		[StructLayout(LayoutKind.Sequential)]
		public struct BITMAP
		{
			public int bmType, bmWidth, bmHeight, bmWidthBytes;
			public ushort bmPlanes, bmBitsPixel;
			public IntPtr bmBits;
		}

		[StructLayout(LayoutKind.Sequential)]
		public struct BITMAPINFO
		{
			public int biSize, biWidth, biHeight;
			public short biPlanes, biBitCount;
			public int biCompression, biSizeImage, biXPelsPerMeter, biYPelsPerMeter, biClrUsed, biClrImportant;
			public uint c0, c1, c2, c3;
		}

		[DllImport("gdi32.dll")] public static extern int GetObject(IntPtr h, int size, ref BITMAP bm);
		[DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr h);
		[DllImport("gdi32.dll")] public static extern int GetDIBits(IntPtr dc, IntPtr bmp, uint start, uint lines, [Out] byte[] bits, ref BITMAPINFO info, uint usage);
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

		public static string[] Strs(Dictionary<string, object> d, string k)
		{
			object v;
			List<string> list = new List<string>();
			if (d != null && d.TryGetValue(k, out v) && v is IEnumerable && !(v is string))
				foreach (object o in (IEnumerable)v) if (o != null && Convert.ToString(o) != "") list.Add(Convert.ToString(o));
			return list.ToArray();
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
			string data = "", accent = "", selftest = "", path = "";
			bool newWindow = false;
			for (int i = 0; i < args.Length; i++)
			{
				string a = args[i];
				bool more = i + 1 < args.Length;
				if (a == "--data" && more) data = args[++i];
				else if (a == "--accent" && more) accent = args[++i];
				else if (a == "--selftest" && more) selftest = args[++i];
				else if (a == "--new-window") newWindow = true;
				else if (!a.StartsWith("--")) path = a;
			}
			if (selftest != "") data = Path.Combine(Path.GetTempPath(), "OazyFilesSelftest-" + Process.GetCurrentProcess().Id);
			if (data == "") data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Oazy", "Files");
			data = Path.GetFullPath(data);

			string pipe = "OazyFiles-" + App.Hash(Environment.UserName + "|" + data.ToLowerInvariant());
			bool first;
			Mutex single = new Mutex(true, "Local\\" + pipe, out first);
			if (!first && selftest == "")
			{
				if (Forward(pipe, newWindow, path)) return 0;
				// The running copy isn't answering; carry on as a second one.
			}
			try { if (!Native.SetProcessDpiAwarenessContext(new IntPtr(-4))) Native.SetProcessDPIAware(); }
			catch { try { Native.SetProcessDPIAware(); } catch { } }
			Application.EnableVisualStyles();
			Application.SetCompatibleTextRenderingDefault(false);
			int code = App.Run(data, accent, pipe, path, selftest);
			GC.KeepAlive(single);
			// Leave now rather than let CLR shutdown finalize WebView2's COM objects
			// off their STA thread, which crashes on the way out (as in Oazy Browser).
			try { single.ReleaseMutex(); } catch { }
			Native.TerminateProcess(Native.GetCurrentProcess(), (uint)code);
			return code;
		}

		static bool Forward(string pipe, bool newWindow, string path)
		{
			for (int attempt = 0; attempt < 3; attempt++)
			{
				try
				{
					using (NamedPipeClientStream c = new NamedPipeClientStream(".", pipe, PipeDirection.Out))
					{
						c.Connect(1000);
						try { Native.AllowSetForegroundWindow(-1); } catch { }
						string text = Json.S.Serialize(Json.Obj("window", newWindow, "path", path)) + "\n";
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

	// --- The app as a whole: prefs, windows, single instance ----------------------------------

	static class App
	{
		public const string UiHost = "oazy.example";
		public const string PageUrl = "https://oazy.example/files.html";
		public const string IconHost = "https://oazy-icons.example/";
		public const string Name = "Oazy Files";

		public static string Data, Ui, Accent = "#38d6c4", Version = "";
		public static CoreWebView2Environment Env;
		public static SynchronizationContext Sync;
		public static readonly List<FilesWindow> Windows = new List<FilesWindow>();
		public static FilesWindow LastActive;
		public static Dictionary<string, object> Prefs;
		public static Selftest Test;
		public static bool Quitting { get { return quitting; } }
		static ApplicationContext ctx;
		static bool prefsDirty, quitting;
		static string pipeName;

		public static int Run(string data, string accent, string pipe, string path, string selftest)
		{
			Data = data;
			pipeName = pipe;
			Ui = Path.Combine(Path.GetDirectoryName(Application.ExecutablePath), "ui");
			try { Directory.CreateDirectory(Data); }
			catch (Exception e)
			{
				MessageBox.Show("Oazy Files can't use its settings folder:\n" + Data + "\n\n" + e.Message, Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
				return 2;
			}
			try { Version = CoreWebView2Environment.GetAvailableBrowserVersionString(); }
			catch (Exception) { Version = ""; }
			if (string.IsNullOrEmpty(Version))
			{
				NoRuntime(path);
				return 3;
			}

			Prefs = Json.Load(Path.Combine(Data, "prefs.json"));
			if (accent != "") { Prefs["accent"] = accent; prefsDirty = true; }
			Accent = Json.Str(Prefs, "accent") != "" ? Json.Str(Prefs, "accent") : Accent;

			SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());
			Sync = SynchronizationContext.Current;
			ctx = new ApplicationContext();
			Icons.Start(3);
			System.Windows.Forms.Timer saveTimer = new System.Windows.Forms.Timer { Interval = 2000 };
			saveTimer.Tick += delegate { SaveNow(); };
			saveTimer.Start();
			if (selftest != "") Test = new Selftest(selftest);
			else StartPipe();
			Start(path);
			Application.Run(ctx);
			SaveNow();
			if (Test != null) Test.Exited();
			return Test != null ? Test.ExitCode : 0;
		}

		static async void Start(string path)
		{
			try
			{
				CoreWebView2EnvironmentOptions opts = new CoreWebView2EnvironmentOptions("--enable-features=OverlayScrollbar");
				Env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(Data, "webview"), opts);
			}
			catch (Exception e)
			{
				MessageBox.Show("Oazy Files couldn't start its renderer.\n\n" + e.Message, Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
				ctx.ExitThread();
				return;
			}
			Env.BrowserProcessExited += OnBrowserExited;
			if (Test != null) { Test.Begin(); return; }
			OpenWindow(path, null);
		}

		public static FilesWindow OpenWindow(string path, Rectangle? bounds)
		{
			if (!bounds.HasValue && Windows.Count == 0)
			{
				object[] b = Prefs.ContainsKey("bounds") ? Prefs["bounds"] as object[] : null;
				if (b != null && b.Length == 4)
				{
					try { bounds = new Rectangle(Convert.ToInt32(b[0]), Convert.ToInt32(b[1]), Convert.ToInt32(b[2]), Convert.ToInt32(b[3])); } catch { }
				}
			}
			FilesWindow w = new FilesWindow(path, bounds, Windows.Count == 0 && Json.Bool(Prefs, "max"));
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
			foreach (FilesWindow w in Windows.ToArray()) { try { w.Close(); } catch { } }
			ctx.ExitThread();
		}

		static void OnBrowserExited(object sender, CoreWebView2BrowserProcessExitedEventArgs e)
		{
			if (quitting || e.BrowserProcessExitKind == CoreWebView2BrowserProcessExitKind.Normal) return;
			Quit();
		}

		static void NoRuntime(string path)
		{
			// Without WebView2 there's no window to draw; Windows Explorer still works.
			try
			{
				if (path != "") Process.Start("explorer.exe", "\"" + path + "\"");
				else Process.Start("explorer.exe");
			}
			catch { }
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
			if (Env == null) return;
			foreach (string line in text.Split('\n'))
			{
				if (line.Trim() == "") continue;
				Dictionary<string, object> m;
				try { m = Json.S.DeserializeObject(line) as Dictionary<string, object>; } catch { continue; }
				if (m == null) continue;
				string path = Json.Str(m, "path");
				if (Json.Bool(m, "window") || LastActive == null) OpenWindow(path, null);
				else
				{
					LastActive.OpenTab(path);
					LastActive.BringUp();
				}
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

		// Runs `work` on a fresh STA thread (the shell wants one) and hands its
		// result to `done` on the UI thread.
		public static void Background(Func<object> work, Action<object> done)
		{
			Thread t = new Thread(delegate()
			{
				object r;
				try { r = work(); }
				catch (Exception e) { r = Json.Obj("error", e.Message); }
				if (done != null) Sync.Post(delegate { done(r); }, null);
			});
			t.IsBackground = true;
			t.SetApartmentState(ApartmentState.STA);
			t.Start();
		}
	}

	// --- Reading the disk -------------------------------------------------------------------

	static class Fs
	{
		static readonly DateTime Epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
		static readonly ConcurrentDictionary<string, string> typeNames = new ConcurrentDictionary<string, string>(StringComparer.OrdinalIgnoreCase);

		public static long Ms(DateTime utc)
		{
			try { return (long)(utc - Epoch).TotalMilliseconds; } catch { return 0; }
		}

		// One row per entry: [name, isDir, size, modified, created, attributes].
		static object[] Row(FileSystemInfo f)
		{
			FileAttributes a = f.Attributes;
			bool dir = (a & FileAttributes.Directory) != 0;
			long size = -1;
			if (!dir) { try { size = ((FileInfo)f).Length; } catch { } }
			return new object[] { f.Name, dir ? 1 : 0, size, Ms(f.LastWriteTimeUtc), Ms(f.CreationTimeUtc), (int)a };
		}

		public static Dictionary<string, object> List(string path)
		{
			path = Normalize(path);
			DirectoryInfo di = new DirectoryInfo(path);
			if (!di.Exists)
			{
				if (File.Exists(path)) return Json.Obj("path", path, "file", true);
				return Json.Obj("path", path, "error", "missing");
			}
			List<object> rows = new List<object>();
			HashSet<string> exts = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
			string error = null;
			try
			{
				foreach (FileSystemInfo f in di.EnumerateFileSystemInfos())
				{
					try
					{
						object[] r = Row(f);
						rows.Add(r);
						if ((int)r[1] == 0) exts.Add(Path.GetExtension(f.Name));
					}
					catch { }
				}
			}
			catch (UnauthorizedAccessException) { error = "denied"; }
			catch (Exception e) { error = e.Message; }
			Dictionary<string, object> types = new Dictionary<string, object>();
			foreach (string x in exts) if (x != "") types[x.ToLowerInvariant()] = TypeName(x);
			Dictionary<string, object> res = Json.Obj("path", path, "items", rows.ToArray(), "types", types);
			if (error != null) res["error"] = error;
			try
			{
				string root = Path.GetPathRoot(path);
				if (!string.IsNullOrEmpty(root) && !root.StartsWith("\\\\"))
				{
					DriveInfo d = new DriveInfo(root);
					if (d.IsReady) { res["free"] = d.AvailableFreeSpace; res["total"] = d.TotalSize; }
				}
			}
			catch { }
			return res;
		}

		// "c:" -> "C:\", "C:\Users\" -> "C:\Users", environment variables expanded.
		public static string Normalize(string path)
		{
			path = Environment.ExpandEnvironmentVariables((path ?? "").Trim().Trim('"')).Replace('/', '\\');
			if (path.Length == 2 && path[1] == ':') path += "\\";
			try { path = Path.GetFullPath(path); } catch { }
			if (path.Length > 3 && path.EndsWith("\\") && !path.EndsWith(":\\")) path = path.TrimEnd('\\');
			if (path.Length >= 2 && path[1] == ':') path = char.ToUpperInvariant(path[0]) + path.Substring(1);
			return path;
		}

		public static string TypeName(string ext)
		{
			string t;
			if (typeNames.TryGetValue(ext, out t)) return t;
			t = "";
			try
			{
				Native.SHFILEINFO info = new Native.SHFILEINFO();
				if (Native.SHGetFileInfo("x" + ext, 0x80, ref info, (uint)Marshal.SizeOf(info), Native.SHGFI_TYPENAME | Native.SHGFI_USEFILEATTRIBUTES) != IntPtr.Zero)
					t = info.szTypeName ?? "";
			}
			catch { }
			typeNames[ext] = t;
			return t;
		}

		public static string KnownFolder(string guid, Environment.SpecialFolder fallback)
		{
			try
			{
				IntPtr p;
				if (Native.SHGetKnownFolderPath(new Guid(guid), 0, IntPtr.Zero, out p) == 0)
				{
					string s = Marshal.PtrToStringUni(p);
					Marshal.FreeCoTaskMem(p);
					if (!string.IsNullOrEmpty(s)) return s;
				}
			}
			catch { }
			return Environment.GetFolderPath(fallback);
		}

		public static Dictionary<string, object> Places()
		{
			string home = App.Home();
			List<object> quick = new List<object>();
			quick.Add(Json.Obj("name", Environment.UserName, "path", home, "kind", "home"));
			quick.Add(Json.Obj("name", "Desktop", "path", Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "kind", "desktop"));
			quick.Add(Json.Obj("name", "Downloads", "path", KnownFolder("374DE290-123F-4565-9164-39C4925E467B", Environment.SpecialFolder.UserProfile), "kind", "downloads"));
			quick.Add(Json.Obj("name", "Documents", "path", Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "kind", "documents"));
			quick.Add(Json.Obj("name", "Pictures", "path", Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "kind", "pictures"));
			quick.Add(Json.Obj("name", "Music", "path", Environment.GetFolderPath(Environment.SpecialFolder.MyMusic), "kind", "music"));
			quick.Add(Json.Obj("name", "Videos", "path", Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), "kind", "videos"));
			return Json.Obj("home", home, "user", Environment.UserName, "quick", quick.ToArray(), "drives", Drives(),
				"system", Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)));
		}

		public static object[] Drives()
		{
			List<object> list = new List<object>();
			foreach (DriveInfo d in DriveInfo.GetDrives())
			{
				string type = "fixed";
				switch (d.DriveType)
				{
					case DriveType.Removable: type = "usb"; break;
					case DriveType.Network: type = "network"; break;
					case DriveType.CDRom: type = "disc"; break;
				}
				Dictionary<string, object> o = Json.Obj("path", d.Name, "letter", d.Name.TrimEnd('\\'), "type", type, "name", "", "total", 0L, "free", 0L);
				try
				{
					// A disconnected network drive can take seconds to say so.
					if (type != "network" || Directory.Exists(d.Name))
					{
						if (d.IsReady)
						{
							o["name"] = d.VolumeLabel;
							o["total"] = d.TotalSize;
							o["free"] = d.AvailableFreeSpace;
						}
					}
				}
				catch { }
				list.Add(o);
			}
			return list.ToArray();
		}

		// Recently opened files, from Windows' Recent folder (its shortcuts).
		public static object[] Recent()
		{
			List<object> list = new List<object>();
			try
			{
				string dir = Environment.GetFolderPath(Environment.SpecialFolder.Recent);
				List<FileInfo> links = new List<FileInfo>(new DirectoryInfo(dir).GetFiles("*.lnk"));
				links.Sort(delegate(FileInfo a, FileInfo b) { return b.LastWriteTimeUtc.CompareTo(a.LastWriteTimeUtc); });
				HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
				foreach (FileInfo l in links)
				{
					if (list.Count >= 30) break;
					string target = Shortcut(l.FullName);
					if (target == "" || !seen.Add(target)) continue;
					FileSystemInfo f;
					if (File.Exists(target)) f = new FileInfo(target);
					else if (Directory.Exists(target)) f = new DirectoryInfo(target);
					else continue;
					object[] r = Row(f);
					list.Add(new object[] { r[0], r[1], r[2], r[3], r[4], r[5], Path.GetDirectoryName(target) ?? "", Ms(l.LastWriteTimeUtc) });
				}
			}
			catch { }
			return list.ToArray();
		}

		static object wsh;

		// A shortcut's target, through WScript.Shell (no extra references needed).
		public static string Shortcut(string lnk)
		{
			try
			{
				if (wsh == null) wsh = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
				object sc = wsh.GetType().InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, wsh, new object[] { lnk });
				string t = Convert.ToString(sc.GetType().InvokeMember("TargetPath", BindingFlags.GetProperty, null, sc, null));
				Marshal.ReleaseComObject(sc);
				return t ?? "";
			}
			catch { return ""; }
		}

		static readonly string[] TextExts = { ".txt", ".md", ".log", ".json", ".xml", ".yml", ".yaml", ".ini", ".cfg", ".conf", ".toml", ".csv", ".tsv",
			".js", ".ts", ".jsx", ".tsx", ".css", ".scss", ".html", ".htm", ".py", ".cs", ".c", ".h", ".cpp", ".hpp", ".rs", ".go", ".java", ".kt",
			".gd", ".gdshader", ".tscn", ".tres", ".godot", ".sh", ".ps1", ".bat", ".cmd", ".sql", ".lua", ".rb", ".php", ".swift", ".vue", ".svelte",
			".gitignore", ".gitattributes", ".editorconfig", ".env", ".properties", ".reg", ".srt", ".vtt", ".nfo" };
		static readonly string[] ImageExts = { ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tif", ".tiff", ".ico" };

		public static Dictionary<string, object> Preview(string path)
		{
			Dictionary<string, object> r = Json.Obj("path", path);
			if (Directory.Exists(path))
			{
				int files = 0, dirs = 0;
				try
				{
					foreach (FileSystemInfo f in new DirectoryInfo(path).EnumerateFileSystemInfos())
					{
						if ((f.Attributes & FileAttributes.Directory) != 0) dirs++; else files++;
						if (files + dirs >= 100000) break;
					}
				}
				catch { r["denied"] = true; }
				r["files"] = files;
				r["dirs"] = dirs;
				return r;
			}
			if (!File.Exists(path)) { r["error"] = "missing"; return r; }
			string ext = Path.GetExtension(path).ToLowerInvariant();
			FileInfo fi = new FileInfo(path);
			if (ext == ".lnk") r["target"] = Shortcut(path);
			if (Array.IndexOf(ImageExts, ext) >= 0)
			{
				try
				{
					using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
					using (Image img = Image.FromStream(fs, false, false))
					{
						r["w"] = img.Width;
						r["h"] = img.Height;
					}
				}
				catch { }
			}
			if ((Array.IndexOf(TextExts, ext) >= 0 || ext == "") && fi.Length < 64L * 1024 * 1024)
			{
				try
				{
					using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
					{
						byte[] buf = new byte[8192];
						int n = fs.Read(buf, 0, buf.Length);
						bool binary = false;
						for (int i = 0; i < n; i++) if (buf[i] == 0) { binary = true; break; }
						if (!binary)
						{
							string text = new UTF8Encoding(false).GetString(buf, 0, n);
							if (text.Length > 0 && text[0] == '\uFEFF') text = text.Substring(1);
							r["text"] = text;
							r["more"] = fi.Length > n;
						}
					}
				}
				catch { }
			}
			return r;
		}

		// A free name in `dir` like "New folder (2)" or "notes (2).txt".
		public static string Unique(string dir, string name, bool folder)
		{
			string stem = folder ? name : Path.GetFileNameWithoutExtension(name);
			string ext = folder ? "" : Path.GetExtension(name);
			string p = Path.Combine(dir, name);
			for (int i = 2; File.Exists(p) || Directory.Exists(p); i++)
				p = Path.Combine(dir, stem + " (" + i + ")" + ext);
			return p;
		}

		public static string Rename(string path, string name)
		{
			name = (name ?? "").Trim();
			if (name == "" || name == "." || name == "..") return "That name can't be used";
			if (name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) return "A name can't contain any of these: \\ / : * ? \" < > |";
			string dir = Path.GetDirectoryName(path);
			if (dir == null) return "That can't be renamed";
			string target = Path.Combine(dir, name);
			if (target == path) return null;
			bool caseOnly = string.Equals(target, path, StringComparison.OrdinalIgnoreCase);
			if (!caseOnly && (File.Exists(target) || Directory.Exists(target))) return "There's already something called " + name + " here";
			if (Directory.Exists(path))
			{
				if (caseOnly)
				{
					string tmp = path + ".oazy-rename";
					Directory.Move(path, tmp);
					Directory.Move(tmp, target);
				}
				else Directory.Move(path, target);
			}
			else File.Move(path, target);
			return null;
		}

		// Copy, move or delete through the shell. Returns {ok, aborted}.
		public static Dictionary<string, object> ShellOp(uint func, string[] from, string to, IntPtr owner, bool permanent)
		{
			if (from.Length == 0) return Json.Obj("ok", true);
			Native.SHFILEOPSTRUCT op = new Native.SHFILEOPSTRUCT();
			op.hwnd = owner;
			op.wFunc = func;
			op.pFrom = string.Join("\0", from) + "\0";
			op.pTo = to != null ? to + "\0" : null;
			ushort flags = Native.FOF_NOCONFIRMMKDIR;
			if (func == Native.FO_DELETE)
			{
				flags |= Native.FOF_NOCONFIRMATION;
				if (!permanent) flags |= (ushort)(Native.FOF_ALLOWUNDO | Native.FOF_WANTNUKEWARNING);
			}
			else
			{
				flags |= Native.FOF_ALLOWUNDO;
				// Copying into the folder the files are already in makes "x - Copy".
				if (func == Native.FO_COPY)
				{
					foreach (string f in from)
					{
						if (string.Equals(Path.GetDirectoryName(f.TrimEnd('\\')), to.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
						{
							flags |= Native.FOF_RENAMEONCOLLISION;
							break;
						}
					}
				}
			}
			op.fFlags = flags;
			int rc = Native.SHFileOperation(ref op);
			Dictionary<string, object> r = Json.Obj("ok", rc == 0 && !op.fAnyOperationsAborted, "aborted", op.fAnyOperationsAborted);
			if (rc != 0 && !op.fAnyOperationsAborted && rc != 0x4C7) r["error"] = "Windows couldn't finish that (code 0x" + rc.ToString("x") + ")";
			return r;
		}

		public static string Extract(string zip)
		{
			string dir = Path.GetDirectoryName(zip);
			string dest = Unique(dir, Path.GetFileNameWithoutExtension(zip), true);
			ZipFile.ExtractToDirectory(zip, dest);
			// A zip holding one folder of the same name shouldn't nest twice.
			try
			{
				string[] inside = Directory.GetFileSystemEntries(dest);
				if (inside.Length == 1 && Directory.Exists(inside[0]))
				{
					string only = inside[0];
					string flat = Unique(dir, Path.GetFileName(only), true);
					string tmp = dest + ".oazy-tmp";
					Directory.Move(only, tmp);
					Directory.Delete(dest);
					if (!Directory.Exists(dest) && Path.GetFileName(only).Equals(Path.GetFileName(dest), StringComparison.OrdinalIgnoreCase)) flat = dest;
					Directory.Move(tmp, flat);
					return flat;
				}
			}
			catch { }
			return dest;
		}

		public static string Compress(string[] paths)
		{
			string dir = Path.GetDirectoryName(paths[0].TrimEnd('\\'));
			string name = paths.Length == 1 ? Path.GetFileNameWithoutExtension(paths[0].TrimEnd('\\')) : Path.GetFileName(dir);
			if (string.IsNullOrEmpty(name)) name = "Archive";
			string zip = Unique(dir, name + ".zip", false);
			using (FileStream fs = new FileStream(zip, FileMode.CreateNew))
			using (ZipArchive a = new ZipArchive(fs, ZipArchiveMode.Create))
			{
				foreach (string p in paths)
				{
					string clean = p.TrimEnd('\\');
					if (Directory.Exists(clean)) AddDir(a, clean, Path.GetFileName(clean));
					else if (File.Exists(clean)) a.CreateEntryFromFile(clean, Path.GetFileName(clean), CompressionLevel.Optimal);
				}
			}
			return zip;
		}

		static void AddDir(ZipArchive a, string dir, string prefix)
		{
			bool any = false;
			foreach (string f in Directory.GetFiles(dir)) { a.CreateEntryFromFile(f, prefix + "/" + Path.GetFileName(f), CompressionLevel.Optimal); any = true; }
			foreach (string d in Directory.GetDirectories(dir)) { AddDir(a, d, prefix + "/" + Path.GetFileName(d)); any = true; }
			if (!any) a.CreateEntry(prefix + "/");
		}

		// Oazy Terminal if Oazy has built it (it lives next to us), else Windows Terminal or PowerShell.
		public static void OpenTerminal(string dir)
		{
			try
			{
				string exe = Path.GetDirectoryName(Application.ExecutablePath);
				string root = Path.GetDirectoryName(Path.GetDirectoryName(exe));
				string term = Path.Combine(root, "terminal");
				string best = null;
				DateTime when = DateTime.MinValue;
				if (Directory.Exists(term))
				{
					foreach (string d in Directory.GetDirectories(term, "app-*"))
					{
						string p = Path.Combine(d, "OazyTerminal.exe");
						if (File.Exists(p) && File.GetLastWriteTimeUtc(p) > when) { best = p; when = File.GetLastWriteTimeUtc(p); }
					}
				}
				if (best != null)
				{
					Process.Start(new ProcessStartInfo(best, "--data \"" + Path.Combine(term, "data") + "\" --accent " + App.Accent + " --cwd \"" + dir.TrimEnd('\\') + (dir.EndsWith(":\\") ? "\\\\" : "") + "\"") { UseShellExecute = false });
					return;
				}
			}
			catch { }
			try { Process.Start(new ProcessStartInfo("wt.exe", "-d \"" + dir + "\"") { UseShellExecute = true }); return; }
			catch { }
			try { Process.Start(new ProcessStartInfo("powershell.exe") { WorkingDirectory = dir, UseShellExecute = true }); }
			catch { }
		}
	}

	// --- Search: everything under a folder whose name matches, nearest first --------------

	class Search
	{
		public readonly int Id;
		volatile bool cancelled;

		public Search(int id) { Id = id; }

		public void Cancel() { cancelled = true; }

		public void Run(string root, string query, bool hidden, FilesWindow w)
		{
			Regex re = null;
			string q = query.Trim();
			if (q.IndexOf('*') >= 0 || q.IndexOf('?') >= 0)
			{
				try { re = new Regex("^" + Regex.Escape(q).Replace("\\*", ".*").Replace("\\?", ".") + "$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant); }
				catch { re = null; }
			}
			string[] words = q.ToLowerInvariant().Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
			Thread t = new Thread(delegate()
			{
				int found = 0, folders = 0;
				bool truncated = false;
				List<object> batch = new List<object>();
				Stopwatch sw = Stopwatch.StartNew();
				Queue<string> queue = new Queue<string>();
				queue.Enqueue(root);
				while (queue.Count > 0 && !cancelled)
				{
					string dir = queue.Dequeue();
					folders++;
					IEnumerable<FileSystemInfo> items;
					try { items = new DirectoryInfo(dir).EnumerateFileSystemInfos(); }
					catch { continue; }
					try
					{
						foreach (FileSystemInfo f in items)
						{
							if (cancelled) break;
							FileAttributes a;
							try { a = f.Attributes; } catch { continue; }
							bool isDir = (a & FileAttributes.Directory) != 0;
							bool hid = (a & (FileAttributes.Hidden | FileAttributes.System)) != 0;
							if (hid && !hidden) continue;
							if (isDir && (a & FileAttributes.ReparsePoint) == 0) queue.Enqueue(f.FullName);
							if (!Matches(f.Name, re, words)) continue;
							long size = -1;
							if (!isDir) { try { size = ((FileInfo)f).Length; } catch { } }
							batch.Add(new object[] { f.Name, isDir ? 1 : 0, size, Fs.Ms(f.LastWriteTimeUtc), Fs.Ms(f.CreationTimeUtc), (int)a, dir });
							found++;
							if (found >= 5000) { truncated = true; cancelled = true; break; }
						}
					}
					catch { }
					if (batch.Count >= 300 || (batch.Count > 0 && sw.ElapsedMilliseconds > 120))
					{
						Send(w, batch, folders, false, false);
						batch = new List<object>();
						sw.Restart();
					}
				}
				Send(w, batch, folders, true, truncated);
			});
			t.IsBackground = true;
			t.Priority = ThreadPriority.BelowNormal;
			t.Start();
		}

		static bool Matches(string name, Regex re, string[] words)
		{
			if (re != null) return re.IsMatch(name);
			string n = name.ToLowerInvariant();
			foreach (string w in words) if (n.IndexOf(w, StringComparison.Ordinal) < 0) return false;
			return true;
		}

		void Send(FilesWindow w, List<object> batch, int folders, bool done, bool truncated)
		{
			object[] items = batch.ToArray();
			int id = Id;
			bool wasCancelled = cancelled && !truncated;
			App.Sync.Post(delegate
			{
				if (wasCancelled && !done) return;
				w.Post(Json.Obj("t", "found", "sid", id, "items", items, "folders", folders, "done", done, "truncated", truncated));
			}, null);
		}
	}

	// --- Icons and thumbnails, rendered on STA threads and kept in memory -------------------

	static class Icons
	{
		class Job
		{
			public string Path, Key;
			public int Size;
			public bool Thumb;
		}

		class Entry
		{
			public string Key, Type;
			public byte[] Bytes;
		}

		static readonly BlockingCollection<Job> queue = new BlockingCollection<Job>(new ConcurrentStack<Job>());
		static readonly object gate = new object();
		static readonly Dictionary<string, LinkedListNode<Entry>> map = new Dictionary<string, LinkedListNode<Entry>>();
		static readonly LinkedList<Entry> lru = new LinkedList<Entry>();
		static readonly Dictionary<string, List<Action<byte[], string>>> waiting = new Dictionary<string, List<Action<byte[], string>>>();
		static long bytes;
		const long Budget = 96L * 1024 * 1024;

		public static void Start(int threads)
		{
			for (int i = 0; i < threads; i++)
			{
				Thread t = new Thread(Work) { IsBackground = true, Name = "icons " + i, Priority = ThreadPriority.BelowNormal };
				t.SetApartmentState(ApartmentState.STA);
				t.Start();
			}
		}

		// Calls `done` (on an icon thread) with the image and its type, or nulls.
		public static void Get(string path, string key, int size, bool thumb, Action<byte[], string> done)
		{
			lock (gate)
			{
				LinkedListNode<Entry> n;
				if (map.TryGetValue(key, out n))
				{
					lru.Remove(n);
					lru.AddFirst(n);
					Entry e = n.Value;
					ThreadPool.QueueUserWorkItem(delegate { done(e.Bytes, e.Type); });
					return;
				}
				List<Action<byte[], string>> list;
				if (waiting.TryGetValue(key, out list)) { list.Add(done); return; }
				waiting[key] = new List<Action<byte[], string>> { done };
			}
			queue.Add(new Job { Path = path, Key = key, Size = size, Thumb = thumb });
		}

		static void Work()
		{
			foreach (Job j in queue.GetConsumingEnumerable())
			{
				byte[] b = null;
				string type = null;
				try { b = Render(j.Path, j.Size, j.Thumb, out type); }
				catch { b = null; }
				List<Action<byte[], string>> list;
				lock (gate)
				{
					if (b != null && !map.ContainsKey(j.Key))
					{
						LinkedListNode<Entry> n = lru.AddFirst(new Entry { Key = j.Key, Bytes = b, Type = type });
						map[j.Key] = n;
						bytes += b.Length;
						while (bytes > Budget && lru.Last != null)
						{
							Entry old = lru.Last.Value;
							lru.RemoveLast();
							map.Remove(old.Key);
							bytes -= old.Bytes.Length;
						}
					}
					if (!waiting.TryGetValue(j.Key, out list)) list = new List<Action<byte[], string>>();
					waiting.Remove(j.Key);
				}
				foreach (Action<byte[], string> a in list) { try { a(b, type); } catch { } }
			}
		}

		static byte[] Render(string path, int size, bool thumb, out string type)
		{
			type = null;
			size = Math.Max(16, Math.Min(1024, size));
			Native.IShellItemImageFactory f;
			Native.SHCreateItemFromParsingName(path, IntPtr.Zero, typeof(Native.IShellItemImageFactory).GUID, out f);
			IntPtr hbm = IntPtr.Zero;
			try
			{
				Native.SIZE s = new Native.SIZE { cx = size, cy = size };
				int hr = thumb ? f.GetImage(s, Native.SIIGBF_THUMBNAILONLY, out hbm) : -1;
				if (hr != 0 && thumb)
				{
					// No thumbnail from the shell (thumbnails switched off, or no
					// handler): draw common pictures ourselves.
					byte[] own = Picture(path, size, out type);
					if (own != null) return own;
				}
				if (hr != 0) hr = f.GetImage(s, Native.SIIGBF_ICONONLY, out hbm);
				if (hr != 0 || hbm == IntPtr.Zero) return null;
				return Encode(hbm, out type);
			}
			finally
			{
				if (hbm != IntPtr.Zero) Native.DeleteObject(hbm);
				Marshal.ReleaseComObject(f);
			}
		}

		static readonly string[] PICTURES = { ".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tif", ".tiff" };

		// A picture scaled to fit `size`, read with GDI+.
		static byte[] Picture(string path, int size, out string type)
		{
			type = null;
			try
			{
				if (Array.IndexOf(PICTURES, Path.GetExtension(path).ToLowerInvariant()) < 0) return null;
				if (new FileInfo(path).Length > 48L * 1024 * 1024) return null;
				using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
				using (Image img = Image.FromStream(fs, false, false))
				{
					double k = Math.Min(1.0, Math.Min((double)size / img.Width, (double)size / img.Height));
					int w = Math.Max(1, (int)Math.Round(img.Width * k)), h = Math.Max(1, (int)Math.Round(img.Height * k));
					using (Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
					{
						using (Graphics g = Graphics.FromImage(bmp))
						{
							g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
							g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
							g.DrawImage(img, 0, 0, w, h);
						}
						return Save(bmp, !Image.IsAlphaPixelFormat(img.PixelFormat), out type);
					}
				}
			}
			catch { type = null; return null; }
		}

		// The shell's bitmap (32-bit, premultiplied alpha) as a PNG, or a JPEG
		// when it's an opaque picture.
		static byte[] Encode(IntPtr hbm, out string type)
		{
			Native.BITMAP bm = new Native.BITMAP();
			Native.GetObject(hbm, Marshal.SizeOf(typeof(Native.BITMAP)), ref bm);
			int w = bm.bmWidth, h = Math.Abs(bm.bmHeight);
			if (w <= 0 || h <= 0) { type = null; return null; }
			Native.BITMAPINFO bi = new Native.BITMAPINFO();
			bi.biSize = 40;
			bi.biWidth = w;
			bi.biHeight = -h;
			bi.biPlanes = 1;
			bi.biBitCount = 32;
			byte[] px = new byte[w * h * 4];
			IntPtr dc = Native.GetDC(IntPtr.Zero);
			try { Native.GetDIBits(dc, hbm, 0, (uint)h, px, ref bi, 0); }
			finally { Native.ReleaseDC(IntPtr.Zero, dc); }
			bool anyAlpha = false, opaque = true;
			for (int i = 3; i < px.Length; i += 4)
			{
				if (px[i] != 0) anyAlpha = true;
				if (px[i] != 255) opaque = false;
			}
			if (!anyAlpha)
			{
				for (int i = 3; i < px.Length; i += 4) px[i] = 255;
				opaque = true;
			}
			else if (!opaque)
			{
				for (int i = 0; i < px.Length; i += 4)
				{
					int a = px[i + 3];
					if (a == 0 || a == 255) continue;
					px[i] = (byte)Math.Min(255, px[i] * 255 / a);
					px[i + 1] = (byte)Math.Min(255, px[i + 1] * 255 / a);
					px[i + 2] = (byte)Math.Min(255, px[i + 2] * 255 / a);
				}
			}
			using (Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
			{
				BitmapData data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
				for (int y = 0; y < h; y++) Marshal.Copy(px, y * w * 4, new IntPtr(data.Scan0.ToInt64() + (long)y * data.Stride), w * 4);
				bmp.UnlockBits(data);
				return Save(bmp, opaque, out type);
			}
		}

		static byte[] Save(Bitmap bmp, bool opaque, out string type)
		{
			int w = bmp.Width, h = bmp.Height;
			using (MemoryStream ms = new MemoryStream())
			{
				if (opaque && w * h > 96 * 96)
				{
					ImageCodecInfo jpeg = null;
					foreach (ImageCodecInfo c in ImageCodecInfo.GetImageEncoders()) if (c.MimeType == "image/jpeg") jpeg = c;
					EncoderParameters p = new EncoderParameters(1);
					p.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 90L);
					using (Bitmap rgb = bmp.Clone(new Rectangle(0, 0, w, h), PixelFormat.Format24bppRgb)) rgb.Save(ms, jpeg, p);
					type = "image/jpeg";
				}
				else
				{
					bmp.Save(ms, ImageFormat.Png);
					type = "image/png";
				}
				return ms.ToArray();
			}
		}
	}

	// --- A window --------------------------------------------------------------------------

	class FilesWindow : Form
	{
		const int WM_GETMINMAXINFO = 0x24, WM_NCCALCSIZE = 0x83, WM_NCHITTEST = 0x84, WM_DPICHANGED = 0x2E0, WM_MOVE = 0x3, WM_ACTIVATE = 0x6, WM_NCLBUTTONDOWN = 0xA1;
		const int HTCLIENT = 1, HTCAPTION = 2, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14;

		CoreWebView2Controller view;
		bool ready, glass, closing, nativeDrag, active;
		readonly List<object> outbox = new List<object>();
		readonly List<string> launches = new List<string>();
		readonly Dictionary<int, Search> searches = new Dictionary<int, Search>();
		FileSystemWatcher watcher;
		string watched = "";
		System.Windows.Forms.Timer changeTimer;

		public FilesWindow(string path, Rectangle? bounds, bool maximized)
		{
			launches.Add(path ?? "");
			Text = App.Name;
			BackColor = Color.Black;
			FormBorderStyle = FormBorderStyle.Sizable;
			StartPosition = FormStartPosition.Manual;
			KeyPreview = false;
			try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

			Rectangle work = Screen.FromPoint(Cursor.Position).WorkingArea;
			float scale = DpiScale();
			int w = (int)(1180 * scale), h = (int)(740 * scale);
			w = Math.Min(w, work.Width - 40);
			h = Math.Min(h, work.Height - 40);
			Rectangle r = new Rectangle(work.Left + (work.Width - w) / 2, work.Top + (work.Height - h) / 2, w, h);
			if (bounds.HasValue && bounds.Value.Width > 300 && bounds.Value.Height > 200 && Screen.FromRectangle(bounds.Value).WorkingArea.IntersectsWith(bounds.Value))
				r = bounds.Value;
			else if (App.Windows.Count > 0)
				r.Offset((int)(32 * scale * App.Windows.Count), (int)(32 * scale * App.Windows.Count));
			Bounds = r;
			if (maximized) StartMaximized(r);
			MinimumSize = new Size((int)(560 * scale), (int)(360 * scale));
			changeTimer = new System.Windows.Forms.Timer { Interval = 350 };
			changeTimer.Tick += delegate
			{
				changeTimer.Stop();
				Post(Json.Obj("t", "changed", "path", watched));
			};
		}

		static float DpiScale()
		{
			using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) return Math.Max(1f, g.DpiX / 96f);
		}

		public float Scale_ { get { try { return Native.GetDpiForWindow(Handle) / 96f; } catch { return 1f; } } }

		// --- Window frame (the same frame as Oazy Terminal's) -------------------------------

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
			// Tells Oazy's shell this window draws its own title bar, so it leaves
			// the caption colour alone (it would show as a dark strip on the glass).
			Native.SetProp(Handle, "OazyGlass", new IntPtr(1));
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
			ApplyLook();
			RefreshFrame();
			BeginInvoke((Action)delegate { RefreshFrame(); KickFrame(); });
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
					// Activating lifts the window to the front too, so a click on the part of
					// it showing behind another window (a maximized one under a smaller one)
					// always brings it forward, whichever part of it took the click.
					if ((m.WParam.ToInt64() & 0xFFFF) != 0 && WindowState != FormWindowState.Minimized)
						Native.SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010 | 0x0200);
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
			Post(Json.Obj("t", "win", "max", Maximized));
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
			Post(Json.Obj("t", "win", "max", Maximized));
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
			if (IsHandleCreated && WindowState == FormWindowState.Normal && !zoomed && !zooming) lastNormal = Bounds;
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
			closing = true;
			if (App.Windows.Count == 1) SaveBounds();
			base.OnFormClosing(e);
		}

		protected override void OnFormClosed(FormClosedEventArgs e)
		{
			foreach (Search s in searches.Values) s.Cancel();
			searches.Clear();
			Watch("");
			if (view != null) try { view.Close(); } catch { }
			base.OnFormClosed(e);
		}

		void SaveBounds()
		{
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
				MessageBox.Show(this, "Couldn't create the window.\n\n" + ex.Message, App.Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
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
			s.AreDevToolsEnabled = Environment.GetEnvironmentVariable("OAZY_FILES_DEVTOOLS") == "1";
			try { s.AreBrowserAcceleratorKeysEnabled = false; } catch { }
			try { s.IsPinchZoomEnabled = false; } catch { }
			try { s.IsSwipeNavigationEnabled = false; } catch { }
			try { s.IsGeneralAutofillEnabled = false; s.IsPasswordAutosaveEnabled = false; } catch { }
			nativeDrag = false;
			try { s.IsNonClientRegionSupportEnabled = true; nativeDrag = true; } catch { }
			cw.SetVirtualHostNameToFolderMapping(App.UiHost, App.Ui, CoreWebView2HostResourceAccessKind.Allow);
			cw.AddWebResourceRequestedFilter(App.IconHost + "*", CoreWebView2WebResourceContext.All);
			cw.WebResourceRequested += OnResource;
			cw.WebMessageReceived += OnMessage;
			cw.NewWindowRequested += delegate(object o, CoreWebView2NewWindowRequestedEventArgs e) { e.Handled = true; };
			cw.NavigationStarting += delegate(object o, CoreWebView2NavigationStartingEventArgs e)
			{
				if (!e.Uri.StartsWith(App.PageUrl)) e.Cancel = true;
			};
			DoLayout();
			cw.Navigate(App.PageUrl);
		}

		// https://oazy-icons.example/i?p=<path>&s=<px>&k=<key>&th=<0|1>
		void OnResource(object sender, CoreWebView2WebResourceRequestedEventArgs e)
		{
			string path = "", key = "";
			int size = 32;
			bool thumb = false;
			try
			{
				Uri u = new Uri(e.Request.Uri);
				foreach (string part in u.Query.TrimStart('?').Split('&'))
				{
					int eq = part.IndexOf('=');
					if (eq < 0) continue;
					string k = part.Substring(0, eq), v = Uri.UnescapeDataString(part.Substring(eq + 1).Replace('+', ' '));
					if (k == "p") path = v;
					else if (k == "s") int.TryParse(v, out size);
					else if (k == "k") key = v;
					else if (k == "th") thumb = v == "1";
				}
			}
			catch { }
			if (path == "")
			{
				e.Response = App.Env.CreateWebResourceResponse(null, 404, "Not Found", "");
				return;
			}
			if (key == "") key = path;
			CoreWebView2Deferral deferral = e.GetDeferral();
			Icons.Get(path, key + "|" + size + "|" + (thumb ? "t" : "i"), size, thumb, delegate(byte[] bytes, string type)
			{
				App.Sync.Post(delegate
				{
					try
					{
						if (bytes == null) e.Response = App.Env.CreateWebResourceResponse(null, 404, "Not Found", "");
						else e.Response = App.Env.CreateWebResourceResponse(new MemoryStream(bytes), 200, "OK",
							"Content-Type: " + type + "\nCache-Control: max-age=600\nAccess-Control-Allow-Origin: *");
					}
					catch { }
					try { deferral.Complete(); } catch { }
				}, null);
			});
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

		void Reply(int rid, Dictionary<string, object> body)
		{
			body["t"] = "reply";
			body["rid"] = rid;
			Post(body);
		}

		public void OpenTab(string path)
		{
			if (!ready) { launches.Add(path ?? ""); return; }
			Post(Json.Obj("t", "open", "path", path ?? ""));
		}

		void OnMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
		{
			Dictionary<string, object> m;
			try { m = Json.S.DeserializeObject(e.WebMessageAsJson) as Dictionary<string, object>; } catch { return; }
			if (m == null) return;
			List<string> files = new List<string>();
			try
			{
				if (e.AdditionalObjects != null)
					foreach (object o in e.AdditionalObjects)
					{
						CoreWebView2File f = o as CoreWebView2File;
						if (f != null && !string.IsNullOrEmpty(f.Path)) files.Add(f.Path);
					}
			}
			catch { }
			Dispatch(m, files);
		}

		public void Dispatch(Dictionary<string, object> m, List<string> files)
		{
			int rid = Json.Int(m, "rid");
			switch (Json.Str(m, "t"))
			{
				case "ready":
					ready = true;
					{
						List<object> tabs = new List<object>();
						foreach (string l in launches) tabs.Add(l);
						launches.Clear();
						Post(Json.Obj("t", "init", "glass", glass, "accent", App.Accent, "nativeDrag", nativeDrag, "version", App.Version,
							"prefs", App.Prefs, "tabs", tabs.ToArray(), "selftest", App.Test != null));
					}
					foreach (object o in outbox) Post(o);
					outbox.Clear();
					Post(Json.Obj("t", "win", "max", Maximized));
					Post(Json.Obj("t", "active", "on", active));
					FocusPage();
					if (App.Test != null) App.Test.PageReady(this);
					break;
				case "list":
					{
						string path = Json.Str(m, "path");
						App.Background(delegate { return Fs.List(path); }, delegate(object r) { Reply(rid, (Dictionary<string, object>)r); });
					}
					break;
				case "places":
					App.Background(delegate { return Fs.Places(); }, delegate(object r) { Reply(rid, (Dictionary<string, object>)r); });
					break;
				case "recent":
					App.Background(delegate { return Json.Obj("items", Fs.Recent()); }, delegate(object r) { Reply(rid, (Dictionary<string, object>)r); });
					break;
				case "preview":
					{
						string path = Json.Str(m, "path");
						App.Background(delegate { return Fs.Preview(path); }, delegate(object r) { Reply(rid, (Dictionary<string, object>)r); });
					}
					break;
				case "watch": Watch(Json.Str(m, "path")); break;
				case "open": Open(rid, Json.Strs(m, "paths"), Json.Str(m, "verb")); break;
				case "openWith":
					try { Process.Start("rundll32.exe", "shell32.dll,OpenAs_RunDLL " + Json.Str(m, "path")); } catch { }
					break;
				case "rename":
					{
						string path = Json.Str(m, "path"), name = Json.Str(m, "name");
						string err;
						try { err = Fs.Rename(path, name); } catch (Exception ex) { err = ex.Message; }
						Reply(rid, err == null ? Json.Obj("ok", true, "path", Path.Combine(Path.GetDirectoryName(path), name.Trim())) : Json.Obj("ok", false, "error", err));
					}
					break;
				case "mkdir":
				case "newfile":
					{
						bool dir = Json.Str(m, "t") == "mkdir";
						try
						{
							string p = Fs.Unique(Json.Str(m, "dir"), Json.Str(m, "name"), dir);
							if (dir) Directory.CreateDirectory(p);
							else File.WriteAllBytes(p, new byte[0]);
							Reply(rid, Json.Obj("ok", true, "path", p, "name", Path.GetFileName(p)));
						}
						catch (Exception ex) { Reply(rid, Json.Obj("ok", false, "error", ex.Message)); }
					}
					break;
				case "delete":
					{
						string[] paths = Json.Strs(m, "paths");
						bool permanent = Json.Bool(m, "permanent");
						IntPtr h = Handle;
						App.Background(delegate { return Fs.ShellOp(Native.FO_DELETE, paths, null, h, permanent); }, delegate(object r) { Reply(rid, (Dictionary<string, object>)r); });
					}
					break;
				case "transfer":
					{
						string[] paths = Json.Strs(m, "paths");
						string dest = Json.Str(m, "dest");
						bool move = Json.Bool(m, "move");
						Transfer(rid, paths, dest, move);
					}
					break;
				case "drop":
					// Files dragged in from another app (their paths come with the message).
					{
						string dest = Json.Str(m, "dest"), mode = Json.Str(m, "mode");
						// Like Windows Explorer: on the same drive a drop moves, from another it copies.
						bool move = mode == "move";
						if (mode == "auto" && files.Count > 0)
						{
							move = true;
							foreach (string f in files)
								if (!string.Equals(Path.GetPathRoot(f), Path.GetPathRoot(dest), StringComparison.OrdinalIgnoreCase)) move = false;
						}
						Transfer(rid, files.ToArray(), dest, move);
					}
					break;
				case "clipSet": SetClipboard(Json.Strs(m, "paths"), Json.Bool(m, "cut")); break;
				case "clipGet":
					{
						bool cut;
						string[] paths = GetClipboard(out cut);
						Reply(rid, Json.Obj("paths", paths, "cut", cut));
					}
					break;
				case "paste":
					{
						bool cut;
						string[] paths = GetClipboard(out cut);
						if (paths.Length == 0) { Reply(rid, Json.Obj("ok", false, "empty", true)); break; }
						if (cut) { try { Clipboard.Clear(); } catch { } }
						Transfer(rid, paths, Json.Str(m, "dest"), cut);
					}
					break;
				case "copyText": SetClipboardText(Json.Str(m, "text")); break;
				case "props":
					{
						string p = Json.Str(m, "path");
						if (p != "") Native.SHObjectProperties(Handle, 2, p, null);
					}
					break;
				case "terminal": Fs.OpenTerminal(Json.Str(m, "path")); break;
				case "explorer":
					{
						string p = Json.Str(m, "path");
						try
						{
							if (p.StartsWith("shell:")) Process.Start("explorer.exe", p);
							else if (File.Exists(p)) Process.Start("explorer.exe", "/select,\"" + p + "\"");
							else Process.Start("explorer.exe", "\"" + p + "\"");
						}
						catch { }
					}
					break;
				case "extract":
					{
						string zip = Json.Str(m, "path");
						App.Background(delegate { return Json.Obj("ok", true, "path", Fs.Extract(zip)); }, delegate(object r) { Reply(rid, (Dictionary<string, object>)r); });
					}
					break;
				case "compress":
					{
						string[] paths = Json.Strs(m, "paths");
						App.Background(delegate { return Json.Obj("ok", true, "path", Fs.Compress(paths)); }, delegate(object r) { Reply(rid, (Dictionary<string, object>)r); });
					}
					break;
				case "search":
					{
						int sid = Json.Int(m, "sid");
						foreach (Search old in searches.Values) old.Cancel();
						searches.Clear();
						Search s = new Search(sid);
						searches[sid] = s;
						s.Run(Json.Str(m, "root"), Json.Str(m, "q"), Json.Bool(m, "hidden"), this);
					}
					break;
				case "cancelSearch":
					foreach (Search old in searches.Values) old.Cancel();
					searches.Clear();
					break;
				case "dragOut": DragOut(Json.Strs(m, "paths")); break;
				case "title":
					{
						string t = Json.Str(m, "text");
						Text = t == "" ? App.Name : t + " - " + App.Name;
					}
					break;
				case "prefs":
					{
						Dictionary<string, object> p = m.ContainsKey("prefs") ? m["prefs"] as Dictionary<string, object> : null;
						if (p != null)
						{
							foreach (KeyValuePair<string, object> kv in p) App.SetPref(kv.Key, kv.Value);
							foreach (FilesWindow w in App.Windows) if (w != this) w.Post(Json.Obj("t", "prefs", "prefs", p));
						}
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
						case "newWindow": App.OpenWindow(Json.Str(m, "path"), null); break;
					}
					break;
				case "test":
					if (App.Test != null) App.Test.FromPage(this, m);
					break;
			}
		}

		void Transfer(int rid, string[] paths, string dest, bool move)
		{
			if (paths.Length == 0 || dest == "" || !Directory.Exists(dest)) { Reply(rid, Json.Obj("ok", false, "error", "Nothing to paste there")); return; }
			IntPtr h = Handle;
			App.Background(delegate { return Fs.ShellOp(move ? Native.FO_MOVE : Native.FO_COPY, paths, dest, h, false); }, delegate(object r) { Reply(rid, (Dictionary<string, object>)r); });
		}

		// Folders (and shortcuts to folders) open in the page; everything else
		// through the shell like a double-click in Windows Explorer.
		void Open(int rid, string[] paths, string verb)
		{
			foreach (string p in paths)
			{
				if (Directory.Exists(p)) { Reply(rid, Json.Obj("navigate", p)); return; }
				if (p.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase))
				{
					string target = Fs.Shortcut(p);
					if (target != "" && Directory.Exists(target)) { Reply(rid, Json.Obj("navigate", target)); return; }
				}
			}
			foreach (string p in paths)
			{
				string path = p;
				App.Background(delegate
				{
					try
					{
						ProcessStartInfo si = new ProcessStartInfo(path) { UseShellExecute = true };
						try { si.WorkingDirectory = Path.GetDirectoryName(path); } catch { }
						if (verb != "") si.Verb = verb;
						Process.Start(si);
						return Json.Obj("ok", true);
					}
					catch (System.ComponentModel.Win32Exception ex)
					{
						// 1155: nothing opens this kind of file yet, so ask.
						if (ex.NativeErrorCode == 1155) { try { Process.Start("rundll32.exe", "shell32.dll,OpenAs_RunDLL " + path); } catch { } return Json.Obj("ok", true); }
						if (ex.NativeErrorCode == 1223) return Json.Obj("ok", false);
						return Json.Obj("ok", false, "error", ex.Message);
					}
				}, delegate(object r) { Reply(rid, (Dictionary<string, object>)r); });
			}
		}

		void Watch(string path)
		{
			if (path == watched && watcher != null) return;
			if (watcher != null)
			{
				try { watcher.EnableRaisingEvents = false; watcher.Dispose(); } catch { }
				watcher = null;
			}
			watched = path;
			if (path == "" || !Directory.Exists(path)) return;
			try
			{
				FileSystemWatcher w = new FileSystemWatcher(path);
				w.IncludeSubdirectories = false;
				w.NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.Size | NotifyFilters.LastWrite | NotifyFilters.Attributes;
				FileSystemEventHandler h = delegate { Changed(); };
				w.Created += h;
				w.Deleted += h;
				w.Changed += h;
				w.Renamed += delegate { Changed(); };
				w.Error += delegate { Changed(); };
				w.EnableRaisingEvents = true;
				watcher = w;
			}
			catch { }
		}

		void Changed()
		{
			App.Sync.Post(delegate
			{
				if (closing) return;
				changeTimer.Stop();
				changeTimer.Start();
			}, null);
		}

		void DragOut(string[] paths)
		{
			List<string> ok = new List<string>();
			foreach (string p in paths) if (File.Exists(p) || Directory.Exists(p)) ok.Add(p);
			if (ok.Count == 0) { Post(Json.Obj("t", "dragEnd", "effect", 0)); return; }
			DragDropEffects effect = DragDropEffects.None;
			try
			{
				Native.ReleaseCapture();
				DataObject d = new DataObject(DataFormats.FileDrop, ok.ToArray());
				effect = DoDragDrop(d, DragDropEffects.Copy | DragDropEffects.Move | DragDropEffects.Link);
			}
			catch { }
			Post(Json.Obj("t", "dragEnd", "effect", (int)effect));
		}

		static void SetClipboard(string[] paths, bool cut)
		{
			if (paths.Length == 0) return;
			StringCollection sc = new StringCollection();
			sc.AddRange(paths);
			DataObject d = new DataObject();
			d.SetFileDropList(sc);
			d.SetData("Preferred DropEffect", new MemoryStream(BitConverter.GetBytes(cut ? 2 : 5)));
			d.SetText(string.Join("\r\n", paths), TextDataFormat.UnicodeText);
			for (int i = 0; i < 5; i++)
			{
				try { Clipboard.SetDataObject(d, true); return; }
				catch { Thread.Sleep(40); }
			}
		}

		static string[] GetClipboard(out bool cut)
		{
			cut = false;
			for (int i = 0; i < 5; i++)
			{
				try
				{
					IDataObject d = Clipboard.GetDataObject();
					if (d == null || !d.GetDataPresent(DataFormats.FileDrop)) return new string[0];
					string[] files = d.GetData(DataFormats.FileDrop) as string[];
					MemoryStream ms = d.GetData("Preferred DropEffect") as MemoryStream;
					if (ms != null && ms.Length >= 4)
					{
						byte[] b = new byte[4];
						ms.Read(b, 0, 4);
						cut = (BitConverter.ToInt32(b, 0) & 2) != 0;
					}
					return files ?? new string[0];
				}
				catch { Thread.Sleep(40); }
			}
			return new string[0];
		}

		static void SetClipboardText(string text)
		{
			if (string.IsNullOrEmpty(text)) return;
			for (int i = 0; i < 5; i++)
			{
				try { Clipboard.SetText(text, TextDataFormat.UnicodeText); return; }
				catch { Thread.Sleep(40); }
			}
		}
	}

	// --- Self-test: proves Oazy Files works on a real Windows box (CI) ------------------

	class Selftest
	{
		readonly string dir;
		readonly List<string> log = new List<string>();
		public int ExitCode = 1;
		FilesWindow win;
		bool pageOk, listOk, iconOk, opsOk, searchOk, glassOk, done;
		Dictionary<string, object> lastState;
		string root;
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
			timeout.Tick += delegate { Log("timed out"); Finish(); };
			timeout.Start();
			root = Path.Combine(Path.GetTempPath(), "Oazy Files test " + Process.GetCurrentProcess().Id);
			Directory.CreateDirectory(root);
			Directory.CreateDirectory(Path.Combine(root, "Projects"));
			Directory.CreateDirectory(Path.Combine(root, "Holiday photos"));
			File.WriteAllText(Path.Combine(root, "notes.txt"), "Oazy Files self-test\r\nünïcødé ✓ 🌴\r\n");
			File.WriteAllText(Path.Combine(root, "Projects", "readme.md"), "# Deep file\r\n");
			File.WriteAllText(Path.Combine(root, "data.json"), "{\"oazy\": true}");
			for (int i = 0; i < 4; i++)
			{
				using (Bitmap b = new Bitmap(640, 420))
				{
					using (Graphics g = Graphics.FromImage(b))
					using (System.Drawing.Drawing2D.LinearGradientBrush br = new System.Drawing.Drawing2D.LinearGradientBrush(new Rectangle(0, 0, 640, 420),
						Color.FromArgb(30 + i * 40, 160, 200 - i * 30), Color.FromArgb(10, 40 + i * 20, 80), 45f + i * 30))
					{
						g.FillRectangle(br, 0, 0, 640, 420);
						g.FillEllipse(Brushes.White, 420 - i * 60, 60 + i * 20, 120, 120);
					}
					b.Save(Path.Combine(root, "Holiday photos", "beach " + (i + 1) + ".png"), ImageFormat.Png);
					if (i == 0) b.Save(Path.Combine(root, "lagoon.png"), ImageFormat.Png);
				}
			}
			Rectangle work = Screen.PrimaryScreen.WorkingArea;
			Rectangle r = new Rectangle(work.Left + 20, work.Top + 20, Math.Min(1280, work.Width - 40), Math.Min(800, work.Height - 40));
			win = App.OpenWindow(root, r);
		}

		public void PageReady(FilesWindow w) { pageOk = true; Log("page ready"); Run(); }

		public void FromPage(FilesWindow w, Dictionary<string, object> m)
		{
			string what = Json.Str(m, "what");
			if (what == "state") lastState = m;
			else Log("page says " + what + " " + Json.Str(m, "detail"));
		}

		async Task<Dictionary<string, object>> State()
		{
			lastState = null;
			win.Post(Json.Obj("t", "test", "action", "state"));
			for (int i = 0; i < 40 && lastState == null; i++) await Task.Delay(100);
			return lastState;
		}

		static bool Has(Dictionary<string, object> s, string name)
		{
			if (s == null) return false;
			return Array.IndexOf(Json.Strs(s, "names"), name) >= 0;
		}

		async void Run()
		{
			await Task.Delay(2500);
			Dictionary<string, object> s = await State();
			listOk = Has(s, "notes.txt") && Has(s, "Projects") && Has(s, "lagoon.png");
			Log("listing " + (s != null ? string.Join(", ", Json.Strs(s, "names")) : "none"));
			Shot("files-grid.png");

			win.Post(Json.Obj("t", "test", "action", "go", "path", Path.Combine(root, "Holiday photos")));
			await Task.Delay(3000);
			s = await State();
			iconOk = s != null && Json.Int(s, "images") > 0;
			Log("loaded images " + (s != null ? Json.Int(s, "images") : -1));
			Shot("files-thumbnails.png");

			win.Post(Json.Obj("t", "test", "action", "go", "path", root));
			await Task.Delay(1200);
			win.Post(Json.Obj("t", "test", "action", "view", "view", "list"));
			win.Post(Json.Obj("t", "test", "action", "select", "name", "notes.txt"));
			await Task.Delay(1500);
			Shot("files-list.png");

			// File operations, through the same messages the page sends.
			win.Dispatch(Json.Obj("t", "rename", "rid", 0, "path", Path.Combine(root, "notes.txt"), "name", "renamed.txt"), new List<string>());
			win.Dispatch(Json.Obj("t", "mkdir", "rid", 0, "dir", root, "name", "New folder"), new List<string>());
			win.Dispatch(Json.Obj("t", "transfer", "rid", 0, "paths", new object[] { Path.Combine(root, "data.json") }, "dest", Path.Combine(root, "Projects"), "move", false), new List<string>());
			await Task.Delay(2500);
			win.Dispatch(Json.Obj("t", "delete", "rid", 0, "paths", new object[] { Path.Combine(root, "lagoon.png") }, "permanent", true), new List<string>());
			await Task.Delay(2500);
			bool renamed = File.Exists(Path.Combine(root, "renamed.txt")) && !File.Exists(Path.Combine(root, "notes.txt"));
			bool made = Directory.Exists(Path.Combine(root, "New folder"));
			bool copied = File.Exists(Path.Combine(root, "Projects", "data.json")) && File.Exists(Path.Combine(root, "data.json"));
			bool deleted = !File.Exists(Path.Combine(root, "lagoon.png"));
			s = await State();
			bool live = s != null && Has(s, "renamed.txt") && !Has(s, "lagoon.png");
			opsOk = renamed && made && copied && deleted;
			Log("rename " + renamed + ", mkdir " + made + ", copy " + copied + ", delete " + deleted + ", view updated " + live);

			win.Post(Json.Obj("t", "test", "action", "view", "view", "grid"));
			win.Post(Json.Obj("t", "test", "action", "search", "q", "readme"));
			await Task.Delay(2500);
			s = await State();
			searchOk = Has(s, "readme.md");
			Log("search " + searchOk);
			Shot("files-search.png");

			win.Post(Json.Obj("t", "test", "action", "clearSearch"));
			win.Post(Json.Obj("t", "test", "action", "menu"));
			await Task.Delay(1200);
			Shot("files-menu.png");
			win.Post(Json.Obj("t", "test", "action", "closeMenu"));
			win.Post(Json.Obj("t", "test", "action", "go", "path", ""));
			await Task.Delay(2500);
			Shot("files-home.png");

			// Maximized (as Windows does it, e.g. Win+Up): Oazy takes over and the
			// window fills exactly the work area, with even glass along the top.
			Rectangle normal = win.Bounds;
			win.WindowState = FormWindowState.Maximized;
			await Task.Delay(1500);
			Shot("files-max.png");
			Rectangle wa = Screen.FromHandle(win.Handle).WorkingArea;
			bool flush = win.Maximized && win.WindowState == FormWindowState.Normal && win.Bounds == wa;
			int diff = TopDiff("files-max.png");
			Log("maximized " + win.Maximized + ", bounds " + win.Bounds + " vs work area " + wa + ", top vs strip " + diff);
			win.SetMaximized(false);
			await Task.Delay(1500);
			Shot("files-restored.png");
			int back = TopDiff("files-restored.png");
			bool restored = !win.Maximized && win.Bounds == normal;
			Log("restored to " + win.Bounds + " (was " + normal + "), top vs strip " + back);
			glassOk = flush && restored && diff >= 0 && diff < 30 && back >= 0 && back < 30;
			Finish();
		}

		public void Exited()
		{
			Log("message loop ended, exiting with " + ExitCode);
			try { File.WriteAllLines(Path.Combine(dir, "files-selftest.log"), log.ToArray()); } catch { }
			try { Directory.Delete(root, true); } catch { }
		}

		// How far the very top of the tab strip is from its lower part, in the
		// empty space right of the tabs (-1 if the shot can't be read).
		int TopDiff(string name)
		{
			try
			{
				using (Bitmap bmp = new Bitmap(Path.Combine(dir, name)))
				{
					int x = bmp.Width * 6 / 10, dy = 0;
					float k = win.Scale_;
					Color top = bmp.GetPixel(x, dy + (int)(8 * k)), low = bmp.GetPixel(x, dy + (int)(36 * k));
					return Math.Abs(top.R - low.R) + Math.Abs(top.G - low.G) + Math.Abs(top.B - low.B);
				}
			}
			catch (Exception e) { Log("glass check failed: " + e.Message); return -1; }
		}

		void Shot(string name)
		{
			try
			{
				Rectangle b = win.Bounds;
				using (Bitmap bmp = new Bitmap(b.Width, b.Height))
				{
					using (Graphics g = Graphics.FromImage(bmp)) g.CopyFromScreen(b.Location, Point.Empty, b.Size);
					bmp.Save(Path.Combine(dir, name), ImageFormat.Png);
				}
				Log("saved " + name);
			}
			catch (Exception e) { Log("screenshot failed: " + e.Message); }
		}

		void Finish()
		{
			if (done) return;
			done = true;
			ExitCode = pageOk && listOk && iconOk && opsOk && searchOk && glassOk ? 0 : 1;
			Log("page=" + pageOk + " list=" + listOk + " icons=" + iconOk + " ops=" + opsOk + " search=" + searchOk + " glass=" + glassOk + " -> " + (ExitCode == 0 ? "PASS" : "FAIL"));
			try { File.WriteAllLines(Path.Combine(dir, "files-selftest.log"), log.ToArray()); } catch { }
			App.Quit();
		}
	}
}
