//+------------------------------------------------------------------+
//| ExecutionEngine.mqh - validated order requests with retcode        |
//| handling, filling-mode fallback, back-off and duplicate guards.    |
//+------------------------------------------------------------------+
#ifndef OMNIX_OCL_EXECUTION_MQH
#define OMNIX_OCL_EXECUTION_MQH

#include "Common.mqh"
#include "BrokerProfile.mqh"
#include "TradeLogger.mqh"
#include "RiskManager.mqh"

class CExecutionEngine
  {
private:
   CBrokerProfile   *bp;
   CTradeLogger     *lg;
   CRiskManager     *rm;
   long              m_magic;
   int               m_deviation_points;
   ENUM_ORDER_TYPE_FILLING m_fill_pending;
   ENUM_ORDER_TYPE_FILLING m_fill_market;
   datetime          m_backoff_until;
   uint              m_last_rc;          // retcode of the last OrderSend (0 = none / skipped)
   long              m_last_send_msc;
   double            m_latency_ema_ms;

   ENUM_ORDER_TYPE_FILLING NextFilling(const ENUM_ORDER_TYPE_FILLING f) const
     {
      if(f==ORDER_FILLING_FOK) return ORDER_FILLING_IOC;
      if(f==ORDER_FILLING_IOC) return ORDER_FILLING_RETURN;
      return ORDER_FILLING_FOK;
     }

   //--- send with filling fallback and one quote-refresh retry. Returns true on success.
   bool              Send(MqlTradeRequest &req,MqlTradeResult &res,const string what,const bool is_pending)
     {
      if(TimeCurrent()<m_backoff_until)
        { lg.Event("EXEC_SKIP",what+": back-off active"); return false; }
      if(!TerminalInfoInteger(TERMINAL_CONNECTED))
        { lg.Event("EXEC_SKIP",what+": terminal disconnected"); return false; }
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
        { lg.Event("EXEC_SKIP",what+": algo trading disabled in terminal"); return false; }

      for(int attempt=0;attempt<3;attempt++)
        {
         if(req.action==TRADE_ACTION_DEAL || req.action==TRADE_ACTION_PENDING)
            req.type_filling=is_pending?m_fill_pending:m_fill_market;
         MqlTradeCheckResult chk; ZeroMemory(chk);
         ZeroMemory(res);
         if(!OrderCheck(req,chk) && chk.retcode!=0 && chk.retcode!=TRADE_RETCODE_DONE)
           {
            if(chk.retcode==TRADE_RETCODE_INVALID_FILL && attempt<2)
              {
               if(is_pending) m_fill_pending=NextFilling(m_fill_pending); else m_fill_market=NextFilling(m_fill_market);
               continue;
              }
            lg.Event("EXEC_CHECK_FAIL",what+": "+chk.comment,req.order,req.position,req.volume,req.price,0,req.sl,(int)chk.retcode);
            rm.RecordRequest(false);
            return false;
           }
         ulong t0=GetMicrosecondCount();
         bool sent=OrderSend(req,res);
         double ms=(GetMicrosecondCount()-t0)/1000.0;
         m_latency_ema_ms=(m_latency_ema_ms<=0)?ms:m_latency_ema_ms+(ms-m_latency_ema_ms)*0.1;
         uint rc=res.retcode;
         m_last_rc=rc;
         if(rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_PLACED || rc==TRADE_RETCODE_DONE_PARTIAL)
           {
            rm.RecordRequest(true);
            lg.Event("EXEC_OK",StringFormat("%s latency=%.1fms",what,ms),res.order>0?res.order:req.order,req.position,
                      req.volume,req.price,res.price,req.sl,(int)rc);
            return true;
           }
         lg.Event("EXEC_FAIL",StringFormat("%s: %s (sent=%d)",what,res.comment,(int)sent),req.order,req.position,
                  req.volume,req.price,res.price,req.sl,(int)rc);
         if(rc==TRADE_RETCODE_INVALID_FILL && attempt<2)
           { if(is_pending) m_fill_pending=NextFilling(m_fill_pending); else m_fill_market=NextFilling(m_fill_market); continue; }
         if((rc==TRADE_RETCODE_REQUOTE || rc==TRADE_RETCODE_PRICE_CHANGED || rc==TRADE_RETCODE_PRICE_OFF) && attempt<1
            && req.action==TRADE_ACTION_DEAL)
           {
            MqlTick t; SymbolInfoTick(bp.symbol,t);
            req.price=(req.type==ORDER_TYPE_BUY)?t.ask:t.bid;
            continue;
           }
         rm.RecordRequest(false);
         if(rc==TRADE_RETCODE_TOO_MANY_REQUESTS || rc==TRADE_RETCODE_CONNECTION || rc==TRADE_RETCODE_TIMEOUT ||
            rc==TRADE_RETCODE_SERVER_DISABLES_AT || rc==TRADE_RETCODE_CLIENT_DISABLES_AT)
            m_backoff_until=TimeCurrent()+5;
         if(rc==TRADE_RETCODE_MARKET_CLOSED || rc==TRADE_RETCODE_TRADE_DISABLED)
            m_backoff_until=TimeCurrent()+60;
         return false;
        }
      return false;
     }

public:
                     CExecutionEngine(void):bp(NULL),lg(NULL),rm(NULL),m_backoff_until(0),m_last_rc(0),m_last_send_msc(0),
                                           m_latency_ema_ms(0) {}

   void              Init(CBrokerProfile *profile,CTradeLogger *logger,CRiskManager *risk,const long magic,
                          const int deviation_points)
     {
      bp=profile; lg=logger; rm=risk; m_magic=magic; m_deviation_points=deviation_points;
      // initial guesses from the symbol's allowed filling flags; Send() falls back if rejected
      long ff=bp.filling_flags;
      m_fill_market=((ff&SYMBOL_FILLING_FOK)!=0)?ORDER_FILLING_FOK:(((ff&SYMBOL_FILLING_IOC)!=0)?ORDER_FILLING_IOC:ORDER_FILLING_RETURN);
      m_fill_pending=ORDER_FILLING_RETURN;
     }
   double            LatencyMs(void) const { return m_latency_ema_ms; }
   uint              LastRetcode(void) const { return m_last_rc; }

   bool              PlaceStop(const ENUM_ORDER_TYPE type,const double lots,const double price,const double sl,
                               const int expiry_seconds,const string reason,ulong &ticket)
     {
      ticket=0;
      MqlTradeRequest r; MqlTradeResult res; ZeroMemory(r);
      r.action=TRADE_ACTION_PENDING; r.symbol=bp.symbol; r.magic=m_magic; r.volume=lots; r.type=type;
      r.price=bp.NormalizePrice(price); r.sl=bp.NormalizePrice(sl); r.tp=0; r.deviation=m_deviation_points;
      r.comment=OCL_ORDER_COMMENT;
      r.type_time=ORDER_TIME_GTC;
      if(expiry_seconds>0 && (bp.expiration_flags&SYMBOL_EXPIRATION_SPECIFIED)!=0)
        { r.type_time=ORDER_TIME_SPECIFIED; r.expiration=TimeTradeServer()+MathMax(expiry_seconds,61); }
      bool ok=Send(r,res,(type==ORDER_TYPE_BUY_STOP?"PLACE BUY_STOP ":"PLACE SELL_STOP ")+reason,true);
      if(ok) ticket=res.order;
      return ok;
     }

   bool              ModifyPending(const ulong ticket,const double price,const double sl,const string reason)
     {
      if(!OrderSelect(ticket)) return false;
      MqlTradeRequest r; MqlTradeResult res; ZeroMemory(r);
      r.action=TRADE_ACTION_MODIFY; r.order=ticket; r.symbol=bp.symbol;
      r.price=bp.NormalizePrice(price); r.sl=bp.NormalizePrice(sl); r.tp=0;
      r.type_time=(ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
      r.expiration=(datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      return Send(r,res,"MODIFY PENDING "+reason,true);
     }

   bool              Cancel(const ulong ticket,const string reason)
     {
      MqlTradeRequest r; MqlTradeResult res; ZeroMemory(r);
      r.action=TRADE_ACTION_REMOVE; r.order=ticket;
      return Send(r,res,"CANCEL "+reason,true);
     }

   bool              ModifySL(const ulong position_ticket,const double sl,const string reason)
     {
      if(!PositionSelectByTicket(position_ticket)) return false;
      MqlTradeRequest r; MqlTradeResult res; ZeroMemory(r);
      r.action=TRADE_ACTION_SLTP; r.position=position_ticket; r.symbol=bp.symbol;
      r.sl=bp.NormalizePrice(sl); r.tp=PositionGetDouble(POSITION_TP); r.magic=m_magic;
      m_last_rc=0;
      return Send(r,res,"MODIFY SL "+reason,false);
     }

   bool              ClosePosition(const ulong position_ticket,const string reason)
     {
      if(!PositionSelectByTicket(position_ticket)) return false;
      MqlTradeRequest r; MqlTradeResult res; ZeroMemory(r);
      MqlTick t; SymbolInfoTick(bp.symbol,t);
      long ptype=PositionGetInteger(POSITION_TYPE);
      r.action=TRADE_ACTION_DEAL; r.position=position_ticket; r.symbol=bp.symbol; r.magic=m_magic;
      r.volume=PositionGetDouble(POSITION_VOLUME);
      r.type=(ptype==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
      r.price=(ptype==POSITION_TYPE_BUY)?t.bid:t.ask;
      r.deviation=m_deviation_points; r.comment=OCL_ORDER_COMMENT+" close";
      return Send(r,res,"CLOSE "+reason,false);
     }
  };

#endif
