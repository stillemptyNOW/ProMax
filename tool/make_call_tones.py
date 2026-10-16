import math
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"


def chime(frequency, start, length, total):
    out = [0.0] * total
    first = int(start * RATE)
    count = int(length * RATE)
    attack = int(0.008 * RATE)
    for i in range(count):
        index = first + i
        if index >= total:
            break
        t = i / RATE
        envelope = math.exp(-t * 5.5)
        if i < attack:
            envelope *= i / attack
        tone = (
            math.sin(2 * math.pi * frequency * t)
            + 0.35 * math.sin(2 * math.pi * frequency * 2 * t) * math.exp(-t * 9)
            + 0.12 * math.sin(2 * math.pi * frequency * 3 * t) * math.exp(-t * 14)
        )
        out[index] += tone * envelope
    return out


def mix(*tracks):
    return [sum(values) for values in zip(*tracks)]


def ringtone():
    total = int(3.2 * RATE)
    notes = [
        (659.25, 0.00),
        (830.61, 0.16),
        (987.77, 0.32),
        (659.25, 0.80),
        (830.61, 0.96),
        (987.77, 1.12),
    ]
    return mix(*(chime(f, start, 1.2, total) for f, start in notes))


def ringback():
    total = int(4.0 * RATE)
    on = int(1.0 * RATE)
    fade = int(0.03 * RATE)
    out = [0.0] * total
    for i in range(on):
        envelope = min(1.0, i / fade, (on - i) / fade)
        t = i / RATE
        out[i] = math.sin(2 * math.pi * 425 * t) * envelope
    return out


def write(name, samples, level):
    peak = max(abs(s) for s in samples) or 1.0
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s / peak * level)) * 32767))
        for s in samples
    )
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(frames)


if __name__ == "__main__":
    write("ringtone.wav", ringtone(), 0.7)
    write("ringback.wav", ringback(), 0.35)
