// Oazy host: a small native companion process for the Oazy shell.
//
// Godot has no FFI, so everything that needs Win32 lives here: listing the
// real application windows (like Alt+Tab does), focusing / minimising /
// closing them, live DWM thumbnails drawn into Oazy's window, app icons,
// the list of installed apps, system stats and the global "home" hotkey.
//
// Oazy compiles this file on first run with the C# compiler that ships with
// every Windows 10/11 (.NET Framework 4.x csc.exe), so it must stay C# 5.
//
// Protocol: one request per stdin line, "<id>\t<command>\t<arg>...".
// Replies are one JSON object per stdout line: {"id":N,"ok":true,...}.
// Unprompted events are {"ev":"windows"|"hotkey"|...,...}.
// The process exits when stdin closes or when Oazy (the parent pid) is gone.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Security;
using System.Text;
using System.Threading;

namespace Oazy
{
	static class Native
	{
		public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
		public delegate void WinEventProc(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);

		[StructLayout(LayoutKind.Sequential)]
		public struct RECT { public int Left, Top, Right, Bottom; }

		[StructLayout(LayoutKind.Sequential)]
		public struct SIZE { public int cx, cy; }

		[StructLayout(LayoutKind.Sequential)]
		public struct POINT { public int x, y; }

		[StructLayout(LayoutKind.Sequential)]
		public struct MONITORINFO
		{
			public int cbSize;
			public RECT rcMonitor;
			public RECT rcWork;
			public uint dwFlags;
		}

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
			public uint biSize;
			public int biWidth, biHeight;
			public ushort biPlanes, biBitCount;
			public uint biCompression, biSizeImage;
			public int biXPelsPerMeter, biYPelsPerMeter;
			public uint biClrUsed, biClrImportant;
			[MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)] public uint[] colors;
		}

		[StructLayout(LayoutKind.Sequential)]
		public struct MSG
		{
			public IntPtr hwnd;
			public uint message;
			public IntPtr wParam;
			public IntPtr lParam;
			public uint time;
			public POINT pt;
		}

		[StructLayout(LayoutKind.Sequential)]
		public struct DWM_THUMBNAIL_PROPERTIES
		{
			public int dwFlags;
			public RECT rcDestination;
			public RECT rcSource;
			public byte opacity;
			public bool fVisible;
			public bool fSourceClientAreaOnly;
		}

		[StructLayout(LayoutKind.Sequential)]
		public struct FILETIME { public uint Low, High; }

		[StructLayout(LayoutKind.Sequential)]
		public struct MEMORYSTATUSEX
		{
			public uint dwLength;
			public uint dwMemoryLoad;
			public ulong ullTotalPhys;
			public ulong ullAvailPhys;
			public ulong ullTotalPageFile;
			public ulong ullAvailPageFile;
			public ulong ullTotalVirtual;
			public ulong ullAvailVirtual;
			public ulong ullAvailExtendedVirtual;
		}

		[StructLayout(LayoutKind.Sequential)]
		public struct SYSTEM_POWER_STATUS
		{
			public byte ACLineStatus;
			public byte BatteryFlag;
			public byte BatteryLifePercent;
			public byte SystemStatusFlag;
			public int BatteryLifeTime;
			public int BatteryFullLifeTime;
		}

		[StructLayout(LayoutKind.Sequential, Pack = 4)]
		public struct PROPERTYKEY { public Guid fmtid; public uint pid; }

		[StructLayout(LayoutKind.Explicit)]
		public struct PROPVARIANT
		{
			[FieldOffset(0)] public ushort vt;
			[FieldOffset(8)] public IntPtr p;
			[FieldOffset(16)] public IntPtr pad;
		}

		[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
		public interface IPropertyStore
		{
			[PreserveSig] int GetCount(out uint count);
			[PreserveSig] int GetAt(uint index, out PROPERTYKEY key);
			[PreserveSig] int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
			[PreserveSig] int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
			[PreserveSig] int Commit();
		}

		[ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
		public interface IShellItemImageFactory
		{
			[PreserveSig] int GetImage(SIZE size, int flags, out IntPtr hbitmap);
		}

		[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
		[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
		[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
		[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
		[DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
		[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
		[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
		[DllImport("user32.dll", EntryPoint = "GetWindowLongW")] public static extern int GetWindowLong(IntPtr h, int index);
		[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
		[DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
		[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
		[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
		[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
		[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
		[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
		[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
		[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
		[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
		[DllImport("user32.dll", EntryPoint = "GetClassLongPtrW")] public static extern IntPtr GetClassLongPtr64(IntPtr h, int index);
		[DllImport("user32.dll", EntryPoint = "GetClassLongW")] public static extern uint GetClassLong32(IntPtr h, int index);
		[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
		[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
		[DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
		[DllImport("user32.dll")] public static extern int GetMessage(out MSG msg, IntPtr h, uint min, uint max);
		[DllImport("user32.dll")] public static extern bool TranslateMessage(ref MSG msg);
		[DllImport("user32.dll")] public static extern IntPtr DispatchMessage(ref MSG msg);
		[DllImport("user32.dll")] public static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr module, WinEventProc proc, uint pid, uint thread, uint flags);
		[DllImport("user32.dll")] public static extern bool LockWorkStation();
		[DllImport("user32.dll", EntryPoint = "SetWindowLongW")] public static extern int SetWindowLong(IntPtr h, int index, int value);
		[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
		[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
		[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
		[DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint action, uint param, ref RECT rect, uint winIni);
		[DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
		[DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr mon, ref MONITORINFO info);
		[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
		[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
		[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
		[DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
		[DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
		[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool QueryFullProcessImageName(IntPtr h, int flags, StringBuilder sb, ref int size);
		[DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out FILETIME idle, out FILETIME kernel, out FILETIME user);
		[DllImport("kernel32.dll")] public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX status);
		[DllImport("kernel32.dll")] public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS status);
		[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int value, int size);
		[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT value, int size);
		[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
		[DllImport("dwmapi.dll")] public static extern int DwmRegisterThumbnail(IntPtr dest, IntPtr src, out IntPtr thumb);
		[DllImport("dwmapi.dll")] public static extern int DwmUnregisterThumbnail(IntPtr thumb);
		[DllImport("dwmapi.dll")] public static extern int DwmUpdateThumbnailProperties(IntPtr thumb, ref DWM_THUMBNAIL_PROPERTIES props);
		[DllImport("dwmapi.dll")] public static extern int DwmQueryThumbnailSourceSize(IntPtr thumb, out SIZE size);
		[DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr h);
		[DllImport("gdi32.dll")] public static extern int GetObject(IntPtr h, int size, ref BITMAP bm);
		[DllImport("gdi32.dll")] public static extern int GetDIBits(IntPtr hdc, IntPtr hbm, uint start, uint lines, [Out] byte[] bits, ref BITMAPINFO info, uint usage);
		[DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
		[DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
		[DllImport("shell32.dll")] public static extern int SHGetPropertyStoreForWindow(IntPtr h, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
		[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SHCreateItemFromParsingName(string path, IntPtr bindCtx, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory factory);
		[DllImport("ole32.dll")] public static extern int PropVariantClear(ref PROPVARIANT pv);
		[DllImport("powrprof.dll")] public static extern bool SetSuspendState(bool hibernate, bool force, bool disableWake);
	}

	static class Json
	{
		public static string Str(string s)
		{
			if (s == null) return "\"\"";
			StringBuilder sb = new StringBuilder(s.Length + 2);
			sb.Append('"');
			foreach (char c in s)
			{
				switch (c)
				{
					case '"': sb.Append("\\\""); break;
					case '\\': sb.Append("\\\\"); break;
					case '\n': sb.Append("\\n"); break;
					case '\r': sb.Append("\\r"); break;
					case '\t': sb.Append("\\t"); break;
					default:
						if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
						else sb.Append(c);
						break;
				}
			}
			sb.Append('"');
			return sb.ToString();
		}

		public static string Bool(bool b) { return b ? "true" : "false"; }
	}

	static class Host
	{
		const int GWL_EXSTYLE = -20;
		const int WS_EX_TOOLWINDOW = 0x80;
		const int WS_EX_APPWINDOW = 0x40000;
		const int WS_EX_NOACTIVATE = 0x8000000;
		const uint GW_OWNER = 4;
		const uint GA_ROOT = 2;
		const int DWMWA_CLOAKED = 14;
		const uint WM_CLOSE = 0x10;
		const uint WM_GETICON = 0x7F;
		const uint WM_HOTKEY = 0x312;
		const int SW_MAXIMIZE = 3;
		const int SW_MINIMIZE = 6;
		const int SW_RESTORE = 9;
		const uint SMTO_ABORTIFHUNG = 2;
		const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
		const uint MOD_ALT = 1, MOD_CONTROL = 2, MOD_NOREPEAT = 0x4000;
		const int SIIGBF_ICONONLY = 4;
		const int SW_HIDE = 0;
		const int SW_SHOWMINNOACTIVE = 7;
		const int SW_SHOWNA = 8;
		const uint SWP_NOSIZE = 0x1, SWP_NOMOVE = 0x2, SWP_NOACTIVATE = 0x10, SWP_FRAMECHANGED = 0x20, SWP_NOOWNERZORDER = 0x200;
		const uint SPI_GETWORKAREA = 0x30, SPI_SETWORKAREA = 0x2F, SPIF_SENDCHANGE = 0x2;
		const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
		const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
		const int DWMWA_BORDER_COLOR = 34, DWMWA_CAPTION_COLOR = 35, DWMWA_TEXT_COLOR = 36;
		const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
		const int DWM_COLOR_DEFAULT = unchecked((int)0xFFFFFFFF);
		const int DWM_COLOR_NONE = unchecked((int)0xFFFFFFFE);

		static readonly object OutLock = new object();
		static readonly object CacheLock = new object();
		static StreamWriter Out;
		static IntPtr Self = IntPtr.Zero;
		static int ParentPid;
		static volatile bool Dirty;
		static int Ticking;
		static Native.WinEventProc HookProc;
		static Timer Ticker;
		static readonly Dictionary<long, IntPtr> Thumbs = new Dictionary<long, IntPtr>();
		static readonly Dictionary<string, string> Descriptions = new Dictionary<string, string>();
		static readonly Dictionary<long, string> Aumids = new Dictionary<long, string>();
		static ulong LastIdle, LastBusy;
		static Native.PROPERTYKEY PKEY_AppUserModel_ID;

		// Shell mode: Oazy is the desktop. These remember what we changed so it
		// can all be put back, even after a crash (see RestorePath).
		static readonly object ShellLock = new object();
		static bool ShellOn;
		static IntPtr Desktop = IntPtr.Zero;
		static bool HideTray;
		static bool TrayHidden;
		static readonly List<IntPtr> HiddenDesktop = new List<IntPtr>();
		static Native.RECT OrigWork, ShellWork;
		static bool WorkSaved, WorkSet;
		static readonly List<IntPtr> Peeked = new List<IntPtr>();
		static bool ThemeOn;
		static int ThemeBorder, ThemeCaption, ThemeText;
		static readonly Dictionary<long, int> Themed = new Dictionary<long, int>();
		static string RestorePath = "";

		[STAThread, HandleProcessCorruptedStateExceptions, SecurityCritical]
		static int Main(string[] args)
		{
			try { Native.SetProcessDpiAwarenessContext(new IntPtr(-4)); }
			catch (Exception) { try { Native.SetProcessDPIAware(); } catch (Exception) { } }
			if (args.Length > 0) int.TryParse(args[0], out ParentPid);
			PKEY_AppUserModel_ID.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
			PKEY_AppUserModel_ID.pid = 5;

			try { RestorePath = Path.Combine(Path.GetDirectoryName(Assembly.GetEntryAssembly().Location), "shell-restore.txt"); }
			catch (Exception) { RestorePath = ""; }
			RecoverStale();

			Out = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false));
			Out.AutoFlush = true;
			Out.NewLine = "\n";
			StreamReader input = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false));

			Thread loop = new Thread(MessageLoop);
			loop.IsBackground = true;
			loop.Start();
			Thread watchdog = new Thread(Watchdog);
			watchdog.IsBackground = true;
			watchdog.Start();
			Ticker = new Timer(Tick, null, 200, 140);

			string line;
			while ((line = input.ReadLine()) != null)
			{
				if (line.Length == 0) continue;
				string[] p = line.Split('\t');
				string reply;
				try { reply = Handle(p); }
				catch (Exception ex) { reply = "\"ok\":false,\"error\":" + Json.Str(ex.Message); }
				Write("{\"id\":" + Num(p[0]) + "," + reply + "}");
			}
			ClearThumbs();
			ExitShell();
			return 0;
		}

		static string Num(string s)
		{
			long v;
			return long.TryParse(s, out v) ? v.ToString() : "0";
		}

		static void Write(string json)
		{
			lock (OutLock)
			{
				try { Out.WriteLine(json); }
				catch (Exception) { Environment.Exit(0); }
			}
		}

		static IntPtr H(string s)
		{
			long v;
			long.TryParse(s, out v);
			return new IntPtr(v);
		}

		static string Arg(string[] p, int i) { return i < p.Length ? p[i] : ""; }

		static int Int(string s, int fallback)
		{
			int v;
			return int.TryParse(s, out v) ? v : fallback;
		}

		static string Handle(string[] p)
		{
			string cmd = Arg(p, 1);
			switch (cmd)
			{
				case "hello":
					Self = H(Arg(p, 2));
					return "\"ok\":true,\"v\":1";
				case "windows":
					return "\"ok\":true," + WindowsJson();
				case "focus":
					return "\"ok\":" + Json.Bool(Focus(H(Arg(p, 2))));
				case "toggle":
				{
					IntPtr h = H(Arg(p, 2));
					if (Native.GetForegroundWindow() == h && !Native.IsIconic(h))
					{
						Native.ShowWindow(h, SW_MINIMIZE);
						return "\"ok\":true,\"action\":\"minimize\"";
					}
					return "\"ok\":" + Json.Bool(Focus(h)) + ",\"action\":\"focus\"";
				}
				case "minimize":
					return "\"ok\":" + Json.Bool(Native.ShowWindow(H(Arg(p, 2)), SW_MINIMIZE));
				case "maximize":
					return "\"ok\":" + Json.Bool(Native.ShowWindow(H(Arg(p, 2)), SW_MAXIMIZE));
				case "restore":
					return "\"ok\":" + Json.Bool(Native.ShowWindow(H(Arg(p, 2)), SW_RESTORE));
				case "close":
					return "\"ok\":" + Json.Bool(Native.PostMessage(H(Arg(p, 2)), WM_CLOSE, IntPtr.Zero, IntPtr.Zero));
				case "home":
					return "\"ok\":" + Json.Bool(Self != IntPtr.Zero && Focus(Self));
				case "icon":
				{
					string error;
					bool saved = SaveIcon(Arg(p, 2), Int(Arg(p, 3), 96), Arg(p, 4), out error);
					return "\"ok\":" + Json.Bool(saved) + (saved ? "" : ",\"error\":" + Json.Str(error));
				}
				case "apps":
					return "\"ok\":true,\"apps\":" + AppsJson();
				case "thumb":
					return Thumb(H(Arg(p, 2)), Int(Arg(p, 3), 0), Int(Arg(p, 4), 0), Int(Arg(p, 5), 0), Int(Arg(p, 6), 0), Int(Arg(p, 7), 255), H(Arg(p, 8)));
				case "shell":
					return EnterShell(H(Arg(p, 2)), Int(Arg(p, 3), 0), Arg(p, 4) == "1");
				case "unshell":
					ExitShell();
					return "\"ok\":true";
				case "style":
					return Style(H(Arg(p, 2)), Arg(p, 3));
				case "theme":
					return Theme(Arg(p, 2) == "1", Int(Arg(p, 3), 0), Int(Arg(p, 4), 0), Int(Arg(p, 5), 0));
				case "show_desktop":
					return ShowDesktop();
				case "thumb_clear":
					ClearThumbs();
					return "\"ok\":true";
				case "stats":
					return "\"ok\":true," + StatsJson();
				case "lock":
					return "\"ok\":" + Json.Bool(Native.LockWorkStation());
				case "sleep":
					return "\"ok\":" + Json.Bool(Native.SetSuspendState(false, false, false));
				case "ping":
					return "\"ok\":true";
			}
			return "\"ok\":false,\"error\":\"unknown command\"";
		}

		// --- Windows -------------------------------------------------------------

		static bool IsAppWindow(IntPtr h, uint pid)
		{
			if (h == Self || !Native.IsWindowVisible(h)) return false;
			if (ParentPid != 0 && pid == (uint)ParentPid) return false;
			int ex = Native.GetWindowLong(h, GWL_EXSTYLE);
			bool app = (ex & WS_EX_APPWINDOW) != 0;
			if (!app && (ex & WS_EX_TOOLWINDOW) != 0) return false;
			if (!app && (ex & WS_EX_NOACTIVATE) != 0) return false;
			if (!app && Native.GetWindow(h, GW_OWNER) != IntPtr.Zero) return false;
			int cloaked;
			if (Native.DwmGetWindowAttribute(h, DWMWA_CLOAKED, out cloaked, 4) == 0 && cloaked != 0) return false;
			if (Native.GetWindowTextLength(h) == 0) return false;
			string cls = ClassName(h);
			if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd") return false;
			return true;
		}

		static string ClassName(IntPtr h)
		{
			StringBuilder sb = new StringBuilder(256);
			Native.GetClassName(h, sb, sb.Capacity);
			return sb.ToString();
		}

		static string Title(IntPtr h)
		{
			int n = Native.GetWindowTextLength(h);
			StringBuilder sb = new StringBuilder(n + 2);
			Native.GetWindowText(h, sb, sb.Capacity);
			return sb.ToString();
		}

		static string ExePath(uint pid)
		{
			IntPtr proc = Native.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
			if (proc == IntPtr.Zero) return "";
			try
			{
				StringBuilder sb = new StringBuilder(1024);
				int size = sb.Capacity;
				return Native.QueryFullProcessImageName(proc, 0, sb, ref size) ? sb.ToString() : "";
			}
			finally { Native.CloseHandle(proc); }
		}

		static string Description(string exe)
		{
			if (exe == "") return "";
			lock (CacheLock)
			{
				string d;
				if (Descriptions.TryGetValue(exe, out d)) return d;
			}
			string desc = "";
			try
			{
				FileVersionInfo info = FileVersionInfo.GetVersionInfo(exe);
				desc = (info.FileDescription ?? "").Trim();
				if (desc == "") desc = (info.ProductName ?? "").Trim();
			}
			catch (Exception) { }
			lock (CacheLock) { Descriptions[exe] = desc; }
			return desc;
		}

		static string Aumid(IntPtr h)
		{
			long key = h.ToInt64();
			lock (CacheLock)
			{
				string cached;
				if (Aumids.TryGetValue(key, out cached)) return cached;
			}
			string id = "";
			Native.IPropertyStore store = null;
			try
			{
				Guid iid = typeof(Native.IPropertyStore).GUID;
				if (Native.SHGetPropertyStoreForWindow(h, ref iid, out store) == 0 && store != null)
				{
					Native.PROPVARIANT pv;
					Native.PROPERTYKEY k = PKEY_AppUserModel_ID;
					if (store.GetValue(ref k, out pv) == 0)
					{
						if (pv.vt == 31 && pv.p != IntPtr.Zero) id = Marshal.PtrToStringUni(pv.p);
						Native.PropVariantClear(ref pv);
					}
				}
			}
			catch (Exception) { }
			finally { if (store != null) Marshal.ReleaseComObject(store); }
			lock (CacheLock) { Aumids[key] = id ?? ""; }
			return id ?? "";
		}

		static string WindowsJson()
		{
			IntPtr fg = Native.GetForegroundWindow();
			List<string> list = new List<string>();
			HashSet<long> alive = new HashSet<long>();
			Native.EnumWindows(delegate(IntPtr h, IntPtr l)
			{
				uint pid;
				Native.GetWindowThreadProcessId(h, out pid);
				if (!IsAppWindow(h, pid)) return true;
				alive.Add(h.ToInt64());
				string exe = ExePath(pid);
				string file = Path.GetFileName(exe).ToLowerInvariant();
				string name = file == "applicationframehost.exe" ? "" : Description(exe);
				list.Add("{\"hwnd\":" + h.ToInt64()
					+ ",\"title\":" + Json.Str(Title(h))
					+ ",\"pid\":" + pid
					+ ",\"exe\":" + Json.Str(exe)
					+ ",\"name\":" + Json.Str(name)
					+ ",\"aumid\":" + Json.Str(Aumid(h))
					+ ",\"class\":" + Json.Str(ClassName(h))
					+ ",\"min\":" + Json.Bool(Native.IsIconic(h))
					+ ",\"max\":" + Json.Bool(Native.IsZoomed(h))
					+ "}");
				return true;
			}, IntPtr.Zero);
			lock (CacheLock)
			{
				List<long> gone = new List<long>();
				foreach (long k in Aumids.Keys) if (!alive.Contains(k)) gone.Add(k);
				foreach (long k in gone) Aumids.Remove(k);
			}
			ThemeWindows(alive);
			uint fgPid;
			Native.GetWindowThreadProcessId(fg, out fgPid);
			bool selfFg = fg != IntPtr.Zero && ((fg == Self && Self != IntPtr.Zero) || (ParentPid != 0 && fgPid == (uint)ParentPid));
			return "\"windows\":[" + string.Join(",", list.ToArray()) + "],\"fg\":" + fg.ToInt64() + ",\"self_fg\":" + Json.Bool(selfFg)
				+ ",\"fs\":" + Json.Bool(!selfFg && IsFullscreen(fg));
		}

		static bool Focus(IntPtr h)
		{
			if (h == IntPtr.Zero || !Native.IsWindow(h)) return false;
			if (Native.IsIconic(h)) Native.ShowWindow(h, SW_RESTORE);
			if (Native.SetForegroundWindow(h) && Native.GetForegroundWindow() == h) return true;
			// Windows only lets the process that received the last input steal the
			// foreground. Attach to the current foreground thread and tap Alt, the
			// long-standing way shells and launchers get permission.
			IntPtr fg = Native.GetForegroundWindow();
			uint ignored;
			uint fgThread = Native.GetWindowThreadProcessId(fg, out ignored);
			uint me = Native.GetCurrentThreadId();
			bool attached = fgThread != 0 && fgThread != me && Native.AttachThreadInput(me, fgThread, true);
			Native.keybd_event(0x12, 0, 0, UIntPtr.Zero);
			Native.keybd_event(0x12, 0, 2, UIntPtr.Zero);
			Native.BringWindowToTop(h);
			Native.SetForegroundWindow(h);
			if (attached) Native.AttachThreadInput(me, fgThread, false);
			return Native.GetForegroundWindow() == h;
		}

		// --- Live thumbnails -------------------------------------------------------

		static string Thumb(IntPtr src, int x, int y, int w, int hgt, int opacity, IntPtr dest)
		{
			if (dest == IntPtr.Zero) dest = Self;
			if (dest == IntPtr.Zero || src == IntPtr.Zero || w <= 0 || hgt <= 0) return "\"ok\":false";
			IntPtr thumb;
			lock (Thumbs)
			{
				if (!Thumbs.TryGetValue(src.ToInt64(), out thumb))
				{
					if (Native.DwmRegisterThumbnail(dest, src, out thumb) != 0) return "\"ok\":false";
					Thumbs[src.ToInt64()] = thumb;
				}
			}
			Native.SIZE s;
			Native.DwmQueryThumbnailSourceSize(thumb, out s);
			int dw = w, dh = hgt;
			if (s.cx > 0 && s.cy > 0)
			{
				double scale = Math.Min((double)w / s.cx, (double)hgt / s.cy);
				dw = Math.Max(1, (int)(s.cx * scale));
				dh = Math.Max(1, (int)(s.cy * scale));
			}
			Native.DWM_THUMBNAIL_PROPERTIES props = new Native.DWM_THUMBNAIL_PROPERTIES();
			props.dwFlags = 0x1 | 0x4 | 0x8 | 0x10;
			props.rcDestination.Left = x + (w - dw) / 2;
			props.rcDestination.Top = y + (hgt - dh) / 2;
			props.rcDestination.Right = props.rcDestination.Left + dw;
			props.rcDestination.Bottom = props.rcDestination.Top + dh;
			props.opacity = (byte)Math.Max(0, Math.Min(255, opacity));
			props.fVisible = true;
			props.fSourceClientAreaOnly = false;
			int hr = Native.DwmUpdateThumbnailProperties(thumb, ref props);
			return "\"ok\":" + Json.Bool(hr == 0) + ",\"x\":" + props.rcDestination.Left + ",\"y\":" + props.rcDestination.Top
				+ ",\"w\":" + dw + ",\"h\":" + dh + ",\"src_w\":" + s.cx + ",\"src_h\":" + s.cy;
		}

		static void ClearThumbs()
		{
			lock (Thumbs)
			{
				foreach (IntPtr t in Thumbs.Values) Native.DwmUnregisterThumbnail(t);
				Thumbs.Clear();
			}
		}

		// --- Icons -----------------------------------------------------------------

		// Shell icon handlers are third-party code running in this process, so a
		// bad one can fault; catch that too rather than taking the companion down.
		[HandleProcessCorruptedStateExceptions, SecurityCritical]
		static bool SaveIcon(string key, int size, string outPath, out string error)
		{
			error = "";
			if (key == "" || outPath == "") { error = "missing arguments"; return false; }
			size = Math.Max(16, Math.Min(256, size));
			if (!key.StartsWith("shell:", StringComparison.OrdinalIgnoreCase) && !key.StartsWith("hwnd:")) key = key.Replace('/', '\\');
			outPath = outPath.Replace('/', '\\');
			Bitmap bmp = null;
			try
			{
				if (key.StartsWith("hwnd:")) bmp = WindowIcon(H(key.Substring(5)));
				else bmp = ShellImage(key, size, out error);
				if (bmp == null && File.Exists(key))
				{
					using (Icon ic = Icon.ExtractAssociatedIcon(key)) { if (ic != null) bmp = ic.ToBitmap(); }
				}
				if (bmp == null) { if (error == "") error = "no icon"; return false; }
				using (Bitmap fitted = Fit(bmp, size))
				{
					string dir = Path.GetDirectoryName(outPath);
					if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
					string tmp = outPath + ".tmp";
					fitted.Save(tmp, ImageFormat.Png);
					if (File.Exists(outPath)) File.Delete(outPath);
					File.Move(tmp, outPath);
				}
				return true;
			}
			catch (Exception ex) { error = ex.GetType().Name + ": " + ex.Message; return false; }
			finally { if (bmp != null) bmp.Dispose(); }
		}

		[HandleProcessCorruptedStateExceptions, SecurityCritical]
		static Bitmap ShellImage(string path, int size, out string error)
		{
			error = "";
			Native.IShellItemImageFactory factory = null;
			try
			{
				Guid iid = typeof(Native.IShellItemImageFactory).GUID;
				int hr = Native.SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out factory);
				if (hr != 0 || factory == null) { error = string.Format("shell item 0x{0:X8}", hr); return null; }
				Native.SIZE s;
				s.cx = size;
				s.cy = size;
				IntPtr hbm;
				hr = factory.GetImage(s, SIIGBF_ICONONLY, out hbm);
				if (hr != 0 || hbm == IntPtr.Zero) { error = string.Format("image 0x{0:X8}", hr); return null; }
				try { return FromHBitmap(hbm); }
				finally { Native.DeleteObject(hbm); }
			}
			catch (Exception ex) { error = ex.GetType().Name + ": " + ex.Message; return null; }
			finally { if (factory != null) Marshal.ReleaseComObject(factory); }
		}

		// Reads a shell HBITMAP into a managed copy. Shell bitmaps are 32-bit with
		// premultiplied alpha (Image.FromHbitmap drops it), so un-premultiply here.
		static Bitmap FromHBitmap(IntPtr hbm)
		{
			Native.BITMAP bm = new Native.BITMAP();
			if (Native.GetObject(hbm, Marshal.SizeOf(typeof(Native.BITMAP)), ref bm) == 0) return null;
			int w = bm.bmWidth, h = Math.Abs(bm.bmHeight);
			if (w <= 0 || h <= 0 || w > 1024 || h > 1024) return null;
			Native.BITMAPINFO info = new Native.BITMAPINFO();
			info.biSize = 40;
			info.biWidth = w;
			info.biHeight = -h;
			info.biPlanes = 1;
			info.biBitCount = 32;
			info.colors = new uint[256];
			byte[] px = new byte[w * h * 4];
			IntPtr dc = Native.GetDC(IntPtr.Zero);
			int lines;
			try { lines = Native.GetDIBits(dc, hbm, 0, (uint)h, px, ref info, 0); }
			finally { Native.ReleaseDC(IntPtr.Zero, dc); }
			if (lines != h) return null;
			bool hasAlpha = false;
			for (int i = 3; i < px.Length; i += 4)
			{
				if (px[i] != 0) { hasAlpha = true; break; }
			}
			for (int i = 0; i < px.Length; i += 4)
			{
				int a = px[i + 3];
				if (!hasAlpha) { px[i + 3] = 255; continue; }
				if (a == 0 || a == 255) continue;
				px[i] = (byte)Math.Min(255, px[i] * 255 / a);
				px[i + 1] = (byte)Math.Min(255, px[i + 1] * 255 / a);
				px[i + 2] = (byte)Math.Min(255, px[i + 2] * 255 / a);
			}
			Bitmap result = new Bitmap(w, h, PixelFormat.Format32bppArgb);
			BitmapData data = result.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
			try
			{
				for (int y = 0; y < h; y++) Marshal.Copy(px, y * w * 4, new IntPtr(data.Scan0.ToInt64() + (long)y * data.Stride), w * 4);
			}
			finally { result.UnlockBits(data); }
			return result;
		}

		static Bitmap WindowIcon(IntPtr h)
		{
			IntPtr icon;
			Native.SendMessageTimeout(h, WM_GETICON, new IntPtr(1), IntPtr.Zero, SMTO_ABORTIFHUNG, 150, out icon);
			if (icon == IntPtr.Zero) Native.SendMessageTimeout(h, WM_GETICON, new IntPtr(2), IntPtr.Zero, SMTO_ABORTIFHUNG, 150, out icon);
			if (icon == IntPtr.Zero) icon = IntPtr.Size == 8 ? Native.GetClassLongPtr64(h, -14) : new IntPtr(Native.GetClassLong32(h, -14));
			if (icon == IntPtr.Zero) return null;
			using (Icon ic = Icon.FromHandle(icon)) { return ic.ToBitmap(); }
		}

		static Bitmap Fit(Bitmap src, int size)
		{
			Bitmap dst = new Bitmap(size, size, PixelFormat.Format32bppArgb);
			using (Graphics g = Graphics.FromImage(dst))
			{
				g.Clear(Color.Transparent);
				g.InterpolationMode = InterpolationMode.HighQualityBicubic;
				g.PixelOffsetMode = PixelOffsetMode.HighQuality;
				g.SmoothingMode = SmoothingMode.HighQuality;
				double scale = Math.Min((double)size / src.Width, (double)size / src.Height);
				int w = Math.Max(1, (int)Math.Round(src.Width * scale));
				int h = Math.Max(1, (int)Math.Round(src.Height * scale));
				g.DrawImage(src, new Rectangle((size - w) / 2, (size - h) / 2, w, h));
			}
			return dst;
		}

		// --- Installed apps ---------------------------------------------------------

		// The same list as Start > All apps (desktop and Store apps), via the shell's
		// AppsFolder. Late-bound COM keeps this free of interop assemblies.
		static string AppsJson()
		{
			List<string> list = new List<string>();
			Type t = Type.GetTypeFromProgID("Shell.Application");
			if (t == null) return "[]";
			object shell = Activator.CreateInstance(t);
			try
			{
				object folder = t.InvokeMember("NameSpace", BindingFlags.InvokeMethod, null, shell, new object[] { "shell:AppsFolder" });
				if (folder == null) return "[]";
				object items = folder.GetType().InvokeMember("Items", BindingFlags.InvokeMethod, null, folder, null);
				int count = (int)items.GetType().InvokeMember("Count", BindingFlags.GetProperty, null, items, null);
				for (int i = 0; i < count; i++)
				{
					try
					{
						object item = items.GetType().InvokeMember("Item", BindingFlags.InvokeMethod, null, items, new object[] { i });
						if (item == null) continue;
						string name = (string)item.GetType().InvokeMember("Name", BindingFlags.GetProperty, null, item, null);
						string path = (string)item.GetType().InvokeMember("Path", BindingFlags.GetProperty, null, item, null);
						if (string.IsNullOrEmpty(name) || string.IsNullOrEmpty(path)) continue;
						list.Add("{\"name\":" + Json.Str(name) + ",\"id\":" + Json.Str(path) + "}");
					}
					catch (Exception) { }
				}
			}
			finally { Marshal.ReleaseComObject(shell); }
			return "[" + string.Join(",", list.ToArray()) + "]";
		}

		// --- System stats ----------------------------------------------------------

		static string StatsJson()
		{
			double cpu = -1;
			Native.FILETIME idle, kernel, user;
			if (Native.GetSystemTimes(out idle, out kernel, out user))
			{
				ulong i = ((ulong)idle.High << 32) | idle.Low;
				ulong busy = (((ulong)kernel.High << 32) | kernel.Low) + (((ulong)user.High << 32) | user.Low);
				ulong di = i - LastIdle, db = busy - LastBusy;
				if (LastBusy != 0 && db > 0) cpu = Math.Max(0.0, Math.Min(1.0, 1.0 - (double)di / db));
				LastIdle = i;
				LastBusy = busy;
			}
			Native.MEMORYSTATUSEX mem = new Native.MEMORYSTATUSEX();
			mem.dwLength = (uint)Marshal.SizeOf(typeof(Native.MEMORYSTATUSEX));
			double memLoad = -1;
			ulong total = 0;
			if (Native.GlobalMemoryStatusEx(ref mem))
			{
				total = mem.ullTotalPhys;
				memLoad = total > 0 ? 1.0 - (double)mem.ullAvailPhys / total : -1;
			}
			Native.SYSTEM_POWER_STATUS power;
			int battery = -1;
			bool charging = false;
			if (Native.GetSystemPowerStatus(out power) && (power.BatteryFlag & 128) == 0 && power.BatteryLifePercent <= 100)
			{
				battery = power.BatteryLifePercent;
				charging = power.ACLineStatus == 1;
			}
			return "\"cpu\":" + cpu.ToString("0.000", System.Globalization.CultureInfo.InvariantCulture)
				+ ",\"mem\":" + memLoad.ToString("0.000", System.Globalization.CultureInfo.InvariantCulture)
				+ ",\"mem_total\":" + total
				+ ",\"battery\":" + battery
				+ ",\"charging\":" + Json.Bool(charging);
		}


		// --- Shell mode ----------------------------------------------------------------
		//
		// Oazy's desktop window sits at the bottom of the z-order (above nothing,
		// since Explorer's desktop is hidden), its taskbar and Start float on top,
		// and the work area stops above Oazy's taskbar so maximised apps fit. The
		// Windows taskbar is hidden while this is on.

		static void SetExStyle(IntPtr h, int ex)
		{
			Native.SetWindowLong(h, GWL_EXSTYLE, ex);
			Native.SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_FRAMECHANGED | 0x4);
		}

		static void KeepDesktopDown()
		{
			if (Desktop == IntPtr.Zero) return;
			Native.SetWindowPos(Desktop, new IntPtr(1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
		}

		static Native.RECT MonitorRect(IntPtr h, bool work)
		{
			Native.MONITORINFO mi = new Native.MONITORINFO();
			mi.cbSize = Marshal.SizeOf(typeof(Native.MONITORINFO));
			IntPtr mon = Native.MonitorFromWindow(h, 1);
			Native.GetMonitorInfo(mon, ref mi);
			return work ? mi.rcWork : mi.rcMonitor;
		}

		static bool SameRect(Native.RECT a, Native.RECT b)
		{
			return a.Left == b.Left && a.Top == b.Top && a.Right == b.Right && a.Bottom == b.Bottom;
		}

		static string EnterShell(IntPtr desktop, int reserve, bool hideTray)
		{
			lock (ShellLock)
			{
				Desktop = desktop;
				HideTray = hideTray;
				if (desktop != IntPtr.Zero)
				{
					int ex = Native.GetWindowLong(desktop, GWL_EXSTYLE);
					SetExStyle(desktop, (ex | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);
				}
				if (!WorkSaved)
				{
					Native.RECT w = new Native.RECT();
					Native.SystemParametersInfo(SPI_GETWORKAREA, 0, ref w, 0);
					OrigWork = w;
					WorkSaved = true;
				}
				ShellOn = true;
				HideExplorer();
				ShellWork = MonitorRect(desktop, false);
				ShellWork.Bottom -= Math.Max(0, reserve);
				WorkSet = reserve > 0;
				if (WorkSet) Native.SystemParametersInfo(SPI_SETWORKAREA, 0, ref ShellWork, SPIF_SENDCHANGE);
				KeepDesktopDown();
				WriteRestore();
			}
			return "\"ok\":true,\"tray_hidden\":" + Json.Bool(TrayHidden);
		}

		static void HideExplorer()
		{
			if (HideTray)
			{
				IntPtr tray = Native.FindWindow("Shell_TrayWnd", null);
				if (tray != IntPtr.Zero && Native.IsWindowVisible(tray))
				{
					Native.ShowWindow(tray, SW_HIDE);
					TrayHidden = true;
				}
			}
			// Explorer's own desktop (wallpaper and icons) would cover Oazy's, which
			// sits at the very bottom.
			IntPtr progman = Native.FindWindow("Progman", null);
			uint explorerPid = 0;
			if (progman != IntPtr.Zero) Native.GetWindowThreadProcessId(progman, out explorerPid);
			Native.EnumWindows(delegate(IntPtr h, IntPtr l)
			{
				string cls = ClassName(h);
				if ((cls == "Progman" || cls == "WorkerW") && Native.IsWindowVisible(h))
				{
					uint pid;
					Native.GetWindowThreadProcessId(h, out pid);
					if (pid == explorerPid)
					{
						Native.ShowWindow(h, SW_HIDE);
						if (!HiddenDesktop.Contains(h)) HiddenDesktop.Add(h);
					}
				}
				return true;
			}, IntPtr.Zero);
		}

		// Explorer restarts and display changes undo what we set; put it back.
		static void ReassertShell()
		{
			lock (ShellLock)
			{
				if (!ShellOn) return;
				HideExplorer();
				if (WorkSet)
				{
					Native.RECT cur = new Native.RECT();
					Native.SystemParametersInfo(SPI_GETWORKAREA, 0, ref cur, 0);
					if (!SameRect(cur, ShellWork)) Native.SystemParametersInfo(SPI_SETWORKAREA, 0, ref ShellWork, SPIF_SENDCHANGE);
				}
			}
		}

		static void ExitShell()
		{
			lock (ShellLock)
			{
				if (TrayHidden)
				{
					IntPtr tray = Native.FindWindow("Shell_TrayWnd", null);
					if (tray != IntPtr.Zero) Native.ShowWindow(tray, SW_SHOWNA);
					TrayHidden = false;
				}
				foreach (IntPtr h in HiddenDesktop) if (Native.IsWindow(h)) Native.ShowWindow(h, SW_SHOWNA);
				HiddenDesktop.Clear();
				if (WorkSet && WorkSaved) Native.SystemParametersInfo(SPI_SETWORKAREA, 0, ref OrigWork, SPIF_SENDCHANGE);
				WorkSet = false;
				ShellOn = false;
				ThemeOn = false;
				ResetTheme();
				try { if (RestorePath != "" && File.Exists(RestorePath)) File.Delete(RestorePath); }
				catch (Exception) { }
			}
		}

		static void WriteRestore()
		{
			if (RestorePath == "") return;
			try
			{
				File.WriteAllText(RestorePath, string.Format("{0} {1} {2} {3} {4}", OrigWork.Left, OrigWork.Top, OrigWork.Right, OrigWork.Bottom, TrayHidden ? 1 : 0));
			}
			catch (Exception) { }
		}

		// A previous run ended without cleaning up (killed, power loss): bring the
		// Windows taskbar, desktop and work area back before anything else.
		static void RecoverStale()
		{
			if (RestorePath == "" || !File.Exists(RestorePath)) return;
			try
			{
				string[] v = File.ReadAllText(RestorePath).Trim().Split(' ');
				if (v.Length >= 5)
				{
					Native.RECT r = new Native.RECT();
					r.Left = int.Parse(v[0]); r.Top = int.Parse(v[1]); r.Right = int.Parse(v[2]); r.Bottom = int.Parse(v[3]);
					if (r.Right > r.Left && r.Bottom > r.Top) Native.SystemParametersInfo(SPI_SETWORKAREA, 0, ref r, SPIF_SENDCHANGE);
					if (v[4] == "1")
					{
						IntPtr tray = Native.FindWindow("Shell_TrayWnd", null);
						if (tray != IntPtr.Zero) Native.ShowWindow(tray, SW_SHOWNA);
					}
				}
				IntPtr progman = Native.FindWindow("Progman", null);
				if (progman != IntPtr.Zero && !Native.IsWindowVisible(progman)) Native.ShowWindow(progman, SW_SHOWNA);
				File.Delete(RestorePath);
			}
			catch (Exception) { }
		}

		static bool IsFullscreen(IntPtr h)
		{
			if (h == IntPtr.Zero || h == Desktop) return false;
			string cls = ClassName(h);
			if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd") return false;
			Native.RECT r;
			if (!Native.GetWindowRect(h, out r)) return false;
			Native.RECT m = MonitorRect(h, false);
			return r.Left <= m.Left && r.Top <= m.Top && r.Right >= m.Right && r.Bottom >= m.Bottom;
		}

		// --- Window looks ------------------------------------------------------------

		// Oazy's own layers (taskbar, Start, previews, dialogs, Oazy's windows) are
		// screen-sized transparent windows cut to shape: no Alt+Tab entry, no
		// rounding or frame from Windows, dark like the rest.
		static string Style(IntPtr h, string kind)
		{
			if (h == IntPtr.Zero || !Native.IsWindow(h)) return "\"ok\":false";
			int ex = Native.GetWindowLong(h, GWL_EXSTYLE);
			SetExStyle(h, (ex | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);
			int dark = 1;
			Native.DwmSetWindowAttribute(h, DWMWA_USE_IMMERSIVE_DARK_MODE, ref dark, 4);
			int corner = 1;
			Native.DwmSetWindowAttribute(h, DWMWA_WINDOW_CORNER_PREFERENCE, ref corner, 4);
			int none = DWM_COLOR_NONE;
			Native.DwmSetWindowAttribute(h, DWMWA_BORDER_COLOR, ref none, 4);
			return "\"ok\":true,\"kind\":" + Json.Str(kind);
		}

		// Gives other apps' title bars and borders Oazy's colours (Windows 11).
		static string Theme(bool on, int border, int caption, int text)
		{
			lock (ShellLock)
			{
				ThemeOn = on;
				ThemeBorder = border;
				ThemeCaption = caption;
				ThemeText = text;
				if (!on) ResetTheme();
				else
				{
					// New colours for windows we already themed; their original
					// dark-mode value stays remembered for the reset.
					foreach (long k in Themed.Keys)
					{
						IntPtr h = new IntPtr(k);
						int b = border, c = caption, t = text;
						Native.DwmSetWindowAttribute(h, DWMWA_BORDER_COLOR, ref b, 4);
						Native.DwmSetWindowAttribute(h, DWMWA_CAPTION_COLOR, ref c, 4);
						Native.DwmSetWindowAttribute(h, DWMWA_TEXT_COLOR, ref t, 4);
					}
				}
			}
			Dirty = true;
			return "\"ok\":true";
		}

		static void ThemeWindows(HashSet<long> alive)
		{
			lock (ShellLock)
			{
				List<long> gone = new List<long>();
				foreach (long k in Themed.Keys) if (!alive.Contains(k)) gone.Add(k);
				foreach (long k in gone) Themed.Remove(k);
				if (!ThemeOn) return;
				foreach (long k in alive)
				{
					if (Themed.ContainsKey(k)) continue;
					IntPtr h = new IntPtr(k);
					int wasDark;
					if (Native.DwmGetWindowAttribute(h, DWMWA_USE_IMMERSIVE_DARK_MODE, out wasDark, 4) != 0) wasDark = 0;
					int dark = 1, b = ThemeBorder, c = ThemeCaption, t = ThemeText;
					Native.DwmSetWindowAttribute(h, DWMWA_USE_IMMERSIVE_DARK_MODE, ref dark, 4);
					Native.DwmSetWindowAttribute(h, DWMWA_BORDER_COLOR, ref b, 4);
					Native.DwmSetWindowAttribute(h, DWMWA_CAPTION_COLOR, ref c, 4);
					Native.DwmSetWindowAttribute(h, DWMWA_TEXT_COLOR, ref t, 4);
					Themed[k] = wasDark;
				}
			}
		}

		static void ResetTheme()
		{
			foreach (KeyValuePair<long, int> kv in Themed)
			{
				IntPtr h = new IntPtr(kv.Key);
				if (!Native.IsWindow(h)) continue;
				int d = DWM_COLOR_DEFAULT, dark = kv.Value;
				Native.DwmSetWindowAttribute(h, DWMWA_BORDER_COLOR, ref d, 4);
				d = DWM_COLOR_DEFAULT;
				Native.DwmSetWindowAttribute(h, DWMWA_CAPTION_COLOR, ref d, 4);
				d = DWM_COLOR_DEFAULT;
				Native.DwmSetWindowAttribute(h, DWMWA_TEXT_COLOR, ref d, 4);
				Native.DwmSetWindowAttribute(h, DWMWA_USE_IMMERSIVE_DARK_MODE, ref dark, 4);
			}
			Themed.Clear();
		}

		// Minimise everything to show the desktop; again brings it all back.
		static string ShowDesktop()
		{
			List<IntPtr> open = new List<IntPtr>();
			Native.EnumWindows(delegate(IntPtr h, IntPtr l)
			{
				uint pid;
				Native.GetWindowThreadProcessId(h, out pid);
				if (IsAppWindow(h, pid) && !Native.IsIconic(h)) open.Add(h);
				return true;
			}, IntPtr.Zero);
			if (open.Count > 0)
			{
				foreach (IntPtr h in open) Native.ShowWindow(h, SW_SHOWMINNOACTIVE);
				lock (Peeked) { Peeked.Clear(); Peeked.AddRange(open); }
				return "\"ok\":true,\"action\":\"minimize\"";
			}
			List<IntPtr> back;
			lock (Peeked) { back = new List<IntPtr>(Peeked); Peeked.Clear(); }
			for (int i = back.Count - 1; i >= 0; i--)
			{
				if (Native.IsWindow(back[i]) && Native.IsIconic(back[i])) Native.ShowWindow(back[i], SW_RESTORE);
			}
			if (back.Count > 0) Focus(back[0]);
			return "\"ok\":true,\"action\":\"restore\"";
		}

		// --- Events: window changes and the home hotkey ----------------------------------

		static void MessageLoop()
		{
			HookProc = new Native.WinEventProc(OnWinEvent);
			// Foreground, minimise start/end, object create/destroy/show/hide, title changes.
			Native.SetWinEventHook(0x0003, 0x0003, IntPtr.Zero, HookProc, 0, 0, 0);
			Native.SetWinEventHook(0x0016, 0x0017, IntPtr.Zero, HookProc, 0, 0, 0);
			Native.SetWinEventHook(0x8000, 0x8003, IntPtr.Zero, HookProc, 0, 0, 0);
			Native.SetWinEventHook(0x800B, 0x800C, IntPtr.Zero, HookProc, 0, 0, 0);
			bool hotkey = Native.RegisterHotKey(IntPtr.Zero, 1, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 0x4F);
			Write("{\"ev\":\"ready\",\"hotkey\":" + Json.Bool(hotkey) + "}");
			Native.MSG msg;
			while (Native.GetMessage(out msg, IntPtr.Zero, 0, 0) > 0)
			{
				if (msg.message == WM_HOTKEY) OnHotkey();
				Native.TranslateMessage(ref msg);
				Native.DispatchMessage(ref msg);
			}
		}

		static void OnWinEvent(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time)
		{
			if (idObject != 0 || idChild != 0 || hwnd == IntPtr.Zero) return;
			if (ev == 0x800B)
			{
				// Location changes are chatty: only the foreground window matters
				// (it may have just gone fullscreen).
				if (hwnd == Native.GetForegroundWindow()) Dirty = true;
				return;
			}
			if (ev >= 0x8000 && Native.GetAncestor(hwnd, GA_ROOT) != hwnd) return;
			if (ev == 0x0003 && ShellOn && hwnd == Desktop) KeepDesktopDown();
			Dirty = true;
		}

		static void OnHotkey()
		{
			IntPtr fg = Native.GetForegroundWindow();
			uint pid;
			Native.GetWindowThreadProcessId(fg, out pid);
			bool wasForeground = fg != IntPtr.Zero && (fg == Self || (ParentPid != 0 && pid == (uint)ParentPid));
			if (!wasForeground && Self != IntPtr.Zero && !ShellOn) Focus(Self);
			Write("{\"ev\":\"hotkey\",\"was_fg\":" + Json.Bool(wasForeground) + "}");
		}

		static void Tick(object state)
		{
			if (!Dirty || Interlocked.Exchange(ref Ticking, 1) == 1) return;
			try
			{
				Dirty = false;
				Write("{\"ev\":\"windows\"," + WindowsJson() + "}");
			}
			catch (Exception) { }
			finally { Interlocked.Exchange(ref Ticking, 0); }
		}

		static void Watchdog()
		{
			while (true)
			{
				Thread.Sleep(2000);
				try { ReassertShell(); }
				catch (Exception) { }
				if (ParentPid <= 0) continue;
				try
				{
					Process p = Process.GetProcessById(ParentPid);
					if (p.HasExited) { ExitShell(); Environment.Exit(0); }
				}
				catch (ArgumentException) { ClearThumbs(); ExitShell(); Environment.Exit(0); }
				catch (Exception) { }
			}
		}
	}
}
