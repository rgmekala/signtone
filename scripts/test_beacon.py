"""
Test the Signtone ultrasonic beacon encode → decode round trip.
"""
import sys
import os
sys.path.insert(0, "backend")

import numpy as np
from app.services.beacon_service import (
    encode_payload,
    decode_signal,
    save_beacon_wav,
    SAMPLE_RATE,
)

print("=" * 55)
print("Signtone - Ultrasonic Beacon Test")
print("=" * 55)

results = []

def run(label: str, signal: np.ndarray, expected: str):
    decoded = decode_signal(signal, SAMPLE_RATE)
    ok = decoded == expected
    status = "✅ Pass" if ok else "❌ Fail"
    results.append(ok)
    print(f"  {status}  {label}")
    if not ok:
        print(f"         expected='{expected}'  got='{decoded}'")
    return decoded


# ── Test 1: basic round trip ──────────────────────────────────────────────────
print("\n[1] Basic encode → decode")
payloads = ["EVT001", "CONF2026", "SW-XYZ", "A1B2C3"]
for p in payloads:
    sig = encode_payload(p)
    run(f"payload='{p}'", sig, p)


# ── Test 2: decode survives light background noise ────────────────────────────
print("\n[2] Noise tolerance (simulates PA system + room echo)")
np.random.seed(42)
test_payload = "SIGNTONE"
clean = encode_payload(test_payload)

for noise_level, label in [(0.05, "5% noise"), (0.10, "10% noise"), (0.20, "20% noise")]:
    noise = np.random.normal(0, noise_level, clean.shape).astype(np.float32)
    noisy = np.clip(clean + noise, -1.0, 1.0)
    run(f"{label}", noisy, test_payload)


# ── Test 3: decode survives volume scaling ────────────────────────────────────
print("\n[3] Volume tolerance (simulates distance from speaker)")
clean = encode_payload("RADIOEVENT")
for scale, label in [(0.8, "80% volume"), (0.5, "50% volume"), (0.3, "30% volume")]:
    scaled = (clean * scale).astype(np.float32)
    run(f"{label}", scaled, "RADIOEVENT")


# ── Test 4: no false positive on silence ─────────────────────────────────────
print("\n[4] No false positive on silence / random audio")
silence = np.zeros(SAMPLE_RATE * 3, dtype=np.float32)
decoded_silence = decode_signal(silence, SAMPLE_RATE)
ok = decoded_silence is None
results.append(ok)
print(f"  {'✅ Pass' if ok else '❌ Fail'}  silence returns None")

np.random.seed(7)
random_audio = np.random.uniform(-1, 1, SAMPLE_RATE * 3).astype(np.float32)
decoded_random = decode_signal(random_audio, SAMPLE_RATE)
ok = decoded_random is None
results.append(ok)
print(f"  {'✅ Pass' if ok else '❌ Fail'}  random audio returns None")


# ── Test 5: save a real .wav file ─────────────────────────────────────────────
print("\n[5] Save beacon .wav file")
wav_path = "/tmp/signtone_test_beacon.wav"
save_beacon_wav("DEMO2026", wav_path)
ok = os.path.exists(wav_path) and os.path.getsize(wav_path) > 1000
results.append(ok)
print(f"  {'✅ Pass' if ok else '❌ Fail'}  saved to {wav_path} "
      f"({os.path.getsize(wav_path):,} bytes)")


# ── Summary ───────────────────────────────────────────────────────────────────
passed = sum(results)
total  = len(results)
print("\n" + "=" * 55)
if passed == total:
    print(f"✅ All {total} tests passed - beacon service ready!")
else:
    print(f"⚠️  {passed}/{total} tests passed")
print("=" * 55)
