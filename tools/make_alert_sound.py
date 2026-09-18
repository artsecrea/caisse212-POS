"""Generate assets/sounds/new_order.wav — the online-order alert.

Kept in the repo (rather than a scratch dir) so the sound can be re-tuned
without hand-editing binary data. Run from the project root:

    python tools/make_alert_sound.py

Design notes, because the choices are not arbitrary:

* **~2.1 kHz carrier.** Human hearing peaks around 2-4 kHz, and the small
  speakers in POS terminals and tablets roll off badly below ~500 Hz. The
  previous chime sat at 988 Hz and measured -21 dBFS RMS; on till hardware that
  is barely audible over a room. Same digital level at 2 kHz is far louder in
  the room.

* **Harmonic-rich, not a pure sine.** A sine is the quietest possible waveform
  for a given peak and is easily masked by broadband kitchen noise. Adding odd
  harmonics gives it an edge that cuts through, without the harshness of a full
  square wave.

* **Three beeps, twice.** Repetition is what gets noticed; a single ping is
  missed if it lands while someone is talking. The gap between groups is what
  makes it read as an alert rather than a UI blip.

* **Sustained, not decaying.** A percussive decay wastes most of the duration at
  low level. Flat-topped beeps keep the RMS high, which is what "loud" actually
  means to a listener.

* **5 ms fades** on every beep edge, so there are no clicks at the boundaries.
"""

import math
import struct
import wave

RATE = 44100
CARRIER = 2100.0        # Hz
BEEP = 0.11             # seconds of tone
GAP = 0.06              # silence between beeps in a group
GROUP_GAP = 0.20        # silence between the two groups
BEEPS_PER_GROUP = 3
GROUPS = 2
PEAK = 0.97             # leave a sliver of headroom so nothing clips
FADE = 0.005            # seconds


def beep(hz, seconds):
    out = []
    n = int(RATE * seconds)
    fade = max(1, int(RATE * FADE))
    for i in range(n):
        t = i / RATE
        # Fundamental + 3rd only: bright and cutting, still musical. A 5th harmonic here lands near 12 kHz: it
        # adds harshness and very steep sample-to-sample slopes while adding
        # almost nothing to perceived loudness, because small POS speakers roll
        # off up there anyway.
        v = (
            math.sin(2 * math.pi * hz * t)
            + 0.40 * math.sin(2 * math.pi * hz * 3 * t)
        ) / 1.40
        # Equal-length fades at both ends kill the edge clicks.
        env = 1.0
        if i < fade:
            env = i / fade
        elif i > n - fade:
            env = (n - i) / fade
        out.append(v * env)
    return out


def silence(seconds):
    return [0.0] * int(RATE * seconds)


samples = []
for g in range(GROUPS):
    for b in range(BEEPS_PER_GROUP):
        # Each beep a touch higher than the last: rising patterns read as
        # "something arrived", falling ones as "something failed".
        samples += beep(CARRIER * (1.0 + 0.06 * b), BEEP)
        if b < BEEPS_PER_GROUP - 1:
            samples += silence(GAP)
    if g < GROUPS - 1:
        samples += silence(GROUP_GAP)

# Normalise to the target peak rather than trusting the arithmetic above.
raw_peak = max(abs(s) for s in samples)
scale = PEAK / raw_peak
samples = [s * scale for s in samples]

peak = max(abs(s) for s in samples)
rms = math.sqrt(sum(s * s for s in samples) / len(samples))
assert peak <= 1.0, peak

frames = b"".join(
    struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
)

out = "assets/sounds/new_order.wav"
with wave.open(out, "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(frames)

print(
    "wrote %s: %.2fs  peak %.3f (%.1f dBFS)  rms %.3f (%.1f dBFS)"
    % (
        out,
        len(samples) / RATE,
        peak,
        20 * math.log10(peak),
        rms,
        20 * math.log10(rms),
    )
)
