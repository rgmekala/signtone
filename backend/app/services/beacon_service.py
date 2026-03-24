"""
Signtone - Ultrasonic Beacon Service
=====================================
Robust BFSK encoder/decoder for real-world environments.
Designed to work in loud venues, crowds, and poor acoustic conditions.
"""

import logging
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

logger = logging.getLogger(__name__)

# ── Frequency plan ────────────────────────────────────────────────────────────
SAMPLE_RATE  = 44100
FREQ_SYNC    = 15000   # Hz - sync/preamble tone
FREQ_ZERO    = 16000   # Hz - bit 0
FREQ_ONE     = 17000   # Hz - bit 1
SYMBOL_DUR   = 0.08    # seconds per bit symbol
GUARD_DUR    = 0.02    # seconds silence between symbols
SYNC_DUR     = 0.20    # seconds sync tone
AMPLITUDE    = 0.6

# ── Detection config ──────────────────────────────────────────────────────────
MAX_PAYLOAD_BYTES = 32
# SNR threshold: beacon tone must be this many times stronger than noise floor
SNR_THRESHOLD     = 2.5   # lowered for real-world use
# Frequency tolerance in Hz for tone classification
FREQ_TOLERANCE    = 400


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _tone(freq: float, duration: float, sr: int = SAMPLE_RATE) -> np.ndarray:
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    return (AMPLITUDE * np.sin(2 * np.pi * freq * t)).astype(np.float32)

def _silence(duration: float, sr: int = SAMPLE_RATE) -> np.ndarray:
    return np.zeros(int(sr * duration), dtype=np.float32)

def _checksum(payload: str) -> int:
    return sum(payload.encode("ascii")) % 256

def _bandpass(signal: np.ndarray, sr: int, low: float, high: float) -> np.ndarray:
    """Bandpass filter to isolate beacon frequencies before decoding."""
    sos = butter(4, [low / (sr / 2), high / (sr / 2)], btype='band', output='sos')
    return sosfilt(sos, signal).astype(np.float32)

def _goertzel_power(segment: np.ndarray, target_freq: float, sr: int) -> float:
    """
    Goertzel algorithm - efficient single-frequency power detector.
    More robust than FFT for detecting a known frequency in noise.
    Returns normalised power (0.0 - 1.0).
    """
    n = len(segment)
    if n == 0:
        return 0.0
    k     = round(n * target_freq / sr)
    omega = 2.0 * np.pi * k / n
    coeff = 2.0 * np.cos(omega)
    s0, s1, s2 = 0.0, 0.0, 0.0
    for x in segment:
        s0 = x + coeff * s1 - s2
        s2 = s1
        s1 = s0
    power = (s1 * s1 + s2 * s2 - coeff * s1 * s2) / (n * n)
    return float(power)

def _classify_tone(segment: np.ndarray, sr: int) -> tuple[str, float]:
    """
    Classify a segment as 'sync', 'one', 'zero', or 'silence'.
    Uses Goertzel for each target frequency.
    Returns (label, snr).
    """
    p_sync = _goertzel_power(segment, FREQ_SYNC, sr)
    p_zero = _goertzel_power(segment, FREQ_ZERO, sr)
    p_one  = _goertzel_power(segment, FREQ_ONE,  sr)

    # Noise floor estimate: median of the three powers
    noise  = np.median([p_sync, p_zero, p_one]) + 1e-12
    powers = {'sync': p_sync, 'zero': p_zero, 'one': p_one}
    best   = max(powers, key=powers.get)
    snr    = powers[best] / noise

    if snr < SNR_THRESHOLD:
        return 'silence', snr
    return best, snr


# ─────────────────────────────────────────────────────────────────────────────
# Encoder
# ─────────────────────────────────────────────────────────────────────────────

def encode_payload(payload: str) -> np.ndarray:
    if len(payload) > MAX_PAYLOAD_BYTES:
        raise ValueError(f"Payload too long: {len(payload)} chars (max {MAX_PAYLOAD_BYTES})")
    if not payload.isascii():
        raise ValueError("Payload must be ASCII characters only")

    logger.info(f"Encoding payload: '{payload}' ({len(payload)} chars)")
    segments = []

    segments.append(_tone(FREQ_SYNC, SYNC_DUR))
    segments.append(_silence(GUARD_DUR))

    for char in payload:
        byte = ord(char)
        for bit_pos in range(7, -1, -1):
            bit  = (byte >> bit_pos) & 1
            freq = FREQ_ONE if bit else FREQ_ZERO
            segments.append(_tone(freq, SYMBOL_DUR))
            segments.append(_silence(GUARD_DUR))

    chk = _checksum(payload)
    for bit_pos in range(7, -1, -1):
        bit  = (chk >> bit_pos) & 1
        freq = FREQ_ONE if bit else FREQ_ZERO
        segments.append(_tone(freq, SYMBOL_DUR))
        segments.append(_silence(GUARD_DUR))

    segments.append(_tone(FREQ_SYNC, SYNC_DUR * 0.5))

    signal   = np.concatenate(segments)
    duration = len(signal) / SAMPLE_RATE
    logger.info(f"Encoded signal: {duration:.2f}s, {len(signal)} samples")
    return signal

def save_beacon_wav(payload: str, output_path: str) -> str:
    signal = encode_payload(payload)
    pcm    = (signal * 32767).astype(np.int16)
    wavfile.write(output_path, SAMPLE_RATE, pcm)
    logger.info(f"Saved beacon to: {output_path}")
    return output_path


# ─────────────────────────────────────────────────────────────────────────────
# Robust Decoder
# ─────────────────────────────────────────────────────────────────────────────

def decode_signal(signal: np.ndarray, sr: int = SAMPLE_RATE) -> str | None:
    """
    Robust BFSK decoder using sliding-window Goertzel detection.

    Strategy:
    1. Bandpass filter to suppress noise outside beacon band
    2. Slide a symbol-sized window across the signal
    3. Score each position using Goertzel SNR for all three tones
    4. Find sync tone onset, then walk forward collecting bits
    5. Attempt decode at every valid sync position found
    6. Return first payload that passes checksum
    """
    symbol_samples = int(sr * SYMBOL_DUR)
    guard_samples  = int(sr * GUARD_DUR)
    step_samples   = symbol_samples + guard_samples
    sync_samples   = int(sr * SYNC_DUR)

    # ── 1. Bandpass filter: keep only 13500-17500 Hz ──────────────────────────
    try:
        filtered = _bandpass(signal, sr, 13500, 17500)
    except Exception:
        filtered = signal  # fallback if filter fails

    n = len(filtered)

    # ── 2. Sliding scan: score every position ─────────────────────────────────
    # Step by guard_samples for fine resolution
    scan_step = max(guard_samples // 2, 1)

    # Collect all sync tone positions
    sync_positions = []
    i = 0
    while i + sync_samples <= n:
        seg   = filtered[i: i + sync_samples]
        label, snr = _classify_tone(seg, sr)
        if label == 'sync' and snr >= SNR_THRESHOLD:
            sync_positions.append((i, snr))
            i += sync_samples  # skip ahead past this sync
        else:
            i += scan_step

    if not sync_positions:
        logger.debug("No sync tone found")
        return None

    logger.info(f"Found {len(sync_positions)} sync position(s): {[(p, f'{s:.1f}') for p,s in sync_positions[:3]]}")

    # ── 3. Try decoding from each sync position ────────────────────────────────
    for sync_pos, sync_snr in sync_positions:
        result = _try_decode_from(filtered, sr, sync_pos, symbol_samples, guard_samples, step_samples)
        if result is not None:
            logger.info(f"Decoded payload: '{result}' ✅ (sync_snr={sync_snr:.1f})")
            return result

    logger.debug("All sync positions tried, no valid payload found")
    return None


def _try_decode_from(
    signal: np.ndarray,
    sr: int,
    sync_pos: int,
    symbol_samples: int,
    guard_samples: int,
    step_samples: int,
) -> str | None:
    sync_samples = int(sr * SYNC_DUR)
    start        = sync_pos + sync_samples + guard_samples

    offsets = [0, guard_samples // 2, -guard_samples // 2,
               guard_samples, -guard_samples]

    for offset in offsets:
        bits = _collect_bits(signal, sr, start + offset, symbol_samples, step_samples)
        n    = len(bits) if bits else 0
        logger.info(f"  sync_pos={sync_pos} offset={offset} bits={n} preview={bits[:8] if bits else []}")

        if bits is None or len(bits) < 16:
            continue

        result = _bits_to_payload(bits)
        if result is not None:
            return result
        else:
            logger.info(f"  bits_to_payload failed for {n} bits: {bits[:16]}")

    return None

def _collect_bits(
    signal: np.ndarray,
    sr: int,
    start: int,
    symbol_samples: int,
    step_samples: int,
    max_bits: int = (MAX_PAYLOAD_BYTES + 1) * 8 + 16,
) -> list[int] | None:
    """
    Walk forward from start collecting bits until silence or end sync.
    Returns list of bits, or None if fewer than 8 bits found.
    """
    bits = []
    pos  = start
    n    = len(signal)

    while pos + symbol_samples <= n and len(bits) < max_bits:
        seg   = signal[pos: pos + symbol_samples]
        label, snr = _classify_tone(seg, sr)

        if label == 'silence':
            # Allow up to 2 consecutive silences (timing jitter)
            if len(bits) > 0:
                break
        elif label == 'sync':
            break  # end marker
        elif label in ('zero', 'one'):
            bits.append(0 if label == 'zero' else 1)

        pos += step_samples

    return bits if len(bits) >= 8 else None


def _bits_to_payload(bits: list[int]) -> str | None:
    """
    Convert bit list to string, verify checksum.
    Tries all valid byte-aligned lengths.
    """
    # Try every valid payload length (1 to MAX_PAYLOAD_BYTES chars + checksum)
    for n_chars in range(1, MAX_PAYLOAD_BYTES + 1):
        n_bits = (n_chars + 1) * 8  # payload bits + checksum byte
        if len(bits) < n_bits:
            break

        data_bits     = bits[:n_chars * 8]
        checksum_bits = bits[n_chars * 8: n_bits]

        # Decode chars
        chars = []
        valid = True
        for i in range(0, len(data_bits), 8):
            byte = 0
            for b in data_bits[i: i + 8]:
                byte = (byte << 1) | b
            if 32 <= byte <= 126:
                chars.append(chr(byte))
            else:
                valid = False
                break

        if not valid:
            continue

        decoded = "".join(chars)

        # Verify checksum
        rx_chk = 0
        for b in checksum_bits:
            rx_chk = (rx_chk << 1) | b

        if rx_chk == _checksum(decoded):
            return decoded

    return None


def decode_from_bytes(audio_bytes: bytes, sr: int = SAMPLE_RATE) -> str | None:
    samples = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32)
    signal  = samples / 32768.0
    return decode_signal(signal, sr)
