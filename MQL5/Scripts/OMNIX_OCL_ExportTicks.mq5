//+------------------------------------------------------------------+
//| OMNIX_OCL_ExportTicks.mq5                                          |
//| Read-only. Exports real Bid/Ask ticks of one symbol to CSV, one    |
//| file per day, for the offline research simulator                  |
//| (research/tick_sim.py). It never sends, modifies or cancels.       |
//|                                                                    |
//| Output (MQL5/Files/OMNIX_OCL/ticks/): <symbol>_YYYYMMDD.csv        |
//|   time_msc,bid,ask                                                 |
//+------------------------------------------------------------------+
#property copyright "OMNIX Global AI"
#property version   "1.00"
#property script_show_inputs

input string   InpSymbol = "";                       // empty = chart symbol
input datetime InpFrom   = D'2026.08.01 00:00';
input datetime InpTo     = D'2026.11.05 00:00';

void OnStart()
  {
   string sym=(InpSymbol=="")?_Symbol:InpSymbol;
   FolderCreate("OMNIX_OCL\\ticks");
   long total=0;
   for(datetime d=InpFrom; d<InpTo; d+=86400)
     {
      MqlTick t[];
      ulong from=(ulong)d*1000, to=(ulong)(d+86400)*1000-1;
      int n=-1;
      for(int attempt=0;attempt<5 && n<0;attempt++)
        {
         n=CopyTicksRange(sym,t,COPY_TICKS_INFO,from,to);
         if(n<0) Sleep(2000);   // history still synchronising
        }
      if(n<=0) continue;
      MqlDateTime md; TimeToStruct(d,md);
      string fn=StringFormat("OMNIX_OCL\\ticks\\%s_%04d%02d%02d.csv",sym,md.year,md.mon,md.day);
      int h=FileOpen(fn,FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h==INVALID_HANDLE){ PrintFormat("cannot open %s",fn); continue; }
      int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
      FileWriteString(h,"time_msc,bid,ask\n");
      for(int i=0;i<n;i++)
         FileWriteString(h,StringFormat("%I64d,%s,%s\n",t[i].time_msc,DoubleToString(t[i].bid,dg),DoubleToString(t[i].ask,dg)));
      FileClose(h);
      total+=n;
      PrintFormat("OMNIX OCL ticks %s %04d-%02d-%02d: %d",sym,md.year,md.mon,md.day,n);
     }
   PrintFormat("OMNIX OCL tick export done: %I64d ticks",total);
  }
