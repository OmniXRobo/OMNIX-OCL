//+------------------------------------------------------------------+
//| SessionNews.mqh - clock handling, session windows (Dubai time),    |
//| weekend/rollover protection and news blackout windows.             |
//+------------------------------------------------------------------+
#ifndef OMNIX_OCL_SESSIONNEWS_MQH
#define OMNIX_OCL_SESSIONNEWS_MQH

#include "Common.mqh"
#include "TradeLogger.mqh"

#define OCL_DUBAI_OFFSET (4*3600)   // Gulf Standard Time, UTC+4, no daylight saving

struct SOCLNewsEvent
  {
   datetime          utc;
   string            title;
   int               impact;    // 3 high, 2 medium, 1 low
   bool              is_fomc;
  };

class CSessionNews
  {
private:
   string            m_sym;
   int               m_base_offset_h;
   ENUM_OCL_DST_RULE m_dst;
   bool              m_tester;
   int               m_win_start,m_win_end;    // minutes of day, Dubai
   int               m_win2_start,m_win2_end;  // optional second window (-1 = off)
   int               m_friday_cutoff_min;      // Dubai minute on Friday after which no new entries
   int               m_monday_delay_min;       // minutes after the week's first quote
   int               m_rollover_guard_min;     // minutes either side of the server day change
   SOCLNewsEvent     m_news[];
   int               m_before_min,m_after_min,m_fomc_before_min,m_fomc_after_min;
   int               m_min_impact;
   datetime          m_last_cal_load;
   bool              m_use_mt5_calendar;
   string            m_file;

   static int        ParseHHMM(const string s)
     {
      string p[]; if(StringSplit(s,':',p)!=2) return 0;
      return (int)StringToInteger(p[0])*60+(int)StringToInteger(p[1]);
     }

public:
                     CSessionNews(void):m_last_cal_load(0) {}

   void              Init(const string sym,const int base_offset_h,const ENUM_OCL_DST_RULE dst,
                          const string win,const string win2,const string friday_cutoff,const int monday_delay,
                          const int rollover_guard,const string news_file,const bool use_mt5_cal,
                          const int before,const int after,const int fomc_before,const int fomc_after,
                          const int min_impact)
     {
      m_sym=sym; m_base_offset_h=base_offset_h; m_dst=dst; m_tester=(bool)MQLInfoInteger(MQL_TESTER);
      string p[];
      m_win_start=0; m_win_end=0;
      if(StringSplit(win,'-',p)==2){ m_win_start=ParseHHMM(p[0]); m_win_end=ParseHHMM(p[1]); }
      m_win2_start=-1; m_win2_end=-1;
      if(win2!="" && StringSplit(win2,'-',p)==2){ m_win2_start=ParseHHMM(p[0]); m_win2_end=ParseHHMM(p[1]); }
      m_friday_cutoff_min=(friday_cutoff=="")?-1:ParseHHMM(friday_cutoff);
      m_monday_delay_min=monday_delay; m_rollover_guard_min=rollover_guard;
      m_before_min=before; m_after_min=after; m_fomc_before_min=fomc_before; m_fomc_after_min=fomc_after;
      m_min_impact=min_impact; m_use_mt5_calendar=use_mt5_cal && !m_tester; m_file=news_file;
      LoadNewsFile();
     }

   //--- best available UTC. Live: terminal's GMT. Tester: server time minus configured offset.
   datetime          NowUTC(void) const
     {
      datetime srv=TimeCurrent();
      if(!m_tester) return TimeGMT();
      // first approximation, then refine with DST evaluated at that UTC
      datetime approx=srv-m_base_offset_h*3600;
      return srv-OCL_ServerOffsetSeconds(approx,m_base_offset_h,(int)m_dst);
     }
   int               ServerOffsetSeconds(void) const
     {
      if(!m_tester) return (int)(MathRound((double)(TimeTradeServer()-TimeGMT())/1800.0)*1800);
      return OCL_ServerOffsetSeconds(NowUTC(),m_base_offset_h,(int)m_dst);
     }
   int               DubaiMinute(void) const { return OCL_MinuteOfDay(NowUTC(),OCL_DUBAI_OFFSET); }

   //--- session gate; returns true when new entries are allowed, with a reason when not
   bool              SessionAllows(string &why) const
     {
      datetime utc=NowUTC();
      MqlDateTime dx; TimeToStruct(utc+OCL_DUBAI_OFFSET,dx);
      int m=dx.hour*60+dx.min;
      bool in1=OCL_InWindow(m,m_win_start,m_win_end);
      bool in2=(m_win2_start>=0 && OCL_InWindow(m,m_win2_start,m_win2_end));
      if(!in1 && !in2){ why="outside session window (Dubai "+StringFormat("%02d:%02d",dx.hour,dx.min)+")"; return false; }
      if(m_friday_cutoff_min>=0 && dx.day_of_week==5 && m>=m_friday_cutoff_min){ why="Friday cutoff"; return false; }
      // server rollover guard: spreads widen around the server day change
      MqlDateTime sv; TimeToStruct(TimeCurrent(),sv);
      int sm=sv.hour*60+sv.min;
      if(m_rollover_guard_min>0 && (sm<m_rollover_guard_min || sm>=1440-m_rollover_guard_min))
        { why="server rollover guard"; return false; }
      // market must be in a trading session per symbol spec (server time)
      datetime f,t; bool open=false;
      int secs=sv.hour*3600+sv.min*60+sv.sec;
      for(uint k=0;SymbolInfoSessionTrade(m_sym,(ENUM_DAY_OF_WEEK)sv.day_of_week,k,f,t);k++)
        {
         // t can be 24:00 (86400) for the end of the day
         if(secs>=(int)f && secs<(int)t){ open=true; break; }
        }
      if(!open){ why="symbol trade session closed (broker schedule)"; return false; }
      // delay after a session opens (Monday open, daily maintenance break)
      if(m_monday_delay_min>0)
        {
         for(uint k=0;SymbolInfoSessionTrade(m_sym,(ENUM_DAY_OF_WEEK)sv.day_of_week,k,f,t);k++)
            if(secs>=(int)f && secs<(int)f+m_monday_delay_min*60 && (int)f>0)
              { why="just after session open"; return false; }
         if(sv.day_of_week==1 && secs<m_monday_delay_min*60){ why="Monday open delay"; return false; }
        }
      return true;
     }

   //--- news: CSV in Common\Files\OMNIX_OCL\<file>, rows: YYYY.MM.DD HH:MM (UTC),currency,impact,title
   void              LoadNewsFile(void)
     {
      ArrayResize(m_news,0);
      if(m_file=="") return;
      int h=FileOpen("OMNIX_OCL\\"+m_file,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,',');
      if(h==INVALID_HANDLE){ PrintFormat("%s news: file %s not found in Common\\Files\\OMNIX_OCL (news filter uses MT5 calendar only)",OCL_PRODUCT,m_file); return; }
      while(!FileIsEnding(h))
        {
         string ts=FileReadString(h); if(FileIsEnding(h) && ts=="") break;
         string ccy=FileReadString(h), imp=FileReadString(h), title=FileReadString(h);
         while(!FileIsLineEnding(h) && !FileIsEnding(h)) title+=" "+FileReadString(h);
         if(StringFind(ts,"20")!=0) continue;             // header or junk
         if(ccy!="USD" && ccy!="ALL") continue;
         SOCLNewsEvent e; e.utc=StringToTime(ts); e.title=title; e.impact=(int)StringToInteger(imp);
         string up=title; StringToUpper(up);
         e.is_fomc=(StringFind(up,"FOMC")>=0 || StringFind(up,"FED INTEREST RATE")>=0 || StringFind(up,"FEDERAL FUNDS")>=0);
         int n=ArraySize(m_news); ArrayResize(m_news,n+1); m_news[n]=e;
        }
      FileClose(h);
      PrintFormat("%s news: %d USD events loaded from %s",OCL_PRODUCT,ArraySize(m_news),m_file);
     }

   //--- live only: pull high-impact USD events from the MT5 economic calendar every 30 min
   void              RefreshMT5Calendar(void)
     {
      if(!m_use_mt5_calendar) return;
      if(TimeCurrent()-m_last_cal_load<1800) return;
      m_last_cal_load=TimeCurrent();
      MqlCalendarValue vals[];
      datetime from=TimeTradeServer()-3600, to=TimeTradeServer()+86400;
      if(CalendarValueHistory(vals,from,to,NULL,"USD")<=0) return;
      int off=ServerOffsetSeconds();
      for(int i=0;i<ArraySize(vals);i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[i].event_id,ev)) continue;
         int imp=(ev.importance==CALENDAR_IMPORTANCE_HIGH)?3:((ev.importance==CALENDAR_IMPORTANCE_MODERATE)?2:1);
         if(imp<m_min_impact) continue;
         datetime utc=vals[i].time-off;                      // calendar times are server time
         bool dup=false;
         for(int k=0;k<ArraySize(m_news);k++) if(m_news[k].utc==utc && m_news[k].title==ev.name){ dup=true; break; }
         if(dup) continue;
         SOCLNewsEvent e; e.utc=utc; e.title=ev.name; e.impact=imp;
         string up=ev.name; StringToUpper(up);
         e.is_fomc=(StringFind(up,"FOMC")>=0 || StringFind(up,"FED INTEREST RATE")>=0);
         int n=ArraySize(m_news); ArrayResize(m_news,n+1); m_news[n]=e;
        }
     }

   //--- true if now is inside a blackout window; returns the event title
   bool              InBlackout(string &title) const
     {
      datetime utc=NowUTC();
      for(int i=0;i<ArraySize(m_news);i++)
        {
         if(m_news[i].impact<m_min_impact) continue;
         int b=(m_news[i].is_fomc?m_fomc_before_min:m_before_min)*60;
         int a=(m_news[i].is_fomc?m_fomc_after_min:m_after_min)*60;
         if(utc>=m_news[i].utc-b && utc<=m_news[i].utc+a){ title=m_news[i].title; return true; }
        }
      return false;
     }

   //--- next FOMC event time in UTC (0 if none known) for FOMC monitoring/logging
   datetime          NextFOMC(void) const
     {
      datetime utc=NowUTC(), best=0;
      for(int i=0;i<ArraySize(m_news);i++)
         if(m_news[i].is_fomc && m_news[i].utc>=utc && (best==0 || m_news[i].utc<best)) best=m_news[i].utc;
      return best;
     }
  };

#endif
