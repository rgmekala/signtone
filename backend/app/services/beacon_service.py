"""
Signtone - Beacon Service v2
=============================
Chirp/LFM encoder + matched-filter correlation decoder.

Architecture:
  Encoder: Each bit = Linear Frequency Modulated (LFM) chirp
           bit 1 = chirp sweeping UP   (f_low → f_high)
           bit 0 = chirp sweeping DOWN (f_high → f_low)
           sync  = long up+down arc    (unique preamble)

  Decoder: Cross-correlation against reference chirp templates
           Peak detection - 20-30dB more sensitive than Goertzel
           Works through room noise, crowd noise, poor acoustics

Profiles:
  ULTRASONIC: 15-17 kHz - inaudible, PA system required
  AUDIBLE:    2-4 kHz   - pleasant, laptop/phone speaker viable
"""

import logging
import numpy as np
from enum import Enum
from scipy.io import wavfile
from scipy.signal import butter, sosfilt, correlate, find_peaks

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# Enums
# ─────────────────────────────────────────────────────────────────────────────

class FrequencyProfile(str, Enum):
    ULTRASONIC = "ultrasonic"   # 15-17 kHz, inaudible, ~30m
    AUDIBLE    = "audible"      # 2-4 kHz, pleasant, ~30m laptop / ~100m PA

class ChimeStyle(str, Enum):
    NONE    = "none"
    MARIMBA = "marimba"
    BELL    = "bell"
    MODERN  = "modern"


# ─────────────────────────────────────────────────────────────────────────────
# Profiles
# ─────────────────────────────────────────────────────────────────────────────

PROFILES = {
    FrequencyProfile.ULTRASONIC: {
        "f_low":        15000,   # chirp start (down) / end (up)
        "f_high":       17000,   # chirp end   (up)   / start (down)
        "bandpass_low": 14000,
        "bandpass_high":18000,
        "label":        "Ultrasonic chirp (15-17 kHz)",
    },
    FrequencyProfile.AUDIBLE: {
        "f_low":        2000,    # chirp start (down) / end (up)
        "f_high":       4000,    # chirp end   (up)   / start (down)
        "bandpass_low": 1500,
        "bandpass_high":4500,
        "label":        "Audible chirp (2-4 kHz)",
    },
}

# ── Timing ────────────────────────────────────────────────────────────────────
SAMPLE_RATE       = 44100
SYMBOL_DUR        = 0.08    # seconds per bit chirp
GUARD_DUR         = 0.01    # seconds silence between symbols
SYNC_DUR          = 0.20    # seconds sync preamble
AMPLITUDE         = 0.8     # higher than before - maximise SNR
MAX_PAYLOAD_BYTES = 32

# ── Correlation detection ─────────────────────────────────────────────────────
CORR_THRESHOLD    = 0.20    # sync detection threshold
BIT_THRESHOLD     = 0.08    # bit detection threshold - lower than sync
                            # mic-captured bits are weaker than sync peak

# Legacy constants (backwards compat)
FREQ_SYNC = 15000
FREQ_ZERO = 16000
FREQ_ONE  = 17000
SNR_THRESHOLD = 2.5


# ─────────────────────────────────────────────────────────────────────────────
# Chirp primitives
# ─────────────────────────────────────────────────────────────────────────────

def _chirp(f_start: float, f_end: float, duration: float,
           sr: int = SAMPLE_RATE, amplitude: float = AMPLITUDE) -> np.ndarray:
    """
    Linear Frequency Modulated (LFM) chirp.
    Sweeps linearly from f_start to f_end over duration seconds.
    Much more noise-resistant than fixed tones - used in radar/sonar.
    """
    n     = int(sr * duration)
    t     = np.linspace(0, duration, n, endpoint=False)
    # Instantaneous phase = integral of instantaneous frequency
    # f(t) = f_start + (f_end - f_start) * t / duration
    phase = 2 * np.pi * (f_start * t + (f_end - f_start) * t**2 / (2 * duration))
    sig   = amplitude * np.sin(phase)
    # Smooth envelope - prevents spectral splatter at edges
    fade  = int(n * 0.10)   # 10% fade each end
    if fade > 0:
        sig[:fade]  *= np.linspace(0, 1, fade)
        sig[-fade:] *= np.linspace(1, 0, fade)
    return sig.astype(np.float32)


def _silence(duration: float, sr: int = SAMPLE_RATE) -> np.ndarray:
    return np.zeros(int(sr * duration), dtype=np.float32)


def _checksum(payload: str) -> int:
    return sum(payload.encode("ascii")) % 256


def _bandpass(signal: np.ndarray, sr: int, low: float, high: float) -> np.ndarray:
    sos = butter(4, [low / (sr / 2), high / (sr / 2)], btype='band', output='sos')
    return sosfilt(sos, signal).astype(np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# Reference chirp templates (used by decoder)
# ─────────────────────────────────────────────────────────────────────────────

def _make_templates(profile: FrequencyProfile, sr: int = SAMPLE_RATE) -> dict:
    """
    Generate reference chirp templates for matched filter correlation.
    Returns dict with 'up', 'down', 'sync' templates.
    """
    p      = PROFILES[profile]
    f_low  = p["f_low"]
    f_high = p["f_high"]

    return {
        # bit 1 = chirp UP
        "up":   _chirp(f_low,  f_high, SYMBOL_DUR, sr, amplitude=1.0),
        # bit 0 = chirp DOWN
        "down": _chirp(f_high, f_low,  SYMBOL_DUR, sr, amplitude=1.0),
        # sync = up then down arc (unique shape, hard to confuse with noise)
        "sync": np.concatenate([
            _chirp(f_low,  f_high, SYNC_DUR / 2, sr, amplitude=1.0),
            _chirp(f_high, f_low,  SYNC_DUR / 2, sr, amplitude=1.0),
        ]),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Zen Bowl signature chime (unchanged)
# ─────────────────────────────────────────────────────────────────────────────

def _chime_z2(sr: int = SAMPLE_RATE) -> np.ndarray:
    """
    Signtone signature sound - Zen Bowl (z2).
    Deep 256 Hz strike with inharmonic partials and long resonant decay.
    """
    freq = 256.0
    dur  = 5.0
    n    = int(sr * dur)
    t    = np.linspace(0, dur, n)
    sig  = (
        0.50 * np.sin(2 * np.pi * freq       * t) * np.exp(-t * 0.8) +
        0.25 * np.sin(2 * np.pi * freq * 2.8 * t) * np.exp(-t * 1.8) +
        0.15 * np.sin(2 * np.pi * freq * 5.1 * t) * np.exp(-t * 3.0) +
        0.10 * np.sin(2 * np.pi * freq * 7.3 * t) * np.exp(-t * 5.0)
    ) * AMPLITUDE
    mx = np.max(np.abs(sig))
    if mx > 0:
        sig = sig / mx * AMPLITUDE
    a = int(sr * 0.003)
    r = int(sr * 0.300)
    sig[:a]  *= np.linspace(0, 1, a)
    sig[-r:] *= np.linspace(1, 0, r)
    return sig.astype(np.float32)

def _chime_marimba(sr: int = SAMPLE_RATE) -> np.ndarray:
    return _chime_z2(sr)

def _chime_bell(sr: int = SAMPLE_RATE) -> np.ndarray:
    return _chime_z2(sr)

def _chime_modern(sr: int = SAMPLE_RATE) -> np.ndarray:
    return _chime_z2(sr)

def _get_chime(style: ChimeStyle, sr: int = SAMPLE_RATE) -> np.ndarray:
    if style == ChimeStyle.NONE:
        return np.array([], dtype=np.float32)
    return _chime_z2(sr)


# ─────────────────────────────────────────────────────────────────────────────
# Encoder
# ─────────────────────────────────────────────────────────────────────────────

def encode_payload(
    payload: str,
    profile: FrequencyProfile = FrequencyProfile.ULTRASONIC,
    chime: ChimeStyle = ChimeStyle.NONE,
) -> np.ndarray:
    """
    Encode payload as LFM chirp sequence.

    bit 1 → chirp UP   (f_low  → f_high)
    bit 0 → chirp DOWN (f_high → f_low)
    sync  → arc UP then DOWN (unique preamble + end marker)
    """
    if len(payload) > MAX_PAYLOAD_BYTES:
        raise ValueError(f"Payload too long: {len(payload)} (max {MAX_PAYLOAD_BYTES})")
    if not payload.isascii():
        raise ValueError("Payload must be ASCII only")

    p      = PROFILES[profile]
    f_low  = p["f_low"]
    f_high = p["f_high"]

    logger.info(f"Encoding '{payload}' | profile={profile} | chime={chime}")

    segments = []

    # ── Optional chime intro ──────────────────────────────────────────────────
    intro = _get_chime(chime)
    if len(intro) > 0:
        segments.append(intro)
        segments.append(_silence(0.05))

    # ── Sync preamble: arc UP then DOWN ──────────────────────────────────────
    segments.append(_chirp(f_low,  f_high, SYNC_DUR / 2))
    segments.append(_chirp(f_high, f_low,  SYNC_DUR / 2))
    segments.append(_silence(GUARD_DUR))

    # ── Data bits ─────────────────────────────────────────────────────────────
    for char in payload:
        byte = ord(char)
        for bit_pos in range(7, -1, -1):
            bit = (byte >> bit_pos) & 1
            if bit == 1:
                segments.append(_chirp(f_low, f_high, SYMBOL_DUR))
            else:
                segments.append(_chirp(f_high, f_low, SYMBOL_DUR))
            segments.append(_silence(GUARD_DUR))

    # ── Checksum bits ─────────────────────────────────────────────────────────
    chk = _checksum(payload)
    for bit_pos in range(7, -1, -1):
        bit = (chk >> bit_pos) & 1
        if bit == 1:
            segments.append(_chirp(f_low, f_high, SYMBOL_DUR))
        else:
            segments.append(_chirp(f_high, f_low, SYMBOL_DUR))
        segments.append(_silence(GUARD_DUR))

    # ── End sync marker ───────────────────────────────────────────────────────
    segments.append(_chirp(f_low,  f_high, SYNC_DUR / 4))
    segments.append(_chirp(f_high, f_low,  SYNC_DUR / 4))

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
    signal = encode_payload(payload, profile=profile, chime=chime)
    pcm    = (signal * 32767).astype(np.int16)
    wavfile.write(output_path, SAMPLE_RATE, pcm)
    logger.info(f"Saved: {output_path}")
    return output_path


def save_chime_wav(style: ChimeStyle, output_path: str) -> str:
    chime = _get_chime(style)
    if len(chime) == 0:
        raise ValueError("ChimeStyle.NONE has no audio to preview")
    pcm = (chime * 32767).astype(np.int16)
    wavfile.write(output_path, SAMPLE_RATE, pcm)
    return output_path


# ─────────────────────────────────────────────────────────────────────────────
# Matched Filter Correlation Decoder
# ─────────────────────────────────────────────────────────────────────────────

def _normalised_correlation(signal: np.ndarray, template: np.ndarray) -> np.ndarray:
    """
    Cross-correlate signal against template, normalised to [-1, 1].
    Uses proper energy normalisation that handles near-zero signal energy.
    """
    n_sig  = len(signal)
    n_tmpl = len(template)
    if n_sig < n_tmpl:
        return np.zeros(1)

    corr = correlate(signal, template, mode='valid')

    # Sliding window energy of signal
    sig_sq  = signal ** 2
    cum_sq  = np.cumsum(sig_sq)
    win_end = cum_sq[n_tmpl - 1:]
    win_str = np.concatenate([[0], cum_sq[:len(cum_sq) - n_tmpl]])
    energy  = win_end - win_str

    tmpl_energy = np.sum(template ** 2)

    # Only normalise where signal energy is meaningful
    # This prevents division by near-zero causing huge values
    min_energy = tmpl_energy * 0.0001  # 0.01% of template energy minimum
    valid_mask = energy > min_energy

    result = np.zeros_like(corr)
    denom  = np.sqrt(energy[valid_mask] * tmpl_energy)
    result[valid_mask] = corr[valid_mask] / denom

    # Clip to [-1, 1] for safety
    return np.clip(result, -1.0, 1.0)


def _find_sync_positions(
    signal: np.ndarray,
    sync_template: np.ndarray,
    sr: int,
    threshold: float = CORR_THRESHOLD,
) -> list[int]:
    """
    Find all positions where the sync preamble occurs in the signal.
    Returns sample indices of sync starts.
    """
    corr   = _normalised_correlation(signal, sync_template)
    corr   = np.abs(corr)

    # Minimum distance between peaks = sync duration samples
    min_dist = int(sr * SYNC_DUR * 0.8)
    peaks, props = find_peaks(corr, height=threshold, distance=min_dist)

    if len(peaks) == 0:
        return []

    # Sort by correlation strength
    order = np.argsort(props['peak_heights'])[::-1]
    return [int(peaks[i]) for i in order]


def _decode_bits_from(
    signal: np.ndarray,
    start: int,
    up_template: np.ndarray,
    down_template: np.ndarray,
    symbol_samples: int,
    step_samples: int,
    max_bits: int,
) -> list[int] | None:
    """
    Walk forward from start collecting bits using matched filter correlation.
    Always collects until end of signal - doesn't stop on low correlation.
    Low correlation bits are still assigned (majority vote: up vs down).
    Only stops at hard silence (both correlations near zero).
    """
    bits      = []
    pos       = start
    n         = len(signal)
    zero_runs = 0   # consecutive near-zero windows

    while pos + symbol_samples <= n and len(bits) < max_bits:
        seg = signal[pos: pos + symbol_samples]

        c_up   = float(np.max(np.abs(_normalised_correlation(seg, up_template))))
        c_down = float(np.max(np.abs(_normalised_correlation(seg, down_template))))

        both = max(c_up, c_down)

        # Hard silence - both very low AND we already have bits
        if both < 0.02 and len(bits) > 0:
            zero_runs += 1
            if zero_runs >= 3:   # 3 consecutive silent windows = end of payload
                break
        else:
            zero_runs = 0

        # Always assign a bit - whichever correlation is higher
        bits.append(1 if c_up >= c_down else 0)
        pos += step_samples

    return bits if len(bits) >= 8 else None


def decode_signal(
    signal: np.ndarray,
    sr: int = SAMPLE_RATE,
    profile: FrequencyProfile = FrequencyProfile.ULTRASONIC,
) -> str | None:
    """
    Decode chirp signal using matched filter correlation.
    Auto-tries both profiles as fallback.
    """
    result = _decode_with_profile(signal, sr, profile)
    if result:
        return result

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
    bandpass_low  = p["bandpass_low"]
    bandpass_high = p["bandpass_high"]

    symbol_samples = int(sr * SYMBOL_DUR)
    guard_samples  = int(sr * GUARD_DUR)
    step_samples   = symbol_samples + guard_samples
    sync_samples   = int(sr * SYNC_DUR)
    max_bits       = (MAX_PAYLOAD_BYTES + 1) * 8 + 16

    # ── 1. Bandpass filter ────────────────────────────────────────────────────
    try:
        filtered = _bandpass(signal, sr, bandpass_low, bandpass_high)
    except Exception:
        filtered = signal

    # ── 2. Build reference templates ─────────────────────────────────────────
    templates = _make_templates(profile, sr)
    up_tmpl   = templates["up"]
    down_tmpl = templates["down"]
    sync_tmpl = templates["sync"]

    # ── 3. Find sync positions via correlation ────────────────────────────────
    sync_positions = _find_sync_positions(filtered, sync_tmpl, sr)

    # ── Debug: log actual correlation values from mic capture ─────────────────
    sync_corr = np.abs(_normalised_correlation(filtered, sync_tmpl))
    logger.info(f"[{profile}] sync corr max={np.max(sync_corr):.4f} "
                f"mean={np.mean(sync_corr):.6f} "
                f">0.10={np.sum(sync_corr>0.10)} "
                f">0.05={np.sum(sync_corr>0.05)} "
                f">0.01={np.sum(sync_corr>0.01)}")

    if not sync_positions:
        logger.debug(f"[{profile}] No sync found")
        return None

    logger.info(f"[{profile}] {len(sync_positions)} sync position(s) found")

    # ── 4. Try decoding from each sync position ───────────────────────────────
    for sync_pos in sync_positions:
        # Start reading bits after sync + guard
        start = sync_pos + sync_samples + guard_samples

        # Try small timing offsets to handle clock drift
        for offset in [0, guard_samples // 2, -guard_samples // 2,
                       guard_samples, -guard_samples]:
            adj_start = start + offset
            if adj_start < 0:
                continue

            bits = _decode_bits_from(
                filtered, adj_start,
                up_tmpl, down_tmpl,
                symbol_samples, step_samples, max_bits,
            )
            if bits is None:
                logger.debug(f"[{profile}] sync_pos={sync_pos} offset={offset} - no bits")
                continue

            logger.info(f"[{profile}] sync_pos={sync_pos} offset={offset} "
                       f"bits={len(bits)} preview={bits[:16]}")
            result = _bits_to_payload(bits)
            if result is not None:
                logger.info(f"[{profile}] Decoded: '{result}' ✅")
                return result
            else:
                logger.debug(f"[{profile}] bits={len(bits)} - checksum failed")
            if result is not None:
                logger.info(f"[{profile}] Decoded: '{result}' ✅")
                return result

    logger.debug(f"[{profile}] Sync found but no valid payload decoded")
    return None


def _bits_to_payload(bits: list[int]) -> str | None:
    """Convert bit list to string, verify checksum."""
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


# ─────────────────────────────────────────────────────────────────────────────
# Legacy Goertzel (kept for reference, not used)
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


def decode_from_bytes(audio_bytes: bytes, sr: int = SAMPLE_RATE) -> str | None:
    samples = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32)
    signal  = samples / 32768.0
    return decode_signal(signal, sr)
