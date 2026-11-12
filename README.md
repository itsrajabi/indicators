# Spike Detectors for MetaTrader 5

Two MQL5 indicators for detecting directional price spikes.

## Indicators

### 1. CleanSpike_3Levels

A three-level classification of directional spikes.

- Level 1: a candle or short sequence whose range is much larger than the recent average.
- Level 2: a Level 1 spike whose aggregate bodies dominate its aggregate range and whose opposing wicks are small.
- Level 3: a Level 2 spike that also aligns with the direction and body strength of a higher timeframe.

Each level is plotted as a separate arrow class (gray dot, blue diamond, gold arrow). Signals are placed once per spike on the completing bar and do not repaint after that bar closes.

Note: this indicator was an early experiment. In testing, Level 1 signals were too frequent to be useful and Level 3 signals almost never fired. It is kept for reference only. For practical use, see RealSpikeDetector.

### 2. RealSpikeDetector

A single, stricter definition of a real spike, replacing the three-level framework.

A real spike is:

- A run of at least four consecutive same-direction candles, with no doji or counter-candle inside the run.
- Structurally clean: sum of bodies is at least 60 percent of the sum of ranges, and the sum of opposing wicks stays below 25 percent.
- Large relative to recent activity: the average range of the run exceeds the average range of the preceding 100 candles.

The signal is plotted once per run, on the candle that completes the fourth consecutive move, and does not repaint after that candle closes. Bull spikes plot a green up arrow; bear spikes plot a red down arrow.

## Installation

1. Open MetaTrader 5 and press F4 to open MetaEditor.
2. In MetaEditor, go to File > Open Data Folder.
3. Navigate to MQL5/Indicators/.
4. Copy the spike-detectors folder into MQL5/Indicators/.
5. Back in MetaEditor, open each .mq5 file and press F7 to compile.
6. In MetaTrader 5, open the Navigator panel (Ctrl+N), expand Indicators > Custom > spike-detectors, and drag an indicator onto a chart.

Compiled .ex5 files are also provided, in which case step 5 can be skipped.

## Inputs

### RealSpikeDetector

| Input | Default | Description |
|---|---|---|
| InpMinRunLength | 4 | Minimum consecutive same-direction candles |
| InpLookback | 100 | Bars used to compute the prior average range |
| InpMinBodyRatio | 0.60 | Minimum sum of bodies over sum of ranges |
| InpMaxWickRatio | 0.25 | Maximum sum of opposing wicks over sum of ranges |
| InpSizeMultiplier | 1.00 | Spike average range must exceed this multiple of prior average |
| InpSkipFormingBar | true | Do not plot on the current forming bar |

### CleanSpike_3Levels

| Input | Default | Description |
|---|---|---|
| InpMinRunLength | 4 | Minimum consecutive same-direction candles |
| InpLookback | 20 | Bars used to compute the average range |
| InpSpikeMultiplier | 0.80 | Net move must exceed this multiple of run length times average range |
| InpMinCandleBodyRatio | 0.25 | Minimum body size of each candle relative to average range |
| InpMinBodyRatio | 0.60 | Minimum sum of bodies over sum of ranges |
| InpMaxWickRatio | 0.25 | Maximum sum of opposing wicks over sum of ranges |
| InpHTF | H1 | Higher timeframe for Level 3 confirmation |
| InpHTFMinBodyRatio | 0.50 | Minimum body ratio of the higher timeframe candle |
| InpSkipFormingBar | true | Do not plot on the current forming bar |

## Notes

- Both indicators are non-repainting once the confirming bar has closed, provided InpSkipFormingBar is true.
- The first InpLookback bars of a chart produce no signals, because the prior average range is not yet available.
- Thresholds are deliberately conservative. Lowering InpSizeMultiplier or InpMinBodyRatio will produce more signals, but the population becomes less selective.

## Status

RealSpikeDetector is the active indicator. CleanSpike_3Levels is retained for reference and is not recommended for live use.

## License

MIT
