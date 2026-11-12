//+------------------------------------------------------------------+
//|                                          CleanSpike3Levels.mq5    |
//|                        Three-Level Clean Spike Indicator for MT5  |
//+------------------------------------------------------------------+
#property copyright "Clean Spike Framework"
#property version   "1.00"
#property description "Identifies Level 1 (basic spike), Level 2 (clean body/shadow spike),"
#property description "and Level 3 (timeframe-confluent spike)."

//--- Plot definitions
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

//--- Level 1: Basic spike (small dot)
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrGray
#property indicator_width1  1
#property indicator_label1  "Level 1 Spike"

//--- Level 2: Clean structural spike (diamond)
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDodgerBlue
#property indicator_width2  2
#property indicator_label2  "Level 2 Clean Spike"

//--- Level 3: Timeframe-confluent spike (large arrow)
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrGold
#property indicator_width3  3
#property indicator_label3  "Level 3 A+ Spike"

//+------------------------------------------------------------------+
//| Input parameters                                                  |
//+------------------------------------------------------------------+
input group "--- Level 1: Basic Spike ---"
input int    InpLookback          = 20;      // Lookback bars for average range
input double InpSpikeMultiplier   = 1.8;     // Range must be >= this × average range

input group "--- Level 2: Clean Structure ---"
input double InpMinBodyRatio      = 0.60;    // Body must be >= this fraction of total range
input double InpMaxWickRatio      = 0.25;    // Each wick must be <= this fraction of total range

input group "--- Level 3: Timeframe Confluence ---"
input ENUM_TIMEFRAMES InpHTF      = PERIOD_H1;  // Higher timeframe to check
input double InpHTFMinBodyRatio   = 0.50;    // HTF candle body must be >= this fraction of its range

//+------------------------------------------------------------------+
//| Indicator buffers                                                 |
//+------------------------------------------------------------------+
double BufferLevel1[];
double BufferLevel2[];
double BufferLevel3[];

//--- Arrow codes (Wingdings characters)
#define ARROW_LEVEL1  159   // small dot
#define ARROW_LEVEL2  116   // diamond
#define ARROW_LEVEL3  233   // large up arrow

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Map buffers
   SetIndexBuffer(0, BufferLevel1, INDICATOR_DATA);
   SetIndexBuffer(1, BufferLevel2, INDICATOR_DATA);
   SetIndexBuffer(2, BufferLevel3, INDICATOR_DATA);

   //--- Set arrow codes
   PlotIndexSetInteger(0, PLOT_ARROW, ARROW_LEVEL1);
   PlotIndexSetInteger(1, PLOT_ARROW, ARROW_LEVEL2);
   PlotIndexSetInteger(2, PLOT_ARROW, ARROW_LEVEL3);

   //--- Set empty values so bars without signals are not drawn
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Optional: arrow vertical shift in pixels
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 10);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 15);
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, 20);

   //--- Validate inputs
   if(InpLookback < 2)
   {
      Print("InpLookback must be at least 2.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpSpikeMultiplier <= 0.0)
   {
      Print("InpSpikeMultiplier must be greater than 0.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMinBodyRatio < 0.0 || InpMinBodyRatio > 1.0)
   {
      Print("InpMinBodyRatio must be between 0 and 1.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMaxWickRatio < 0.0 || InpMaxWickRatio > 1.0)
   {
      Print("InpMaxWickRatio must be between 0 and 1.");
      return INIT_PARAMETERS_INCORRECT;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
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
   //--- Need enough bars for the lookback average
   if(rates_total < InpLookback + 2)
      return 0;

   //--- Determine calculation start
   int start;
   if(prev_calculated == 0)
   {
      start = InpLookback;   // skip the warm-up period
      //--- Initialize all buffers to EMPTY_VALUE
      ArrayInitialize(BufferLevel1, EMPTY_VALUE);
      ArrayInitialize(BufferLevel2, EMPTY_VALUE);
      ArrayInitialize(BufferLevel3, EMPTY_VALUE);
   }
   else
   {
      start = prev_calculated - 1;   // recalculate the last bar for updates
      if(start < InpLookback)
         start = InpLookback;
   }

   //--- Main loop
   for(int i = start; i < rates_total; i++)
   {
      //--- Reset buffer values for this bar
      BufferLevel1[i] = EMPTY_VALUE;
      BufferLevel2[i] = EMPTY_VALUE;
      BufferLevel3[i] = EMPTY_VALUE;

      //--- Candle geometry
      double range = high[i] - low[i];
      if(range <= 0.0)
         continue;   // skip flat bars

      double bodyHigh = MathMax(open[i], close[i]);
      double bodyLow  = MathMin(open[i], close[i]);
      double bodySize = bodyHigh - bodyLow;
      double upperWick = high[i] - bodyHigh;
      double lowerWick = bodyLow - low[i];

      //--- Determine candle direction
      bool isBullish = (close[i] > open[i]);
      bool isBearish = (close[i] < open[i]);
      if(!isBullish && !isBearish)
         continue;   // skip doji-like bars with zero body

      //--- Calculate average range over the lookback period
      double avgRange = 0.0;
      for(int j = i - InpLookback; j < i; j++)
         avgRange += (high[j] - low[j]);
      avgRange /= InpLookback;
      if(avgRange <= 0.0)
         continue;

      //--- LEVEL 1 CHECK: Is this a spike?
      bool isSpike = (range >= InpSpikeMultiplier * avgRange);
      if(!isSpike)
         continue;

      //--- Level 1 signal
      BufferLevel1[i] = (isBullish) ? low[i] : high[i];

      //--- LEVEL 2 CHECK: Is the spike clean?
      double bodyRatio = bodySize / range;
      double upperWickRatio = upperWick / range;
      double lowerWickRatio = lowerWick / range;

      bool isCleanStructure = (bodyRatio >= InpMinBodyRatio) &&
                              (upperWickRatio <= InpMaxWickRatio) &&
                              (lowerWickRatio <= InpMaxWickRatio);
      if(!isCleanStructure)
         continue;

      //--- Level 2 signal
      BufferLevel2[i] = (isBullish) ? low[i] : high[i];

      //--- LEVEL 3 CHECK: Timeframe confluence
      MqlRates htfRates[];
      int htfCopied = CopyRates(_Symbol, InpHTF, 0, 2, htfRates);
      if(htfCopied < 2)
         continue;   // HTF data not ready

      //--- Use the most recent completed HTF bar (index 1 in the returned array)
      //--- CopyRates with start_pos=0, count=2 returns bars ordered oldest -> newest.
      //--- Index 1 is the most recently completed bar on the HTF.
      double htfOpen  = htfRates[1].open;
      double htfClose = htfRates[1].close;
      double htfHigh  = htfRates[1].high;
      double htfLow   = htfRates[1].low;
      double htfRange = htfHigh - htfLow;

      if(htfRange <= 0.0)
         continue;

      double htfBodySize = MathAbs(htfClose - htfOpen);
      double htfBodyRatio = htfBodySize / htfRange;
      bool htfIsBullish = (htfClose > htfOpen);
      bool htfIsBearish = (htfClose < htfOpen);

      //--- HTF must be moving in the same direction and have a reasonably sized body
      bool htfAligned = false;
      if(isBullish && htfIsBullish && htfBodyRatio >= InpHTFMinBodyRatio)
         htfAligned = true;
      if(isBearish && htfIsBearish && htfBodyRatio >= InpHTFMinBodyRatio)
         htfAligned = true;

      if(!htfAligned)
         continue;

      //--- Level 3 signal (A+ setup)
      BufferLevel3[i] = (isBullish) ? low[i] : high[i];
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
