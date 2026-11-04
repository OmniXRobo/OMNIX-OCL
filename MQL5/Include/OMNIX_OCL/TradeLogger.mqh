//+------------------------------------------------------------------+
//| TradeLogger.mqh - audit trail for OMNIX OCL                        |
//| Files (in MQL5/Files/OMNIX_OCL/ or Common/Files/OMNIX_OCL/):       |
//|   events_YYYYMMDD.csv  every decision, request, transaction        |
//|   trades.csv           one row per closed position, net of costs   |
//|   status.json          snapshot for the dashboard                  |
//| No passwords or full account numbers are ever written.             |
//+------------------------------------------------------------------+
#ifndef OMNIX_OCL_LOGGER_MQH
#define OMNIX_OCL_LOGGER_MQH

#include "Common.mqh"

struct SOCLLogRow
  {
   string            event;
   ulong             order_ticket;
   ulong             position_id;
   double            bid;
   double            ask;
   double            volume;
   double            req_price;
   double            exec_price;
   double            sl;
   double            commission;
   double            slippage;
   int               retcode;
   string            reason;
  };

class CTradeLogger
  {
private:
   int               m_h;
   int               m_day;
   bool              m_common;
   bool              m_flush_each;
   bool              m_log_ticks;
   string            m_symbol;
   string            m_broker;
   string            m_env;
   string            m_acct;
   string            m_dir;
   long              m_rows;

   int               Flags(void) const { return FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|(m_common?FILE_COMMON:0); }

   bool              OpenDaily(void)
     {
      MqlDateTime d; TimeToStruct(TimeCurrent(),d);
      int day=d.year*10000+d.mon*100+d.day;
      if(m_h!=INVALID_HANDLE && day==m_day) return true;
      if(m_h!=INVALID_HANDLE) FileClose(m_h);
      m_day=day;
      string fn=StringFormat("%s\\events_%d.csv",m_dir,day);
      m_h=FileOpen(fn,Flags(),',');
      if(m_h==INVALID_HANDLE){ PrintFormat("%s logger: cannot open %s err=%d",OCL_PRODUCT,fn,GetLastError()); return false; }
      if(FileSize(m_h)==0)
         FileWrite(m_h,"ts_msc","ts","broker","env","account","symbol","version","event","order_ticket",
                   "position_id","bid","ask","spread","volume","req_price","exec_price","sl","commission",
                   "slippage","retcode","reason");
      FileSeek(m_h,0,SEEK_END);
      return true;
     }

public:
                     CTradeLogger(void):m_h(INVALID_HANDLE),m_day(0),m_common(false),m_flush_each(true),
                                        m_log_ticks(false),m_rows(0) {}
                    ~CTradeLogger(void) { Close(); }

   bool              Init(const string symbol,const bool use_common,const bool log_ticks)
     {
      m_symbol=symbol; m_common=use_common; m_log_ticks=log_ticks;
      bool tester=(bool)MQLInfoInteger(MQL_TESTER);
      m_flush_each=!tester;                      // flushing every row is too slow in the tester
      m_broker=AccountInfoString(ACCOUNT_COMPANY); StringReplace(m_broker,",",";");
      ENUM_ACCOUNT_TRADE_MODE tm=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
      m_env=tester?"tester":(tm==ACCOUNT_TRADE_MODE_DEMO?"demo":(tm==ACCOUNT_TRADE_MODE_CONTEST?"contest":"real"));
      string login=IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
      m_acct="***"+StringSubstr(login,MathMax(0,StringLen(login)-3));
      m_dir=tester?"OMNIX_OCL\\tester":"OMNIX_OCL";
      FolderCreate("OMNIX_OCL",m_common?FILE_COMMON:0);
      FolderCreate(m_dir,m_common?FILE_COMMON:0);
      return OpenDaily();
     }

   void              Close(void) { if(m_h!=INVALID_HANDLE){ FileClose(m_h); m_h=INVALID_HANDLE; } }
   bool              LogTicks(void) const { return m_log_ticks; }
   string            Env(void) const { return m_env; }
   string            Dir(void) const { return m_dir; }
   bool              Common(void) const { return m_common; }

   void              Write(const SOCLLogRow &r)
     {
      if(!OpenDaily()) return;
      long msc=OCL_NowMsc(m_symbol);
      int dg=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      string reason=r.reason; StringReplace(reason,",",";");
      FileWrite(m_h,msc,OCL_MscToString(msc),m_broker,m_env,m_acct,m_symbol,OCL_VERSION,r.event,
                r.order_ticket,r.position_id,DoubleToString(r.bid,dg),DoubleToString(r.ask,dg),
                DoubleToString(r.ask-r.bid,dg),DoubleToString(r.volume,2),DoubleToString(r.req_price,dg),
                DoubleToString(r.exec_price,dg),DoubleToString(r.sl,dg),DoubleToString(r.commission,2),
                DoubleToString(r.slippage,dg),r.retcode,reason);
      m_rows++;
      if(m_flush_each) FileFlush(m_h);
     }

   //--- convenience: event with current quotes and a reason
   void              Event(const string event,const string reason,const ulong order=0,const ulong pos=0,
                           const double vol=0,const double req=0,const double exec=0,const double sl=0,
                           const int retcode=0)
     {
      SOCLLogRow r; ZeroMemory(r);
      MqlTick t; if(SymbolInfoTick(m_symbol,t)){ r.bid=t.bid; r.ask=t.ask; }
      r.event=event; r.reason=reason; r.order_ticket=order; r.position_id=pos; r.volume=vol;
      r.req_price=req; r.exec_price=exec; r.sl=sl; r.retcode=retcode;
      Write(r);
     }

   //--- one row per closed position
   void              Trade(const ulong pos_id,const int dir,const double vol,const long open_msc,const long close_msc,
                           const double entry,const double exit_price,const double gross,const double commission,
                           const double swap,const double entry_slip,const string exit_reason,const string regime,
                           const string strategy_tag)
     {
      int flags=Flags();
      string fn=m_dir+"\\trades.csv";
      int h=FileOpen(fn,flags,',');
      if(h==INVALID_HANDLE) return;
      if(FileSize(h)==0)
         FileWrite(h,"position_id","dir","volume","open","close","duration_s","entry","exit","move",
                   "gross","commission","swap","net","entry_slippage","exit_reason","regime","strategy",
                   "broker","env","version");
      FileSeek(h,0,SEEK_END);
      int dg=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      FileWrite(h,pos_id,dir>0?"BUY":"SELL",DoubleToString(vol,2),OCL_MscToString(open_msc),OCL_MscToString(close_msc),
                DoubleToString((close_msc-open_msc)/1000.0,3),DoubleToString(entry,dg),DoubleToString(exit_price,dg),
                DoubleToString((exit_price-entry)*dir,dg),DoubleToString(gross,2),DoubleToString(commission,2),
                DoubleToString(swap,2),DoubleToString(gross+commission+swap,2),DoubleToString(entry_slip,dg),
                exit_reason,regime,strategy_tag,m_broker,m_env,OCL_VERSION);
      FileClose(h);
     }

   //--- small JSON snapshot read by the dashboard
   void              Status(const string json)
     {
      int h=FileOpen(m_dir+"\\status.json",FILE_WRITE|FILE_TXT|FILE_ANSI|(m_common?FILE_COMMON:0));
      if(h==INVALID_HANDLE) return;
      FileWriteString(h,json);
      FileClose(h);
     }
  };

#endif
