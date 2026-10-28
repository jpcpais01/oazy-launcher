// Oazy media: what's playing, through Windows' own media controls (the
// "GlobalSystemMediaTransportControls" behind the volume flyout), so the
// music wallpaper can show the song and play, pause, skip and seek it.
//
// Built as a library next to the companion (native/oazy_host.cs), which loads
// it with reflection: it needs WinRT metadata to compile, and if that's
// missing only the now-playing bar is lost. C# 5, like the companion.
//
// Media.Start(emit) begins polling and sends {"ev":"media",...} through emit
// whenever something changes; Media.Command(cmd, arg) controls the session.

using System;
using System.Text;
using System.Threading;
using Windows.Media.Control;

namespace OazyMedia
{
	public static class Media
	{
		static Action<string> Emit;
		static GlobalSystemMediaTransportControlsSessionManager Manager;
		static readonly object Lock = new object();
		static GlobalSystemMediaTransportControlsSession Session;
		static string Prefer = "chrome";
		static string Last = "";
		static long LastSent;

		public static string Start(Action<string> emit)
		{
			Emit = emit;
			Manager = GlobalSystemMediaTransportControlsSessionManager.RequestAsync().AsTask().Result;
			Thread t = new Thread(Loop);
			t.IsBackground = true;
			t.Start();
			return "\"ok\":true";
		}

		public static string Command(string cmd, string arg)
		{
			GlobalSystemMediaTransportControlsSession s;
			lock (Lock) s = Session;
			switch (cmd)
			{
				case "prefer":
					lock (Lock) Prefer = arg ?? "";
					Last = "";
					return "\"ok\":true";
				case "refresh":
					Last = "";
					return "\"ok\":true";
			}
			if (s == null) return "\"ok\":false,\"error\":\"nothing playing\"";
			bool done = false;
			switch (cmd)
			{
				case "toggle": done = s.TryTogglePlayPauseAsync().AsTask().Result; break;
				case "play": done = s.TryPlayAsync().AsTask().Result; break;
				case "pause": done = s.TryPauseAsync().AsTask().Result; break;
				case "next": done = s.TrySkipNextAsync().AsTask().Result; break;
				case "prev": done = s.TrySkipPreviousAsync().AsTask().Result; break;
				case "seek":
					double sec;
					if (double.TryParse(arg, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out sec))
						done = s.TryChangePlaybackPositionAsync((long)(sec * 10000000.0)).AsTask().Result;
					break;
			}
			Last = "";
			return "\"ok\":" + (done ? "true" : "false");
		}

		static void Loop()
		{
			while (true)
			{
				try { Poll(); }
				catch (Exception) { }
				Thread.Sleep(400);
			}
		}

		// The session to show: one from the preferred app (Chrome) if any,
		// playing ones first; otherwise whatever Windows calls current.
		static GlobalSystemMediaTransportControlsSession Pick()
		{
			string prefer;
			lock (Lock) prefer = Prefer;
			GlobalSystemMediaTransportControlsSession best = null;
			int bestScore = -1;
			foreach (var s in Manager.GetSessions())
			{
				string app = (s.SourceAppUserModelId ?? "").ToLowerInvariant();
				int score = 0;
				if (prefer != "" && prefer != "all" && app.Contains(prefer)) score += 2;
				var info = s.GetPlaybackInfo();
				if (info != null && info.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing) score += 1;
				if (score > bestScore) { bestScore = score; best = s; }
			}
			if (best != null && bestScore >= 1) return best;
			return Manager.GetCurrentSession() ?? best;
		}

		static void Poll()
		{
			var s = Pick();
			lock (Lock) Session = s;
			var sb = new StringBuilder(256);
			sb.Append("{\"ev\":\"media\"");
			if (s == null)
			{
				sb.Append(",\"has\":false}");
				Send(sb.ToString(), Last != "none");
				Last = "none";
				return;
			}
			var props = s.TryGetMediaPropertiesAsync().AsTask().Result;
			var info = s.GetPlaybackInfo();
			var tl = s.GetTimelineProperties();
			bool playing = info != null && info.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
			double dur = tl != null ? (tl.EndTime - tl.StartTime).TotalSeconds : 0.0;
			double pos = tl != null ? (tl.Position - tl.StartTime).TotalSeconds : 0.0;
			// Apps report the position only now and then: carry it to now.
			if (playing && tl != null)
			{
				double since = (DateTimeOffset.Now - tl.LastUpdatedTime).TotalSeconds;
				if (since > 0.0 && since < 36000.0) pos += since;
			}
			if (dur > 0.0) pos = Math.Max(0.0, Math.Min(pos, dur));
			var c = info != null ? info.Controls : null;
			sb.Append(",\"has\":true");
			sb.Append(",\"app\":").Append(Str(s.SourceAppUserModelId));
			sb.Append(",\"title\":").Append(Str(props != null ? props.Title : ""));
			sb.Append(",\"artist\":").Append(Str(props != null ? props.Artist : ""));
			sb.Append(",\"album\":").Append(Str(props != null ? props.AlbumTitle : ""));
			sb.Append(",\"playing\":").Append(playing ? "true" : "false");
			sb.Append(",\"can_seek\":").Append(c != null && c.IsPlaybackPositionEnabled ? "true" : "false");
			sb.Append(",\"can_next\":").Append(c != null && c.IsNextEnabled ? "true" : "false");
			sb.Append(",\"can_prev\":").Append(c != null && c.IsPreviousEnabled ? "true" : "false");
			string key = sb.ToString() + ((long)(dur * 10)).ToString();
			sb.Append(",\"dur\":").Append(dur.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture));
			sb.Append(",\"pos\":").Append(pos.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture));
			sb.Append('}');
			Send(sb.ToString(), key != Last);
			Last = key;
		}

		// Sends on a change, and every few seconds anyway so the position
		// stays honest.
		static void Send(string json, bool changed)
		{
			long now = Environment.TickCount;
			if (!changed && now - LastSent < 3000) return;
			LastSent = now;
			if (Emit != null) Emit(json);
		}

		static string Str(string s)
		{
			if (s == null) return "\"\"";
			var sb = new StringBuilder(s.Length + 2);
			sb.Append('"');
			foreach (char ch in s)
			{
				if (ch == '"') sb.Append("\\\"");
				else if (ch == '\\') sb.Append("\\\\");
				else if (ch < 0x20) sb.Append("\\u").Append(((int)ch).ToString("x4"));
				else sb.Append(ch);
			}
			sb.Append('"');
			return sb.ToString();
		}
	}
}
