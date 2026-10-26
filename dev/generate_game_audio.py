"""Original stadium loop and goal fanfare, synthesized locally with Python's stdlib."""
from array import array
from pathlib import Path
import math
import random
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets/audio"
BEAT = 60 / 116
rng = random.Random(241024)


def note(buf, at, duration, midi, volume, bass=False):
    freq = 440 * 2 ** ((midi - 69) / 12)
    for i in range(int(duration * RATE)):
        t = i / RATE
        env = min(1, t / 0.008) * math.exp(-t * (5 if bass else 7))
        env *= min(1, (duration - t) / 0.025)
        phase = math.tau * freq * t
        tone = math.sin(phase) + 0.22 * math.sin(2 * phase) + 0.09 * math.sin(3 * phase)
        buf[(int(at * RATE) + i) % len(buf)] += tone * env * volume


def drum(buf, at, kind, volume):
    duration = {"kick": 0.28, "snare": 0.17, "hat": 0.055}[kind]
    for i in range(int(duration * RATE)):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        if kind == "kick":
            value = math.sin(math.tau * (45 * t + 7 * (1 - math.exp(-t * 35)))) * math.exp(-t * 18)
        elif kind == "snare":
            value = (noise * 0.7 + math.sin(math.tau * 180 * t) * 0.3) * math.exp(-t * 30)
        else:
            value = noise * math.exp(-t * 90)
        buf[(int(at * RATE) + i) % len(buf)] += value * volume * min(1, t / 0.0015)


def save(name, data):
    peak = max(abs(v) for v in data)
    pcm = array("h", (round(v * 0.84 / peak * 32767) for v in data))
    with wave.open(str(OUT / name), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes(pcm.tobytes())
    print(f"{name}: {len(data) / RATE:.2f}s, PCM peak 0.84")


def main():
    OUT.mkdir(exist_ok=True)
    loop = array("f", [0]) * round(32 * BEAT * RATE)
    roots = [45, 41, 48, 43, 45, 41, 48, 43]
    melody = [69, 72, 76, 72, 69, 67, 64, 67, 72, 76, 79, 76, 74, 71, 67, 71]
    for bar, root in enumerate(roots):
        for beat in range(4):
            at = (bar * 4 + beat) * BEAT
            drum(loop, at, "kick", 0.55)
            if beat in (1, 3):
                drum(loop, at, "snare", 0.23)
            drum(loop, at + BEAT / 2, "hat", 0.12)
            note(loop, at + BEAT / 2, BEAT * 0.44, root, 0.28, True)
            if beat in (0, 2):
                for pitch in (root + 12, root + 19, root + (15 if root == 45 else 16)):
                    note(loop, at + BEAT / 4, BEAT * 0.8, pitch, 0.075)
            if bar % 2 == 1:
                note(loop, at, BEAT * 0.75, melody[(bar // 2 * 4 + beat) % 16], 0.12)
    save("stadium_loop.wav", loop)
    fanfare = array("f", [0]) * (RATE * 3)
    for at, chord in [(0, (60, 64, 67)), (0.22, (62, 65, 69)), (0.44, (64, 67, 72)), (0.78, (60, 67, 72, 76))]:
        for midi in chord:
            note(fanfare, at, 1.7, midi, 0.15)
        drum(fanfare, at, "kick", 0.26)
    for i in range(12):
        drum(fanfare, 0.8 + i * 0.09, "snare", 0.05)
    save("goal_celebration.wav", fanfare)


if __name__ == "__main__":
    main()
