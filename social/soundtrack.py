"""Original synthesized soundtrack for the Sur3ati motion video (20 s), timed to its scenes.
Scenes: 0-3.6 map | 3.6-7.2 logo | 7.2-12.6 gauge | 12.6-16.4 report | 16.4-20 CTA
"""
import numpy as np
from scipy.signal import butter, sosfilt
from scipy.io import wavfile

SR = 44100
DUR = 20.0
N = int(SR * DUR)
t = np.arange(N) / SR
BPM = 112
BEAT = 60 / BPM
mix = np.zeros(N)

def sec(x): return int(x * SR)
def note(n): return 440.0 * 2 ** ((n - 69) / 12)            # midi -> Hz
def env(n, a, d, s, r, hold):                                  # ADSR (samples)
    a, d, r, hold = sec(a), sec(d), sec(r), sec(hold)
    e = np.zeros(n)
    i = 0
    e[i:i+a] = np.linspace(0, 1, a); i += a
    e[i:i+d] = np.linspace(1, s, d); i += d
    e[i:i+hold] = s; i += hold
    e[i:i+r] = np.linspace(s, 0, r)
    return e[:n]
def lp(x, fc, order=2):
    sos = butter(order, fc / (SR/2), btype='low', output='sos'); return sosfilt(sos, x)
def hp(x, fc, order=2):
    sos = butter(order, fc / (SR/2), btype='high', output='sos'); return sosfilt(sos, x)
def add(sig, at, gain=1.0):
    i = sec(at); n = min(len(sig), N - i)
    if n > 0: mix[i:i+n] += sig[:n] * gain

# ---- harmony: A minor, one chord per bar (bar = 4 beats = 2.14 s) ----
CHORDS = [[57,60,64],[53,57,60],[48,52,55],[55,59,62]]       # Am, F, C, G (midi)
BARS = int(np.ceil(DUR / (4*BEAT)))

def pad_chord(midis, length):
    n = sec(length); tt = np.arange(n) / SR; out = np.zeros(n)
    for m in midis:
        f = note(m)
        for k, g in ((1,1),(2,.35),(3,.18),(4,.08)):           # gentle saw-ish partials
            det = 1 + 0.004*np.sin(2*np.pi*0.3*tt + m)           # slow chorus
            out += g*np.sin(2*np.pi*f*k*det*tt)
    out *= env(n, 0.6, 0.2, 0.8, 0.9, length-1.7)
    return lp(out, 1800) * 0.16

def pluck(m, length=0.28):
    n = sec(length); tt = np.arange(n) / SR; f = note(m)
    x = np.sin(2*np.pi*f*tt) + 0.3*np.sin(2*np.pi*2*f*tt)
    return x * np.exp(-tt*14) * 0.35

def sub(m, length):
    n = sec(length); tt = np.arange(n)/SR
    return np.sin(2*np.pi*note(m-12)*tt) * env(n, .01, .05, .9, .1, length-.16) * 0.42

def kick():
    n = sec(0.35); tt = np.arange(n)/SR
    f = 150*np.exp(-tt*22) + 45
    return np.sin(2*np.pi*np.cumsum(f)/SR) * np.exp(-tt*9) * 1.0

def hat(open_=False):
    n = sec(0.25 if open_ else 0.06); x = np.random.randn(n)
    return hp(x, 7000) * np.exp(-np.arange(n)/SR*(12 if open_ else 70)) * 0.22

def clap():
    n = sec(0.2); x = np.random.randn(n); e = np.exp(-np.arange(n)/SR*28)
    for d in (0.008, 0.017): e += np.roll(np.exp(-np.arange(n)/SR*28), sec(d))
    return lp(hp(x, 1200), 6000) * e * 0.18

def riser(length):
    n = sec(length); tt = np.arange(n)/SR; x = np.random.randn(n)
    out = np.zeros(n)
    steps = 40
    for i in range(steps):                                        # sweeping band-pass, rising
        a, b = i*n//steps, (i+1)*n//steps
        fc = 300 + (i/steps)**2 * 6000
        out[a:b] = lp(hp(x[a:b], fc*0.7), fc*1.6)
    return out * (tt/length)**2 * 0.5

def impact(m=45):
    n = sec(1.6); tt = np.arange(n)/SR
    boom = np.sin(2*np.pi*(note(m)*np.exp(-tt*1.5)+30)*tt) * np.exp(-tt*2.2)
    noise = lp(np.random.randn(n), 900) * np.exp(-tt*6)
    return (boom*0.9 + noise*0.35)

def whoosh(length=0.7):
    n = sec(length); tt = np.arange(n)/SR; x = np.random.randn(n)
    e = np.sin(np.pi*tt/length)**2
    return lp(hp(x, 800), 5000) * e * 0.25

def chime(midis, at, spread=0.09):
    for i, m in enumerate(midis):
        n = sec(1.8); tt = np.arange(n)/SR; f = note(m)
        x = (np.sin(2*np.pi*f*tt) + 0.4*np.sin(2*np.pi*f*3.01*tt)) * np.exp(-tt*2.4) * 0.28
        add(x, at + i*spread)

np.random.seed(3)
# ---- pads + bass on every bar ----
for b in range(BARS):
    start = b*4*BEAT; ch = CHORDS[b % 4]
    add(pad_chord(ch, 4*BEAT), start, 1.0 if start >= 3.4 else 0.55)
    if start >= 3.4: add(sub(ch[0], 4*BEAT), start)

# ---- arpeggio (16ths) from the logo scene onward, brighter from the gauge scene ----
step = BEAT/4; i = 0; tt_ = 3.6
while tt_ < 16.2:
    ch = CHORDS[int(tt_ // (4*BEAT)) % 4]
    pattern = [ch[0]+12, ch[1]+12, ch[2]+12, ch[1]+24]
    gain = 0.5 if tt_ < 7.2 else 0.85
    if i % 2 == 0 or tt_ >= 7.2: add(pluck(pattern[i % 4]), tt_, gain)
    tt_ += step; i += 1

# ---- drums: hats from logo scene, kick+clap from gauge scene ----
b = 0; tt_ = 3.6
while tt_ < 16.4:
    if tt_ >= 3.6: add(hat(open_=(b % 8 == 7)), tt_, 0.7 if tt_ < 7.2 else 1.0)     # 8th-note hats
    if tt_ >= 7.2 and b % 2 == 0: add(kick(), tt_)                                 # kick on beats
    if tt_ >= 7.2 and b % 4 == 2: add(clap(), tt_)                                 # clap on 2 & 4
    tt_ += BEAT/2; b += 1

# ---- scene hits ----
add(riser(1.6), 2.0)               # into the logo
add(impact(45), 3.6)               # logo lands
add(whoosh(), 3.45)
add(riser(2.0), 5.2)               # into the gauge
add(impact(43), 7.2)
add(riser(1.2), 11.4)              # into the report
add(impact(45), 12.6)
chime([76, 80, 83, 88], 12.9)      # grade B pop (E major-ish sparkle)
add(whoosh(0.6), 16.3)             # into the CTA
chime([69, 76, 81], 16.5, 0.12)    # final chime on A

# gauge sweep ticks (accelerating clicks while the needle climbs, 7.6 -> 10.4)
tk = 7.6
while tk < 10.4:
    n = sec(0.03); x = hp(np.random.randn(n), 3000) * np.exp(-np.arange(n)/SR*250) * 0.18
    add(x, tk); tk += 0.22 - 0.16 * ((tk-7.6)/2.8)

# ---- master: gentle glue, fade out, normalize ----
x = mix
x = np.tanh(x * 1.15) / np.tanh(1.15)                 # soft clip
fade = np.ones(N); fo = sec(2.2); fade[-fo:] = np.linspace(1, 0, fo); fi = sec(0.4); fade[:fi] = np.linspace(0, 1, fi)
x = x * fade
x = x / np.max(np.abs(x)) * 0.89
wavfile.write('soundtrack.wav', SR, (x * 32767).astype(np.int16))
print('wrote soundtrack.wav', len(x)/SR, 's')
