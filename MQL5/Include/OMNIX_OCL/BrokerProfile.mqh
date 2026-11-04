//+------------------------------------------------------------------+
//| BrokerProfile.mqh - gold symbol discovery and broker profiling     |
//| All monetary values are derived from live symbol properties; no    |
//| broker's settings are assumed for another.                         |
//+------------------------------------------------------------------+
#ifndef OMNIX_OCL_BROKER_MQH
#define OMNIX_OCL_BROKER_MQH

#include "Common.mqh"
#include "TradeLogger.mqh"

class CBrokerProfile
  {
public:
   string            symbol;
   string            company;
   string            server;
   int               digits;
   double            point;
   double            tick_size;
   double            tick_value;          // loss tick value, account currency per lot
   double            contract_size;
   double            vol_min,vol_max,vol_step,vol_limit;
   int               stops_level;         // points
   int               freeze_level;        // points
   double            swap_long,swap_short;
   double            margin_per_lot;      // from OrderCalcMargin at current Ask
   long              filling_flags;       // SYMBOL_FILLING_MODE bit mask
   long              order_flags;         // SYMBOL_ORDER_MODE bit mask
   long              expiration_flags;
   ENUM_SYMBOL_TRADE_EXECUTION exec_mode;
   ENUM_SYMBOL_TRADE_MODE      trade_mode;
   ENUM_ACCOUNT_MARGIN_MODE    margin_mode;
   string            base_ccy,profit_ccy,account_ccy;
   double            money_per_price_lot; // e.g. 100 USD per $1 per lot for 100 oz
   double            commission_rt_per_lot_cfg;    // owner-entered round-turn commission per lot
   double            commission_rt_per_lot_obs;    // learned from actual deals (0 until observed)
   int               commission_obs_count;

                     CBrokerProfile(void):commission_rt_per_lot_obs(0),commission_obs_count(0) {}

   bool              Hedging(void) const { return margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING; }
   double            CommissionRT(void) const
     { return (commission_obs_count>=5)?commission_rt_per_lot_obs:commission_rt_per_lot_cfg; }
   double            CostAsPrice(void) const { return OCL_CostAsPrice(CommissionRT(),money_per_price_lot); }
   double            NormalizePrice(const double p) const { return NormalizeDouble(OCL_RoundToTick(p,tick_size),digits); }
   double            NormalizeVol(const double v) const
     {
      double vmax=vol_max; if(vol_limit>0) vmax=MathMin(vmax,vol_limit);
      return OCL_NormalizeVolume(v,vol_min,vmax,vol_step);
     }
   double            MinStopDist(const double buffer) const
     {
      // refresh: stop/freeze levels can change intraday on some servers
      int sl=(int)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
      int fl=(int)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      return OCL_MinStopDistance(sl,fl,point,buffer);
     }
   double            FreezeDist(void) const
     { return (double)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL)*point; }

   //--- record actual commission from a closed round trip (both deals summed), per lot
   void              ObserveCommission(const double commission_total,const double volume)
     {
      if(volume<=0) return;
      double per_lot=MathAbs(commission_total)/volume;
      commission_obs_count++;
      commission_rt_per_lot_obs+= (per_lot-commission_rt_per_lot_obs)/MathMin(commission_obs_count,50);
     }

   //--- pick the gold symbol: override > chart symbol if gold > best-scoring Market Watch/server symbol
   static string     Discover(const string override_name,const string chart_symbol,string &report)
     {
      report="";
      if(override_name!="")
        {
         if(SymbolSelect(override_name,true)) { report="override "+override_name; return override_name; }
         report="override symbol not found: "+override_name; return "";
        }
      if(IsGold(chart_symbol)) { report="chart symbol "+chart_symbol; return chart_symbol; }
      string best=""; int best_score=0;
      int n=SymbolsTotal(false);
      for(int i=0;i<n;i++)
        {
         string s=SymbolName(i,false);
         if(!IsGold(s)) continue;
         int sc=OCL_GoldNameScore(s);
         if(SymbolInfoInteger(s,SYMBOL_SELECT)) sc+=5;   // prefer what the user already shows
         if(sc>best_score){ best_score=sc; best=s; }
         report+=s+"("+IntegerToString(sc)+") ";
        }
      if(best!="") SymbolSelect(best,true);
      report="candidates: "+report+"-> "+best;
      return best;
     }

   static bool       IsGold(const string s)
     {
      if(s=="") return false;
      string base=SymbolInfoString(s,SYMBOL_CURRENCY_BASE), prof=SymbolInfoString(s,SYMBOL_CURRENCY_PROFIT);
      StringToUpper(base); StringToUpper(prof);
      if(base=="XAU" && prof=="USD") return true;
      // some brokers name it GOLD with base currency USD or blank; fall back to the name score
      return (OCL_GoldNameScore(s)>0 && prof=="USD");
     }

   //--- read everything; returns false with a reason if the configuration cannot be traded safely
   bool              Load(const string sym,const double commission_rt_cfg,string &why)
     {
      symbol=sym; why="";
      company=AccountInfoString(ACCOUNT_COMPANY);
      server=AccountInfoString(ACCOUNT_SERVER);
      account_ccy=AccountInfoString(ACCOUNT_CURRENCY);
      digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
      point=SymbolInfoDouble(sym,SYMBOL_POINT);
      tick_size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
      tick_value=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tick_value<=0) tick_value=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
      contract_size=SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE);
      vol_min=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
      vol_max=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
      vol_step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
      vol_limit=SymbolInfoDouble(sym,SYMBOL_VOLUME_LIMIT);
      stops_level=(int)SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL);
      freeze_level=(int)SymbolInfoInteger(sym,SYMBOL_TRADE_FREEZE_LEVEL);
      swap_long=SymbolInfoDouble(sym,SYMBOL_SWAP_LONG);
      swap_short=SymbolInfoDouble(sym,SYMBOL_SWAP_SHORT);
      filling_flags=SymbolInfoInteger(sym,SYMBOL_FILLING_MODE);
      order_flags=SymbolInfoInteger(sym,SYMBOL_ORDER_MODE);
      expiration_flags=SymbolInfoInteger(sym,SYMBOL_EXPIRATION_MODE);
      exec_mode=(ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(sym,SYMBOL_TRADE_EXEMODE);
      trade_mode=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(sym,SYMBOL_TRADE_MODE);
      margin_mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      base_ccy=SymbolInfoString(sym,SYMBOL_CURRENCY_BASE);
      profit_ccy=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
      commission_rt_per_lot_cfg=commission_rt_cfg;
      money_per_price_lot=OCL_MoneyPerPricePerLot(tick_value,tick_size);
      double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
      margin_per_lot=0;
      if(ask>0 && !OrderCalcMargin(ORDER_TYPE_BUY,sym,1.0,ask,margin_per_lot)) margin_per_lot=0;

      //--- validation: reject unsafe or unsupported configurations
      if(point<=0 || tick_size<=0)            { why="invalid point/tick size"; return false; }
      if(tick_value<=0)                       { why="tick value unavailable (no quotes yet?)"; return false; }
      if(vol_min<=0 || vol_step<=0 || vol_max<vol_min) { why="invalid volume limits"; return false; }
      if(trade_mode!=SYMBOL_TRADE_MODE_FULL)  { why="symbol trade mode is not FULL ("+EnumToString(trade_mode)+")"; return false; }
      if((order_flags&SYMBOL_ORDER_STOP)==0)  { why="broker does not allow stop orders on this symbol"; return false; }
      if((order_flags&SYMBOL_ORDER_SL)==0)    { why="broker does not allow stop-loss on this symbol"; return false; }
      if(margin_mode==ACCOUNT_MARGIN_MODE_EXCHANGE) { why="exchange margin mode not supported"; return false; }
      if(profit_ccy!=account_ccy)
         PrintFormat("%s note: profit currency %s differs from account currency %s; tick value conversion is used",
                     OCL_PRODUCT,profit_ccy,account_ccy);
      return true;
     }

   string            Describe(void) const
     {
      return StringFormat("broker=%s server=%s symbol=%s digits=%d point=%g tick=%g tickval=%g contract=%g "
                          "money/$/lot=%.2f vol=[%g..%g step %g limit %g] stops=%d freeze=%d swapL=%g swapS=%g "
                          "margin/lot=%.2f filling=%I64d orders=%I64d exec=%s margin_mode=%s comm_rt_cfg=%.2f",
                          company,server,symbol,digits,point,tick_size,tick_value,contract_size,money_per_price_lot,
                          vol_min,vol_max,vol_step,vol_limit,stops_level,freeze_level,swap_long,swap_short,
                          margin_per_lot,filling_flags,order_flags,EnumToString(exec_mode),
                          EnumToString(margin_mode),commission_rt_per_lot_cfg);
     }

   //--- write a profile file per account/server for the multi-broker comparison
   void              Save(const CTradeLogger &logger) const
     {
      string srv=server; StringReplace(srv," ","_"); StringReplace(srv,"\\","_"); StringReplace(srv,"/","_");
      string fn=logger.Dir()+"\\broker_profile_"+srv+"_"+symbol+".txt";
      int h=FileOpen(fn,FILE_WRITE|FILE_TXT|FILE_ANSI|(logger.Common()?FILE_COMMON:0));
      if(h==INVALID_HANDLE) return;
      FileWriteString(h,Describe()+"\n");
      // trading sessions (server time) for each weekday
      for(int d=0;d<7;d++)
        {
         datetime f,t; string line=StringFormat("session day=%d:",d);
         for(uint k=0;SymbolInfoSessionTrade(symbol,(ENUM_DAY_OF_WEEK)d,k,f,t);k++)
            line+=" "+TimeToString(f,TIME_MINUTES)+"-"+TimeToString(t,TIME_MINUTES);
         FileWriteString(h,line+"\n");
        }
      FileClose(h);
     }
  };

#endif
