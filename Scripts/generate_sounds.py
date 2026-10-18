"""Generate the app's short, original notification tones."""
import math
from pathlib import Path
import struct
import wave

ROOT = Path(__file__).resolve().parents[1] / "Pomodoro/Sounds"
ROOT.mkdir(exist_ok=True)
for name, frequencies, duration in [("bell", [880, 1760], 1.2), ("chime", [523.25, 659.25, 783.99], 1.5),
                                     ("softTap", [440, 660], 0.35), ("digital", [1046.5, 1318.5], 0.75)]:
    frames = bytearray()
    for sample in range(int(44100 * duration)):
        t = sample / 44100
        envelope = min(1, t / 0.008) * math.exp(-5 * t / duration) * min(1, (duration - t) / 0.05)
        value = sum(math.sin(2 * math.pi * f * t) for f in frequencies) / len(frequencies)
        if name == "digital" and int(t * 8) % 2: value = 0
        frames.extend(struct.pack("<h", int(18000 * envelope * value)))
    with wave.open(str(ROOT / (name + ".wav")), "wb") as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(44100)
        sound.writeframes(frames)


# Keep the original recordings stable; the softer presets use their own envelopes.
for name, duration in [("mellow", 0.9), ("wood", 0.4), ("ripple", 1.2)]:
    samples = []
    for sample in range(int(44100 * duration)):
        t = sample / 44100
        if name == "mellow":
            envelope = min(1, t / 0.025) * math.exp(-4 * t / duration) * min(1, (duration - t) / 0.12)
            value = envelope * (math.sin(2 * math.pi * 523.25 * t)
                                + 0.25 * math.sin(2 * math.pi * 659.25 * t))
        elif name == "wood":
            envelope = min(1, t / 0.005) * math.exp(-18 * t / duration) * min(1, (duration - t) / 0.05)
            value = envelope * (math.sin(2 * math.pi * 350 * t)
                                + 0.35 * math.sin(2 * math.pi * 720 * t))
        else:
            value = 0
            for onset, frequency in [(0, 523.25), (0.22, 659.25), (0.44, 783.99)]:
                age = t - onset
                if 0 <= age < 0.65:
                    envelope = min(1, age / 0.018) * math.exp(-5 * age / 0.65) * min(1, (0.65 - age) / 0.1)
                    value += envelope * math.sin(2 * math.pi * frequency * age)
        samples.append(value)
    peak = max(abs(value) for value in samples)
    frames = b"".join(struct.pack("<h", round(value / peak * 0.32 * 32767)) for value in samples)
    with wave.open(str(ROOT / (name + ".wav")), "wb") as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(44100)
        sound.writeframes(frames)
