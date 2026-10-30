class_name ClaudeMood
extends RefCounted
## How Claude feels, for its avatar in the orb popup (ClaudeBlob).
##
## Claude says it itself: ClaudeCli asks it to start each reply with a hidden
## tag such as [[mood:happy]], which is taken out before the reply is drawn
## (ChatMarkdown does it, so history shows clean too). When a reply has no tag,
## a few cues in its words stand in, and what you write gets a quick reaction
## of its own before Claude has said anything.
##
## What a conversation is about comes the same way: a [[topic:...]] tag
## (one of ClaudeScene.TOPICS, or none), and before that a guess from your
## own words, so the avatar can get its props out straight away.

const MOODS := ["calm", "happy", "excited", "curious", "thoughtful", "concerned", "sorry", "playful", "proud", "surprised", "loving", "amazed", "laughing", "shy", "confused", "determined"]

## Words that hint at a topic (English and Portuguese, lower case). Short
## ones are matched as whole words.
const TOPIC_WORDS := {
	"finance": ["finance", "financ", "money", "stock", "stocks", "invest", "budget", "crypto", "bitcoin", "btc", "eth", "trading", "trade", "portfolio", "dividend", "inflation", "salary", "tax", "taxes", "bank", "loan", "mortgage", "market", "hyperliquid", "dinheiro", "ações", "acoes", "investir", "orçamento", "orcamento", "imposto", "banco", "salário", "salario", "economy", "economia", "price", "preço", "preco", "euro", "dollar", "usd", "eur"],
	"physics": ["physics", "física", "fisica", "quantum", "gravity", "gravidade", "relativity", "relatividade", "newton", "einstein", "velocity", "velocidade", "momentum", "energy", "energia", "force", "força", "forca", "particle", "partícula", "atom", "átomo", "atomo", "electron", "photon", "thermodynamics", "entropy", "magnet", "wave", "onda"],
	"math": ["math", "maths", "mathematics", "matemática", "matematica", "equation", "equação", "equacao", "algebra", "álgebra", "calculus", "cálculo", "calculo", "integral", "derivative", "derivada", "geometry", "geometria", "theorem", "teorema", "matrix", "matriz", "probability", "probabilidade", "statistics", "estatística", "estatistica", "fraction", "fração", "sqrt", "pi", "trigonometry", "vector", "vetor"],
	"code": ["code", "coding", "código", "codigo", "program", "programming", "programar", "function", "função", "funcao", "python", "javascript", "typescript", "rust", "c#", "c++", "java", "gdscript", "godot", "compile", "compiler", "git", "github", "repo", "commit", "pull request", "api", "debug", "regex", "sql", "html", "css", "react", "npm", "terminal", "bash", "powershell", "variable", "bug", "deploy"],
	"music": ["music", "música", "musica", "song", "songs", "canção", "cancao", "album", "spotify", "playlist", "guitar", "guitarra", "piano", "band", "banda", "singer", "cantor", "lyrics", "letra", "concert", "concerto", "melody", "chord", "acorde", "beat", "rap", "jazz", "rock", "dj"],
	"art": ["art", "arte", "drawing", "draw", "desenho", "desenhar", "paint", "painting", "pintura", "pintar", "artist", "artista", "sketch", "illustration", "ilustração", "design", "logo", "colour", "color", "cor", "palette", "paleta", "museum", "museu", "photoshop", "figma"],
	"science": ["chemistry", "química", "quimica", "chemical", "molecule", "molécula", "molecula", "reaction", "reação", "reacao", "biology", "biologia", "cell", "célula", "celula", "dna", "gene", "genetic", "lab", "laboratory", "laboratório", "experiment", "experiência", "science", "ciência", "ciencia", "acid", "ácido", "element", "periodic"],
	"space": ["space", "espaço", "espaco", "planet", "planeta", "star", "stars", "estrela", "galaxy", "galáxia", "galaxia", "universe", "universo", "nasa", "spacex", "rocket", "foguete", "moon", "lua", "mars", "marte", "orbit", "órbita", "orbita", "astronaut", "astronauta", "telescope", "telescópio", "black hole", "buraco negro", "cosmos", "astronomy", "astronomia", "nebula", "jupiter", "saturn", "saturno"],
	"weather": ["weather", "tempo lá fora", "meteorologia", "forecast", "previsão", "previsao", "rain", "chuva", "raining", "snow", "neve", "sunny", "sol", "storm", "tempestade", "cloud", "nuvem", "temperature", "temperatura", "umbrella", "guarda-chuva", "wind", "vento", "humidity"],
	"food": ["food", "comida", "recipe", "receita", "cook", "cooking", "cozinhar", "dinner", "jantar", "lunch", "almoço", "almoco", "breakfast", "pequeno-almoço", "pasta", "pizza", "bake", "baking", "soup", "sopa", "restaurant", "restaurante", "eat", "comer", "meal", "refeição", "chef", "kitchen", "cozinha", "bacalhau", "cake", "bolo"],
	"games": ["game", "games", "jogo", "jogos", "gaming", "steam", "playstation", "ps5", "xbox", "nintendo", "switch", "minecraft", "fortnite", "elden ring", "gta", "rpg", "fps", "controller", "comando", "nível", "boss", "speedrun", "esports"],
	"sport": ["sport", "sports", "desporto", "football", "futebol", "soccer", "benfica", "porto", "sporting", "ronaldo", "messi", "goal", "golo", "jogo de futebol", "basketball", "nba", "tennis", "ténis", "tenis", "gym", "ginásio", "ginasio", "workout", "treino", "correr", "marathon", "maratona", "f1", "formula 1", "champions", "league", "liga", "world cup", "mundial"],
	"travel": ["travel", "viagem", "viajar", "trip", "holiday", "vacation", "férias", "ferias", "flight", "voo", "airport", "aeroporto", "hotel", "country", "país", "pais", "city", "cidade", "map", "mapa", "visit", "visitar", "tourist", "turista", "passport", "passaporte", "beach", "praia", "japan", "japão", "paris", "lisbon", "lisboa", "geography", "geografia"],
	"books": ["book", "books", "livro", "livros", "read", "reading", "ler", "leitura", "novel", "romance", "author", "autor", "story", "história", "historia", "history", "poem", "poema", "poetry", "poesia", "literature", "literatura", "library", "biblioteca", "write", "writing", "escrever", "essay", "ensaio", "chapter", "capítulo", "study", "estudar", "exam", "exame", "homework", "philosophy", "filosofia"],
	"health": ["health", "saúde", "saude", "doctor", "médico", "medico", "medicine", "medicina", "medicamento", "sick", "doente", "symptom", "sintoma", "pain", "dor", "heart", "coração", "coracao", "hospital", "diet", "dieta", "sleep", "dormir", "vitamin", "vitamina", "headache", "fever", "febre", "blood", "sangue", "therapy", "terapia", "anxiety", "ansiedade", "stress"],
	"nature": ["nature", "natureza", "plant", "plants", "planta", "plantas", "garden", "jardim", "flower", "flor", "flores", "tree", "árvore", "arvore", "forest", "floresta", "animal", "animals", "animais", "dog", "cão", "cao", "cat", "gato", "bird", "pássaro", "passaro", "climate", "clima", "environment", "ambiente", "ocean", "oceano", "mountain", "montanha", "hike", "caminhada", "grow", "seed", "semente"],
	"party": ["party", "festa", "birthday", "aniversário", "aniversario", "anos", "celebrate", "celebrar", "celebration", "congrats", "congratulations", "parabéns", "parabens", "wedding", "casamento", "christmas", "natal", "new year", "ano novo", "gift", "presente", "surprise party", "anniversary"],
	"film": ["film", "films", "filme", "filmes", "movie", "movies", "cinema", "netflix", "series", "série", "serie", "tv", "episode", "episódio", "episodio", "anime", "ator", "actress", "atriz", "director", "realizador", "trailer", "hbo", "disney", "marvel", "oscar", "youtube"],
	"language": ["translate", "translation", "traduzir", "tradução", "traducao", "language", "languages", "língua", "lingua", "idioma", "english", "inglês", "ingles", "portuguese", "português", "portugues", "spanish", "espanhol", "french", "francês", "frances", "german", "alemão", "alemao", "japanese", "japonês", "grammar", "gramática", "gramatica", "word", "palavra", "pronounce", "pronúncia", "meaning", "significa", "vocabulary"],
	"planning": ["plan", "plano", "planear", "planning", "schedule", "horário", "horario", "agenda", "calendar", "calendário", "calendario", "todo", "to-do", "to do", "tasks", "tarefas", "list", "lista", "organize", "organise", "organizar", "productivity", "produtividade", "deadline", "prazo", "meeting", "reunião", "reuniao", "goals", "objetivos", "routine", "rotina", "checklist", "remind", "lembrar"],
	"security": ["security", "segurança", "seguranca", "password", "passwords", "palavra-passe", "senha", "privacy", "privacidade", "hack", "hacker", "hacked", "virus", "vírus", "malware", "encrypt", "encryption", "encriptação", "vpn", "firewall", "2fa", "phishing", "scam", "burla", "lock", "secure", "antivirus", "breach"],
	"ai": ["ai", "ia", "artificial intelligence", "inteligência artificial", "inteligencia artificial", "llm", "gpt", "chatgpt", "claude", "anthropic", "openai", "machine learning", "neural", "model", "modelo", "robot", "robô", "robo", "agent", "agente", "prompt", "gemini", "deep learning"],
}

static var _word: RegEx

static var _tag: RegEx
static var _partial: RegEx


static func _tags() -> RegEx:
	if _tag == null:
		_tag = RegEx.create_from_string("\\[\\[\\s*(mood|topic)\\s*:\\s*([A-Za-z]+)\\s*\\]\\][ \\t]*\\n?")
		# A tag still arriving at the end of a streamed reply.
		_partial = RegEx.create_from_string("\\[(\\[(\\s*(m(o(o(d(\\s*:\\s*[A-Za-z]*\\s*\\]?)?)?)?)?|t(o(p(i(c(\\s*:\\s*[A-Za-z]*\\s*\\]?)?)?)?)?)?)?)?)?$")
	return _tag


## The moods tagged in a reply, in order (unknown words left out).
static func found(text: String) -> PackedStringArray:
	return _found(text, "mood", MOODS)


## The topics tagged in a reply, in order ("none" included).
static func topics(text: String) -> PackedStringArray:
	return _found(text, "topic", ClaudeScene.TOPICS + ["none"])


static func _found(text: String, what: String, known: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if not text.contains("[["):
		return out
	for m in _tags().search_all(text):
		if m.get_string(1).to_lower() != what:
			continue
		var word := m.get_string(2).to_lower()
		if known.has(word):
			out.append(word)
	return out


## The topic your words are most likely about, or "".
static func topic(text: String) -> String:
	if _word == null:
		_word = RegEx.create_from_string("[\\p{L}\\p{N}#+\\-]+")
	var t := text.to_lower()
	var words := {}
	for m in _word.search_all(t):
		words[m.get_string()] = true
	var best := ""
	var score := 0
	for k: String in TOPIC_WORDS:
		var n := 0
		for w: String in TOPIC_WORDS[k]:
			# Short words and ones with spaces: whole words or phrases only.
			if w.length() <= 4 or w.contains(" "):
				if words.has(w) or (w.contains(" ") and t.contains(w)):
					n += 2
			elif t.contains(w):
				n += 2
		if n > score:
			score = n
			best = k
	return best


## Said hello.
static func greeting(text: String) -> bool:
	var t := " " + text.to_lower().strip_edges() + " "
	for w in [" hi ", " hi!", " hey ", " hey!", " hello", " olá", " ola ", " ola!", " yo ", "good morning", "good evening", "good afternoon", "bom dia", "boa tarde", "boa noite"]:
		if t.begins_with(w):
			return true
	return false


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
	for w in ["haha", " lol", "lmao", "kkk", "😂", "🤣", "rsrs", "ahah"]:
		if t.contains(w):
			return "laughing"
	for w in ["love you", "<3", "❤", "amo-te", "adoro-te", "😍", "🥰"]:
		if t.contains(w):
			return "loving"
	for w in ["thank", "thx", "obrigad", " love ", "awesome", "amazing", " great", "perfect", " nice", " cool", ":)", ":d", "brilliant", "well done", "good job", "fixe", "brutal"]:
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
