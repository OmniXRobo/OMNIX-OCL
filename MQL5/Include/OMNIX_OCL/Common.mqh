//+------------------------------------------------------------------+
//| Common.mqh - shared enums, constants and settings for OMNIX OCL    |
//+------------------------------------------------------------------+
#ifndef OMNIX_OCL_COMMON_MQH
#define OMNIX_OCL_COMMON_MQH

#include "OCLMath.mqh"

#define OCL_PRODUCT          "OMNIX OCL"
#define OCL_VERSION          "0.3.0"
#define OCL_ORDER_COMMENT    "OMNIX OCL"

// Live-money trading is disabled at compile time. The EA refuses to start on
// any account that is not a demo account (Strategy Tester is always allowed).
// Changing this requires an owner-approved code change, review and rebuild.
#define OCL_LIVE_TRADING_ALLOWED false

//--- Millisecond clock for throttles and timers. Live: wall clock. Strategy Tester: simulated
//    tick time, because a tester day passes in seconds of wall time and wall-clock throttles
//    would block almost every SL / pending modify there.
ulong OCL_NowMs(void)
  {
   if(MQLInfoInteger(MQL_TESTER))
     {
      MqlTick t;
      if(SymbolInfoTick(_Symbol,t) && t.time_msc>0) return (ulong)t.time_msc;
      return (ulong)TimeCurrent()*1000;
     }
   return GetTickCount64();
  }

enum ENUM_OCL_LOT_MODE      { LOT_FIXED=0, LOT_RISK=1, LOT_ADAPTIVE=2 };
enum ENUM_OCL_DIST_MODE     { DIST_FIXED=0, DIST_SPREAD_SCALED=1, DIST_ATR=2, DIST_TICK_RANGE=3 };
enum ENUM_OCL_PENDING_MODE  { PEND_STATIC=0, PEND_FOLLOW_MODIFY=1, PEND_FOLLOW_REPLACE=2 };
enum ENUM_OCL_OCO_MODE      { OCO_CANCEL_ON_FILL=0, OCO_CANCEL_ON_CLOSE=1, OCO_KEEP_OPPOSITE=2 };
enum ENUM_OCL_FOLLOW_DIR    { FOLLOW_TIGHTEN_ONLY=0, FOLLOW_BOTH_WAYS=1 };
enum ENUM_OCL_ARM_SIDES     { ARM_BOTH=0, ARM_WITH_MOMENTUM=1, ARM_WITH_HTF_BIAS=2 };
enum ENUM_OCL_REARM_MODE    { REARM_IMMEDIATE=0, REARM_SPREAD=1, REARM_VOLATILITY=2, REARM_MOMENTUM=3, REARM_ADAPTIVE=4 };
enum ENUM_OCL_EXIT_PROFILE  { EXIT_CUSTOM=0, EXIT_A_FIXED=1, EXIT_B_TRAIL=2, EXIT_C_BREAKEVEN=3,
                              EXIT_D_MICROPROFIT=4, EXIT_E_TIME=5, EXIT_F_ADAPTIVE=6 };
enum ENUM_OCL_TIME_EXIT     { TIMEEXIT_ALWAYS=0, TIMEEXIT_IF_NOT_PROFITABLE=1 };
enum ENUM_OCL_DST_RULE      { DST_NONE=0, DST_US=1, DST_EU=2 };
enum ENUM_OCL_NEWS_ACTION   { NEWS_BLOCK_NEW=0, NEWS_REDUCED_RISK=1, NEWS_MONITOR_ONLY=2 };
enum ENUM_OCL_REGIME        { REGIME_UNKNOWN=0, REGIME_QUIET=1, REGIME_NORMAL=2, REGIME_ACTIVE=3, REGIME_EXTREME=4 };

string OCL_RegimeName(const ENUM_OCL_REGIME r)
  {
   switch(r)
     {
      case REGIME_QUIET:   return "quiet";
      case REGIME_NORMAL:  return "normal";
      case REGIME_ACTIVE:  return "active";
      case REGIME_EXTREME: return "extreme";
     }
   return "unknown";
  }

//--- resolved exit configuration (after applying an exit profile)
struct SOCLExitConfig
  {
   bool              use_trailing;
   double            trail_activation;   // price units
   double            trail_distance;
   double            trail_step;
   bool              use_breakeven;
   double            be_trigger;
   double            be_offset;
   bool              use_microprofit;
   double            micro_profit_usd;   // net, per position
   bool              use_time_exit;
   int               max_hold_seconds;
   ENUM_OCL_TIME_EXIT time_exit_rule;
   bool              adaptive;           // variant F: volatility-scaled trail, momentum fade exit
   double            adaptive_trail_k;   // trail = k * short-term range
   double            adaptive_min_trail;
  };

//--- millisecond timestamp for logs (server time of the last tick when available)
long OCL_NowMsc(const string symbol)
  {
   MqlTick t;
   if(SymbolInfoTick(symbol,t) && t.time_msc>0) return (long)t.time_msc;
   return (long)TimeCurrent()*1000;
  }

string OCL_MscToString(const long msc)
  {
   return TimeToString((datetime)(msc/1000),TIME_DATE|TIME_SECONDS)+StringFormat(".%03d",(int)(msc%1000));
  }

#endif
