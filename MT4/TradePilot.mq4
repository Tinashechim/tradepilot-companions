// TradePilot - By Tinashe Chimanikire
// Legacy account/session storage keys are retained for upgrade compatibility.
#property strict
#include "TradePilotSizing.mqh"
#include "TradePilotLocal.mqh"
#include "TradePilotCharts.mqh"
#property version   "2.13"
#property description "TradePilot for MT4"
#property copyright "Tinashe Chimanikire"

bool tp_spread_on=false;
bool tp_spread_confirm_open=false;
int tp_spread_pending_side=0;
bool tp_spread_pending_calculation=false;
// ============================================================
// MT4 TRADEPILOT
// Session boundary: 23:30 broker/server time
// The EA can execute BUY/SELL market orders from the panel.
// The selected SL becomes the actual broker stop loss for panel-executed trades.
// ============================================================

#define BASE_PANEL_X       12
#define BASE_PANEL_Y       16
#define BASE_PANEL_WIDTH   304
#define BASE_PANEL_HEIGHT  724

#define BASE_LABEL_X       11
#define BASE_VALUE_X       160
#define BASE_UNIT_X        256

#define BASE_FONT_TITLE    6
#define BASE_FONT_SECTION  6
#define BASE_FONT_NORMAL   5
#define BASE_FONT_SMALL    5

double panel_scale        = 1.0;
double auto_panel_scale   = 1.0;
double manual_panel_scale = 1.0;
bool manual_scale_override = false;


bool   risk_percentage_mode = true;

bool   daily_percentage_mode = true;
bool   sl_line_enabled = false;

double risk_value = 1.0;
double daily_target_value = 5.0;

string GV_PREFIX;
string GV_RISK_MODE;
string GV_RISK_VALUE;
string GV_DAILY_MODE;
string GV_DAILY_VALUE;
string GV_PANEL_SCALE;
string GV_SL_ENABLED;
string GV_CLOSE_LOCK;


// ============================================================
// BASIC HELPERS
// ============================================================

string AccountCurrencyText()
{
   return AccountCurrency();
}

int PriceDigits()
{
   return (int)MarketInfo(Symbol(), MODE_DIGITS);
}

double PointSize()
{
   return MarketInfo(Symbol(), MODE_POINT);
}

double CurrentAsk()
{
   return MarketInfo(Symbol(), MODE_ASK);
}

double CurrentBid()
{
   return MarketInfo(Symbol(), MODE_BID);
}

datetime GetSessionStartForTime(datetime time_value)
{
   MqlDateTime parts;
   TimeToStruct(time_value, parts);

   parts.hour = 23;
   parts.min  = 30;
   parts.sec  = 0;

   datetime today_start = StructToTime(parts);

   if(time_value < today_start)
      return today_start - 86400;

   return today_start;
}

string SessionKey(datetime session_start, string suffix)
{
   return GV_PREFIX +
          "S_" +
          IntegerToString((int)session_start) +
          "_" +
          suffix;
}


// ============================================================
// GLOBAL VARIABLE KEYS
// ============================================================

void BuildGlobalVariableNames()
{
   GV_PREFIX =
      "PSBM4_" +
      IntegerToString(AccountNumber()) +
      "_";

   GV_RISK_MODE   = GV_PREFIX + "RISK_MODE";
   GV_RISK_VALUE  = GV_PREFIX + "RISK_VALUE";
   GV_DAILY_MODE  = GV_PREFIX + "DAILY_MODE";
   GV_DAILY_VALUE = GV_PREFIX + "DAILY_VALUE";
   GV_PANEL_SCALE = GV_PREFIX + "PANEL_SCALE";
   GV_SL_ENABLED  = GV_PREFIX + "SL_ENABLED";
   GV_CLOSE_LOCK  = GV_PREFIX + "CLOSE_LOCK";
}

void LoadSharedSettings()
{
   if(!GlobalVariableCheck(GV_RISK_MODE))
      GlobalVariableSet(GV_RISK_MODE, 1.0);

   if(!GlobalVariableCheck(GV_RISK_VALUE))
      GlobalVariableSet(GV_RISK_VALUE, 1.0);

   if(!GlobalVariableCheck(GV_DAILY_MODE))
      GlobalVariableSet(GV_DAILY_MODE, 1.0);

   if(!GlobalVariableCheck(GV_DAILY_VALUE))
      GlobalVariableSet(GV_DAILY_VALUE, 5.0);

   if(!GlobalVariableCheck(GV_PANEL_SCALE))
      GlobalVariableSet(GV_PANEL_SCALE, 1.0);

   if(!GlobalVariableCheck(GV_SL_ENABLED))
      GlobalVariableSet(GV_SL_ENABLED, 0.0);

   risk_percentage_mode =
      GlobalVariableGet(GV_RISK_MODE) > 0.5;

   risk_value =
      GlobalVariableGet(GV_RISK_VALUE);

   daily_percentage_mode =
      GlobalVariableGet(GV_DAILY_MODE) > 0.5;

   daily_target_value =
      GlobalVariableGet(GV_DAILY_VALUE);

   manual_panel_scale =
      GlobalVariableGet(GV_PANEL_SCALE);

   sl_line_enabled =
      GlobalVariableGet(GV_SL_ENABLED) > 0.5;

   if(manual_panel_scale < 0.50)
      manual_panel_scale = 0.50;

   if(manual_panel_scale > 1.50)
      manual_panel_scale = 1.50;
}


// ============================================================
// ORDER / SESSION HELPERS
// ============================================================

bool IsSelectedMarketOrder()
{
   int type = OrderType();
   return(type == OP_BUY || type == OP_SELL);
}

int GetSessionOpenOrderCount(datetime session_start)
{
   int count = 0;

   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsSelectedMarketOrder())
         continue;

      if(GetSessionStartForTime(OrderOpenTime()) == session_start)
         count++;
   }

   return count;
}

double GetSessionFloatingPL(datetime session_start)
{
   double total = 0.0;

   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsSelectedMarketOrder())
         continue;

      if(GetSessionStartForTime(OrderOpenTime()) != session_start)
         continue;

      total += OrderProfit() + OrderSwap() + OrderCommission();
   }

   return total;
}

int GetCarryOverOrderCount()
{
   datetime current_session =
      GetSessionStartForTime(TPDL_Now());

   int count = 0;

   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsSelectedMarketOrder())
         continue;

      if(GetSessionStartForTime(OrderOpenTime()) < current_session)
         count++;
   }

   return count;
}

double GetCarryOverFloatingPL()
{
   datetime current_session =
      GetSessionStartForTime(TPDL_Now());

   double total = 0.0;

   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsSelectedMarketOrder())
         continue;

      if(GetSessionStartForTime(OrderOpenTime()) >= current_session)
         continue;

      total += OrderProfit() + OrderSwap() + OrderCommission();
   }

   return total;
}

int GetCarryOverBasketCount()
{
   datetime current_session =
      GetSessionStartForTime(TPDL_Now());

   datetime sessions[];
   int count = 0;

   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsSelectedMarketOrder())
         continue;

      datetime session_start =
         GetSessionStartForTime(OrderOpenTime());

      if(session_start >= current_session)
         continue;

      bool found = false;

      for(int j = 0; j < count; j++)
      {
         if(sessions[j] == session_start)
         {
            found = true;
            break;
         }
      }

      if(!found)
      {
         ArrayResize(sessions, count + 1);
         sessions[count] = session_start;
         count++;
      }
   }

   return count;
}


// ============================================================
// CLOSED P/L ATTRIBUTED TO ORIGINAL OPEN SESSION
// ============================================================

double GetSessionClosedPL(datetime session_start, bool target_adjustment=false)
{
   double actual=0,adjusted=0;
   if(!TP_BasketResults(session_start,actual,adjusted,false))return 0;
   return target_adjustment?adjusted:actual;
}

// Used only to reconstruct the actual account balance at a session boundary.
// This uses close time because AccountBalance() changes when a trade closes.
double GetAccountRealizedSince(datetime session_start)
{
   double total = 0.0;

   for(int i = 0; i < OrdersHistoryTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(!IsSelectedMarketOrder())
         continue;

      if(OrderCloseTime() < session_start)
         continue;

      total += OrderProfit() + OrderSwap() + OrderCommission();
   }

   return total;
}


// ============================================================
// SESSION STATE
// ============================================================

void EnsureSessionState(datetime session_start)
{
   string balance_key = SessionKey(session_start, "START_BAL");
   string mode_key    = SessionKey(session_start, "MODE");
   string target_key  = SessionKey(session_start, "TARGET");

   if(!GlobalVariableCheck(balance_key))
   {
      double start_balance = AccountBalance();

      datetime current_session =
         GetSessionStartForTime(TPDL_Now());

      // For the current session, reconstruct the balance at 23:30
      // from the present balance and realized P/L since the boundary.
      if(session_start == current_session)
         start_balance -= GetAccountRealizedSince(session_start);

      GlobalVariableSet(balance_key, start_balance);
   }

   if(!GlobalVariableCheck(mode_key))
      GlobalVariableSet(
         mode_key,
         daily_percentage_mode ? 1.0 : 0.0
      );

   if(!GlobalVariableCheck(target_key))
      GlobalVariableSet(
         target_key,
         daily_target_value
      );
}

double GetSessionStartBalance(datetime session_start)
{
   EnsureSessionState(session_start);
   return GlobalVariableGet(
      SessionKey(session_start, "START_BAL")
   );
}

bool GetSessionPercentageMode(datetime session_start)
{
   EnsureSessionState(session_start);
   return GlobalVariableGet(
      SessionKey(session_start, "MODE")
   ) > 0.5;
}

double GetSessionTargetInput(datetime session_start)
{
   EnsureSessionState(session_start);
   return GlobalVariableGet(
      SessionKey(session_start, "TARGET")
   );
}

double GetSessionTargetMoney(datetime session_start)
{
   double target = GetSessionTargetInput(session_start);
   double ratio_target=0;if(TPDR_Target(session_start,target,ratio_target)) return ratio_target;

   if(GetSessionPercentageMode(session_start))
   {
      return
         GetSessionStartBalance(session_start) *
         target /
         100.0;
   }

   return target;
}

double GetSessionRemainingTargetMoney(datetime session_start)
{
   double remaining =
      GetSessionTargetMoney(session_start) -
      GetSessionClosedPL(session_start,true);

   if(remaining < 0.0)
      remaining = 0.0;

   return remaining;
}

double GetSessionClosedPercent(datetime session_start)
{
   double balance =
      GetSessionStartBalance(session_start);

   if(balance <= 0.0)
      return 0.0;

   return
      GetSessionClosedPL(session_start) /
      balance *
      100.0;
}

void UpdateCurrentSessionTargetFromUI()
{
   datetime current_session =
      GetSessionStartForTime(TPDL_Now());

   EnsureSessionState(current_session);

   GlobalVariableSet(
      SessionKey(current_session, "MODE"),
      daily_percentage_mode ? 1.0 : 0.0
   );

   GlobalVariableSet(
      SessionKey(current_session, "TARGET"),
      daily_target_value
   );
   TPDR_Save(current_session);
}


// ============================================================
// MULTI-CHART CLOSE LOCK
// ============================================================

bool AcquireCloseLock()
{
   if(!GlobalVariableCheck(GV_CLOSE_LOCK))
      GlobalVariableSet(GV_CLOSE_LOCK, 0.0);

   double now = (double)TimeCurrent();
   double old = GlobalVariableGet(GV_CLOSE_LOCK);

   // Recover a stale lock after 10 seconds.
   if(old > 0.0 && now - old <= 10.0)
      return false;

   return GlobalVariableSetOnCondition(
      GV_CLOSE_LOCK,
      now,
      old
   );
}

void ReleaseCloseLock()
{
   GlobalVariableSet(GV_CLOSE_LOCK, 0.0);
}


// ============================================================
// AUTOMATIC SESSION BASKET CLOSE
// ============================================================

bool CloseSessionOrders(datetime session_start)
{
   bool success = true;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsSelectedMarketOrder())
         continue;

      if(GetSessionStartForTime(OrderOpenTime()) != session_start)
         continue;

      int ticket = OrderTicket();
      int type   = OrderType();
      double lots = OrderLots();
      string symbol = OrderSymbol();

      RefreshRates();

      double close_price =
         (type == OP_BUY)
         ? MarketInfo(symbol, MODE_BID)
         : MarketInfo(symbol, MODE_ASK);

      if(close_price <= 0.0)
      {
         success = false;
         continue;
      }

      ResetLastError();

      if(!OrderClose(
         ticket,
         lots,
         close_price,
         30,
         clrNONE
      ))
      {
         Print(
            "TradePilot MT4: OrderClose failed. Ticket=",
            ticket,
            " Error=",
            GetLastError()
         );

         success = false;
      }
   }

   return success;
}

void CheckBasketTakeProfit()
{
   datetime sessions[];
   int session_count = 0;

   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsSelectedMarketOrder())
         continue;

      datetime session_start =
         GetSessionStartForTime(OrderOpenTime());

      EnsureSessionState(session_start);

      bool found = false;

      for(int j = 0; j < session_count; j++)
      {
         if(sessions[j] == session_start)
         {
            found = true;
            break;
         }
      }

      if(!found)
      {
         ArrayResize(sessions, session_count + 1);
         sessions[session_count] = session_start;
         session_count++;
      }
   }

   for(int i = 0; i < session_count; i++)
   {
      datetime session_start = sessions[i];

      double target=GetSessionTargetMoney(session_start),actual=0,adjusted=0;
      if(target<=0 || !TP_BasketResults(session_start,actual,adjusted) || adjusted<target)continue;
      // Preserve the existing policy: realised target alone never liquidates unrelated survivors.
      if(GetSessionClosedPL(session_start,true)>=target)continue;

      if(!AcquireCloseLock())
         return;

      CloseSessionOrders(session_start);
      ReleaseCloseLock();
   }
}


// ============================================================
// POSITION SIZER
// ============================================================

double GetRiskAmount()
{
   if(risk_percentage_mode)
      return AccountBalance() * risk_value / 100.0;

   return risk_value;
}

double NormalizeCalculatedVolume(double volume)
{
   double step =
      MarketInfo(Symbol(), MODE_LOTSTEP);

   if(step <= 0.0)
      return 0.0;

   return MathFloor(volume / step) * step;
}

double GetOneLotLoss(double entry, double stop)
{
   double tick_size =
      SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);

   double tick_value =
      MarketInfo(Symbol(), MODE_TICKVALUE);

   if(!MathIsValidNumber(tick_size) || !MathIsValidNumber(tick_value) || tick_size <= 0.0 || tick_value <= 0.0)
      return 0.0;

   return
      MathAbs(entry - stop) /
      tick_size *
      tick_value;
}

double GetBrokerRequiredMargin(
   int order_type,
   double volume
)
{
   if(!MathIsValidNumber(volume) || volume <= 0.0)
      return -1.0;

   double required=-1;
   int verified=TP_CheckMargin(Symbol(),order_type,order_type==OP_BUY ? Ask : Bid,volume,required);
   return verified==1 ? required : -1;
}

void CalculatePositionSize()
{
   double entry =
      StringToDouble(
         ObjectGetString(
            0,
            "TradePilot_ENTRY_EDIT",
            OBJPROP_TEXT
         )
      );

   double stop =
      StringToDouble(
         ObjectGetString(
            0,
            "TradePilot_SL_EDIT",
            OBJPROP_TEXT
         )
      );

   double entered_risk =
      StringToDouble(
         ObjectGetString(
            0,
            "TradePilot_RISK_EDIT",
            OBJPROP_TEXT
         )
      );

   if(
      entered_risk <= 0.0 ||
      entry <= 0.0 ||
      stop <= 0.0 ||
      entry == stop
   )
      return;

   risk_value = entered_risk;

   GlobalVariableSet(
      GV_RISK_VALUE,
      risk_value
   );

   double risk_amount =
      TPDL_CapRisk(GetRiskAmount());

   double one_lot_loss =
      GetOneLotLoss(
         entry,
         stop
      );

   if(one_lot_loss <= 0.0)
      return;

   double raw_volume =
      risk_amount /
      one_lot_loss;

   double calculated_volume =
      NormalizeCalculatedVolume(
         raw_volume
      );

   double minimum =
      MarketInfo(
         Symbol(),
         MODE_MINLOT
      );

   double maximum =
      MarketInfo(
         Symbol(),
         MODE_MAXLOT
      );

   int order_type =
      (stop < entry)
      ? OP_BUY
      : OP_SELL;

   calculated_volume=TP_AffordableLots(Symbol(),order_type,entry,calculated_volume);
   double required_margin=-1;
   int margin_check=calculated_volume>0 ? TP_CheckMargin(Symbol(),order_type,entry,calculated_volume,required_margin) : -1;

   ObjectSetString(
      0,
      "TradePilot_RISK_AMOUNT_VALUE",
      OBJPROP_TEXT,
      (risk_percentage_mode ? DoubleToString(AccountBalance()>0 ? risk_amount/AccountBalance()*100.0 : 0,2)+"% " : "")+"("+AccountCurrencyText()+" "+DoubleToString(risk_amount,2)+")"
   );

   ObjectSetString(
      0,
      "TradePilot_BROKER_MAX_VALUE",
      OBJPROP_TEXT,
      DoubleToString(maximum, 2)
   );

   ObjectSetString(
      0,
      "TradePilot_MARGIN_VALUE",
      OBJPROP_TEXT,
      margin_check<0 ? "Not verified" : DoubleToString(required_margin, 2)
   );
   ObjectSetInteger(0,"TradePilot_MARGIN_VALUE",OBJPROP_COLOR,margin_check==1 ? C'90,220,140' : C'255,100,100');

   ObjectSetString(
      0,
      "TradePilot_MARGIN_UNIT",
      OBJPROP_TEXT,
      AccountCurrencyText()
   );

   if(
      calculated_volume <= 0.0 ||
      calculated_volume < minimum
   )
   {
      ObjectSetString(
         0,
         "TradePilot_CALCULATED_VALUE",
         OBJPROP_TEXT,
         calculated_volume<0 ? "Margin not verified" : "Below minimum lot"
      );

      ObjectSetInteger(
         0,
         "TradePilot_CALCULATED_VALUE",
         OBJPROP_COLOR,
         clrOrange
      );
   }
   else
   {
      ObjectSetString(
         0,
         "TradePilot_CALCULATED_VALUE",
         OBJPROP_TEXT,
         DoubleToString(calculated_volume, 2)
      );

      ObjectSetInteger(
         0,
         "TradePilot_CALCULATED_VALUE",
         OBJPROP_COLOR,
         calculated_volume > maximum
         ? clrOrange
         : C'90,220,140'
      );
   }

   ChartRedraw();
}



// ============================================================
// COST-AWARE RISK
// ============================================================

double GetPlannedLossPerLot(double entry,double stop)
{
   double market_loss=GetOneLotLoss(entry,stop);

   if(market_loss<=0.0)
      return 0.0;

   // Shared with the copier: stop-loss price risk, excluding broker fees.
   return market_loss;
}


// ============================================================
// PANEL TRADE EXECUTION
// ============================================================

double NormalizeExecutableVolume(double volume)
{
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   double min_lot = MarketInfo(Symbol(), MODE_MINLOT);
   double max_lot = MarketInfo(Symbol(), MODE_MAXLOT);

   if(step <= 0.0 || min_lot <= 0.0 || max_lot <= 0.0)
      return 0.0;

   double normalized =
      MathFloor(volume / step) * step;

   normalized = NormalizeDouble(normalized, 8);

   if(normalized < min_lot)
      return 0.0;

   // Do not silently cap the user's risk calculation.
   // If the required size exceeds the broker maximum, reject execution.
   if(normalized > max_lot)
      return -1.0;

   return normalized;
}


bool ValidateBrokerStopDistance(
   int order_type,
   double entry,
   double stop
)
{
   double point = PointSize();

   if(point <= 0.0)
      return false;

   double minimum_distance =
      MarketInfo(Symbol(), MODE_STOPLEVEL) *
      point;

   if(order_type == OP_BUY)
   {
      if(stop >= entry)
         return false;

      if(minimum_distance > 0.0 &&
         entry - stop < minimum_distance)
         return false;
   }
   else
   {
      if(stop <= entry)
         return false;

      if(minimum_distance > 0.0 &&
         stop - entry < minimum_distance)
         return false;
   }

   return true;
}


void ExecutePanelTrade(int order_type,bool spread_confirmed=false)
{
   if(!tp_spread_on && !spread_confirmed){tp_spread_pending_calculation=false;tp_spread_pending_side=(int)order_type;tp_spread_confirm_open=true;TP_SpreadTradePrompt();return;}

   string daily_reason="";if(!TPDL_EntryAllowed(daily_reason)) {Alert(daily_reason);return;}

   RefreshRates();

   double entry =
      (order_type == OP_BUY)
      ? CurrentAsk()
      : CurrentBid();

   double stop =
      StringToDouble(
         ObjectGetString(
            0,
            "TradePilot_SL_EDIT",
            OBJPROP_TEXT
         )
      );

   double entered_risk =
      StringToDouble(
         ObjectGetString(
            0,
            "TradePilot_RISK_EDIT",
            OBJPROP_TEXT
         )
      );

   if(entry <= 0.0 || stop <= 0.0 || entered_risk <= 0.0)
   {
      Alert("Trade not sent: check Risk and Stop Loss values.");
      return;
   }

   entry = NormalizeDouble(entry, PriceDigits());
   stop  = NormalizeDouble(stop, PriceDigits());

   if(!ValidateBrokerStopDistance(order_type, entry, stop))
   {
      Alert(
         "Trade not sent: invalid Stop Loss for ",
         order_type == OP_BUY ? "BUY." : "SELL."
      );
      return;
   }

   risk_value = entered_risk;
   GlobalVariableSet(GV_RISK_VALUE, risk_value);

   double risk_amount = TPDL_CapRisk(GetRiskAmount());
   double one_lot_loss = GetPlannedLossPerLot(entry, stop);

   if(risk_amount <= 0.0 || one_lot_loss <= 0.0)
   {
      Alert("Trade not sent: unable to calculate risk.");
      return;
   }

   double raw_volume =
      risk_amount / one_lot_loss;

   double volume =
      NormalizeExecutableVolume(raw_volume);

   if(volume < 0.0)
   {
      Alert(
         "Trade not sent: calculated lot size exceeds broker maximum."
      );
      return;
   }

   if(volume <= 0.0)
   {
      Alert(
         "Trade not sent: calculated lot size is below broker minimum."
      );
      return;
   }

   double required_margin =
      GetBrokerRequiredMargin(
         order_type,
         volume
      );

   if(required_margin<0 || required_margin>=AccountFreeMargin())
   {
      Alert("Trade not sent: insufficient free margin.");
      return;
   }

   // Update the panel with the exact values being used for execution.
   ObjectSetString(
      0,
      "TradePilot_ENTRY_EDIT",
      OBJPROP_TEXT,
      DoubleToString(entry, PriceDigits())
   );

   ObjectSetString(
      0,
      "TradePilot_SL_EDIT",
      OBJPROP_TEXT,
      DoubleToString(stop, PriceDigits())
   );

   ObjectSetString(
      0,
      "TradePilot_RISK_AMOUNT_VALUE",
      OBJPROP_TEXT,
      (risk_percentage_mode ? DoubleToString(AccountBalance()>0 ? risk_amount/AccountBalance()*100.0 : 0,2)+"% " : "")+"("+AccountCurrencyText()+" "+DoubleToString(risk_amount,2)+")"
   );

   ObjectSetString(
      0,
      "TradePilot_CALCULATED_VALUE",
      OBJPROP_TEXT,
      DoubleToString(volume, 2)
   );

   ObjectSetString(
      0,
      "TradePilot_MARGIN_VALUE",
      OBJPROP_TEXT,
      DoubleToString(required_margin, 2)
   );

   RefreshRates();

   // Re-read the executable price immediately before sending and recalculate
   // the lot size so a stale panel entry does not control the trade.
   entry =
      (order_type == OP_BUY)
      ? CurrentAsk()
      : CurrentBid();

   entry = NormalizeDouble(entry, PriceDigits());

   if(!ValidateBrokerStopDistance(order_type, entry, stop))
   {
      Alert("Trade not sent: price moved too close to the Stop Loss.");
      return;
   }

   one_lot_loss = GetPlannedLossPerLot(entry, stop);

   if(one_lot_loss <= 0.0)
   {
      Alert("Trade not sent: unable to recalculate current risk.");
      return;
   }

   raw_volume = risk_amount / one_lot_loss;
   volume = NormalizeExecutableVolume(raw_volume);

   if(volume < 0.0)
   {
      Alert("Trade not sent: current calculated size exceeds broker maximum.");
      return;
   }

   if(volume <= 0.0)
   {
      Alert("Trade not sent: current calculated size is below broker minimum.");
      return;
   }

   volume=TP_AffordableLots(Symbol(),order_type,entry,volume);
   double confirmed_margin=0;
   if(volume<=0 || TP_CheckMargin(Symbol(),order_type,entry,volume,confirmed_margin)!=1) { Alert("Trade not sent: lot size or free margin is not verified.");return; }
   int slippage_points = 10;

   ResetLastError();

   if(!TPDL_EntryAllowed(daily_reason) || !TPDL_AcceptRisk(volume*one_lot_loss,daily_reason)) {Alert(daily_reason);return;}
   double tp_master_balance = AccountBalance();
   int ticket =
      OrderSend(
         Symbol(),
         order_type,
         volume,
         entry,
         slippage_points,
         stop,
         0,
         "TradePilot",
         0,
         0,
         clrNONE
      );

   if(ticket < 0)
   {
      int error_code = GetLastError();

      Print(
         "TradePilot OrderSend failed. Error ",
         error_code
      );

      Alert(
         "Trade not sent. MT4 error: ",
         error_code
      );

      return;
   }

   if(OrderSelect(ticket,SELECT_BY_TICKET)) TP_RecordRisk(ticket,OrderLots()*GetPlannedLossPerLot(OrderOpenPrice(),OrderStopLoss()),tp_master_balance);
   // Read the broker-confirmed order values back into the panel.
   if(OrderSelect(ticket, SELECT_BY_TICKET))
   {
      ObjectSetString(
         0,
         "TradePilot_ENTRY_EDIT",
         OBJPROP_TEXT,
         DoubleToString(
            OrderOpenPrice(),
            PriceDigits()
         )
      );

      ObjectSetString(
         0,
         "TradePilot_SL_EDIT",
         OBJPROP_TEXT,
         DoubleToString(
            OrderStopLoss(),
            PriceDigits()
         )
      );

      ObjectSetString(
         0,
         "TradePilot_CALCULATED_VALUE",
         OBJPROP_TEXT,
         DoubleToString(
            OrderLots(),
            2
         )
      );
   }

   SyncStopLossLineWithoutSpread();
   UpdatePanel();
   ChartRedraw();
}


// ============================================================
// SPREAD / PRICE
// ============================================================

double GetCurrentSpreadPoints()
{
   double point = PointSize();

   if(point <= 0.0)
      return 0.0;

   return
      (CurrentAsk() - CurrentBid()) /
      point;
}


// ============================================================
// RESPONSIVE PANEL SCALE
// ============================================================

int S(double value)
{
   int result =
      (int)MathRound(
         value * panel_scale
      );

   if(result < 1)
      result = 1;

   return result;
}

int PanelX()
{
   return S(BASE_PANEL_X);
}

int PanelY()
{
   return S(BASE_PANEL_Y);
}

int PanelWidth()
{
   return S(BASE_PANEL_WIDTH);
}

int PanelHeight()
{
   return S(BASE_PANEL_HEIGHT);
}

int LabelX()
{
   return PanelX() + S(BASE_LABEL_X);
}

int ValueX()
{
   return PanelX() + S(BASE_VALUE_X);
}

int UnitX()
{
   return PanelX() + S(BASE_UNIT_X);
}

int FontSize(int base_size)
{
   // Increase the previous text size by 20%.
   int size =
      (int)MathRound(
         base_size *
         1.56 *
         panel_scale
      );

   if(size < 4)
      size = 4;

   return size;
}

void CalculatePanelScale()
{
   long chart_width =
      ChartGetInteger(
         0,
         CHART_WIDTH_IN_PIXELS,
         0
      );

   long chart_height =
      ChartGetInteger(
         0,
         CHART_HEIGHT_IN_PIXELS,
         0
      );

   if(
      chart_width <= 0 ||
      chart_height <= 0
   )
   {
      panel_scale = manual_panel_scale;
      return;
   }

   double available_width =
      (double)chart_width - 20.0;

   double available_height =
      (double)chart_height - 20.0;

   double width_scale =
      available_width /
      (double)(
         BASE_PANEL_X +
         BASE_PANEL_WIDTH + 12 + 304 + 12 + 304
      );

   double height_scale =
      available_height /
      (double)(
         BASE_PANEL_Y +
         BASE_PANEL_HEIGHT
      );

   auto_panel_scale =
      MathMin(
         width_scale,
         height_scale
      );

   if(auto_panel_scale < 0.25)
      auto_panel_scale = 0.25;

   if(auto_panel_scale > 1.50)
      auto_panel_scale = 1.50;

   // Before the user presses +/- the panel automatically fits the chart.
   // After +/- is pressed, the user's requested scale takes priority so
   // every click produces a visible 10% size change.
   if(manual_scale_override)
      panel_scale = manual_panel_scale;
   else
      panel_scale = MathMin(
         manual_panel_scale,
         auto_panel_scale
      );

   if(panel_scale < 0.50)
      panel_scale = 0.50;

   if(panel_scale > 1.50)
      panel_scale = 1.50;
}


// ============================================================
// OBJECT HELPERS
// ============================================================

void CreateRectangle(
   string name,
   int x,
   int y,
   int width,
   int height,
   color background,
   color border
)
{
   // Retain object creation order so overlays and their controls stay visible.
   if(ObjectFind(0,name)>=0 && (ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)!=OBJ_RECTANGLE_LABEL)ObjectDelete(0,name);
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0))return;

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
}

#include "TradePilotLabelHelp.mqh"

void CreateLabel(
   string name,
   string text,
   int x,
   int y,
   int font_size,
   color text_color
)
{
   if(name=="TradePilot_TITLE" || name=="TradePilot_SUBTITLE" || name=="TradePilot_DESCRIPTION") {
      int row=name=="TradePilot_TITLE" ? 2 : name=="TradePilot_SUBTITLE" ? 16 : 28;
      y=PanelY()+S(row);
      int available_width=S(name=="TradePilot_DESCRIPTION" ? 272 : 164);
      font_size=TP_HeaderFont(text,font_size,available_width,S(name=="TradePilot_TITLE" ? 13 : 11));
   }


   // Retain object creation order so overlays and their controls stay visible.
   if(ObjectFind(0,name)>=0 && (ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)!=OBJ_LABEL)ObjectDelete(0,name);
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_LABEL,0,0,0))return;
   ObjectSetString(0,name,OBJPROP_TOOLTIP,TP_LabelHelp(name,text));

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   if(text=="")ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1);
}

void CreateValue(
   string name,
   string text,
   int y,
   color text_color
)
{
   CreateLabel(
      name,
      text,
      ValueX(),
      y,
      FontSize(BASE_FONT_NORMAL),
      text_color
   );
}

void CreateButton(
   string name,
   string text,
   int x,
   int y,
   int width,
   int height,
   color background
)
{
   // Preserve the same object while the mouse is pressed or a chart event is queued.
   if(ObjectFind(0,name)>=0 && (ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)!=OBJ_BUTTON)ObjectDelete(0,name);
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_BUTTON,0,0,0))return;

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FontSize(BASE_FONT_SMALL));
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 20);
}

void CreateEdit(
   string name,
   string text,
   int x,
   int y,
   int width,
   int height
)
{
   ObjectDelete(0, name);

   if(!ObjectCreate(
      0,
      name,
      OBJ_EDIT,
      0,
      0,
      0
   ))
      return;

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'42,46,56');
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FontSize(BASE_FONT_SMALL));
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_LEFT);
   ObjectSetInteger(0, name, OBJPROP_READONLY, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 2);
   string help="Enter a value using the unit shown beside this field.";
   if(StringFind(name,"DAILY_TARGET")>=0) help="Daily basket target. Use the displayed unit: example 5 for 5%, or 100 for 100 in account currency. This is separate from the desktop monthly follower target.";
   else if(StringFind(name,"RISK_EDIT")>=0) help="Planned trade risk. Use the displayed mode: example 1 for 1% of balance, or 100 for 100 in account currency. Sizing uses balance and stop-loss distance; broker fees affect actual results.";
   else if(StringFind(name,"ENTRY_EDIT")>=0) help="Planned entry price, for example 1.08500 for EURUSD. The executed price can differ from this estimate.";
   else if(StringFind(name,"SL_EDIT")>=0) help="Stop-loss price, for example 1.08000 below a BUY entry at 1.08500. For a SELL, place the stop above entry. You can also drag the stop line.";
   ObjectSetString(0,name,OBJPROP_TOOLTIP,help);
}


// ============================================================
// STOP LOSS LINE
// ============================================================

void DeleteStopLossLine()
{
   ObjectDelete(
      0,
      "TradePilot_SL_LINE"
   );

}

void CreateStopLossLine()
{
   if(!sl_line_enabled)
      return;

   double price = 0.0;

   if(ObjectFind(
      0,
      "TradePilot_SL_EDIT"
   ) >= 0)
   {
      price =
         StringToDouble(
            ObjectGetString(
               0,
               "TradePilot_SL_EDIT",
               OBJPROP_TEXT
            )
         );
   }

   if(price <= 0.0)
      price =
         CurrentAsk() -
         100.0 *
         PointSize();

   price =
      NormalizeDouble(
         price,
         PriceDigits()
      );

   ObjectDelete(
      0,
      "TradePilot_SL_LINE"
   );

   if(!ObjectCreate(
      0,
      "TradePilot_SL_LINE",
      OBJ_HLINE,
      0,
      0,
      price
   ))
      return;

   // Keep the SL line a normal red MT4 horizontal price line.
   // OBJ_HLINE displays its price on the chart's price scale/grid.
   ObjectSetInteger(0, "TradePilot_SL_LINE", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "TradePilot_SL_LINE", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "TradePilot_SL_LINE", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, "TradePilot_SL_LINE", OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, "TradePilot_SL_LINE", OBJPROP_SELECTED, true);
   ObjectSetInteger(0, "TradePilot_SL_LINE", OBJPROP_BACK, true);
   ObjectSetInteger(0, "TradePilot_SL_LINE", OBJPROP_HIDDEN, true);

}

// ============================================================
// STOP LOSS INPUT / LINE
// ============================================================
//
// For panel-executed trades the Stop Loss field is the ACTUAL broker SL price.
// We therefore do not add spread to the SL itself.
//
// Risk is calculated from the executable market side:
// BUY  entry = Ask, risk distance = Ask - SL
// SELL entry = Bid, risk distance = SL - Bid
//
// This naturally includes the Bid/Ask difference without shifting the broker SL.

double tp_spread_base=0;
void TP_SpreadStop(bool new_base)
{
   double stop=StringToDouble(ObjectGetString(0,"TradePilot_SL_EDIT",OBJPROP_TEXT));
   double entry=StringToDouble(ObjectGetString(0,"TradePilot_ENTRY_EDIT",OBJPROP_TEXT));
   if(stop<=0 || entry<=0) return;
   if(new_base || tp_spread_base<=0) tp_spread_base=stop;
   double spread=MathMax(0,SymbolInfoDouble(Symbol(),SYMBOL_ASK)-SymbolInfoDouble(Symbol(),SYMBOL_BID));
   double effective=tp_spread_base;
   if(tp_spread_on) effective+=(tp_spread_base<entry ? -spread : spread);
   effective=NormalizeDouble(effective,(int)SymbolInfoInteger(Symbol(),SYMBOL_DIGITS));
   if(effective<=0) return;
   ObjectSetString(0,"TradePilot_SL_EDIT",OBJPROP_TEXT,DoubleToString(effective,(int)SymbolInfoInteger(Symbol(),SYMBOL_DIGITS)));
   if(ObjectFind(0,"TradePilot_SL_LINE")>=0) ObjectSetDouble(0,"TradePilot_SL_LINE",OBJPROP_PRICE1,effective);
   ObjectSetString(0,"TradePilot_SPREAD_TOGGLE",OBJPROP_TEXT,tp_spread_on?"SPREAD ON":"SPREAD OFF");
   ObjectSetInteger(0,"TradePilot_SPREAD_TOGGLE",OBJPROP_BGCOLOR,tp_spread_on?C'35,115,80':C'140,45,45');
   CalculatePositionSize();ChartRedraw();
}

void UpdateStopLossFromLine()
{
   if(
      !sl_line_enabled ||
      ObjectFind(0, "TradePilot_SL_LINE") < 0
   )
      return;

   double stop =
      NormalizeDouble(
         ObjectGetDouble(
            0,
            "TradePilot_SL_LINE",
            OBJPROP_PRICE1
         ),
         PriceDigits()
      );

   if(stop <= 0.0)
      return;

   ObjectSetString(
      0,
      "TradePilot_SL_EDIT",
      OBJPROP_TEXT,
      DoubleToString(stop, PriceDigits())
   );

   ChartRedraw();
}


void UpdateStopLossLineFromInput()
{
   if(!sl_line_enabled)
      return;

   double stop =
      StringToDouble(
         ObjectGetString(
            0,
            "TradePilot_SL_EDIT",
            OBJPROP_TEXT
         )
      );

   if(stop <= 0.0)
      return;

   stop = NormalizeDouble(stop, PriceDigits());

   ObjectSetString(
      0,
      "TradePilot_SL_EDIT",
      OBJPROP_TEXT,
      DoubleToString(stop, PriceDigits())
   );

   if(ObjectFind(0, "TradePilot_SL_LINE") < 0)
      CreateStopLossLine();

   ObjectSetDouble(
      0,
      "TradePilot_SL_LINE",
      OBJPROP_PRICE1,
      stop
   );

   ChartRedraw();
}


void UpdateSLButton()
{
   if(ObjectFind(
      0,
      "TradePilot_SL_TOGGLE"
   ) < 0)
      return;

   ObjectSetString(
      0,
      "TradePilot_SL_TOGGLE",
      OBJPROP_TEXT,
      sl_line_enabled
      ? "SL LINE ON"
      : "SL LINE OFF"
   );

   ObjectSetInteger(
      0,
      "TradePilot_SL_TOGGLE",
      OBJPROP_BGCOLOR,
      sl_line_enabled
      ? C'35,115,80'
      : C'140,45,45'
   );
}


// ============================================================
// PANEL
// ============================================================

void DeletePanelObjects()
{
   ObjectsDeleteAll(0,"TPUI_");
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name =
         ObjectName(
            0,
            i,
            -1,
            -1
         );

      if(StringFind(name, "TradePilot_") == 0)
         ObjectDelete(0, name);
   }
}

void CreatePanel()
{
   // Remove scrollbar objects left behind by any older EA build.
   ObjectDelete(0, "TradePilot_SCROLL_TRACK");
   ObjectDelete(0, "TradePilot_SCROLL_THUMB");
   ObjectDelete(0, "TradePilot_SCROLL_LEFT");
   ObjectDelete(0, "TradePilot_SCROLL_RIGHT");
   ObjectDelete(0, "TradePilot_SCROLL_UP");
   ObjectDelete(0, "TradePilot_SCROLL_DOWN");

   CalculatePanelScale();

   string currency =
      AccountCurrencyText();

   int digits =
      PriceDigits();

   double current_price =
      CurrentAsk();

   int px = PanelX();
   int py = PanelY();
   int pw = PanelWidth();

   CreateRectangle(
      "TradePilot_PANEL",
      px,
      py,
      pw,
      PanelHeight(),
      C'25,28,35',
      C'70,75,85'
   );

   CreateRectangle(
      "TradePilot_HEADER",
      px,
      py,
      pw,
      S(42),
      C'35,39,48',
      C'35,39,48'
   );

   CreateLabel(
      "TradePilot_TITLE",
      "TRADEPILOT",
      LabelX(),
      py + S(6),
      FontSize(BASE_FONT_TITLE),
      clrWhite
   );

   CreateLabel(
      "TradePilot_SUBTITLE",
      "By Tinashe Chimanikire",
      LabelX(),
      py + S(20),
      FontSize(BASE_FONT_SMALL),
      C'160,165,175'
   );
   CreateLabel("TradePilot_DESCRIPTION","Trade management",LabelX(),py+S(32),FontSize(BASE_FONT_SMALL),C'160,165,175');

   // Manual scale controls aligned with the management subtitle.
   // Zoom controls are created after panel backgrounds by TP_PanelVisibility.



   // SECTION BOUNDARIES
   // Each major subject has its own visible border.
   CreateRectangle(
      "TradePilot_CURRENT_BORDER",
      px + S(6), py + S(46),
      pw - S(12), S(101),
      C'25,28,35', C'70,75,85'
   );

   CreateRectangle(
      "TradePilot_CARRY_BORDER",
      px + S(6), py + S(153),
      pw - S(12), S(79),
      C'25,28,35', C'70,75,85'
   );

   CreateRectangle(
      "TradePilot_DAILY_BORDER",
      px + S(6), py + S(41),
      pw - S(12), S(329),
      C'25,28,35', C'70,75,85'
   );

   CreateRectangle(
      "TradePilot_SIZER_BORDER",
      px + S(6), py + S(373),
      pw - S(12), S(331),
      C'25,28,35', C'70,75,85'
   );


   CreateRectangle("TradePilot_BASKET_COLUMN_BG",PanelX()+PanelWidth()+S(12),PanelY(),S(304),S(322),C'25,28,35',C'70,75,85');
   // CURRENT BASKET
   CreateLabel("TradePilot_BASKET_TITLE", "CURRENT BASKET",
               LabelX(), py + S(51), FontSize(BASE_FONT_SECTION), C'90,180,255');

   CreateLabel("TradePilot_POSITIONS_LABEL", "Positions",
               LabelX(), py + S(72), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_POSITIONS_VALUE", "0", py + S(72), clrWhite);

   CreateLabel("TradePilot_PROFIT_LABEL", "Floating P/L",
               LabelX(), py + S(91), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_PROFIT_VALUE", "0.00", py + S(91), clrWhite);

   CreateLabel("TradePilot_TP_VALUE_LABEL", "Remaining Target",
               LabelX(), py + S(110), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_TARGET_VALUE", "0.00", py + S(110), C'90,220,140');
   CreateLabel("TradePilot_TARGET_UNIT", currency,
               UnitX(), py + S(111), FontSize(BASE_FONT_SMALL), C'160,165,175');

   CreateLabel("TradePilot_STATUS_LABEL", "Status",
               LabelX(), py + S(129), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_STATUS_VALUE", "WAITING", py + S(129), C'255,190,80');


   // CARRY-OVER
   CreateLabel("TradePilot_CARRY_TITLE", "CARRY-OVER",
               LabelX(), py + S(158), FontSize(BASE_FONT_SECTION), C'90,180,255');

   CreateLabel("TradePilot_CARRY_BASKETS_LABEL", "Older Baskets",
               LabelX(), py + S(179), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_CARRY_BASKETS_VALUE", "0", py + S(179), clrWhite);

   CreateLabel("TradePilot_CARRY_POSITIONS_LABEL", "Positions",
               LabelX(), py + S(198), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_CARRY_POSITIONS_VALUE", "0", py + S(198), clrWhite);

   CreateLabel("TradePilot_CARRY_PL_LABEL", "Floating P/L",
               LabelX(), py + S(217), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_CARRY_PL_VALUE", "0.00", py + S(217), clrWhite);


   // DAILY PERFORMANCE
   CreateLabel("TradePilot_DAILY_TITLE", "DAILY PERFORMANCE",
               LabelX(), py + S(46), FontSize(BASE_FONT_SECTION), C'90,180,255');
   CreateLabel("TradePilot_DAILY_MODE_LABEL", "Target Mode",
               LabelX(), py + S(67), FontSize(BASE_FONT_NORMAL), C'190,195,205');

   CreateButton(
      "TradePilot_DAILY_MODE_BUTTON",
      TPDR_Enabled()?"Ratio":(daily_percentage_mode ? "Percentage" : "Cash"),
      ValueX(),
      py + S(63),
      S(88),
      S(19),
      C'55,60,70'
   );

   CreateLabel("TradePilot_DAILY_TARGET_LABEL", "Daily Target",
               LabelX(), py + S(91), FontSize(BASE_FONT_NORMAL), C'190,195,205');

   CreateEdit(
      "TradePilot_DAILY_TARGET_EDIT",
      DoubleToString(daily_target_value, 2),
      ValueX(),
      py + S(87),
      S(72),
      S(19)
   );

   CreateLabel(
      "TradePilot_DAILY_TARGET_UNIT",
      daily_percentage_mode ? "%" : currency,
      UnitX(),
      py + S(91),
      FontSize(BASE_FONT_SMALL),
      C'160,165,175'
   );

   CreateLabel("TradePilot_CLOSED_PL_LABEL", "Closed P/L",
               LabelX(), py + S(289), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_CLOSED_PL_VALUE", "0.00", py + S(289), clrWhite);

   CreateLabel("TradePilot_CLOSED_PERCENT_LABEL", "Closed P/L %",
               LabelX(), py + S(308), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_CLOSED_PERCENT_VALUE", "0.00%", py + S(308), clrWhite);

   CreateLabel("TradePilot_DAILY_REMAINING_LABEL", "Remaining Target",
               LabelX(), py + S(327), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_DAILY_REMAINING_VALUE", "0.00", py + S(327), C'90,220,140');

   CreateLabel("TradePilot_DAILY_STATUS_LABEL", "Status",
               LabelX(), py + S(346), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_DAILY_STATUS_VALUE", "ACTIVE", py + S(346), C'255,190,80');


   // POSITION SIZER
   CreateLabel("TradePilot_SIZER_TITLE", "POSITION SIZER",
               LabelX(), py + S(382), FontSize(BASE_FONT_SECTION), C'90,180,255');

   CreateLabel("TradePilot_SYMBOL_LABEL", "Symbol",
               LabelX(), py + S(403), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_SYMBOL_VALUE", Symbol(), py + S(403), clrWhite);

   CreateLabel("TradePilot_SPREAD_LABEL", "Current Spread",
               LabelX(), py + S(422), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_SPREAD_VALUE", "0.0", py + S(422), clrWhite);
   CreateLabel("TradePilot_SPREAD_UNIT", "points",
               UnitX(), py + S(423), FontSize(BASE_FONT_SMALL), C'160,165,175');

   CreateLabel("TradePilot_RISK_MODE_LABEL", "Risk Mode",
               LabelX(), py + S(446), FontSize(BASE_FONT_NORMAL), C'190,195,205');

   CreateButton(
      "TradePilot_RISK_MODE_BUTTON",
      risk_percentage_mode ? "Percentage" : "Money",
      ValueX(),
      py + S(442),
      S(88),
      S(19),
      C'55,60,70'
   );

   CreateLabel("TradePilot_RISK_LABEL", "Risk",
               LabelX(), py + S(470), FontSize(BASE_FONT_NORMAL), C'190,195,205');

   CreateEdit(
      "TradePilot_RISK_EDIT",
      DoubleToString(risk_value, 2),
      ValueX(),
      py + S(466),
      S(72),
      S(19)
   );

   CreateLabel(
      "TradePilot_RISK_UNIT",
      risk_percentage_mode ? "%" : currency,
      UnitX(),
      py + S(470),
      FontSize(BASE_FONT_SMALL),
      C'160,165,175'
   );

   CreateLabel("TradePilot_ENTRY_LABEL", "Entry Price",
               LabelX(), py + S(494), FontSize(BASE_FONT_NORMAL), C'190,195,205');

   CreateEdit(
      "TradePilot_ENTRY_EDIT",
      DoubleToString(current_price, digits),
      ValueX(),
      py + S(490),
      S(96),
      S(19)
   );

   double initial_sl =
      current_price -
      100.0 *
      PointSize();

   CreateLabel("TradePilot_SL_LABEL", "Stop Loss",
               LabelX(), py + S(518), FontSize(BASE_FONT_NORMAL), C'190,195,205');

   CreateEdit(
      "TradePilot_SL_EDIT",
      DoubleToString(initial_sl, digits),
      ValueX(),
      py + S(514),
      S(96),
      S(19)
   );

   CreateButton(
      "TradePilot_SL_TOGGLE",
      sl_line_enabled ? "SL LINE ON" : "SL LINE OFF",
      LabelX(),
      py + S(538),
      S(88),
      S(19),
      sl_line_enabled
      ? C'35,115,80'
      : C'140,45,45'
   );

   CreateButton("TradePilot_SPREAD_TOGGLE",tp_spread_on?"SPREAD ON":"SPREAD OFF",ValueX(),py + S(538),S(124),S(19),tp_spread_on?C'35,115,80':C'140,45,45');
   ObjectSetString(0,"TradePilot_SPREAD_TOGGLE",OBJPROP_TOOLTIP,"ON moves the planned stop one current spread farther from entry and recalculates size. OFF restores the unadjusted stop. Starts OFF. It does not change stops on existing trades.");

   CreateLabel("TradePilot_CALCULATED_LABEL", "Calculated Size",
               LabelX(), py + S(566), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_CALCULATED_VALUE", "Not calculated", py + S(566), clrOrange);
   CreateLabel("TradePilot_CALCULATED_UNIT", "lots",
               UnitX(), py + S(567), FontSize(BASE_FONT_SMALL), C'160,165,175');

   CreateLabel("TradePilot_BROKER_MAX_LABEL", "Broker Max",
               LabelX(), py + S(588), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_BROKER_MAX_VALUE", "0.00", py + S(588), clrWhite);
   CreateLabel("TradePilot_BROKER_MAX_UNIT", "lots",
               UnitX(), py + S(588), FontSize(BASE_FONT_SMALL), C'160,165,175');

   CreateLabel("TradePilot_MARGIN_LABEL", "Required Margin",
               LabelX(), py + S(610), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_MARGIN_VALUE", "Not verified", py + S(610), clrWhite);
   CreateLabel("TradePilot_MARGIN_UNIT", currency,
               UnitX(), py + S(611), FontSize(BASE_FONT_SMALL), C'160,165,175');


   CreateButton("TradePilot_CALCULATE_BUTTON","CALCULATE",LabelX(),py+S(626),pw-S(22),S(21),C'45,105,155');

   CreateButton("TradePilot_BUY_BUTTON","BUY",LabelX(),py+S(652),pw-S(22),S(21),C'35,115,80');

   CreateButton("TradePilot_SELL_BUTTON","SELL",LabelX(),py+S(678),pw-S(22),S(21),C'140,45,45');

   ObjectDelete(0,"TradePilot_SIGNATURE");

   if(sl_line_enabled)
      CreateStopLossLine();


}

void SyncStopLossLineWithoutSpread()
{
   if(!sl_line_enabled)
      return;

   double stop =
      StringToDouble(
         ObjectGetString(
            0,
            "TradePilot_SL_EDIT",
            OBJPROP_TEXT
         )
      );

   if(stop <= 0.0)
      return;

   if(ObjectFind(0, "TradePilot_SL_LINE") < 0)
      CreateStopLossLine();

   ObjectSetDouble(
      0,
      "TradePilot_SL_LINE",
      OBJPROP_PRICE1,
      NormalizeDouble(stop, PriceDigits())
   );

   ObjectSetInteger(
      0,
      "TradePilot_SL_LINE",
      OBJPROP_COLOR,
      clrRed
   );

   ChartRedraw();
}


void RebuildResponsivePanel()
{
   // Preserve current editable values before rebuilding.
   string risk_text = "";
   string entry_text = "";
   string sl_text = "";
   string daily_text = "";

   if(ObjectFind(0, "TradePilot_RISK_EDIT") >= 0)
      risk_text = ObjectGetString(0, "TradePilot_RISK_EDIT", OBJPROP_TEXT);

   if(ObjectFind(0, "TradePilot_ENTRY_EDIT") >= 0)
      entry_text = ObjectGetString(0, "TradePilot_ENTRY_EDIT", OBJPROP_TEXT);

   if(ObjectFind(0, "TradePilot_SL_EDIT") >= 0)
      sl_text = ObjectGetString(0, "TradePilot_SL_EDIT", OBJPROP_TEXT);

   if(ObjectFind(0, "TradePilot_DAILY_TARGET_EDIT") >= 0)
      daily_text = ObjectGetString(0, "TradePilot_DAILY_TARGET_EDIT", OBJPROP_TEXT);

   CreatePanel();

   if(risk_text != "")
      ObjectSetString(0, "TradePilot_RISK_EDIT", OBJPROP_TEXT, risk_text);

   if(entry_text != "")
      ObjectSetString(0, "TradePilot_ENTRY_EDIT", OBJPROP_TEXT, entry_text);

   if(sl_text != "")
      ObjectSetString(0, "TradePilot_SL_EDIT", OBJPROP_TEXT, sl_text);

   if(daily_text != "")
      ObjectSetString(0, "TradePilot_DAILY_TARGET_EDIT", OBJPROP_TEXT, daily_text);

   if(sl_line_enabled)
      SyncStopLossLineWithoutSpread();

   TP_DailyEquivalent();
   TPDL_ClosedSummary();
   TPDL_FinalStatus();
   TPC_Render();TPDC_Render();
   TP_BasketColumnLayout();
   TP_PanelVisibility();
   ChartRedraw();
}


// ============================================================
// PANEL UPDATE
// ============================================================

void UpdatePanelBackground(double closed_pl, double target_money)
{
   color panel_color = C'25,28,35';
   color header_color = C'35,39,48';

   if(closed_pl < 0.0)
   {
      panel_color = C'52,29,31';
      header_color = C'72,34,37';
   }
   else if(target_money > 0.0 && closed_pl >= target_money)
   {
      panel_color = C'27,48,35';
      header_color = C'31,67,44';
   }

   ObjectSetInteger(
      0,
      "TradePilot_PANEL",
      OBJPROP_BGCOLOR,
      panel_color
   );

   ObjectSetInteger(
      0,
      "TradePilot_HEADER",
      OBJPROP_BGCOLOR,
      header_color
   );
}

void UpdatePanel()
{
   TP_DailyChoiceRender();
   TP_BasketColumnLayout();

   TPDL_Render();
   datetime current_session =
      GetSessionStartForTime(TPDL_Now());

   EnsureSessionState(current_session);

   int positions =
      GetSessionOpenOrderCount(
         current_session
      );

   double floating =
      GetSessionFloatingPL(
         current_session
      );

   double closed =
      GetSessionClosedPL(
         current_session
      );

   double closed_percent =
      GetSessionClosedPercent(
         current_session
      );

   double target_money =
      GetSessionTargetMoney(
         current_session
      );

   double remaining =
      GetSessionRemainingTargetMoney(
         current_session
      );

   int carry_baskets =
      GetCarryOverBasketCount();

   int carry_positions =
      GetCarryOverOrderCount();

   double carry_pl =
      GetCarryOverFloatingPL();

   ObjectSetString(0, "TradePilot_POSITIONS_VALUE", OBJPROP_TEXT,
                   IntegerToString(positions));

   ObjectSetString(0, "TradePilot_PROFIT_VALUE", OBJPROP_TEXT,
                   DoubleToString(floating, 2));

   ObjectSetString(0, "TradePilot_TARGET_VALUE", OBJPROP_TEXT,
                   DoubleToString(remaining, 2));

   double display_base=GetSessionStartBalance(current_session);
   ObjectSetString(0,"TradePilot_TARGET_VALUE",OBJPROP_TEXT,daily_percentage_mode && display_base>0 ? DoubleToString(remaining/display_base*100,2)+"% ("+AccountCurrencyText()+" "+DoubleToString(remaining,2)+")" : DoubleToString(remaining,2));
   ObjectSetString(0,"TradePilot_TARGET_UNIT",OBJPROP_TEXT,daily_percentage_mode ? "" : AccountCurrencyText());
   ObjectSetInteger(0,"TradePilot_TARGET_UNIT",OBJPROP_TIMEFRAMES,daily_percentage_mode?OBJ_NO_PERIODS:OBJ_ALL_PERIODS);
   ObjectSetString(0, "TradePilot_STATUS_VALUE", OBJPROP_TEXT,
                   positions > 0 ? "ACTIVE" : "WAITING");

   ObjectSetString(0, "TradePilot_CARRY_BASKETS_VALUE", OBJPROP_TEXT,
                   IntegerToString(carry_baskets));

   ObjectSetString(0, "TradePilot_CARRY_POSITIONS_VALUE", OBJPROP_TEXT,
                   IntegerToString(carry_positions));

   ObjectSetString(0, "TradePilot_CARRY_PL_VALUE", OBJPROP_TEXT,
                   DoubleToString(carry_pl, 2));

   ObjectSetString(0, "TradePilot_CLOSED_PL_VALUE", OBJPROP_TEXT,
                   DoubleToString(closed, 2));

   ObjectSetString(0, "TradePilot_CLOSED_PERCENT_VALUE", OBJPROP_TEXT,
                   DoubleToString(closed_percent, 2) + "%");

   ObjectSetString(0, "TradePilot_DAILY_REMAINING_VALUE", OBJPROP_TEXT,
                   DoubleToString(remaining, 2));

   ObjectSetString(
      0,
      "TradePilot_DAILY_STATUS_VALUE",
      OBJPROP_TEXT,
      remaining<=0 && target_money>0
      ? "TARGET REACHED"
      : "ACTIVE"
   );

   ObjectSetString(
      0,
      "TradePilot_SPREAD_VALUE",
      OBJPROP_TEXT,
      DoubleToString(
         GetCurrentSpreadPoints(),
         1
      )
   );

   ObjectSetString(
      0,
      "TradePilot_DAILY_TARGET_UNIT",
      OBJPROP_TEXT,
      daily_percentage_mode
      ? "%"
      : AccountCurrencyText()
   );

   ObjectSetString(
      0,
      "TradePilot_RISK_UNIT",
      OBJPROP_TEXT,
      risk_percentage_mode
      ? "%"
      : AccountCurrencyText()
   );

   UpdatePanelBackground(
      GetSessionClosedPL(GetSessionStartForTime(TPDL_Now()),true),
      target_money
   );

   TP_DailyEquivalent();
   TPDL_ClosedSummary();
   TPDL_FinalStatus();
   TPC_Render();TPDC_Render();
   TP_BasketColumnLayout();
   TP_PanelVisibility();
   ChartRedraw();
}


// ============================================================
// INITIALIZATION / CLEANUP
// ============================================================

bool tp_panel_ready=false;

int OnInit()
{

   // Return control to MT4 before synchronous chart setup during profile load.
   tp_panel_ready=false;
   if(!EventSetTimer(1)) return INIT_FAILED;
   Print("TradePilot startup queued; waiting for terminal chart readiness.");
   return INIT_SUCCEEDED;
}

void TP_InitializePanel()
{
   Print("TradePilot startup phase: chart cleanup");
   // Start from a clean panel state, including objects from older versions.
   DeletePanelObjects();
   // Chart APIs run only after MT4 has returned from initial profile loading.
   ObjectsDeleteAll(0,"TPP_");ObjectsDeleteAll(0,"TPM_");

   BuildGlobalVariableNames();
   LoadSharedSettings();
   Print("TradePilot startup phase: session state");

   datetime current_session =
      GetSessionStartForTime(TPDL_Now());

   EnsureSessionState(
      current_session
   );

   Print("TradePilot startup phase: panel creation");
   CreatePanel();
   UpdatePanel();

   Print(
      "TradePilot MT4 started. Session: ",
      TimeToString(
         current_session,
         TIME_DATE | TIME_SECONDS
      )
   );

   Print("TradePilot startup phase: connection owner");
   TP_LocalInit();
   TPM_Init();
   tp_panel_ready=true;
}

void OnDeinit(const int reason)
{
   TPP_Deinit();
   if(!tp_panel_ready) { EventKillTimer(); TP_LocalDeinit(); return; }
   ObjectsDeleteAll(0, "TPM_");
   // Always restore normal MT4 chart mouse scrolling.
   ChartSetInteger(
      0,
      CHART_MOUSE_SCROLL,
      true
   );


   TP_LocalDeinit();
   EventKillTimer();

   DeletePanelObjects();

   ChartRedraw();

   Print(
      "TradePilot MT4 stopped."
   );
}


// ============================================================
// TICK / TIMER
// ============================================================

void OnTick()
{
   // Basket management is timer-driven so it is not dependent
   // only on ticks from this chart's symbol.
}

void OnTimer()
{
   TPP_Poll();
   if(!tp_panel_ready) { TP_InitializePanel(); return; }
   TP_LocalPoll();
   TP_ChartPoll();
   TPM_Render();
   // Pull shared settings changed by another chart instance.
   risk_percentage_mode =
      GlobalVariableGet(GV_RISK_MODE) > 0.5;

   risk_value =
      GlobalVariableGet(GV_RISK_VALUE);

   daily_percentage_mode =
      GlobalVariableGet(GV_DAILY_MODE) > 0.5;

   daily_target_value =
      GlobalVariableGet(GV_DAILY_VALUE);

   CheckBasketTakeProfit();
   UpdatePanel();
}


// ============================================================
// CHART EVENTS
// ============================================================

void OnChartEvent(
   const int id,
   const long &lparam,
   const double &dparam,
   const string &sparam
)
{
 if(id==CHARTEVENT_OBJECT_CLICK && TP_PanelToggle(sparam))return;
 if(id==CHARTEVENT_OBJECT_ENDEDIT && sparam=="TradePilot_SCALE_VALUE") {
  if(tp_spread_confirm_open||tpc_open||tpdc_open){ObjectSetString(0,sparam,OBJPROP_TEXT,DoubleToString(manual_panel_scale*100.0,1)+"%");return;}
  string text=ObjectGetString(0,sparam,OBJPROP_TEXT);StringTrimLeft(text);StringTrimRight(text);
  if(StringLen(text)>0 && StringSubstr(text,StringLen(text)-1)=="%")text=StringSubstr(text,0,StringLen(text)-1);
  bool valid=StringLen(text)>0;bool dot=false;
  for(int i=0;i<StringLen(text);i++){ushort c=StringGetCharacter(text,i);if(c==46&&!dot){dot=true;continue;}if(c<48||c>57)valid=false;}
  double percent=StringToDouble(text);
  if(!valid||!MathIsValidNumber(percent)||percent<50||percent>150){Alert("Enter a zoom percentage from 50 to 150, for example 100%.");ObjectSetString(0,sparam,OBJPROP_TEXT,DoubleToString(manual_panel_scale*100.0,1)+"%");return;}
  manual_panel_scale=percent/100.0;
  manual_scale_override=true;
  GlobalVariableSet(GV_PANEL_SCALE,manual_panel_scale);GlobalVariablesFlush();
  RebuildResponsivePanel();TPM_Render();return;
 }

 if(id==CHARTEVENT_OBJECT_CLICK && tp_spread_confirm_open) {
  if(sparam=="TradePilot_SPREAD_CONFIRM_CANCEL"){TP_SpreadTradeClose();return;}
  if(sparam=="TradePilot_SPREAD_CONFIRM_CONTINUE"){int side=tp_spread_pending_side;bool calculation=tp_spread_pending_calculation;TP_SpreadTradeClose();if(calculation)TP_CalculateRequested(true);else ExecutePanelTrade(side,true);return;}
  return;
 }

   if(tpc_open&&id==CHARTEVENT_OBJECT_CLICK){TPC_Event(sparam);return;}

   if(tpdc_open&&id==CHARTEVENT_OBJECT_CLICK){TP_DailyChoiceEvent(sparam);return;}

   if(!tp_panel_ready) return;
   if(id==CHARTEVENT_OBJECT_CLICK && sparam=="TradePilot_SPREAD_TOGGLE")
   {
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      if(StringToDouble(ObjectGetString(0,"TradePilot_SL_EDIT",OBJPROP_TEXT))<=0 || StringToDouble(ObjectGetString(0,"TradePilot_ENTRY_EDIT",OBJPROP_TEXT))<=0) {Alert("Enter a valid entry and planned stop before switching Spread ON/OFF.");return;}
      if(!tp_spread_on) tp_spread_base=StringToDouble(ObjectGetString(0,"TradePilot_SL_EDIT",OBJPROP_TEXT));
      tp_spread_on=!tp_spread_on;TP_SpreadStop(false);return;
   }
   if(TPP_Event(id, sparam)) return;
   if(TPM_Event(id, sparam)) return;
   // Automatically re-fit the complete panel when chart/monitor dimensions change.
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      static long previous_width=-1,previous_height=-1;
      long width=ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),height=ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
      if(width==previous_width && height==previous_height)return;
      previous_width=width;previous_height=height;

      RebuildResponsivePanel();
      TPM_Render();
      return;
   }

   // SL line dragged.
   if(
      id == CHARTEVENT_OBJECT_DRAG &&
      sparam == "TradePilot_SL_LINE"
   )
   {
      UpdateStopLossFromLine();
      TP_SpreadStop(true);
      return;
   }

   // Edited text committed.
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == "TradePilot_SL_EDIT")
      {
         UpdateStopLossLineFromInput();
         TP_SpreadStop(true);
         return;
      }

      if(sparam == "TradePilot_RISK_EDIT")
      {
         double value =
            StringToDouble(
               ObjectGetString(
                  0,
                  "TradePilot_RISK_EDIT",
                  OBJPROP_TEXT
               )
            );

         if(value > 0.0)
         {
            risk_value = value;
            GlobalVariableSet(
               GV_RISK_VALUE,
               risk_value
            );
         }

         return;
      }

      if(sparam == "TradePilot_DAILY_TARGET_EDIT")
      {
         // Keep the edited target pending until Update is confirmed.
         return;
      }
   }

   if(id != CHARTEVENT_OBJECT_CLICK)
      return;


   // CLOSE / REMOVE EA FROM THIS CHART
   // Trades remain untouched.



   // PANEL SCALE -
   if(sparam == "TradePilot_SCALE_MINUS")
   {
      manual_scale_override = true;

      ObjectSetInteger(
         0,
         sparam,
         OBJPROP_STATE,
         false
      );

      manual_panel_scale -= 0.01;

      if(manual_panel_scale < 0.50)
         manual_panel_scale = 0.50;

      GlobalVariableSet(
         GV_PANEL_SCALE,
         manual_panel_scale
      );

      RebuildResponsivePanel();
      TPM_Render();
      return;
   }


   // PANEL SCALE +
   if(sparam == "TradePilot_SCALE_PLUS")
   {
      manual_scale_override = true;

      ObjectSetInteger(
         0,
         sparam,
         OBJPROP_STATE,
         false
      );

      manual_panel_scale += 0.01;

      if(manual_panel_scale > 1.50)
         manual_panel_scale = 1.50;

      GlobalVariableSet(
         GV_PANEL_SCALE,
         manual_panel_scale
      );

      RebuildResponsivePanel();
      TPM_Render();
      return;
   }


   // DAILY TARGET MODE
   if(TPDR_Event(sparam)) return;
   if(TPDL_Event(sparam)) return;
   if(TPC_Event(sparam)) return;
   if(TP_DailyChoiceEvent(sparam)) return;
   if(sparam == "TradePilot_DAILY_MODE_BUTTON")
   {
      ObjectSetInteger(
         0,
         sparam,
         OBJPROP_STATE,
         false
      );

      daily_percentage_mode =
         !daily_percentage_mode;

      GlobalVariableSet(
         GV_DAILY_MODE,
         daily_percentage_mode
         ? 1.0
         : 0.0
      );

      UpdateCurrentSessionTargetFromUI();

      ObjectSetString(
         0,
         "TradePilot_DAILY_MODE_BUTTON",
         OBJPROP_TEXT,
         daily_percentage_mode
         ? "Percentage"
         : "Money"
      );

      ObjectSetString(
         0,
         "TradePilot_DAILY_TARGET_UNIT",
         OBJPROP_TEXT,
         daily_percentage_mode
         ? "%"
         : AccountCurrencyText()
      );

      UpdatePanel();
      return;
   }


   // RISK MODE
   if(sparam == "TradePilot_RISK_MODE_BUTTON")
   {
      ObjectSetInteger(
         0,
         sparam,
         OBJPROP_STATE,
         false
      );

      risk_percentage_mode =
         !risk_percentage_mode;

      GlobalVariableSet(
         GV_RISK_MODE,
         risk_percentage_mode
         ? 1.0
         : 0.0
      );

      ObjectSetString(
         0,
         "TradePilot_RISK_MODE_BUTTON",
         OBJPROP_TEXT,
         risk_percentage_mode
         ? "Percentage"
         : "Money"
      );

      ObjectSetString(
         0,
         "TradePilot_RISK_UNIT",
         OBJPROP_TEXT,
         risk_percentage_mode
         ? "%"
         : AccountCurrencyText()
      );

      ChartRedraw();
      return;
   }


   // STOP LOSS LINE ON/OFF
   if(sparam == "TradePilot_SL_TOGGLE")
   {
      ObjectSetInteger(
         0,
         sparam,
         OBJPROP_STATE,
         false
      );

      sl_line_enabled =
         !sl_line_enabled;

      GlobalVariableSet(
         GV_SL_ENABLED,
         sl_line_enabled
         ? 1.0
         : 0.0
      );

      if(sl_line_enabled)
         CreateStopLossLine();
      else
         DeleteStopLossLine();

      UpdateSLButton();
      ChartRedraw();
      return;
   }


   // Sizing uses stop-loss price risk consistently across master and follower



   // EXECUTE BUY FROM PANEL
   if(sparam == "TradePilot_BUY_BUTTON")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ExecutePanelTrade(OP_BUY);
      return;
   }


   // EXECUTE SELL FROM PANEL
   if(sparam == "TradePilot_SELL_BUTTON")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ExecutePanelTrade(OP_SELL);
      return;
   }


   // POSITION SIZE CALCULATION
   if(sparam == "TradePilot_CALCULATE_BUTTON")
   {
      ObjectSetInteger(
         0,
         sparam,
         OBJPROP_STATE,
         false
      );

      TP_CalculateRequested();
      return;
   }
}

// ============================================================
// POINT MEASURER: chart-only state; no trading or shared-risk calls.
// Separate prefix deliberately survives the manager's TradePilot_ rebuilds.
// ============================================================
input double TPM_PipSizeOverride = 0.0; // Optional pip price size; 0 = forex auto, other symbols points only
bool tpm_on = false;
bool tpm_percent = true;
double tpm_risk = 1.0;
double tpm_prices[3];
double tpm_scale = 1.0;
string tpm_names[3] = {"ENTRY", "STOP LOSS", "TAKE PROFIT"};
color tpm_colors[3] = {clrDodgerBlue, clrTomato, clrLimeGreen};

double TPM_PipSize()
{
   if(TPM_PipSizeOverride > 0.0) return TPM_PipSizeOverride;
   string currencies = "|USD|EUR|GBP|JPY|CHF|CAD|AUD|NZD|ZAR|CNH|CNY|HKD|SGD|NOK|SEK|DKK|PLN|CZK|HUF|TRY|MXN|BRL|RUB|INR|KRW|ILS|THB|AED|SAR|";
   string base_currency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string quote_currency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   if(base_currency == "" || quote_currency == "" ||
      StringFind(currencies, "|"+base_currency+"|") < 0 ||
      StringFind(currencies, "|"+quote_currency+"|") < 0) return 0.0;
   // Native platform adapter: do not assume that metals/indices have forex pips.
   if((int)MarketInfo(_Symbol, MODE_PROFITCALCMODE) == 0) return _Point * ((_Digits == 3 || _Digits == 5) ? 10.0 : 1.0);
   return 0.0;
}

int TPM_S(double value) { return (int)MathRound(value * tpm_scale); }
int TPM_X() { return PanelX() + PanelWidth() + S(12 + 304 + 12); }
string TPM_Line(int i) { return "TPM_LINE_" + IntegerToString(i); }

void TPM_Widget(string key, ENUM_OBJECT type, int x, int y, int w, int h,
                string text, color foreground, color background, int font=9)
{
   string name = "TPM_" + key;
   bool fresh = ObjectFind(0, name) < 0;
   if(fresh && !ObjectCreate(0, name, type, 0, 0, 0)) return;
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, TPM_X()+TPM_S(x));
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, PanelY()+TPM_S(y));
   ObjectSetInteger(0, name, OBJPROP_COLOR, foreground);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, type == OBJ_RECTANGLE_LABEL ? 0 : 20);
   if(type == OBJ_LABEL) ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   else
   {
      ObjectSetInteger(0, name, OBJPROP_XSIZE, TPM_S(w));
      ObjectSetInteger(0, name, OBJPROP_YSIZE, TPM_S(h));
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'65,74,90');
   }
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FontSize(key=="TITLE"?BASE_FONT_SECTION:BASE_FONT_NORMAL));
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   // Never overwrite a partially typed risk value during timer/resize refreshes.
   if(type != OBJ_EDIT || fresh) ObjectSetString(0, name, OBJPROP_TEXT, text);
   if(type == OBJ_EDIT) ObjectSetInteger(0, name, OBJPROP_READONLY, false);
   if(type == OBJ_LABEL) ObjectSetString(0,name,OBJPROP_TOOLTIP,TP_LabelHelp(name,text));
   if(type == OBJ_EDIT) ObjectSetString(0,name,OBJPROP_TOOLTIP,"Measurement risk input. Use the unit shown in the Point Measurer. Example: 1 for 1 percent. This panel only measures; it does not place a trade.");
}

void TPM_ReadRisk()
{
   if(ObjectFind(0, "TPM_RISK") < 0) return;
   string text = ObjectGetString(0, "TPM_RISK", OBJPROP_TEXT);
   StringTrimLeft(text); StringTrimRight(text);
   bool valid = StringLen(text) > 0;
   int dots = 0, digits = 0;
   for(int i=0; i<StringLen(text); i++)
   {
      ushort c = StringGetCharacter(text, i);
      if(c == 46) dots++;
      else if(c >= 48 && c <= 57) digits++;
      else valid = false;
   }
   double value = StringToDouble(text);
   if(valid && dots <= 1 && digits > 0 && MathIsValidNumber(value) && value >= 0.0 && value <= 1e12)
      tpm_risk = value;
   ObjectSetString(0, "TPM_RISK", OBJPROP_TEXT, DoubleToString(tpm_risk, 2));
}

bool TPM_EnsureLines()
{
   if(tpm_prices[0] <= 0.0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid <= 0.0) bid = iClose(_Symbol, PERIOD_CURRENT, 0);
      if(bid <= 0.0 || _Point <= 0.0) return false;
      double distance = MathMin(200 * _Point, bid * 0.1);
      tpm_prices[0] = bid;
      tpm_prices[1] = NormalizeDouble(bid-distance, _Digits);
      tpm_prices[2] = NormalizeDouble(bid+2*distance, _Digits);
   }
   for(int i=0; i<3; i++)
   {
      string name = TPM_Line(i);
      if(ObjectFind(0, name) < 0)
      {
         if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, tpm_prices[i])) return false;
         ObjectSetInteger(0, name, OBJPROP_COLOR, tpm_colors[i]);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, name, OBJPROP_SELECTED, true);
         // Keep measuring lines behind the opaque Basket Manager panels.
         ObjectSetInteger(0, name, OBJPROP_BACK, true);
         ObjectSetInteger(0, name, OBJPROP_ZORDER, 5);
         ObjectSetString(0, name, OBJPROP_TEXT, tpm_names[i]);
         ObjectSetString(0, name, OBJPROP_TOOLTIP, "Point Measurer - " + tpm_names[i] + " (measurement only)");
      }
      tpm_prices[i] = ObjectGetDouble(0, name, OBJPROP_PRICE);
      // Visible text labels do not depend on the chart's Show object descriptions setting.
      int px=0, py=0;
      string tag = "TAG_" + IntegerToString(i);
      if(ChartTimePriceToXY(0, 0, iTime(_Symbol, PERIOD_CURRENT, 0), tpm_prices[i], px, py) && py > 0)
      {
         TPM_Widget(tag, OBJ_LABEL, 12, 0, 0, 0, tpm_names[i], tpm_colors[i], clrNONE, 8);
         ObjectSetInteger(0, "TPM_"+tag, OBJPROP_BACK, true);
         ObjectSetInteger(0, "TPM_"+tag, OBJPROP_YDISTANCE, py);
         ObjectSetInteger(0, "TPM_"+tag, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
         ObjectSetInteger(0, "TPM_"+tag, OBJPROP_XDISTANCE, (int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-TPM_S(12));
      }
      else ObjectDelete(0, "TPM_"+tag);
   }
   return true;
}

string TPM_Distance(double distance)
{
   if(_Point <= 0.0) return "n/a";
   string result = DoubleToString(distance/_Point, 1) + " pts";
   double pip = TPM_PipSize();
   if(pip > 0.0) result += " / " + DoubleToString(distance/pip, 1) + " pips";
   return result;
}

bool tpm_spread_on=false;
double tpm_base_stop=0,tpm_applied_stop=0,tpm_spread_price=0,tpm_spread_cash=-1;
bool TPM_SpreadRefresh()
{
 MqlTick quote;bool fresh=_Point>0 && TerminalInfoInteger(TERMINAL_CONNECTED) && SymbolInfoTick(_Symbol,quote) && quote.ask>=quote.bid && quote.bid>0 && MathAbs((double)(TPDL_Now()-quote.time))<=15;
 tpm_spread_price=fresh?quote.ask-quote.bid:0;tpm_spread_cash=-1;
 if(tpm_base_stop<=0 || MathAbs(tpm_prices[1]-tpm_applied_stop)>_Point*0.1) tpm_base_stop=tpm_prices[1];
 if(!tpm_spread_on || fresh) {
  double stop=tpm_base_stop;
  if(tpm_spread_on) stop+=tpm_base_stop<tpm_prices[0]?-tpm_spread_price:tpm_spread_price;
  tpm_applied_stop=NormalizeDouble(stop,_Digits);tpm_prices[1]=tpm_applied_stop;
  ObjectSetDouble(0,TPM_Line(1),OBJPROP_PRICE,tpm_applied_stop);
 }
 if(fresh && tpm_spread_price>0) {
#ifdef __MQL5__
  tpm_spread_cash=GetOneLotMarketLoss(tpm_base_stop<tpm_prices[0]?ORDER_TYPE_BUY:ORDER_TYPE_SELL,tpm_prices[0],tpm_prices[0]+(tpm_base_stop<tpm_prices[0]?-tpm_spread_price:tpm_spread_price));
#else
  tpm_spread_cash=GetOneLotLoss(tpm_prices[0],tpm_prices[0]+tpm_spread_price);
#endif
  if(!MathIsValidNumber(tpm_spread_cash) || tpm_spread_cash<=0)tpm_spread_cash=-1;
 }
 TPM_Widget("SPREAD",OBJ_BUTTON,12,185,132,24,tpm_spread_on?"Spread ON":"Spread OFF",clrWhite,tpm_spread_on?C'35,115,80':C'140,45,45');
 ObjectSetString(0,"TPM_SPREAD",OBJPROP_TOOLTIP,"Use only this chart's broker spread. ON moves this measuring stop one current spread farther from entry and updates its ratio; OFF restores the base measuring stop. Dragging the stop creates a new base. It never changes a broker order or the position sizer's separate spread control.");
 string caption=fresh?"Spread: "+DoubleToString(tpm_spread_price/_Point,1)+" points":"Spread: waiting for broker quote";
 TPM_Widget("SPREAD_INFO",OBJ_LABEL,12,212,0,0,caption,clrWhite,clrNONE);
 ObjectSetString(0,"TPM_SPREAD_INFO",OBJPROP_TOOLTIP,"The current difference between this chart\'s buying and selling prices, measured in broker points. Spread ON adds this distance to the measuring stop. Waiting means a fresh broker price has not arrived.");
 TPM_Widget("SPREAD_COST",OBJ_LABEL,12,231,0,0,tpm_spread_cash>=0?"1 lot: ("+AccountInfoString(ACCOUNT_CURRENCY)+" "+DoubleToString(tpm_spread_cash,2)+")":"Spread cash value not verified",clrSilver,clrNONE,8);
 ObjectSetString(0,"TPM_SPREAD_COST",OBJPROP_TOOLTIP,"Estimated spread value for one lot using this account's broker contract and currency. Excludes commission, swap, fees and price gaps. No other broker's spread is used.");
 if(TP_LocalBridge && TP_BridgeToken!="" && TP_AccountId!="") {
  string text="MEASURE\t"+TP_BridgeToken+"\t"+TP_AccountId+"\t"+TP_Login()+"\t"+TP_Server()+"\tMT4\t"+TP_Int(TimeGMT())+"\t"+TP_Int(ChartID())+"\t"+_Symbol+"\t"+(tpm_spread_on?"1":"0")+"\t"+(fresh?"1":"0")+"\t"+TP_Num(tpm_spread_price)+"\t"+TP_Num(_Point>0?tpm_spread_price/_Point:0)+"\t"+TP_Num(tpm_spread_cash)+"\t"+AccountInfoString(ACCOUNT_CURRENCY)+"\t"+TP_Num(tpm_prices[0])+"\t"+TP_Num(tpm_prices[1])+"\t"+TP_Num(tpm_prices[2])+"\t"+TimeToString(TPDL_Now(),TIME_DATE|TIME_SECONDS)+"\r\n";
  TP_Atomic(".measurement-"+TP_Int(ChartID())+".tsv",text);
 }
 return !tpm_spread_on || fresh;
}

void TPM_Render()
{
   tpm_scale = panel_scale;
   long width = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(width > TPM_X()+12) tpm_scale = MathMin(tpm_scale, (double)(width-TPM_X()-12)/304.0);
   TPM_Widget("BG", OBJ_RECTANGLE_LABEL, 0, 0, 304, tpm_on ? 346 : 31, "", clrSlateGray, C'24,29,39');
   TPM_Widget("TITLE", OBJ_LABEL, 12, 8, 0, 0, "POINT MEASURER", C'90,180,255', clrNONE, 10);
   if(tpm_on)TPM_Widget("SUBTITLE",OBJ_LABEL,12,27,0,0,"Measurement only",clrWhite,clrNONE);
   else ObjectDelete(0,"TPM_SUBTITLE");
   TPM_Widget("TOGGLE", OBJ_BUTTON, 244, 6, 50, 24, tpm_on ? "ON" : "OFF", clrWhite, tpm_on ? C'35,115,80' : C'140,45,45');
   ObjectDelete(0,"TPM_AUTHOR");
   TPP_Render();
   if(!tpm_on) return;
   bool ready = TPM_EnsureLines();
   if(ready) {ready=TPM_SpreadRefresh();TPM_EnsureLines();}
   for(int i=0; i<3; i++)
      TPM_Widget("PRICE_"+IntegerToString(i), OBJ_LABEL, 12, 49+i*22, 0, 0,
         tpm_names[i]+"   "+(ready ? DoubleToString(tpm_prices[i], _Digits) : "waiting for price"), tpm_colors[i], clrNONE);
   double sl = MathAbs(tpm_prices[0]-tpm_prices[1]);
   double tp = MathAbs(tpm_prices[2]-tpm_prices[0]);
   bool valid = ready && sl > _Point*0.01 && _Point > 0.0;
   double rr = valid ? tp/sl : 0.0;
   TPM_Widget("SL_DIST", OBJ_LABEL, 12, 116, 0, 0, "SL   "+(ready ? TPM_Distance(sl) : "n/a"), clrWhite, clrNONE);
   TPM_Widget("TP_DIST", OBJ_LABEL, 12, 138, 0, 0, "TP   "+(ready ? TPM_Distance(tp) : "n/a"), clrWhite, clrNONE);
   TPM_Widget("RR", OBJ_LABEL, 12, 163, 0, 0, "R:R   "+(valid ? "1 : "+DoubleToString(rr,2) : "n/a (zero SL / no price)"), clrWhite, clrNONE, 10);
   TPM_Widget("RISK_CAPTION", OBJ_LABEL, 12, 264, 0, 0, "Risk", clrSilver, clrNONE);
   TPM_Widget("RISK", OBJ_EDIT, 53, 258, 108, 26, DoubleToString(tpm_risk,2), clrWhite, C'37,44,57');
   TPM_Widget("PERCENT", OBJ_BUTTON, 170, 258, 42, 26, "%", clrWhite, tpm_percent ? C'35,115,80' : C'65,70,80');
   TPM_Widget("CASH", OBJ_BUTTON, 219, 258, 73, 26, "CASH", clrWhite, tpm_percent ? C'65,70,80' : C'35,115,80');
   string unit = tpm_percent ? "%" : AccountInfoString(ACCOUNT_CURRENCY);
   bool opposite = (tpm_prices[1]<tpm_prices[0] && tpm_prices[2]>tpm_prices[0]) ||
                   (tpm_prices[1]>tpm_prices[0] && tpm_prices[2]<tpm_prices[0]);
   color potential_color=ready?(opposite?C'35,115,80':C'140,45,45'):clrSilver;
   color potential_font=ready?(opposite?tpm_colors[2]:tpm_colors[1]):clrSilver;
   TPM_Widget("RETURN_BORDER",OBJ_RECTANGLE_LABEL,8,290,288,28,"",potential_color,C'24,29,39');
   ObjectSetInteger(0,"TPM_RETURN_BORDER",OBJPROP_BORDER_COLOR,potential_color);
   TPM_Widget("RETURN", OBJ_LABEL, 12, 297, 0, 0, "Potential   "+(valid ? DoubleToString(rr*tpm_risk,2)+" "+unit : "n/a"), potential_font, clrNONE, 10);
   ObjectSetString(0,"TPM_RETURN",OBJPROP_TOOLTIP,"Potential is the measured target value. Green means entry is between Stop Loss and Take Profit. Red means both lines are on the same side of entry, so this is not a valid profit-and-loss layout. Move one line across entry. This is a measurement, not a realised trading loss.");

   ObjectSetInteger(0,"TPM_BG",OBJPROP_YSIZE,TPM_S(ready && !opposite?346:326));
   if(ready && !opposite)TPM_Widget("NOTE", OBJ_LABEL, 12, 324, 0, 0, "SL/TP not opposite entry; distance ratio only", clrSilver, clrNONE);
   else ObjectDelete(0,"TPM_NOTE");

}

void TPM_Init()
{
   ObjectsDeleteAll(0, "TPM_");
   ArrayInitialize(tpm_prices, 0.0);
   TPM_Render();
}

bool TPM_Event(const int id, const string name)
{
   if(StringFind(name, "TPM_") != 0) return false;
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(name == "TPM_SPREAD") {tpm_spread_on=!tpm_spread_on;ObjectSetInteger(0,name,OBJPROP_STATE,false);}
      else if(name == "TPM_TOGGLE")
      {
         TPM_ReadRisk();
         if(tpm_on)
            for(int i=0; i<3; i++)
               if(ObjectFind(0, TPM_Line(i)) >= 0) tpm_prices[i] = ObjectGetDouble(0, TPM_Line(i), OBJPROP_PRICE);
         tpm_on = !tpm_on;
         ObjectsDeleteAll(0, "TPM_");
      }
      else if(name == "TPM_PERCENT" || name == "TPM_CASH")
      {
         TPM_ReadRisk();
         tpm_percent = name == "TPM_PERCENT";
         ObjectSetInteger(0, name, OBJPROP_STATE, false);
      }
   }
   if(id == CHARTEVENT_OBJECT_ENDEDIT && name == "TPM_RISK") TPM_ReadRisk();
   TPM_Render();
   return true;
}

#include "TradePilotPending.mqh"
#include "TradePilotBasket.mqh"
#include "TradePilotDailyRisk.mqh"
#include "TradePilotDailyRatio.mqh"
#include "TradePilotCarry.mqh"


bool tp_daily_wins=false,tp_daily_losses=false;
bool tpdc_loss=false;string tpdc_loss_change="";bool tpdc_loss_unlimited=false;
bool tpdc_open=false;datetime tpdc_period=0;string tpdc_signature="";
datetime tp_daily_choice_session=0;
bool TP_DailyInclude(datetime session,double net)
{
 string key=SessionKey(session,net>=0 ? "APPLY_WINS" : "APPLY_LOSSES");
 return GlobalVariableCheck(key) && GlobalVariableGet(key)>0;
}
void TP_DailyChoiceClose()
{
 string names[]={"WINS","LOSSES","APPLY","CANCEL"};
 for(int i=0;i<ArraySize(names);i++) ObjectDelete(0,"TradePilot_DAILY_CHOICE_"+names[i]);
 ChartRedraw();
}
void TP_DailyChoiceRender()
{
 if(tp_daily_choice_session!=GetSessionStartForTime(TPDL_Now())) {tp_daily_choice_session=GetSessionStartForTime(TPDL_Now());tp_daily_wins=TP_DailyInclude(tp_daily_choice_session,1);tp_daily_losses=TP_DailyInclude(tp_daily_choice_session,-1);}
 int x=LabelX(),y=PanelY()+S(322);
 CreateButton("TradePilot_DAILY_CHOICE_WINS",(tp_daily_wins ? "[X]" : "[ ]")+" Apply wins",x,y,S(130),S(20),tp_daily_wins?C'35,115,80':C'140,45,45');
 CreateButton("TradePilot_DAILY_CHOICE_LOSSES",(tp_daily_losses ? "[X]" : "[ ]")+" Apply losses",ValueX(),y,S(130),S(20),tp_daily_losses?C'35,115,80':C'140,45,45');
 CreateButton("TradePilot_DAILY_UPDATE","Update",(LabelX()+ValueX()+S(130)-S(88))/2,PanelY()+S(140),S(88),S(19),C'55,60,70');
 ObjectSetString(0,"TradePilot_DAILY_UPDATE",OBJPROP_TOOLTIP,"Click to save Daily Performance: target, Apply wins and Apply losses. Daily Loss Limit has its own Update. Red/green applies to ON/OFF switches; Update is a save action. Invalid input leaves settings unchanged.");
 ObjectSetString(0,"TradePilot_DAILY_CHOICE_WINS",OBJPROP_TOOLTIP,"Default OFF. Turn ON to count this daily basket's positive net results, including open profits, toward its target. Press Update to save for this period. Reports always retain actual results.");
 ObjectSetString(0,"TradePilot_DAILY_CHOICE_LOSSES",OBJPROP_TOOLTIP,"Default OFF. Turn ON to include this daily basket's negative net results, including open losses, so losses increase the amount needed to reach its target. Press Update to save. Daily loss protection always counts all results.");

}
string TPDC_InputSignature()
{return ObjectGetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TEXT)+"|"+(TPDR_Enabled()?"Ratio":ObjectGetString(0,"TradePilot_DAILY_MODE_BUTTON",OBJPROP_TEXT))+"|"+(tp_daily_wins?"1":"0")+"|"+(tp_daily_losses?"1":"0")+"|"+ObjectGetString(0,"TradePilot_LIMIT_EDIT",OBJPROP_TEXT)+"|"+(tpdl_edit_percent?"1":"0");}
void TPDC_Close(){tpdc_open=false;ObjectsDeleteAll(0,"TradePilot_DAILY_CONFIRM_");}
void TPDC_Render()
{
 if(!tpdc_open)return;
 int x=PanelX()+PanelWidth()+S(24),y=PanelY()+S(55),w=S(280);
 CreateRectangle("TradePilot_DAILY_CONFIRM_BG",x,y,w,S(160),C'25,30,40',C'85,95,110');
 CreateLabel("TradePilot_DAILY_CONFIRM_TITLE",(tpdc_loss?"Confirm Daily Loss Limit":"Confirm Daily Performance"),x+S(12),y+S(12),FontSize(BASE_FONT_NORMAL),clrWhite);
 CreateLabel("TradePilot_DAILY_CONFIRM_WINS","Apply wins: "+(tp_daily_wins?"ON":"OFF"),x+S(12),y+S(38),FontSize(BASE_FONT_NORMAL),clrWhite);
 CreateLabel("TradePilot_DAILY_CONFIRM_LOSSES","Apply losses: "+(tp_daily_losses?"ON":"OFF"),x+S(12),y+S(58),FontSize(BASE_FONT_NORMAL),clrWhite);

 double entered=TPDR_Parse(ObjectGetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TEXT));
 double proposed=TPDR_Enabled()?entered*TPDR_RiskCash():(GlobalVariableGet(GV_DAILY_MODE)>0.5?GetSessionStartBalance(tpdc_period)*entered/100:entered);
 double delta=proposed-GetSessionTargetMoney(tpdc_period);
 double amount=MathAbs(delta),balance=GetSessionStartBalance(tpdc_period),risk=TPDR_RiskCash();
 string cash=AccountCurrency()+" "+DoubleToString(amount,2);
 string percentage=balance>0?DoubleToString(amount/balance*100,2)+"%":"Percentage pending";
 string ratio=risk>0?DoubleToString(amount/risk,2)+"R":"Ratio pending";
 string modes=TPDR_Enabled()?ratio+" ("+cash+"; "+percentage+")":GlobalVariableGet(GV_DAILY_MODE)>0.5?percentage+" ("+cash+"; "+ratio+")":cash+" ("+percentage+"; "+ratio+")";
 string change=MathAbs(delta)<0.00000001?"Daily target unchanged":(delta>0?"Increase by ":"Decrease by ")+modes;

 if(tpdc_loss)change=tpdc_loss_change;
 CreateLabel("TradePilot_DAILY_CONFIRM_CHANGE",change,x+S(12),y+S(78),TP_HeaderFont(change,FontSize(BASE_FONT_NORMAL),S(252),S(16)),clrWhite);
 CreateLabel("TradePilot_DAILY_CONFIRM_CONTINUE",(tpdc_loss && tpdc_loss_unlimited?"No daily loss limit. Continue?":"Continue?"),x+S(12),y+S(98),FontSize(BASE_FONT_NORMAL),clrWhite);
 CreateButton("TradePilot_DAILY_CONFIRM_YES","Yes",x+S(12),y+S(126),S(90),S(22),C'55,60,70');
 CreateButton("TradePilot_DAILY_CONFIRM_NO","No",x+S(150),y+S(126),S(90),S(22),C'55,60,70');
 ObjectSetInteger(0,"TradePilot_DAILY_CONFIRM_YES",OBJPROP_ZORDER,100);ObjectSetInteger(0,"TradePilot_DAILY_CONFIRM_NO",OBJPROP_ZORDER,100);
 ObjectSetString(0,"TradePilot_DAILY_CONFIRM_YES",OBJPROP_TOOLTIP,"Confirm and save only the daily settings shown in this review.");ObjectSetString(0,"TradePilot_DAILY_CONFIRM_NO",OBJPROP_TOOLTIP,"Cancel without changing the saved daily settings.");
}

bool TP_DailyChoiceEvent(string name)
{
 if(name=="TradePilot_DAILY_CONFIRM_NO"){TPDC_Close();UpdatePanel();return true;}
 if(name=="TradePilot_DAILY_CONFIRM_YES"){
  ObjectSetInteger(0,name,OBJPROP_STATE,false);
  if(!tpdc_open)return true;
  if(tpdc_period!=GetSessionStartForTime(TPDL_Now())||tpdc_signature!=TPDC_InputSignature()){TPDC_Close();Alert("Daily settings changed. Review them and press Update again.");UpdatePanel();return true;}
  if(tpdc_loss){
   if(!TPDL_SavePending(true)){TPDC_Close();UpdatePanel();return true;}
   GlobalVariableSet(SessionKey(tpdc_period,"APPLY_WINS"),tp_daily_wins?1:0);GlobalVariableSet(SessionKey(tpdc_period,"APPLY_LOSSES"),tp_daily_losses?1:0);
   TPDC_Close();UpdatePanel();return true;
  }
  double pending_target=TPDR_Parse(ObjectGetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TEXT));
  if(!MathIsValidNumber(pending_target)||pending_target<=0){TPDC_Close();return true;}
  daily_target_value=pending_target;GlobalVariableSet(GV_DAILY_VALUE,pending_target);UpdateCurrentSessionTargetFromUI();
  GlobalVariableSet(SessionKey(tpdc_period,"APPLY_WINS"),tp_daily_wins?1:0);GlobalVariableSet(SessionKey(tpdc_period,"APPLY_LOSSES"),tp_daily_losses?1:0);
  TPDC_Close();UpdatePanel();return true;
 }
 if(name=="TradePilot_DAILY_UPDATE"){
  ObjectSetInteger(0,name,OBJPROP_STATE,false);
  if(tp_daily_choice_session!=GetSessionStartForTime(TPDL_Now())){TP_DailyChoiceRender();Alert("The daily period has changed. Review the checkboxes and press Update again.");return true;}
  double value=TPDR_Parse(ObjectGetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TEXT));
  if(!MathIsValidNumber(value)||value<=0){Alert("Enter a positive daily target or valid risk-to-reward ratio before pressing Update.");return true;}
  TPC_Close();tpdc_loss=false;tpdc_open=true;tpdc_period=tp_daily_choice_session;tpdc_signature=TPDC_InputSignature();TPDC_Render();ChartRedraw();return true;
 }
 if(StringFind(name,"TradePilot_DAILY_CHOICE_")!=0)return false;
 ObjectSetInteger(0,name,OBJPROP_STATE,false);
 if(name=="TradePilot_DAILY_CHOICE_WINS")tp_daily_wins=!tp_daily_wins;
 if(name=="TradePilot_DAILY_CHOICE_LOSSES")tp_daily_losses=!tp_daily_losses;
 TP_DailyChoiceRender();return true;
}

void TP_DailyEquivalent()
{
 datetime period=GetSessionStartForTime(TPDL_Now());
 TPDR_TargetEquivalents(period,GetSessionTargetMoney(period),GetSessionPercentageMode(period),AccountCurrencyText());
 double remaining=GetSessionRemainingTargetMoney(period),balance=GetSessionStartBalance(period);
 double day_closed=0,day_floating=0,day_adjusted=0;
 if(TPDL_Totals(day_closed,day_floating,day_adjusted)) remaining=MathMax(0,GetSessionTargetMoney(period)-day_adjusted);
 ObjectSetString(0,"TradePilot_DAILY_REMAINING_VALUE",OBJPROP_TEXT,(GetSessionPercentageMode(period) && balance>0 ? DoubleToString(remaining/balance*100,2)+"% " : "")+"("+AccountCurrencyText()+" "+DoubleToString(remaining,2)+")");
 string primary="",second="",third="";
 TPDR_RemainingParts(period,remaining,balance,AccountCurrency(),GlobalVariableGet(GV_DAILY_MODE)>0.5,primary,second,third,true);
 string help="Remaining target: the selected mode is next to the heading, with the other two equivalent values in brackets on the same row. Percentage uses the period's starting balance. Ratio uses planned risk. "+primary+"; "+second+"; "+third;
 ObjectSetString(0,"TradePilot_TARGET_VALUE",OBJPROP_TEXT,primary);
 ObjectSetString(0,"TradePilot_TARGET_VALUE",OBJPROP_TOOLTIP,help);
 ObjectSetInteger(0,"TradePilot_TARGET_UNIT",OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
 ObjectSetInteger(0,"TradePilot_TARGET_VALUE",OBJPROP_XDISTANCE,ValueX()+PanelWidth()+S(12));
 ObjectSetInteger(0,"TradePilot_TARGET_VALUE",OBJPROP_YDISTANCE,PanelY()+S(77));
 ObjectSetInteger(0,"TradePilot_TP_VALUE_LABEL",OBJPROP_YDISTANCE,PanelY()+S(77));
 ObjectSetInteger(0,"TradePilot_TARGET_VALUE",OBJPROP_FONTSIZE,TP_HeaderFont(primary,FontSize(BASE_FONT_NORMAL),S(132),S(15)));
 ObjectDelete(0,"TradePilot_TARGET_OTHER1");ObjectDelete(0,"TradePilot_TARGET_OTHER2");
 double closed_net=0,floating_net=0,adjusted_net=0;
 bool closed_ready=TPDL_Totals(closed_net,floating_net,adjusted_net);
 ObjectSetInteger(0,"TradePilot_DAILY_REMAINING_VALUE",OBJPROP_COLOR,!closed_ready?clrWhite:closed_net>0?C'90,220,140':closed_net<0?C'255,100,100':clrWhite);
 ObjectSetString(0,"TradePilot_MARGIN_UNIT",OBJPROP_TEXT,AccountCurrencyText());
 string old_risk[]={"TradePilot_RISK_AMOUNT_LABEL","TradePilot_RISK_AMOUNT_VALUE","TradePilot_RISK_AMOUNT_UNIT"};
 for(int i=0;i<ArraySize(old_risk);i++)ObjectDelete(0,old_risk[i]);
 TP_BasketCostsRender(period);
 TP_BasketProgressRows(period);
 string carry_display=TP_CarryMoneyPercent(GetCarryOverFloatingPL());
 ObjectSetString(0,"TradePilot_CARRY_PL_VALUE",OBJPROP_TEXT,carry_display);
 ObjectSetInteger(0,"TradePilot_CARRY_PL_VALUE",OBJPROP_FONTSIZE,TP_HeaderFont(carry_display,FontSize(BASE_FONT_NORMAL),S(132),S(15)));
 ObjectSetString(0,"TradePilot_CARRY_PL_VALUE",OBJPROP_TOOLTIP,"Older baskets' open net result in account currency. The percentage uses the sum of their distinct original-day starting balances, counted once per day; it is not a cash-flow-adjusted investment return.");
 ObjectSetInteger(0,"TradePilot_CARRY_CURRENCY",OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
 TPDR_Render(period);
}

void TP_BasketColumnLayout()
{
 int left=PanelX(),offset=PanelWidth()+S(12);
 string names[]={"CURRENT_BORDER","BASKET_TITLE","POSITIONS_LABEL","POSITIONS_VALUE","PROFIT_LABEL","PROFIT_VALUE","TP_VALUE_LABEL","TARGET_VALUE","TARGET_UNIT","STATUS_LABEL","STATUS_VALUE","CARRY_BORDER","CARRY_DIVIDER","CARRY_TITLE","CARRY_BASKETS_LABEL","CARRY_BASKETS_VALUE","CARRY_POSITIONS_LABEL","CARRY_POSITIONS_VALUE","CARRY_PROFIT_LABEL","CARRY_PROFIT_VALUE","CARRY_CURRENCY","CARRY_PL_LABEL","CARRY_PL_VALUE"};
 for(int i=0;i<ArraySize(names);i++) {
  string name="TradePilot_"+names[i];if(ObjectFind(0,name)<0)continue;
  long x=ObjectGetInteger(0,name,OBJPROP_XDISTANCE);
  if(x>=left && x<left+PanelWidth()) {ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x+offset);ObjectSetInteger(0,name,OBJPROP_YDISTANCE,ObjectGetInteger(0,name,OBJPROP_YDISTANCE)-S(45));if(StringFind(names[i],"CARRY_")==0)ObjectSetInteger(0,name,OBJPROP_YDISTANCE,ObjectGetInteger(0,name,OBJPROP_YDISTANCE)+S(126));if(names[i]=="STATUS_LABEL"||names[i]=="STATUS_VALUE")ObjectSetInteger(0,name,OBJPROP_YDISTANCE,ObjectGetInteger(0,name,OBJPROP_YDISTANCE)+S(50));if(names[i]=="CURRENT_BORDER")ObjectSetInteger(0,name,OBJPROP_YSIZE,S(227));}
 }
}

void TP_SpreadTradeClose()
{
 tp_spread_confirm_open=false;ObjectsDeleteAll(0,"TradePilot_SPREAD_CONFIRM_");ChartRedraw();
}
void TP_SpreadTradePrompt()
{
 int x=LabelX(),y=PanelY()+S(614);
 string text=tp_spread_pending_calculation?"Spread OFF. Continue calculating?":"Spread OFF. Continue with this trade?";
 CreateRectangle("TradePilot_SPREAD_CONFIRM_BG",x-S(4),y-S(5),S(286),S(70),C'25,28,35',C'110,125,145');
 CreateLabel("TradePilot_SPREAD_CONFIRM_TEXT",text,x,y,TP_HeaderFont(text,FontSize(BASE_FONT_NORMAL),S(278),S(16)),clrWhite);
 ObjectSetString(0,"TradePilot_SPREAD_CONFIRM_TEXT",OBJPROP_TOOLTIP,tp_spread_pending_calculation?"Calculate using your entered stop without extra spread allowance. Continue calculates only; it sends no order. Cancel leaves the calculation unchanged.":"Continue this one trade using the entered stop without extra spread allowance. Quote, stop, risk, margin and trading permissions are checked again. Cancel sends nothing.");
 CreateButton("TradePilot_SPREAD_CONFIRM_CONTINUE","Continue",x,y+S(25),S(130),S(24),C'55,60,70');
 CreateButton("TradePilot_SPREAD_CONFIRM_CANCEL","Cancel",ValueX(),y+S(25),S(130),S(24),C'140,45,45');
 ObjectSetString(0,"TradePilot_SPREAD_CONFIRM_CONTINUE",OBJPROP_TOOLTIP,tp_spread_pending_calculation?"Calculate with spread allowance OFF. This does not place a trade.":"Continue this one order with spread allowance OFF after normal broker checks.");
 ObjectSetString(0,"TradePilot_SPREAD_CONFIRM_CANCEL",OBJPROP_TOOLTIP,"Cancel this request without sending an order or changing the spread setting.");ChartRedraw();
}

void TP_CalculateRequested(bool confirmed=false)
{
 if(!tp_spread_on && !confirmed){tp_spread_pending_calculation=true;tp_spread_confirm_open=true;TP_SpreadTradePrompt();return;}
 CalculatePositionSize();
}

#include "TradePilotPanelVisibility.mqh"
