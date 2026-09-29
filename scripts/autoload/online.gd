extends Node
## Autoload "Online": talks to the Supabase project (accounts and the server
## functions). Only OnlineBackend and the online menu use it.
##
## Project settings live in data/online.json: {"url": "...", "anon_key": "..."}.
## The anon key is public by design; never put the service_role key here.

const CONFIG_PATH := "res://data/online.json"
const SESSION_PATH := "user://online_session.cfg"
const TIMEOUT_SECONDS := 15.0

var url := ""
var anon_key := ""
var access_token := ""
var refresh_token := ""
var _expires_at := 0


func _ready() -> void:
	var cfg: Variant = JsonUtil.read_file(CONFIG_PATH)
	if typeof(cfg) == TYPE_DICTIONARY:
		url = str(cfg.get("url", "")).trim_suffix("/")
		anon_key = str(cfg.get("anon_key", ""))
	var session := ConfigFile.new()
	if session.load(SESSION_PATH) == OK:
		refresh_token = session.get_value("auth", "refresh_token", "")


## True once the project URL and key are filled in.
func is_configured() -> bool:
	return url != "" and anon_key != ""


func has_saved_session() -> bool:
	return refresh_token != ""


# --- Accounts -----------------------------------------------------------------------

## Returns "" on success, or a message to show. When email confirmation is on,
## sign-up succeeds without a session and the player must confirm first.
func sign_up(email: String, password: String) -> String:
	var r := await _request("/auth/v1/signup", {"email": email, "password": password}, false)
	if r["code"] >= 400:
		return _auth_error(r)
	if r["body"].has("access_token"):
		_store_session(r["body"])
		return ""
	return "confirm_email"


func sign_in(email: String, password: String) -> String:
	var r := await _request("/auth/v1/token?grant_type=password", {"email": email, "password": password}, false)
	if r["code"] >= 400:
		return _auth_error(r)
	_store_session(r["body"])
	return ""


## Uses the saved refresh token. Returns "" on success.
func resume_session() -> String:
	if refresh_token == "":
		return "Not signed in."
	var r := await _request("/auth/v1/token?grant_type=refresh_token", {"refresh_token": refresh_token}, false)
	if r["code"] >= 400:
		sign_out()
		return "Please sign in again."
	_store_session(r["body"])
	return ""


func sign_out() -> void:
	access_token = ""
	refresh_token = ""
	_expires_at = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))


func delete_account() -> String:
	var r := await call_function("account", {"action": "delete"})
	if r["code"] >= 400:
		return str(r["body"].get("error", "Couldn't delete the account."))
	sign_out()
	return ""


func _store_session(body: Dictionary) -> void:
	access_token = body.get("access_token", "")
	refresh_token = body.get("refresh_token", "")
	_expires_at = int(Time.get_unix_time_from_system()) + int(body.get("expires_in", 3600))
	var session := ConfigFile.new()
	session.set_value("auth", "refresh_token", refresh_token)
	session.save(SESSION_PATH)


func _auth_error(r: Dictionary) -> String:
	var b: Dictionary = r["body"]
	var msg := str(b.get("msg", b.get("error_description", b.get("message", b.get("error", "")))))
	return msg if msg != "" else "Couldn't reach the server (HTTP %d)." % r["code"]


# --- Server functions ------------------------------------------------------------------

## Calls a server function as the signed-in player: {"code": int, "body": Dictionary}.
func call_function(name: String, payload: Dictionary) -> Dictionary:
	if int(Time.get_unix_time_from_system()) > _expires_at - 60 and refresh_token != "":
		await resume_session()
	return await _request("/functions/v1/" + name, payload, true)


func _request(path: String, payload: Dictionary, authed: bool) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "apikey: " + anon_key])
	if authed:
		headers.append("Authorization: Bearer " + access_token)
	var err := http.request(url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		http.queue_free()
		return {"code": 0, "body": {"error": "Couldn't reach the server."}}
	var res: Array = await http.request_completed
	http.queue_free()
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var body: Variant = JsonUtil.ints(JSON.parse_string(text)) if text != "" else {}
	if typeof(body) != TYPE_DICTIONARY:
		body = {"error": text}
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"code": 0, "body": {"error": "Couldn't reach the server."}}
	return {"code": code, "body": body}
