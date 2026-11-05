//+------------------------------------------------------------------+
//| OMNIX_OCL.mq5                                                      |
//| OMNIX OCL - Order Control & Liquidity                              |
//| Powered by OMNIX Global AI                                         |
//|                                                                    |
//| Tick-driven XAUUSD stop-bracket scalper with configurable OCO,     |
//| re-arm, exit and sizing variants. DEMO / STRATEGY TESTER ONLY.     |
//+------------------------------------------------------------------+
#property copyright   "OMNIX Global AI"
#property version     "0.300"
#property description "OMNIX OCL - Order Control & Liquidity. Demo and Strategy Tester only."

#include <OMNIX_OCL/Common.mqh>
#include <OMNIX_OCL/TradeLogger.mqh>
#include <OMNIX_OCL/BrokerProfile.mqh>
#include <OMNIX_OCL/MarketData.mqh>
#include <OMNIX_OCL/SessionNews.mqh>
#include <OMNIX_OCL/RiskManager.mqh>
#include <OMNIX_OCL/ExecutionEngine.mqh>
#include <OMNIX_OCL/SignalEngine.mqh>
#include <OMNIX_OCL/PendingOrders.mqh>
#include <OMNIX_OCL/PositionManager.mqh>

//==================== inputs ====================
input group "=== Identity ==="
input long     InpMagic               = 20261104;      // Magic number
input string   InpSymbolOverride      = "";            // Gold symbol override (empty = auto-discover)
input string   InpStrategyTag         = "baseline";    // Strategy label written to every trade row

input group "=== Entry bracket ==="
input ENUM_OCL_DIST_MODE    InpDistMode      = DIST_FIXED;   // Entry distance mode
input double   InpOffsetFixed         = 0.95;          // Fixed offset from Ask/Bid ($)
input double   InpOffsetSpreadK       = 1.0;           // Spread-scaled: offset = fixed + k*spread
input double   InpOffsetAtrK          = 0.8;           // ATR mode: offset = k*ATR(M1)
input double   InpOffsetRangeK        = 0.6;           // Tick-range mode: offset = k*range(window)
input int      InpRangeWindowMs       = 30000;         // Tick-range window (ms)
input double   InpOffsetMin           = 0.30;          // Offset floor ($)
input double   InpOffsetMax           = 3.00;          // Offset cap ($)
input double   InpSLFixed             = 1.00;          // Initial stop-loss distance ($)
input double   InpSLAtrK              = 0.0;           // >0: SL = max(fixed, k*ATR(M1))
input ENUM_OCL_ARM_SIDES    InpArmSides      = ARM_BOTH;     // Which sides to arm

input group "=== Pending order management ==="
input ENUM_OCL_PENDING_MODE InpPendingMode   = PEND_FOLLOW_MODIFY; // Static / follow by modify / follow by replace
input ENUM_OCL_FOLLOW_DIR   InpFollowDir     = FOLLOW_TIGHTEN_ONLY;// Follow direction
input double   InpFollowStep          = 0.10;          // Price drift that triggers a follow ($)
input int      InpFollowMinMs         = 1000;          // Min ms between follows of one order
input int      InpFollowMaxPerMin     = 30;            // Max follow requests per minute
input int      InpPendingLifetimeS    = 300;           // Cancel unfilled orders after (s), 0 = never
input bool     InpBrokerExpiry        = false;         // Also set broker-side expiry where supported
input ENUM_OCL_OCO_MODE     InpOcoMode       = OCO_CANCEL_ON_FILL; // Opposite-order policy
input double   InpStopBuffer          = 0.02;          // Extra $ beyond broker stop/freeze levels

input group "=== Re-entry ==="
input ENUM_OCL_REARM_MODE   InpRearmMode     = REARM_SPREAD; // Re-arm policy after a close
input int      InpRearmCooldownS      = 0;             // Minimum wait after a close (s)
input double   InpRearmSpreadK        = 1.5;           // Spread mode: spread <= k * average
input double   InpRearmRangeMin       = 0.40;          // Volatility mode: min range in window ($)
input double   InpRearmRangeMax       = 6.00;          // Volatility mode: max range in window ($)
input int      InpMomentumWindowMs    = 5000;          // Momentum window (ms)
input double   InpMomentumMin         = 0.30;          // Momentum threshold ($ over window)

input group "=== Filters (optional) ==="
input bool     InpUseAtrFilter        = false;         // Use ATR(M1) band
input double   InpAtrMin              = 0.30;          // ATR(M1) min ($)
input double   InpAtrMax              = 6.00;          // ATR(M1) max ($)
input bool     InpBlockExtremeRegime  = true;          // Do not arm in extreme volatility regime
input bool     InpUseRsiFilter        = false;         // Use RSI(M1) band
input double   InpRsiLow              = 20;            // RSI low
input double   InpRsiHigh             = 80;            // RSI high
input bool     InpUseAdxFilter        = false;         // Use ADX(M5) minimum
input double   InpAdxMin              = 18;            // ADX min

input group "=== Exit ==="
input ENUM_OCL_EXIT_PROFILE InpExitProfile   = EXIT_B_TRAIL; // Exit variant A-F (Custom uses the switches below)
input bool     InpUseTrailing         = true;          // Custom: trailing stop
input double   InpTrailActivation     = 0.30;          // Trailing activation: favourable move ($)
input double   InpTrailDistance       = 0.15;          // Trailing distance ($)
input double   InpTrailStep           = 0.05;          // Minimum SL improvement per modify ($)
input bool     InpUseBreakEven        = false;         // Custom: break-even
input double   InpBETrigger           = 0.30;          // Break-even trigger ($)
input double   InpBEOffset            = 0.02;          // Break-even offset beyond costs ($)
input bool     InpUseMicroProfit      = false;         // Custom: micro-profit close
input double   InpMicroProfitUSD      = 3.00;          // Close at this NET floating profit (account ccy)
input bool     InpUseTimeExit         = false;         // Custom: time exit
input int      InpMaxHoldS            = 180;           // Max holding time (s)
input ENUM_OCL_TIME_EXIT    InpTimeExitRule  = TIMEEXIT_IF_NOT_PROFITABLE; // Time-exit rule
input double   InpAdaptiveTrailK      = 0.5;           // Adaptive: trail = k * range(momentum window)
input double   InpAdaptiveMinTrail    = 0.10;          // Adaptive: minimum trail ($)
input int      InpSLMinModifyMs       = 500;           // Min ms between SL modifies (raised to 2x measured latency)
input double   InpLatencyPadPerSec    = 0.30;          // Extra SL gap ($) per second of order latency (0 = off)

input group "=== Position sizing ==="
input ENUM_OCL_LOT_MODE     InpLotMode       = LOT_FIXED;    // Fixed / risk-based / adaptive
input double   InpFixedLots           = 0.01;          // Fixed lots
input double   InpRiskPct             = 0.50;          // Risk per trade (% equity) for risk/adaptive
input double   InpMaxRiskPct          = 1.00;          // Hard cap risk per trade (% equity), all modes
input double   InpAdaptiveMaxLots     = 0.50;          // Adaptive mode lot ceiling
input double   InpCommissionRTPerLot  = 6.00;          // Round-turn commission per lot (until learned from deals)
input double   InpSimCommissionRTPerLot = 0.0;         // If the broker charges 0 (tester/some demos): book this RT commission per lot in logs, risk and OnTester

input group "=== Risk limits ==="
input double   InpMaxDailyLossPct     = 3.0;           // Max daily loss (% of day-start balance)
input double   InpMaxDailyDDPct       = 4.0;           // Max daily drawdown from day's equity peak (%)
input double   InpMaxWeeklyDDPct      = 8.0;           // Max weekly drawdown (%)
input double   InpMaxSpread           = 0.40;          // Max spread ($)
input double   InpMaxSpreadVsAvg      = 2.5;           // Max spread as multiple of average
input double   InpMaxSlippage         = 0.30;          // Max average entry slippage ($) before pausing
input int      InpDeviationPoints     = 30;            // Max deviation for market closes (points)
input int      InpMaxPositions        = 1;             // Max concurrent positions
input int      InpMaxPending          = 2;             // Max pending orders
input int      InpMaxTradesPerHour    = 0;             // Max entries per hour (0 = off)
input int      InpMaxConsecLosses     = 0;             // Consecutive losses before pause (0 = off)
input int      InpConsecLossPauseMin  = 30;            // Pause length (min)
input double   InpMaxRejectRate       = 0.5;           // Max order rejection rate (last 20)
input double   InpMaxAccountLots      = 1.0;           // Max total open lots on the account
input double   InpMinFreeMargin       = 100;           // Min free margin after order (account ccy)
input double   InpMinMarginLevel      = 300;           // Min margin level (%)
input double   InpMaxDailyCommission  = 0;             // Daily commission budget (0 = off)
input bool     InpEmergencyStop       = false;         // EMERGENCY STOP: flatten and stop

input group "=== Sessions (Dubai time, UTC+4) ==="
input string   InpSessionDubai        = "00:00-00:00"; // Main window HH:MM-HH:MM (equal = 24h)
input string   InpSession2Dubai       = "";            // Optional second window
input string   InpFridayCutoffDubai   = "23:30";       // No new entries on Friday after (Dubai)
input int      InpSessionOpenDelayMin = 5;             // Wait after a session opens (min)
input int      InpRolloverGuardMin    = 10;            // Avoid +/- N min around server midnight
input int      InpServerUTCOffsetH    = 2;             // Tester only: server base UTC offset (h)
input ENUM_OCL_DST_RULE     InpServerDST     = DST_US;       // Tester only: server DST rule

input group "=== News ==="
input string   InpNewsFile            = "news_calendar.csv"; // Common\Files\OMNIX_OCL\ CSV (UTC)
input bool     InpUseMT5Calendar      = true;          // Live/demo: also use the MT5 economic calendar
input ENUM_OCL_NEWS_ACTION  InpNewsAction    = NEWS_MONITOR_ONLY; // Action inside a blackout (monitor = log only, keep trading)
input double   InpNewsLotFactor       = 0.5;           // Reduced-risk factor
input int      InpNewsBeforeMin       = 15;            // Blackout before event (min)
input int      InpNewsAfterMin        = 15;            // Blackout after event (min)
input int      InpFomcBeforeMin       = 30;            // FOMC: before (min)
input int      InpFomcAfterMin        = 60;            // FOMC: after (min)
input int      InpNewsMinImpact       = 3;             // 3 = high impact only
input double   InpCircuitRange60s     = 8.0;           // Circuit breaker: 60s range above this ($) pauses
input int      InpCircuitPauseMin     = 10;            // Circuit breaker pause (min)

input group "=== Logging ==="
input bool     InpLogCommon           = true;          // Write logs to Common\Files (dashboard reads there)
input bool     InpLogTicks            = false;         // Log every processed tick (large files)
input int      InpStatusEverySec      = 2;             // status.json refresh (live)

//==================== globals ====================
CTradeLogger      g_log;
CBrokerProfile    g_bp;
CMarketData       g_md;
CSessionNews      g_sn;
CRiskManager      g_risk;
CExecutionEngine  g_ex;
CSignalEngine     g_sig;
CPendingOrders    g_pend;
CPositionManager  g_pos;

datetime          g_last_close=0;
datetime          g_circuit_until=0;
string            g_last_wait="";
long              g_last_tick_msc=0;
ulong             g_last_process_ms=0;
datetime          g_last_status=0;
bool              g_tester=false;
double            g_sim_commission_total=0;   // simulated commission booked (negative)
double            g_closed_lots=0;

// open-position bookkeeping for slippage and duration (small fixed table)
#define OCL_TRACK 16
ulong  g_trk_pos[OCL_TRACK];
long   g_trk_open_msc[OCL_TRACK];
double g_trk_req[OCL_TRACK];
double g_trk_slip[OCL_TRACK];
string g_trk_regime[OCL_TRACK];
int    g_trk_next=0;

//==================== helpers ====================
void ResolveExit(SOCLExitConfig &e)
  {
   e.use_trailing=InpUseTrailing; e.trail_activation=InpTrailActivation; e.trail_distance=InpTrailDistance;
   e.trail_step=InpTrailStep; e.use_breakeven=InpUseBreakEven; e.be_trigger=InpBETrigger; e.be_offset=InpBEOffset;
   e.use_microprofit=InpUseMicroProfit; e.micro_profit_usd=InpMicroProfitUSD; e.use_time_exit=InpUseTimeExit;
   e.max_hold_seconds=InpMaxHoldS; e.time_exit_rule=InpTimeExitRule; e.adaptive=false;
   e.adaptive_trail_k=InpAdaptiveTrailK; e.adaptive_min_trail=InpAdaptiveMinTrail;
   if(InpExitProfile==EXIT_CUSTOM) return;
   e.use_trailing=false; e.use_breakeven=false; e.use_microprofit=false; e.use_time_exit=false;
   switch(InpExitProfile)
     {
      case EXIT_A_FIXED:       break;
      case EXIT_B_TRAIL:       e.use_trailing=true; break;
      case EXIT_C_BREAKEVEN:   e.use_breakeven=true; break;
      case EXIT_D_MICROPROFIT: e.use_microprofit=true; break;
      case EXIT_E_TIME:        e.use_time_exit=true; break;
      case EXIT_F_ADAPTIVE:    e.adaptive=true; e.use_breakeven=true; e.use_time_exit=true; break;
      default: break;
     }
  }

string ExitProfileName(void)
  {
   string n=EnumToString(InpExitProfile); StringReplace(n,"EXIT_",""); return n;
  }

void LogWait(const string why)
  {
   if(why==g_last_wait) return;          // log state changes, not every tick
   g_last_wait=why;
   g_log.Event("WAIT",why);
  }

void Track(const ulong pos,const long open_msc,const double req,const double slip,const string regime)
  {
   int k=g_trk_next; g_trk_next=(g_trk_next+1)%OCL_TRACK;
   g_trk_pos[k]=pos; g_trk_open_msc[k]=open_msc; g_trk_req[k]=req; g_trk_slip[k]=slip; g_trk_regime[k]=regime;
  }
int TrackFind(const ulong pos) { for(int i=0;i<OCL_TRACK;i++) if(g_trk_pos[i]==pos) return i; return -1; }

void Flatten(const string why)
  {
   g_pend.CancelAll(why);
   g_pos.CloseAll(why);
  }

//==================== lifecycle ====================
int OnInit()
  {
   g_tester=(bool)MQLInfoInteger(MQL_TESTER);

   //--- live-money guard: demo accounts and the Strategy Tester only
   ENUM_ACCOUNT_TRADE_MODE tm=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(!g_tester && tm!=ACCOUNT_TRADE_MODE_DEMO && !OCL_LIVE_TRADING_ALLOWED)
     {
      Alert(OCL_PRODUCT," refuses to run: this is not a demo account. Live trading is disabled by design.");
      return INIT_FAILED;
     }

   //--- symbol discovery and broker profile
   string rep;
   string sym=CBrokerProfile::Discover(InpSymbolOverride,_Symbol,rep);
   if(sym==""){ Alert(OCL_PRODUCT,": no gold symbol found. ",rep); return INIT_FAILED; }
   if(sym!=_Symbol)
      PrintFormat("%s: chart is %s but gold symbol is %s (%s). Attach the EA to a %s chart for best tick timing.",
                  OCL_PRODUCT,_Symbol,sym,rep,sym);
   if(!g_log.Init(sym,InpLogCommon && !g_tester,InpLogTicks)) return INIT_FAILED;
   string why;
   if(!g_bp.Load(sym,InpCommissionRTPerLot,why))
     {
      g_log.Event("INIT_REJECT",why);
      Alert(OCL_PRODUCT,": unsupported configuration: ",why);
      return INIT_FAILED;
     }
   g_log.Event("INIT",StringFormat("%s %s env=%s %s | discovery: %s",OCL_PRODUCT,OCL_VERSION,g_log.Env(),g_bp.Describe(),rep));
   g_bp.Save(g_log);

   //--- input sanity
   if(InpSLFixed<=0 || InpMaxPositions<1 || InpMaxPending<1 || InpMaxRiskPct<=0)
     { Alert(OCL_PRODUCT,": invalid inputs (SL, limits or risk cap must be positive)"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMaxPositions>1)
      g_log.Event("CONFIG_WARN","max positions > 1: the OCO geometry guard still prevents overlapping brackets");

   if(!g_md.Init(sym)){ Alert(OCL_PRODUCT,": indicator init failed"); return INIT_FAILED; }
   g_sn.Init(sym,InpServerUTCOffsetH,InpServerDST,InpSessionDubai,InpSession2Dubai,InpFridayCutoffDubai,
             InpSessionOpenDelayMin,InpRolloverGuardMin,InpNewsFile,InpUseMT5Calendar,InpNewsBeforeMin,
             InpNewsAfterMin,InpFomcBeforeMin,InpFomcAfterMin,InpNewsMinImpact);

   SOCLRiskConfig rc;
   rc.lot_mode=InpLotMode; rc.fixed_lots=InpFixedLots; rc.risk_pct=InpRiskPct; rc.max_risk_pct=InpMaxRiskPct;
   rc.adaptive_max_lots=InpAdaptiveMaxLots; rc.max_daily_loss_pct=InpMaxDailyLossPct; rc.max_daily_dd_pct=InpMaxDailyDDPct;
   rc.max_weekly_dd_pct=InpMaxWeeklyDDPct; rc.max_spread=InpMaxSpread; rc.max_spread_vs_avg=InpMaxSpreadVsAvg;
   rc.max_slippage=InpMaxSlippage; rc.max_positions=InpMaxPositions; rc.max_pending=InpMaxPending;
   rc.max_trades_per_hour=InpMaxTradesPerHour; rc.max_consec_losses=InpMaxConsecLosses;
   rc.consec_loss_pause_min=InpConsecLossPauseMin; rc.max_reject_rate=InpMaxRejectRate;
   rc.max_account_lots=InpMaxAccountLots; rc.min_free_margin=InpMinFreeMargin; rc.min_margin_level=InpMinMarginLevel;
   rc.max_daily_commission=InpMaxDailyCommission; rc.emergency_stop=InpEmergencyStop;
   g_risk.Init(rc,GetPointer(g_bp),GetPointer(g_log),InpMagic);
   g_ex.Init(GetPointer(g_bp),GetPointer(g_log),GetPointer(g_risk),InpMagic,InpDeviationPoints);

   SOCLSignalConfig sc;
   sc.dist_mode=InpDistMode; sc.offset_fixed=InpOffsetFixed; sc.offset_spread_k=InpOffsetSpreadK;
   sc.offset_atr_k=InpOffsetAtrK; sc.offset_range_k=InpOffsetRangeK; sc.range_window_ms=InpRangeWindowMs;
   sc.offset_min=InpOffsetMin; sc.offset_max=InpOffsetMax; sc.sl_fixed=InpSLFixed; sc.sl_atr_k=InpSLAtrK;
   sc.arm_sides=InpArmSides; sc.momentum_window_ms=InpMomentumWindowMs; sc.momentum_min=InpMomentumMin;
   sc.use_atr_filter=InpUseAtrFilter; sc.atr_min=InpAtrMin; sc.atr_max=InpAtrMax;
   sc.block_extreme_regime=InpBlockExtremeRegime; sc.use_rsi_filter=InpUseRsiFilter; sc.rsi_low=InpRsiLow;
   sc.rsi_high=InpRsiHigh; sc.use_adx_filter=InpUseAdxFilter; sc.adx_min=InpAdxMin; sc.rearm_mode=InpRearmMode;
   sc.rearm_cooldown_s=InpRearmCooldownS; sc.rearm_spread_k=InpRearmSpreadK; sc.rearm_range_min=InpRearmRangeMin;
   sc.rearm_range_max=InpRearmRangeMax;
   g_sig.Init(sc,GetPointer(g_md));

   SOCLPendingConfig pc;
   pc.mode=InpPendingMode; pc.follow_dir=InpFollowDir; pc.follow_step=InpFollowStep; pc.follow_min_ms=InpFollowMinMs;
   pc.follow_max_per_min=InpFollowMaxPerMin; pc.lifetime_s=InpPendingLifetimeS; pc.broker_expiry=InpBrokerExpiry;
   pc.oco_mode=InpOcoMode; pc.stop_buffer=InpStopBuffer;
   g_pend.Init(pc,GetPointer(g_bp),GetPointer(g_log),GetPointer(g_ex),GetPointer(g_md),InpMagic);

   SOCLExitConfig ec; ResolveExit(ec);
   g_pos.Init(ec,GetPointer(g_bp),GetPointer(g_log),GetPointer(g_ex),GetPointer(g_md),InpMagic,InpSLMinModifyMs,
              InpStopBuffer,InpMomentumWindowMs,InpMomentumMin,InpLatencyPadPerSec);
   g_pos.SetInitialStop(InpSLFixed);

   //--- restart reconciliation: adopt existing positions/orders with our magic
   int np=g_pos.Scan(); g_pend.Scan();
   g_log.Event("RECONCILE",StringFormat("found %d position(s), buy_stop=%I64u sell_stop=%I64u extra=%d",
                                         np,g_pend.buy_ticket,g_pend.sell_ticket,g_pend.extra_orders));
   ArrayInitialize(g_trk_pos,0);
   EventSetMillisecondTimer(250);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_log.Event("DEINIT",StringFormat("reason=%d",reason));
   // pending orders are removed on shutdown so nothing is left unmanaged; positions keep their server-side SL
   if(reason!=REASON_CHARTCHANGE && reason!=REASON_PARAMETERS && reason!=REASON_RECOMPILE)
      g_pend.CancelAll("EA stopped");
   g_md.Release();
   g_log.Close();
   if(!g_tester) Comment("");
  }

void OnTick()  { Process(); }
void OnTimer() { Process(); }

//==================== main loop ====================
void Process()
  {
   if(!g_md.Update()) return;
   // same quote as last time: only re-run once per second (time exits, session ends)
   ulong now_ms=OCL_NowMs();
   if(g_md.tick.time_msc==(ulong)g_last_tick_msc && now_ms-g_last_process_ms<1000) { Housekeeping(); return; }
   g_last_tick_msc=(long)g_md.tick.time_msc; g_last_process_ms=now_ms;
   if(g_log.LogTicks()) g_log.Event("TICK",OCL_RegimeName(g_md.Regime()));
   g_sn.RefreshMT5Calendar();

   //--- 1. continuous risk limits
   string why="";
   if(g_risk.Update(why)){ Flatten("risk: "+why); return; }
   if(g_risk.Halted()){ Flatten("risk halted: "+g_risk.HaltReason()); LogWait("halted: "+g_risk.HaltReason()); return; }

   //--- 2. volatility circuit breaker
   if(InpCircuitRange60s>0 && g_md.RangeMs(60000)>InpCircuitRange60s && TimeCurrent()>=g_circuit_until)
     {
      g_circuit_until=TimeCurrent()+InpCircuitPauseMin*60;
      g_log.Event("CIRCUIT_BREAKER",StringFormat("60s range %.2f > %.2f; no new orders for %d min",
                                                  g_md.RangeMs(60000),InpCircuitRange60s,InpCircuitPauseMin));
      g_pend.CancelAll("circuit breaker");
     }

   //--- 3. positions
   int npos=g_pos.Scan();
   if(npos>InpMaxPositions){ g_pos.CloseExcess(InpMaxPositions); npos=g_pos.Scan(); }
   g_pend.Scan();
   g_pend.CancelExtras();
   if(npos>0)
     {
      g_pend.ManageInPosition(g_pos.dir,g_pos.sl);
      g_pos.Manage();
      Housekeeping();
      return;
     }

   //--- 4. flat: gates for new orders
   if(TimeCurrent()<g_circuit_until){ LogWait("circuit breaker"); Housekeeping(); return; }
   if(!g_sn.SessionAllows(why))
     {
      if(g_pend.buy_ticket>0 || g_pend.sell_ticket>0) g_pend.CancelAll("session: "+why);
      LogWait("session: "+why); Housekeeping(); return;
     }
   double news_factor=1.0; string title;
   if(g_sn.InBlackout(title))
     {
      if(InpNewsAction==NEWS_BLOCK_NEW)
        {
         if(g_pend.buy_ticket>0 || g_pend.sell_ticket>0) g_pend.CancelAll("news blackout: "+title);
         LogWait("news blackout: "+title); Housekeeping(); return;
        }
      if(InpNewsAction==NEWS_REDUCED_RISK) news_factor=InpNewsLotFactor;
      else LogWait("news (monitor only): "+title);
     }

   //--- hostile conditions remove resting stops (they would fill at a bad price)
   double sp=g_md.spread, avg=g_md.SpreadAvg();
   bool hostile=(InpMaxSpread>0 && sp>InpMaxSpread) || (InpMaxSpreadVsAvg>0 && avg>0 && sp>InpMaxSpreadVsAvg*avg)
                || g_risk.NoNewActive() || g_risk.EmergencyActive();
   if(hostile)
     {
      if(g_pend.buy_ticket>0 || g_pend.sell_ticket>0) g_pend.CancelAll(StringFormat("hostile: spread %.2f avg %.2f",sp,avg));
      LogWait(StringFormat("hostile: spread %.2f avg %.2f",sp,avg)); Housekeeping(); return;
     }

   //--- 5. signal, size, gates, re-arm
   SOCLSignal s; g_sig.Evaluate(s);
   string lnote;
   double lots=g_risk.Lots(s.sl_dist,g_md.Regime(),news_factor,lnote);
   int need=((s.arm_buy && g_pend.buy_ticket==0)?1:0)+((s.arm_sell && g_pend.sell_ticket==0)?1:0);
   bool may_place=false; string place_why="";
   if(need>0)
     {
      string rwhy, gwhy;
      if(!g_sig.RearmAllowed(g_last_close,rwhy)) LogWait("re-arm wait: "+rwhy);
      else if(!g_risk.CanArm(sp,avg,lots,need,gwhy)) LogWait("risk gate: "+gwhy);
      else { may_place=true; place_why="re-arm: "+rwhy+" | lots "+DoubleToString(lots,2)+" "+lnote; g_last_wait=""; }
     }
   else if(!s.arm_buy && !s.arm_sell) LogWait("signal: "+s.reason);
   g_pend.ManageFlat(s,may_place,lots,place_why);
   Housekeeping();
  }

//==================== trade transactions ====================
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.symbol!="" && trans.symbol!=g_bp.symbol) return;
   switch(trans.type)
     {
      case TRADE_TRANSACTION_ORDER_ADD:
         g_log.Event("TX_ORDER_ADD",EnumToString(trans.order_type),trans.order,trans.position,trans.volume,trans.price,0,trans.price_sl);
         break;
      case TRADE_TRANSACTION_ORDER_UPDATE:
         g_log.Event("TX_ORDER_UPDATE",EnumToString(trans.order_state),trans.order,trans.position,trans.volume,trans.price,0,trans.price_sl);
         break;
      case TRADE_TRANSACTION_ORDER_DELETE:
         g_log.Event("TX_ORDER_DELETE",EnumToString(trans.order_state),trans.order,trans.position,trans.volume,trans.price,0,trans.price_sl);
         break;
      case TRADE_TRANSACTION_POSITION:
         g_log.Event("TX_POSITION_MODIFY","sl/tp changed",0,trans.position,trans.volume,0,0,trans.price_sl);
         break;
      case TRADE_TRANSACTION_DEAL_ADD:
         OnDeal(trans.deal);
         break;
      default: break;
     }
  }

void OnDeal(const ulong deal)
  {
   if(deal==0 || !HistoryDealSelect(deal)) return;
   ulong pos_id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
   ENUM_DEAL_TYPE dtype=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
   if(dtype!=DEAL_TYPE_BUY && dtype!=DEAL_TYPE_SELL) return;
   double price=HistoryDealGetDouble(deal,DEAL_PRICE), vol=HistoryDealGetDouble(deal,DEAL_VOLUME);
   double comm=HistoryDealGetDouble(deal,DEAL_COMMISSION);
   long msc=HistoryDealGetInteger(deal,DEAL_TIME_MSC);
   ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
   ENUM_DEAL_REASON reason=(ENUM_DEAL_REASON)HistoryDealGetInteger(deal,DEAL_REASON);

   if(entry==DEAL_ENTRY_IN)
     {
      if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic) return;
      double req=price;
      if(HistoryOrderSelect(order)) req=HistoryOrderGetDouble(order,ORDER_PRICE_OPEN);
      int d=(dtype==DEAL_TYPE_BUY)?1:-1;
      double slip=(price-req)*d;                 // positive = filled worse than the stop price
      Track(pos_id,msc,req,slip,OCL_RegimeName(g_md.Regime()));
      g_risk.RecordEntry(slip);
      g_log.Event("FILL",StringFormat("%s entry, slippage %.2f",d>0?"BUY":"SELL",slip),order,pos_id,vol,req,price,0);
      // apply the OCO policy at once rather than waiting for the next tick
      if(g_pos.Scan()>0){ g_pend.Scan(); g_pend.ManageInPosition(g_pos.dir,g_pos.sl); }
      return;
     }

   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT) return;
   // is this one of our positions? check the entry deal's magic
   if(!HistorySelectByPosition(pos_id)) return;
   bool ours=false; double gross=0, commission=0, swap=0, entry_px=0, in_vol=0; int dir=0; long open_msc=0;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong dt=HistoryDealGetTicket(i); if(dt==0) continue;
      ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(dt,DEAL_ENTRY);
      if(e==DEAL_ENTRY_IN)
        {
         if(HistoryDealGetInteger(dt,DEAL_MAGIC)==InpMagic) ours=true;
         entry_px=HistoryDealGetDouble(dt,DEAL_PRICE); in_vol+=HistoryDealGetDouble(dt,DEAL_VOLUME);
         dir=(HistoryDealGetInteger(dt,DEAL_TYPE)==DEAL_TYPE_BUY)?1:-1;
         open_msc=HistoryDealGetInteger(dt,DEAL_TIME_MSC);
        }
      gross+=HistoryDealGetDouble(dt,DEAL_PROFIT);
      commission+=HistoryDealGetDouble(dt,DEAL_COMMISSION)+HistoryDealGetDouble(dt,DEAL_FEE);
      swap+=HistoryDealGetDouble(dt,DEAL_SWAP);
     }
   if(!ours) return;
   bool simulated=false;
   if(PositionSelectByTicket(pos_id)==false && commission==0.0 && InpSimCommissionRTPerLot>0)
     { commission=-InpSimCommissionRTPerLot*in_vol; simulated=true; g_sim_commission_total+=commission; }
   string rs=EnumToString(reason); StringReplace(rs,"DEAL_REASON_","");
   g_log.Event("EXIT_DEAL",rs,order,pos_id,vol,0,price,HistoryDealGetDouble(deal,DEAL_SL));
   if(PositionSelectByTicket(pos_id)) return;      // partial close: position still open
   int k=TrackFind(pos_id);
   double slip=(k>=0)?g_trk_slip[k]:0; string regime=(k>=0)?g_trk_regime[k]:"unknown";
   g_log.Trade(pos_id,dir,in_vol,open_msc,msc,entry_px,price,gross,commission,swap,slip,rs,regime,
               InpStrategyTag+"/"+ExitProfileName());
   double net=gross+commission+swap;
   g_risk.RecordClose(net,commission);
   if(!simulated) g_bp.ObserveCommission(commission,in_vol);
   g_closed_lots+=in_vol;
   g_last_close=TimeCurrent();
   g_log.Event("POSITION_CLOSED",StringFormat("net %.2f gross %.2f comm %.2f reason %s",net,gross,commission,rs),0,pos_id,in_vol,entry_px,price);
   if(k>=0) g_trk_pos[k]=0;
   g_pend.OnPositionClosed();
  }

//==================== status / panel ====================
void Housekeeping()
  {
   if(g_tester && MQLInfoInteger(MQL_OPTIMIZATION)) return;
   int every=g_tester?60:InpStatusEverySec;
   if(TimeCurrent()-g_last_status<every) return;
   g_last_status=TimeCurrent();
   double bal=AccountInfoDouble(ACCOUNT_BALANCE), eq=AccountInfoDouble(ACCOUNT_EQUITY);
   string json=StringFormat("{\"product\":\"%s\",\"version\":\"%s\",\"env\":\"%s\",\"symbol\":\"%s\",\"time\":\"%s\","
                            "\"balance\":%.2f,\"equity\":%.2f,\"floating\":%.2f,\"day_pnl\":%.2f,\"day_dd_pct\":%.2f,"
                            "\"positions\":%d,\"buy_stop\":%I64u,\"buy_stop_price\":%.2f,\"sell_stop\":%I64u,\"sell_stop_price\":%.2f,"
                            "\"spread\":%.2f,\"spread_avg\":%.2f,\"regime\":\"%s\",\"latency_ms\":%.1f,"
                            "\"consec_losses\":%d,\"halted\":%s,\"halt_reason\":\"%s\",\"emergency\":%s,\"no_new\":%s,"
                            "\"last_wait\":\"%s\",\"commission_rt_per_lot\":%.2f,\"strategy\":\"%s/%s\"}",
                            OCL_PRODUCT,OCL_VERSION,g_log.Env(),g_bp.symbol,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                            bal,eq,eq-bal,g_risk.DayPnL(),g_risk.DayDDPct(),g_pos.Scan(),
                            g_pend.buy_ticket,g_pend.buy_ticket>0?g_pend.buy_price:0.0,
                            g_pend.sell_ticket,g_pend.sell_ticket>0?g_pend.sell_price:0.0,
                            g_md.spread,g_md.SpreadAvg(),OCL_RegimeName(g_md.Regime()),g_ex.LatencyMs(),
                            g_risk.ConsecLosses(),g_risk.Halted()?"true":"false",g_risk.HaltReason(),
                            g_risk.EmergencyActive()?"true":"false",g_risk.NoNewActive()?"true":"false",
                            g_last_wait,g_bp.CommissionRT(),InpStrategyTag,ExitProfileName());
   g_log.Status(json);
   if(!g_tester)
      Comment(StringFormat("%s %s  [%s]  %s\nEquity %.2f  Day P/L %.2f  DD %.2f%%\nSpread %.2f (avg %.2f)  Regime %s\n"
                           "BuyStop %s  SellStop %s  Pos %d\nState: %s",
                           OCL_PRODUCT,OCL_VERSION,StringUpper_(g_log.Env()),g_bp.symbol,eq,g_risk.DayPnL(),g_risk.DayDDPct(),
                           g_md.spread,g_md.SpreadAvg(),OCL_RegimeName(g_md.Regime()),
                           g_pend.buy_ticket>0?DoubleToString(g_pend.buy_price,2):"-",
                           g_pend.sell_ticket>0?DoubleToString(g_pend.sell_price,2):"-",g_pos.Scan(),g_last_wait));
  }

string StringUpper_(string s) { StringToUpper(s); return s; }

//==================== tester custom criterion ====================
// Net profit after commission (real, plus any simulated commission) divided by (1 + max equity drawdown);
// penalises fewer than 30 trades. The totals are also printed to the tester log (OCL_TESTER line).
double OnTester()
  {
   double net=TesterStatistics(STAT_PROFIT)+g_sim_commission_total;
   PrintFormat("OCL_TESTER net_after_sim=%.2f sim_commission=%.2f closed_lots=%.2f trades=%.0f",
               net,g_sim_commission_total,g_closed_lots,TesterStatistics(STAT_TRADES));
   double dd=TesterStatistics(STAT_EQUITY_DD);
   double trades=TesterStatistics(STAT_TRADES);
   if(trades<30) return -1000+trades;
   return net/(1.0+dd);
  }
