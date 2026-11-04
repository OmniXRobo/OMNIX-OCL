//+------------------------------------------------------------------+
//| OMNIX_OCL_ExportHistory.mq5                                        |
//| Read-only. Exports the account's order and deal history to CSV so  |
//| research/reconstruct_lifecycle.py can rebuild every order's life.  |
//| It never sends, modifies or cancels anything.                      |
//|                                                                    |
//| Output (MQL5/Files/OMNIX_OCL/):                                    |
//|   history_orders.csv, history_deals.csv                            |
//| For each order it also looks up the market tick at the moment the  |
//| order was set up, so placement distance from Bid/Ask is measurable.|
//+------------------------------------------------------------------+
#property copyright "OMNIX Global AI"
#property version   "1.00"
#property script_show_inputs

input datetime InpFrom          = D'2026.10.01 00:00';
input datetime InpTo            = D'2030.01.01 00:00';
input string   InpCommentFilter = "";      // e.g. "HexaFX" ; empty = all
input string   InpSymbolFilter  = "";      // empty = all symbols
input bool     InpLookupTicks   = true;    // fetch Bid/Ask at order setup time (slower)

string Csv(string s){ StringReplace(s,",",";"); StringReplace(s,"\n"," "); return s; }

bool TickAt(const string sym,const long msc,double &bid,double &ask)
  {
   bid=0; ask=0;
   MqlTick t[];
   // last tick at or before msc, searching back up to 60 s
   int n=CopyTicksRange(sym,t,COPY_TICKS_INFO,(ulong)MathMax(0,msc-60000),(ulong)msc);
   if(n<=0) return false;
   bid=t[n-1].bid; ask=t[n-1].ask;
   return true;
  }

void OnStart()
  {
   if(!HistorySelect(InpFrom,InpTo)){ Print("HistorySelect failed"); return; }
   FolderCreate("OMNIX_OCL");

   //--- orders
   int ho=FileOpen("OMNIX_OCL\\history_orders.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(ho==INVALID_HANDLE){ Print("cannot open orders file ",GetLastError()); return; }
   FileWrite(ho,"ticket","symbol","type","state","reason","magic","position_id","position_by_id",
             "time_setup_msc","time_done_msc","time_expiration","volume_initial","volume_current",
             "price_open","price_current","sl","tp","type_filling","type_time","comment",
             "bid_at_setup","ask_at_setup");
   int total=HistoryOrdersTotal(), kept=0;
   for(int i=0;i<total;i++)
     {
      ulong tk=HistoryOrderGetTicket(i); if(tk==0) continue;
      string sym=HistoryOrderGetString(tk,ORDER_SYMBOL), cm=HistoryOrderGetString(tk,ORDER_COMMENT);
      if(InpSymbolFilter!="" && sym!=InpSymbolFilter) continue;
      if(InpCommentFilter!="" && StringFind(cm,InpCommentFilter)<0) continue;
      long setup=HistoryOrderGetInteger(tk,ORDER_TIME_SETUP_MSC);
      double bid=0,ask=0;
      if(InpLookupTicks) TickAt(sym,setup,bid,ask);
      FileWrite(ho,tk,sym,
                EnumToString((ENUM_ORDER_TYPE)HistoryOrderGetInteger(tk,ORDER_TYPE)),
                EnumToString((ENUM_ORDER_STATE)HistoryOrderGetInteger(tk,ORDER_STATE)),
                EnumToString((ENUM_ORDER_REASON)HistoryOrderGetInteger(tk,ORDER_REASON)),
                HistoryOrderGetInteger(tk,ORDER_MAGIC),
                HistoryOrderGetInteger(tk,ORDER_POSITION_ID),
                HistoryOrderGetInteger(tk,ORDER_POSITION_BY_ID),
                setup,HistoryOrderGetInteger(tk,ORDER_TIME_DONE_MSC),
                HistoryOrderGetInteger(tk,ORDER_TIME_EXPIRATION),
                DoubleToString(HistoryOrderGetDouble(tk,ORDER_VOLUME_INITIAL),2),
                DoubleToString(HistoryOrderGetDouble(tk,ORDER_VOLUME_CURRENT),2),
                DoubleToString(HistoryOrderGetDouble(tk,ORDER_PRICE_OPEN),5),
                DoubleToString(HistoryOrderGetDouble(tk,ORDER_PRICE_CURRENT),5),
                DoubleToString(HistoryOrderGetDouble(tk,ORDER_SL),5),
                DoubleToString(HistoryOrderGetDouble(tk,ORDER_TP),5),
                EnumToString((ENUM_ORDER_TYPE_FILLING)HistoryOrderGetInteger(tk,ORDER_TYPE_FILLING)),
                EnumToString((ENUM_ORDER_TYPE_TIME)HistoryOrderGetInteger(tk,ORDER_TYPE_TIME)),
                Csv(cm),DoubleToString(bid,5),DoubleToString(ask,5));
      kept++;
     }
   FileClose(ho);

   //--- deals
   int hd=FileOpen("OMNIX_OCL\\history_deals.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(hd==INVALID_HANDLE){ Print("cannot open deals file ",GetLastError()); return; }
   FileWrite(hd,"ticket","order","position_id","symbol","type","entry","reason","magic","time_msc",
             "volume","price","sl","tp","profit","commission","swap","fee","comment");
   int dt=HistoryDealsTotal(), dk=0;
   for(int j=0;j<dt;j++)
     {
      ulong d=HistoryDealGetTicket(j); if(d==0) continue;
      string sym=HistoryDealGetString(d,DEAL_SYMBOL), cm=HistoryDealGetString(d,DEAL_COMMENT);
      if(InpSymbolFilter!="" && sym!=InpSymbolFilter) continue;
      // exit deals often carry a different comment ([sl ...]); keep them, the Python side joins by position_id
      FileWrite(hd,d,HistoryDealGetInteger(d,DEAL_ORDER),HistoryDealGetInteger(d,DEAL_POSITION_ID),sym,
                EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(d,DEAL_TYPE)),
                EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY)),
                EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(d,DEAL_REASON)),
                HistoryDealGetInteger(d,DEAL_MAGIC),HistoryDealGetInteger(d,DEAL_TIME_MSC),
                DoubleToString(HistoryDealGetDouble(d,DEAL_VOLUME),2),
                DoubleToString(HistoryDealGetDouble(d,DEAL_PRICE),5),
                DoubleToString(HistoryDealGetDouble(d,DEAL_SL),5),
                DoubleToString(HistoryDealGetDouble(d,DEAL_TP),5),
                DoubleToString(HistoryDealGetDouble(d,DEAL_PROFIT),2),
                DoubleToString(HistoryDealGetDouble(d,DEAL_COMMISSION),2),
                DoubleToString(HistoryDealGetDouble(d,DEAL_SWAP),2),
                DoubleToString(HistoryDealGetDouble(d,DEAL_FEE),2),Csv(cm));
      dk++;
     }
   FileClose(hd);
   PrintFormat("OMNIX OCL export: %d orders, %d deals written to MQL5\\Files\\OMNIX_OCL\\",kept,dk);
  }
