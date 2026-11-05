//+------------------------------------------------------------------+
//| PositionManager.mqh - exits for open positions                     |
//| Exit variants A-F (see documentation/M2_Strategy_Specification).   |
//| A server-side SL is always present; it only ever moves in the      |
//| position's favour.                                                 |
//+------------------------------------------------------------------+
#ifndef OMNIX_OCL_POSITION_MQH
#define OMNIX_OCL_POSITION_MQH

#include "Common.mqh"
#include "BrokerProfile.mqh"
#include "TradeLogger.mqh"
#include "ExecutionEngine.mqh"
#include "MarketData.mqh"

class CPositionManager
  {
private:
   SOCLExitConfig    c;
   CBrokerProfile   *bp;
   CTradeLogger     *lg;
   CExecutionEngine *ex;
   CMarketData      *md;
   long              m_magic;
   double            m_sl_dist;          // initial SL distance used to restore a missing SL
   int               m_sl_min_modify_ms;
   ulong             m_last_sl_mod_ms;
   int               m_missing_sl_fails;
   double            m_stop_buffer;
   int               m_momentum_window_ms;
   double            m_momentum_min;
   double            m_latency_pad_per_s; // extra SL gap ($) per second of measured order latency

public:
   ulong             ticket;              // current position ticket (0 = flat)
   int               dir;
   double            entry,sl,volume,profit,swap;
   datetime          open_time;

                     CPositionManager(void):bp(NULL),lg(NULL),ex(NULL),md(NULL),m_last_sl_mod_ms(0),m_missing_sl_fails(0),ticket(0) {}

   void              Init(const SOCLExitConfig &cfg,CBrokerProfile *p,CTradeLogger *l,CExecutionEngine *e,CMarketData *m,
                          const long magic,const int sl_min_modify_ms,const double stop_buffer,
                          const int momentum_window_ms,const double momentum_min,const double latency_pad_per_s=0.0)
     {
      m_latency_pad_per_s=latency_pad_per_s;
      c=cfg; bp=p; lg=l; ex=e; md=m; m_magic=magic; m_sl_min_modify_ms=sl_min_modify_ms; m_stop_buffer=stop_buffer;
      m_momentum_window_ms=momentum_window_ms; m_momentum_min=momentum_min;
     }
   void              SetInitialStop(const double d) { m_sl_dist=d; }

   //--- find our positions; returns count and loads the oldest into the public fields
   int               Scan(void)
     {
      int n=0; ticket=0; datetime oldest=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i); if(t==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic || PositionGetString(POSITION_SYMBOL)!=bp.symbol) continue;
         n++;
         datetime ot=(datetime)PositionGetInteger(POSITION_TIME);
         if(ticket==0 || ot<oldest)
           {
            oldest=ot; ticket=t; open_time=ot;
            dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
            entry=PositionGetDouble(POSITION_PRICE_OPEN); sl=PositionGetDouble(POSITION_SL);
            volume=PositionGetDouble(POSITION_VOLUME); profit=PositionGetDouble(POSITION_PROFIT);
            swap=PositionGetDouble(POSITION_SWAP);
           }
        }
      return n;
     }

   //--- close everything of ours on the symbol
   void              CloseAll(const string reason)
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i); if(t==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic || PositionGetString(POSITION_SYMBOL)!=bp.symbol) continue;
         ex.ClosePosition(t,reason);
        }
     }

   //--- close all but the oldest (should never be needed; guards against overlap)
   void              CloseExcess(const int max_positions)
     {
      int n=Scan(); if(n<=max_positions) return;
      ulong keep=ticket;
      for(int i=PositionsTotal()-1;i>=0 && n>max_positions;i--)
        {
         ulong t=PositionGetTicket(i); if(t==0 || t==keep) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic || PositionGetString(POSITION_SYMBOL)!=bp.symbol) continue;
         if(ex.ClosePosition(t,"excess position over limit")) n--;
        }
     }

   double            NetFloating(void) const
     { return profit+swap-bp.CommissionRT()*volume; }

   //--- per-tick exit management for the position loaded by Scan()
   void              Manage(void)
     {
      if(ticket==0) return;
      double bid=md.tick.bid, ask=md.tick.ask, tick=bp.tick_size;
      double mind=bp.MinStopDist(m_stop_buffer);
      double px=(dir>0)?bid:ask;
      //--- latency guard: on a slow link price keeps moving while a modify is in flight, so keep the
      //    new stop further from price and space modifies by at least two round trips
      double lat_ms=ex.LatencyMs();
      double lat_pad=(m_latency_pad_per_s>0 && lat_ms>0)?OCL_RoundToTick(m_latency_pad_per_s*lat_ms/1000.0,tick):0.0;
      double mind_mod=mind+lat_pad;
      ulong  min_gap_ms=(ulong)MathMax((double)m_sl_min_modify_ms,2.0*lat_ms);
      double move=(dir>0)?(bid-entry):(entry-ask);

      //--- 1. never run without a stop
      if(sl<=0)
        {
         double want=(dir>0)?OCL_RoundToTick(MathMin(entry-m_sl_dist,bid-mind),tick)
                            :OCL_RoundToTick(MathMax(entry+m_sl_dist,ask+mind),tick);
         if(ex.ModifySL(ticket,want,"restore missing SL")) m_missing_sl_fails=0;
         else if(++m_missing_sl_fails>=2) ex.ClosePosition(ticket,"could not set SL");
         return;
        }

      //--- 2. time exit (variant E)
      int age=(int)(TimeCurrent()-open_time);
      if(c.use_time_exit && c.max_hold_seconds>0 && age>=c.max_hold_seconds)
        {
         if(c.time_exit_rule==TIMEEXIT_ALWAYS || NetFloating()<=0)
           { ex.ClosePosition(ticket,StringFormat("time exit %ds net %.2f",age,NetFloating())); return; }
        }

      //--- 3. micro-profit capture (variant D), on NET floating profit after commission
      if(c.use_microprofit && c.micro_profit_usd>0 && NetFloating()>=c.micro_profit_usd)
        { ex.ClosePosition(ticket,StringFormat("micro-profit net %.2f",NetFloating())); return; }

      //--- 4. adaptive momentum-fade exit (variant F): in profit and the micro-move turns against us
      if(c.adaptive && move>=c.trail_activation && m_momentum_min>0)
        {
         double ch=md.ChangeMs(m_momentum_window_ms)*dir;
         if(ch<=-m_momentum_min && NetFloating()>0)
           { ex.ClosePosition(ticket,StringFormat("momentum fade %.2f, net %.2f",ch,NetFloating())); return; }
        }

      //--- 5. stop improvements: break-even (C) and trailing (B / F); pick the tighter
      double best=0;
      string why="";
      if(c.use_breakeven)
        {
         double be=OCL_BreakEvenCandidate(dir,entry,bid,ask,sl,c.be_trigger,c.be_offset,bp.CostAsPrice(),mind_mod,tick);
         if(be>0){ best=be; why="break-even"; }
        }
      if(c.use_trailing || c.adaptive)
        {
         double trail=c.trail_distance;
         if(c.adaptive)
            trail=MathMax(c.adaptive_min_trail,c.adaptive_trail_k*md.RangeMs(m_momentum_window_ms));
         double tr=OCL_TrailCandidate(dir,entry,bid,ask,sl,c.trail_activation,trail,c.trail_step,mind_mod,tick);
         if(tr>0 && (best==0 || (dir>0 && tr>best) || (dir<0 && tr<best))){ best=tr; why=StringFormat("trail %.2f",trail); }
        }
      if(best>0)
        {
         // freeze level: cannot modify when the current SL is within the freeze distance of price
         double fz=bp.FreezeDist();
         if(fz>0 && MathAbs(px-sl)<=fz) return;
         ulong now=GetTickCount64();
         if(now-m_last_sl_mod_ms<min_gap_ms) return;
         m_last_sl_mod_ms=now;
         if(ex.ModifySL(ticket,best,StringFormat("%s %.2f->%.2f move %.2f lat %.0fms",why,sl,best,move,lat_ms))) return;
         uint rc=ex.LastRetcode();
         if(rc==TRADE_RETCODE_POSITION_CLOSED) return;     // already stopped out
         //--- price ran through the stop we wanted while the request was in flight (typically 10016):
         //    the old, worse stop is still live, so take the price that the new stop was meant to protect
         MqlTick t;
         if(!SymbolInfoTick(bp.symbol,t)) return;
         double now_px=(dir>0)?t.bid:t.ask;
         bool crossed=(dir>0)?(now_px<=best+1e-9):(now_px>=best-1e-9);
         if(crossed && (rc==TRADE_RETCODE_INVALID_STOPS || rc==TRADE_RETCODE_ERROR || rc==TRADE_RETCODE_TIMEOUT
                        || rc==TRADE_RETCODE_FROZEN || rc==TRADE_RETCODE_PRICE_CHANGED))
            ex.ClosePosition(ticket,StringFormat("stop %.2f passed during modify (rc %u), close at market %.2f",best,rc,now_px));
        }
     }
  };

#endif
