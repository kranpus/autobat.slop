class_name Passwords
extends RefCounted
## Password hashing for server accounts.
##
## Passwords are never stored, logged or encrypted reversibly. The server keeps
## only a random per-account salt and PBKDF2-HMAC-SHA256(password, salt), with
## many iterations so that guessing passwords from a stolen file is slow.
## Login tokens ("remember me") are random and also stored only as SHA-256.

const ITERATIONS := 600000   # OWASP 2023 guidance for PBKDF2-HMAC-SHA256
const SALT_BYTES := 16
const MIN_LENGTH := 6
const MAX_LENGTH := 128


## PBKDF2-HMAC-SHA256 with a single 32-byte output block (RFC 8018).
static func pbkdf2_sha256(password: String, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var crypto := Crypto.new()
	var key := password.to_utf8_buffer()
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := crypto.hmac_digest(HashingContext.HASH_SHA256, key, block)
	# XOR every round into four 64-bit lanes (fast in GDScript).
	var t0 := u.decode_u64(0)
	var t1 := u.decode_u64(8)
	var t2 := u.decode_u64(16)
	var t3 := u.decode_u64(24)
	for i in range(1, iterations):
		u = crypto.hmac_digest(HashingContext.HASH_SHA256, key, u)
		t0 ^= u.decode_u64(0)
		t1 ^= u.decode_u64(8)
		t2 ^= u.decode_u64(16)
		t3 ^= u.decode_u64(24)
	var out := PackedByteArray()
	out.resize(32)
	out.encode_u64(0, t0)
	out.encode_u64(8, t1)
	out.encode_u64(16, t2)
	out.encode_u64(24, t3)
	return out


## A new password record: {"salt", "hash", "iterations"} (hex strings).
static func make_record(password: String, iterations: int = ITERATIONS) -> Dictionary:
	var salt := Crypto.new().generate_random_bytes(SALT_BYTES)
	return {"salt": salt.hex_encode(), "hash": pbkdf2_sha256(password, salt, iterations).hex_encode(), "iterations": iterations}


static func verify(password: String, record: Dictionary) -> bool:
	var salt: PackedByteArray = str(record.get("salt", "")).hex_decode()
	var expected: PackedByteArray = str(record.get("hash", "")).hex_decode()
	if salt.is_empty() or expected.size() != 32:
		return false
	var actual := pbkdf2_sha256(password, salt, int(record.get("iterations", ITERATIONS)))
	return constant_time_equal(actual, expected)


## Compare without leaking where the first difference is.
static func constant_time_equal(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0


static func random_token() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()


static func sha256_hex(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


## "" when acceptable, otherwise the reason.
static func check_new_password(password: String) -> String:
	if password.length() < MIN_LENGTH:
		return "Passwords need at least %d characters." % MIN_LENGTH
	if password.length() > MAX_LENGTH:
		return "That password is too long."
	return ""
