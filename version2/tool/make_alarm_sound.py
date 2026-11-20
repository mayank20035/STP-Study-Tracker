"""Synthesises the target alarm chime (res/raw/alarm.wav).

A bright three-note bell arpeggio played twice, then a short pause. Android's
insistent notification flag loops it until the user presses Stop.
"""
import math
import struct
import sys
import wave

RATE = 44100


def bell(freq, dur, amp=1.0):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 7.5) * min(1.0, t * 400)  # fast attack, ringing decay
        v = (math.sin(2 * math.pi * freq * t)
             + 0.45 * math.sin(2 * math.pi * freq * 2.0 * t) * math.exp(-t * 4)
             + 0.25 * math.sin(2 * math.pi * freq * 2.76 * t) * math.exp(-t * 9))
        out.append(v * env * amp)
    return out


def mix(base, add, offset):
    need = offset + len(add)
    if len(base) < need:
        base.extend([0.0] * (need - len(base)))
    for i, v in enumerate(add):
        base[offset + i] += v
    return base


def main(path):
    notes = [1318.5, 1568.0, 2093.0]  # E6 G6 C7
    samples = []
    step = int(RATE * 0.16)
    pos = 0
    for rep in range(2):
        for f in notes:
            mix(samples, bell(f, 0.9), pos)
            pos += step
        pos += int(RATE * 0.12)
    total = pos + int(RATE * 0.75)
    samples.extend([0.0] * (total - len(samples)))
    peak = max(abs(s) for s in samples) or 1
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(s / peak * 0.85 * 32767)) for s in samples[:total]))
    print(f'wrote {path} ({total / RATE:.2f}s)')


if __name__ == '__main__':
    main(sys.argv[1])
