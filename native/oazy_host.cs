// Oazy host: a small native companion process for the Oazy shell.
//
// Godot has no FFI, so everything that needs Win32 lives here: listing the
// real application windows (like Alt+Tab does), focusing / minimising /
// closing them, live DWM thumbnails drawn into Oazy's window, app icons,
// the list of installed apps, system stats and sensors, speaker volume, media keys,
// Oazy's mouse pointers and the global "home" hotkey.
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
using System.Net.NetworkInformation;
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
		public delegate IntPtr WndProc(IntPtr h, uint msg, IntPtr w, IntPtr l);
		public delegate IntPtr KeyboardProc(int code, IntPtr w, IntPtr l);

		[StructLayout(LayoutKind.Sequential)]
		public struct RECT { public int Left, Top, Right, Bottom; }

		[StructLayout(LayoutKind.Sequential)]
		public struct SIZE { public int cx, cy; }

		[StructLayout(LayoutKind.Sequential)]
		public struct APPBARDATA
		{
			public int cbSize;
			public IntPtr hWnd;
			public uint uCallbackMessage;
			public uint uEdge;
			public RECT rc;
			public IntPtr lParam;
		}

		[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
		public struct WNDCLASSEX
		{
			public int cbSize;
			public uint style;
			public WndProc lpfnWndProc;
			public int cbClsExtra, cbWndExtra;
			public IntPtr hInstance, hIcon, hCursor, hbrBackground;
			public string lpszMenuName, lpszClassName;
			public IntPtr hIconSm;
		}

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
		public struct KBDLLHOOKSTRUCT
		{
			public uint vkCode;
			public uint scanCode;
			public uint flags;
			public uint time;
			public UIntPtr dwExtraInfo;
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

		// Core Audio: the default speakers' master volume and mute.
		[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
		public class MMDeviceEnumerator { }

		[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
		public interface IMMDeviceEnumerator
		{
			[PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
			[PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
		}

		[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
		public interface IMMDevice
		{
			[PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
			[PreserveSig] int OpenPropertyStore(int access, out IPropertyStore store);
		}

		[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
		public interface IAudioEndpointVolume
		{
			[PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
			[PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
			[PreserveSig] int GetChannelCount(out uint count);
			[PreserveSig] int SetMasterVolumeLevel(float db, ref Guid ctx);
			[PreserveSig] int SetMasterVolumeLevelScalar(float level, ref Guid ctx);
			[PreserveSig] int GetMasterVolumeLevel(out float db);
			[PreserveSig] int GetMasterVolumeLevelScalar(out float level);
			[PreserveSig] int SetChannelVolumeLevel(uint channel, float db, ref Guid ctx);
			[PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid ctx);
			[PreserveSig] int GetChannelVolumeLevel(uint channel, out float db);
			[PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
			[PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx);
			[PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
		}

		[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
		[DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA data);
		[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern ushort RegisterClassEx(ref WNDCLASSEX wc);
		[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr CreateWindowEx(int ex, string cls, string name, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
		[DllImport("user32.dll")] public static extern IntPtr DefWindowProc(IntPtr h, uint msg, IntPtr w, IntPtr l);
		[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern uint RegisterWindowMessage(string name);
		[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr GetModuleHandle(string name);
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
		[DllImport("shell32.dll")] public static extern int SHQueryUserNotificationState(out int state);
		[DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h, bool altTab);
		[DllImport("user32.dll")] public static extern IntPtr GetLastActivePopup(IntPtr h);
		[DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
		[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
		[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int cmd);
		[DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr h);
		[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr GetProp(IntPtr h, string name);
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
		[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
		[DllImport("user32.dll")] public static extern IntPtr SetWindowsHookEx(int id, KeyboardProc proc, IntPtr module, uint thread);
		[DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr w, IntPtr l);
		[DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
		[DllImport("user32.dll", EntryPoint = "SetWindowLongW")] public static extern int SetWindowLong(IntPtr h, int index, int value);
		[DllImport("user32.dll")] public static extern int GetWindowRgnBox(IntPtr h, out RECT r);
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
		[DllImport("user32.dll", EntryPoint = "SystemParametersInfoW")] public static extern bool SystemParametersInfoPtr(uint action, uint param, IntPtr value, uint winIni);
		[DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr LoadImage(IntPtr inst, string name, uint type, int cx, int cy, uint flags);
		[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadCursorFromFile(string name);
		[DllImport("user32.dll")] public static extern bool SetSystemCursor(IntPtr cursor, uint id);
		[DllImport("user32.dll")] public static extern bool DestroyCursor(IntPtr cursor);
		[DllImport("user32.dll")] public static extern uint GetDpiForSystem();
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
		const int GWL_EXSTYLE = -20, GWL_STYLE = -16;
		const int WS_CAPTION = 0xC00000, WS_THICKFRAME = 0x40000;
		const int WS_EX_TOOLWINDOW = 0x80;
		const int WS_EX_APPWINDOW = 0x40000;
		const int WS_EX_NOACTIVATE = 0x8000000;
		const int WS_EX_TOPMOST = 0x8;
		const uint GW_OWNER = 4, GW_HWNDNEXT = 2;
		const uint GA_ROOT = 2, GA_ROOTOWNER = 3;
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
		const uint ABM_NEW = 0, ABM_REMOVE = 1, ABM_QUERYPOS = 2, ABM_SETPOS = 3, ABM_GETSTATE = 4, ABM_SETSTATE = 10;
		const uint ABE_BOTTOM = 3, ABN_POSCHANGED = 1, ABN_FULLSCREENAPP = 2;
		const int ABS_AUTOHIDE = 1;
		const uint WM_APP = 0x8000, WM_APPBAR = WM_APP + 1, WM_SHELL_APPLY = WM_APP + 2, WM_DISPLAYCHANGE = 0x7E;
		const uint HOTKEY_HOME = 1, HOTKEY_DESKTOP = 2;
		const int SIIGBF_ICONONLY = 4;
		const int SW_HIDE = 0;
		const int SW_SHOWNOACTIVATE = 4;
		const int SW_SHOWMINNOACTIVE = 7;
		const int SW_SHOWNA = 8;
		const uint MONITOR_DEFAULTTONEAREST = 2;
		const uint SWP_NOSIZE = 0x1, SWP_NOMOVE = 0x2, SWP_NOZORDER = 0x4, SWP_NOACTIVATE = 0x10, SWP_FRAMECHANGED = 0x20, SWP_NOOWNERZORDER = 0x200, SWP_ASYNCWINDOWPOS = 0x4000;
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
		static readonly Dictionary<string, IntPtr> Thumbs = new Dictionary<string, IntPtr>();
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
		static Native.RECT OrigWork;
		static bool WorkSaved;
		// Oazy's taskbar is a real AppBar, so Windows itself keeps maximised
		// apps above it. (Setting the work area directly fought Explorer, which
		// kept putting its own back: windows jumped between the two sizes.)
		static IntPtr AppBarWnd = IntPtr.Zero;
		static Native.WndProc AppBarProc;
		static bool AppBarOn;
		static int Reserve;
		static uint TaskbarCreated;
		// Explorer's taskbar autohide state before we changed it, -1 if untouched.
		static int TrayState = -1;
		static readonly List<IntPtr> Peeked = new List<IntPtr>();
		// Oazy's always-on-top layers (taskbar, Start, menus...), kept there.
		static readonly HashSet<long> OnTop = new HashSet<long>();
		// What the last window list said about a fullscreen app (see Watchdog).
		static volatile bool LastFs;
		static bool ThemeOn;
		static int ThemeBorder;
		static readonly HashSet<long> Themed = new HashSet<long>();
		static string RestorePath = "";
		// Set while Oazy's pointers replace the system ones (see Cursors).
		static string CursorMarker = "";
		static bool CursorsOn;
		static readonly object CursorLock = new object();
		// Alt+Tab: Oazy asked for it, it is open right now, Oazy answered the last one.
		static volatile bool SwitchWanted;
		static volatile bool Switching;
		static volatile bool SwitchAcked = true;
		static IntPtr KeyHook = IntPtr.Zero;
		static Native.KeyboardProc KeyProc;
		const int WH_KEYBOARD_LL = 13;
		const uint WM_KEYDOWN = 0x100, WM_SYSKEYDOWN = 0x104;
		const uint LLKHF_ALTDOWN = 0x20, LLKHF_INJECTED = 0x10;
		const uint VK_TAB = 0x09, VK_RETURN = 0x0D, VK_SHIFT = 0x10, VK_MENU = 0x12, VK_ESCAPE = 0x1B;
		const uint VK_LEFT = 0x25, VK_UP = 0x26, VK_RIGHT = 0x27, VK_DOWN = 0x28, VK_DELETE = 0x2E;
		const uint VK_LSHIFT = 0xA0, VK_RSHIFT = 0xA1, VK_LMENU = 0xA4, VK_RMENU = 0xA5;
		const byte VK_MASK = 0xE8;

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
			if (RestorePath != "") CursorMarker = Path.Combine(Path.GetDirectoryName(RestorePath), "cursor-restore.txt");
			RecoverStale();
			if (CursorMarker != "" && File.Exists(CursorMarker)) RestoreCursors();

			Out = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false));
			Out.AutoFlush = true;
			Out.NewLine = "\n";
			Wifi.Emit = Write;
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
				if (Arg(p, 1) == "capture")
				{
					// Pictures of windows take a while: answer from a worker so
					// focus and the rest never wait behind one.
					string[] job = p;
					ThreadPool.QueueUserWorkItem(delegate(object state)
					{
						string r;
						try { r = Capture(H(Arg(job, 2)), Int(Arg(job, 3), 640), Int(Arg(job, 4), 400), Arg(job, 5)); }
						catch (Exception ex) { r = "\"ok\":false,\"error\":" + Json.Str(ex.Message); }
						Write("{\"id\":" + Num(job[0]) + "," + r + "}");
					});
					continue;
				}
				string reply;
				try { reply = Handle(p); }
				catch (Exception ex) { reply = "\"ok\":false,\"error\":" + Json.Str(ex.Message); }
				// Id 0: fire and forget (live previews moving every frame).
				if (p[0] != "0") Write("{\"id\":" + Num(p[0]) + "," + reply + "}");
			}
			RestoreCursors();
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
				case "release":
					return "\"ok\":" + Json.Bool(Release(H(Arg(p, 2))));
				case "raise":
					// "raise <hwnd> 1": back to the very top of the topmost band, for
					// Oazy's always-on-top layers (taskbar, previews, Start, menus).
					return "\"ok\":" + Json.Bool(Native.SetWindowPos(H(Arg(p, 2)), Arg(p, 3) == "1" ? new IntPtr(-1) : IntPtr.Zero, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER));
				case "toggle":
				{
					IntPtr h = H(Arg(p, 2));
					// The app counts as in front while one of its dialogs is.
					IntPtr fg = Native.GetForegroundWindow();
					bool active = fg == h || (fg != IntPtr.Zero && Native.GetAncestor(fg, GA_ROOTOWNER) == h);
					if (active && !Native.IsIconic(h))
					{
						Native.ShowWindow(h, SW_MINIMIZE);
						return "\"ok\":true,\"action\":\"minimize\"";
					}
					return "\"ok\":" + Json.Bool(Focus(h)) + ",\"action\":\"focus\"";
				}
				case "expect":
					Expect();
					return "\"ok\":true";
				case "restore_quietly":
				{
					// Back from minimised without taking focus (Oazy's desktop after Win+D).
					IntPtr h = H(Arg(p, 2));
					bool ok = Native.IsIconic(h) && Native.ShowWindow(h, SW_SHOWNOACTIVATE);
					if (h == Desktop) KeepDesktopDown();
					return "\"ok\":" + Json.Bool(ok);
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
					return Style(H(Arg(p, 2)), Arg(p, 3), Arg(p, 4) == "1");
				case "fit":
					return Fit(H(Arg(p, 2)), Int(Arg(p, 3), 0));
				case "theme":
					return Theme(Arg(p, 2) == "1", Int(Arg(p, 3), 0), Int(Arg(p, 4), 0), Int(Arg(p, 5), 0));
				case "show_desktop":
					return ShowDesktop(Arg(p, 2) == "1", H(Arg(p, 3)));
				case "thumb_clear":
					ClearThumbs();
					return "\"ok\":true";
				case "stats":
					return "\"ok\":true," + StatsJson() + Sensors.Read(Arg(p, 2) == "1");
				case "procs":
					return Procs.List(ParentPid);
				case "kill":
					return Procs.Kill(Arg(p, 2), ParentPid);
				case "lock":
					return "\"ok\":" + Json.Bool(Native.LockWorkStation());
				case "sleep":
					return "\"ok\":" + Json.Bool(Native.SetSuspendState(false, false, false));
				case "volume":
					return Volume(null, -1);
				case "volume_set":
				{
					float level;
					if (!float.TryParse(Arg(p, 2), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out level))
						return "\"ok\":false,\"error\":\"bad level\"";
					return Volume(Math.Max(0f, Math.Min(1f, level)), -1);
				}
				case "mute":
					return Volume(null, Arg(p, 2) == "1" ? 1 : 0);
				case "media":
					return "\"ok\":" + Json.Bool(MediaKey(Arg(p, 2)));
				case "switcher":
					SwitchWanted = Arg(p, 2) == "1";
					if (!SwitchWanted) Switching = false;
					SwitchAcked = true;
					return "\"ok\":true,\"hook\":" + Json.Bool(KeyHook != IntPtr.Zero);
				case "keep_pictures":
					KeepPictures(Arg(p, 2), Int(Arg(p, 3), 640), Int(Arg(p, 4), 400));
					return "\"ok\":true";
				case "switcher_ack":
					SwitchAcked = true;
					return "\"ok\":true";
				case "cursors":
					return Cursors(Arg(p, 2));
				case "cursors_off":
					RestoreCursors();
					return "\"ok\":true";
				case "ping":
					return "\"ok\":true";
				case "wifi":
					return Wifi.Status(Arg(p, 2) == "1");
				case "wifi_scan":
					return Wifi.Scan();
				case "wifi_connect":
					return Wifi.Connect(Arg(p, 2), Arg(p, 3), Arg(p, 4) != "0");
				case "wifi_disconnect":
					return Wifi.Disconnect();
				case "wifi_forget":
					return Wifi.Forget(Arg(p, 2));
				case "wifi_radio":
					return Wifi.SetRadio(Arg(p, 2) == "1");
				case "webview2":
					return "\"ok\":true,\"version\":" + Json.Str(WebView2Version());
			}
			return "\"ok\":false,\"error\":\"unknown command\"";
		}

		// The Edge WebView2 runtime Oazy Browser runs on ("" when it isn't installed).
		static string WebView2Version()
		{
			const string Client = @"Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}";
			string[] keys = {
				@"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\" + Client,
				@"HKEY_LOCAL_MACHINE\SOFTWARE\" + Client,
				@"HKEY_CURRENT_USER\Software\" + Client,
			};
			foreach (string k in keys)
			{
				try
				{
					string v = Microsoft.Win32.Registry.GetValue(k, "pv", null) as string;
					if (!string.IsNullOrEmpty(v) && v != "0.0.0.0") return v;
				}
				catch { }
			}
			return "";
		}

		// --- Mouse pointers ---------------------------------------------------------

		// Oazy's pointer files (one per glyph) for each system cursor id.
		static readonly string[] CursorFiles = {
			"32512:arrow.cur", "32513:text.cur", "32514:busy.ani", "32515:cross.cur", "32516:up.cur",
			"32642:nwse.cur", "32643:nesw.cur", "32644:we.cur", "32645:ns.cur", "32646:move.cur",
			"32648:no.cur", "32649:hand.cur", "32650:working.ani", "32651:help.cur",
		};
		const uint IMAGE_CURSOR = 2, LR_LOADFROMFILE = 0x10, SPI_SETCURSORS = 0x57;

		// Swaps the system cursors for the files in `dir`. Nothing is written to
		// the user's cursor scheme: SetSystemCursor only lasts until the scheme is
		// reloaded (RestoreCursors) or the user signs out, and a marker file makes
		// the next start put Windows' own back if this process dies first.
		static string Cursors(string dir)
		{
			if (dir == "" || !Directory.Exists(dir)) return "\"ok\":false,\"error\":\"no cursor folder\"";
			int px = CursorPixels();
			int done = 0;
			lock (CursorLock)
			{
				if (CursorMarker != "")
				{
					try { File.WriteAllText(CursorMarker, dir); }
					catch (Exception) { }
				}
				CursorsOn = true;
				foreach (string pair in CursorFiles)
				{
					int colon = pair.IndexOf(':');
					uint id = uint.Parse(pair.Substring(0, colon));
					string file = Path.Combine(dir, pair.Substring(colon + 1));
					if (!File.Exists(file)) continue;
					IntPtr h = Native.LoadImage(IntPtr.Zero, file, IMAGE_CURSOR, px, px, LR_LOADFROMFILE);
					if (h == IntPtr.Zero) h = Native.LoadCursorFromFile(file);
					if (h == IntPtr.Zero) continue;
					// The system takes ownership of h when this succeeds.
					if (Native.SetSystemCursor(h, id)) done++;
					else Native.DestroyCursor(h);
				}
			}
			return "\"ok\":" + Json.Bool(done > 0) + ",\"set\":" + done + ",\"px\":" + px;
		}

		// Reloads the user's own cursor scheme from the registry.
		static void RestoreCursors()
		{
			lock (CursorLock)
			{
				bool stale = CursorMarker != "" && File.Exists(CursorMarker);
				if (!CursorsOn && !stale) return;
				Native.SystemParametersInfoPtr(SPI_SETCURSORS, 0, IntPtr.Zero, 0);
				CursorsOn = false;
				try { if (stale) File.Delete(CursorMarker); }
				catch (Exception) { }
			}
		}

		// The pointer size Windows itself would use: the accessibility size
		// (Settings > Mouse pointer size) at the screen's scale.
		static int CursorPixels()
		{
			int baseSize = 32;
			try
			{
				object v = Microsoft.Win32.Registry.GetValue("HKEY_CURRENT_USER\\Control Panel\\Cursors", "CursorBaseSize", null);
				if (v is int && (int)v >= 32 && (int)v <= 256) baseSize = (int)v;
			}
			catch (Exception) { }
			uint dpi = 96;
			try { dpi = Native.GetDpiForSystem(); }
			catch (Exception) { }
			if (dpi < 96) dpi = 96;
			return Math.Min(256, (int)Math.Round(baseSize * dpi / 96.0));
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

		internal static string ExePath(uint pid)
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

		internal static string Description(string exe)
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
			// Front to back, as Windows keeps them.
			List<IntPtr> order = new List<IntPtr>();
			Native.EnumWindows(delegate(IntPtr h, IntPtr l)
			{
				uint pid;
				Native.GetWindowThreadProcessId(h, out pid);
				if (!IsAppWindow(h, pid)) return true;
				alive.Add(h.ToInt64());
				order.Add(h);
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
					+ ",\"max\":" + Json.Bool(Native.IsZoomed(h) || Native.GetProp(h, "OazyMax") != IntPtr.Zero)
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
			CheckExpected(order);
			uint fgPid;
			Native.GetWindowThreadProcessId(fg, out fgPid);
			bool selfFg = fg != IntPtr.Zero && ((fg == Self && Self != IntPtr.Zero) || (ParentPid != 0 && fgPid == (uint)ParentPid));
			// A dialog in front (Save as, a message box) stands for the app it belongs to.
			IntPtr fgApp = fg;
			if (fg != IntPtr.Zero && !alive.Contains(fg.ToInt64()))
			{
				IntPtr owner = Native.GetAncestor(fg, GA_ROOTOWNER);
				if (owner != IntPtr.Zero && alive.Contains(owner.ToInt64())) fgApp = owner;
			}
			bool fs = !selfFg && FullscreenOverOazy(fg);
			LastFs = fs;
			return "\"windows\":[" + string.Join(",", list.ToArray()) + "],\"fg\":" + fgApp.ToInt64() + ",\"self_fg\":" + Json.Bool(selfFg)
				+ ",\"fs\":" + Json.Bool(fs);
		}

		// --- Focus ------------------------------------------------------------------
		// Windows lets only the app you're using hand the foreground to another
		// window. Oazy's taskbar never takes focus (clicking it leaves the app you
		// were in active), so bringing a window forward from it has to get that
		// right the way Windows' own shell features do. A window is only raised
		// without focus when all of that fails: a window in front that isn't the
		// active one is what made clicks on the window behind it do nothing.

		static readonly object FocusLock = new object();
		// The windows that were in front, newest first: where focus goes back to
		// when one of Oazy's layers (Start, a menu) closes.
		static readonly List<IntPtr> FgHistory = new List<IntPtr>();

		static bool Focus(IntPtr h)
		{
			if (h == IntPtr.Zero || !Native.IsWindow(h)) return false;
			// An app that stopped responding only gets the requests that don't
			// wait for it, or the companion would hang along with it.
			if (Native.IsHungAppWindow(h))
			{
				if (Native.IsIconic(h)) Native.ShowWindowAsync(h, SW_RESTORE);
				return Native.SetForegroundWindow(h);
			}
			lock (FocusLock)
			{
				if (Native.IsIconic(h)) Native.ShowWindow(h, SW_RESTORE);
				// An app with a dialog open (Save as, a message box) hands focus to
				// the dialog, as on Windows' own taskbar.
				IntPtr target = h;
				IntPtr popup = Native.GetLastActivePopup(h);
				if (popup != IntPtr.Zero && popup != h && Native.IsWindowVisible(popup) && Native.IsWindowEnabled(popup)) target = popup;
				if (Activate(target)) return true;
				Lift(h);
				if (target != h) Lift(target);
				return false;
			}
		}

		// Makes `w` the foreground window. Hold FocusLock.
		static bool Activate(IntPtr w)
		{
			if (Native.GetForegroundWindow() == w) return true;
			if (Native.SetForegroundWindow(w) && Native.GetForegroundWindow() == w) return true;
			// Share input with the window in front for a moment: to Windows the
			// request then comes from the app you're in.
			IntPtr fg = Native.GetForegroundWindow();
			uint ignored;
			uint fgThread = fg != IntPtr.Zero ? Native.GetWindowThreadProcessId(fg, out ignored) : 0;
			uint me = Native.GetCurrentThreadId();
			bool attached = fgThread != 0 && fgThread != me && Native.AttachThreadInput(me, fgThread, true);
			try
			{
				Native.BringWindowToTop(w);
				Native.SetForegroundWindow(w);
			}
			finally
			{
				if (attached) Native.AttachThreadInput(me, fgThread, false);
			}
			if (Native.GetForegroundWindow() == w) return true;
			// Still refused (the app in front is busy, or runs as administrator):
			// a key press of our own makes this the process with the last input.
			PressUnusedKey();
			if (Native.SetForegroundWindow(w) && Native.GetForegroundWindow() == w) return true;
			// Last resort: the call Windows' own Alt+Tab makes.
			Native.SwitchToThisWindow(w, true);
			return Native.GetForegroundWindow() == w;
		}

		// Alt with a key nobody uses in between, so no app opens its menu bar as it
		// would for Alt on its own (Chrome's menu button, Explorer's menus, an
		// invisible system menu in apps without a title bar). Alt is left out
		// while Shift or Ctrl is down, where it would make a shortcut.
		static void PressUnusedKey()
		{
			bool alt = (Native.GetAsyncKeyState((int)VK_MENU) & 0x8000) == 0
				&& (Native.GetAsyncKeyState((int)VK_SHIFT) & 0x8000) == 0
				&& (Native.GetAsyncKeyState(0x11) & 0x8000) == 0;
			if (alt) Native.keybd_event((byte)VK_MENU, 0, 0, UIntPtr.Zero);
			Native.keybd_event(VK_MASK, 0, 0, UIntPtr.Zero);
			Native.keybd_event(VK_MASK, 0, 2, UIntPtr.Zero);
			if (alt) Native.keybd_event((byte)VK_MENU, 0, 2, UIntPtr.Zero);
		}

		// To the top of its band without focus. An always-on-top window stays
		// always on top. Posted to the window's own thread, so a busy app never
		// holds the companion up.
		static void Lift(IntPtr h)
		{
			uint z = SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_ASYNCWINDOWPOS;
			bool topmost = (Native.GetWindowLong(h, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
			Native.SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, z);
			if (!topmost) Native.SetWindowPos(h, new IntPtr(-2), 0, 0, 0, 0, z);
		}

		static void NoteForeground(IntPtr h)
		{
			if (h == IntPtr.Zero) return;
			lock (FgHistory)
			{
				FgHistory.Remove(h);
				FgHistory.Insert(0, h);
				if (FgHistory.Count > 16) FgHistory.RemoveAt(FgHistory.Count - 1);
			}
		}

		// False while a window is cut down to nothing (one of Oazy's parked layers).
		static bool HasShape(IntPtr h)
		{
			Native.RECT box;
			if (Native.GetWindowRgnBox(h, out box) == 0) return true;
			return box.Right > 0 && box.Bottom > 0 && box.Right > box.Left && box.Bottom > box.Top;
		}

		// One of Oazy's layers emptied while active (it stays up, cut to nothing,
		// so it can come back instantly): focus goes back to the window that had
		// it before, as when a menu closes. Skipped if the layer has a shape
		// again (opened straight back).
		static bool Release(IntPtr h)
		{
			if (h == IntPtr.Zero || !Native.IsWindow(h) || Native.GetForegroundWindow() != h || HasShape(h)) return false;
			IntPtr back = FocusBackTarget(h);
			lock (FocusLock)
			{
				if (back != IntPtr.Zero && Activate(back))
				{
					if (back == Desktop) KeepDesktopDown();
					return true;
				}
			}
			// Nothing to go back to, or Windows refused: hiding the layer for a
			// moment makes Windows activate the next window in line.
			Native.ShowWindow(h, SW_HIDE);
			Native.ShowWindow(h, SW_SHOWNA);
			return true;
		}

		// The most recent window in front that is still there to go back to:
		// open, not minimised, on this virtual desktop, and if it is another of
		// Oazy's layers, showing something. Else Oazy's desktop.
		static IntPtr FocusBackTarget(IntPtr leaving)
		{
			List<IntPtr> recent;
			lock (FgHistory) recent = new List<IntPtr>(FgHistory);
			IntPtr desktop = Desktop != IntPtr.Zero ? Desktop : Self;
			foreach (IntPtr w in recent)
			{
				if (w == leaving || !Native.IsWindow(w) || !Native.IsWindowVisible(w) || Native.IsIconic(w) || !Native.IsWindowEnabled(w)) continue;
				int cloaked;
				if (Native.DwmGetWindowAttribute(w, DWMWA_CLOAKED, out cloaked, 4) == 0 && cloaked != 0) continue;
				uint pid;
				Native.GetWindowThreadProcessId(w, out pid);
				if (w != desktop && ParentPid != 0 && pid == (uint)ParentPid && !HasShape(w)) continue;
				return w;
			}
			return desktop;
		}

		// A window Oazy just launched comes up in front with focus. Started from
		// Oazy's taskbar (which never takes focus), a new app doesn't get the
		// right to come forward by itself: Windows leaves it behind the app you
		// were in, or in front of it without focus.
		static readonly object ExpectLock = new object();
		static DateTime ExpectUntil = DateTime.MinValue;
		static DateTime ExpectSettled = DateTime.MinValue;
		static HashSet<long> ExpectKnown = new HashSet<long>();

		static void Expect()
		{
			HashSet<long> known = new HashSet<long>();
			Native.EnumWindows(delegate(IntPtr h, IntPtr l)
			{
				uint pid;
				Native.GetWindowThreadProcessId(h, out pid);
				if (IsAppWindow(h, pid)) known.Add(h.ToInt64());
				return true;
			}, IntPtr.Zero);
			lock (ExpectLock)
			{
				ExpectKnown = known;
				ExpectUntil = DateTime.UtcNow.AddSeconds(20);
				// Start closing and handing focus back is part of launching.
				ExpectSettled = DateTime.UtcNow.AddSeconds(1.5);
			}
		}

		// Went on to another window while the app was still loading: as with
		// Windows' own Start menu, it then opens without taking focus.
		static void ForegroundMoved(IntPtr h)
		{
			lock (ExpectLock)
			{
				DateTime now = DateTime.UtcNow;
				if (now > ExpectUntil || now < ExpectSettled) return;
				if (ExpectKnown.Contains(h.ToInt64())) ExpectUntil = DateTime.MinValue;
			}
		}

		// With every new window list (front to back): the first new window since
		// Expect() is the one that was launched.
		static void CheckExpected(List<IntPtr> order)
		{
			IntPtr fresh = IntPtr.Zero;
			lock (ExpectLock)
			{
				if (DateTime.UtcNow > ExpectUntil) return;
				foreach (IntPtr h in order)
				{
					if (ExpectKnown.Contains(h.ToInt64()) || Native.IsIconic(h)) continue;
					fresh = h;
					break;
				}
				if (fresh == IntPtr.Zero) return;
				ExpectUntil = DateTime.MinValue;
			}
			if (Native.GetForegroundWindow() == fresh) return;
			ThreadPool.QueueUserWorkItem(delegate(object state)
			{
				try { Focus(fresh); }
				catch (Exception) { }
			});
		}

		// --- Live thumbnails -------------------------------------------------------

		static string Thumb(IntPtr src, int x, int y, int w, int hgt, int opacity, IntPtr dest)
		{
			if (dest == IntPtr.Zero) dest = Self;
			if (dest == IntPtr.Zero || src == IntPtr.Zero || w <= 0 || hgt <= 0) return "\"ok\":false";
			IntPtr thumb;
			lock (Thumbs)
			{
				// One per source and destination: the taskbar preview and the
				// switcher are different windows.
				string key = dest.ToInt64() + ":" + src.ToInt64();
				if (!Thumbs.TryGetValue(key, out thumb))
				{
					if (Native.DwmRegisterThumbnail(dest, src, out thumb) != 0) return "\"ok\":false";
					Thumbs[key] = thumb;
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
			// Opacity 0 hides it (the switcher fades previews in and out).
			props.fVisible = opacity > 0;
			props.fSourceClientAreaOnly = false;
			int hr = Native.DwmUpdateThumbnailProperties(thumb, ref props);
			return "\"ok\":" + Json.Bool(hr == 0) + ",\"x\":" + props.rcDestination.Left + ",\"y\":" + props.rcDestination.Top
				+ ",\"w\":" + dw + ",\"h\":" + dh + ",\"src_w\":" + s.cx + ",\"src_h\":" + s.cy;
		}

		// --- Window pictures ----------------------------------------------------------
		// A still of a window as Windows itself would draw it (PrintWindow with
		// PW_RENDERFULLCONTENT also gets Chrome, Electron and DirectX content),
		// cropped to the visible frame, scaled to fit maxW x maxH and written to
		// `path` as raw RGBA bytes. "dev" is how much the pixels vary: next to
		// nothing means a blank picture.
		[HandleProcessCorruptedStateExceptions, SecurityCritical]
		static string Capture(IntPtr h, int maxW, int maxH, string path)
		{
			if (h == IntPtr.Zero || !Native.IsWindow(h)) return "\"ok\":false,\"error\":\"no window\"";
			if (Native.IsIconic(h)) return "\"ok\":false,\"error\":\"minimised\"";
			Native.RECT wr;
			if (!Native.GetWindowRect(h, out wr)) return "\"ok\":false,\"error\":\"no rect\"";
			int w = wr.Right - wr.Left, hh = wr.Bottom - wr.Top;
			if (w <= 0 || hh <= 0 || w > 16384 || hh > 16384) return "\"ok\":false,\"error\":\"bad size\"";
			Rectangle crop = new Rectangle(0, 0, w, hh);
			Native.RECT fr;
			if (Native.DwmGetWindowAttribute(h, DWMWA_EXTENDED_FRAME_BOUNDS, out fr, Marshal.SizeOf(typeof(Native.RECT))) == 0)
			{
				Rectangle f = Rectangle.FromLTRB(fr.Left - wr.Left, fr.Top - wr.Top, fr.Right - wr.Left, fr.Bottom - wr.Top);
				f.Intersect(crop);
				if (f.Width > 8 && f.Height > 8) crop = f;
			}
			// Leave out the window's 1px border, which Windows (and Oazy's own
			// app theming) tints with the accent colour: in a small picture it
			// reads as a coloured frame.
			if (crop.Width > 16 && crop.Height > 16) crop.Inflate(-2, -2);
			maxW = Math.Max(16, Math.Min(maxW, 2048));
			maxH = Math.Max(16, Math.Min(maxH, 2048));
			using (Bitmap full = new Bitmap(w, hh, PixelFormat.Format32bppArgb))
			{
				bool printed;
				using (Graphics g = Graphics.FromImage(full))
				{
					IntPtr dc = g.GetHdc();
					try { printed = Native.PrintWindow(h, dc, 2); }
					finally { g.ReleaseHdc(dc); }
				}
				if (!printed) return "\"ok\":false,\"error\":\"PrintWindow failed\"";
				double k = Math.Min(1.0, Math.Min((double)maxW / crop.Width, (double)maxH / crop.Height));
				int ow = Math.Max(1, (int)Math.Round(crop.Width * k));
				int oh = Math.Max(1, (int)Math.Round(crop.Height * k));
				using (Bitmap pic = new Bitmap(ow, oh, PixelFormat.Format32bppArgb))
				{
					using (Graphics g = Graphics.FromImage(pic))
					{
						g.CompositingMode = CompositingMode.SourceCopy;
						g.InterpolationMode = InterpolationMode.HighQualityBicubic;
						g.PixelOffsetMode = PixelOffsetMode.HighQuality;
						g.DrawImage(full, new Rectangle(0, 0, ow, oh), crop, GraphicsUnit.Pixel);
					}
					BitmapData bd = pic.LockBits(new Rectangle(0, 0, ow, oh), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
					byte[] px = new byte[ow * oh * 4];
					try
					{
						for (int y = 0; y < oh; y++)
							Marshal.Copy(new IntPtr(bd.Scan0.ToInt64() + (long)y * bd.Stride), px, y * ow * 4, ow * 4);
					}
					finally { pic.UnlockBits(bd); }
					double sum = 0, sum2 = 0;
					int n = 0;
					for (int i = 0; i < px.Length; i += 4)
					{
						byte b = px[i];
						px[i] = px[i + 2];
						px[i + 2] = b;
						px[i + 3] = 255;
						if ((i / 4) % 7 == 0)
						{
							double l = 0.3 * px[i] + 0.59 * px[i + 1] + 0.11 * px[i + 2];
							sum += l;
							sum2 += l * l;
							n++;
						}
					}
					double mean = n > 0 ? sum / n : 0;
					double dev = n > 0 ? Math.Sqrt(Math.Max(0, sum2 / n - mean * mean)) : 0;
					File.WriteAllBytes(path, px);
					return "\"ok\":true,\"w\":" + ow + ",\"h\":" + oh
						+ ",\"dev\":" + dev.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture);
				}
			}
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

		// Back under every other window, unless it already is. Windows lifts a
		// window it activates (a click on the desktop) and Godot lifts its own
		// when it restyles them; this runs on every change of the window in front.
		static void KeepDesktopDown()
		{
			IntPtr d = Desktop;
			if (d == IntPtr.Zero || !ShellOn) return;
			for (IntPtr n = Native.GetWindow(d, GW_HWNDNEXT); n != IntPtr.Zero; n = Native.GetWindow(n, GW_HWNDNEXT))
			{
				if (!Native.IsWindowVisible(n)) continue;
				// Asynchronous, so a busy Oazy never holds up the companion.
				Native.SetWindowPos(d, new IntPtr(1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_ASYNCWINDOWPOS);
				return;
			}
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
				Reserve = Math.Max(0, reserve);
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
				if (HideTray) AutoHideTray(true);
				HideExplorer();
				KeepDesktopDown();
				WriteRestore();
			}
			// The AppBar lives on the message loop's thread.
			ApplyAppBar(true);
			return "\"ok\":true,\"tray_hidden\":" + Json.Bool(TrayHidden) + ",\"appbar\":" + Json.Bool(AppBarOn);
		}

		static void ApplyAppBar(bool wait)
		{
			if (AppBarWnd == IntPtr.Zero) return;
			if (wait)
			{
				IntPtr ignored;
				Native.SendMessageTimeout(AppBarWnd, WM_SHELL_APPLY, IntPtr.Zero, IntPtr.Zero, SMTO_ABORTIFHUNG, 3000, out ignored);
			}
			else Native.PostMessage(AppBarWnd, WM_SHELL_APPLY, IntPtr.Zero, IntPtr.Zero);
		}

		static Native.APPBARDATA BarData()
		{
			Native.APPBARDATA d = new Native.APPBARDATA();
			d.cbSize = Marshal.SizeOf(typeof(Native.APPBARDATA));
			d.hWnd = AppBarWnd;
			d.uCallbackMessage = WM_APPBAR;
			d.uEdge = ABE_BOTTOM;
			return d;
		}

		// Message loop thread only. Registers, places or removes the AppBar to
		// match the shell state.
		static void SyncAppBar()
		{
			bool want;
			int reserve;
			IntPtr desktop;
			lock (ShellLock) { want = ShellOn && HideTray && Reserve > 0; reserve = Reserve; desktop = Desktop; }
			Native.APPBARDATA d = BarData();
			if (!want)
			{
				if (AppBarOn) Native.SHAppBarMessage(ABM_REMOVE, ref d);
				AppBarOn = false;
				return;
			}
			if (!AppBarOn)
			{
				AppBarOn = Native.SHAppBarMessage(ABM_NEW, ref d) != UIntPtr.Zero;
				if (!AppBarOn) return;
			}
			Native.RECT mon = MonitorRect(desktop != IntPtr.Zero ? desktop : AppBarWnd, false);
			d.rc = mon;
			d.rc.Top = mon.Bottom - reserve;
			Native.SHAppBarMessage(ABM_QUERYPOS, ref d);
			// Other bars on the same edge may push it up; keep its height.
			d.rc.Top = d.rc.Bottom - reserve;
			Native.SHAppBarMessage(ABM_SETPOS, ref d);
			Native.SetWindowPos(AppBarWnd, IntPtr.Zero, d.rc.Left, d.rc.Top, d.rc.Right - d.rc.Left, d.rc.Bottom - d.rc.Top, SWP_NOACTIVATE | SWP_NOOWNERZORDER | 0x4);
		}

		static IntPtr OnAppBarMessage(IntPtr h, uint msg, IntPtr w, IntPtr l)
		{
			try
			{
				if (msg == WM_SHELL_APPLY)
				{
					SyncAppBar();
					return IntPtr.Zero;
				}
				if (msg == WM_APPBAR)
				{
					uint code = (uint)w.ToInt64();
					if (code == ABN_POSCHANGED && AppBarOn) SyncAppBar();
					else if (code == ABN_FULLSCREENAPP) Dirty = true;
					return IntPtr.Zero;
				}
				if (msg == WM_DISPLAYCHANGE && AppBarOn)
				{
					SyncAppBar();
				}
				else if (TaskbarCreated != 0 && msg == TaskbarCreated)
				{
					// Explorer restarted: it forgot our bar and showed its own.
					AppBarOn = false;
					lock (ShellLock)
					{
						if (ShellOn && HideTray) { TrayHidden = false; AutoHideTray(true); HideExplorer(); }
					}
					SyncAppBar();
				}
			}
			catch (Exception) { }
			return Native.DefWindowProc(h, msg, w, l);
		}

		static void CreateAppBarWindow()
		{
			AppBarProc = new Native.WndProc(OnAppBarMessage);
			Native.WNDCLASSEX wc = new Native.WNDCLASSEX();
			wc.cbSize = Marshal.SizeOf(typeof(Native.WNDCLASSEX));
			wc.lpfnWndProc = AppBarProc;
			wc.hInstance = Native.GetModuleHandle(null);
			wc.lpszClassName = "OazyTaskbarSpace";
			Native.RegisterClassEx(ref wc);
			// Never shown: it only tells Windows how much room Oazy's taskbar takes.
			AppBarWnd = Native.CreateWindowEx(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, "OazyTaskbarSpace", "Oazy taskbar", 0x80000000, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, wc.hInstance, IntPtr.Zero);
			TaskbarCreated = Native.RegisterWindowMessage("TaskbarCreated");
		}

		// Explorer's taskbar on autohide gives its space back; ours takes it.
		static void AutoHideTray(bool on)
		{
			IntPtr tray = Native.FindWindow("Shell_TrayWnd", null);
			if (tray == IntPtr.Zero) return;
			Native.APPBARDATA d = new Native.APPBARDATA();
			d.cbSize = Marshal.SizeOf(typeof(Native.APPBARDATA));
			d.hWnd = tray;
			int state = (int)Native.SHAppBarMessage(ABM_GETSTATE, ref d).ToUInt32();
			if (on)
			{
				if (TrayState < 0) TrayState = state;
				if ((state & ABS_AUTOHIDE) == 0)
				{
					d.lParam = new IntPtr(state | ABS_AUTOHIDE);
					Native.SHAppBarMessage(ABM_SETSTATE, ref d);
				}
			}
			else if (TrayState >= 0)
			{
				if (state != TrayState)
				{
					d.lParam = new IntPtr(TrayState);
					Native.SHAppBarMessage(ABM_SETSTATE, ref d);
				}
				TrayState = -1;
			}
		}

		static void HideExplorer()
		{
			if (HideTray)
			{
				IntPtr tray = Native.FindWindow("Shell_TrayWnd", null);
				if (tray != IntPtr.Zero && Native.IsWindowVisible(tray)) Native.ShowWindow(tray, SW_HIDE);
				if (tray != IntPtr.Zero) TrayHidden = true;
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

		// Explorer brings its taskbar and desktop back now and then (Win key,
		// restarts); hide them again. The work area is left to the AppBar.
		static void ReassertShell()
		{
			lock (ShellLock)
			{
				if (!ShellOn) return;
				HideExplorer();
			}
			if (!AppBarOn) ApplyAppBar(false);
		}

		static void ExitShell()
		{
			lock (ShellLock)
			{
				ShellOn = false;
			}
			if (AppBarOn) ApplyAppBar(true);
			lock (ShellLock)
			{
				AutoHideTray(false);
				if (TrayHidden)
				{
					IntPtr tray = Native.FindWindow("Shell_TrayWnd", null);
					if (tray != IntPtr.Zero) Native.ShowWindow(tray, SW_SHOWNA);
					TrayHidden = false;
				}
				foreach (IntPtr h in HiddenDesktop) if (Native.IsWindow(h)) Native.ShowWindow(h, SW_SHOWNA);
				HiddenDesktop.Clear();
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
				File.WriteAllText(RestorePath, string.Format("{0} {1} {2} {3} {4} {5}", OrigWork.Left, OrigWork.Top, OrigWork.Right, OrigWork.Bottom, HideTray ? 1 : 0, TrayState));
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
					if (v.Length >= 6 && int.TryParse(v[5], out TrayState) && TrayState >= 0) AutoHideTray(false);
					TrayState = -1;
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

		// A game or video taking a whole screen. Not a maximised app: on a screen
		// where nothing keeps room for a taskbar (a second monitor) one covers
		// it too, its borders hanging off the edges. Not Windows' own
		// full-screen views either (Task View, Alt+Tab, Snap), which Windows
		// keeps its taskbar up for.
		static bool IsFullscreen(IntPtr h)
		{
			if (h == IntPtr.Zero || h == Desktop || Native.IsIconic(h)) return false;
			string cls = ClassName(h);
			if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd"
				|| cls == "MultitaskingViewFrame" || cls == "XamlExplorerHostIslandWindow" || cls == "ForegroundStaging")
				return false;
			Native.RECT r;
			if (!Native.GetWindowRect(h, out r)) return false;
			Native.RECT m = MonitorRect(h, false);
			if (r.Left > m.Left || r.Top > m.Top || r.Right < m.Right || r.Bottom < m.Bottom) return false;
			if (SameRect(r, m) || !Native.IsZoomed(h)) return true;
			// Maximised and hanging over the edges: just a maximised app, unless it
			// dropped its frame the way Chrome or a game does for fullscreen.
			return (Native.GetWindowLong(h, GWL_STYLE) & (WS_CAPTION | WS_THICKFRAME)) == 0;
		}

		// Fullscreen on the screen Oazy's desktop and taskbar are on: a game on
		// another monitor leaves Oazy's taskbar alone, as Windows' does.
		static bool FullscreenOverOazy(IntPtr h)
		{
			if (!IsFullscreen(h)) return false;
			IntPtr home = Desktop != IntPtr.Zero ? Desktop : Self;
			return home == IntPtr.Zero || Native.MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST) == Native.MonitorFromWindow(home, MONITOR_DEFAULTTONEAREST);
		}

		static bool ExclusiveFullscreen()
		{
			int state;
			// QUNS_RUNNING_D3D_FULL_SCREEN
			return Native.SHQueryUserNotificationState(out state) == 0 && state == 3;
		}

		static bool IsOazy(IntPtr h)
		{
			if (h == IntPtr.Zero) return false;
			if (h == Self) return true;
			uint pid;
			Native.GetWindowThreadProcessId(h, out pid);
			return ParentPid != 0 && pid == (uint)ParentPid;
		}

		// --- Window looks ------------------------------------------------------------

		// Oazy's own layers (taskbar, Start, previews, dialogs, Oazy's windows) are
		// screen-sized transparent windows cut to shape: no Alt+Tab entry, no
		// rounding or frame from Windows, dark like the rest. A `top` one stays
		// above other apps from now on (see KeepOnTop), whatever Godot does
		// with the window.
		static string Style(IntPtr h, string kind, bool top)
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
			lock (OnTop)
			{
				if (top) OnTop.Add(h.ToInt64());
				else OnTop.Remove(h.ToInt64());
			}
			if (top) Native.SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_ASYNCWINDOWPOS);
			return "\"ok\":true,\"kind\":" + Json.Str(kind);
		}

		// Every couple of seconds: Oazy's always-on-top layers that have somehow
		// dropped out of the topmost band go back into it.
		static void KeepOnTop()
		{
			List<IntPtr> drop = new List<IntPtr>();
			lock (OnTop)
			{
				List<long> gone = new List<long>();
				foreach (long k in OnTop)
				{
					IntPtr h = new IntPtr(k);
					if (!Native.IsWindow(h)) gone.Add(k);
					else if (Native.IsWindowVisible(h) && (Native.GetWindowLong(h, GWL_EXSTYLE) & WS_EX_TOPMOST) == 0) drop.Add(h);
				}
				foreach (long k in gone) OnTop.Remove(k);
			}
			foreach (IntPtr h in drop)
				Native.SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_ASYNCWINDOWPOS);
		}

		// One of Oazy's screen-sized windows back over the whole screen Oazy's
		// desktop is on, `inset` pixels short of the bottom (layers that stop
		// above the taskbar). Godot won't move or resize a window it counts as
		// fullscreen, so after a display change this is the only way. If it is
		// already right, Godot is just asked to read its position again (its
		// coordinates move when a monitor to the left or above comes or goes).
		static string Fit(IntPtr h, int inset)
		{
			if (h == IntPtr.Zero || !Native.IsWindow(h) || Native.IsIconic(h)) return "\"ok\":false";
			IntPtr home = Desktop != IntPtr.Zero ? Desktop : (Self != IntPtr.Zero ? Self : h);
			Native.RECT m = MonitorRect(home, false);
			m.Bottom -= Math.Max(0, inset);
			Native.RECT r;
			if (Native.GetWindowRect(h, out r) && SameRect(r, m))
			{
				Native.SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_FRAMECHANGED | SWP_ASYNCWINDOWPOS);
				return "\"ok\":true,\"moved\":false";
			}
			bool ok = Native.SetWindowPos(h, IntPtr.Zero, m.Left, m.Top, m.Right - m.Left, m.Bottom - m.Top, SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_ASYNCWINDOWPOS);
			return "\"ok\":" + Json.Bool(ok) + ",\"moved\":true";
		}

		// Gives other apps' window borders Oazy's accent (Windows 11). Only the
		// border: changing an app's dark mode or title bar colour after it is on
		// screen left DWM drawing a stale title bar (a dark band, or the wrong
		// shade over Mica) until the window was restored and maximised again.
		// The caption and text colours are still accepted, and ignored.
		static string Theme(bool on, int border, int caption, int text)
		{
			lock (ShellLock)
			{
				ThemeOn = on;
				ThemeBorder = border;
				if (!on) ResetTheme();
				else
				{
					foreach (long k in Themed)
					{
						int b = border;
						Native.DwmSetWindowAttribute(new IntPtr(k), DWMWA_BORDER_COLOR, ref b, 4);
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
				Themed.RemoveWhere(delegate(long k) { return !alive.Contains(k); });
				if (!ThemeOn) return;
				foreach (long k in alive)
				{
					if (Themed.Contains(k)) continue;
					IntPtr h = new IntPtr(k);
					// Oazy's own apps (Browser, Files, Terminal, Claude) set their own.
					if (Native.GetProp(h, "OazyGlass") != IntPtr.Zero) continue;
					int b = ThemeBorder;
					Native.DwmSetWindowAttribute(h, DWMWA_BORDER_COLOR, ref b, 4);
					Themed.Add(k);
				}
			}
		}

		static void ResetTheme()
		{
			foreach (long k in Themed)
			{
				IntPtr h = new IntPtr(k);
				if (!Native.IsWindow(h)) continue;
				int d = DWM_COLOR_DEFAULT;
				Native.DwmSetWindowAttribute(h, DWMWA_BORDER_COLOR, ref d, 4);
			}
			Themed.Clear();
		}

		// Show desktop, for other apps' windows and Oazy's together, so the two
		// never go opposite ways. If anything is showing (`oazyOpen`: Oazy's own
		// windows, in the OS window `layer`, which Oazy minimises itself),
		// everything steps aside and the desktop takes focus; if nothing is,
		// what stepped aside comes back in the order it was in, and the window
		// that was in front gets focus again.
		static string ShowDesktop(bool oazyOpen, IntPtr layer)
		{
			List<IntPtr> open = new List<IntPtr>();
			Native.EnumWindows(delegate(IntPtr h, IntPtr l)
			{
				uint pid;
				Native.GetWindowThreadProcessId(h, out pid);
				if (h == layer && oazyOpen) open.Add(h);
				else if (IsAppWindow(h, pid) && !Native.IsIconic(h)) open.Add(h);
				return true;
			}, IntPtr.Zero);
			if (open.Count > 0 || oazyOpen)
			{
				foreach (IntPtr h in open)
				{
					if (h != layer) ShowPolitely(h, SW_SHOWMINNOACTIVE);
				}
				lock (Peeked) { Peeked.Clear(); Peeked.AddRange(open); }
				IntPtr desktop = Desktop != IntPtr.Zero ? Desktop : Self;
				if (desktop != IntPtr.Zero)
				{
					lock (FocusLock) Activate(desktop);
					KeepDesktopDown();
				}
				return "\"ok\":true,\"action\":\"hide\"";
			}
			List<IntPtr> back;
			lock (Peeked) { back = new List<IntPtr>(Peeked); Peeked.Clear(); }
			back.RemoveAll(delegate(IntPtr h) { return !Native.IsWindow(h); });
			bool restored = false;
			// Back to front, so each one lands on top of the ones behind it...
			for (int i = back.Count - 1; i >= 0; i--)
			{
				if (back[i] == layer) continue;
				if (Native.IsIconic(back[i])) ShowPolitely(back[i], SW_RESTORE);
				restored = true;
			}
			// ...and Oazy's layer slots in under the window that was in front of
			// it (Oazy shows its windows in it again when this returns).
			int at = back.IndexOf(layer);
			if (at >= 0)
			{
				IntPtr after = at > 0 ? back[at - 1] : IntPtr.Zero;
				Native.SetWindowPos(layer, after, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_ASYNCWINDOWPOS);
			}
			if (back.Count > 0 && back[0] != layer) Focus(back[0]);
			return "\"ok\":true,\"action\":\"restore\",\"restored\":" + Json.Bool(restored)
				+ ",\"oazy_front\":" + Json.Bool(at == 0);
		}

		// ShowWindow, or for an app that stopped responding the kind that
		// doesn't wait for it.
		static void ShowPolitely(IntPtr h, int cmd)
		{
			if (Native.IsHungAppWindow(h)) Native.ShowWindowAsync(h, cmd);
			else Native.ShowWindow(h, cmd);
		}

		// --- Sound and media ----------------------------------------------------------

		static Guid NoContext = Guid.Empty;

		// Reads (and optionally sets) the default output's volume. Looked up on
		// every call so switching to headphones just works.
		static string Volume(float? set, int mute)
		{
			Native.IMMDeviceEnumerator en = null;
			Native.IMMDevice dev = null;
			Native.IAudioEndpointVolume vol = null;
			try
			{
				en = (Native.IMMDeviceEnumerator)new Native.MMDeviceEnumerator();
				if (en.GetDefaultAudioEndpoint(0, 1, out dev) != 0 || dev == null)
					return "\"ok\":false,\"error\":\"no speakers\"";
				Guid iid = typeof(Native.IAudioEndpointVolume).GUID;
				object o;
				if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0 || o == null)
					return "\"ok\":false,\"error\":\"no volume control\"";
				vol = (Native.IAudioEndpointVolume)o;
				if (set.HasValue)
				{
					vol.SetMasterVolumeLevelScalar(set.Value, ref NoContext);
					if (set.Value > 0f) vol.SetMute(false, ref NoContext);
				}
				if (mute >= 0) vol.SetMute(mute == 1, ref NoContext);
				float level;
				bool muted;
				vol.GetMasterVolumeLevelScalar(out level);
				vol.GetMute(out muted);
				return "\"ok\":true,\"level\":" + level.ToString("0.000", System.Globalization.CultureInfo.InvariantCulture)
					+ ",\"muted\":" + Json.Bool(muted)
					+ ",\"device\":" + Json.Str(DeviceName(dev));
			}
			finally
			{
				if (vol != null) Marshal.ReleaseComObject(vol);
				if (dev != null) Marshal.ReleaseComObject(dev);
				if (en != null) Marshal.ReleaseComObject(en);
			}
		}

		static string DeviceName(Native.IMMDevice dev)
		{
			Native.IPropertyStore store;
			if (dev.OpenPropertyStore(0, out store) != 0 || store == null) return "";
			try
			{
				Native.PROPERTYKEY key;
				key.fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0");
				key.pid = 14;
				Native.PROPVARIANT pv;
				if (store.GetValue(ref key, out pv) != 0) return "";
				string name = pv.vt == 31 && pv.p != IntPtr.Zero ? Marshal.PtrToStringUni(pv.p) : "";
				Native.PropVariantClear(ref pv);
				return name ?? "";
			}
			finally { Marshal.ReleaseComObject(store); }
		}

		static bool MediaKey(string which)
		{
			byte vk;
			switch (which)
			{
				case "play": vk = 0xB3; break;
				case "next": vk = 0xB0; break;
				case "prev": vk = 0xB1; break;
				default: return false;
			}
			Native.keybd_event(vk, 0, 0, UIntPtr.Zero);
			Native.keybd_event(vk, 0, 2, UIntPtr.Zero);
			return true;
		}

		// --- Events: window changes and the home hotkey ----------------------------------

		static void MessageLoop()
		{
			HookProc = new Native.WinEventProc(OnWinEvent);
			// Foreground, minimise start/end, object create/destroy/show/hide, title
			// changes, cloaked/uncloaked (store apps show by uncloaking).
			Native.SetWinEventHook(0x0003, 0x0003, IntPtr.Zero, HookProc, 0, 0, 0);
			Native.SetWinEventHook(0x0016, 0x0017, IntPtr.Zero, HookProc, 0, 0, 0);
			Native.SetWinEventHook(0x8000, 0x8003, IntPtr.Zero, HookProc, 0, 0, 0);
			Native.SetWinEventHook(0x800B, 0x800C, IntPtr.Zero, HookProc, 0, 0, 0);
			Native.SetWinEventHook(0x8017, 0x8018, IntPtr.Zero, HookProc, 0, 0, 0);
			bool hotkey = Native.RegisterHotKey(IntPtr.Zero, (int)HOTKEY_HOME, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 0x4F);
			Native.RegisterHotKey(IntPtr.Zero, (int)HOTKEY_DESKTOP, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 0x44);
			KeyProc = new Native.KeyboardProc(OnKey);
			KeyHook = Native.SetWindowsHookEx(WH_KEYBOARD_LL, KeyProc, Native.GetModuleHandle(null), 0);
			try { CreateAppBarWindow(); }
			catch (Exception) { AppBarWnd = IntPtr.Zero; }
			Write("{\"ev\":\"ready\",\"hotkey\":" + Json.Bool(hotkey) + "}");
			Native.MSG msg;
			while (Native.GetMessage(out msg, IntPtr.Zero, 0, 0) > 0)
			{
				if (msg.message == WM_HOTKEY && (uint)msg.wParam.ToInt64() == HOTKEY_DESKTOP) Write("{\"ev\":\"desktop_key\"}");
				else if (msg.message == WM_HOTKEY)
				{
					try { OnHotkey(); }
					catch (Exception) { }
				}
				Native.TranslateMessage(ref msg);
				Native.DispatchMessage(ref msg);
			}
		}

		static void OnWinEvent(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time)
		{
			// An exception here would end the companion (and Oazy's taskbar
			// would lose its windows until it restarted).
			try { WinEvent(ev, hwnd, idObject, idChild); }
			catch (Exception) { Dirty = true; }
		}

		static void WinEvent(uint ev, IntPtr hwnd, int idObject, int idChild)
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
			if (ev == 0x8002 && ShellOn && TrayHidden && ClassName(hwnd) == "Shell_TrayWnd")
			{
				// Explorer showed its taskbar (Win key): Oazy's is the one in use.
				Native.ShowWindow(hwnd, SW_HIDE);
				return;
			}
			if (ev == 0x0003)
			{
				NoteForeground(hwnd);
				ForegroundMoved(hwnd);
				KeepDesktopDown();
			}
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

		// --- Alt+Tab ------------------------------------------------------------------
		// While Oazy is the desktop, Alt+Tab opens Oazy's own switcher: the hook
		// swallows Tab (and the keys used to steer) and tells Oazy, which draws
		// it and switches when Alt comes up. Windows' own one still shows over
		// apps running as administrator (their keys never reach this hook), over
		// games in exclusive fullscreen, and whenever Oazy didn't answer the last time.

		static IntPtr OnKey(int code, IntPtr w, IntPtr l)
		{
			if (code >= 0)
			{
				Native.KBDLLHOOKSTRUCT k = (Native.KBDLLHOOKSTRUCT)Marshal.PtrToStructure(l, typeof(Native.KBDLLHOOKSTRUCT));
				uint msg = (uint)w.ToInt64();
				try
				{
					if ((k.flags & LLKHF_INJECTED) == 0 && SwitchKey(k.vkCode, msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN, (k.flags & LLKHF_ALTDOWN) != 0))
						return new IntPtr(1);
				}
				catch (Exception) { Switching = false; }
			}
			return Native.CallNextHookEx(KeyHook, code, w, l);
		}

		// True to swallow the key.
		static bool SwitchKey(uint vk, bool down, bool alt)
		{
			bool isAlt = vk == VK_MENU || vk == VK_LMENU || vk == VK_RMENU;
			if (!Switching)
			{
				if (!down || vk != VK_TAB || !alt || !SwitchWanted) return false;
				if (!SwitchAcked) return false;
				IntPtr fg = Native.GetForegroundWindow();
				uint pid;
				Native.GetWindowThreadProcessId(fg, out pid);
				bool self = fg == Self || (ParentPid != 0 && pid == (uint)ParentPid);
				// Over a game in exclusive fullscreen nothing else can draw, so
				// Windows' own switcher (which drops out of it) takes those.
				// Borderless fullscreen (browsers, videos, most games) is just
				// a big window, and Oazy's switcher shows over it.
				if (!self && ExclusiveFullscreen()) return false;
				Switching = true;
				SwitchAcked = false;
				// A key between Alt going down and up, so the app underneath
				// doesn't open its menu bar when Alt is let go.
				Native.keybd_event(VK_MASK, 0, 0, UIntPtr.Zero);
				Native.keybd_event(VK_MASK, 0, 2, UIntPtr.Zero);
				SwitchEvent(Shift() ? "open_back" : "open");
				return true;
			}
			if (isAlt)
			{
				if (!down) { Switching = false; SwitchEvent("done"); }
				return false;
			}
			if (!alt)
			{
				// Alt came up without us seeing it (a secure desktop took the keys).
				Switching = false;
				SwitchEvent("cancel");
				return false;
			}
			string key = null;
			switch (vk)
			{
				case VK_TAB: key = Shift() ? "prev" : "next"; break;
				case VK_LEFT: key = "left"; break;
				case VK_RIGHT: key = "right"; break;
				case VK_UP: key = "up"; break;
				case VK_DOWN: key = "down"; break;
				case VK_DELETE: key = "close"; break;
				case VK_RETURN: key = "done"; break;
				case VK_ESCAPE: key = "cancel"; break;
				case VK_SHIFT: case VK_LSHIFT: case VK_RSHIFT: return false;
			}
			if (key == null) return false;
			if (down)
			{
				if (key == "done" || key == "cancel") Switching = false;
				SwitchEvent(key);
			}
			return true;
		}

		// --- Kept pictures ----------------------------------------------------------
		// Windows can't draw a minimised window, so Alt+Tab would have nothing
		// to show for it. While enabled, a background thread keeps a recent
		// picture of every open window instead: the one in front every few
		// seconds (and soon after it comes to the front), the others now and
		// then, one at a time, and never while a fullscreen game is up. Each new
		// picture goes to <dir>\<hwnd>.kept.rgba with a "picture" event.

		static volatile string KeepDir = "";
		static int KeepW = 640, KeepH = 400;
		static Thread Keeper;
		static readonly Dictionary<long, DateTime> Kept = new Dictionary<long, DateTime>();

		static void KeepPictures(string dir, int w, int h)
		{
			KeepW = w;
			KeepH = h;
			KeepDir = dir ?? "";
			if (KeepDir != "" && Keeper == null)
			{
				Keeper = new Thread(KeepLoop);
				Keeper.IsBackground = true;
				Keeper.Priority = ThreadPriority.BelowNormal;
				Keeper.Start();
			}
		}

		static void KeepLoop()
		{
			IntPtr lastFg = IntPtr.Zero;
			DateTime fgSince = DateTime.UtcNow;
			while (true)
			{
				Thread.Sleep(600);
				string dir = KeepDir;
				if (dir == "") continue;
				try
				{
					IntPtr fg = Native.GetForegroundWindow();
					DateTime now = DateTime.UtcNow;
					if (fg != lastFg) { lastFg = fg; fgSince = now; }
					if (fg != IntPtr.Zero && IsFullscreen(fg)) continue;
					// Windows that are gone drop out.
					List<IntPtr> open = new List<IntPtr>();
					Native.EnumWindows(delegate(IntPtr h, IntPtr l)
					{
						uint pid;
						Native.GetWindowThreadProcessId(h, out pid);
						if (IsAppWindow(h, pid)) open.Add(h);
						return true;
					}, IntPtr.Zero);
					HashSet<long> alive = new HashSet<long>();
					foreach (IntPtr h in open) alive.Add(h.ToInt64());
					List<long> gone = new List<long>();
					foreach (long k in Kept.Keys) if (!alive.Contains(k)) gone.Add(k);
					foreach (long k in gone) Kept.Remove(k);
					// Pick one: the front window once it has had a moment to draw,
					// else whichever other window has gone longest without one.
					IntPtr pick = IntPtr.Zero;
					if (alive.Contains(fg.ToInt64()) && !Native.IsIconic(fg) && (now - fgSince).TotalMilliseconds >= 500
						&& Age(fg, now) >= ((now - fgSince).TotalSeconds < 2 ? 1.0 : 3.0))
						pick = fg;
					if (pick == IntPtr.Zero)
					{
						double oldest = 15.0;
						foreach (IntPtr h in open)
						{
							if (Native.IsIconic(h)) continue;
							double age = Age(h, now);
							if (age >= oldest) { oldest = age; pick = h; }
						}
					}
					if (pick == IntPtr.Zero) continue;
					Kept[pick.ToInt64()] = now;
					string path = Path.Combine(dir, pick.ToInt64() + ".kept.rgba");
					string r = Capture(pick, KeepW, KeepH, path);
					if (r.StartsWith("\"ok\":true")) Write("{\"ev\":\"picture\",\"hwnd\":" + pick.ToInt64() + "," + r + "}");
				}
				catch (Exception) { }
			}
		}

		static double Age(IntPtr h, DateTime now)
		{
			DateTime at;
			return Kept.TryGetValue(h.ToInt64(), out at) ? (now - at).TotalSeconds : 1e9;
		}

		static bool Shift() { return (Native.GetAsyncKeyState((int)VK_SHIFT) & 0x8000) != 0; }

		static void SwitchEvent(string key)
		{
			Write("{\"ev\":\"switch\",\"key\":" + Json.Str(key) + "}");
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
				// Oazy's taskbar can't be left out of place by a missed event: back
				// on top if it ever dropped out, and a fullscreen app that went away
				// without anything else coming to the front is noticed anyway.
				try
				{
					KeepOnTop();
					IntPtr fg = Native.GetForegroundWindow();
					if ((!IsOazy(fg) && FullscreenOverOazy(fg)) != LastFs) Dirty = true;
				}
				catch (Exception) { }
				if (ParentPid <= 0) continue;
				try
				{
					Process p = Process.GetProcessById(ParentPid);
					if (p.HasExited) { RestoreCursors(); ExitShell(); Environment.Exit(0); }
				}
				catch (ArgumentException) { RestoreCursors(); ClearThumbs(); ExitShell(); Environment.Exit(0); }
				catch (Exception) { }
			}
		}
	}

	// --- Sensors ------------------------------------------------------------------
	//
	// Every process with its CPU and memory, for Oazy's task manager. One
	// NtQuerySystemInformation call reads them all without opening a single
	// process (so it is cheap, and works for elevated and system ones too);
	// only processes seen for the first time are opened, once, for their path.
	// CPU is the share of all processor time since the previous call, so the
	// first call after a while reads zero.
	static class Procs
	{
		const int SystemProcessInformation = 5;
		const uint STATUS_INFO_LENGTH_MISMATCH = 0xC0000004;
		const uint PROCESS_TERMINATE = 0x1;
		static readonly object Lock = new object();
		static IntPtr Buf = IntPtr.Zero;
		static int BufLen;
		// pid -> create time + CPU time at the previous call.
		static Dictionary<long, long[]> Last = new Dictionary<long, long[]>();
		// "pid:create" -> exe path.
		static readonly Dictionary<string, string> Paths = new Dictionary<string, string>();
		static readonly Dictionary<long, string> Names = new Dictionary<long, string>();
		// Never ended from Oazy, whatever asks (the UI hides End for these too).
		static readonly string[] Critical = { "system", "registry", "smss.exe", "csrss.exe", "wininit.exe", "winlogon.exe", "services.exe", "lsass.exe", "lsaiso.exe", "memory compression", "secure system", "dwm.exe", "fontdrvhost.exe", "svchost.exe" };

		[DllImport("ntdll.dll")] static extern uint NtQuerySystemInformation(int cls, IntPtr buf, int len, out int ret);
		[DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
		[DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateProcess(IntPtr h, uint code);
		[DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

		static bool Query()
		{
			for (int tries = 0; tries < 6; tries++)
			{
				if (Buf == IntPtr.Zero)
				{
					BufLen = Math.Max(BufLen, 1 << 20);
					Buf = Marshal.AllocHGlobal(BufLen);
				}
				int need;
				uint st = NtQuerySystemInformation(SystemProcessInformation, Buf, BufLen, out need);
				if (st == 0) return true;
				if (st != STATUS_INFO_LENGTH_MISMATCH) return false;
				Marshal.FreeHGlobal(Buf);
				Buf = IntPtr.Zero;
				BufLen = Math.Max(need, BufLen) + (256 << 10);
			}
			return false;
		}

		public static string List(int parentPid)
		{
			lock (Lock)
			{
				if (!Query()) return "\"ok\":false,\"error\":\"process list unavailable\"";
				bool x64 = IntPtr.Size == 8;
				int oName = 0x38, oNameBuf = x64 ? 0x40 : 0x3C;
				int oPid = x64 ? 0x50 : 0x44, oParent = x64 ? 0x58 : 0x48, oSession = x64 ? 0x64 : 0x50;
				var rows = new List<long[]>();
				var names = new List<string>();
				var now = new Dictionary<long, long[]>();
				long den = 0, idle = 0;
				int off = 0;
				while (true)
				{
					IntPtr e = new IntPtr(Buf.ToInt64() + off);
					int next = Marshal.ReadInt32(e, 0);
					long priv = Marshal.ReadInt64(e, 0x08);
					long created = Marshal.ReadInt64(e, 0x20);
					long cpuTime = Marshal.ReadInt64(e, 0x28) + Marshal.ReadInt64(e, 0x30);
					long pid = Marshal.ReadIntPtr(e, oPid).ToInt64();
					long ppid = Marshal.ReadIntPtr(e, oParent).ToInt64();
					int session = Marshal.ReadInt32(e, oSession);
					int nameLen = Marshal.ReadInt16(e, oName) & 0xFFFF;
					IntPtr nameBuf = Marshal.ReadIntPtr(e, oNameBuf);
					string name = pid == 0 ? "Idle" : (nameBuf != IntPtr.Zero && nameLen > 0 ? Marshal.PtrToStringUni(nameBuf, nameLen / 2) : "System");
					long[] prev;
					long delta = 0;
					if (Last.TryGetValue(pid, out prev) && prev[0] == created) delta = Math.Max(0, cpuTime - prev[1]);
					now[pid] = new long[] { created, cpuTime };
					den += delta;
					if (pid == 0) idle = delta;
					else
					{
						rows.Add(new long[] { pid, ppid, session, priv, delta, created });
						names.Add(name);
					}
					if (next == 0) break;
					off += next;
				}
				// Paths of processes that are gone are forgotten.
				var alive = new HashSet<string>();
				Names.Clear();
				var sb = new StringBuilder(rows.Count * 160);
				var ci = System.Globalization.CultureInfo.InvariantCulture;
				for (int i = 0; i < rows.Count; i++)
				{
					long[] r = rows[i];
					string key = r[0] + ":" + r[5];
					alive.Add(key);
					Names[r[0]] = names[i].ToLowerInvariant();
					string exe;
					if (!Paths.TryGetValue(key, out exe))
					{
						exe = r[0] == 4 ? "" : Host.ExePath((uint)r[0]);
						Paths[key] = exe;
					}
					if (sb.Length > 0) sb.Append(',');
					sb.Append("{\"pid\":").Append(r[0])
						.Append(",\"ppid\":").Append(r[1])
						.Append(",\"s\":").Append(r[2])
						.Append(",\"t\":").Append(r[5])
						.Append(",\"n\":").Append(Json.Str(names[i]))
						.Append(",\"exe\":").Append(Json.Str(exe))
						.Append(",\"d\":").Append(Json.Str(Host.Description(exe)))
						.Append(",\"cpu\":").Append((den > 0 ? (double)r[4] / den : 0.0).ToString("0.0000", ci))
						.Append(",\"mem\":").Append(r[3])
						.Append('}');
				}
				var stale = new List<string>();
				foreach (string k in Paths.Keys) if (!alive.Contains(k)) stale.Add(k);
				foreach (string k in stale) Paths.Remove(k);
				Last = now;
				Native.MEMORYSTATUSEX mem = new Native.MEMORYSTATUSEX();
				mem.dwLength = (uint)Marshal.SizeOf(typeof(Native.MEMORYSTATUSEX));
				ulong total = 0, avail = 0;
				if (Native.GlobalMemoryStatusEx(ref mem)) { total = mem.ullTotalPhys; avail = mem.ullAvailPhys; }
				double busy = den > 0 ? 1.0 - (double)idle / den : -1;
				return "\"ok\":true,\"self\":" + parentPid + ",\"cpu\":" + busy.ToString("0.000", ci)
					+ ",\"mem_total\":" + total + ",\"mem_used\":" + (total - avail)
					+ ",\"cores\":" + Environment.ProcessorCount
					+ ",\"procs\":[" + sb.ToString() + "]";
			}
		}

		// "kill <pid>,<pid>...": ends each one. Ones Windows refuses (elevated,
		// another user's, protected) come back in "denied" so Oazy can offer to
		// ask for admin rights; ones already gone count as ended.
		public static string Kill(string pids, int parentPid)
		{
			int ended = 0;
			var denied = new List<string>();
			var refused = new List<string>();
			int self = Process.GetCurrentProcess().Id;
			foreach (string part in pids.Split(','))
			{
				uint pid;
				if (!uint.TryParse(part.Trim(), out pid)) continue;
				string name;
				lock (Lock) { Names.TryGetValue(pid, out name); }
				if (pid <= 4 || pid == (uint)parentPid || pid == (uint)self || (name != null && Array.IndexOf(Critical, name) >= 0))
				{
					refused.Add(pid.ToString());
					continue;
				}
				IntPtr h = OpenProcess(PROCESS_TERMINATE, false, pid);
				if (h == IntPtr.Zero)
				{
					int err = Marshal.GetLastWin32Error();
					if (err == 87) ended++;
					else denied.Add(pid.ToString());
					continue;
				}
				try
				{
					if (TerminateProcess(h, 1)) ended++;
					else if (Marshal.GetLastWin32Error() == 5) denied.Add(pid.ToString());
					else ended++;
				}
				finally { CloseHandle(h); }
			}
			return "\"ok\":" + Json.Bool(denied.Count == 0 && refused.Count == 0) + ",\"ended\":" + ended
				+ ",\"denied\":[" + string.Join(",", denied.ToArray()) + "],\"refused\":[" + string.Join(",", refused.ToArray()) + "]";
		}
	}

	// Clocks, temperatures and GPU load for the desktop's This PC widget, all
	// read without admin rights or a driver of Oazy's own: the CPU clock from
	// the counters Task Manager uses, NVIDIA GPUs through NVML (part of every
	// NVIDIA driver), other GPUs through what WDDM drivers report to Windows
	// (D3DKMT) plus the "GPU Engine" counters for load. Windows only exposes the
	// CPU's own temperature to kernel drivers, so rather than install one (the
	// old WinRing0 driver is on Microsoft's vulnerable-driver blocklist) the
	// opt-in CPU temperature comes from HWiNFO or LibreHardwareMonitor when one
	// is running, and otherwise from the motherboard's ACPI thermal zone.
	//
	// Some of these calls take tens of milliseconds, so a background thread
	// polls them and "stats" copies the last snapshot. It idles when nobody has
	// asked for a while (the desktop is hidden or a game is fullscreen).
	static class Sensors
	{
		static readonly object Lock = new object();
		static Thread Worker;
		static volatile bool WantCpuTemp;
		static long LastAsked;
		static string Snapshot = "";

		public static string Read(bool cpuTemp)
		{
			WantCpuTemp = cpuTemp;
			Interlocked.Exchange(ref LastAsked, DateTime.UtcNow.Ticks);
			lock (Lock)
			{
				if (Worker == null)
				{
					Worker = new Thread(Loop);
					Worker.IsBackground = true;
					Worker.Priority = ThreadPriority.BelowNormal;
					Worker.Start();
				}
				return Snapshot;
			}
		}

		static void Loop()
		{
			while (true)
			{
				if (new TimeSpan(DateTime.UtcNow.Ticks - Interlocked.Read(ref LastAsked)).TotalSeconds < 15)
				{
					string s;
					try { s = Poll(); }
					catch (Exception) { s = ""; }
					lock (Lock) Snapshot = s;
				}
				Thread.Sleep(2000);
			}
		}

		static string Poll()
		{
			StringBuilder sb = new StringBuilder();
			Num(sb, "cpu_mhz", CpuMhz());
			double mhz = -1, temp = -1, load = -1;
			string name = "";
			Adapters();
			if (!Hybrid && NvmlReady())
			{
				uint v;
				NvUtilization u;
				if (NvClock != null && NvClock(NvDevice, 0, out v) == 0) mhz = v;
				if (NvTemp != null && NvTemp(NvDevice, 0, out v) == 0) temp = v;
				if (NvLoad != null && NvLoad(NvDevice, out u) == 0) load = u.Gpu;
				name = NvDeviceName;
			}
			if (Gpu != 0)
			{
				if (name == "") name = GpuName;
				if (temp < 0) temp = KmtTemp();
				if (mhz < 0) mhz = KmtMhz();
				if (load < 0) load = EngineLoad();
			}
			if (name != "") sb.Append(",\"gpu_name\":").Append(Json.Str(name));
			Num(sb, "gpu_mhz", mhz);
			Num(sb, "gpu_temp", temp);
			Num(sb, "gpu_load", load);
			if (WantCpuTemp)
			{
				string src;
				double t = CpuTemp(out src);
				Num(sb, "cpu_temp", t);
				if (t >= 0) sb.Append(",\"cpu_temp_src\":").Append(Json.Str(src));
			}
			return sb.ToString();
		}

		static void Num(StringBuilder sb, string key, double v)
		{
			sb.Append(",\"").Append(key).Append("\":").Append(v.ToString("0.#", System.Globalization.CultureInfo.InvariantCulture));
		}

		[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr LoadLibrary(string path);
		[DllImport("kernel32.dll", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr lib, string name);

		static T Fn<T>(IntPtr lib, string name) where T : class
		{
			IntPtr p = GetProcAddress(lib, name);
			return p == IntPtr.Zero ? null : Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
		}

		// --- CPU clock ---

		static PerformanceCounter CpuFreq, CpuPerf;
		static bool CpuFailed;

		// "Processor Frequency" is the base clock; "% Processor Performance" is
		// how far above or below it the cores ran since the last read (turbo
		// shows as more than 100%), which is how Task Manager gets its "Speed".
		static double CpuMhz()
		{
			if (CpuFailed) return -1;
			try
			{
				if (CpuFreq == null)
				{
					CpuFreq = new PerformanceCounter("Processor Information", "Processor Frequency", "_Total", true);
					try
					{
						CpuPerf = new PerformanceCounter("Processor Information", "% Processor Performance", "_Total", true);
						CpuPerf.NextValue();
					}
					catch (Exception) { CpuPerf = null; }
				}
				double mhz = CpuFreq.NextValue();
				if (CpuPerf != null)
				{
					double perf = CpuPerf.NextValue();
					if (perf > 0) mhz *= perf / 100.0;
				}
				return mhz > 0 ? mhz : -1;
			}
			catch (Exception) { CpuFailed = true; return -1; }
		}

		// --- NVIDIA (NVML) ---

		[UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvInitFn();
		[UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvHandleFn(uint index, out IntPtr device);
		[UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvValueFn(IntPtr device, int kind, out uint value);
		[UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvLoadFn(IntPtr device, out NvUtilization util);
		[UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvNameFn(IntPtr device, byte[] name, uint length);

		[StructLayout(LayoutKind.Sequential)]
		struct NvUtilization { public uint Gpu, Memory; }

		static int NvState;
		static IntPtr NvDevice;
		static NvValueFn NvTemp, NvClock;
		static NvLoadFn NvLoad;
		static string NvDeviceName = "";

		static bool NvmlReady()
		{
			if (NvState != 0) return NvState > 0;
			NvState = -1;
			string pf = Environment.GetEnvironmentVariable("ProgramW6432");
			if (string.IsNullOrEmpty(pf)) pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
			string[] paths = {
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "nvml.dll"),
				Path.Combine(pf, "NVIDIA Corporation\\NVSMI\\nvml.dll"),
			};
			IntPtr lib = IntPtr.Zero;
			foreach (string path in paths)
			{
				if (!File.Exists(path)) continue;
				lib = LoadLibrary(path);
				if (lib != IntPtr.Zero) break;
			}
			if (lib == IntPtr.Zero) return false;
			NvInitFn init = Fn<NvInitFn>(lib, "nvmlInit_v2");
			NvHandleFn handle = Fn<NvHandleFn>(lib, "nvmlDeviceGetHandleByIndex_v2");
			NvNameFn name = Fn<NvNameFn>(lib, "nvmlDeviceGetName");
			NvTemp = Fn<NvValueFn>(lib, "nvmlDeviceGetTemperature");
			NvClock = Fn<NvValueFn>(lib, "nvmlDeviceGetClockInfo");
			NvLoad = Fn<NvLoadFn>(lib, "nvmlDeviceGetUtilizationRates");
			if (init == null || handle == null || init() != 0 || handle(0, out NvDevice) != 0) return false;
			if (name != null)
			{
				byte[] b = new byte[96];
				if (name(NvDevice, b, (uint)b.Length) == 0)
				{
					int end = Array.IndexOf(b, (byte)0);
					NvDeviceName = Encoding.UTF8.GetString(b, 0, end < 0 ? b.Length : end).Trim();
				}
			}
			NvState = 1;
			return true;
		}

		// --- Any WDDM GPU (D3DKMT), what Task Manager's GPU page reads ---

		[StructLayout(LayoutKind.Sequential)]
		struct KmtAdapterInfo { public uint Adapter; public uint LuidLow; public int LuidHigh; public uint Sources; public int PrecisePresent; }

		[StructLayout(LayoutKind.Sequential)]
		struct KmtEnum { public uint Count; public IntPtr Adapters; }

		[StructLayout(LayoutKind.Sequential)]
		struct KmtQuery { public uint Adapter; public int Type; public IntPtr Data; public uint Size; }

		[StructLayout(LayoutKind.Sequential)]
		struct KmtAdapterPerf
		{
			public uint PhysicalIndex;
			public ulong MemFreq, MaxMemFreq, MaxMemFreqOC, MemBandwidth, PcieBandwidth;
			public uint FanRpm, Power, Temperature;
			public byte PowerStateOverride;
		}

		[StructLayout(LayoutKind.Sequential)]
		struct KmtNodePerf
		{
			public uint Node, PhysicalIndex;
			public ulong Freq, MaxFreq, MaxFreqOC;
			public uint Voltage, VoltageMax, VoltageMaxOC;
			public ulong MaxLatency;
		}

		[StructLayout(LayoutKind.Sequential)]
		struct KmtSegments { public ulong Dedicated, DedicatedSystem, Shared; }

		[StructLayout(LayoutKind.Sequential)]
		struct KmtType { public uint Flags; }

		[DllImport("gdi32.dll")] static extern int D3DKMTEnumAdapters2(ref KmtEnum e);
		[DllImport("gdi32.dll")] static extern int D3DKMTQueryAdapterInfo(ref KmtQuery q);
		[DllImport("gdi32.dll")] static extern int D3DKMTCloseAdapter(ref uint adapter);

		const int KMT_REGISTRY_INFO = 8, KMT_SEGMENT_SIZE = 3, KMT_ADAPTER_TYPE = 15, KMT_NODE_PERF = 61, KMT_ADAPTER_PERF = 62;
		const uint TYPE_RENDER = 0x1, TYPE_SOFTWARE = 0x4, TYPE_HYBRID_DISCRETE = 0x10;

		static bool Enumerated, Hybrid;
		static uint Gpu;
		static string GpuLuid = "", GpuName = "";

		static bool Query<T>(uint adapter, int type, ref T data) where T : struct
		{
			int size = Marshal.SizeOf(typeof(T));
			IntPtr buf = Marshal.AllocHGlobal(size);
			try
			{
				Marshal.StructureToPtr(data, buf, false);
				KmtQuery q = new KmtQuery();
				q.Adapter = adapter;
				q.Type = type;
				q.Data = buf;
				q.Size = (uint)size;
				if (D3DKMTQueryAdapterInfo(ref q) != 0) return false;
				data = (T)Marshal.PtrToStructure(buf, typeof(T));
				return true;
			}
			finally { Marshal.FreeHGlobal(buf); }
		}

		// Picks the GPU with the most dedicated memory (the discrete one when a
		// PC has two), skipping Microsoft's software renderer.
		static void Adapters()
		{
			if (Enumerated) return;
			Enumerated = true;
			try
			{
				KmtEnum e = new KmtEnum();
				if (D3DKMTEnumAdapters2(ref e) != 0 || e.Count == 0) return;
				int stride = Marshal.SizeOf(typeof(KmtAdapterInfo));
				e.Adapters = Marshal.AllocHGlobal(stride * (int)e.Count);
				try
				{
					if (D3DKMTEnumAdapters2(ref e) != 0) return;
					ulong best = 0;
					KmtAdapterInfo pick = new KmtAdapterInfo();
					List<uint> handles = new List<uint>();
					for (int i = 0; i < e.Count; i++)
					{
						KmtAdapterInfo a = (KmtAdapterInfo)Marshal.PtrToStructure(new IntPtr(e.Adapters.ToInt64() + i * stride), typeof(KmtAdapterInfo));
						handles.Add(a.Adapter);
						KmtType kt = new KmtType();
						if (Query(a.Adapter, KMT_ADAPTER_TYPE, ref kt))
						{
							uint type = kt.Flags;
							if ((type & TYPE_HYBRID_DISCRETE) != 0) Hybrid = true;
							if ((type & TYPE_SOFTWARE) != 0 || (type & TYPE_RENDER) == 0) continue;
						}
						KmtSegments seg = new KmtSegments();
						Query(a.Adapter, KMT_SEGMENT_SIZE, ref seg);
						if (Gpu == 0 || seg.Dedicated > best)
						{
							best = seg.Dedicated;
							Gpu = a.Adapter;
							pick = a;
						}
					}
					foreach (uint h in handles)
					{
						if (h == Gpu) continue;
						uint c = h;
						D3DKMTCloseAdapter(ref c);
					}
					if (Gpu == 0) return;
					GpuLuid = string.Format("luid_0x{0:X8}_0x{1:X8}", pick.LuidHigh, pick.LuidLow);
					GpuName = KmtName(Gpu);
				}
				finally { Marshal.FreeHGlobal(e.Adapters); }
			}
			catch (Exception) { Gpu = 0; }
		}

		static string KmtName(uint adapter)
		{
			int size = 4 * 260 * 2;
			IntPtr buf = Marshal.AllocHGlobal(size);
			try
			{
				KmtQuery q = new KmtQuery();
				q.Adapter = adapter;
				q.Type = KMT_REGISTRY_INFO;
				q.Data = buf;
				q.Size = (uint)size;
				if (D3DKMTQueryAdapterInfo(ref q) != 0) return "";
				return (Marshal.PtrToStringUni(buf) ?? "").Trim();
			}
			catch (Exception) { return ""; }
			finally { Marshal.FreeHGlobal(buf); }
		}

		static double KmtTemp()
		{
			KmtAdapterPerf p = new KmtAdapterPerf();
			if (!Query(Gpu, KMT_ADAPTER_PERF, ref p) || p.Temperature == 0) return -1;
			double c = p.Temperature / 10.0;
			return c > 0 && c < 150 ? c : -1;
		}

		// Node 0 is the 3D engine on every driver Oazy has seen.
		static double KmtMhz()
		{
			KmtNodePerf p = new KmtNodePerf();
			if (!Query(Gpu, KMT_NODE_PERF, ref p) || p.Freq == 0) return -1;
			return p.Freq / 1000000.0;
		}

		// --- GPU load from the "GPU Engine" counters ---
		//
		// Like Task Manager: add up every process's share of each engine, then
		// take the busiest engine. One ReadCategory per poll, not one counter
		// per process.

		static Dictionary<string, CounterSample> EnginePrev = new Dictionary<string, CounterSample>();
		static bool EngineFailed;

		static double EngineLoad()
		{
			if (EngineFailed) return -1;
			try
			{
				InstanceDataCollectionCollection all = new PerformanceCounterCategory("GPU Engine").ReadCategory();
				InstanceDataCollection util = all["Utilization Percentage"];
				if (util == null) { EngineFailed = true; return -1; }
				Dictionary<string, CounterSample> now = new Dictionary<string, CounterSample>();
				Dictionary<string, double> engines = new Dictionary<string, double>();
				bool any = false;
				foreach (InstanceData d in util.Values)
				{
					string inst = d.InstanceName;
					int at = inst.IndexOf("luid_", StringComparison.OrdinalIgnoreCase);
					if (at < 0) continue;
					string engine = inst.Substring(at);
					if (GpuLuid != "" && !engine.StartsWith(GpuLuid, StringComparison.OrdinalIgnoreCase)) continue;
					now[inst] = d.Sample;
					CounterSample prev;
					if (!EnginePrev.TryGetValue(inst, out prev)) continue;
					any = true;
					double v;
					engines.TryGetValue(engine, out v);
					engines[engine] = v + CounterSample.Calculate(prev, d.Sample);
				}
				EnginePrev = now;
				if (!any) return -1;
				double max = 0;
				foreach (double v in engines.Values) max = Math.Max(max, v);
				return Math.Min(100.0, max);
			}
			catch (Exception) { EngineFailed = true; return -1; }
		}

		// --- CPU temperature (opt-in) ---

		static DateTime LhmRetry, OhmRetry, AcpiRetry;

		static double CpuTemp(out string src)
		{
			double t = HwInfoTemp();
			src = "hwinfo";
			if (t < 0) { t = WmiTemp("root\\LibreHardwareMonitor", ref LhmRetry); src = "lhm"; }
			if (t < 0) { t = WmiTemp("root\\OpenHardwareMonitor", ref OhmRetry); src = "ohm"; }
			if (t < 0) { t = AcpiTemp(); src = "acpi"; }
			return t;
		}

		static readonly string[] CpuLabels = {
			"cpu package", "cpu (tctl/tdie)", "cpu (tdie)", "cpu (tctl)", "cpu die (average)",
			"core (tctl/tdie)", "core (tdie)", "core (tctl)", "package", "core max", "core average",
		};

		static int LabelRank(string label)
		{
			int i = Array.IndexOf(CpuLabels, label.Trim().ToLowerInvariant());
			return i < 0 ? CpuLabels.Length : i;
		}

		[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr OpenFileMapping(uint access, bool inherit, string name);
		[DllImport("kernel32.dll")] static extern IntPtr MapViewOfFile(IntPtr map, uint access, uint high, uint low, UIntPtr bytes);
		[DllImport("kernel32.dll")] static extern bool UnmapViewOfFile(IntPtr view);
		[DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

		// HWiNFO's shared memory (Settings > Shared Memory Support), packed:
		// a header of offsets and counts, then fixed-size "reading" records
		// holding type (1 = temperature), labels, unit and current value.
		static double HwInfoTemp()
		{
			IntPtr map = OpenFileMapping(4, false, "Global\\HWiNFO_SENS_SM2");
			if (map == IntPtr.Zero) return -1;
			IntPtr view = MapViewOfFile(map, 4, 0, 0, UIntPtr.Zero);
			try
			{
				if (view == IntPtr.Zero || Marshal.ReadInt32(view, 0) != 0x53695748) return -1;
				long first = (uint)Marshal.ReadInt32(view, 32);
				long stride = (uint)Marshal.ReadInt32(view, 36);
				long count = (uint)Marshal.ReadInt32(view, 40);
				if (stride < 292 || count > 10000) return -1;
				double best = -1;
				int rank = int.MaxValue;
				for (long i = 0; i < count; i++)
				{
					IntPtr r = new IntPtr(view.ToInt64() + first + i * stride);
					if (Marshal.ReadInt32(r, 0) != 1) continue;
					string label = Marshal.PtrToStringAnsi(new IntPtr(r.ToInt64() + 12)) ?? "";
					int k = LabelRank(label);
					if (k == CpuLabels.Length && !label.StartsWith("CPU", StringComparison.OrdinalIgnoreCase)) continue;
					if (k >= rank) continue;
					string unit = Marshal.PtrToStringAnsi(new IntPtr(r.ToInt64() + 268)) ?? "";
					double v = BitConverter.Int64BitsToDouble(Marshal.ReadInt64(r, 284));
					if (unit.IndexOf('F') >= 0) v = (v - 32.0) * 5.0 / 9.0;
					if (v <= 0 || v > 150) continue;
					best = v;
					rank = k;
				}
				return best;
			}
			catch (Exception) { return -1; }
			finally
			{
				if (view != IntPtr.Zero) UnmapViewOfFile(view);
				CloseHandle(map);
			}
		}

		// LibreHardwareMonitor and OpenHardwareMonitor publish their sensors
		// over WMI while they run. A missing namespace is retried every 30 s.
		static double WmiTemp(string ns, ref DateTime retry)
		{
			if (DateTime.UtcNow < retry) return -1;
			try
			{
				double best = -1;
				int rank = int.MaxValue;
				using (System.Management.ManagementObjectSearcher s = new System.Management.ManagementObjectSearcher(ns, "SELECT Name, Identifier, Value FROM Sensor WHERE SensorType='Temperature'"))
				{
					foreach (System.Management.ManagementBaseObject o in s.Get())
					{
						string id = (Convert.ToString(o["Identifier"]) ?? "").ToLowerInvariant();
						if (id.IndexOf("cpu") < 0) continue;
						double v = Convert.ToDouble(o["Value"]);
						int k = LabelRank(Convert.ToString(o["Name"]) ?? "");
						if (v <= 0 || v > 150) continue;
						if (k < rank || (k == rank && v > best))
						{
							best = v;
							rank = k;
						}
					}
				}
				if (best < 0) retry = DateTime.UtcNow.AddSeconds(30);
				return best;
			}
			catch (Exception)
			{
				retry = DateTime.UtcNow.AddSeconds(30);
				return -1;
			}
		}

		// The motherboard's ACPI thermal zones (Kelvin). Close to the CPU on
		// most laptops; some desktops report a fixed value or none at all.
		static double AcpiTemp()
		{
			if (DateTime.UtcNow < AcpiRetry) return -1;
			try
			{
				InstanceDataCollectionCollection all = new PerformanceCounterCategory("Thermal Zone Information").ReadCategory();
				double best = -1;
				InstanceDataCollection fine = all["High Precision Temperature"];
				if (fine != null)
					foreach (InstanceData d in fine.Values) best = Math.Max(best, d.RawValue / 10.0 - 273.15);
				InstanceDataCollection coarse = all["Temperature"];
				if (best <= 0 && coarse != null)
					foreach (InstanceData d in coarse.Values) best = Math.Max(best, d.RawValue - 273.15);
				if (best > 5 && best < 125) return best;
			}
			catch (Exception) { }
			AcpiRetry = DateTime.UtcNow.AddSeconds(60);
			return -1;
		}
	}

	// --- Wi-Fi and wired networks ----------------------------------------------
	//
	// The Native Wifi API (wlanapi.dll) works for a standard user: listing the
	// networks around, scanning, connecting with a profile written for the
	// network, disconnecting and forgetting. Structs are read by offset so
	// the layout stays visible next to the docs.

	static class Wifi
	{
		public delegate void NotifyProc(IntPtr data, IntPtr ctx);

		[StructLayout(LayoutKind.Sequential)]
		struct ConnectParams
		{
			public int Mode;
			[MarshalAs(UnmanagedType.LPWStr)] public string Profile;
			public IntPtr Ssid;
			public IntPtr BssidList;
			public int BssType;
			public uint Flags;
		}

		[DllImport("wlanapi.dll")] static extern uint WlanOpenHandle(uint version, IntPtr reserved, out uint negotiated, out IntPtr handle);
		[DllImport("wlanapi.dll")] static extern uint WlanEnumInterfaces(IntPtr h, IntPtr reserved, out IntPtr list);
		[DllImport("wlanapi.dll")] static extern uint WlanGetAvailableNetworkList(IntPtr h, ref Guid iface, uint flags, IntPtr reserved, out IntPtr list);
		[DllImport("wlanapi.dll")] static extern uint WlanGetNetworkBssList(IntPtr h, ref Guid iface, IntPtr ssid, int bssType, bool secure, IntPtr reserved, out IntPtr list);
		[DllImport("wlanapi.dll")] static extern uint WlanScan(IntPtr h, ref Guid iface, IntPtr ssid, IntPtr ie, IntPtr reserved);
		[DllImport("wlanapi.dll")] static extern uint WlanQueryInterface(IntPtr h, ref Guid iface, int opcode, IntPtr reserved, out uint size, out IntPtr data, out int valueType);
		[DllImport("wlanapi.dll")] static extern uint WlanSetInterface(IntPtr h, ref Guid iface, int opcode, uint size, IntPtr data, IntPtr reserved);
		[DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] static extern uint WlanSetProfile(IntPtr h, ref Guid iface, uint flags, string xml, string security, bool overwrite, IntPtr reserved, out uint reason);
		[DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] static extern uint WlanDeleteProfile(IntPtr h, ref Guid iface, string name, IntPtr reserved);
		[DllImport("wlanapi.dll")] static extern uint WlanConnect(IntPtr h, ref Guid iface, ref ConnectParams p, IntPtr reserved);
		[DllImport("wlanapi.dll")] static extern uint WlanDisconnect(IntPtr h, ref Guid iface, IntPtr reserved);
		[DllImport("wlanapi.dll")] static extern uint WlanRegisterNotification(IntPtr h, uint sources, bool ignoreDup, NotifyProc cb, IntPtr ctx, IntPtr reserved, out uint prev);
		[DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] static extern uint WlanReasonCodeToString(uint reason, int size, StringBuilder text, IntPtr reserved);
		[DllImport("wlanapi.dll")] static extern void WlanFreeMemory(IntPtr p);

		const int OP_RADIO = 4, OP_CONNECTION = 7;
		const uint SOURCE_ACM = 0x08, SOURCE_MSM = 0x10;
		const int AVAILABLE_SIZE = 628, IFACE_SIZE = 532, BSS_SIZE = 360;

		public static Action<string> Emit;
		static IntPtr Handle = IntPtr.Zero;
		static uint OpenError;
		static NotifyProc Callback;
		static bool Internet;
		static DateTime InternetAt = DateTime.MinValue;

		static bool Open()
		{
			if (Handle != IntPtr.Zero) return true;
			uint v;
			IntPtr h;
			try { OpenError = WlanOpenHandle(2, IntPtr.Zero, out v, out h); }
			catch (Exception) { OpenError = 1; return false; }
			if (OpenError != 0) return false;
			Handle = h;
			Callback = OnNotify;
			uint prev;
			WlanRegisterNotification(Handle, SOURCE_ACM | SOURCE_MSM, true, Callback, IntPtr.Zero, IntPtr.Zero, out prev);
			return true;
		}

		// The first wireless adapter (most PCs have one) and its state.
		static bool Adapter(out Guid id, out int state)
		{
			id = Guid.Empty;
			state = 0;
			IntPtr list;
			if (!Open() || WlanEnumInterfaces(Handle, IntPtr.Zero, out list) != 0) return false;
			try
			{
				int n = Marshal.ReadInt32(list, 0);
				if (n < 1) return false;
				IntPtr e = new IntPtr(list.ToInt64() + 8);
				byte[] g = new byte[16];
				Marshal.Copy(e, g, 0, 16);
				id = new Guid(g);
				state = Marshal.ReadInt32(e, 16 + 512);
				return true;
			}
			finally { WlanFreeMemory(list); }
		}

		static byte[] Ssid(IntPtr at)
		{
			int len = Math.Min(32, Math.Max(0, Marshal.ReadInt32(at, 0)));
			byte[] b = new byte[len];
			if (len > 0) Marshal.Copy(new IntPtr(at.ToInt64() + 4), b, 0, len);
			return b;
		}

		static string Hex(byte[] b)
		{
			StringBuilder sb = new StringBuilder(b.Length * 2);
			foreach (byte x in b) sb.Append(x.ToString("x2"));
			return sb.ToString();
		}

		static string Name(byte[] b)
		{
			try { return new UTF8Encoding(false, true).GetString(b); }
			catch (Exception) { return Encoding.Default.GetString(b); }
		}

		static string Text(IntPtr at, int chars)
		{
			string s = Marshal.PtrToStringUni(at, chars);
			int z = s.IndexOf('\0');
			return z >= 0 ? s.Substring(0, z) : s;
		}

		static string Auth(int a)
		{
			switch (a)
			{
				case 1: return "open";
				case 2: return "wep";
				case 3: case 6: case 8: case 11: return "enterprise";
				case 4: return "wpa";
				case 7: return "wpa2";
				case 9: return "wpa3";
				case 10: return "owe";
			}
			return "other";
		}

		class Net
		{
			public byte[] Raw;
			public string Profile = "";
			public int Signal, AuthAlgo, Cipher;
			public bool Secure, Connected, Known, Connectable;
		}

		// One entry per name: Windows lists a network once per saved profile
		// and once more without one.
		static List<Net> Networks(Guid id)
		{
			List<Net> all = new List<Net>();
			IntPtr list;
			if (WlanGetAvailableNetworkList(Handle, ref id, 0, IntPtr.Zero, out list) != 0) return all;
			Dictionary<string, Net> seen = new Dictionary<string, Net>();
			try
			{
				int n = Marshal.ReadInt32(list, 0);
				for (int i = 0; i < n; i++)
				{
					IntPtr e = new IntPtr(list.ToInt64() + 8 + (long)i * AVAILABLE_SIZE);
					Net net = new Net();
					net.Raw = Ssid(new IntPtr(e.ToInt64() + 512));
					if (net.Raw.Length == 0 || Marshal.ReadInt32(e, 548) != 1) continue;
					net.Profile = Text(e, 256);
					net.Connectable = Marshal.ReadInt32(e, 556) != 0;
					net.Signal = Marshal.ReadInt32(e, 604);
					net.Secure = Marshal.ReadInt32(e, 608) != 0;
					net.AuthAlgo = Marshal.ReadInt32(e, 612);
					net.Cipher = Marshal.ReadInt32(e, 616);
					int flags = Marshal.ReadInt32(e, 620);
					net.Connected = (flags & 1) != 0;
					net.Known = (flags & 2) != 0;
					string key = Hex(net.Raw);
					Net had;
					if (seen.TryGetValue(key, out had))
					{
						had.Connected |= net.Connected;
						had.Signal = Math.Max(had.Signal, net.Signal);
						if (net.Known && !had.Known) { had.Known = true; had.Profile = net.Profile; }
						continue;
					}
					seen[key] = net;
					all.Add(net);
				}
			}
			finally { WlanFreeMemory(list); }
			all.Sort(delegate(Net a, Net b)
			{
				if (a.Connected != b.Connected) return a.Connected ? -1 : 1;
				return b.Signal.CompareTo(a.Signal);
			});
			return all;
		}

		// Radio: [software on, hardware on].
		static bool[] Radio(Guid id)
		{
			bool[] r = { true, true };
			uint size;
			IntPtr data;
			int type;
			if (WlanQueryInterface(Handle, ref id, OP_RADIO, IntPtr.Zero, out size, out data, out type) != 0) return r;
			try
			{
				int n = Marshal.ReadInt32(data, 0);
				bool sw = false, hw = false;
				for (int i = 0; i < n && i < 64; i++)
				{
					if (Marshal.ReadInt32(data, 4 + i * 12 + 4) == 1) sw = true;
					if (Marshal.ReadInt32(data, 4 + i * 12 + 8) == 1) hw = true;
				}
				if (n > 0) { r[0] = sw; r[1] = hw; }
			}
			finally { WlanFreeMemory(data); }
			return r;
		}

		// The live link: name, speed and band.
		static string Current(Guid id)
		{
			uint size;
			IntPtr data;
			int type;
			if (WlanQueryInterface(Handle, ref id, OP_CONNECTION, IntPtr.Zero, out size, out data, out type) != 0) return "";
			try
			{
				if (Marshal.ReadInt32(data, 0) != 1) return "";
				byte[] raw = Ssid(new IntPtr(data.ToInt64() + 520));
				byte[] bssid = new byte[6];
				Marshal.Copy(new IntPtr(data.ToInt64() + 560), bssid, 0, 6);
				long rx = (uint)Marshal.ReadInt32(data, 580);
				long tx = (uint)Marshal.ReadInt32(data, 584);
				int signal = Marshal.ReadInt32(data, 576);
				return "{\"id\":" + Json.Str(Hex(raw)) + ",\"ssid\":" + Json.Str(Name(raw))
					+ ",\"signal\":" + signal + ",\"mbps\":" + (Math.Max(rx, tx) / 1000)
					+ ",\"ghz\":" + Json.Str(Band(id, bssid)) + "}";
			}
			finally { WlanFreeMemory(data); }
		}

		static string Band(Guid id, byte[] bssid)
		{
			IntPtr list;
			try { if (WlanGetNetworkBssList(Handle, ref id, IntPtr.Zero, 1, false, IntPtr.Zero, out list) != 0) return ""; }
			catch (Exception) { return ""; }
			try
			{
				int n = Marshal.ReadInt32(list, 4);
				byte[] b = new byte[6];
				for (int i = 0; i < n; i++)
				{
					IntPtr e = new IntPtr(list.ToInt64() + 8 + (long)i * BSS_SIZE);
					Marshal.Copy(new IntPtr(e.ToInt64() + 40), b, 0, 6);
					bool same = true;
					for (int k = 0; k < 6; k++) if (b[k] != bssid[k]) same = false;
					if (!same) continue;
					long khz = (uint)Marshal.ReadInt32(e, 92);
					if (khz >= 5925000 && khz < 7200000) return "6";
					if (khz >= 4900000 && khz < 5925000) return "5";
					if (khz >= 2400000 && khz < 2500000) return "2.4";
					return "";
				}
			}
			finally { WlanFreeMemory(list); }
			return "";
		}

		static bool Virtual(NetworkInterface ni)
		{
			string d = (ni.Description + " " + ni.Name).ToLowerInvariant();
			foreach (string w in new string[] { "virtual", "hyper-v", "vmware", "vbox", "tap-", "tap ", "wintun", "wireguard", "loopback", "bluetooth", "vethernet", "npcap", "zerotier", "tailscale" })
				if (d.Contains(w)) return true;
			return false;
		}

		static string Wired()
		{
			StringBuilder sb = new StringBuilder("[");
			try
			{
				foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces())
				{
					if (ni.NetworkInterfaceType != NetworkInterfaceType.Ethernet && ni.NetworkInterfaceType != NetworkInterfaceType.GigabitEthernet) continue;
					if (Virtual(ni)) continue;
					if (sb.Length > 1) sb.Append(',');
					bool up = ni.OperationalStatus == OperationalStatus.Up;
					sb.Append("{\"name\":").Append(Json.Str(ni.Name))
						.Append(",\"device\":").Append(Json.Str(ni.Description))
						.Append(",\"up\":").Append(Json.Bool(up))
						.Append(",\"mbps\":").Append(up ? Math.Max(0, ni.Speed / 1000000) : 0).Append('}');
				}
			}
			catch (Exception) { }
			return sb.Append(']').ToString();
		}

		// Windows' own "is there internet" answer (Network List Manager).
		static bool HasInternet()
		{
			if ((DateTime.UtcNow - InternetAt).TotalSeconds < 4) return Internet;
			InternetAt = DateTime.UtcNow;
			try
			{
				Type t = Type.GetTypeFromCLSID(new Guid("DCB00C01-570F-4A9B-8D69-199FDBA5723B"));
				object nlm = Activator.CreateInstance(t);
				Internet = (bool)t.InvokeMember("IsConnectedToInternet", BindingFlags.GetProperty, null, nlm, null);
				Marshal.ReleaseComObject(nlm);
			}
			catch (Exception) { Internet = NetworkInterface.GetIsNetworkAvailable(); }
			return Internet;
		}

		static string StateName(int s)
		{
			switch (s)
			{
				case 1: return "connected";
				case 3: return "disconnecting";
				case 4: return "disconnected";
				case 5: case 6: case 7: return "connecting";
			}
			return "off";
		}

		// list: also the networks around (the tray icon only needs the link).
		public static string Status(bool list)
		{
			StringBuilder sb = new StringBuilder("\"ok\":true");
			sb.Append(",\"internet\":").Append(Json.Bool(HasInternet()));
			sb.Append(",\"ethernet\":").Append(Wired());
			Guid id;
			int state;
			if (!Adapter(out id, out state))
				return sb.Append(",\"wifi\":false").ToString();
			bool[] radio = Radio(id);
			sb.Append(",\"wifi\":true,\"radio\":").Append(Json.Bool(radio[0] && radio[1]))
				.Append(",\"hw_off\":").Append(Json.Bool(!radio[1]))
				.Append(",\"state\":").Append(Json.Str(StateName(state)));
			string cur = state == 1 ? Current(id) : "";
			if (cur != "") sb.Append(",\"current\":").Append(cur);
			if (list && radio[0] && radio[1])
			{
				sb.Append(",\"networks\":[");
				bool first = true;
				foreach (Net n in Networks(id))
				{
					if (!first) sb.Append(',');
					first = false;
					sb.Append("{\"id\":").Append(Json.Str(Hex(n.Raw)))
						.Append(",\"ssid\":").Append(Json.Str(Name(n.Raw)))
						.Append(",\"signal\":").Append(n.Signal)
						.Append(",\"secure\":").Append(Json.Bool(n.Secure))
						.Append(",\"auth\":").Append(Json.Str(Auth(n.AuthAlgo)))
						.Append(",\"known\":").Append(Json.Bool(n.Known))
						.Append(",\"connected\":").Append(Json.Bool(n.Connected))
						.Append(",\"connectable\":").Append(Json.Bool(n.Connectable)).Append('}');
				}
				sb.Append(']');
			}
			return sb.ToString();
		}

		static string Fail(string why) { return "\"ok\":false,\"error\":" + Json.Str(why); }

		public static string Scan()
		{
			Guid id;
			int state;
			if (!Adapter(out id, out state)) return Fail("No Wi-Fi adapter");
			return "\"ok\":" + Json.Bool(WlanScan(Handle, ref id, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero) == 0);
		}

		static string Xml(string s) { return SecurityElement.Escape(s); }

		// A profile like the one Windows writes when you join from its flyout.
		static string ProfileXml(Net n, string name, string key, bool auto)
		{
			string auth, enc, keyType = "passPhrase";
			switch (n.AuthAlgo)
			{
				case 1: auth = "open"; enc = n.Secure ? "WEP" : "none"; if (n.Secure) keyType = "networkKey"; break;
				case 2: auth = "shared"; enc = "WEP"; keyType = "networkKey"; break;
				case 4: auth = "WPAPSK"; enc = n.Cipher == 2 ? "TKIP" : "AES"; break;
				case 7: auth = "WPA2PSK"; enc = n.Cipher == 2 ? "TKIP" : "AES"; break;
				case 9: auth = "WPA3SAE"; enc = "AES"; break;
				case 10: auth = "OWE"; enc = "AES"; break;
				default: return "";
			}
			StringBuilder x = new StringBuilder();
			x.Append("<?xml version=\"1.0\"?><WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\">");
			x.Append("<name>").Append(Xml(name)).Append("</name><SSIDConfig><SSID><hex>").Append(Hex(n.Raw).ToUpperInvariant())
				.Append("</hex><name>").Append(Xml(name)).Append("</name></SSID></SSIDConfig>");
			x.Append("<connectionType>ESS</connectionType><connectionMode>").Append(auto ? "auto" : "manual").Append("</connectionMode>");
			x.Append("<MSM><security><authEncryption><authentication>").Append(auth).Append("</authentication><encryption>").Append(enc)
				.Append("</encryption><useOneX>false</useOneX>");
			if (auth == "WPA3SAE") x.Append("<transitionMode xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v4\">true</transitionMode>");
			x.Append("</authEncryption>");
			if (key != "")
				x.Append("<sharedKey><keyType>").Append(keyType).Append("</keyType><protected>false</protected><keyMaterial>")
					.Append(Xml(key)).Append("</keyMaterial></sharedKey>");
			x.Append("</security></MSM></WLANProfile>");
			return x.ToString();
		}

		static string Unbase(string b64)
		{
			if (b64 == "") return "";
			try { return Encoding.UTF8.GetString(Convert.FromBase64String(b64)); }
			catch (Exception) { return ""; }
		}

		// Joins a network: with its saved profile when there's one and no new
		// key, otherwise writes a profile first. The outcome arrives as a
		// "wifi" event once Windows has tried.
		public static string Connect(string hex, string keyB64, bool auto)
		{
			Guid id;
			int state;
			if (!Adapter(out id, out state)) return Fail("No Wi-Fi adapter");
			Net net = null;
			foreach (Net n in Networks(id))
				if (Hex(n.Raw) == hex) net = n;
			if (net == null) return Fail("That network is out of range");
			string key = Unbase(keyB64);
			string profile = net.Profile;
			bool created = false;
			if (!net.Known || key != "")
			{
				if (net.AuthAlgo == 3 || net.AuthAlgo == 6 || net.AuthAlgo == 8 || net.AuthAlgo == 11)
					return "\"ok\":false,\"error\":\"enterprise\"";
				profile = Name(net.Raw);
				string xml = ProfileXml(net, profile, key, auto);
				if (xml == "") return Fail("Windows needs to join this one");
				uint reason;
				uint err = WlanSetProfile(Handle, ref id, 0, xml, null, true, IntPtr.Zero, out reason);
				// Standard users can't always write all-user profiles: keep it to this user then.
				if (err == 5) err = WlanSetProfile(Handle, ref id, 2, xml, null, true, IntPtr.Zero, out reason);
				if (err != 0) return Fail(reason != 0 ? Reason(reason) : "Windows didn't accept that key (error " + err + ")");
				created = !net.Known;
			}
			ConnectParams p = new ConnectParams();
			p.Mode = 0;
			p.Profile = profile;
			p.BssType = 1;
			uint e = WlanConnect(Handle, ref id, ref p, IntPtr.Zero);
			return e == 0 ? "\"ok\":true,\"created\":" + Json.Bool(created) : Fail("Couldn't start connecting (error " + e + ")");
		}

		public static string Disconnect()
		{
			Guid id;
			int state;
			if (!Adapter(out id, out state)) return Fail("No Wi-Fi adapter");
			return "\"ok\":" + Json.Bool(WlanDisconnect(Handle, ref id, IntPtr.Zero) == 0);
		}

		public static string Forget(string hex)
		{
			Guid id;
			int state;
			if (!Adapter(out id, out state)) return Fail("No Wi-Fi adapter");
			foreach (Net n in Networks(id))
			{
				if (Hex(n.Raw) != hex || !n.Known) continue;
				uint e = WlanDeleteProfile(Handle, ref id, n.Profile, IntPtr.Zero);
				return e == 0 ? "\"ok\":true" : Fail(e == 5 ? "Only an administrator can forget this network" : "Couldn't forget it (error " + e + ")");
			}
			return Fail("Not a saved network");
		}

		// Turning the radio off and on; Windows may keep that for administrators.
		public static string SetRadio(bool on)
		{
			Guid id;
			int state;
			if (!Adapter(out id, out state)) return Fail("No Wi-Fi adapter");
			IntPtr data = Marshal.AllocHGlobal(12);
			try
			{
				Marshal.WriteInt32(data, 0, 0);
				Marshal.WriteInt32(data, 4, on ? 1 : 2);
				Marshal.WriteInt32(data, 8, on ? 1 : 2);
				uint e = WlanSetInterface(Handle, ref id, OP_RADIO, 12, data, IntPtr.Zero);
				return e == 0 ? "\"ok\":true" : "\"ok\":false,\"error\":" + Json.Str(e == 5 ? "denied" : "error " + e);
			}
			finally { Marshal.FreeHGlobal(data); }
		}

		static string Reason(uint code)
		{
			StringBuilder sb = new StringBuilder(512);
			try
			{
				if (WlanReasonCodeToString(code, sb.Capacity, sb, IntPtr.Zero) == 0) return sb.ToString().Trim();
			}
			catch (Exception) { }
			return "Reason " + code;
		}

		static void OnNotify(IntPtr data, IntPtr ctx)
		{
			try
			{
				uint source = (uint)Marshal.ReadInt32(data, 0);
				int code = Marshal.ReadInt32(data, 4);
				int size = Marshal.ReadInt32(data, 24);
				IntPtr p = Marshal.ReadIntPtr(data, IntPtr.Size == 8 ? 32 : 28);
				string what = "";
				string extra = "";
				if (source == SOURCE_ACM)
				{
					switch (code)
					{
						case 7: what = "scan"; break;
						case 8: what = "scan"; break;
						case 9: what = "connecting"; break;
						case 13: case 14: what = "adapter"; break;
						case 21: what = "disconnected"; break;
						case 10: case 11:
							if (p == IntPtr.Zero || size < 564) { what = code == 10 ? "connected" : "failed"; break; }
							uint reason = (uint)Marshal.ReadInt32(p, 560);
							what = code == 10 && reason == 0 ? "connected" : "failed";
							extra = ",\"ssid\":" + Json.Str(Name(Ssid(new IntPtr(p.ToInt64() + 516))));
							if (what == "failed") extra += ",\"reason\":" + Json.Str(Reason(reason)) + ",\"code\":" + reason;
							break;
					}
				}
				else if (source == SOURCE_MSM && code == 7) what = "radio";
				if (what != "" && Emit != null) Emit("{\"ev\":\"wifi\",\"what\":\"" + what + "\"" + extra + "}");
			}
			catch (Exception) { }
		}
	}
}
