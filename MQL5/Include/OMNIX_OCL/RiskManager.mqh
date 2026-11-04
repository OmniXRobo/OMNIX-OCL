//+------------------------------------------------------------------+
//| RiskManager.mqh - pre-trade and continuous risk limits             |
//| No martingale, no grid, no averaging, no size increase after loss. |
//| Every entry must pass CanOpen(); limits are re-checked every tick. |
//+------------------------------------------------------------------+
#ifndef OMNIX_OCL_RISK_MQH
#define OMNIX_OCL_RISK_MQH

#include "Common.mqh"
#include "BrokerProfile.mqh"
#include "TradeLogger.mqh"

#define OCL_GV_EMERGENCY "OMNIX_OCL_EMERGENCY"   // >0: flatten and stop (set by dashboard/owner)
#define OCL_GV_NO_NEW    "OMNIX_OCL_NO_NEW"      // >0: no new pending orders

struct SOCLRiskConfig
  {
   ENUM_OCL_LOT_MODE lot_mode;
   double            fixed_lots;
   double            risk_pct;            // % of equity per trade (risk / adaptive modes)
   double            max_risk_pct;        // hard cap applied in every mode
   double            adaptive_max_lots;
   double            max_daily_loss_pct;  // from day-start balance, realised + floating
   double            max_daily_dd_pct;    // from the day's equity peak
   double            max_weekly_dd_pct;   // from the week's equity peak
   double            max_spread;          // price units
   double            max_spread_vs_avg;   // multiple of average spread
   double            max_slippage;        // price units, used for entry-quality kill switch
   int               max_positions;
   int               max_pending;
   int               max_trades_per_hour;
   int               max_consec_losses;
   int               consec_loss_pause_min;
   double            max_reject_rate;     // 0..1 over the last 20 requests
   double            max_account_lots;    // total open lots on the account, all symbols
   double            min_free_margin;     // account currency
   double            min_margin_level;    // %
   double            max_daily_commission;// account currency
   bool              emergency_stop;      // input switch
  };

class CRiskManager
  {
private:
   SOCLRiskConfig    c;
   CBrokerProfile   *bp;
   CTradeLogger     *lg;
   long              m_magic;
   int               m_day,m_week;
   double            m_day_start_bal,m_day_peak_eq,m_week_peak_eq;
   double            m_day_commission;
   int               m_consec_losses;
   datetime          m_pause_until;
   datetime          m_trades[];          // entry times, last hour
   bool              m_req_ok[20];
   int               m_req_n,m_req_head;
   bool              m_halt_day;          // daily limit hit: flat and no entries until next day
   bool              m_halt_week;
   string            m_halt_reason;
   double            m_slip_ema;

   int               DayKey(const datetime t) const { MqlDateTime d; TimeToStruct(t,d); return d.year*1000+d.day_of_year; }
   int               WeekKey(const datetime t) const { return (int)((t+3*86400)/(7*86400)); } // weeks start Monday 00:00 server time

public:
                     CRiskManager(void):bp(NULL),lg(NULL),m_day(0),m_week(0),m_day_commission(0),m_consec_losses(0),
                                       m_pause_until(0),m_req_n(0),m_req_head(0),m_halt_day(false),m_halt_week(false),
                                       m_slip_ema(0) {}

   void              Init(const SOCLRiskConfig &cfg,CBrokerProfile *profile,CTradeLogger *logger,const long magic)
     {
      c=cfg; bp=profile; lg=logger; m_magic=magic;
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      m_day=DayKey(TimeCurrent()); m_week=WeekKey(TimeCurrent());
      m_day_start_bal=AccountInfoDouble(ACCOUNT_BALANCE); m_day_peak_eq=eq; m_week_peak_eq=eq;
      if(!GlobalVariableCheck(OCL_GV_EMERGENCY)) GlobalVariableSet(OCL_GV_EMERGENCY,0);
      if(!GlobalVariableCheck(OCL_GV_NO_NEW))    GlobalVariableSet(OCL_GV_NO_NEW,0);
     }

   bool              EmergencyActive(void) const
     { return c.emergency_stop || GlobalVariableGet(OCL_GV_EMERGENCY)>0; }
   bool              NoNewActive(void) const { return GlobalVariableGet(OCL_GV_NO_NEW)>0; }
   string            HaltReason(void) const { return m_halt_reason; }
   bool              Halted(void) const { return m_halt_day || m_halt_week; }
   int               ConsecLosses(void) const { return m_consec_losses; }
   double            DayCommission(void) const { return m_day_commission; }
   double            DayPnL(void) const { return AccountInfoDouble(ACCOUNT_EQUITY)-m_day_start_bal; }
   double            DayDDPct(void) const
     { return (m_day_peak_eq>0)?(m_day_peak_eq-AccountInfoDouble(ACCOUNT_EQUITY))/m_day_peak_eq*100.0:0.0; }

   //--- per tick: roll periods, update peaks, evaluate continuous limits.
   //    Returns true if positions must be closed and pendings removed now.
   bool              Update(string &why)
     {
      datetime now=TimeCurrent();
      double eq=AccountInfoDouble(ACCOUNT_EQUITY), bal=AccountInfoDouble(ACCOUNT_BALANCE);
      int dk=DayKey(now), wk=WeekKey(now);
      if(dk!=m_day)
        {
         m_day=dk; m_day_start_bal=bal; m_day_peak_eq=eq; m_day_commission=0; m_halt_day=false;
         if(lg!=NULL) lg.Event("RISK_DAY_RESET",StringFormat("start balance %.2f",bal));
        }
      if(wk!=m_week){ m_week=wk; m_week_peak_eq=eq; m_halt_week=false; }
      m_day_peak_eq=MathMax(m_day_peak_eq,eq); m_week_peak_eq=MathMax(m_week_peak_eq,eq);

      if(EmergencyActive()){ why="EMERGENCY STOP active"; return true; }
      if(!m_halt_day)
        {
         double loss_pct=(m_day_start_bal>0)?(m_day_start_bal-eq)/m_day_start_bal*100.0:0;
         if(c.max_daily_loss_pct>0 && loss_pct>=c.max_daily_loss_pct)
           { m_halt_day=true; m_halt_reason=StringFormat("daily loss %.2f%% >= %.2f%%",loss_pct,c.max_daily_loss_pct); }
         else if(c.max_daily_dd_pct>0 && DayDDPct()>=c.max_daily_dd_pct)
           { m_halt_day=true; m_halt_reason=StringFormat("daily drawdown %.2f%% >= %.2f%%",DayDDPct(),c.max_daily_dd_pct); }
         if(m_halt_day){ if(lg!=NULL) lg.Event("RISK_HALT_DAY",m_halt_reason); why=m_halt_reason; return true; }
        }
      if(!m_halt_week && c.max_weekly_dd_pct>0 && m_week_peak_eq>0)
        {
         double wdd=(m_week_peak_eq-eq)/m_week_peak_eq*100.0;
         if(wdd>=c.max_weekly_dd_pct)
           {
            m_halt_week=true; m_halt_reason=StringFormat("weekly drawdown %.2f%% >= %.2f%%",wdd,c.max_weekly_dd_pct);
            if(lg!=NULL) lg.Event("RISK_HALT_WEEK",m_halt_reason);
            why=m_halt_reason; return true;
           }
        }
      if(m_halt_day || m_halt_week){ why=m_halt_reason; return false; }   // already flat; just stay out
      return false;
     }

   //--- count this EA's positions and pending orders on the symbol
   void              Counts(int &positions,int &pendings) const
     {
      positions=0; pendings=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i); if(t==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)==m_magic && PositionGetString(POSITION_SYMBOL)==bp.symbol) positions++;
        }
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         ulong t=OrderGetTicket(i); if(t==0) continue;
         if(OrderGetInteger(ORDER_MAGIC)==m_magic && OrderGetString(ORDER_SYMBOL)==bp.symbol) pendings++;
        }
     }

   double            AccountLots(void) const
     {
      double v=0;
      for(int i=PositionsTotal()-1;i>=0;i--){ if(PositionGetTicket(i)>0) v+=PositionGetDouble(POSITION_VOLUME); }
      return v;
     }

   //--- gate for placing new pending orders. new_orders = how many we want to add
   bool              CanArm(const double spread,const double spread_avg,const double lots,const int new_orders,string &why)
     {
      if(EmergencyActive()){ why="emergency stop"; return false; }
      if(NoNewActive()){ why="no-new-orders switch"; return false; }
      if(m_halt_day || m_halt_week){ why="halted: "+m_halt_reason; return false; }
      if(TimeCurrent()<m_pause_until){ why="consecutive-loss pause until "+TimeToString(m_pause_until,TIME_MINUTES); return false; }
      if(c.max_spread>0 && spread>c.max_spread){ why=StringFormat("spread %.2f > max %.2f",spread,c.max_spread); return false; }
      if(c.max_spread_vs_avg>0 && spread_avg>0 && spread>c.max_spread_vs_avg*spread_avg)
        { why=StringFormat("spread %.2f > %.1fx average %.2f",spread,c.max_spread_vs_avg,spread_avg); return false; }
      int pos,pend; Counts(pos,pend);
      if(pos>=c.max_positions){ why="max positions"; return false; }
      if(pend+new_orders>c.max_pending){ why="max pending orders"; return false; }
      PruneTrades();
      if(c.max_trades_per_hour>0 && ArraySize(m_trades)>=c.max_trades_per_hour){ why="max trades per hour"; return false; }
      if(c.max_reject_rate>0 && m_req_n>=10 && RejectRate()>c.max_reject_rate)
        { why=StringFormat("order rejection rate %.0f%% too high",RejectRate()*100); return false; }
      if(c.max_daily_commission>0 && MathAbs(m_day_commission)>=c.max_daily_commission){ why="daily commission budget used"; return false; }
      if(c.max_slippage>0 && m_slip_ema>c.max_slippage)
        { why=StringFormat("average entry slippage %.2f > max %.2f",m_slip_ema,c.max_slippage); return false; }
      if(lots<=0){ why="lot size computes to zero"; return false; }
      if(c.max_account_lots>0 && AccountLots()+lots>c.max_account_lots+1e-9){ why="account exposure limit"; return false; }
      double margin=0;
      if(OrderCalcMargin(ORDER_TYPE_BUY,bp.symbol,lots,SymbolInfoDouble(bp.symbol,SYMBOL_ASK),margin))
        {
         double fm=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         if(fm-margin<c.min_free_margin){ why=StringFormat("free margin %.2f - %.2f < min %.2f",fm,margin,c.min_free_margin); return false; }
        }
      double ml=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(c.min_margin_level>0 && AccountInfoDouble(ACCOUNT_MARGIN)>0 && ml<c.min_margin_level){ why="margin level too low"; return false; }
      return true;
     }

   //--- position size. Never larger than max_risk_pct of equity at the given stop.
   double            Lots(const double stop_dist,const ENUM_OCL_REGIME regime,const double news_factor,string &note)
     {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      double cost=bp.CommissionRT();
      double cap=OCL_LotsForRisk(eq*c.max_risk_pct/100.0,stop_dist,bp.money_per_price_lot,cost,
                                 bp.vol_min,bp.vol_max,bp.vol_step);
      double lots=0;
      if(c.lot_mode==LOT_FIXED){ lots=bp.NormalizeVol(c.fixed_lots); note="fixed"; }
      else
        {
         lots=OCL_LotsForRisk(eq*c.risk_pct/100.0,stop_dist,bp.money_per_price_lot,cost,bp.vol_min,bp.vol_max,bp.vol_step);
         note=StringFormat("risk %.2f%%",c.risk_pct);
         if(c.lot_mode==LOT_ADAPTIVE)
           {
            // only ever scales DOWN from the risk-based size
            double f=1.0;
            if(regime==REGIME_ACTIVE) f*=0.75;
            if(regime==REGIME_EXTREME || regime==REGIME_UNKNOWN) f*=0.5;
            if(c.max_daily_dd_pct>0 && DayDDPct()>c.max_daily_dd_pct*0.5) f*=0.5;
            if(m_consec_losses>=2) f*=0.5;
            lots=bp.NormalizeVol(MathMin(lots*f,c.adaptive_max_lots));
            note+=StringFormat(" adaptive x%.2f",f);
           }
        }
      if(news_factor<1.0){ lots=bp.NormalizeVol(lots*news_factor); note+=StringFormat(" news x%.2f",news_factor); }
      if(cap>0 && lots>cap){ note+=StringFormat(" capped %.2f->%.2f by max risk",lots,cap); lots=cap; }
      if(cap<=0){ note+=" (min lot exceeds max risk)"; lots=0; }
      return lots;
     }

   void              RecordEntry(const double slippage)
     {
      int n=ArraySize(m_trades); ArrayResize(m_trades,n+1); m_trades[n]=TimeCurrent();
      m_slip_ema=(n==0 && m_slip_ema==0)?MathMax(slippage,0):m_slip_ema+(MathMax(slippage,0)-m_slip_ema)*0.1;
     }
   void              PruneTrades(void)
     {
      datetime lim=TimeCurrent()-3600; int k=0;
      for(int i=0;i<ArraySize(m_trades);i++) if(m_trades[i]>=lim) m_trades[k++]=m_trades[i];
      ArrayResize(m_trades,k);
     }
   void              RecordRequest(const bool ok)
     {
      m_req_ok[m_req_head]=ok; m_req_head=(m_req_head+1)%20; if(m_req_n<20) m_req_n++;
     }
   double            RejectRate(void) const
     {
      if(m_req_n==0) return 0; int bad=0;
      for(int i=0;i<m_req_n;i++) if(!m_req_ok[i]) bad++;
      return (double)bad/m_req_n;
     }
   void              RecordClose(const double net,const double commission)
     {
      m_day_commission+=commission;
      if(net<0)
        {
         m_consec_losses++;
         if(c.max_consec_losses>0 && m_consec_losses>=c.max_consec_losses)
           {
            m_pause_until=TimeCurrent()+c.consec_loss_pause_min*60;
            if(lg!=NULL) lg.Event("RISK_PAUSE",StringFormat("%d consecutive losses; pause %d min",m_consec_losses,c.consec_loss_pause_min));
            m_consec_losses=0;
           }
        }
      else m_consec_losses=0;
     }
  };

#endif
