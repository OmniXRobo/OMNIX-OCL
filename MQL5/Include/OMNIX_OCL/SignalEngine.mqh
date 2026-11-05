//+------------------------------------------------------------------+
//| SignalEngine.mqh - decides WHETHER and WHERE to arm the bracket.   |
//| Filters are optional; the default is a symmetric tick-driven       |
//| straddle with spread/volatility sanity checks.                     |
//+------------------------------------------------------------------+
#ifndef OMNIX_OCL_SIGNAL_MQH
#define OMNIX_OCL_SIGNAL_MQH

#include "Common.mqh"
#include "MarketData.mqh"

struct SOCLSignalConfig
  {
   ENUM_OCL_DIST_MODE dist_mode;
   double            offset_fixed;       // $ from Ask (buy) / Bid (sell)
   double            offset_spread_k;    // DIST_SPREAD_SCALED: offset = fixed + k*spread
   double            offset_atr_k;       // DIST_ATR: offset = k*ATR(M1)
   double            offset_range_k;     // DIST_TICK_RANGE: offset = k*range(window)
   int               range_window_ms;
   double            offset_min,offset_max;
   double            sl_fixed;           // initial SL distance ($)
   double            sl_atr_k;           // >0: SL = max(sl_fixed, k*ATR)
   ENUM_OCL_ARM_SIDES arm_sides;
   int               momentum_window_ms;
   double            momentum_min;       // $ move over the window to call a direction
   bool              use_atr_filter;
   double            atr_min,atr_max;    // ATR(M1) band in $
   bool              block_extreme_regime;
   bool              use_rsi_filter;
   double            rsi_low,rsi_high;   // skip arming when RSI outside [low,high]
   bool              use_adx_filter;
   double            adx_min;
   bool              use_spike_filter;   // skip / withdraw the bracket while price is spiking
   int               spike_window_ms;
   double            spike_max;          // $ |mid change| over the window
   ENUM_OCL_REARM_MODE rearm_mode;
   int               rearm_cooldown_s;   // minimum seconds after a close (all modes)
   double            rearm_spread_k;     // REARM_SPREAD: spread <= k * average
   double            rearm_range_min;    // REARM_VOLATILITY: range(window) >= this
   double            rearm_range_max;    //                   and <= this (0 = no cap)
  };

struct SOCLSignal
  {
   bool              arm_buy;
   bool              arm_sell;
   double            buy_offset;
   double            sell_offset;
   double            sl_dist;
   string            reason;
  };

class CSignalEngine
  {
private:
   SOCLSignalConfig  c;
   CMarketData      *md;

public:
   void              Init(const SOCLSignalConfig &cfg,CMarketData *market) { c=cfg; md=market; }

   double            Offset(void) const
     {
      double o=c.offset_fixed;
      switch(c.dist_mode)
        {
         case DIST_SPREAD_SCALED: o=c.offset_fixed+c.offset_spread_k*md.spread; break;
         case DIST_ATR:           o=c.offset_atr_k*md.AtrM1(); break;
         case DIST_TICK_RANGE:    o=c.offset_range_k*md.RangeMs(c.range_window_ms); break;
         default: break;
        }
      if(c.offset_min>0) o=MathMax(o,c.offset_min);
      if(c.offset_max>0) o=MathMin(o,c.offset_max);
      return o;
     }

   double            StopDistance(void) const
     {
      double s=c.sl_fixed;
      if(c.sl_atr_k>0 && md.AtrM1()>0) s=MathMax(s,c.sl_atr_k*md.AtrM1());
      return s;
     }

   //--- re-arm policy after a close; why explains waiting or arming
   bool              RearmAllowed(const datetime last_close,string &why) const
     {
      int since=(last_close>0)?(int)(TimeCurrent()-last_close):100000;
      if(since<c.rearm_cooldown_s){ why=StringFormat("cooldown %d/%ds",since,c.rearm_cooldown_s); return false; }
      ENUM_OCL_REARM_MODE m=c.rearm_mode;
      if(m==REARM_ADAPTIVE)
        {
         switch(md.Regime())
           {
            case REGIME_QUIET:   m=REARM_VOLATILITY; break;
            case REGIME_NORMAL:  m=REARM_SPREAD; break;
            case REGIME_ACTIVE:  m=REARM_MOMENTUM; break;
            default: why="adaptive: regime "+OCL_RegimeName(md.Regime())+" -> wait"; return false;
           }
        }
      switch(m)
        {
         case REARM_IMMEDIATE: why="immediate"; return true;
         case REARM_SPREAD:
            if(md.SpreadAvg()>0 && md.spread>c.rearm_spread_k*md.SpreadAvg())
              { why=StringFormat("spread %.2f > %.1fx avg",md.spread,c.rearm_spread_k); return false; }
            why="spread ok"; return true;
         case REARM_VOLATILITY:
           {
            double r=md.RangeMs(c.range_window_ms);
            if(r<c.rearm_range_min){ why=StringFormat("range %.2f < %.2f",r,c.rearm_range_min); return false; }
            if(c.rearm_range_max>0 && r>c.rearm_range_max){ why=StringFormat("range %.2f > %.2f",r,c.rearm_range_max); return false; }
            why=StringFormat("range %.2f ok",r); return true;
           }
         case REARM_MOMENTUM:
           {
            double ch=md.ChangeMs(c.momentum_window_ms);
            if(MathAbs(ch)<c.momentum_min){ why=StringFormat("momentum %.2f < %.2f",ch,c.momentum_min); return false; }
            why=StringFormat("momentum %.2f",ch); return true;
           }
         default: break;
        }
      why="unknown mode"; return false;
     }

   //--- full decision for this tick
   void              Evaluate(SOCLSignal &s) const
     {
      s.arm_buy=true; s.arm_sell=true; s.reason="";
      s.buy_offset=Offset(); s.sell_offset=s.buy_offset; s.sl_dist=StopDistance();
      if(c.block_extreme_regime && md.Regime()==REGIME_EXTREME)
        { s.arm_buy=s.arm_sell=false; s.reason="regime extreme"; return; }
      if(c.use_atr_filter)
        {
         double a=md.AtrM1();
         if(a<c.atr_min || (c.atr_max>0 && a>c.atr_max))
           { s.arm_buy=s.arm_sell=false; s.reason=StringFormat("ATR %.2f outside [%.2f,%.2f]",a,c.atr_min,c.atr_max); return; }
        }
      if(c.use_rsi_filter)
        {
         double r=md.RsiM1();
         if(r!=EMPTY_VALUE && (r<c.rsi_low || r>c.rsi_high))
           { s.arm_buy=s.arm_sell=false; s.reason=StringFormat("RSI %.1f outside band",r); return; }
        }
      if(c.use_adx_filter)
        {
         double x=md.AdxM5();
         if(x!=EMPTY_VALUE && x<c.adx_min){ s.arm_buy=s.arm_sell=false; s.reason=StringFormat("ADX %.1f < %.1f",x,c.adx_min); return; }
        }
      if(c.use_spike_filter && c.spike_max>0)
        {
         double sp=MathAbs(md.ChangeMs(c.spike_window_ms));
         if(sp>c.spike_max){ s.arm_buy=s.arm_sell=false; s.reason=StringFormat("spike %.2f > %.2f in %dms",sp,c.spike_max,c.spike_window_ms); return; }
        }
      if(c.arm_sides==ARM_WITH_MOMENTUM)
        {
         double ch=md.ChangeMs(c.momentum_window_ms);
         if(ch>=c.momentum_min) s.arm_sell=false;
         else if(ch<=-c.momentum_min) s.arm_buy=false;
         else { s.arm_buy=s.arm_sell=false; s.reason="no momentum"; return; }
        }
      else if(c.arm_sides==ARM_WITH_HTF_BIAS)
        {
         int b=md.BiasH1();
         if(b>0) s.arm_sell=false; else if(b<0) s.arm_buy=false;
         else { s.arm_buy=s.arm_sell=false; s.reason="no H1 bias"; return; }
        }
      s.reason=StringFormat("offset %.2f sl %.2f regime %s",s.buy_offset,s.sl_dist,OCL_RegimeName(md.Regime()));
     }
  };

#endif
