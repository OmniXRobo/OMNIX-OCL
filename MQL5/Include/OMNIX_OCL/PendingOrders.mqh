//+------------------------------------------------------------------+
//| PendingOrders.mqh - Buy Stop / Sell Stop bracket management        |
//| State is rebuilt from the terminal every tick (restart-safe);      |
//| in-flight guards stop duplicate requests.                          |
//+------------------------------------------------------------------+
#ifndef OMNIX_OCL_PENDING_MQH
#define OMNIX_OCL_PENDING_MQH

#include "Common.mqh"
#include "BrokerProfile.mqh"
#include "TradeLogger.mqh"
#include "ExecutionEngine.mqh"
#include "SignalEngine.mqh"
#include "MarketData.mqh"

struct SOCLPendingConfig
  {
   ENUM_OCL_PENDING_MODE mode;
   ENUM_OCL_FOLLOW_DIR   follow_dir;
   double            follow_step;        // $ difference that justifies a modify
   int               follow_min_ms;      // min ms between modifies of one order
   int               follow_max_per_min; // cap on modify/replace requests per minute (both sides)
   int               lifetime_s;         // cancel an unfilled order after this many seconds (0 = never)
   bool              broker_expiry;      // also send ORDER_TIME_SPECIFIED where supported
   ENUM_OCL_OCO_MODE oco_mode;
   double            stop_buffer;        // extra $ beyond broker stop/freeze level
  };

class CPendingOrders
  {
private:
   SOCLPendingConfig c;
   CBrokerProfile   *bp;
   CTradeLogger     *lg;
   CExecutionEngine *ex;
   CMarketData      *md;
   long              m_magic;
   long              m_inflight_until[2];   // 0 buy, 1 sell (GetTickCount64 ms)
   ulong             m_last_mod_ms[2];
   ulong             m_mod_times[];         // GetTickCount64 of recent modifies

   bool              InFlight(const int side) const { return (long)GetTickCount64()<m_inflight_until[side]; }
   void              SetInFlight(const int side,const bool on) { m_inflight_until[side]=on?(long)GetTickCount64()+3000:0; }

   int               ModsLastMinute(void)
     {
      ulong now=GetTickCount64(); int k=0;
      for(int i=0;i<ArraySize(m_mod_times);i++) if(now-m_mod_times[i]<60000) m_mod_times[k++]=m_mod_times[i];
      ArrayResize(m_mod_times,k);
      return k;
     }
   void              NoteMod(void) { int n=ArraySize(m_mod_times); ArrayResize(m_mod_times,n+1); m_mod_times[n]=GetTickCount64(); }

public:
   ulong             buy_ticket,sell_ticket;
   double            buy_price,sell_price,buy_sl,sell_sl;
   datetime          buy_setup,sell_setup;
   int               extra_orders;          // our orders that are not one of the two stops (should be 0)

                     CPendingOrders(void):bp(NULL),lg(NULL),ex(NULL),md(NULL) { m_inflight_until[0]=m_inflight_until[1]=0; m_last_mod_ms[0]=m_last_mod_ms[1]=0; }

   void              Init(const SOCLPendingConfig &cfg,CBrokerProfile *p,CTradeLogger *l,CExecutionEngine *e,
                          CMarketData *m,const long magic)
     { c=cfg; bp=p; lg=l; ex=e; md=m; m_magic=magic; }

   ENUM_OCL_OCO_MODE OcoMode(void) const { return c.oco_mode; }

   //--- rebuild state from the terminal
   void              Scan(void)
     {
      buy_ticket=sell_ticket=0; extra_orders=0;
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         ulong t=OrderGetTicket(i); if(t==0) continue;
         if(OrderGetInteger(ORDER_MAGIC)!=m_magic || OrderGetString(ORDER_SYMBOL)!=bp.symbol) continue;
         // an order that has just filled can still be listed for a moment (state STARTED/FILLED);
         // only working orders count, otherwise the OCO step tries to cancel the order that opened the position
         ENUM_ORDER_STATE st=(ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
         if(st!=ORDER_STATE_PLACED && st!=ORDER_STATE_PARTIAL) continue;
         ENUM_ORDER_TYPE ty=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(ty==ORDER_TYPE_BUY_STOP && buy_ticket==0)
           { buy_ticket=t; buy_price=OrderGetDouble(ORDER_PRICE_OPEN); buy_sl=OrderGetDouble(ORDER_SL);
             buy_setup=(datetime)OrderGetInteger(ORDER_TIME_SETUP); SetInFlight(0,false); }
         else if(ty==ORDER_TYPE_SELL_STOP && sell_ticket==0)
           { sell_ticket=t; sell_price=OrderGetDouble(ORDER_PRICE_OPEN); sell_sl=OrderGetDouble(ORDER_SL);
             sell_setup=(datetime)OrderGetInteger(ORDER_TIME_SETUP); SetInFlight(1,false); }
         else extra_orders++;
        }
     }

   //--- remove every order of ours on the symbol (duplicates included)
   void              CancelAll(const string reason)
     {
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         ulong t=OrderGetTicket(i); if(t==0) continue;
         if(OrderGetInteger(ORDER_MAGIC)!=m_magic || OrderGetString(ORDER_SYMBOL)!=bp.symbol) continue;
         ENUM_ORDER_STATE st=(ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
         if(st!=ORDER_STATE_PLACED && st!=ORDER_STATE_PARTIAL) continue;
         ex.Cancel(t,reason);
        }
      Scan();
     }

   void              CancelSide(const int side,const string reason)
     {
      ulong t=(side==0)?buy_ticket:sell_ticket;
      if(t==0) return;
      // the cached ticket can be stale: the order may have filled (or been removed) since the last Scan();
      // cancelling it then fails with rc=10013, so only cancel an order that is still working
      if(!IsWorking(t)){ if(side==0) buy_ticket=0; else sell_ticket=0; return; }
      if(ex.Cancel(t,reason)){ if(side==0) buy_ticket=0; else sell_ticket=0; }
     }

   bool              IsWorking(const ulong t) const
     {
      if(!OrderSelect(t)) return false;
      ENUM_ORDER_STATE st=(ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      return (st==ORDER_STATE_PLACED || st==ORDER_STATE_PARTIAL);
     }

   //--- duplicates (e.g. after a restart race): keep one per side
   void              CancelExtras(void)
     {
      if(extra_orders<=0) return;
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         ulong t=OrderGetTicket(i); if(t==0) continue;
         if(OrderGetInteger(ORDER_MAGIC)!=m_magic || OrderGetString(ORDER_SYMBOL)!=bp.symbol) continue;
         ENUM_ORDER_STATE st=(ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
         if(st!=ORDER_STATE_PLACED && st!=ORDER_STATE_PARTIAL) continue;   // filling or already gone
         if(t!=buy_ticket && t!=sell_ticket) ex.Cancel(t,"duplicate/unknown order");
        }
     }

   //--- desired prices for this tick
   void              Desired(const SOCLSignal &s,double &bprice,double &bsl,double &sprice,double &ssl) const
     {
      double tick=bp.tick_size, mind=bp.MinStopDist(c.stop_buffer);
      double sld=MathMax(s.sl_dist,mind+tick);
      bprice=OCL_BuyStopPrice(md.tick.ask,s.buy_offset,mind,tick);
      bsl=OCL_RoundToTick(bprice-sld,tick);
      sprice=OCL_SellStopPrice(md.tick.bid,s.sell_offset,mind,tick);
      ssl=OCL_RoundToTick(sprice+sld,tick);
     }

   //--- flat: place missing sides and manage existing ones
   void              ManageFlat(const SOCLSignal &s,const bool may_place,const double lots,const string why_place)
     {
      double bpz,bsl,spz,ssl; Desired(s,bpz,bsl,spz,ssl);
      ulong nowms=GetTickCount64();

      //--- lifetime expiry (own timer; broker expiry is a backstop)
      if(c.lifetime_s>0)
        {
         if(buy_ticket>0 && TimeCurrent()-buy_setup>=c.lifetime_s) CancelSide(0,"lifetime");
         if(sell_ticket>0 && TimeCurrent()-sell_setup>=c.lifetime_s) CancelSide(1,"lifetime");
        }
      //--- a side the signal no longer wants (e.g. momentum flipped) is withdrawn
      if(buy_ticket>0 && !s.arm_buy)  CancelSide(0,"signal withdrew buy side: "+s.reason);
      if(sell_ticket>0 && !s.arm_sell) CancelSide(1,"signal withdrew sell side: "+s.reason);

      //--- follow price
      if(c.mode!=PEND_STATIC)
        {
         double fz=bp.FreezeDist();
         for(int side=0;side<2;side++)
           {
            ulong t=(side==0)?buy_ticket:sell_ticket; if(t==0) continue;
            double cur=(side==0)?buy_price:sell_price, want=(side==0)?bpz:spz, wsl=(side==0)?bsl:ssl;
            double diff=want-cur;
            if(MathAbs(diff)<c.follow_step-1e-9) continue;
            // tighten-only: buy stop may only move down toward a falling market, sell stop only up
            if(c.follow_dir==FOLLOW_TIGHTEN_ONLY && ((side==0 && diff>0) || (side==1 && diff<0))) continue;
            if(nowms-m_last_mod_ms[side]<(ulong)c.follow_min_ms) continue;
            if(ModsLastMinute()>=c.follow_max_per_min) continue;
            // freeze level: cannot touch an order whose price is within the freeze distance of the market
            double mkt=(side==0)?md.tick.ask:md.tick.bid;
            if(fz>0 && MathAbs(cur-mkt)<=fz) continue;
            m_last_mod_ms[side]=nowms; NoteMod();
            string why=StringFormat("follow %.2f->%.2f",cur,want);
            if(c.mode==PEND_FOLLOW_MODIFY)
               ex.ModifyPending(t,want,wsl,why);
            else
              {
               // replace: cancel then place a new order on the same side
               if(IsWorking(t) && ex.Cancel(t,"replace "+why))
                 {
                  ulong nt=0; SetInFlight(side,true);
                  if(!ex.PlaceStop(side==0?ORDER_TYPE_BUY_STOP:ORDER_TYPE_SELL_STOP,lots,want,wsl,
                                   c.broker_expiry?c.lifetime_s:0,"replace "+why,nt)) SetInFlight(side,false);
                 }
              }
           }
        }

      //--- place missing sides
      if(!may_place) return;
      if(s.arm_buy && buy_ticket==0 && !InFlight(0))
        {
         ulong t=0; SetInFlight(0,true);
         if(!ex.PlaceStop(ORDER_TYPE_BUY_STOP,lots,bpz,bsl,c.broker_expiry?c.lifetime_s:0,why_place+" | "+s.reason,t))
            SetInFlight(0,false);
        }
      if(s.arm_sell && sell_ticket==0 && !InFlight(1))
        {
         ulong t=0; SetInFlight(1,true);
         if(!ex.PlaceStop(ORDER_TYPE_SELL_STOP,lots,spz,ssl,c.broker_expiry?c.lifetime_s:0,why_place+" | "+s.reason,t))
            SetInFlight(1,false);
        }
     }

   //--- a position is open (dir +1 long / -1 short) with current SL; apply the OCO policy
   void              ManageInPosition(const int dir,const double pos_sl)
     {
      // a same-side remainder (partial fill) is never left working
      if(dir>0 && buy_ticket>0)  CancelSide(0,"same-side remainder while long");
      if(dir<0 && sell_ticket>0) CancelSide(1,"same-side remainder while short");
      if(c.oco_mode==OCO_CANCEL_ON_FILL)
        {
         if(dir>0 && sell_ticket>0) CancelSide(1,"OCO: buy filled");
         if(dir<0 && buy_ticket>0)  CancelSide(0,"OCO: sell filled");
         return;
        }
      // keep the opposite only while the position's SL sits strictly between entry and the opposite order,
      // so the position must be stopped out before the opposite can fill (no overlap)
      if(dir>0 && sell_ticket>0 && !(pos_sl>0 && pos_sl>sell_price+bp.tick_size)) CancelSide(1,"OCO geometry unsafe");
      if(dir<0 && buy_ticket>0  && !(pos_sl>0 && pos_sl<buy_price-bp.tick_size))  CancelSide(0,"OCO geometry unsafe");
     }

   //--- called after a position closes
   void              OnPositionClosed(void)
     {
      Scan();
      if(c.oco_mode==OCO_CANCEL_ON_CLOSE && (buy_ticket>0 || sell_ticket>0)) CancelAll("OCO: position closed");
      // OCO_KEEP_OPPOSITE: the resting order stays and becomes one side of the next bracket
     }
  };

#endif
