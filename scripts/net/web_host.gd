extends RefCounted
## A minimal static HTTP server for the exported browser build, so the game
## server can host the web version itself: players on the network open
## http://<server-ip>:24705 and play. GET/HEAD only, files from one folder,
## non-blocking (polled every frame by Party on the dedicated server).
##
## For the public internet put the web build on an HTTPS host instead
## (itch.io, GitHub Pages...) and give the server a real certificate for
## wss:// - see HOSTING.md.

const MAX_CONNECTIONS := 64
const IDLE_TIMEOUT_MS := 20000
const CHUNK := 65536
const MAX_SEND_PER_POLL := 4 << 20   # bytes per connection per frame
const MIME := {
	"html": "text/html; charset=utf-8", "js": "application/javascript", "wasm": "application/wasm",
	"pck": "application/octet-stream", "png": "image/png", "ico": "image/x-icon", "svg": "image/svg+xml",
	"json": "application/json", "css": "text/css", "txt": "text/plain; charset=utf-8",
}

var _server := TCPServer.new()
var _dir := ""
var _conns: Array = []   # {peer, request, out, file, last}


func start(port: int, dir: String) -> Error:
	_dir = dir
	return _server.listen(port)


func poll() -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if _conns.size() >= MAX_CONNECTIONS:
			peer.disconnect_from_host()
			continue
		_conns.append({"peer": peer, "request": PackedByteArray(), "out": PackedByteArray(), "file": null, "last": Time.get_ticks_msec(), "answered": false})
	var still: Array = []
	for c in _conns:
		if _service(c):
			still.append(c)
		else:
			(c["peer"] as StreamPeerTCP).disconnect_from_host()
	_conns = still


## Returns false when the connection is finished.
func _service(c: Dictionary) -> bool:
	var peer: StreamPeerTCP = c["peer"]
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var now := Time.get_ticks_msec()
	if now - int(c["last"]) > IDLE_TIMEOUT_MS:
		return false
	if not c["answered"]:
		var n := peer.get_available_bytes()
		if n > 0:
			var got: Array = peer.get_partial_data(mini(n, 8192))
			var buf: PackedByteArray = c["request"]
			buf.append_array(got[1])
			c["request"] = buf   # packed arrays are values: store it back
			c["last"] = now
		var req: PackedByteArray = c["request"]
		if req.size() > 16384:
			return false
		var text := req.get_string_from_ascii()
		if not text.contains("\r\n\r\n"):
			return true
		c["answered"] = true
		_answer(c, text.get_slice("\r\n", 0))
	# Send what's pending, refilling from the file as the socket accepts it.
	var sent := 0
	while sent < MAX_SEND_PER_POLL:
		var out: PackedByteArray = c["out"]
		if out.is_empty():
			var f: FileAccess = c["file"]
			if f == null or f.eof_reached() or f.get_position() >= f.get_length():
				return false   # all sent (Connection: close)
			c["out"] = f.get_buffer(CHUNK)
			continue
		var res: Array = peer.put_partial_data(out)
		var wrote: int = res[1]
		if res[0] != OK:
			return false
		sent += wrote
		if wrote > 0:
			c["last"] = now
		if wrote < out.size():
			c["out"] = out.slice(wrote)
			break   # socket buffer full; continue next frame
		c["out"] = PackedByteArray()
	return true


func _answer(c: Dictionary, request_line: String) -> void:
	var parts := request_line.split(" ")
	if parts.size() < 2 or parts[0] not in ["GET", "HEAD"]:
		_respond(c, "405 Method Not Allowed", "text/plain", "Only GET is supported.".to_utf8_buffer())
		return
	var path := parts[1].get_slice("?", 0).uri_decode()
	if path == "/" or path == "":
		path = "/index.html"
	# Only plain files inside the web folder.
	if path.contains("..") or path.contains("\\") or path.contains(":"):
		_respond(c, "403 Forbidden", "text/plain", "Forbidden".to_utf8_buffer())
		return
	var full := _dir.path_join(path.trim_prefix("/"))
	var f := FileAccess.open(full, FileAccess.READ)
	if f == null or DirAccess.dir_exists_absolute(full):
		_respond(c, "404 Not Found", "text/plain", "Not found".to_utf8_buffer())
		return
	var ext := full.get_extension().to_lower()
	var header := "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n" % [MIME.get(ext, "application/octet-stream"), f.get_length()]
	c["out"] = header.to_utf8_buffer()
	if parts[0] == "GET":
		c["file"] = f


func _respond(c: Dictionary, status: String, mime: String, body: PackedByteArray) -> void:
	var out := ("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, mime, body.size()]).to_utf8_buffer()
	out.append_array(body)
	c["out"] = out
