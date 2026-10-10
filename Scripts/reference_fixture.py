#!/usr/bin/env python3
"""TEST ONLY: independent primitives; deterministic inputs are public synthetic fixtures.
Never use this script to create a real vault. Production uses the Swift engine's CSPRNG.
Requires the pinned packages in reference-requirements.txt, outside the app dependency graph.
"""
import argparse
import json
import struct
from pathlib import Path
from argon2.low_level import hash_secret_raw, Type
from Crypto.Cipher import ChaCha20_Poly1305

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'Packages/CryptaCore/Tests/CryptaCoreTests/Fixtures'
PASSPHRASE = 'public fixture passphrase 🗝️ with spaces'.encode('utf-8')
WRAP_LABEL = b'Crypta/v1/key-wrap\0'
PAYLOAD_LABEL = b'Crypta/v1/payload\0'


def derive(password, salt, passes, memory):
    return hash_secret_raw(password, salt, time_cost=passes, memory_cost=memory,
                           parallelism=1, hash_len=32, type=Type.ID, version=19)


def seal(message, key, nonce, aad):
    cipher = ChaCha20_Poly1305.new(key=key, nonce=nonce)
    cipher.update(aad)
    ciphertext, tag = cipher.encrypt_and_digest(message)
    return ciphertext + tag


def open_sealed(ciphertext, key, nonce, aad):
    cipher = ChaCha20_Poly1305.new(key=key, nonce=nonce)
    cipher.update(aad)
    return cipher.decrypt_and_verify(ciphertext[:-16], ciphertext[-16:])


def generate():
    vault_id = bytes(range(16))
    salt = bytes(range(16, 32))
    wrap_nonce = bytes(range(32, 56))
    payload_nonce = bytes(range(56, 80))
    vault_key = bytes(range(80, 112))
    core = struct.pack('<8sHHI16sHH12s', b'CRYPTA\r\n', 1, 48, 0, vault_id, 1, 1, bytes(12))
    slot = struct.pack('<HHIII16s24s8s', 1, 1, 3, 65536, 1, salt, wrap_nonce, bytes(8))
    payload = json.dumps({'schemaVersion': 1, 'vaultID': vault_id.hex(), 'name': 'Public interoperability fixture',
                          'createdAt': 0, 'modifiedAt': 0, 'revision': 0, 'categories': [], 'entries': []},
                         sort_keys=True, separators=(',', ':')).encode()
    descriptor = payload_nonce + struct.pack('<Q', len(payload) + 16)
    kek = derive(PASSPHRASE, salt, 3, 65536)
    output = core + slot + seal(vault_key, kek, wrap_nonce, WRAP_LABEL + core + slot)
    output += descriptor + seal(payload, vault_key, payload_nonce, PAYLOAD_LABEL + core + descriptor)
    (FIXTURES / 'reference-v1.crypta').write_bytes(output)
    (FIXTURES / 'reference-payload.json').write_bytes(payload)
    print('Generated public independent fixture.')


def verify(path):
    data = path.read_bytes()
    assert data[:8] == b'CRYPTA\r\n' and len(data) == 192 + struct.unpack_from('<Q', data, 184)[0]
    passes, memory, lanes = struct.unpack_from('<III', data, 52)
    assert 3 <= passes <= 6 and 65536 <= memory <= 524288 and lanes == 1
    kek = derive(PASSPHRASE, data[64:80], passes, memory)
    key = open_sealed(data[112:160], kek, data[80:104], WRAP_LABEL + data[:112])
    payload = open_sealed(data[192:], key, data[160:184], PAYLOAD_LABEL + data[:48] + data[160:192])
    assert isinstance(json.loads(payload), dict)
    print('Independent Argon2id/XChaCha verification passed; no plaintext printed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generate', action='store_true')
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    if args.generate:
        generate()
    if args.verify:
        verify(args.verify)
