//+------------------------------------------------------------------+
//|                                          CleanSpike_3Levels.mq5   |
//+------------------------------------------------------------------+
#property copyright "Clean Spike Framework"
#property version   "1.10"
#property description "Level 1: sustained run of same-direction candles."
#property description "Level 2: that run is structurally clean (large bodies, small opposing wicks)."
#property description "Level 3: that clean run aligns with a strong HTF candle."

#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrGray
#property indicator_width1  1
#property indicator_label1  "Level 1 Run Spike"

#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDodgerBlue
#property indicator_width2  2
#property indicator_label2  "Level 2 Clean Run"

#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrGold
#property indicator_width3  3
#property indicator_label3  "Level 3 A+ Run"

//--- Inputs
input group "--- Level 1: Sustained Run Spike ---"
input int    InpMinRunLength       = 4;      // Minimum consecutive same-direction candles
input int    InpLookback           = 20;     // Bars used to compute average candle range
input double InpSpikeMultiplier    = 0.80;   // Net move must be >= this × (RunLength × avgRange)
input double InpMinCandleBodyRatio = 0.25;   // Each candle body must be >= this × avgRange

input group "--- Level 2: Clean Structure ---"
input double InpMinBodyRatio       = 0.60;   // Sum(bodies) / Sum(ranges) across the run
input double InpMaxWickRatio       = 0.25;   // Sum(opposing wicks) / Sum(ranges) across the run

input group "--- Level 3: Timeframe Confluence ---"
input ENUM_TIMEFRAMES InpHTF       = PERIOD_H1;  // Higher timeframe to align with
input double InpHTFMinBodyRatio    = 0.50;       // HTF body / HTF range

input group "--- Behaviour ---"
input bool   InpSkipFormingBar     = true;   // Do not plot on the current forming bar (non-repainting)

//--- Buffers
double BufferLevel1[];
double BufferLevel2[];
double BufferLevel3[];

#define ARROW_LEVEL1  159   // small dot
#define ARROW_LEVEL2  116   // diamond
#define ARROW_LEVEL3  233   // large arrow

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferLevel1, INDICATOR_DATA);
   SetIndexBuffer(1, BufferLevel2, INDICATOR_DATA);
   SetIndexBuffer(2, BufferLevel3, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, ARROW_LEVEL1);
   PlotIndexSetInteger(1, PLOT_ARROW, ARROW_LEVEL2);
   PlotIndexSetInteger(2, PLOT_ARROW, ARROW_LEVEL3);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 10);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 15);
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, 20);

   if(InpMinRunLength < 2)                     { Print("InpMinRunLength must be >= 2."); return INIT_PARAMETERS_INCORRECT; }
   if(InpLookback < 2)                         { Print("InpLookback must be >= 2.");     return INIT_PARAMETERS_INCORRECT; }
   if(InpSpikeMultiplier <= 0.0)               { Print("InpSpikeMultiplier must be > 0."); return INIT_PARAMETERS_INCORRECT; }
   if(InpMinBodyRatio < 0.0 || InpMinBodyRatio > 1.0)     { Print("InpMinBodyRatio must be 0..1."); return INIT_PARAMETERS_INCORRECT; }
   if(InpMaxWickRatio < 0.0 || InpMaxWickRatio > 1.0)     { Print("InpMaxWickRatio must be 0..1."); return INIT_PARAMETERS_INCORRECT; }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Direction of a single candle: 1 bull, -1 bear, 0 doji             |
//+------------------------------------------------------------------+
int CandleDir(const double &open[], const double &close[], int bar)
{
   if(close[bar] > open[bar]) return 1;
   if(close[bar] < open[bar]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Length of the same-direction run ending at 'bar', capped at 'cap'|
//+------------------------------------------------------------------+
int RunLengthCapped(const double &open[], const double &close[], int bar, int cap)
{
   if(bar < 0) return 0;
   int dir = CandleDir(open, close, bar);
   if(dir == 0) return 0;
   int len = 1;
   for(int k = bar - 1; k >= 0 && len < cap; k--)
   {
      int dk = CandleDir(open, close, k);
      if(dk != dir) break;
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
      ArrayInitialize(BufferLevel1, EMPTY_VALUE);
      ArrayInitialize(BufferLevel2, EMPTY_VALUE);
      ArrayInitialize(BufferLevel3, EMPTY_VALUE);
   }
   else
   {
      start = prev_calculated - 1;
      if(start < warmup) start = warmup;
   }

   for(int i = start; i < rates_total; i++)
   {
      BufferLevel1[i] = EMPTY_VALUE;
      BufferLevel2[i] = EMPTY_VALUE;
      BufferLevel3[i] = EMPTY_VALUE;

      if(InpSkipFormingBar && i == rates_total - 1)
         continue;

      const int N = InpMinRunLength;

      //--- Confirmation: run ending at i has length exactly N
      int rl_i = RunLengthCapped(open, close, i, N);
      if(rl_i != N) continue;

      int rl_prev = (i > 0) ? RunLengthCapped(open, close, i - 1, N) : 0;
      if(rl_prev != N - 1) continue;      // already signalled earlier in a longer run

      const int runStart = i - N + 1;
      if(runStart - InpLookback < 0) continue;

      const bool isBullish = (CandleDir(open, close, i) == 1);

      //--- Verify every candle in the run is same-direction
      bool uniform = true;
      for(int k = runStart; k <= i; k++)
      {
         int dk = CandleDir(open, close, k);
         if((isBullish && dk != 1) || (!isBullish && dk != -1)) { uniform = false; break; }
      }
      if(!uniform) continue;

      //--- Average candle range over the lookback immediately before the run
      double avgRange = 0.0;
      for(int k = runStart - InpLookback; k < runStart; k++)
         avgRange += (high[k] - low[k]);
      avgRange /= InpLookback;
      if(avgRange <= 0.0) continue;

      //--- Aggregate statistics of the run
      double sumRanges = 0.0, sumBodies = 0.0, sumOpposingWicks = 0.0;
      double runLowestLow = low[runStart];
      double runHighestHigh = high[runStart];
      bool allCandlesLargeEnough = true;

      for(int k = runStart; k <= i; k++)
      {
         const double r           = high[k] - low[k];
         const double body        = MathAbs(close[k] - open[k]);
         const double lowerWick   = MathMin(open[k], close[k]) - low[k];
         const double upperWick   = high[k] - MathMax(open[k], close[k]);

         sumRanges        += r;
         sumBodies        += body;
         sumOpposingWicks += (isBullish ? lowerWick : upperWick);

         if(low[k]  < runLowestLow)   runLowestLow   = low[k];
         if(high[k] > runHighestHigh) runHighestHigh = high[k];

         if(InpMinCandleBodyRatio > 0.0 && body < InpMinCandleBodyRatio * avgRange)
            allCandlesLargeEnough = false;
      }

      if(!allCandlesLargeEnough) continue;

      //--- Net directional move of the run
      const double netMove = isBullish ? (close[i] - open[runStart])
                                       : (open[runStart] - close[i]);
      if(netMove <= 0.0) continue;

      //--- LEVEL 1
      const double requiredMove = InpSpikeMultiplier * (double)N * avgRange;
      if(netMove < requiredMove) continue;

      //--- LEVEL 2
      const double bodyRatio         = (sumRanges > 0.0) ? (sumBodies / sumRanges) : 0.0;
      const double opposingWickRatio = (sumRanges > 0.0) ? (sumOpposingWicks / sumRanges) : 1.0;
      const bool isClean = (bodyRatio >= InpMinBodyRatio) && (opposingWickRatio <= InpMaxWickRatio);

      //--- LEVEL 3 (last closed HTF bar must agree in direction and have a real body)
      bool isHTFConfluent = false;
      MqlRates htfRates[];
      ArraySetAsSeries(htfRates, true);
      int htfCopied = CopyRates(_Symbol, InpHTF, 0, 3, htfRates);
      if(htfCopied >= 3)
      {
         const double htfOpen  = htfRates[1].open;
         const double htfClose = htfRates[1].close;
         const double htfHigh  = htfRates[1].high;
         const double htfLow   = htfRates[1].low;
         const double htfRange = htfHigh - htfLow;

         if(htfRange > 0.0)
         {
            const double htfBodyRatio = MathAbs(htfClose - htfOpen) / htfRange;
            const bool htfBull = (htfClose > htfOpen);
            const bool htfBear = (htfClose < htfOpen);

            if(isBullish && htfBull && htfBodyRatio >= InpHTFMinBodyRatio) isHTFConfluent = true;
            if(!isBullish && htfBear && htfBodyRatio >= InpHTFMinBodyRatio) isHTFConfluent = true;
         }
      }

      //--- Plot only the highest achieved level
      const double plotPrice = isBullish ? runLowestLow : runHighestHigh;

      if(isClean && isHTFConfluent) BufferLevel3[i] = plotPrice;
      else if(isClean)              BufferLevel2[i] = plotPrice;
      else                          BufferLevel1[i] = plotPrice;
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
