class_name HlExchange
extends RefCounted
## Where placing and cancelling orders on Hyperliquid will live. For now the
## trading page is view-only, so every call here says no and nothing is sent.
##
## The plan for trading, so it lands safely:
## - Orders are signed by an *agent* (API) wallet that you approve on
##   Hyperliquid's site. An agent can trade but can never withdraw, and you
##   can revoke it there at any time. Oazy never sees your main wallet's key.
## - The agent's key is kept by Windows (DPAPI, through the companion), never in
##   settings.cfg, logs or the cache, and is only unwrapped to sign.
## - Every order shows a confirm step with size, price, fees and liquidation
##   price before it's signed; there's no one-click trading by default.
## - Signing is EIP-712 over the order action, posted to EXCHANGE.
##
## Until then the page reads everything through Hyperliquid (the info API and
## WebSocket), which needs nothing but your public address.

const EXCHANGE := "https://api.hyperliquid.xyz/exchange"
const VIEW_ONLY := "Trading isn't on yet: this page is view-only for now."


## Whether this build can place orders at all.
static func can_trade() -> bool:
	return false


## A limit or market order. `order` is {coin, buy (bool), size, price (NAN for
## market), reduce_only, tif ("Gtc", "Ioc", "Alo")}. Answers {ok, error, oid}.
static func place(_order: Dictionary) -> Dictionary:
	return {"ok": false, "error": VIEW_ONLY}


static func cancel(_coin: String, _oid: int) -> Dictionary:
	return {"ok": false, "error": VIEW_ONLY}
