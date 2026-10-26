extends Node
## Your Oazy profile: the Google account you sign in with (name, email, photo),
## shown in Start, Settings and the desktop's greeting.
##
## Signing in happens on Google's own pages, in a small Oazy Browser window
## (Browser.sign_in). It signs the browser's shared WebView2 profile in, so Oazy
## Browser, Flow and every other web app are signed in with it at once. The
## Google accounts already in Chrome are offered to pick from (chrome_accounts):
## their names, emails and photos are in Chrome's profile files. Chrome's actual
## sessions can't be borrowed (Chrome encrypts its cookies for itself), so
## Google asks for your password or passkey once.

signal changed
## A sign-in started or ended (the window is open while `busy`).
signal busy_changed(busy: bool)

const DIR := "user://account"
const PROFILE := DIR + "/profile.json"
const PHOTO := DIR + "/photo"
const RESULT := DIR + "/signin-result.json"
## How long a sign-in window may stay open before Oazy stops listening for it.
const WAIT_MS := 20 * 60 * 1000
const MANAGE_URL := "https://myaccount.google.com/"
## Chrome's user data folders under %LOCALAPPDATA%, with the name to show.
const CHROMES := [["Google/Chrome/User Data", "Chrome"], ["Google/Chrome Beta/User Data", "Chrome Beta"]]

var full_name := ""
var email := ""
var photo: Texture2D
var busy := false

var _pending := {}
var _signing_out := false
var _started := 0
var _poll: Timer
var _mock_chrome: Array = []
var _mocked := false
var _photo_cache := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	if not App.smoke_test:
		_load()
	_poll = Timer.new()
	_poll.wait_time = 0.6
	_poll.timeout.connect(_check_result)
	add_child(_poll)


func signed_in() -> bool:
	return email != ""


## Who you are, for Start: your Google name, else the name you set, else
## Windows' account name.
func display_name() -> String:
	if full_name != "":
		return full_name
	var set_name := str(Settings.get_value("user_name")).strip_edges()
	if set_name != "":
		return set_name
	if email != "":
		return email.get_slice("@", 0)
	return App.user_name()


## The first name for the desktop's greeting ("" when Oazy doesn't know you).
func first_name() -> String:
	var set_name := str(Settings.get_value("user_name")).strip_edges()
	if set_name != "":
		return set_name
	if full_name != "":
		return full_name.get_slice(" ", 0)
	return App.user_name()


# --- Chrome's accounts -------------------------------------------------------------------

## The Google accounts Chrome knows on this PC, signed-in profiles first:
## [{name, email, photo_file, photo_url, from}]. Empty when there's no Chrome.
func chrome_accounts() -> Array:
	if _mocked:
		return _mock_chrome.duplicate(true)
	var out: Array = []
	if not App.is_windows():
		return out
	var seen := {}
	var local := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	if local == "":
		return out
	for spec in CHROMES:
		var root := local.path_join(spec[0])
		var state = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("Local State")))
		if not state is Dictionary:
			continue
		var cache: Dictionary = (state as Dictionary).get("profile", {}).get("info_cache", {})
		var order: Array = (state as Dictionary).get("profile", {}).get("profiles_order", cache.keys())
		for dir in cache.keys():
			if not order.has(dir):
				order.append(dir)
		var extra: Array = []
		for dir in order:
			var p = cache.get(dir)
			if not p is Dictionary:
				continue
			var profile_name := str(p.get("name", ""))
			# The account Chrome itself is signed in with.
			var mail := str(p.get("user_name", "")).strip_edges()
			if mail.contains("@") and not seen.has(mail.to_lower()):
				seen[mail.to_lower()] = true
				var pic := str(p.get("gaia_picture_file_name", ""))
				var file := root.path_join(str(dir)).path_join(pic) if pic != "" else ""
				out.append({
					"name": str(p.get("gaia_name", "")) if str(p.get("gaia_name", "")) != "" else profile_name,
					"email": mail,
					"photo_file": file if file != "" and FileAccess.file_exists(file) else "",
					"photo_url": str(p.get("last_downloaded_gaia_picture_url_with_size", "")),
					"from": spec[1] if profile_name == "" or profile_name == str(p.get("gaia_name", "")) else "%s · %s" % [spec[1], profile_name],
				})
			# Other Google accounts signed in on the web in that profile.
			var prefs = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(str(dir)).path_join("Preferences")))
			if prefs is Dictionary:
				for a in (prefs as Dictionary).get("account_info", []):
					if not a is Dictionary:
						continue
					var m := str(a.get("email", "")).strip_edges()
					if not m.contains("@") or seen.has(m.to_lower()):
						continue
					seen[m.to_lower()] = true
					extra.append({
						"name": str(a.get("full_name", "")),
						"email": m,
						"photo_file": "",
						"photo_url": str(a.get("picture_url", "")),
						"from": spec[1] if profile_name == "" else "%s · %s" % [spec[1], profile_name],
					})
		out.append_array(extra)
	return out


## Screenshots and tests: pretend Chrome has these accounts.
func set_mock_chrome(list: Array) -> void:
	_mock_chrome = list
	_mocked = true


## Screenshots and tests: be signed in as this person, without Google.
func set_mock(person: Dictionary, tex: Texture2D = null) -> void:
	full_name = str(person.get("name", ""))
	email = str(person.get("email", ""))
	photo = tex
	changed.emit()


## An account's picture (from chrome_accounts), loaded or fetched; calls
## `done` with the texture, or never when there's none.
func picture(acc: Dictionary, done: Callable) -> void:
	var file := str(acc.get("photo_file", ""))
	if file != "":
		var t := _load_tex(file)
		if t:
			done.call(t)
			return
	var url := big_photo(str(acc.get("photo_url", "")))
	if url == "":
		if acc.has("texture") and acc["texture"] is Texture2D:
			done.call(acc["texture"])
		return
	if _photo_cache.has(url):
		done.call(_photo_cache[url])
		return
	_download(url, "", func(t: Texture2D) -> void:
		_photo_cache[url] = t
		done.call(t)
	)


## A Google photo url asked for at a size that stays sharp in Oazy.
static func big_photo(url: String) -> String:
	if not url.begins_with("https://"):
		return ""
	var re := RegEx.create_from_string("=s\\d+(-c)?$")
	if re.search(url):
		return re.sub(url, "=s256-c")
	var path := RegEx.create_from_string("/s\\d+(-c)?/")
	if path.search(url):
		return path.sub(url, "/s256-c/")
	if url.contains("googleusercontent.com/a/") and not url.contains("="):
		return url + "=s256-c"
	return url


# --- Signing in and out --------------------------------------------------------------------

## Signs in with Google, with `acc` (from chrome_accounts) filled in when given.
## Google's page opens in a small Oazy window; when it's done, the account
## becomes your profile.
func sign_in(acc: Dictionary = {}) -> void:
	if busy:
		App.toast("Finish signing in to Google in the window that's open")
		Browser.sign_in(str(_pending.get("email", "")), ProjectSettings.globalize_path(RESULT))
		return
	if not App.is_windows():
		# Nowhere to sign in to Google here; Chrome's details make the profile.
		if not acc.is_empty():
			_apply({"name": acc.get("name", ""), "email": acc.get("email", "")}, acc)
		else:
			App.toast("Signing in with Google works on Windows")
		return
	_pending = acc
	_signing_out = false
	_begin()
	if not Browser.sign_in(str(acc.get("email", "")), ProjectSettings.globalize_path(RESULT)):
		_end()
		return
	App.toast("Finish signing in on Google's page" if acc.is_empty() else "Google will ask for %s's password or passkey" % str(acc.get("email", "")))


## Forgets your profile and signs Oazy Browser, Flow and every web app out of Google.
func sign_out() -> void:
	var was := email
	_clear()
	if App.is_windows() and not busy:
		_signing_out = true
		_begin()
		Browser.sign_out(ProjectSettings.globalize_path(RESULT))
	App.toast("Signed out of %s" % was if was != "" else "Signed out")


## Opens your Google Account's page in Oazy Browser.
func manage() -> void:
	if not Browser.open(MANAGE_URL):
		OS.shell_open(MANAGE_URL)


func _begin() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT))
	busy = true
	_started = Time.get_ticks_msec()
	_poll.start()
	busy_changed.emit(true)


func _end() -> void:
	busy = false
	_poll.stop()
	busy_changed.emit(false)


func _check_result() -> void:
	var path := ProjectSettings.globalize_path(RESULT)
	if not FileAccess.file_exists(path):
		if Time.get_ticks_msec() - _started > WAIT_MS:
			_end()
		return
	var r = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(path)
	_end()
	if not r is Dictionary:
		return
	if _signing_out:
		_signing_out = false
		return
	if not bool(r.get("ok", false)):
		if bool(r.get("cancelled", false)):
			App.toast("Sign-in cancelled")
		return
	_apply(r, _pending)
	_pending = {}


## Makes `r` (what Google said) your profile, with gaps filled from `acc`
## (what Chrome said).
func _apply(r: Dictionary, acc: Dictionary) -> void:
	var new_email := str(r.get("email", "")).strip_edges()
	if new_email == "":
		new_email = str(acc.get("email", ""))
	var new_name := str(r.get("name", "")).strip_edges()
	if new_name == "" and str(acc.get("email", "")).to_lower() == new_email.to_lower():
		new_name = str(acc.get("name", ""))
	if new_email == "":
		App.toast("Signed in to Google")
		return
	var same := new_email.to_lower() == email.to_lower()
	full_name = new_name
	email = new_email
	if not same:
		photo = null
		for ext in ["png", "jpg"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PHOTO + "." + ext))
	_save()
	changed.emit()
	Sfx.play(&"notify")
	App.toast("Signed in as %s" % (full_name if full_name != "" else email))
	# The photo: Google's (fresh), else Chrome's copy.
	var url := big_photo(str(r.get("photo", "")))
	if url != "":
		_download(url, PHOTO, func(t: Texture2D) -> void: _set_photo(t))
	elif str(acc.get("email", "")).to_lower() == email.to_lower():
		picture(acc, func(t: Texture2D) -> void:
			_set_photo(t)
			if t:
				t.get_image().save_png(ProjectSettings.globalize_path(PHOTO + ".png"))
		)


func _set_photo(t: Texture2D) -> void:
	if t == null or not signed_in():
		return
	photo = t
	changed.emit()


func _clear() -> void:
	full_name = ""
	email = ""
	photo = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	for ext in ["png", "jpg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PHOTO + "." + ext))
	changed.emit()


func _save() -> void:
	var f := FileAccess.open(PROFILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"name": full_name, "email": email}))
		f.close()


func _load() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	if not d is Dictionary:
		return
	full_name = str(d.get("name", ""))
	email = str(d.get("email", ""))
	for ext in ["png", "jpg"]:
		var t := _load_tex(ProjectSettings.globalize_path(PHOTO + "." + ext))
		if t:
			photo = t
			break


static func _load_tex(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK and img.load_jpg_from_buffer(bytes) != OK and img.load_webp_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(img)


## Fetches a picture; saves it as `save_as`.png when given. `done` gets the
## texture (only on success).
func _download(url: String, save_as: String, done: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
			return
		var img := Image.new()
		if img.load_jpg_from_buffer(body) != OK and img.load_png_from_buffer(body) != OK and img.load_webp_from_buffer(body) != OK:
			return
		if save_as != "":
			img.save_png(ProjectSettings.globalize_path(save_as + ".png"))
		done.call(ImageTexture.create_from_image(img))
	)
	if req.request(url, PackedStringArray(["User-Agent: " + App.USER_AGENT])) != OK:
		req.queue_free()
