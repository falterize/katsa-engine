"""Generate original stereo demonstration audio. No third-party audio assets."""

import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / 'assets/audio'
RATE = 44100


def write(name, duration, sample):
    frames = bytearray()
    for i in range(int(RATE * duration)):
        left, right = sample(i / RATE)
        frames.extend(
            struct.pack(
                '<hh', int(max(-1, min(1, left)) * 32767), int(max(-1, min(1, right)) * 32767)
            )
        )
    destination = ROOT / ('music' if name == 'demoMusic.wav' else 'effects') / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(destination), 'wb') as output:
        output.setparams((2, 2, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(frames)


def chime(t):
    envelope = math.exp(-2 * t) * min(1, t * 100)
    return (
        0.45 * envelope * (math.sin(math.tau * 440 * t) + 0.3 * math.sin(math.tau * 880 * t)),
        0.45
        * envelope
        * (math.sin(math.tau * 554.365 * t) + 0.3 * math.sin(math.tau * 1108.73 * t)),
    )


def music(t):
    chord = [
        (220, 277.18, 329.63),
        (174.61, 220, 261.63),
        (261.63, 329.63, 392),
        (196, 246.94, 293.66),
    ][int(t / 2) % 4]
    beat = t % 0.5
    env = min(1, beat * 60) * math.exp(-beat * 5)
    fade = min(1, t * 10, (8 - t) * 10)
    left = sum(math.sin(math.tau * f * t) for f in chord) / 3
    right = sum(math.sin(math.tau * f * 1.001 * t + 0.3) for f in chord) / 3
    bass = math.sin(math.tau * (chord[0] / 2) * t) * 0.2
    return fade * (left * 0.3 * env + bass), fade * (right * 0.3 * env + bass)


write('stereoChime.wav', 2, chime)
write('demoMusic.wav', 8, music)
