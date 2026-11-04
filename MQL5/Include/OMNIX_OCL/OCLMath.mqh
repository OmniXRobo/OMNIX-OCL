//+------------------------------------------------------------------+
//| OCLMath.mqh - pure, side-effect-free helpers for OMNIX OCL         |
//| Every function here is mirrored in tests/python/ocl_reference.py   |
//| and checked against the shared vectors in tests/vectors.json.      |
//+------------------------------------------------------------------+
#ifndef OMNIX_OCL_MATH_MQH
#define OMNIX_OCL_MATH_MQH

//--- round a price to the symbol's tick size (nearest)
double OCL_RoundToTick(const double price,const double tick_size)
  {
   if(tick_size<=0.0) return price;
   return MathRound(price/tick_size)*tick_size;
  }

//--- floor a volume to the volume step and clamp to [vmin,vmax]; 0 if below vmin
double OCL_NormalizeVolume(const double volume,const double vmin,const double vmax,const double vstep)
  {
   if(vstep<=0.0 || volume<vmin-1e-9) return 0.0;
   double steps=MathFloor((volume+1e-9)/vstep);
   double v=steps*vstep;
   if(v>vmax) v=MathFloor((vmax+1e-9)/vstep)*vstep;
   if(v<vmin-1e-9) return 0.0;
   return NormalizeDouble(v,8);
  }

//--- money moved per 1.0 price unit per 1.0 lot (e.g. 100 USD for 100 oz gold)
double OCL_MoneyPerPricePerLot(const double tick_value,const double tick_size)
  {
   if(tick_size<=0.0) return 0.0;
   return tick_value/tick_size;
  }

//--- lots so that a stop of stop_dist price units loses risk_money (before costs)
//    cost_per_lot is the round-turn commission per lot; it is included in the risk
double OCL_LotsForRisk(const double risk_money,const double stop_dist,const double money_per_price_lot,
                       const double cost_per_lot,const double vmin,const double vmax,const double vstep)
  {
   if(risk_money<=0.0 || stop_dist<=0.0 || money_per_price_lot<=0.0) return 0.0;
   double loss_per_lot=stop_dist*money_per_price_lot+MathMax(cost_per_lot,0.0);
   return OCL_NormalizeVolume(risk_money/loss_per_lot,vmin,vmax,vstep);
  }

//--- minimum legal distance between a pending/stop price and current price
double OCL_MinStopDistance(const int stops_level_points,const int freeze_level_points,
                           const double point,const double buffer_price)
  {
   int lvl=(int)MathMax(stops_level_points,freeze_level_points);
   return lvl*point+MathMax(buffer_price,0.0);
  }

//--- Buy Stop entry: at least min_dist above Ask
double OCL_BuyStopPrice(const double ask,const double offset,const double min_dist,const double tick)
  {
   double p=ask+MathMax(offset,min_dist);
   p=OCL_RoundToTick(p,tick);
   if(p-ask<min_dist-1e-9) p=OCL_RoundToTick(p+tick,tick);
   return p;
  }

//--- Sell Stop entry: at least min_dist below Bid
double OCL_SellStopPrice(const double bid,const double offset,const double min_dist,const double tick)
  {
   double p=bid-MathMax(offset,min_dist);
   p=OCL_RoundToTick(p,tick);
   if(bid-p<min_dist-1e-9) p=OCL_RoundToTick(p-tick,tick);
   return p;
  }

//--- Trailing stop candidate. dir=+1 long, -1 short. Returns 0 if no move is warranted.
//    Long: SL = bid - trail once (bid-entry) >= activation; only moves up by >= step.
double OCL_TrailCandidate(const int dir,const double entry,const double bid,const double ask,
                          const double current_sl,const double activation,const double trail,
                          const double step,const double min_dist,const double tick)
  {
   if(trail<=0.0) return 0.0;
   if(dir>0)
     {
      if(bid-entry<activation-1e-9) return 0.0;
      double sl=OCL_RoundToTick(bid-MathMax(trail,min_dist),tick);
      if(bid-sl<min_dist-1e-9) sl=OCL_RoundToTick(sl-tick,tick);
      if(current_sl>0.0 && sl<current_sl+step-1e-9) return 0.0;
      return sl;
     }
   if(entry-ask<activation-1e-9) return 0.0;
   double s=OCL_RoundToTick(ask+MathMax(trail,min_dist),tick);
   if(s-ask<min_dist-1e-9) s=OCL_RoundToTick(s+tick,tick);
   if(current_sl>0.0 && s>current_sl-step+1e-9) return 0.0;
   return s;
  }

//--- Break-even SL: entry plus enough to cover round-turn costs plus an offset.
//    Returns 0 if trigger not reached or SL already at/through the target.
double OCL_BreakEvenCandidate(const int dir,const double entry,const double bid,const double ask,
                              const double current_sl,const double trigger,const double offset,
                              const double cost_price,const double min_dist,const double tick)
  {
   if(dir>0)
     {
      if(bid-entry<trigger-1e-9) return 0.0;
      double sl=OCL_RoundToTick(entry+cost_price+offset,tick);
      if(bid-sl<min_dist-1e-9) return 0.0;
      if(current_sl>0.0 && current_sl>=sl-1e-9) return 0.0;
      return sl;
     }
   if(entry-ask<trigger-1e-9) return 0.0;
   double s=OCL_RoundToTick(entry-cost_price-offset,tick);
   if(s-ask<min_dist-1e-9) return 0.0;
   if(current_sl>0.0 && current_sl<=s+1e-9) return 0.0;
   return s;
  }

//--- round-turn commission per lot expressed as a price distance
double OCL_CostAsPrice(const double commission_rt_per_lot,const double money_per_price_lot)
  {
   if(money_per_price_lot<=0.0) return 0.0;
   return commission_rt_per_lot/money_per_price_lot;
  }

//--- days in a Gregorian month
int OCL_DaysInMonth(const int year,const int month)
  {
   if(month==2) return ((year%4==0 && year%100!=0) || year%400==0)?29:28;
   if(month==4 || month==6 || month==9 || month==11) return 30;
   return 31;
  }

//--- day of month of the n-th (1-based) given weekday (0=Sun) in a month; n=-1 means last
int OCL_NthWeekdayOfMonth(const int year,const int month,const int weekday,const int n)
  {
   MqlDateTime d; ZeroMemory(d); d.year=year; d.mon=month; d.day=1;
   datetime first=StructToTime(d);
   MqlDateTime f; TimeToStruct(first,f);
   int day=1+((weekday-f.day_of_week+7)%7);
   if(n>0) return day+7*(n-1);
   int dim=OCL_DaysInMonth(year,month);
   while(day+7<=dim) day+=7;
   return day;
  }

//--- 0 none, 1 US (2nd Sun Mar 02:00 local .. 1st Sun Nov 02:00), 2 EU (last Sun Mar 01:00 UTC .. last Sun Oct 01:00 UTC)
//    utc is a UTC timestamp. Returns true when DST is in force for that rule.
bool OCL_IsDST(const datetime utc,const int rule)
  {
   if(rule==0) return false;
   MqlDateTime u; TimeToStruct(utc,u);
   MqlDateTime s; ZeroMemory(s); MqlDateTime e; ZeroMemory(e);
   s.year=u.year; e.year=u.year;
   if(rule==1)
     {
      // US Eastern: 02:00 EST = 07:00 UTC start; 02:00 EDT = 06:00 UTC end
      s.mon=3;  s.day=OCL_NthWeekdayOfMonth(u.year,3,0,2);  s.hour=7;
      e.mon=11; e.day=OCL_NthWeekdayOfMonth(u.year,11,0,1); e.hour=6;
     }
   else
     {
      s.mon=3;  s.day=OCL_NthWeekdayOfMonth(u.year,3,0,-1);  s.hour=1;
      e.mon=10; e.day=OCL_NthWeekdayOfMonth(u.year,10,0,-1); e.hour=1;
     }
   datetime ds=StructToTime(s), de=StructToTime(e);
   return (utc>=ds && utc<de);
  }

//--- server UTC offset in seconds given base hours and DST rule (DST adds 1 hour)
int OCL_ServerOffsetSeconds(const datetime utc,const int base_hours,const int dst_rule)
  {
   return (base_hours+(OCL_IsDST(utc,dst_rule)?1:0))*3600;
  }

//--- minutes since midnight in a fixed-offset zone (Dubai = +4h, no DST)
int OCL_MinuteOfDay(const datetime utc,const int zone_offset_seconds)
  {
   MqlDateTime d; TimeToStruct(utc+zone_offset_seconds,d);
   return d.hour*60+d.min;
  }

//--- window [start,end) in minutes of day; supports windows crossing midnight. start==end means 24h.
bool OCL_InWindow(const int minute,const int start_min,const int end_min)
  {
   if(start_min==end_min) return true;
   if(start_min<end_min) return (minute>=start_min && minute<end_min);
   return (minute>=start_min || minute<end_min);
  }

//--- score how likely a symbol name is spot gold vs USD (0 = not gold)
int OCL_GoldNameScore(const string raw_name)
  {
   string n=raw_name; StringToUpper(n);
   if(StringFind(n,"XAUUSD")==0)  return (StringLen(n)==6)?100:90;
   if(StringFind(n,"XAUUSD")>0)   return 70;
   if(n=="GOLD")                  return 80;
   if(StringFind(n,"GOLD")==0 && StringFind(n,"EUR")<0 && StringFind(n,"AUD")<0 && StringFind(n,"GBP")<0
      && StringFind(n,"JPY")<0 && StringFind(n,"CHF")<0 && StringFind(n,"FUT")<0) return 60;
   return 0;
  }

#endif
