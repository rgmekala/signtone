"""
Signtone - Beacon Service
==========================
Robust BFSK encoder/decoder with:
  - FrequencyProfile: ultrasonic (15-17 kHz) or audible (4-6 kHz)
  - ChimeStyle: none | marimba | bell | modern
  - Same Goertzel decoder for both profiles
"""

import logging
import numpy as np
from enum import Enum
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

logger = logging.getLogger(__name__)

# ── Frequency profiles ────────────────────────────────────────────────────────

class FrequencyProfile(str, Enum):
    ULTRASONIC = "ultrasonic"   # 15-17 kHz - inaudible, short range (~30m)
    AUDIBLE    = "audible"      # 4-6 kHz   - audible, long range (~300m)

class ChimeStyle(str, Enum):
    NONE    = "none"     # raw BFSK only
    MARIMBA = "marimba"  # warm wooden C5→E5→G5
    BELL    = "bell"     # clear C6→G6 with decay tail
    MODERN  = "modern"   # two-tone synthetic ding

# ── Profile parameters ────────────────────────────────────────────────────────

PROFILES = {
    FrequencyProfile.ULTRASONIC: {
        "freq_sync":    15000,
        "freq_zero":    16000,
        "freq_one":     17000,
        "bandpass_low": 13500,
        "bandpass_high":17500,
        "whistle":      False,
        "label":        "Ultrasonic (15-17 kHz)",
    },
    FrequencyProfile.AUDIBLE: {
        # C major - C4/E4/G4 (262/330/392 Hz)
        # Pure whistle tone - soft, minimal, pleasant
        "freq_sync":    262,     # C4
        "freq_zero":    330,     # E4
        "freq_one":     392,     # G4
        "bandpass_low": 200,
        "bandpass_high":500,
        "whistle":      True,
        "label":        "Audible whistle - C major (262/330/392 Hz)",
    },
}

# ── Global config (shared) ────────────────────────────────────────────────────
SAMPLE_RATE       = 44100
SYMBOL_DUR        = 0.08    # seconds per bit symbol
GUARD_DUR         = 0.02    # seconds silence between symbols
SYNC_DUR          = 0.20    # seconds sync tone
AMPLITUDE         = 0.6
MAX_PAYLOAD_BYTES = 32
SNR_THRESHOLD     = 2.5
FREQ_TOLERANCE    = 400

# Legacy constants (kept for backwards compatibility with existing imports)
FREQ_SYNC = 15000
FREQ_ZERO = 16000
FREQ_ONE  = 17000


# ─────────────────────────────────────────────────────────────────────────────
# Signal primitives
# ─────────────────────────────────────────────────────────────────────────────

def _tone(freq: float, duration: float, sr: int = SAMPLE_RATE,
          amplitude: float = AMPLITUDE, whistle: bool = False) -> np.ndarray:
    n   = int(sr * duration)
    t   = np.linspace(0, duration, n, endpoint=False)
    if whistle:
        # Soft whistle - pure sine + tiny breath noise
        # This is the official Signtone audible sound (w0)
        rng   = np.random.default_rng(42)
        noise = rng.standard_normal(n) * 0.02
        sig   = (0.90 * np.sin(2 * np.pi * freq * t) + noise) * amplitude
        # 40% crossfade on each end - smooth, no clicks
        fade  = int(n * 0.40)
        sig[:fade]  *= np.linspace(0, 1, fade)
        sig[-fade:] *= np.linspace(1, 0, fade)
    else:
        # Ultrasonic - plain sine wave
        sig = np.sin(2 * np.pi * freq * t) * amplitude
        # Short envelope to avoid clicks
        env_n = int(sr * min(8, duration * 1000 * 0.15) / 1000)
        if env_n > 0:
            sig[:env_n]  *= np.linspace(0, 1, env_n)
            sig[-env_n:] *= np.linspace(1, 0, env_n)
    return sig.astype(np.float32)

def _silence(duration: float, sr: int = SAMPLE_RATE) -> np.ndarray:
    return np.zeros(int(sr * duration), dtype=np.float32)

def _checksum(payload: str) -> int:
    return sum(payload.encode("ascii")) % 256

def _bandpass(signal: np.ndarray, sr: int, low: float, high: float) -> np.ndarray:
    sos = butter(4, [low / (sr / 2), high / (sr / 2)], btype='band', output='sos')
    return sosfilt(sos, signal).astype(np.float32)

def _apply_envelope(signal: np.ndarray, sr: int,
                    attack_ms: float = 5, release_ms: float = 10) -> np.ndarray:
    """Smooth attack/release to avoid clicks."""
    atk = int(sr * attack_ms / 1000)
    rel = int(sr * release_ms / 1000)
    env = np.ones(len(signal), dtype=np.float32)
    env[:atk]  = np.linspace(0, 1, atk)
    env[-rel:] = np.linspace(1, 0, rel)
    return signal * env


# ─────────────────────────────────────────────────────────────────────────────
# Chime synthesizers
# ─────────────────────────────────────────────────────────────────────────────

def _chime_z2(sr: int = SAMPLE_RATE) -> np.ndarray:
    """
    Signtone signature sound - Zen Bowl (z2).
    Deep 256 Hz strike with inharmonic partials and long resonant decay.
    Sounds: calm, authoritative, intentional.
    """
    freq = 256.0   # C4 - deep, resonant
    dur  = 5.0
    n    = int(sr * dur)
    t    = np.linspace(0, dur, n)

    sig = (
        0.50 * np.sin(2 * np.pi * freq       * t) * np.exp(-t * 0.8) +
        0.25 * np.sin(2 * np.pi * freq * 2.8 * t) * np.exp(-t * 1.8) +
        0.15 * np.sin(2 * np.pi * freq * 5.1 * t) * np.exp(-t * 3.0) +
        0.10 * np.sin(2 * np.pi * freq * 7.3 * t) * np.exp(-t * 5.0)
    )
    sig = sig * AMPLITUDE
    mx  = np.max(np.abs(sig))
    if mx > 0:
        sig = sig / mx * AMPLITUDE

    # Very short attack (3ms) - bowl strike character
    # Long release (300ms) - natural resonance tail
    a = int(sr * 0.003)
    r = int(sr * 0.300)
    sig[:a]  *= np.linspace(0, 1, a)
    sig[-r:] *= np.linspace(1, 0, r)
    return sig.astype(np.float32)


# Keep old chime functions as aliases for backwards compatibility
def _chime_marimba(sr: int = SAMPLE_RATE) -> np.ndarray:
    return _chime_z2(sr)

def _chime_bell(sr: int = SAMPLE_RATE) -> np.ndarray:
    return _chime_z2(sr)

def _chime_modern(sr: int = SAMPLE_RATE) -> np.ndarray:
    return _chime_z2(sr)


def _get_chime(style: ChimeStyle, sr: int = SAMPLE_RATE) -> np.ndarray:
    """Return the Signtone signature zen bowl sound for any chime style."""
    if style == ChimeStyle.NONE:
        return np.array([], dtype=np.float32)
    return _chime_z2(sr)  # z2 is the official Signtone sound


# ─────────────────────────────────────────────────────────────────────────────
# Goertzel detector
# ─────────────────────────────────────────────────────────────────────────────

def _goertzel_power(segment: np.ndarray, target_freq: float, sr: int) -> float:
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

def _classify_tone(segment: np.ndarray, sr: int,
                   freq_sync: float, freq_zero: float, freq_one: float
                   ) -> tuple[str, float]:
    p_sync = _goertzel_power(segment, freq_sync, sr)
    p_zero = _goertzel_power(segment, freq_zero, sr)
    p_one  = _goertzel_power(segment, freq_one,  sr)

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

def encode_payload(
    payload: str,
    profile: FrequencyProfile = FrequencyProfile.ULTRASONIC,
    chime: ChimeStyle = ChimeStyle.NONE,
) -> np.ndarray:
    """
    Encode a payload string into BFSK audio.

    Args:
        payload: ASCII string to encode (max 32 chars)
        profile: FrequencyProfile.ULTRASONIC or AUDIBLE
        chime:   ChimeStyle for branded intro/outro

    Returns:
        numpy float32 array ready to write as WAV
    """
    if len(payload) > MAX_PAYLOAD_BYTES:
        raise ValueError(f"Payload too long: {len(payload)} (max {MAX_PAYLOAD_BYTES})")
    if not payload.isascii():
        raise ValueError("Payload must be ASCII only")

    p         = PROFILES[profile]
    freq_sync = p["freq_sync"]
    freq_zero = p["freq_zero"]
    freq_one  = p["freq_one"]
    whistle   = p.get("whistle", False)

    logger.info(f"Encoding '{payload}' | profile={profile} | chime={chime}")

    segments = []

    # ── Chime intro (zen bowl z2) ─────────────────────────────────────────────
    intro = _get_chime(chime)
    if len(intro) > 0:
        segments.append(intro)
        segments.append(_silence(0.05))

    # ── BFSK payload ──────────────────────────────────────────────────────────
    segments.append(_tone(freq_sync, SYNC_DUR, whistle=whistle))
    segments.append(_silence(GUARD_DUR))

    for char in payload:
        byte = ord(char)
        for bit_pos in range(7, -1, -1):
            bit  = (byte >> bit_pos) & 1
            freq = freq_one if bit else freq_zero
            segments.append(_tone(freq, SYMBOL_DUR, whistle=whistle))
            segments.append(_silence(GUARD_DUR))

    chk = _checksum(payload)
    for bit_pos in range(7, -1, -1):
        bit  = (chk >> bit_pos) & 1
        freq = freq_one if bit else freq_zero
        segments.append(_tone(freq, SYMBOL_DUR, whistle=whistle))
        segments.append(_silence(GUARD_DUR))

    segments.append(_tone(freq_sync, SYNC_DUR * 0.5, whistle=whistle))

    # No chime outro - one intro chime is enough.
    # The BFSK data ends cleanly on its own.

    signal   = np.concatenate(segments)
    duration = len(signal) / SAMPLE_RATE
    logger.info(f"Encoded: {duration:.2f}s | {len(signal)} samples")
    return signal


def save_beacon_wav(
    payload: str,
    output_path: str,
    profile: FrequencyProfile = FrequencyProfile.ULTRASONIC,
    chime: ChimeStyle = ChimeStyle.NONE,
) -> str:
    """Encode payload and save as WAV file."""
    signal = encode_payload(payload, profile=profile, chime=chime)
    pcm    = (signal * 32767).astype(np.int16)
    wavfile.write(output_path, SAMPLE_RATE, pcm)
    logger.info(f"Saved: {output_path}")
    return output_path


def save_chime_wav(style: ChimeStyle, output_path: str) -> str:
    """Save just the chime (no BFSK) for preview purposes."""
    chime = _get_chime(style)
    if len(chime) == 0:
        raise ValueError("ChimeStyle.NONE has no audio to preview")
    pcm = (chime * 32767).astype(np.int16)
    wavfile.write(output_path, SAMPLE_RATE, pcm)
    return output_path


# ─────────────────────────────────────────────────────────────────────────────
# Decoder - works for both profiles
# ─────────────────────────────────────────────────────────────────────────────

def decode_signal(
    signal: np.ndarray,
    sr: int = SAMPLE_RATE,
    profile: FrequencyProfile = FrequencyProfile.ULTRASONIC,
) -> str | None:
    """
    Decode BFSK signal. Auto-tries both profiles if profile not specified.
    """
    result = _decode_with_profile(signal, sr, profile)
    if result:
        return result

    # Auto-fallback: try the other profile
    other = (FrequencyProfile.AUDIBLE
             if profile == FrequencyProfile.ULTRASONIC
             else FrequencyProfile.ULTRASONIC)
    logger.debug(f"Trying fallback profile: {other}")
    return _decode_with_profile(signal, sr, other)


def _decode_with_profile(
    signal: np.ndarray,
    sr: int,
    profile: FrequencyProfile,
) -> str | None:
    p             = PROFILES[profile]
    freq_sync     = p["freq_sync"]
    freq_zero     = p["freq_zero"]
    freq_one      = p["freq_one"]
    bandpass_low  = p["bandpass_low"]
    bandpass_high = p["bandpass_high"]

    symbol_samples = int(sr * SYMBOL_DUR)
    guard_samples  = int(sr * GUARD_DUR)
    step_samples   = symbol_samples + guard_samples
    sync_samples   = int(sr * SYNC_DUR)

    # Bandpass filter
    try:
        filtered = _bandpass(signal, sr, bandpass_low, bandpass_high)
    except Exception:
        filtered = signal

    n         = len(filtered)
    scan_step = max(guard_samples // 2, 1)

    # Find sync positions
    sync_positions = []
    i = 0
    while i + sync_samples <= n:
        seg   = filtered[i: i + sync_samples]
        label, snr = _classify_tone(seg, sr, freq_sync, freq_zero, freq_one)
        if label == 'sync' and snr >= SNR_THRESHOLD:
            sync_positions.append((i, snr))
            i += sync_samples
        else:
            i += scan_step

    if not sync_positions:
        logger.debug(f"[{profile}] No sync tone found")
        return None

    logger.info(f"[{profile}] {len(sync_positions)} sync position(s) found")

    for sync_pos, sync_snr in sync_positions:
        result = _try_decode_from(
            filtered, sr, sync_pos,
            symbol_samples, guard_samples, step_samples,
            freq_sync, freq_zero, freq_one,
        )
        if result is not None:
            logger.info(f"[{profile}] Decoded: '{result}' ✅")
            return result

    return None


def _try_decode_from(
    signal, sr, sync_pos,
    symbol_samples, guard_samples, step_samples,
    freq_sync, freq_zero, freq_one,
) -> str | None:
    sync_samples = int(sr * SYNC_DUR)
    start        = sync_pos + sync_samples + guard_samples

    offsets = [0, guard_samples // 2, -guard_samples // 2,
               guard_samples, -guard_samples]

    for offset in offsets:
        bits = _collect_bits(
            signal, sr, start + offset,
            symbol_samples, step_samples,
            freq_sync, freq_zero, freq_one,
        )
        if bits is None or len(bits) < 16:
            continue
        result = _bits_to_payload(bits)
        if result is not None:
            return result
    return None


def _collect_bits(
    signal, sr, start,
    symbol_samples, step_samples,
    freq_sync, freq_zero, freq_one,
    max_bits: int = (MAX_PAYLOAD_BYTES + 1) * 8 + 16,
) -> list[int] | None:
    bits = []
    pos  = start
    n    = len(signal)

    while pos + symbol_samples <= n and len(bits) < max_bits:
        seg   = signal[pos: pos + symbol_samples]
        label, snr = _classify_tone(seg, sr, freq_sync, freq_zero, freq_one)

        if label == 'silence':
            if len(bits) > 0:
                break
        elif label == 'sync':
            break
        elif label in ('zero', 'one'):
            bits.append(0 if label == 'zero' else 1)

        pos += step_samples

    return bits if len(bits) >= 8 else None


def _bits_to_payload(bits: list[int]) -> str | None:
    for n_chars in range(1, MAX_PAYLOAD_BYTES + 1):
        n_bits = (n_chars + 1) * 8
        if len(bits) < n_bits:
            break

        data_bits     = bits[:n_chars * 8]
        checksum_bits = bits[n_chars * 8: n_bits]

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
        rx_chk  = 0
        for b in checksum_bits:
            rx_chk = (rx_chk << 1) | b

        if rx_chk == _checksum(decoded):
            return decoded

    return None


def decode_from_bytes(audio_bytes: bytes, sr: int = SAMPLE_RATE) -> str | None:
    samples = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32)
    signal  = samples / 32768.0
    return decode_signal(signal, sr)
