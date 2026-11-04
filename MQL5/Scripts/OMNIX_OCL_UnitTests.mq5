//+------------------------------------------------------------------+
//| OMNIX_OCL_UnitTests.mq5                                            |
//| Runs the shared OCLMath vectors inside MetaTrader 5.               |
//| Drag onto any chart; results go to the Experts tab and to          |
//| MQL5/Files/OMNIX_OCL/unit_test_results.txt                         |
//+------------------------------------------------------------------+
#property copyright "OMNIX Global AI"
#property version   "1.00"
#property script_show_inputs false

#include <OMNIX_OCL/OCLMath.mqh>

int g_pass=0,g_fail=0;
string g_report="";

void Record(const string name,const bool ok,const string detail)
  {
   if(ok) g_pass++; else { g_fail++; g_report+="FAIL "+name+" "+detail+"\n"; PrintFormat("FAIL %s %s",name,detail); }
  }
void CheckD(const string name,const double got,const double exp)
  { Record(name,MathAbs(got-exp)<1e-6,StringFormat("got=%.8f exp=%.8f",got,exp)); }
void CheckI(const string name,const long got,const long exp)
  { Record(name,got==exp,StringFormat("got=%I64d exp=%I64d",got,exp)); }
void CheckB(const string name,const bool got,const bool exp)
  { Record(name,got==exp,StringFormat("got=%s exp=%s",(string)got,(string)exp)); }

#include "OMNIX_OCL_TestVectors.mqh"

void OnStart()
  {
   OCL_RunVectorTests();
   // Observed bracket from the reference screenshot: Bid 4042.85 / Ask 4042.98, offset 0.97, SL 1.00
   double b=OCL_BuyStopPrice(4042.98,0.97,0.0,0.01), s=OCL_SellStopPrice(4042.85,0.97,0.0,0.01);
   CheckD("bracket.buy",b,4043.95);
   CheckD("bracket.sell",s,4041.88);
   CheckB("bracket.no_overlap",(b-1.0)>s,true);
   string summary=StringFormat("OMNIX OCL unit tests: %d passed, %d failed",g_pass,g_fail);
   Print(summary);
   int h=FileOpen("OMNIX_OCL\\unit_test_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE){ FileWriteString(h,summary+"\n"+g_report); FileClose(h); }
  }
