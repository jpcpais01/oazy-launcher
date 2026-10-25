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
using System.Runtime.InteropServices;
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
		[DllImport("dwmapi.dll")] public static extern int DwmRegisterThumbnail(IntPtr dest, IntPtr src, out IntPtr thumb);
		[DllImport("dwmapi.dll")] public static extern int DwmUnregisterThumbnail(IntPtr thumb);
		[DllImport("dwmapi.dll")] public static extern int DwmUpdateThumbnailProperties(IntPtr thumb, ref DWM_THUMBNAIL_PROPERTIES props);
		[DllImport("dwmapi.dll")] public static extern int DwmQueryThumbnailSourceSize(IntPtr thumb, out SIZE size);
		[DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr h);
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

		[STAThread]
		static int Main(string[] args)
		{
			try { Native.SetProcessDpiAwarenessContext(new IntPtr(-4)); }
			catch (Exception) { try { Native.SetProcessDPIAware(); } catch (Exception) { } }
			if (args.Length > 0) int.TryParse(args[0], out ParentPid);
			PKEY_AppUserModel_ID.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
			PKEY_AppUserModel_ID.pid = 5;

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
					return "\"ok\":" + Json.Bool(SaveIcon(Arg(p, 2), Int(Arg(p, 3), 96), Arg(p, 4)));
				case "apps":
					return "\"ok\":true,\"apps\":" + AppsJson();
				case "thumb":
					return Thumb(H(Arg(p, 2)), Int(Arg(p, 3), 0), Int(Arg(p, 4), 0), Int(Arg(p, 5), 0), Int(Arg(p, 6), 0), Int(Arg(p, 7), 255));
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
			return "\"windows\":[" + string.Join(",", list.ToArray()) + "],\"fg\":" + fg.ToInt64() + ",\"self_fg\":" + Json.Bool(fg == Self && Self != IntPtr.Zero);
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

		static string Thumb(IntPtr src, int x, int y, int w, int hgt, int opacity)
		{
			if (Self == IntPtr.Zero || src == IntPtr.Zero || w <= 0 || hgt <= 0) return "\"ok\":false";
			IntPtr thumb;
			lock (Thumbs)
			{
				if (!Thumbs.TryGetValue(src.ToInt64(), out thumb))
				{
					if (Native.DwmRegisterThumbnail(Self, src, out thumb) != 0) return "\"ok\":false";
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

		static bool SaveIcon(string key, int size, string outPath)
		{
			if (key == "" || outPath == "") return false;
			size = Math.Max(16, Math.Min(256, size));
			Bitmap bmp = null;
			try
			{
				if (key.StartsWith("hwnd:")) bmp = WindowIcon(H(key.Substring(5)));
				else bmp = ShellImage(key, size);
				if (bmp == null) return false;
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
			catch (Exception) { return false; }
			finally { if (bmp != null) bmp.Dispose(); }
		}

		static Bitmap ShellImage(string path, int size)
		{
			Native.IShellItemImageFactory factory = null;
			try
			{
				Guid iid = typeof(Native.IShellItemImageFactory).GUID;
				if (Native.SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out factory) != 0 || factory == null) return null;
				Native.SIZE s;
				s.cx = size;
				s.cy = size;
				IntPtr hbm;
				if (factory.GetImage(s, SIIGBF_ICONONLY, out hbm) != 0 || hbm == IntPtr.Zero) return null;
				try { return FromHBitmap(hbm); }
				finally { Native.DeleteObject(hbm); }
			}
			catch (Exception) { return null; }
			finally { if (factory != null) Marshal.ReleaseComObject(factory); }
		}

		// HBITMAPs from the shell carry premultiplied alpha that Image.FromHbitmap
		// throws away; read the raw pixels back to keep soft edges.
		static Bitmap FromHBitmap(IntPtr hbm)
		{
			using (Bitmap src = Image.FromHbitmap(hbm))
			{
				if (Image.GetPixelFormatSize(src.PixelFormat) < 32) return new Bitmap(src);
				Rectangle r = new Rectangle(0, 0, src.Width, src.Height);
				BitmapData data = src.LockBits(r, ImageLockMode.ReadOnly, src.PixelFormat);
				try
				{
					byte[] bytes = new byte[Math.Abs(data.Stride) * data.Height];
					Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
					bool hasAlpha = false;
					for (int i = 3; i < bytes.Length; i += 4)
					{
						if (bytes[i] != 0) { hasAlpha = true; break; }
					}
					if (!hasAlpha) return new Bitmap(src);
					using (Bitmap pre = new Bitmap(data.Width, data.Height, data.Stride, PixelFormat.Format32bppPArgb, data.Scan0))
					{
						Bitmap result = new Bitmap(data.Width, data.Height, PixelFormat.Format32bppArgb);
						using (Graphics g = Graphics.FromImage(result))
						{
							g.CompositingMode = CompositingMode.SourceCopy;
							g.DrawImage(pre, new Rectangle(0, 0, data.Width, data.Height));
						}
						return result;
					}
				}
				finally { src.UnlockBits(data); }
			}
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

		// --- Events: window changes and the home hotkey ----------------------------------

		static void MessageLoop()
		{
			HookProc = new Native.WinEventProc(OnWinEvent);
			// Foreground, minimise start/end, object create/destroy/show/hide, title changes.
			Native.SetWinEventHook(0x0003, 0x0003, IntPtr.Zero, HookProc, 0, 0, 0);
			Native.SetWinEventHook(0x0016, 0x0017, IntPtr.Zero, HookProc, 0, 0, 0);
			Native.SetWinEventHook(0x8000, 0x8003, IntPtr.Zero, HookProc, 0, 0, 0);
			Native.SetWinEventHook(0x800C, 0x800C, IntPtr.Zero, HookProc, 0, 0, 0);
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
			if (ev >= 0x8000 && Native.GetAncestor(hwnd, GA_ROOT) != hwnd) return;
			Dirty = true;
		}

		static void OnHotkey()
		{
			bool wasForeground = Self != IntPtr.Zero && Native.GetForegroundWindow() == Self;
			if (!wasForeground && Self != IntPtr.Zero) Focus(Self);
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
				if (ParentPid <= 0) continue;
				try
				{
					Process p = Process.GetProcessById(ParentPid);
					if (p.HasExited) Environment.Exit(0);
				}
				catch (ArgumentException) { ClearThumbs(); Environment.Exit(0); }
				catch (Exception) { }
			}
		}
	}
}
