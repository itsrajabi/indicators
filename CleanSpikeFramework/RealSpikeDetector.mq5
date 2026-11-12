//+------------------------------------------------------------------+
//|                                            RealSpikeDetector.mq5 |
//|                                  Real Spike Detector for MT5     |
//+------------------------------------------------------------------+
#property copyright "Real Spike Detector"
#property version   "1.00"
#property description "Detects real spikes: a clean run of same-direction candles"
#property description "whose average range beats the recent average range."

#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2
#property indicator_label1  "Bull Spike"

#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2
#property indicator_label2  "Bear Spike"

//--- Inputs
input group "--- Run Definition ---"
input int    InpMinRunLength   = 4;      // Minimum consecutive same-direction candles
input int    InpLookback        = 100;    // Bars used to compute prior average range

input group "--- Structure Filter ---"
input double InpMinBodyRatio    = 0.60;   // Sum(bodies) / Sum(ranges) across the run
input double InpMaxWickRatio    = 0.25;   // Sum(opposing wicks) / Sum(ranges) across the run

input group "--- Size Filter ---"
input double InpSizeMultiplier  = 1.00;   // Spike avg range must exceed this × prior avg range

input group "--- Behaviour ---"
input bool   InpSkipFormingBar  = true;   // Do not plot on the current forming bar

//--- Buffers
double BufferBull[];
double BufferBear[];

#define ARROW_BULL 233
#define ARROW_BEAR 234

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferBull, INDICATOR_DATA);
   SetIndexBuffer(1, BufferBear, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, ARROW_BULL);
   PlotIndexSetInteger(1, PLOT_ARROW, ARROW_BEAR);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 15);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -15);

   if(InpMinRunLength < 2)              { Print("InpMinRunLength must be >= 2."); return INIT_PARAMETERS_INCORRECT; }
   if(InpLookback < 2)                  { Print("InpLookback must be >= 2.");     return INIT_PARAMETERS_INCORRECT; }
   if(InpMinBodyRatio < 0 || InpMinBodyRatio > 1) { Print("InpMinBodyRatio must be 0..1."); return INIT_PARAMETERS_INCORRECT; }
   if(InpMaxWickRatio < 0 || InpMaxWickRatio > 1) { Print("InpMaxWickRatio must be 0..1."); return INIT_PARAMETERS_INCORRECT; }
   if(InpSizeMultiplier < 0)            { Print("InpSizeMultiplier must be >= 0."); return INIT_PARAMETERS_INCORRECT; }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Direction of a single candle: 1 bull, -1 bear, 0 doji             |
//+------------------------------------------------------------------+
int CandleDir(const double &open[], const double &close[], int bar)
{
   if(close[bar] > open[bar]) return  1;
   if(close[bar] < open[bar]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Same-direction run length ending at 'bar', capped at 'cap'        |
//+------------------------------------------------------------------+
int RunLengthCapped(const double &open[], const double &close[], int bar, int cap)
{
   if(bar < 0) return 0;
   int dir = CandleDir(open, close, bar);
   if(dir == 0) return 0;
   int len = 1;
   for(int k = bar - 1; k >= 0 && len < cap; k--)
   {
      if(CandleDir(open, close, k) != dir) break;
      len++;
   }
   return len;
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   const int warmup = InpLookback + InpMinRunLength + 2;
   if(rates_total < warmup)
      return 0;

   int start;
   if(prev_calculated == 0)
   {
      start = warmup;
      ArrayInitialize(BufferBull, EMPTY_VALUE);
      ArrayInitialize(BufferBear, EMPTY_VALUE);
   }
   else
   {
      start = prev_calculated - 1;
      if(start < warmup) start = warmup;
   }

   for(int i = start; i < rates_total; i++)
   {
      BufferBull[i] = EMPTY_VALUE;
      BufferBear[i] = EMPTY_VALUE;

      if(InpSkipFormingBar && i == rates_total - 1)
         continue;

      const int N = InpMinRunLength;

      //--- Fire once per run, on the bar that completes the minimum length
      if(RunLengthCapped(open, close, i, N) != N) continue;
      if(i > 0 && RunLengthCapped(open, close, i - 1, N) != N - 1) continue;

      const int runStart = i - N + 1;
      if(runStart - InpLookback < 0) continue;

      const bool isBullish = (CandleDir(open, close, i) == 1);

      //--- Verify uniformity (no dojis or counter-candles inside the run)
      bool uniform = true;
      for(int k = runStart; k <= i; k++)
      {
         int dk = CandleDir(open, close, k);
         if((isBullish && dk != 1) || (!isBullish && dk != -1)) { uniform = false; break; }
      }
      if(!uniform) continue;

      //--- Aggregate run statistics
      double sumRanges = 0.0, sumBodies = 0.0, sumOpposingWicks = 0.0;
      double runLowestLow = low[runStart];
      double runHighestHigh = high[runStart];

      for(int k = runStart; k <= i; k++)
      {
         const double r         = high[k] - low[k];
         const double body      = MathAbs(close[k] - open[k]);
         const double lowerWick = MathMin(open[k], close[k]) - low[k];
         const double upperWick = high[k] - MathMax(open[k], close[k]);

         sumRanges        += r;
         sumBodies        += body;
         sumOpposingWicks += (isBullish ? lowerWick : upperWick);

         if(low[k]  < runLowestLow)   runLowestLow   = low[k];
         if(high[k] > runHighestHigh) runHighestHigh = high[k];
      }

      if(sumRanges <= 0.0) continue;

      //--- RULE: clean structure (aggregate)
      const double bodyRatio         = sumBodies        / sumRanges;
      const double opposingWickRatio = sumOpposingWicks / sumRanges;
      if(bodyRatio         < InpMinBodyRatio) continue;
      if(opposingWickRatio > InpMaxWickRatio) continue;

      //--- RULE: size filter (spike average vs prior average)
      double priorRangeSum = 0.0;
      for(int k = runStart - InpLookback; k < runStart; k++)
         priorRangeSum += (high[k] - low[k]);
      const double priorAvgRange = priorRangeSum / InpLookback;
      if(priorAvgRange <= 0.0) continue;

      const double spikeAvgRange = sumRanges / N;
      if(spikeAvgRange <= InpSizeMultiplier * priorAvgRange) continue;

      //--- All rules passed -> plot
      if(isBullish) BufferBull[i] = runLowestLow;
      else          BufferBear[i] = runHighestHigh;
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
