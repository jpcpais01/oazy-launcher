class_name ClaudeMood
extends RefCounted
## How Claude feels, for its avatar in the orb popup (ClaudeBlob).
##
## Claude says it itself: ClaudeCli asks it to start each reply with a hidden
## tag such as [[mood:happy]], which is taken out before the reply is drawn
## (ChatMarkdown does it, so history shows clean too). When a reply has no tag,
## a few cues in its words stand in, and what you write gets a quick reaction
## of its own before Claude has said anything.

const MOODS := ["calm", "happy", "excited", "curious", "thoughtful", "concerned", "sorry", "playful", "proud", "surprised"]

static var _tag: RegEx
static var _partial: RegEx


static func _tags() -> RegEx:
	if _tag == null:
		_tag = RegEx.create_from_string("\\[\\[\\s*mood\\s*:\\s*([A-Za-z]+)\\s*\\]\\][ \\t]*\\n?")
		# A tag still arriving at the end of a streamed reply.
		_partial = RegEx.create_from_string("\\[(\\[(\\s*m(o(o(d(\\s*:\\s*[A-Za-z]*\\s*\\]?)?)?)?)?)?)?$")
	return _tag


## The moods tagged in a reply, in order (unknown words left out).
static func found(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not text.contains("[["):
		return out
	for m in _tags().search_all(text):
		var mood := m.get_string(1).to_lower()
		if MOODS.has(mood):
			out.append(mood)
	return out


## The reply as it's shown: tags out, and one half arrived held back.
static func strip(text: String) -> String:
	if text.contains("[["):
		text = _tags().sub(text, "", true)
	if text.ends_with("[") or text.contains("[["):
		_tags()
		var m := _partial.search(text)
		if m and m.get_start() >= text.length() - 24:
			text = text.substr(0, m.get_start())
	return text


## A mood from a reply's own words, for one that came without a tag.
static func guess(text: String) -> String:
	var t := text.to_lower()
	for w in ["sorry", "unfortunately", "i couldn't", "i can't", "i wasn't able", "failed", "doesn't seem to work"]:
		if t.contains(w):
			return "sorry"
	for w in ["done!", "all set", "there you go", "here you go", "great news", "nice!", "perfect"]:
		if t.contains(w):
			return "proud" if t.contains("done") or t.contains("all set") else "happy"
	if t.count("!") >= 2:
		return "happy"
	if t.strip_edges().ends_with("?"):
		return "curious"
	return "calm"


## A quick reaction to what you wrote, before Claude answers.
static func hearing(text: String) -> String:
	var t := " " + text.to_lower().strip_edges() + " "
	for w in ["thank", "thx", "obrigad", " love ", "awesome", "amazing", " great", "perfect", " nice", " cool", "haha", "lol", ":)", ":d", "<3", "❤", "brilliant", "well done", "good job"]:
		if t.contains(w):
			return "happy"
	for w in ["wow", "omg", "whoa", "no way", "really?"]:
		if t.contains(w):
			return "surprised"
	for w in ["sad", "tired", "broken", "doesn't work", "not working", "error", "bug", "crash", "fail", "stuck", "frustrat", "ugh", "annoy", "help me", "problem", "wrong"]:
		if t.contains(w):
			return "concerned"
	for w in [" hi ", " hey ", " hello ", " olá ", " ola ", " yo ", "good morning", "good evening", "good afternoon"]:
		if t.begins_with(w) or t.left(16).contains(w):
			return "excited"
	if t.count("!") >= 2:
		return "excited"
	if t.strip_edges().ends_with("?") or t.begins_with(" why ") or t.begins_with(" how ") or t.begins_with(" what "):
		return "curious"
	return "thoughtful"
