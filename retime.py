"""Write a separate subtitle file adjusted to two playback reference points."""
import sys
import pysubs2

source, destination, scale, offset = sys.argv[1:]
scale = float(scale)
offset_ms = 1000 * float(offset)
subtitles = pysubs2.load(source)
for event in subtitles:
    event.start = max(0, round(scale * event.start + offset_ms))
    event.end = max(event.start + 1, round(scale * event.end + offset_ms))
subtitles.save(destination)
