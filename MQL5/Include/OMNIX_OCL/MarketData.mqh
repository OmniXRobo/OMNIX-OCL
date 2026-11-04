//+------------------------------------------------------------------+
//| MarketData.mqh - tick buffer, spread statistics, multi-timeframe   |
//| indicators and volatility regime for OMNIX OCL.                    |
//| Only closed bars are read from indicators (shift >= 1) for any     |
//| filter, so there is no look-ahead in the Strategy Tester.          |
//+------------------------------------------------------------------+
#ifndef OMNIX_OCL_MARKETDATA_MQH
#define OMNIX_OCL_MARKETDATA_MQH

#include "Common.mqh"

#define OCL_TICKBUF 1024

class CMarketData
  {
private:
   string            m_sym;
   double            m_bid[OCL_TICKBUF];
   double            m_ask[OCL_TICKBUF];
   long              m_msc[OCL_TICKBUF];
   int               m_head;
   int               m_count;
   double            m_spread_ema;
   int               h_atr_m1,h_atr_m1_slow,h_ema_fast_m1,h_ema_slow_m1,h_ema_fast_m5,h_ema_slow_m5,
                     h_ema_fast_h1,h_ema_slow_h1,h_rsi_m1,h_adx_m5;
   ENUM_OCL_REGIME   m_regime;
   double            m_atr,m_atr_slow;

   double            Buf(const int h,const int shift) const
     {
      if(h==INVALID_HANDLE) return EMPTY_VALUE;
      double v[1];
      if(CopyBuffer(h,0,shift,1,v)!=1) return EMPTY_VALUE;
      return v[0];
     }

public:
   MqlTick           tick;
   double            spread;

                     CMarketData(void):m_head(0),m_count(0),m_spread_ema(0),m_regime(REGIME_UNKNOWN),
                                       m_atr(0),m_atr_slow(0),spread(0)
     {
      h_atr_m1=h_atr_m1_slow=h_ema_fast_m1=h_ema_slow_m1=h_ema_fast_m5=h_ema_slow_m5=INVALID_HANDLE;
      h_ema_fast_h1=h_ema_slow_h1=h_rsi_m1=h_adx_m5=INVALID_HANDLE;
     }
                    ~CMarketData(void) { Release(); }

   bool              Init(const string sym)
     {
      m_sym=sym;
      h_atr_m1      =iATR(sym,PERIOD_M1,14);
      h_atr_m1_slow =iATR(sym,PERIOD_M1,240);
      h_ema_fast_m1 =iMA(sym,PERIOD_M1,9,0,MODE_EMA,PRICE_CLOSE);
      h_ema_slow_m1 =iMA(sym,PERIOD_M1,34,0,MODE_EMA,PRICE_CLOSE);
      h_ema_fast_m5 =iMA(sym,PERIOD_M5,9,0,MODE_EMA,PRICE_CLOSE);
      h_ema_slow_m5 =iMA(sym,PERIOD_M5,34,0,MODE_EMA,PRICE_CLOSE);
      h_ema_fast_h1 =iMA(sym,PERIOD_H1,20,0,MODE_EMA,PRICE_CLOSE);
      h_ema_slow_h1 =iMA(sym,PERIOD_H1,50,0,MODE_EMA,PRICE_CLOSE);
      h_rsi_m1      =iRSI(sym,PERIOD_M1,14,PRICE_CLOSE);
      h_adx_m5      =iADX(sym,PERIOD_M5,14);
      return (h_atr_m1!=INVALID_HANDLE && h_atr_m1_slow!=INVALID_HANDLE);
     }

   void              Rel(int &h) { if(h!=INVALID_HANDLE) IndicatorRelease(h); h=INVALID_HANDLE; }
   void              Release(void)
     {
      Rel(h_atr_m1); Rel(h_atr_m1_slow); Rel(h_ema_fast_m1); Rel(h_ema_slow_m1); Rel(h_ema_fast_m5);
      Rel(h_ema_slow_m5); Rel(h_ema_fast_h1); Rel(h_ema_slow_h1); Rel(h_rsi_m1); Rel(h_adx_m5);
     }

   //--- call once per OnTick; returns false if no valid quote
   bool              Update(void)
     {
      if(!SymbolInfoTick(m_sym,tick) || tick.bid<=0 || tick.ask<=0) return false;
      spread=tick.ask-tick.bid;
      // store only when the quote changed (OnTick can fire for other reasons)
      int last=(m_head-1+OCL_TICKBUF)%OCL_TICKBUF;
      if(m_count==0 || m_bid[last]!=tick.bid || m_ask[last]!=tick.ask)
        {
         m_bid[m_head]=tick.bid; m_ask[m_head]=tick.ask; m_msc[m_head]=(long)tick.time_msc;
         m_head=(m_head+1)%OCL_TICKBUF; if(m_count<OCL_TICKBUF) m_count++;
         m_spread_ema=(m_spread_ema<=0)?spread:m_spread_ema+(spread-m_spread_ema)*0.02;
        }
      m_atr=Buf(h_atr_m1,1); m_atr_slow=Buf(h_atr_m1_slow,1);
      UpdateRegime();
      return true;
     }

   double            SpreadAvg(void) const { return m_spread_ema; }
   double            AtrM1(void) const { return (m_atr==EMPTY_VALUE)?0.0:m_atr; }
   double            AtrM1Slow(void) const { return (m_atr_slow==EMPTY_VALUE)?0.0:m_atr_slow; }
   ENUM_OCL_REGIME   Regime(void) const { return m_regime; }

   //--- high-low range of mid price over the last window_ms
   double            RangeMs(const int window_ms) const
     {
      if(m_count<2) return 0.0;
      long now=m_msc[(m_head-1+OCL_TICKBUF)%OCL_TICKBUF];
      double hi=-DBL_MAX,lo=DBL_MAX;
      for(int i=0;i<m_count;i++)
        {
         int k=(m_head-1-i+OCL_TICKBUF)%OCL_TICKBUF;
         if(now-m_msc[k]>window_ms) break;
         double mid=(m_bid[k]+m_ask[k])*0.5;
         hi=MathMax(hi,mid); lo=MathMin(lo,mid);
        }
      return (hi>lo)?hi-lo:0.0;
     }

   //--- signed mid-price change over the last window_ms (velocity proxy)
   double            ChangeMs(const int window_ms) const
     {
      if(m_count<2) return 0.0;
      int k0=(m_head-1+OCL_TICKBUF)%OCL_TICKBUF;
      long now=m_msc[k0];
      double cur=(m_bid[k0]+m_ask[k0])*0.5, past=cur;
      for(int i=1;i<m_count;i++)
        {
         int k=(m_head-1-i+OCL_TICKBUF)%OCL_TICKBUF;
         past=(m_bid[k]+m_ask[k])*0.5;
         if(now-m_msc[k]>=window_ms) break;
        }
      return cur-past;
     }

   //--- number of quote changes in the last window_ms (activity)
   int               TicksMs(const int window_ms) const
     {
      if(m_count<1) return 0;
      long now=m_msc[(m_head-1+OCL_TICKBUF)%OCL_TICKBUF];
      int n=0;
      for(int i=0;i<m_count;i++)
        {
         int k=(m_head-1-i+OCL_TICKBUF)%OCL_TICKBUF;
         if(now-m_msc[k]>window_ms) break;
         n++;
        }
      return n;
     }

   //--- +1 / -1 / 0 trend by EMA alignment on closed bars
   int               TrendM1(void) const { return Align(h_ema_fast_m1,h_ema_slow_m1); }
   int               TrendM5(void) const { return Align(h_ema_fast_m5,h_ema_slow_m5); }
   int               BiasH1(void)  const { return Align(h_ema_fast_h1,h_ema_slow_h1); }
   int               Align(const int hf,const int hs) const
     {
      double f=Buf(hf,1), s=Buf(hs,1);
      if(f==EMPTY_VALUE || s==EMPTY_VALUE) return 0;
      return (f>s)?1:((f<s)?-1:0);
     }
   double            RsiM1(void) const { return Buf(h_rsi_m1,1); }
   double            AdxM5(void) const { return Buf(h_adx_m5,1); }

   void              UpdateRegime(void)
     {
      if(m_atr<=0 || m_atr==EMPTY_VALUE || m_atr_slow<=0 || m_atr_slow==EMPTY_VALUE) { m_regime=REGIME_UNKNOWN; return; }
      double r=m_atr/m_atr_slow;
      m_regime=(r<0.6)?REGIME_QUIET:((r<1.4)?REGIME_NORMAL:((r<2.5)?REGIME_ACTIVE:REGIME_EXTREME));
     }
  };

#endif
