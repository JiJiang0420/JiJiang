#!/usr/bin/env python3
"""Rebuild original procedural audio and the game's Chinese UI font subset.

Run from any directory:
    python3 tools/generate_assets.py             # audio and font
    python3 tools/generate_assets.py --audio     # Python standard library only
    python3 tools/generate_assets.py --font      # requires fontTools
    python3 tools/generate_assets.py --font --font-source /path/to/NotoSansCJK-Regular.ttc

Audio is synthesized here; no recordings or third-party audio are used. Font
input is Noto Sans CJK SC (collection face 2), distributed under the SIL OFL 1.1.
The Debian fonts-noto-cjk package supplies the default font and copyright file.
For another installation, supply its matching original notice with --font-license.
The subset keeps the source license metadata and uses a distinct family name.
Use the same Python/fontTools versions and source files for reproducible builds.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import math
from pathlib import Path
import random
import struct
import tempfile
import wave


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SAMPLE_RATE = 22_050
RANDOM_SEED = 20_261_105
FONT_SOURCE = Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc")
FONT_LICENSE = Path("/usr/share/doc/fonts-noto-cjk/copyright")
DURATIONS = {
    "red": 0.24,
    "blue": 0.42,
    "gold": 0.40,
    "gold_place": 0.14,
    "gold_launch": 0.28,
    "switch": 0.18,
    "hurt": 0.20,
    "buy": 0.55,
    "ambience": 8.0,
}
TAU = math.tau


def atomic_write(path: Path, data: bytes) -> None:
    """Do not leave a partial resource if generation is interrupted."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            dir=path.parent, prefix=path.name + ".", suffix=".tmp", delete=False
        ) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def envelope(t: float, duration: float, attack: float, release: float) -> float:
    """Smooth both ends so frequently repeated cues do not click."""
    start = math.sin(math.pi * 0.5 * min(t / attack, 1.0)) ** 2
    end = math.sin(math.pi * 0.5 * min((duration - t) / release, 1.0)) ** 2
    return start * end


def chirp(t: float, duration: float, start_hz: float, end_hz: float) -> float:
    phase = start_hz * t + (end_hz - start_hz) * t * t / (2.0 * duration)
    return math.sin(TAU * phase)


def synthesize(name: str) -> bytes:
    """Return 22050 Hz mono signed-16-bit little-endian WAV bytes."""
    duration = DURATIONS[name]
    frames = int(duration * SAMPLE_RATE)
    # Independent seeds keep an existing cue stable if another cue is added.
    seed_offset = int.from_bytes(hashlib.sha256(name.encode("ascii")).digest()[:4], "big")
    rng = random.Random(RANDOM_SEED + seed_offset)
    samples = []
    filtered_noise = 0.0
    phases = [rng.random() * TAU for _ in range(5)]
    for frame in range(frames):
        t = frame / SAMPLE_RATE
        if name == "ambience":
            # All carrier and modulation periods divide eight seconds exactly.
            # This is a periodic signal, not an attack/release sound crossfaded
            # at its ends; Godot loops it at SAMPLE_RATE * 8 with no gap.
            slow = 0.78 + 0.15 * math.cos(TAU * t / duration)
            value = slow * (
                0.44 * math.sin(TAU * 440 * t / duration + phases[0])
                + 0.23 * math.sin(TAU * 660 * t / duration + phases[1])
                + 0.15 * math.sin(TAU * 881 * t / duration + phases[2])
            )
            shimmer = 0.06 + 0.025 * math.sin(TAU * 2 * t / duration)
            value += shimmer * math.sin(TAU * 1761 * t / duration + phases[3])
            value += 0.025 * math.sin(TAU * 2640 * t / duration + phases[4])
        else:
            noise = rng.uniform(-1.0, 1.0)
            filtered_noise += 0.12 * (noise - filtered_noise)
            gate = envelope(t, duration, 0.004, min(0.05, duration / 3.0))
            if name == "red":
                # A dry, falling tear: noisy edge plus a short resonant cut.
                value = (0.65 * (noise - filtered_noise)
                         + 0.32 * chirp(t, duration, 1600.0, 320.0))
                value *= gate * math.exp(-5.0 * t / duration)
            elif name == "blue":
                # A rounded rising pulse with a quiet fifth, for a tightening link.
                value = (0.70 * chirp(t, duration, 190.0, 430.0)
                         + 0.25 * chirp(t, duration, 285.0, 645.0)
                         + 0.10 * filtered_noise)
                value *= gate * math.exp(-3.2 * t / duration)
            elif name == "gold":
                # Unequal partial decay produces a bright, restrained struck bell.
                value = (0.62 * math.sin(TAU * 760.0 * t) * math.exp(-6.0 * t)
                         + 0.25 * math.sin(TAU * 1138.0 * t) * math.exp(-12.0 * t)
                         + 0.10 * math.sin(TAU * 1804.0 * t) * math.exp(-20.0 * t))
                value *= gate
            elif name == "gold_place":
                # A light, brief setting click: higher and quieter than impact.
                # It confirms placement without suggesting that an enemy was hit.
                value = (0.64 * math.sin(TAU * 1840.0 * t) * math.exp(-38.0 * t)
                         + 0.22 * math.sin(TAU * 2760.0 * t) * math.exp(-56.0 * t)
                         + 0.10 * (noise - filtered_noise) * math.exp(-85.0 * t))
                value *= gate
            elif name == "gold_launch":
                # A soft-edged rush with no struck bell or impact transient.
                # The rising then falling air envelope conveys forward movement.
                rush = math.sin(math.pi * t / duration) ** 1.5
                value = (1.1 * filtered_noise
                         + 0.18 * (noise - filtered_noise)
                         + 0.10 * chirp(t, duration, 620.0, 180.0))
                value *= envelope(t, duration, 0.025, 0.06) * rush
            elif name == "switch":
                # Short cloth-like air, kept distinct from the damage cue.
                value = (0.75 * filtered_noise
                         + 0.18 * chirp(t, duration, 280.0, 720.0))
                value *= gate * math.sin(math.pi * t / duration)
            elif name == "hurt":
                value = (0.8 * chirp(t, duration, 140.0, 48.0)
                         + 0.25 * filtered_noise)
                value *= gate * math.exp(-4.5 * t / duration)
            elif name == "buy":
                # Three original ascending tones; no sampled or quoted melody.
                value = 0.0
                for start, hz in ((0.0, 660.0), (0.11, 825.0), (0.22, 990.0)):
                    age = t - start
                    if age >= 0.0:
                        onset = min(age / 0.004, 1.0)
                        value += onset * math.exp(-11.0 * age) * (
                            0.65 * math.sin(TAU * hz * age)
                            + 0.12 * math.sin(TAU * hz * 2.0 * age)
                        )
                value *= gate
        samples.append(value)

    peak = max(abs(value) for value in samples) or 1.0
    ceiling = {"ambience": 0.55, "gold_place": 0.32, "gold_launch": 0.55}.get(name, 0.78)
    gain = ceiling / peak
    pcm = bytearray()
    for value in samples:
        pcm.extend(struct.pack("<h", round(value * gain * 32767)))
    output = io.BytesIO()
    with wave.open(output, "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(SAMPLE_RATE)
        stream.writeframes(pcm)
    return output.getvalue()


def generate_audio() -> None:
    for name in DURATIONS:
        data = synthesize(name)
        destination = PROJECT_ROOT / "game/assets/audio" / f"{name}.wav"
        atomic_write(destination, data)
        print(f"audio: {destination.relative_to(PROJECT_ROOT)} ({len(data)} bytes)")


def font_text_sources() -> list[Path]:
    """Collect the GDD, runtime scripts and project READMEs, without build caches."""
    sources = {PROJECT_ROOT / "GDD.md"}
    for extension in ("*.gd", "*.cs"):
        sources.update((PROJECT_ROOT / "game/scripts").rglob(extension))
    for path in PROJECT_ROOT.rglob("*.md"):
        if path.name.lower().startswith("readme") and not any(
            part.startswith(".") for part in path.relative_to(PROJECT_ROOT).parts
        ):
            sources.add(path)
    return sorted(sources)


def is_cjk(codepoint: int) -> bool:
    return (0x3400 <= codepoint <= 0x4DBF or 0x4E00 <= codepoint <= 0x9FFF
            or 0xF900 <= codepoint <= 0xFAFF or 0x20000 <= codepoint <= 0x323AF)


def generate_font(source: Path, license_path: Path) -> None:
    try:
        from fontTools import subset
        from fontTools.ttLib import TTFont
    except ImportError as error:
        raise RuntimeError("Font generation requires fontTools (tested with 4.61.1).") from error
    if not source.is_file():
        raise RuntimeError(f"Noto source font does not exist: {source}")
    if not license_path.is_file():
        raise RuntimeError(f"Original Noto copyright/license file does not exist: {license_path}")
    license_data = license_path.read_bytes()
    if b"SIL OPEN FONT LICENSE" not in license_data:
        raise RuntimeError("The font license file must include the original SIL OFL text.")

    paths = font_text_sources()
    text = "".join(path.read_text(encoding="utf-8") for path in paths)
    requested = set(range(0x20, 0x7F))
    requested.update(ord(character) for character in text if character.isprintable())
    # Include the UI's common punctuation even before a future string uses it.
    requested.update(map(ord, "\u00a0·×—–→←↑↓…•％"))

    with TTFont(source, fontNumber=2, recalcTimestamp=False) as font:
        family = font["name"].getDebugName(1) or ""
        if "Noto Sans CJK SC" not in family:
            raise RuntimeError(f"Expected Noto Sans CJK SC face 2, found {family!r}.")
        available = set(font.getBestCmap())
        unsupported = requested - available
        missing_cjk = sorted(value for value in unsupported if is_cjk(value))
        if missing_cjk:
            missing = ", ".join(f"U+{value:04X}" for value in missing_cjk)
            raise RuntimeError(f"Source font does not cover required Chinese characters: {missing}")
        included = sorted(requested & available)
        options = subset.Options()
        options.recalc_timestamp = False
        options.name_IDs = ["*"]
        options.name_languages = ["*"]
        options.name_legacy = True
        options.notdef_glyph = True
        options.notdef_outline = True
        options.recommended_glyphs = True
        subsetter = subset.Subsetter(options=options)
        subsetter.populate(unicodes=included)
        subsetter.subset(font)

        # Give the modified subset its own family while preserving copyright,
        # trademark and license records from the source face.
        names = {
            1: "Witches Feast UI", 2: "Regular", 3: "WitchesFeastUI-Regular-1",
            4: "Witches Feast UI Regular", 6: "WitchesFeastUI-Regular",
            16: "Witches Feast UI", 17: "Regular",
        }
        for record in font["name"].names:
            if record.nameID in names:
                record.string = names[record.nameID].encode(record.getEncoding())
        if "CFF " in font:
            cff = font["CFF "].cff
            cff.fontNames = ["WitchesFeastUI-Regular"]
            cff.topDictIndex[0].FamilyName = "Witches Feast UI"
            cff.topDictIndex[0].FullName = "Witches Feast UI Regular"
        output = io.BytesIO()
        font.save(output, reorderTables=True)

    data = output.getvalue()
    with TTFont(io.BytesIO(data), recalcTimestamp=False) as result:
        missing = set(included) - set(result.getBestCmap())
        if missing:
            raise RuntimeError(f"Generated font lost {len(missing)} requested characters.")
    directory = PROJECT_ROOT / "game/assets/fonts"
    atomic_write(directory / "ui.ttf", data)
    atomic_write(directory / "LICENSE.txt", license_data)
    print(f"font: game/assets/fonts/ui.ttf ({len(data)} bytes, {len(included)} codepoints, "
          f"{len(paths)} source files)")
    print("license: copied the original Noto copyright notice to game/assets/fonts/LICENSE.txt")
    if unsupported:
        codes = ", ".join(f"U+{value:04X}" for value in sorted(unsupported))
        print(f"note: non-CJK characters absent from the source font were omitted: {codes}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--audio", action="store_true", help="regenerate the seven WAV files")
    parser.add_argument("--font", action="store_true", help="regenerate the UI font subset and license")
    parser.add_argument("--font-source", type=Path, default=FONT_SOURCE,
                        help="Noto Sans CJK Regular collection (face 2: Simplified Chinese)")
    parser.add_argument("--font-license", type=Path, default=FONT_LICENSE,
                        help="original copyright/OFL notice belonging to the source font")
    args = parser.parse_args()
    default_both = not (args.audio or args.font)
    try:
        if args.font or default_both:
            generate_font(args.font_source, args.font_license)
        if args.audio or default_both:
            generate_audio()
    except (OSError, RuntimeError, ValueError) as error:
        parser.exit(1, f"asset generation failed: {error}\n")


if __name__ == "__main__":
    main()
