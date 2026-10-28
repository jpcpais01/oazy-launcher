### Claude uses your Claude plan, not a stray API key
- The orb's Claude chat and the Oazy Claude app could say your credit balance was too low even though your Claude subscription was fine. That happened when an `ANTHROPIC_API_KEY` sat in your environment: Claude Code's headless mode bills that key, while the claude you run in a terminal ignores it unless you said yes to it.
- Oazy now does what the terminal does: it uses your signed-in Claude plan (and its extra usage), and only uses the API key if you approved it in Claude Code or it's your only sign-in.
