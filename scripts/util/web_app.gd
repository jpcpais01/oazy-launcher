class_name WebApp
## Oazy's own WebView2 apps (Browser, Terminal): a C# 5 program plus its HTML,
## shipped inside the exe and compiled on first use with the csc.exe that
## comes with Windows, so Oazy stays a single exe.
##
## build() unpacks `files` ({path in the app folder: res:// path}) into
## user://<folder>/app-<hash of the files> and compiles `cs` there into `exe`.
## A new Oazy with changed files builds a new folder and cleans up old ones.
## `refs` are extra .NET Framework assemblies the program uses.

const WEBVIEW2 := {
	"Microsoft.Web.WebView2.Core.dll": "res://native/browser/bin/Microsoft.Web.WebView2.Core.dll",
	"WebView2Loader.dll": "res://native/browser/bin/WebView2Loader.dll",
	"LICENSE.txt": "res://native/browser/bin/LICENSE.txt",
}
## Oazy's UI typeface, for every web app's page (shipped as .bin so Godot
## packs it untouched instead of importing it).
const FONTS := {
	"ui/fonts/Geist-Variable.woff2": "res://native/fonts/Geist-Variable.woff2.bin",
	"OFL-Geist.txt": "res://native/fonts/OFL-Geist.txt",
}


## Returns {"exe": path} or {"error": text}. Safe to call from a worker thread.
static func build(folder: String, exe_name: String, cs: String, icon: String, files: Dictionary, refs: Array = []) -> Dictionary:
	var hashes := PackedStringArray()
	var blobs := {}
	for f in files:
		var bytes := FileAccess.get_file_as_bytes(str(files[f]))
		if bytes.is_empty():
			return {"error": "%s is missing from the package" % str(files[f]).get_file()}
		blobs[f] = bytes
		hashes.append(str(f) + ":" + _md5(bytes))
	var key := "\n".join(hashes).md5_text().substr(0, 10)
	var root := ProjectSettings.globalize_path("user://" + folder)
	var dir := root.path_join("app-" + key)
	var exe := dir.path_join(exe_name)
	if FileAccess.file_exists(exe):
		return {"exe": exe}
	for f in files:
		var path := dir.path_join(str(f))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var out := FileAccess.open(path, FileAccess.WRITE)
		if out == null:
			return {"error": "Can't write to %s" % dir}
		out.store_buffer(blobs[f])
		out.close()
	var log := ""
	for csc in Host.CSC:
		if not FileAccess.file_exists(csc):
			continue
		var out := []
		var w := func(p: String) -> String: return dir.path_join(p).replace("/", "\\")
		var args := ["/nologo", "/optimize+", "/target:winexe", "/platform:x64",
			"/win32icon:" + w.call(icon),
			"/r:System.dll", "/r:System.Core.dll", "/r:System.Drawing.dll", "/r:System.Windows.Forms.dll", "/r:System.Web.Extensions.dll",
			"/r:" + w.call("Microsoft.Web.WebView2.Core.dll")]
		for r in refs:
			args.append("/r:" + str(r))
		args.append_array(["/out:" + w.call(exe_name + ".tmp"), w.call(cs)])
		var code := OS.execute(csc, args, out, true)
		if code == 0 and FileAccess.file_exists(dir.path_join(exe_name + ".tmp")):
			DirAccess.rename_absolute(dir.path_join(exe_name + ".tmp"), exe)
			_clean_old(root, "app-" + key, exe_name)
			return {"exe": exe}
		log = "\n".join(out).strip_edges().substr(0, 600)
	if log == "":
		return {"error": "The .NET Framework C# compiler wasn't found"}
	return {"error": "build failed: " + log}


## Is this real window one of the app's? (`folder` as passed to build.)
static func owns_window(w: Dictionary, folder: String, exe_name: String) -> bool:
	var exe := str(w.get("exe", "")).replace("\\", "/").to_lower()
	return exe.get_file() == exe_name.to_lower() and exe.contains("/%s/app-" % folder)


static func _md5(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## Older builds go, unless one is still running (its files are locked).
static func _clean_old(root: String, keep: String, exe_name: String) -> void:
	for d in DirAccess.get_directories_at(root):
		if not d.begins_with("app-") or d == keep:
			continue
		var path := root.path_join(d)
		if DirAccess.remove_absolute(path.path_join(exe_name)) != OK and FileAccess.file_exists(path.path_join(exe_name)):
			continue
		_remove_tree(path)


static func _remove_tree(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)
