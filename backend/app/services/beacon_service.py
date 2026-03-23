"""
Signtone - Ultrasonic Beacon Service
=====================================
Encodes a short string payload (event ID) into an inaudible ultrasonic
audio signal using Binary Frequency Shift Keying (BFSK).

Encode side  (backend / admin dashboard):
    payload → BFSK encoder → .wav file at 18-19 kHz
    Organizer plays this .wav through their PA / radio system

Decode side  (mobile app → backend):
    Phone mic captures audio → backend FFT analysis
    → detect BFSK tones → extract payload string

Frequency plan (all inaudible to most adults):
    SYNC tone  : 17500 Hz  - marks start of transmission
    BIT 0      : 18000 Hz
    BIT 1      : 19000 Hz
    GUARD band : 200 Hz silence between symbols
"""

import logging
import struct
import hashlib
import numpy as np
from scipy.signal import butter, sosfilt, spectrogram
from scipy.io import wavfile

logger = logging.getLogger(__name__)

# ── Frequency plan ────────────────────────────────────────────────────────────
SAMPLE_RATE  = 44100   # Hz - standard audio sample rate
FREQ_SYNC    = 17500   # Hz - sync / preamble tone
FREQ_ZERO    = 18000   # Hz - bit 0
FREQ_ONE     = 19000   # Hz - bit 1
SYMBOL_DUR   = 0.08    # seconds per bit symbol
GUARD_DUR    = 0.02    # seconds silence between symbols
SYNC_DUR     = 0.20    # seconds for sync tone
AMPLITUDE    = 0.6     # 0.0 - 1.0  (keep below 0.8 to avoid clipping)

# ── Detection thresholds ──────────────────────────────────────────────────────
DETECT_THRESHOLD  = 0.15   # minimum normalised magnitude to count as a tone
SYNC_MIN_DUR      = 0.10   # seconds of sync tone needed to trigger detection
MAX_PAYLOAD_BYTES = 32     # maximum payload length


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _tone(freq: float, duration: float, sr: int = SAMPLE_RATE) -> np.ndarray:
    """Generate a pure sine tone."""
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    return (AMPLITUDE * np.sin(2 * np.pi * freq * t)).astype(np.float32)


def _silence(duration: float, sr: int = SAMPLE_RATE) -> np.ndarray:
    """Generate silence."""
    return np.zeros(int(sr * duration), dtype=np.float32)


def _checksum(payload: str) -> int:
    """Simple 8-bit checksum of payload bytes."""
    return sum(payload.encode("ascii")) % 256


# ─────────────────────────────────────────────────────────────────────────────
# Encoder
# ─────────────────────────────────────────────────────────────────────────────

def encode_payload(payload: str) -> np.ndarray:
    """
    Encode a string payload into an ultrasonic audio signal.

    Structure:
        [SYNC tone 200ms]
        [8 bits per character] + [guard silence between bits]
        [8-bit checksum]
        [SYNC tone 100ms - end marker]

    Returns a float32 numpy array ready to save as .wav or stream.
    """
    if len(payload) > MAX_PAYLOAD_BYTES:
        raise ValueError(
            f"Payload too long: {len(payload)} chars "
            f"(max {MAX_PAYLOAD_BYTES})"
        )
    if not payload.isascii():
        raise ValueError("Payload must be ASCII characters only")

    logger.info(f"Encoding payload: '{payload}' ({len(payload)} chars)")

    segments = []

    # 1 - preamble sync tone
    segments.append(_tone(FREQ_SYNC, SYNC_DUR))
    segments.append(_silence(GUARD_DUR))

    # 2 - encode each character as 8 bits MSB-first
    for char in payload:
        byte = ord(char)
        for bit_pos in range(7, -1, -1):
            bit = (byte >> bit_pos) & 1
            freq = FREQ_ONE if bit else FREQ_ZERO
            segments.append(_tone(freq, SYMBOL_DUR))
            segments.append(_silence(GUARD_DUR))

    # 3 - checksum byte (8 bits)
    chk = _checksum(payload)
    for bit_pos in range(7, -1, -1):
        bit = (chk >> bit_pos) & 1
        freq = FREQ_ONE if bit else FREQ_ZERO
        segments.append(_tone(freq, SYMBOL_DUR))
        segments.append(_silence(GUARD_DUR))

    # 4 - end sync tone
    segments.append(_tone(FREQ_SYNC, SYNC_DUR * 0.5))

    signal = np.concatenate(segments)
    duration = len(signal) / SAMPLE_RATE
    logger.info(f"Encoded signal: {duration:.2f}s, {len(signal)} samples")
    return signal


def save_beacon_wav(payload: str, output_path: str) -> str:
    """
    Encode a payload and save it as a .wav file.
    Organizer plays this file through their PA or radio broadcast.
    """
    signal = encode_payload(payload)
    pcm = (signal * 32767).astype(np.int16)
    wavfile.write(output_path, SAMPLE_RATE, pcm)
    logger.info(f"Saved beacon to: {output_path}")
    return output_path


# ─────────────────────────────────────────────────────────────────────────────
# Decoder
# ─────────────────────────────────────────────────────────────────────────────

def _dominant_freq(segment: np.ndarray, sr: int = SAMPLE_RATE) -> tuple[float, float]:
    """
    Find the dominant frequency and its normalised magnitude in a segment.
    Returns (frequency_hz, magnitude_0_to_1).
    """
    windowed = segment * np.hanning(len(segment))
    fft = np.abs(np.fft.rfft(windowed))
    freqs = np.fft.rfftfreq(len(segment), d=1.0 / sr)

    # Focus on ultrasonic range 17000-20000 Hz only
    mask = (freqs >= 17000) & (freqs <= 20000)
    if not np.any(mask):
        return 0.0, 0.0

    ultra_fft = fft * mask
    peak_idx = np.argmax(ultra_fft)
    peak_mag = ultra_fft[peak_idx] / (np.max(fft) + 1e-10)
    return float(freqs[peak_idx]), float(peak_mag)


def decode_signal(signal: np.ndarray, sr: int = SAMPLE_RATE) -> str | None:
    """
    Decode an ultrasonic BFSK signal back to its original payload string.

    Returns the decoded string if successful, None if no valid beacon found.
    """
    symbol_samples = int(sr * SYMBOL_DUR)
    guard_samples  = int(sr * GUARD_DUR)
    step_samples   = symbol_samples + guard_samples
    sync_samples   = int(sr * SYNC_DUR)

    # ── Step 1: find sync tone ────────────────────────────────────────────────
    sync_start = None
    for i in range(0, len(signal) - sync_samples, guard_samples):
        seg = signal[i: i + sync_samples]
        freq, mag = _dominant_freq(seg, sr)
        if mag >= DETECT_THRESHOLD and abs(freq - FREQ_SYNC) < 300:
            sync_start = i + sync_samples + int(sr * GUARD_DUR)
            logger.info(f"Sync tone detected at sample {i} (mag={mag:.3f})")
            break

    if sync_start is None:
        logger.debug("No sync tone found in signal")
        return None

    # ── Step 2: decode bits ───────────────────────────────────────────────────
    bits = []
    pos  = sync_start

    while pos + symbol_samples <= len(signal):
        seg  = signal[pos: pos + symbol_samples]
        freq, mag = _dominant_freq(seg, sr)

        # Stop if below threshold (silence/end of signal)
        if mag < DETECT_THRESHOLD:
            break

        # Stop if we see the sync frequency again (end marker)
        if abs(freq - FREQ_SYNC) < 400:
            break

        # Classify bit: closer to FREQ_ONE or FREQ_ZERO
        if abs(freq - FREQ_ONE) < abs(freq - FREQ_ZERO):
            bits.append(1)
        else:
            bits.append(0)

        pos += step_samples

    logger.debug(f"Total bits decoded: {len(bits)}")

    if len(bits) < 16:   # need at least 2 bytes (1 char + checksum)
        logger.warning(f"Too few bits decoded: {len(bits)}")
        return None

    # Trim to nearest multiple of 8 if slightly off due to timing jitter
    remainder = len(bits) % 8
    if remainder != 0:
        logger.debug(f"Trimming {remainder} trailing bits to align to byte boundary")
        bits = bits[:len(bits) - remainder]

    if len(bits) < 16:
        logger.warning(f"Too few bits after trim: {len(bits)}")
        return None

    # ── Step 3: bits → bytes → string ────────────────────────────────────────
    # Last 8 bits are the checksum
    data_bits     = bits[:-8]
    checksum_bits = bits[-8:]

    if len(data_bits) % 8 != 0:
        logger.warning(f"Bit count not divisible by 8: {len(data_bits)}")
        return None

    chars = []
    for i in range(0, len(data_bits), 8):
        byte = 0
        for bit in data_bits[i: i + 8]:
            byte = (byte << 1) | bit
        if 32 <= byte <= 126:   # printable ASCII range
            chars.append(chr(byte))
        else:
            logger.warning(f"Non-printable byte decoded: {byte}")
            return None

    decoded = "".join(chars)

    # ── Step 4: verify checksum ───────────────────────────────────────────────
    rx_chk = 0
    for bit in checksum_bits:
        rx_chk = (rx_chk << 1) | bit

    expected_chk = _checksum(decoded)
    if rx_chk != expected_chk:
        logger.warning(
            f"Checksum mismatch: received {rx_chk}, expected {expected_chk}"
        )
        return None

    logger.info(f"Decoded payload: '{decoded}' ✅")
    return decoded


def decode_from_bytes(audio_bytes: bytes, sr: int = SAMPLE_RATE) -> str | None:
    """
    Decode a beacon from raw PCM bytes.
    Used when mobile app streams mic audio to the backend.
    """
    samples = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32)
    signal  = samples / 32768.0
    return decode_signal(signal, sr)
