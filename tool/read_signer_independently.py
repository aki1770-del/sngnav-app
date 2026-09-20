#!/usr/bin/env python3
"""AAE independent signer reader. Two paths, neither of them apksigner.

PATH A  structure walk: EOCD -> central directory offset -> APK Signing Block
        -> id-value pairs -> v2 (0x7109871a) / v3 (0xf05368c0) -> signers
        -> signed data -> certificates -> first DER cert -> sha256.
PATH B  no structure walk at all: scan the tail for DER SEQUENCE headers and
        keep whatever x509 parses as a certificate.
"""
import sys, struct, hashlib
from cryptography import x509
from cryptography.hazmat.primitives import serialization

MAGIC = b"APK Sig Block 42"
V2, V3 = 0x7109871a, 0xf05368c0

def find_signing_block(buf):
    # EOCD: signature 0x06054b50, central-dir offset at +16
    end = max(0, len(buf) - 65536 - 22)
    pos = buf.rfind(b"PK\x05\x06", end)
    if pos < 0: raise ValueError("no EOCD")
    cd_off = struct.unpack_from("<I", buf, pos + 16)[0]
    if buf[cd_off-16:cd_off] != MAGIC: raise ValueError("no APK Sig Block magic")
    size_at_end = struct.unpack_from("<Q", buf, cd_off - 24)[0]
    start = cd_off - 8 - size_at_end
    size_at_start = struct.unpack_from("<Q", buf, start)[0]
    if size_at_start != size_at_end: raise ValueError("signing block size mismatch")
    return buf[start + 8 : cd_off - 24]        # the id-value pairs only

def pairs(block):
    off = 0
    while off + 12 <= len(block):
        ln = struct.unpack_from("<Q", block, off)[0]
        if ln < 4 or off + 8 + ln > len(block): break
        yield struct.unpack_from("<I", block, off + 8)[0], block[off+12 : off+8+ln]
        off += 8 + ln

def lv_seq(buf):
    """uint32-length-prefixed elements inside buf."""
    off = 0
    while off + 4 <= len(buf):
        n = struct.unpack_from("<I", buf, off)[0]
        if off + 4 + n > len(buf): break
        yield buf[off+4 : off+4+n]
        off += 4 + n

def certs_from_scheme(value):
    """value = uint32 len(signers) then signers; signer = signed_data | sigs | pubkey.
       signed_data = digests | certificates | ..., both length-prefixed."""
    out = []
    if len(value) < 4: return out
    signers_blob = value[4:4+struct.unpack_from("<I", value, 0)[0]]
    for signer in lv_seq(signers_blob):
        if len(signer) < 4: continue
        sd_len = struct.unpack_from("<I", signer, 0)[0]
        signed_data = signer[4:4+sd_len]
        if len(signed_data) < 4: continue
        d_len = struct.unpack_from("<I", signed_data, 0)[0]   # digests
        rest = signed_data[4+d_len:]
        if len(rest) < 4: continue
        c_len = struct.unpack_from("<I", rest, 0)[0]          # certificates
        for der in lv_seq(rest[4:4+c_len]):
            out.append(der)
    return out

def path_a(buf):
    blk = find_signing_block(buf)
    found = {}
    for pid, value in pairs(blk):
        if pid in (V2, V3):
            cs = certs_from_scheme(value)
            if cs: found[pid] = cs
    return found

def path_b(buf):
    """No structure knowledge. Scan the last 512 KiB for DER SEQUENCEs that parse."""
    tail = buf[-524288:] if len(buf) > 524288 else buf
    seen, out = set(), []
    i = 0
    while True:
        i = tail.find(b"\x30\x82", i)
        if i < 0: break
        ln = struct.unpack_from(">H", tail, i + 2)[0] + 4
        cand = tail[i:i+ln]
        if len(cand) == ln:
            try:
                c = x509.load_der_x509_certificate(cand)
                d = hashlib.sha256(c.public_bytes(serialization.Encoding.DER)).hexdigest()
                if d not in seen: seen.add(d); out.append(d)
            except Exception: pass
        i += 1
    return out

for p in sys.argv[1:]:
    buf = open(p, "rb").read()
    try:
        a = path_a(buf)
        a_digests = [hashlib.sha256(d).hexdigest() for d in (a.get(V2) or a.get(V3) or [])]
    except Exception as e:
        a_digests = ["ERROR:%s" % e]
    b_digests = path_b(buf)
    print("%s\t%s\t%s" % (a_digests[0] if a_digests else "NONE",
                          b_digests[0] if b_digests else "NONE", p))
