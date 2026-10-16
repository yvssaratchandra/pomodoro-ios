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
