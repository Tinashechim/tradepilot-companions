// TradePilot - By Tinashe Chimanikire
// Legacy account/session storage keys are retained for upgrade compatibility.
#include <Trade/Trade.mqh>
#include "TradePilotSizing.mqh"
#include "TradePilotLocal.mqh"
#include "TradePilotCharts.mqh"

#property copyright "Tinashe Chimanikire"
#property version   "2.20"
#property strict

CTrade trade;


bool tp_spread_on=false;
bool tp_spread_confirm_open=false;
int tp_spread_pending_side=0;
bool tp_spread_pending_calculation=false;
// ============================================================
// RESPONSIVE PANEL
// ============================================================

#define BASE_PANEL_X       12
#define BASE_PANEL_Y       16
#define BASE_PANEL_WIDTH   304
#define BASE_PANEL_HEIGHT  800

#define BASE_LABEL_X       11
#define BASE_VALUE_X       160
#define BASE_UNIT_X        256

#define BASE_FONT_TITLE    6
#define BASE_FONT_SECTION  6
#define BASE_FONT_NORMAL   5
#define BASE_FONT_SMALL    5


double panel_scale = 1.0;
double auto_panel_scale = 1.0;
double manual_panel_scale = 1.0;


// ============================================================
// ENUMS
// ============================================================

enum RiskMode
{
   RISK_MONEY,
   RISK_PERCENTAGE
};

enum DailyTargetMode
{
   DAILY_MONEY,
   DAILY_PERCENTAGE
};


// ============================================================
// SHARED GLOBAL VARIABLES
// ============================================================

string GV_CLOSE_LOCK;

string GV_DAILY_MODE;
string GV_DAILY_TARGET;
string GV_PANEL_SCALE;


// ============================================================
// LOCAL POSITION SIZER VARIABLES
// ============================================================

RiskMode risk_mode = RISK_PERCENTAGE;

double risk_value = 1.0;

bool sl_line_enabled = false;

// Include estimated trading costs in planned risk.
// FTMO ETHUSD test reference: 36.42 / 2.11 lots ≈ 17.26 per lot round trip.
// This is an estimate and can be adjusted later for another broker/symbol.
// Commission is discovered per symbol by the local companion.


// ============================================================
// RESPONSIVE SIZE HELPERS
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
   return
      PanelX() +
      S(BASE_LABEL_X);
}


int ValueX()
{
   return
      PanelX() +
      S(BASE_VALUE_X);
}


int UnitX()
{
   return
      PanelX() +
      S(BASE_UNIT_X);
}


int FontSize(int base_size)
{
   // Text is 20% larger than the previous baseline and
   // continues to grow/shrink with the whole panel.
   int size =
      (int)MathRound(
         base_size * 1.44 * panel_scale
      );

   if(size < 4)
      size = 4;

   return size;
}


// ============================================================
// CALCULATE RESPONSIVE SCALE
// ============================================================

void CalculatePanelScale()
{
   long chart_width =
      ChartGetInteger(
         0,
         CHART_WIDTH_IN_PIXELS
      );


   long chart_height =
      ChartGetInteger(
         0,
         CHART_HEIGHT_IN_PIXELS
      );


   if(
      chart_width <= 0 ||
      chart_height <= 0
   )
   {
      auto_panel_scale = 1.0;
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


   if(auto_panel_scale > 1.0)
      auto_panel_scale = 1.0;


   if(auto_panel_scale < 0.50)
      auto_panel_scale = 0.50;


   // Manual scale adjusts the automatically fitted size.
   panel_scale =
      auto_panel_scale *
      manual_panel_scale;


   if(panel_scale < 0.25)
      panel_scale = 0.25;


   if(panel_scale > 1.50)
      panel_scale = 1.50;
}


// ============================================================
// GLOBAL VARIABLE NAMES
// ============================================================

void CreateGlobalVariableNames()
{
   string account =
      IntegerToString(
         (int)AccountInfoInteger(
            ACCOUNT_LOGIN
         )
      );


   string prefix =
      "PSBM_" + account + "_";


   GV_CLOSE_LOCK =
      prefix + "CLOSE_LOCK";


   GV_DAILY_MODE =
      prefix + "DAILY_MODE";


   GV_DAILY_TARGET =
      prefix + "DAILY_TARGET";


   GV_PANEL_SCALE =
      prefix + "PANEL_SCALE";
}


// ============================================================
// INITIALIZE SHARED VARIABLES
// ============================================================

void InitializeSharedVariables()
{
   if(!GlobalVariableCheck(GV_CLOSE_LOCK))
      GlobalVariableSet(
         GV_CLOSE_LOCK,
         0.0
      );


   if(!GlobalVariableCheck(GV_DAILY_MODE))
      GlobalVariableSet(
         GV_DAILY_MODE,
         (double)DAILY_PERCENTAGE
      );


   if(!GlobalVariableCheck(GV_DAILY_TARGET))
      GlobalVariableSet(
         GV_DAILY_TARGET,
         5.0
      );


   if(!GlobalVariableCheck(GV_PANEL_SCALE))
      GlobalVariableSet(
         GV_PANEL_SCALE,
         1.0
      );


   manual_panel_scale =
      GlobalVariableGet(
         GV_PANEL_SCALE
      );


   if(manual_panel_scale < 0.50)
      manual_panel_scale = 0.50;


   if(manual_panel_scale > 1.50)
      manual_panel_scale = 1.50;
}


// ============================================================
// SESSION BASKET STATE
//
// Each position permanently belongs to the 23:30 session in
// which it was opened.  Session settings are stored separately
// so carried positions keep their original target.
// ============================================================

string SessionKey(datetime session_start, string suffix)
{
   string account =
      IntegerToString(
         (int)AccountInfoInteger(ACCOUNT_LOGIN)
      );

   return
      "PSBM_" + account + "_S_" +
      IntegerToString((int)session_start) +
      "_" + suffix;
}


datetime GetSessionStartForTime(datetime value)
{
   MqlDateTime session_struct;
   TimeToStruct(value, session_struct);

   session_struct.hour = 23;
   session_struct.min  = 30;
   session_struct.sec  = 0;

   datetime boundary =
      StructToTime(session_struct);

   if(value >= boundary)
      return boundary;

   return boundary - 86400;
}


datetime GetPositionSessionStartByIndex(int index)
{
   ulong ticket = PositionGetTicket(index);

   if(ticket == 0)
      return 0;

   datetime opened =
      (datetime)PositionGetInteger(POSITION_TIME);

   return GetSessionStartForTime(opened);
}


void EnsureSessionState(datetime session_start)
{
   if(session_start <= 0)
      return;

   string balance_key =
      SessionKey(session_start, "START_BALANCE");

   string mode_key =
      SessionKey(session_start, "MODE");

   string target_key =
      SessionKey(session_start, "TARGET");

   if(!GlobalVariableCheck(balance_key))
      GlobalVariableSet(
         balance_key,
         AccountInfoDouble(ACCOUNT_BALANCE)
      );

   if(!GlobalVariableCheck(mode_key))
      GlobalVariableSet(
         mode_key,
         (double)GetDailyTargetMode()
      );

   if(!GlobalVariableCheck(target_key))
      GlobalVariableSet(
         target_key,
         GetDailyTargetValue()
      );
}


double GetSessionStartBalance(datetime session_start)
{
   EnsureSessionState(session_start);

   return GlobalVariableGet(
      SessionKey(session_start, "START_BALANCE")
   );
}


DailyTargetMode GetSessionTargetMode(datetime session_start)
{
   EnsureSessionState(session_start);

   return
      (DailyTargetMode)(int)GlobalVariableGet(
         SessionKey(session_start, "MODE")
      );
}


double GetSessionTargetValue(datetime session_start)
{
   EnsureSessionState(session_start);

   return GlobalVariableGet(
      SessionKey(session_start, "TARGET")
   );
}


int GetSessionOpenPositionCount(datetime session_start)
{
   int count = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(GetPositionSessionStartByIndex(i) == session_start)
         count++;
   }

   return count;
}


double GetSessionFloatingProfit(datetime session_start)
{
   double profit = 0.0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      datetime opened =
         (datetime)PositionGetInteger(POSITION_TIME);

      if(GetSessionStartForTime(opened) != session_start)
         continue;

      profit += PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }

   return profit;
}


// ============================================================
// CARRY-OVER SUMMARY
// ============================================================

int GetCarryOverPositionCount(datetime current_session)
{
   int count = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      datetime position_session =
         GetPositionSessionStartByIndex(i);

      if(position_session > 0 && position_session < current_session)
         count++;
   }

   return count;
}


double GetCarryOverFloatingProfit(datetime current_session)
{
   double profit = 0.0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      datetime opened =
         (datetime)PositionGetInteger(POSITION_TIME);

      datetime position_session =
         GetSessionStartForTime(opened);

      if(position_session > 0 && position_session < current_session)
         profit += PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }

   return profit;
}


int GetCarryOverBasketCount(datetime current_session)
{
   datetime sessions[];
   int session_count = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      datetime position_session =
         GetPositionSessionStartByIndex(i);

      if(position_session <= 0 || position_session >= current_session)
         continue;

      bool already_counted = false;

      for(int j = 0; j < session_count; j++)
      {
         if(sessions[j] == position_session)
         {
            already_counted = true;
            break;
         }
      }

      if(already_counted)
         continue;

      ArrayResize(sessions, session_count + 1);
      sessions[session_count] = position_session;
      session_count++;
   }

   return session_count;
}


// ============================================================
// DAILY TARGET SETTINGS
// ============================================================

DailyTargetMode GetDailyTargetMode()
{
   return
      (DailyTargetMode)
      (int)GlobalVariableGet(
         GV_DAILY_MODE
      );
}


double GetDailyTargetValue()
{
   return
      GlobalVariableGet(
         GV_DAILY_TARGET
      );
}


// ============================================================
// DAILY SESSION
//
// 23:30:00 -> next day 23:29:59
// ============================================================

datetime GetDailySessionStart()
{
   return GetSessionStartForTime(TPDL_Now());
}


// ============================================================
// POSITION IDENTIFIER -> ORIGINAL SESSION
// ============================================================

datetime GetPositionIdentifierSession(long position_id)
{
   if(position_id <= 0)
      return 0;

   int total = HistoryDealsTotal();
   datetime earliest = 0;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);

      if(ticket == 0)
         continue;

      if(HistoryDealGetInteger(ticket, DEAL_POSITION_ID) != position_id)
         continue;

      ENUM_DEAL_ENTRY entry =
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);

      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT)
         continue;

      datetime deal_time =
         (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

      if(earliest == 0 || deal_time < earliest)
         earliest = deal_time;
   }

   if(earliest == 0)
      return 0;

   return GetSessionStartForTime(earliest);
}


// ============================================================
// CLOSED P/L BELONGING TO ONE ORIGINAL SESSION
// ============================================================

double GetSessionClosedProfit(datetime session_start, bool target_adjustment=false)
{
   double actual=0,adjusted=0;
   if(!TP_BasketResults(session_start,actual,adjusted,false))return 0;
   return target_adjustment?adjusted:actual;
}


bool HasSessionClosedTrades(datetime session_start)
{
   if(!HistorySelect(session_start, TimeCurrent()))
      return false;

   int total = HistoryDealsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);

      if(ticket == 0)
         continue;

      ENUM_DEAL_TYPE deal_type =
         (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);

      if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL)
         continue;

      ENUM_DEAL_ENTRY entry =
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);

      if(
         entry != DEAL_ENTRY_OUT &&
         entry != DEAL_ENTRY_OUT_BY &&
         entry != DEAL_ENTRY_INOUT
      )
      {
         continue;
      }

      long position_id =
         HistoryDealGetInteger(ticket, DEAL_POSITION_ID);

      if(GetPositionIdentifierSession(position_id) == session_start)
         return true;
   }

   return false;
}


double GetSessionBaseTargetMoney(datetime session_start)
{
   double target = GetSessionTargetValue(session_start);
   double ratio_target=0;if(TPDR_Target(session_start,target,ratio_target)) return ratio_target;

   if(GetSessionTargetMode(session_start) == DAILY_MONEY)
      return target;

   return
      GetSessionStartBalance(session_start) *
      (target / 100.0);
}
bool GetSessionPercentageModeCompat(datetime period){return GetSessionTargetMode(period)==DAILY_PERCENTAGE;}
double GetSessionTargetMoney(datetime period){return TPDA_Target(period,GetSessionBaseTargetMoney(period));}



double GetSessionRemainingTargetMoney(datetime session_start)
{
   double remaining =
      GetSessionTargetMoney(session_start) -
      GetSessionClosedProfit(session_start,true);

   if(remaining < 0)
      remaining = 0;

   return remaining;
}


double GetSessionClosedProfitPercent(datetime session_start)
{
   double start_balance =
      GetSessionStartBalance(session_start);

   if(start_balance <= 0)
      return 0.0;

   return
      (GetSessionClosedProfit(session_start) /
       start_balance) * 100.0;
}


double GetSessionRemainingTargetPercent(datetime session_start)
{
   double start_balance =
      GetSessionStartBalance(session_start);

   if(start_balance <= 0)
      return 0.0;

   return
      (GetSessionRemainingTargetMoney(session_start) /
       start_balance) * 100.0;
}


bool IsSessionTargetReached(datetime session_start)
{
   double target_money =
      GetSessionTargetMoney(session_start);

   if(target_money <= 0)
      return false;

   return
      GetSessionClosedProfit(session_start,true) >=
      target_money;
}


// Current daily panel always represents the CURRENT session only.

double GetTodayClosedProfit()
{
   return GetSessionClosedProfit(GetDailySessionStart());
}


bool HasClosedTradesToday()
{
   return HasSessionClosedTrades(GetDailySessionStart());
}


double GetDailyStartBalance()
{
   return GetSessionStartBalance(GetDailySessionStart());
}


double GetTodayClosedProfitPercent()
{
   return GetSessionClosedProfitPercent(GetDailySessionStart());
}


double GetDailyTargetMoney()
{
   return GetSessionTargetMoney(GetDailySessionStart());
}


double GetRemainingDailyTargetMoney()
{
   return GetSessionRemainingTargetMoney(GetDailySessionStart());
}


double GetRemainingDailyTargetPercent()
{
   return GetSessionRemainingTargetPercent(GetDailySessionStart());
}


bool IsDailyTargetReached()
{
   return IsSessionTargetReached(GetDailySessionStart());
}


// ============================================================
// READ DAILY TARGET
// ============================================================

bool ReadDailyTarget()
{
   string text =
      ObjectGetString(
         0,
         "TradePilot_DAILY_TARGET_EDIT",
         OBJPROP_TEXT
      );


   double value =
      TPDR_Parse(text);


   if(value <= 0)
   {
      ObjectSetString(
         0,
         "TradePilot_DAILY_TARGET_EDIT",
         OBJPROP_TEXT,
         DoubleToString(
            GetDailyTargetValue(),
            2
         )
      );


      return false;
   }


   GlobalVariableSet(
      GV_DAILY_TARGET,
      value
   );

   // The current session may still be edited during the day.
   // Older carried sessions keep their own frozen target.
   datetime current_session =
      GetDailySessionStart();

   EnsureSessionState(current_session);

   GlobalVariableSet(
      SessionKey(current_session, "TARGET"),
      value
   );


   GlobalVariableSet(SessionKey(current_session,"MODE"),(double)GetDailyTargetMode());
   TPDR_Save(current_session);
   return true;
}


// ============================================================
// CLOSE LOCK
// ============================================================

bool AcquireCloseLock()
{
   return
      GlobalVariableSetOnCondition(
         GV_CLOSE_LOCK,
         1.0,
         0.0
      );
}


void ReleaseCloseLock()
{
   GlobalVariableSet(
      GV_CLOSE_LOCK,
      0.0
   );
}


// ============================================================
// CLOSE ONLY POSITIONS FROM ONE SESSION
// ============================================================

bool CloseSessionPositions(datetime session_start)
{
   bool success = true;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      datetime opened =
         (datetime)PositionGetInteger(POSITION_TIME);

      if(GetSessionStartForTime(opened) != session_start)
         continue;

      if(!trade.PositionClose(ticket))
         success = false;
   }

   return success;
}


// ============================================================
// CHECK ALL OPEN SESSION BASKETS
// ============================================================

void CheckBasketTakeProfit()
{
   datetime sessions[];
   int session_count = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      datetime session_start =
         GetPositionSessionStartByIndex(i);

      if(session_start <= 0)
         continue;

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

      if(IsSessionTargetReached(session_start))
         continue;

      double target=GetSessionTargetMoney(session_start),actual=0,adjusted=0;
      if(target<=0 || !TP_BasketResults(session_start,actual,adjusted) || adjusted<target)continue;

      if(!AcquireCloseLock())
         return;

      CloseSessionPositions(session_start);
      ReleaseCloseLock();
   }
}


// ============================================================
// CURRENT SPREAD
// ============================================================

double GetCurrentSpreadPoints()
{
   MqlTick tick;


   if(!SymbolInfoTick(
      _Symbol,
      tick
   ))
   {
      return 0.0;
   }


   double point =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_POINT
      );


   if(point <= 0)
      return 0.0;


   return
      (tick.ask - tick.bid) /
      point;
}


// ============================================================
// CURRENT PRICE
// ============================================================

double GetCurrentPrice()
{
   MqlTick tick;


   if(!SymbolInfoTick(
      _Symbol,
      tick
   ))
   {
      return 0.0;
   }


   return tick.ask;
}


// ============================================================
// RISK AMOUNT
// ============================================================

double GetRiskAmount()
{
   if(risk_mode == RISK_MONEY)
      return risk_value;


   double balance =
      AccountInfoDouble(
         ACCOUNT_BALANCE
      );


   return
      balance *
      (risk_value / 100.0);
}


// ============================================================
// NORMALIZE CALCULATED VOLUME
// ============================================================

double NormalizeCalculatedVolume(
   double volume
)
{
   double step =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP
      );


   if(step <= 0)
      return 0.0;


   return
      MathFloor(
         volume / step
      ) * step;
}


// ============================================================
// STOP LOSS INPUT
// ============================================================

double GetStopLossInputPrice()
{
   string text =
      ObjectGetString(
         0,
         "TradePilot_SL_EDIT",
         OBJPROP_TEXT
      );


   return
      StringToDouble(text);
}


// ============================================================
// CREATE STOP LOSS LINE
//
// VISUAL / CALCULATION ONLY.
// NEVER MODIFIES BROKER STOP LOSS.
// ============================================================

void CreateStopLossLine()
{
   if(!sl_line_enabled)
      return;


   string name =
      "TradePilot_SL_LINE";


   ObjectDelete(
      0,
      name
   );


   double sl_price =
      GetStopLossInputPrice();


   if(sl_price <= 0)
   {
      double current_price =
         GetCurrentPrice();


      double point =
         SymbolInfoDouble(
            _Symbol,
            SYMBOL_POINT
         );


      if(
         current_price <= 0 ||
         point <= 0
      )
      {
         return;
      }


      sl_price =
         current_price -
         (100 * point);
   }


   int digits =
      (int)SymbolInfoInteger(
         _Symbol,
         SYMBOL_DIGITS
      );


   sl_price =
      NormalizeDouble(
         sl_price,
         digits
      );


   if(!ObjectCreate(
      0,
      name,
      OBJ_HLINE,
      0,
      0,
      sl_price
   ))
   {
      return;
   }


   ObjectSetInteger(
      0,
      name,
      OBJPROP_COLOR,
      clrRed
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_WIDTH,
      2
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_STYLE,
      STYLE_SOLID
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_SELECTABLE,
      true
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_SELECTED,
      true
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_BACK,
      true
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_HIDDEN,
      false
   );


   ObjectSetString(
      0,
      name,
      OBJPROP_TOOLTIP,
      "Calculation Stop Loss"
   );


   ObjectSetString(
      0,
      "TradePilot_SL_EDIT",
      OBJPROP_TEXT,
      DoubleToString(
         sl_price,
         digits
      )
   );


   ChartRedraw();
}


// ============================================================
// DELETE STOP LOSS LINE
// ============================================================

void DeleteStopLossLine()
{
   ObjectDelete(
      0,
      "TradePilot_SL_LINE"
   );


   ChartRedraw();
}


// ============================================================
// UPDATE STOP LOSS BUTTON
// ============================================================

void UpdateStopLossLineButton()
{
   if(sl_line_enabled)
   {
      ObjectSetString(
         0,
         "TradePilot_SL_LINE_BUTTON",
         OBJPROP_TEXT,
         "SL LINE ON"
      );


      ObjectSetInteger(
         0,
         "TradePilot_SL_LINE_BUTTON",
         OBJPROP_BGCOLOR,
         C'35,115,80'
      );
   }
   else
   {
      ObjectSetString(
         0,
         "TradePilot_SL_LINE_BUTTON",
         OBJPROP_TEXT,
         "SL LINE OFF"
      );


      ObjectSetInteger(
         0,
         "TradePilot_SL_LINE_BUTTON",
         OBJPROP_BGCOLOR,
         C'140,45,45'
      );
   }
}


// ============================================================
// TOGGLE STOP LOSS LINE
// ============================================================

void ToggleStopLossLine()
{
   sl_line_enabled =
      !sl_line_enabled;


   if(sl_line_enabled)
      CreateStopLossLine();
   else
      DeleteStopLossLine();


   if(risk_mode == RISK_PERCENTAGE)
   {
      ObjectSetString(0, "TradePilot_RISK_MODE_BUTTON", OBJPROP_TEXT, "PERCENTAGE");
      ObjectSetString(0, "TradePilot_RISK_UNIT", OBJPROP_TEXT, "%");
   }
   else
   {
      ObjectSetString(0, "TradePilot_RISK_MODE_BUTTON", OBJPROP_TEXT, "MONEY");
      ObjectSetString(
         0,
         "TradePilot_RISK_UNIT",
         OBJPROP_TEXT,
         AccountInfoString(ACCOUNT_CURRENCY)
      );
   }

   UpdateStopLossLineButton();


   ChartRedraw();
}


// ============================================================
// STOP LOSS LINE -> INPUT
// ============================================================


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
   if(ObjectFind(0,"TradePilot_SL_LINE")>=0) ObjectSetDouble(0,"TradePilot_SL_LINE",OBJPROP_PRICE,effective);
   ObjectSetString(0,"TradePilot_SPREAD_TOGGLE",OBJPROP_TEXT,tp_spread_on?"SPREAD ON":"SPREAD OFF");
   ObjectSetInteger(0,"TradePilot_SPREAD_TOGGLE",OBJPROP_BGCOLOR,tp_spread_on?C'35,115,80':C'140,45,45');
   CalculatePositionSize();ChartRedraw();
}

void UpdateStopLossFromLine()
{
   if(!sl_line_enabled)
      return;


   if(
      ObjectFind(
         0,
         "TradePilot_SL_LINE"
      ) < 0
   )
   {
      return;
   }


   double price =
      ObjectGetDouble(
         0,
         "TradePilot_SL_LINE",
         OBJPROP_PRICE
      );


   int digits =
      (int)SymbolInfoInteger(
         _Symbol,
         SYMBOL_DIGITS
      );


   price =
      NormalizeDouble(
         price,
         digits
      );


   ObjectSetString(
      0,
      "TradePilot_SL_EDIT",
      OBJPROP_TEXT,
      DoubleToString(
         price,
         digits
      )
   );


   ChartRedraw();
}


// ============================================================
// STOP LOSS INPUT -> LINE
// ============================================================

void UpdateStopLossLineFromInput()
{
   string text =
      ObjectGetString(
         0,
         "TradePilot_SL_EDIT",
         OBJPROP_TEXT
      );


   double price =
      StringToDouble(text);


   if(price <= 0)
      return;


   if(!sl_line_enabled)
      return;


   if(
      ObjectFind(
         0,
         "TradePilot_SL_LINE"
      ) < 0
   )
   {
      CreateStopLossLine();
      return;
   }


   int digits =
      (int)SymbolInfoInteger(
         _Symbol,
         SYMBOL_DIGITS
      );


   price =
      NormalizeDouble(
         price,
         digits
      );


   ObjectSetDouble(
      0,
      "TradePilot_SL_LINE",
      OBJPROP_PRICE,
      price
   );


   ObjectSetInteger(
      0,
      "TradePilot_SL_LINE",
      OBJPROP_SELECTED,
      true
   );


   ChartRedraw();
}


// ============================================================
// CALCULATE POSITION SIZE
// ============================================================

double GetOneLotMarketLoss(
   ENUM_ORDER_TYPE order_type,
   double entry,
   double stop
)
{
   double result = 0.0;
   double probe=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(probe<=0) return 0;

   if(!OrderCalcProfit(
      order_type,
      _Symbol,
      probe,
      entry,
      stop,
      result
   ))
      return 0.0;

   return MathAbs(result)/probe;
}


double GetPlannedLossPerLot(
   ENUM_ORDER_TYPE order_type,
   double entry,
   double stop
)
{
   double market_loss =
      GetOneLotMarketLoss(
         order_type,
         entry,
         stop
      );

   if(market_loss <= 0.0)
      return 0.0;

   // Shared with the copier: stop-loss price risk, excluding broker fees.
   return market_loss;
}


double NormalizeExecutableVolume(double volume)
{
   double step =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP
      );

   double minimum =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );

   double maximum =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX
      );

   if(
      step <= 0.0 ||
      minimum <= 0.0 ||
      maximum <= 0.0
   )
      return 0.0;

   double normalized =
      MathFloor(volume / step) *
      step;

   normalized =
      NormalizeDouble(
         normalized,
         8
      );

   if(normalized < minimum)
      return 0.0;

   // Never silently cap the user's risk.
   if(normalized > maximum)
      return -1.0;

   return normalized;
}


bool ValidateBrokerStopDistance(
   ENUM_ORDER_TYPE order_type,
   double entry,
   double stop
)
{
   double point =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_POINT
      );

   if(point <= 0.0)
      return false;

   double minimum_distance =
      (double)SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      ) *
      point;

   if(order_type == ORDER_TYPE_BUY)
   {
      if(stop >= entry)
         return false;

      if(entry - stop < minimum_distance)
         return false;
   }
   else
   {
      if(stop <= entry)
         return false;

      if(stop - entry < minimum_distance)
         return false;
   }

   return true;
}


void UpdateTradeCalculationDisplay(
   ENUM_ORDER_TYPE order_type,
   double entry,
   double stop,
   double risk_amount,
   double calculated_volume
)
{
   double required_margin=-1;
   int margin_check=calculated_volume>0 ? TP_CheckMargin(_Symbol,(int)order_type,entry,calculated_volume,required_margin) : -1;
   bool rejected_size=calculated_volume==0 && tp_size_reason=="Insufficient free margin" && tp_size_requested>0;
   if(rejected_size){required_margin=tp_requested_margin;margin_check=tp_requested_margin_check;}
   ObjectSetString(0,"TradePilot_MARGIN_LABEL",OBJPROP_TEXT,"Required Margin");
   double minimum =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );

   double maximum =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX
      );

   ObjectSetString(
      0,
      "TradePilot_RISK_AMOUNT_VALUE",
      OBJPROP_TEXT,
      (risk_mode==RISK_PERCENTAGE ? DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE)>0 ? risk_amount/AccountInfoDouble(ACCOUNT_BALANCE)*100.0 : 0,2)+"% " : "")+"("+AccountInfoString(ACCOUNT_CURRENCY)+" "+DoubleToString(risk_amount,2)+")"
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
      margin_check<0 ? (calculated_volume==0?"Not calculated":"Not verified") : DoubleToString(required_margin, 2)
   );
   ObjectSetInteger(0,"TradePilot_MARGIN_VALUE",OBJPROP_COLOR,margin_check==1 ? C'90,220,140' : C'255,100,100');
   ObjectSetString(0,"TradePilot_SIZE_VALUE",OBJPROP_TOOLTIP,tp_size_detail+tp_size_reason);
   ObjectSetString(0,"TradePilot_MARGIN_VALUE",OBJPROP_TOOLTIP,rejected_size?"Required margin for the displayed risk-based size of "+DoubleToString(tp_size_requested,8)+" lots. Available free margin: "+DoubleToString(tp_margin_free,2)+". Red means this size is unaffordable and will not be sent. Moving the planned stop recalculates its size and margin.":calculated_volume==0?"No permitted lot size was produced and no broker margin amount was available. Read the Calculated Size explanation.":"Margin is checked against current free margin for the calculated size. Broker acceptance remains required.");

   ObjectSetString(
      0,
      "TradePilot_MARGIN_UNIT",
      OBJPROP_TEXT,
      AccountInfoString(ACCOUNT_CURRENCY)
   );

   if(
      calculated_volume <= 0.0 ||
      calculated_volume < minimum
   )
   {
      ObjectSetString(
         0,
         "TradePilot_SIZE_VALUE",
         OBJPROP_TEXT,
         rejected_size ? DoubleToString(tp_size_requested,2) : tp_size_reason!="" ? tp_size_reason : calculated_volume<0 ? "Margin not verified" : "Below minimum lot"
      );

      ObjectSetInteger(
         0,
         "TradePilot_SIZE_VALUE",
         OBJPROP_COLOR,
         C'255,100,100'
      );
   }
   else
   {
      ObjectSetString(
         0,
         "TradePilot_SIZE_VALUE",
         OBJPROP_TEXT,
         DoubleToString(calculated_volume, 2)
      );

      ObjectSetInteger(
         0,
         "TradePilot_SIZE_VALUE",
         OBJPROP_COLOR,
         calculated_volume > maximum || margin_check!=1
         ? C'255,190,80'
         : C'90,220,140'
      );
   }

   ChartRedraw();
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
      !MathIsValidNumber(entered_risk) || !MathIsValidNumber(entry) || !MathIsValidNumber(stop) ||
      entered_risk <= 0.0 ||
      entry <= 0.0 ||
      stop <= 0.0 ||
      entry == stop
   )
   {TP_SizeFailure("Check sizing inputs","Enter a positive risk, entry and stop price. Entry and stop must be different. No order was sent.");return;}

   risk_value = entered_risk;

   string budget_reason="";
   double risk_amount=TPDL_SizingRisk(GetRiskAmount(),budget_reason);
   if(risk_amount<=0){TP_SizeFailure(StringFind(budget_reason,"Daily loss limit reached")==0?"Daily limit reached":"Daily check pending",budget_reason!=""?budget_reason:"The entered risk needs a verified positive account balance. No order was sent.");return;}


   ENUM_ORDER_TYPE order_type =
      stop < entry
      ? ORDER_TYPE_BUY
      : ORDER_TYPE_SELL;

   double planned_loss_per_lot =
      GetPlannedLossPerLot(
         order_type,
         entry,
         stop
      );

   if(!MathIsValidNumber(planned_loss_per_lot) || planned_loss_per_lot <= 0.0)
   {TP_SizeFailure("Risk calculation pending","The broker did not provide a usable stop-loss risk calculation for this symbol. Check the connection and symbol prices, then calculate again. No order was sent.");return;}

   double calculated_volume =
      NormalizeCalculatedVolume(
         risk_amount /
         planned_loss_per_lot
      );

   TP_SizeDiagnostic(risk_amount / planned_loss_per_lot,risk_amount,planned_loss_per_lot,AccountInfoString(ACCOUNT_CURRENCY));
   calculated_volume=TP_AffordableLots(_Symbol,(int)order_type,entry,calculated_volume);
   ObjectSetString(0,"TradePilot_SIZE_VALUE",OBJPROP_TOOLTIP,"Size is capped by broker lot rules, stop-loss risk and current free margin. Actual risk can be below the requested risk when margin limits the size.");
   UpdateTradeCalculationDisplay(
      order_type,
      entry,
      stop,
      risk_amount,
      calculated_volume
   );
   Print("TradePilot sizing: ",_Symbol," | ",tp_size_detail," | ",tp_size_reason);
   TP_SizeRowLayout();
}


void ExecutePanelTrade(ENUM_ORDER_TYPE order_type,bool spread_confirmed=false)
{
   string daily_reason="";if(!TPDL_EntryAllowed(daily_reason)) {TPDL_Notify(daily_reason);return;}
   if(!tp_spread_on && !spread_confirmed){tp_spread_pending_calculation=false;tp_spread_pending_side=(int)order_type;tp_spread_confirm_open=true;TP_SpreadTradePrompt();return;}



   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
   {
      Print("TradePilot MT5: Could not read current market price.");
      return;
   }

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

   if(stop <= 0.0 || entered_risk <= 0.0)
      return;

   risk_value = entered_risk;

   double entry =
      order_type == ORDER_TYPE_BUY
      ? tick.ask
      : tick.bid;

   if(entry <= 0.0)
      return;

   if(!ValidateBrokerStopDistance(
      order_type,
      entry,
      stop
   ))
   {
      Print(
         "TradePilot MT5: Invalid Stop Loss for ",
         order_type == ORDER_TYPE_BUY ? "BUY" : "SELL",
         ". Entry=",
         DoubleToString(entry, _Digits),
         " SL=",
         DoubleToString(stop, _Digits)
      );
      return;
   }

   double risk_amount =
      TPDL_CapRisk(GetRiskAmount());

   double planned_loss_per_lot =
      GetPlannedLossPerLot(
         order_type,
         entry,
         stop
      );

   if(planned_loss_per_lot <= 0.0)
      return;

   double volume =
      NormalizeExecutableVolume(
         risk_amount /
         planned_loss_per_lot
      );

   if(volume == -1.0)
   {
      Print("TradePilot MT5: Required volume exceeds broker maximum.");
      return;
   }

   if(volume <= 0.0)
   {
      Print("TradePilot MT5: Required volume is below broker minimum.");
      return;
   }

   UpdateTradeCalculationDisplay(
      order_type,
      entry,
      stop,
      risk_amount,
      volume
   );

   // Refresh the market price immediately before execution and
   // recalculate the volume from the executable side of the market.
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   entry =
      order_type == ORDER_TYPE_BUY
      ? tick.ask
      : tick.bid;

   if(!ValidateBrokerStopDistance(
      order_type,
      entry,
      stop
   ))
      return;

   planned_loss_per_lot =
      GetPlannedLossPerLot(
         order_type,
         entry,
         stop
      );

   if(planned_loss_per_lot <= 0.0)
      return;

   volume =
      NormalizeExecutableVolume(
         risk_amount /
         planned_loss_per_lot
      );

   if(volume <= 0.0)
      return;

   volume=TP_AffordableLots(_Symbol,(int)order_type,entry,volume);
   double confirmed_margin=0;
   if(volume<=0 || TP_CheckMargin(_Symbol,(int)order_type,entry,volume,confirmed_margin)!=1) { Alert("Trade not sent: lot size or free margin is not verified."); return; }
   trade.SetDeviationInPoints(10);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(!TPDL_EntryAllowed(daily_reason) || !TPDL_AcceptRisk(volume*planned_loss_per_lot,daily_reason)) {TPDL_Notify(daily_reason);return;}
   double tp_master_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   bool sent = false;

   if(order_type == ORDER_TYPE_BUY)
   {
      sent =
         trade.Buy(
            volume,
            _Symbol,
            0.0,
            NormalizeDouble(stop, _Digits),
            0.0,
            "TP-MANUAL"
         );
   }
   else
   {
      sent =
         trade.Sell(
            volume,
            _Symbol,
            0.0,
            NormalizeDouble(stop, _Digits),
            0.0,
            "TP-MANUAL"
         );
   }

   if(!sent)
   {
      Print(
         "TradePilot MT5: Trade execution failed. Retcode=",
         trade.ResultRetcode(),
         " ",
         trade.ResultRetcodeDescription()
      );
      return;
   }

   if(HistoryDealSelect(trade.ResultDeal()))
      TP_RecordRisk(HistoryDealGetInteger(trade.ResultDeal(),DEAL_POSITION_ID),trade.ResultVolume()*GetPlannedLossPerLot(order_type,trade.ResultPrice()>0 ? trade.ResultPrice() : entry,stop),tp_master_balance);
   double confirmed_entry =
      trade.ResultPrice();

   if(confirmed_entry <= 0.0)
      confirmed_entry = entry;

   ObjectSetString(
      0,
      "TradePilot_ENTRY_EDIT",
      OBJPROP_TEXT,
      DoubleToString(
         confirmed_entry,
         _Digits
      )
   );

   ObjectSetString(
      0,
      "TradePilot_SL_EDIT",
      OBJPROP_TEXT,
      DoubleToString(
         stop,
         _Digits
      )
   );

   ObjectSetString(
      0,
      "TradePilot_SIZE_VALUE",
      OBJPROP_TEXT,
      DoubleToString(volume, 2)
   );

   UpdateTradeCalculationDisplay(
      order_type,
      confirmed_entry,
      stop,
      risk_amount,
      volume
   );

   ChartRedraw();
}


// ============================================================
// UI HELPERS
// ============================================================

bool tp_main_open=false,tp_basket_open=false;
bool tp_panel_build=false;
void TP_ApplyBasketVisibility(string name);
bool TP_IsBasketObject(string key);

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
   TP_ApplyBasketVisibility(name);

   ObjectSetInteger(
      0,
      name,
      OBJPROP_XDISTANCE,
      x
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_YDISTANCE,
      y
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_XSIZE,
      width
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_YSIZE,
      height
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_BGCOLOR,
      background
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_BORDER_COLOR,
      border
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_CORNER,
      CORNER_LEFT_UPPER
   );


   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
}


#include "TradePilotRenderBatch.mqh"
#include "TradePilotLabelHelp.mqh"

void CreateLabel(
   string name,
   string text,
   int x,
   int y,
   int size,
   color text_color
)
{
   // Keep basket labels in their final column during data-only refreshes.
   if(!tp_panel_build && TP_IsBasketObject(name) && ObjectFind(0,name)>=0){x=(int)ObjectGetInteger(0,name,OBJPROP_XDISTANCE);y=(int)ObjectGetInteger(0,name,OBJPROP_YDISTANCE);}

   if(name=="TradePilot_TITLE" || name=="TradePilot_SUBTITLE" || name=="TradePilot_DESCRIPTION") {
      int row=name=="TradePilot_TITLE" ? 2 : name=="TradePilot_SUBTITLE" ? 16 : 28;
      y=PanelY()+S(row);
      int available_width=S(name=="TradePilot_DESCRIPTION" ? 272 : 196);
      size=TP_HeaderFont(text,size,available_width,S(name=="TradePilot_TITLE" ? 13 : 11));
   }


   // Retain object creation order so overlays and their controls stay visible.
   if(ObjectFind(0,name)>=0 && (ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)!=OBJ_LABEL)ObjectDelete(0,name);
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_LABEL,0,0,0))return;
   TP_ApplyBasketVisibility(name);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,TP_LabelHelp(name,text));

   ObjectSetInteger(
      0,
      name,
      OBJPROP_XDISTANCE,
      x
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_YDISTANCE,
      y
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_CORNER,
      CORNER_LEFT_UPPER
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_ANCHOR,
      ANCHOR_LEFT_UPPER
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_FONTSIZE,
      size
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_COLOR,
      text_color
   );


   ObjectSetString(
      0,
      name,
      OBJPROP_FONT,
      "Arial"
   );


   ObjectSetString(
      0,
      name,
      OBJPROP_TEXT,
      text
   );


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
   TP_ApplyBasketVisibility(name);

   ObjectSetInteger(
      0,
      name,
      OBJPROP_XDISTANCE,
      x
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_YDISTANCE,
      y
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_XSIZE,
      width
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_YSIZE,
      height
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_BGCOLOR,
      background
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_BORDER_COLOR,
      C'80,85,95'
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_COLOR,
      clrWhite
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_FONTSIZE,
      FontSize(BASE_FONT_NORMAL)
   );


   ObjectSetString(
      0,
      name,
      OBJPROP_FONT,
      "Arial"
   );


   ObjectSetString(
      0,
      name,
      OBJPROP_TEXT,
      text
   );

   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 2);
}


void CreateEdit(
   string name,
   string text,
   int x,
   int y,
   int width
)
{
   bool edit_exists=ObjectFind(0,name)>=0;
   if(edit_exists && (ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)!=OBJ_EDIT){ObjectDelete(0,name);edit_exists=false;}
   if(edit_exists)text=ObjectGetString(0,name,OBJPROP_TEXT);


   if(!edit_exists)ObjectCreate(
      0,
      name,
      OBJ_EDIT,
      0,
      0,
      0
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_XDISTANCE,
      x
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_YDISTANCE,
      y
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_XSIZE,
      width
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_YSIZE,
      S(19)
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_BGCOLOR,
      C'45,49,58'
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_BORDER_COLOR,
      C'80,85,95'
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_COLOR,
      clrWhite
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_FONTSIZE,
      FontSize(BASE_FONT_NORMAL)
   );


   ObjectSetString(
      0,
      name,
      OBJPROP_FONT,
      "Arial"
   );


   ObjectSetString(
      0,
      name,
      OBJPROP_TEXT,
      text
   );

   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 2);
   string help="Enter a value using the unit shown beside this field.";
   if(StringFind(name,"DAILY_TARGET")>=0) help="Daily basket target. Use the displayed unit: example 5 for 5%, or 100 for 100 in account currency. This is separate from the desktop monthly follower target.";
   else if(StringFind(name,"RISK_EDIT")>=0) help="Planned trade risk. Use the displayed mode: example 1 for 1% of balance, or 100 for 100 in account currency. Sizing uses balance and stop-loss distance; broker fees affect actual results.";
   else if(StringFind(name,"ENTRY_EDIT")>=0) help="Planned entry price, for example 1.08500 for EURUSD. The executed price can differ from this estimate.";
   else if(StringFind(name,"SL_EDIT")>=0) help="Stop-loss price, for example 1.08000 below a BUY entry at 1.08500. For a SELL, place the stop above entry. You can also drag the stop line.";
   ObjectSetString(0,name,OBJPROP_TOOLTIP,help);
   ObjectSetInteger(0,name,OBJPROP_ALIGN,ALIGN_LEFT);

}


// ============================================================
// UPDATE PANEL BACKGROUND
// ============================================================

void UpdatePanelBackground()
{
   color panel_color =
      C'25,28,35';


   color header_color =
      C'35,39,48';


   if(IsDailyTargetReached())
   {
      panel_color =
         C'25,75,50';


      header_color =
         C'30,95,60';
   }
   else if(
      HasClosedTradesToday() &&
      GetTodayClosedProfit() < 0
   )
   {
      panel_color =
         C'75,30,35';


      header_color =
         C'95,35,40';
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


// ============================================================
// CREATE PANEL
// ============================================================

void CreatePanel()
{
   tp_panel_build=true;
   CalculatePanelScale();

   string account_currency = AccountInfoString(ACCOUNT_CURRENCY);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double current_price = GetCurrentPrice();

   int px = PanelX();
   int py = PanelY();
   int pw = PanelWidth();

   CreateRectangle("TradePilot_PANEL", px, py, pw, PanelHeight(), C'25,28,35', C'70,75,85');
   CreateRectangle("TradePilot_HEADER", px, py, pw, S(42), C'35,39,48', C'35,39,48');

   CreateLabel("TradePilot_TITLE", "TRADEPILOT",
               LabelX(), py + S(6), FontSize(BASE_FONT_TITLE), clrWhite);
   CreateLabel("TradePilot_SUBTITLE", "By Tinashe Chimanikire",
               LabelX(), py + S(20), FontSize(BASE_FONT_SMALL), C'160,165,175');
   CreateLabel("TradePilot_DESCRIPTION","Trade management",LabelX(),py+S(32),FontSize(BASE_FONT_SMALL),C'160,165,175');

   // Manual panel scaling. Automatic monitor/chart fitting remains active,
   // while these controls let the user fine-tune the result.
   // Zoom controls are created after panel backgrounds by TP_PanelVisibility.


   CreateRectangle("TradePilot_BASKET_COLUMN_BG",PanelX()+PanelWidth()+S(12),PanelY(),S(304),S(322),C'25,28,35',C'70,75,85');
   // Create the Carry-over background before its labels so it cannot cover them.
   CreateRectangle("TradePilot_CARRY_BORDER",PanelX()+PanelWidth()+S(18),PanelY()+S(370),S(292),S(108),C'25,28,35',C'70,75,85');
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
   CreateLabel("TradePilot_TARGET_UNIT", account_currency,
               UnitX(), py + S(111), FontSize(BASE_FONT_SMALL), C'160,165,175');

   CreateLabel("TradePilot_STATUS_LABEL", "Status",
               LabelX(), py + S(129), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_STATUS_VALUE", "WAITING", py + S(129), C'255,190,80');

   // CARRY-OVER
   CreateRectangle("TradePilot_CARRY_DIVIDER", LabelX(), py + S(151), pw - S(22), 1,
                   C'65,70,80', C'65,70,80');
   CreateLabel("TradePilot_CARRY_TITLE", "CARRY-OVER",
               LabelX(), py + S(161), FontSize(BASE_FONT_SECTION), C'90,180,255');

   CreateLabel("TradePilot_CARRY_BASKETS_LABEL", "Older Baskets",
               LabelX(), py + S(181), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_CARRY_BASKETS_VALUE", "0", py + S(181), clrWhite);

   CreateLabel("TradePilot_CARRY_POSITIONS_LABEL", "Positions",
               LabelX(), py + S(200), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_CARRY_POSITIONS_VALUE", "0", py + S(200), clrWhite);

   CreateLabel("TradePilot_CARRY_PROFIT_LABEL", "Floating P/L",
               LabelX(), py + S(219), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_CARRY_PROFIT_VALUE", "0.00", py + S(219), clrWhite);
   CreateLabel("TradePilot_CARRY_CURRENCY", account_currency,
               UnitX(), py + S(220), FontSize(BASE_FONT_SMALL), C'160,165,175');

   // DAILY PERFORMANCE
   CreateRectangle("TradePilot_DAILY_DIVIDER", LabelX(), py + S(41), pw - S(22), 1,
                   C'65,70,80', C'65,70,80');
   CreateLabel("TradePilot_DAILY_TITLE", "DAILY PERFORMANCE",
               LabelX(), py + S(51), FontSize(BASE_FONT_SECTION), C'90,180,255');
   CreateLabel("TradePilot_DAILY_MODE_LABEL", "Target Mode",
               LabelX(), py + S(73), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateButton("TradePilot_DAILY_MODE_BUTTON",TPDR_Enabled()?"RATIO":(GetDailyTargetMode()==DAILY_PERCENTAGE?"PERCENTAGE":"CASH"),
                ValueX(), py + S(67), S(130), S(19), C'55,60,70');

   CreateLabel("TradePilot_DAILY_TARGET_LABEL", "Daily Target",
               LabelX(), py + S(97), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateEdit("TradePilot_DAILY_TARGET_EDIT", DoubleToString(GetDailyTargetValue(), 2),
              ValueX(), py + S(91), S(72));
   CreateLabel("TradePilot_DAILY_TARGET_UNIT", "%",
               UnitX(), py + S(98), FontSize(BASE_FONT_SMALL), clrWhite);

   CreateLabel("TradePilot_DAILY_CLOSED_LABEL", "Closed P/L",
               LabelX(), py + S(289), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_DAILY_CLOSED_VALUE", "0.00", py + S(289), clrWhite);
   CreateLabel("TradePilot_DAILY_CURRENCY", account_currency,
               UnitX(), py + S(290), FontSize(BASE_FONT_SMALL), C'160,165,175');

   CreateLabel("TradePilot_DAILY_PERCENT_LABEL", "Closed P/L %",
               LabelX(), py + S(308), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_DAILY_PERCENT_VALUE", "0.00", py + S(308), clrWhite);
   CreateLabel("TradePilot_DAILY_PERCENT_UNIT", "%",
               UnitX(), py + S(309), FontSize(BASE_FONT_SMALL), C'160,165,175');

   CreateLabel("TradePilot_REMAINING_LABEL", "Remaining Target",
               LabelX(), py + S(327), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_REMAINING_VALUE", "0.00", py + S(327), C'255,190,80');
   CreateLabel("TradePilot_REMAINING_UNIT", "%",
               UnitX(), py + S(328), FontSize(BASE_FONT_SMALL), C'160,165,175');

   CreateLabel("TradePilot_DAILY_STATUS_LABEL", "Status",
               LabelX(), py + S(346), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_DAILY_STATUS_VALUE", "IN PROGRESS", py + S(346), C'255,190,80');

   // POSITION SIZER
   CreateRectangle("TradePilot_SIZER_DIVIDER", LabelX(), py + S(456), pw - S(22), 1,
                   C'65,70,80', C'65,70,80');
   CreateLabel("TradePilot_SIZER_TITLE", "POSITION SIZER",
               LabelX(), py + S(466), FontSize(BASE_FONT_SECTION), C'90,180,255');

   CreateLabel("TradePilot_SYMBOL_LABEL", "Symbol",
               LabelX(), py + S(488), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_SYMBOL_VALUE", _Symbol, py + S(488), clrWhite);

   CreateLabel("TradePilot_SPREAD_LABEL", "Spread",
               LabelX(), py + S(507), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_SPREAD_VALUE", "0.0", py + S(507), clrWhite);
   CreateLabel("TradePilot_SPREAD_UNIT", "points",
               UnitX(), py + S(508), FontSize(BASE_FONT_SMALL), C'160,165,175');

   CreateLabel("TradePilot_RISK_MODE_LABEL", "Risk Mode",
               LabelX(), py + S(531), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateButton("TradePilot_RISK_MODE_BUTTON", "PERCENTAGE",
                ValueX(), py + S(525), S(130), S(19), C'55,60,70');

   CreateLabel("TradePilot_RISK_LABEL", "Risk",
               LabelX(), py + S(555), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateEdit("TradePilot_RISK_EDIT", "1.00", ValueX(), py + S(549), S(72));
   CreateLabel("TradePilot_RISK_UNIT", "%",
               UnitX(), py + S(556), FontSize(BASE_FONT_SMALL), clrWhite);

   CreateLabel("TradePilot_ENTRY_LABEL", "Entry Price",
               LabelX(), py + S(579), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateEdit("TradePilot_ENTRY_EDIT", DoubleToString(current_price, digits),
              ValueX(), py + S(573), S(88));

   CreateLabel("TradePilot_SL_LABEL", "Stop Loss",
               LabelX(), py + S(603), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateEdit("TradePilot_SL_EDIT", "", ValueX(), py + S(597), S(88));

   CreateButton("TradePilot_SPREAD_TOGGLE",tp_spread_on?"SPREAD ON":"SPREAD OFF",LabelX(),py + S(621),S(130),S(20),tp_spread_on?C'35,115,80':C'140,45,45');
   ObjectSetString(0,"TradePilot_SPREAD_TOGGLE",OBJPROP_TOOLTIP,"ON moves the planned stop one current spread farther from entry and recalculates size. OFF restores the unadjusted stop. Starts OFF. It does not change stops on existing trades.");
   CreateButton("TradePilot_SL_LINE_BUTTON", sl_line_enabled ? "SL LINE ON" : "SL LINE OFF",
                ValueX(), py + S(621), S(130), S(20), sl_line_enabled ? C'35,115,80' : C'140,45,45');

   CreateLabel("TradePilot_SIZE_LABEL", "Calculated Size",
               LabelX(), py + S(642), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_SIZE_VALUE", "Not calculated", py + S(642), C'255,190,80');
   CreateLabel("TradePilot_SIZE_UNIT", "lots",
               UnitX(), py + S(643), FontSize(BASE_FONT_SMALL), C'160,165,175');

   CreateLabel("TradePilot_BROKER_MAX_LABEL", "Broker Max",
               LabelX(), py + S(664), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_BROKER_MAX_VALUE",
               DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), 2),
               py + S(664), clrWhite);
   CreateLabel("TradePilot_BROKER_MAX_UNIT", "lots",
               UnitX(), py + S(664), FontSize(BASE_FONT_SMALL), C'160,165,175');

   CreateLabel("TradePilot_MARGIN_LABEL", "Required Margin",
               LabelX(), py + S(686), FontSize(BASE_FONT_NORMAL), C'190,195,205');
   CreateValue("TradePilot_MARGIN_VALUE", "Not calculated", py + S(686), C'255,100,100');
   CreateLabel("TradePilot_MARGIN_UNIT", account_currency,
               UnitX(), py + S(687), FontSize(BASE_FONT_SMALL), C'160,165,175');


   CreateButton("TradePilot_CALCULATE_BUTTON","CALCULATE",LabelX(),py+S(702),pw-S(22),S(21),C'45,105,155');

   CreateButton("TradePilot_BUY_BUTTON","BUY",LabelX(),py+S(728),pw-S(22),S(21),C'35,115,80');

   CreateButton("TradePilot_SELL_BUTTON","SELL",LabelX(),py+S(754),pw-S(22),S(21),C'140,45,45');

   ObjectDelete(0,"TradePilot_SIGNATURE");


   CreateStopLossLine();


   UpdateStopLossLineButton();



   tp_panel_build=false;
}


// ============================================================
// REBUILD RESPONSIVE PANEL
// ============================================================

void RebuildResponsivePanel()
{
   string daily_target =
      ObjectGetString(
         0,
         "TradePilot_DAILY_TARGET_EDIT",
         OBJPROP_TEXT
      );


   string risk =
      ObjectGetString(
         0,
         "TradePilot_RISK_EDIT",
         OBJPROP_TEXT
      );


   string entry =
      ObjectGetString(
         0,
         "TradePilot_ENTRY_EDIT",
         OBJPROP_TEXT
      );


   string stop =
      ObjectGetString(
         0,
         "TradePilot_SL_EDIT",
         OBJPROP_TEXT
      );


   // Resizing must never commit pending Daily Performance edits.

   double old_stop =
      StringToDouble(stop);


   // Existing objects are resized in place to avoid flashing.


   CalculatePanelScale();


   CreatePanel();
   ObjectSetString(0,"TradePilot_SCALE_VALUE",OBJPROP_TEXT,DoubleToString(manual_panel_scale*100.0,1)+"%");
   ObjectSetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TEXT,daily_target);


   if(StringToDouble(risk) > 0)
   {
      ObjectSetString(
         0,
         "TradePilot_RISK_EDIT",
         OBJPROP_TEXT,
         risk
      );
   }


   if(StringToDouble(entry) > 0)
   {
      ObjectSetString(
         0,
         "TradePilot_ENTRY_EDIT",
         OBJPROP_TEXT,
         entry
      );
   }


   if(old_stop > 0)
   {
      ObjectSetString(
         0,
         "TradePilot_SL_EDIT",
         OBJPROP_TEXT,
         stop
      );


      if(sl_line_enabled)
         UpdateStopLossLineFromInput();
   }


   UpdatePanel();


   TP_DailyEquivalent();
   TPDL_ClosedSummary();
   TPDL_FinalStatus();
   TPDA_LimitButtons();TPDA_PerformanceRows();
   TPC_Render();TPDC_Render();TPDL_NoticeRender();if(tp_spread_confirm_open)TP_SpreadTradePrompt();
   TP_BasketColumnLayout();
   TP_SizeRowLayout();
   TP_PanelVisibility();
   ChartRedraw();
}


// ============================================================
// UPDATE PANEL
// ============================================================

void UpdatePanel()
{
   TPR_Begin();
   TP_DailyChoiceRender();
   TP_BasketColumnLayout();

   TPDL_Render();
   string account_currency =
      AccountInfoString(
         ACCOUNT_CURRENCY
      );


   UpdatePanelBackground();


   // ========================================================
   // CURRENT SESSION BASKET
   // ========================================================

   datetime current_session =
      GetDailySessionStart();

   EnsureSessionState(current_session);

   int current_positions =
      GetSessionOpenPositionCount(current_session);

   ObjectSetString(
      0,
      "TradePilot_POSITIONS_VALUE",
      OBJPROP_TEXT,
      IntegerToString(current_positions)
   );

   double basket_profit =
      GetSessionFloatingProfit(current_session);

   ObjectSetString(
      0,
      "TradePilot_PROFIT_VALUE",
      OBJPROP_TEXT,
      DoubleToString(basket_profit, 2)
   );

   if(basket_profit > 0)
      ObjectSetInteger(0, "TradePilot_PROFIT_VALUE", OBJPROP_COLOR, C'90,220,140');
   else if(basket_profit < 0)
      ObjectSetInteger(0, "TradePilot_PROFIT_VALUE", OBJPROP_COLOR, C'255,100,100');
   else
      ObjectSetInteger(0, "TradePilot_PROFIT_VALUE", OBJPROP_COLOR, clrWhite);

   double remaining_money =
      GetSessionRemainingTargetMoney(current_session);

   ObjectSetString(
      0,
      "TradePilot_TARGET_VALUE",
      OBJPROP_TEXT,
      DoubleToString(remaining_money, 2)
   );

   ObjectSetString(
      0,
      "TradePilot_TARGET_UNIT",
      OBJPROP_TEXT,
      account_currency
   );

   if(current_positions > 0)
   {
      ObjectSetString(0, "TradePilot_STATUS_VALUE", OBJPROP_TEXT, "ACTIVE");
      ObjectSetInteger(0, "TradePilot_STATUS_VALUE", OBJPROP_COLOR, C'90,220,140');
   }
   else
   {
      ObjectSetString(0, "TradePilot_STATUS_VALUE", OBJPROP_TEXT, "WAITING");
      ObjectSetInteger(0, "TradePilot_STATUS_VALUE", OBJPROP_COLOR, C'255,190,80');
   }


   bool display_percent=GetDailyTargetMode()==DAILY_PERCENTAGE;
   double display_base=GetSessionStartBalance(current_session);
   string target_display=display_percent && display_base>0 ? DoubleToString(remaining_money/display_base*100,2)+"% ("+account_currency+" "+DoubleToString(remaining_money,2)+")" : DoubleToString(remaining_money,2);
   ObjectSetString(0,"TradePilot_TARGET_VALUE",OBJPROP_TEXT,target_display);
   ObjectSetString(0,"TradePilot_TARGET_UNIT",OBJPROP_TEXT,display_percent ? "" : account_currency);
   ObjectSetInteger(0,"TradePilot_TARGET_UNIT",OBJPROP_TIMEFRAMES,display_percent?OBJ_NO_PERIODS:OBJ_ALL_PERIODS);
   // ========================================================
   // CARRY-OVER BASKETS
   // ========================================================

   int carry_baskets =
      GetCarryOverBasketCount(current_session);

   int carry_positions =
      GetCarryOverPositionCount(current_session);

   double carry_profit =
      GetCarryOverFloatingProfit(current_session);

   ObjectSetString(
      0,
      "TradePilot_CARRY_BASKETS_VALUE",
      OBJPROP_TEXT,
      IntegerToString(carry_baskets)
   );

   ObjectSetString(
      0,
      "TradePilot_CARRY_POSITIONS_VALUE",
      OBJPROP_TEXT,
      IntegerToString(carry_positions)
   );

   ObjectSetString(
      0,
      "TradePilot_CARRY_PROFIT_VALUE",
      OBJPROP_TEXT,
      DoubleToString(carry_profit, 2)
   );

   ObjectSetString(
      0,
      "TradePilot_CARRY_CURRENCY",
      OBJPROP_TEXT,
      account_currency
   );

   if(carry_profit > 0)
      ObjectSetInteger(0, "TradePilot_CARRY_PROFIT_VALUE", OBJPROP_COLOR, C'90,220,140');
   else if(carry_profit < 0)
      ObjectSetInteger(0, "TradePilot_CARRY_PROFIT_VALUE", OBJPROP_COLOR, C'255,100,100');
   else
      ObjectSetInteger(0, "TradePilot_CARRY_PROFIT_VALUE", OBJPROP_COLOR, clrWhite);


   // ========================================================
   // DAILY PERFORMANCE
   // ========================================================

   if(
      GetDailyTargetMode() ==
      DAILY_PERCENTAGE
   )
   {


      ObjectSetString(
         0,
         "TradePilot_REMAINING_UNIT",
         OBJPROP_TEXT,
         "%"
      );


      ObjectSetString(
         0,
         "TradePilot_REMAINING_VALUE",
         OBJPROP_TEXT,
         DoubleToString(
            GetRemainingDailyTargetPercent(),
            2
         )
      );
   }
   else
   {


      ObjectSetString(
         0,
         "TradePilot_REMAINING_UNIT",
         OBJPROP_TEXT,
         account_currency
      );


      ObjectSetString(
         0,
         "TradePilot_REMAINING_VALUE",
         OBJPROP_TEXT,
         DoubleToString(
            GetRemainingDailyTargetMoney(),
            2
         )
      );
   }


   double daily_profit =
      GetTodayClosedProfit();


   double daily_percent =
      GetTodayClosedProfitPercent();


   ObjectSetString(
      0,
      "TradePilot_DAILY_CLOSED_VALUE",
      OBJPROP_TEXT,
      DoubleToString(
         daily_profit,
         2
      )
   );


   ObjectSetString(
      0,
      "TradePilot_DAILY_PERCENT_VALUE",
      OBJPROP_TEXT,
      DoubleToString(
         daily_percent,
         2
      )
   );


   color daily_color =
      clrWhite;


   if(daily_profit > 0)
   {
      daily_color =
         C'90,220,140';
   }
   else if(daily_profit < 0)
   {
      daily_color =
         C'255,100,100';
   }


   ObjectSetInteger(
      0,
      "TradePilot_DAILY_CLOSED_VALUE",
      OBJPROP_COLOR,
      daily_color
   );


   ObjectSetInteger(
      0,
      "TradePilot_DAILY_PERCENT_VALUE",
      OBJPROP_COLOR,
      daily_color
   );


   if(IsDailyTargetReached())
   {
      ObjectSetString(
         0,
         "TradePilot_DAILY_STATUS_VALUE",
         OBJPROP_TEXT,
         "TARGET REACHED"
      );


      ObjectSetInteger(
         0,
         "TradePilot_DAILY_STATUS_VALUE",
         OBJPROP_COLOR,
         C'90,220,140'
      );


      ObjectSetInteger(
         0,
         "TradePilot_REMAINING_VALUE",
         OBJPROP_COLOR,
         C'90,220,140'
      );
   }
   else
   {
      ObjectSetString(
         0,
         "TradePilot_DAILY_STATUS_VALUE",
         OBJPROP_TEXT,
         "IN PROGRESS"
      );


      ObjectSetInteger(
         0,
         "TradePilot_DAILY_STATUS_VALUE",
         OBJPROP_COLOR,
         C'255,190,80'
      );


      ObjectSetInteger(
         0,
         "TradePilot_REMAINING_VALUE",
         OBJPROP_COLOR,
         C'255,190,80'
      );
   }


   // ========================================================
   // POSITION SIZER
   // ========================================================

   ObjectSetString(
      0,
      "TradePilot_SYMBOL_VALUE",
      OBJPROP_TEXT,
      _Symbol
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
      "TradePilot_BROKER_MAX_VALUE",
      OBJPROP_TEXT,
      DoubleToString(
         SymbolInfoDouble(
            _Symbol,
            SYMBOL_VOLUME_MAX
         ),
         2
      )
   );


   UpdateStopLossLineButton();


   TP_DailyEquivalent();
   TPDL_ClosedSummary();
   TPDL_FinalStatus();
   TPDA_LimitButtons();TPDA_PerformanceRows();
   TPC_Render();TPDC_Render();TPDL_NoticeRender();if(tp_spread_confirm_open)TP_SpreadTradePrompt();
   TP_BasketColumnLayout();
   TP_SizeRowLayout();
   TP_PanelVisibility();
   TPR_End();
   ChartRedraw();
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
 // Enter/edit completion uses the same validation and review as Update; never save silently.
 if(id==CHARTEVENT_OBJECT_ENDEDIT && sparam=="TradePilot_DAILY_TARGET_EDIT"){TP_DailyChoiceEvent("TradePilot_DAILY_UPDATE");return;}
 if(id==CHARTEVENT_OBJECT_ENDEDIT && sparam=="TradePilot_LIMIT_EDIT"){TPDL_Event("TradePilot_LIMIT_UPDATE");return;}

 if(id==CHARTEVENT_OBJECT_ENDEDIT && sparam=="TradePilot_SCALE_VALUE") {
  if(tp_spread_confirm_open||tpc_open||tpdc_open){ObjectSetString(0,sparam,OBJPROP_TEXT,DoubleToString(manual_panel_scale*100.0,1)+"%");return;}
  string text=ObjectGetString(0,sparam,OBJPROP_TEXT);StringTrimLeft(text);StringTrimRight(text);
  if(StringLen(text)>0 && StringSubstr(text,StringLen(text)-1)=="%")text=StringSubstr(text,0,StringLen(text)-1);
  bool valid=StringLen(text)>0;bool dot=false;
  for(int i=0;i<StringLen(text);i++){ushort c=StringGetCharacter(text,i);if(c==46&&!dot){dot=true;continue;}if(c<48||c>57)valid=false;}
  double percent=StringToDouble(text);
  if(!valid||!MathIsValidNumber(percent)||percent<50||percent>150){Alert("Enter a zoom percentage from 50 to 150, for example 100%.");ObjectSetString(0,sparam,OBJPROP_TEXT,DoubleToString(manual_panel_scale*100.0,1)+"%");return;}
  manual_panel_scale=percent/100.0;

  GlobalVariableSet(GV_PANEL_SCALE,manual_panel_scale);GlobalVariablesFlush();
  RebuildResponsivePanel();TPM_Render();return;
 }

 if(id==CHARTEVENT_OBJECT_CLICK && TPDL_NoticeEvent(sparam))return;
 if(id==CHARTEVENT_OBJECT_CLICK && tp_spread_confirm_open) {
  if(sparam=="TradePilot_SPREAD_CONFIRM_CANCEL"){TP_SpreadTradeClose();return;}
  if(sparam=="TradePilot_SPREAD_CONFIRM_CONTINUE"){int side=tp_spread_pending_side;bool calculation=tp_spread_pending_calculation;TP_SpreadTradeClose();if(calculation)TP_CalculateRequested(true);else ExecutePanelTrade((ENUM_ORDER_TYPE)side,true);return;}
  return;
 }

   if(tpc_open&&id==CHARTEVENT_OBJECT_CLICK){TPC_Event(sparam);return;}

   if(tpdc_open&&id==CHARTEVENT_OBJECT_CLICK){TP_DailyChoiceEvent(sparam);return;}

   if(id==CHARTEVENT_OBJECT_CLICK && sparam=="TradePilot_SPREAD_TOGGLE")
   {
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      if(StringToDouble(ObjectGetString(0,"TradePilot_SL_EDIT",OBJPROP_TEXT))<=0 || StringToDouble(ObjectGetString(0,"TradePilot_ENTRY_EDIT",OBJPROP_TEXT))<=0) {Alert("Enter a valid entry and planned stop before switching Spread ON/OFF.");return;}
      if(!tp_spread_on) tp_spread_base=StringToDouble(ObjectGetString(0,"TradePilot_SL_EDIT",OBJPROP_TEXT));
      tp_spread_on=!tp_spread_on;TP_SpreadStop(false);return;
   }
   if(TPP_Event(id, sparam)) return;
   if(TPM_Event(id, sparam)) return;
   // --------------------------------------------------------
   // CHART RESIZE
   // --------------------------------------------------------

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


   // --------------------------------------------------------
   // STOP LOSS LINE DRAG
   // --------------------------------------------------------

   if(
      id == CHARTEVENT_OBJECT_DRAG &&
      sparam == "TradePilot_SL_LINE"
   )
   {
      UpdateStopLossFromLine();
      TP_SpreadStop(true);
      return;
   }


   // --------------------------------------------------------
   // BUTTONS
   // --------------------------------------------------------

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // -----------------------------------------------------
      // MANUAL PANEL SCALE
      // -----------------------------------------------------

      if(
         sparam == "TradePilot_SCALE_MINUS" ||
         sparam == "TradePilot_SCALE_PLUS"
      )
      {
         ObjectSetInteger(
            0,
            sparam,
            OBJPROP_STATE,
            false
         );


         if(sparam == "TradePilot_SCALE_MINUS")
            manual_panel_scale -= 0.01;
         else
            manual_panel_scale += 0.01;


         if(manual_panel_scale < 0.50)
            manual_panel_scale = 0.50;


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


      // -----------------------------------------------------
      // DAILY TARGET MODE
      // -----------------------------------------------------

   if(TPDR_Event(sparam)) return;
   if(TPDA_LimitEvent(sparam)) return;
   if(TPDL_Event(sparam)) return;
   if(TPC_Event(sparam)) return;
   if(TP_DailyChoiceEvent(sparam)) return;
      if(sparam == "TradePilot_DAILY_MODE_BUTTON")
      {
         ObjectSetInteger(
            0,
            "TradePilot_DAILY_MODE_BUTTON",
            OBJPROP_STATE,
            false
         );


         if(
            GetDailyTargetMode() ==
            DAILY_PERCENTAGE
         )
         {
            GlobalVariableSet(
               GV_DAILY_MODE,
               (double)DAILY_MONEY
            );
         }
         else
         {
            GlobalVariableSet(
               GV_DAILY_MODE,
               (double)DAILY_PERCENTAGE
            );
         }


         datetime current_session =
            GetDailySessionStart();

         EnsureSessionState(current_session);

         GlobalVariableSet(
            SessionKey(current_session, "MODE"),
            (double)GetDailyTargetMode()
         );


         UpdatePanel();
         return;
      }


      // -----------------------------------------------------
      // RISK MODE
      // -----------------------------------------------------

      if(sparam == "TradePilot_RISK_MODE_BUTTON")
      {
         ObjectSetInteger(
            0,
            "TradePilot_RISK_MODE_BUTTON",
            OBJPROP_STATE,
            false
         );


         if(risk_mode == RISK_PERCENTAGE)
         {
            risk_mode =
               RISK_MONEY;


            ObjectSetString(
               0,
               "TradePilot_RISK_MODE_BUTTON",
               OBJPROP_TEXT,
               "MONEY"
            );


            ObjectSetString(
               0,
               "TradePilot_RISK_UNIT",
               OBJPROP_TEXT,
               AccountInfoString(
                  ACCOUNT_CURRENCY
               )
            );
         }
         else
         {
            risk_mode =
               RISK_PERCENTAGE;


            ObjectSetString(
               0,
               "TradePilot_RISK_MODE_BUTTON",
               OBJPROP_TEXT,
               "PERCENTAGE"
            );


            ObjectSetString(
               0,
               "TradePilot_RISK_UNIT",
               OBJPROP_TEXT,
               "%"
            );
         }


         ChartRedraw();
         return;
      }


      // -----------------------------------------------------
      // SL LINE
      // -----------------------------------------------------

      if(sparam == "TradePilot_SL_LINE_BUTTON")
      {
         ObjectSetInteger(
            0,
            "TradePilot_SL_LINE_BUTTON",
            OBJPROP_STATE,
            false
         );


         ToggleStopLossLine();
         return;
      }


      // -----------------------------------------------------
      // Sizing uses stop-loss price risk consistently across master and follower
      // -----------------------------------------------------




      // -----------------------------------------------------
      // EXECUTE BUY / SELL FROM PANEL
      // -----------------------------------------------------

      if(sparam == "TradePilot_BUY_BUTTON")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ExecutePanelTrade(ORDER_TYPE_BUY);
         return;
      }

      if(sparam == "TradePilot_SELL_BUTTON")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ExecutePanelTrade(ORDER_TYPE_SELL);
         return;
      }


      // -----------------------------------------------------
      // CALCULATE
      // -----------------------------------------------------

      if(sparam == "TradePilot_CALCULATE_BUTTON")
      {
         ObjectSetInteger(
            0,
            "TradePilot_CALCULATE_BUTTON",
            OBJPROP_STATE,
            false
         );


         TP_CalculateRequested();
         return;
      }


   }


   // --------------------------------------------------------
   // EDIT BOXES
   // --------------------------------------------------------

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == "TradePilot_DAILY_TARGET_EDIT")
      {
         // Keep the edited target pending until Update is confirmed.
         return;
      }


      if(sparam == "TradePilot_SL_EDIT")
      {
         UpdateStopLossLineFromInput();
         TP_SpreadStop(true);
         return;
      }
   }
}


// ============================================================
// DELETE PANEL
// ============================================================

void DeletePanel()
{
   ObjectsDeleteAll(0,"TPUI_");
   ObjectsDeleteAll(
      0,
      "TradePilot_"
   );


   ChartRedraw();
}


// ============================================================
// INITIALIZATION
// ============================================================

int OnInit()
{
   // Clear only our saved tool objects; broker orders and chart studies remain untouched.
   ObjectsDeleteAll(0,"TPP_");ObjectsDeleteAll(0,"TPM_");

   CreateGlobalVariableNames();


   InitializeSharedVariables();


   CalculatePanelScale();


   CreatePanel();


   EventSetTimer(1);


   UpdatePanel();


   TP_LocalInit();
   TPM_Init();
   return INIT_SUCCEEDED;
}


// ============================================================
// SHUTDOWN
// ============================================================

void OnDeinit(
   const int reason
)
{
   TPP_Deinit();
   ObjectsDeleteAll(0, "TPM_");
   TP_LocalDeinit();
   EventKillTimer();


   DeletePanel();
}


// ============================================================
// MAIN PROCESS
// ============================================================

void ProcessEA()
{
   // Freeze the current session settings and discover any
   // carried session baskets from their original open times.
   EnsureSessionState(GetDailySessionStart());

   for(int i = 0; i < PositionsTotal(); i++)
      EnsureSessionState(GetPositionSessionStartByIndex(i));

   UpdatePanel();


   CheckBasketTakeProfit();
}


// ============================================================
// TICK
// ============================================================

void OnTick()
{
   ProcessEA();
}


// ============================================================
// TIMER
// ============================================================

void OnTimer()
{
   TPP_Poll();
   TP_LocalPoll();
   TP_ChartPoll();
   TPM_Render();
   ProcessEA();
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
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_CALC_MODE); if(mode == SYMBOL_CALC_MODE_FOREX || mode == SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE) return _Point * ((_Digits == 3 || _Digits == 5) ? 10.0 : 1.0);
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
 TPM_Widget("SPREAD",OBJ_BUTTON,12,185,132,24,tpm_spread_on?"SPREAD ON":"SPREAD OFF",clrWhite,tpm_spread_on?C'35,115,80':C'140,45,45');
 ObjectSetString(0,"TPM_SPREAD",OBJPROP_TOOLTIP,"Use only this chart's broker spread. ON moves this measuring stop one current spread farther from entry and updates its ratio; OFF restores the base measuring stop. Dragging the stop creates a new base. It never changes a broker order or the position sizer's separate spread control.");
 string caption=fresh?"Spread: "+DoubleToString(tpm_spread_price/_Point,1)+" points":"Spread: waiting for broker quote";
 TPM_Widget("SPREAD_INFO",OBJ_LABEL,12,212,0,0,caption,clrWhite,clrNONE);
 ObjectSetString(0,"TPM_SPREAD_INFO",OBJPROP_TOOLTIP,"The current difference between this chart\'s buying and selling prices, measured in broker points. Spread ON adds this distance to the measuring stop. Waiting means a fresh broker price has not arrived.");
 if(TP_LocalBridge && TP_BridgeToken!="" && TP_AccountId!="") {
  string text="MEASURE\t"+TP_BridgeToken+"\t"+TP_AccountId+"\t"+TP_Login()+"\t"+TP_Server()+"\tMT5\t"+TP_Int(TimeGMT())+"\t"+TP_Int(ChartID())+"\t"+_Symbol+"\t"+(tpm_spread_on?"1":"0")+"\t"+(fresh?"1":"0")+"\t"+TP_Num(tpm_spread_price)+"\t"+TP_Num(_Point>0?tpm_spread_price/_Point:0)+"\t"+TP_Num(tpm_spread_cash)+"\t"+AccountInfoString(ACCOUNT_CURRENCY)+"\t"+TP_Num(tpm_prices[0])+"\t"+TP_Num(tpm_prices[1])+"\t"+TP_Num(tpm_prices[2])+"\t"+TimeToString(TPDL_Now(),TIME_DATE|TIME_SECONDS)+"\r\n";
  TP_Atomic(".measurement-"+TP_Int(ChartID())+".tsv",text);
 }
 return !tpm_spread_on || fresh;
}

void TPM_Render()
{
   tpm_scale = panel_scale;
   long width = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(width > TPM_X()+12) tpm_scale = MathMin(tpm_scale, (double)(width-TPM_X()-12)/304.0);
   TPM_Widget("BG", OBJ_RECTANGLE_LABEL, 0, 0, 304, tpm_on ? ((tpm_prices[1]<tpm_prices[0] && tpm_prices[2]>tpm_prices[0]) || (tpm_prices[1]>tpm_prices[0] && tpm_prices[2]<tpm_prices[0]) ? 302 : 322) : 31, "", clrSlateGray, C'24,29,39');
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
   TPM_Widget("RISK_CAPTION", OBJ_LABEL, 12, 240, 0, 0, "Risk", clrSilver, clrNONE);
   TPM_Widget("RISK", OBJ_EDIT, 53, 234, 108, 26, DoubleToString(tpm_risk,2), clrWhite, C'37,44,57');
   TPM_Widget("PERCENT", OBJ_BUTTON, 170, 234, 42, 26, "%", clrWhite, tpm_percent ? C'35,115,80' : C'65,70,80');
   TPM_Widget("CASH", OBJ_BUTTON, 219, 234, 73, 26, "CASH", clrWhite, tpm_percent ? C'65,70,80' : C'35,115,80');
   string unit = tpm_percent ? "%" : AccountInfoString(ACCOUNT_CURRENCY);
   bool opposite = (tpm_prices[1]<tpm_prices[0] && tpm_prices[2]>tpm_prices[0]) ||
                   (tpm_prices[1]>tpm_prices[0] && tpm_prices[2]<tpm_prices[0]);
   color potential_color=ready?(opposite?C'35,115,80':C'140,45,45'):clrSilver;
   color potential_font=ready?(opposite?tpm_colors[2]:tpm_colors[1]):clrSilver;
   TPM_Widget("RETURN_BORDER",OBJ_RECTANGLE_LABEL,8,266,288,28,"",potential_color,C'24,29,39');
   ObjectSetInteger(0,"TPM_RETURN_BORDER",OBJPROP_BORDER_COLOR,potential_color);
   TPM_Widget("RETURN", OBJ_LABEL, 12, 273, 0, 0, "POTENTIAL   "+(valid ? DoubleToString(rr*tpm_risk,2)+" "+unit : "n/a"), potential_font, clrNONE, 10);
   ObjectSetString(0,"TPM_RETURN",OBJPROP_TOOLTIP,"Potential is the measured target value. Green means entry is between Stop Loss and Take Profit. Red means both lines are on the same side of entry, so this is not a valid profit-and-loss layout. Move one line across entry. This is a measurement, not a realised trading loss.");

   ObjectSetInteger(0,"TPM_BG",OBJPROP_YSIZE,TPM_S(ready && !opposite?322:302));
   if(ready && !opposite)TPM_Widget("NOTE", OBJ_LABEL, 12, 300, 0, 0, "SL/TP not opposite entry; distance ratio only", clrSilver, clrNONE);
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
#include "TradePilotDailyApply.mqh"
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
 if(tp_daily_choice_session!=GetDailySessionStart()) {tp_daily_choice_session=GetDailySessionStart();tp_daily_wins=TP_DailyInclude(tp_daily_choice_session,1);tp_daily_losses=TP_DailyInclude(tp_daily_choice_session,-1);}
 int x=LabelX(),y=PanelY()+S(184);
 CreateButton("TradePilot_DAILY_CHOICE_WINS","APPLY WINS",x,y,S(130),S(20),tp_daily_wins?C'35,115,80':C'140,45,45');
 CreateButton("TradePilot_DAILY_CHOICE_LOSSES","APPLY LOSSES",ValueX(),y,S(130),S(20),tp_daily_losses?C'35,115,80':C'140,45,45');
 CreateButton("TradePilot_DAILY_UPDATE","UPDATE",(LabelX()+ValueX()+S(130)-S(88))/2,PanelY()+S(211),S(88),S(19),C'55,60,70');
 ObjectSetString(0,"TradePilot_DAILY_UPDATE",OBJPROP_TOOLTIP,"Click to save Daily Performance: target, Apply wins and Apply losses. Daily Loss Limit has its own Update. Red/green applies to ON/OFF switches; Update is a save action. Invalid input leaves settings unchanged.");
 ObjectSetString(0,"TradePilot_DAILY_CHOICE_WINS",OBJPROP_TOOLTIP,"Default OFF. Turn ON to subtract this day's completed Current Basket wins from the daily target. The preview updates immediately. Update and Yes saves this section only; reports keep actual results.");
 ObjectSetString(0,"TradePilot_DAILY_CHOICE_LOSSES",OBJPROP_TOOLTIP,"Default OFF. Turn ON to add this day's completed Current Basket losses to the daily target. The preview updates immediately. Update and Yes saves this section only. Daily Loss Limit has separate choices.");

}
string TPDC_InputSignature()
{return ObjectGetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TEXT)+"|"+(TPDR_Enabled()?"Ratio":ObjectGetString(0,"TradePilot_DAILY_MODE_BUTTON",OBJPROP_TEXT))+"|"+(tp_daily_wins?"1":"0")+"|"+(tp_daily_losses?"1":"0")+"|"+(tp_limit_wins?"1":"0")+"|"+(tp_limit_losses?"1":"0")+"|"+ObjectGetString(0,"TradePilot_LIMIT_EDIT",OBJPROP_TEXT)+"|"+(tpdl_edit_percent?"1":"0");}
void TPDC_Close(){tpdc_open=false;ObjectsDeleteAll(0,"TradePilot_DAILY_CONFIRM_");}
void TPDC_Render()
{
 if(!tpdc_open)return;
 int x=PanelX()+PanelWidth()+S(24),y=PanelY()+S(55),w=S(280);
 CreateRectangle("TradePilot_DAILY_CONFIRM_BG",x,y,w,S(160),C'25,30,40',C'85,95,110');
 CreateLabel("TradePilot_DAILY_CONFIRM_TITLE",(tpdc_loss?"Confirm Daily Loss Limit":"Confirm Daily Performance"),x+S(12),y+S(12),FontSize(BASE_FONT_NORMAL),clrWhite);
 double reviewed_wins=0,reviewed_losses=0;TPDA_Closed(tpdc_period,reviewed_wins,reviewed_losses);
 string review_currency=AccountInfoString(ACCOUNT_CURRENCY);
 bool review_wins=tpdc_loss?tp_limit_wins:tp_daily_wins,review_losses=tpdc_loss?tp_limit_losses:tp_daily_losses;
 string win_review="Apply wins: "+(review_wins?"ON "+review_currency+" "+DoubleToString(reviewed_wins,2):"OFF");
 string loss_review="Apply losses: "+(review_losses?"ON "+review_currency+" "+DoubleToString(MathAbs(reviewed_losses),2):"OFF");
 CreateLabel("TradePilot_DAILY_CONFIRM_WINS",win_review,x+S(12),y+S(38),TP_HeaderFont(win_review,FontSize(BASE_FONT_NORMAL),S(252),S(16)),clrWhite);
 CreateLabel("TradePilot_DAILY_CONFIRM_LOSSES",loss_review,x+S(12),y+S(58),TP_HeaderFont(loss_review,FontSize(BASE_FONT_NORMAL),S(252),S(16)),clrWhite);

 double entered=TPDR_Parse(ObjectGetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TEXT));
 double proposed=TPDR_Enabled()?entered*TPDR_RiskCash():(GlobalVariableGet(GV_DAILY_MODE)>0.5?GetSessionStartBalance(tpdc_period)*entered/100:entered);
 proposed=TPDA_Target(tpdc_period,proposed,true);
 double delta=proposed-GetSessionTargetMoney(tpdc_period);
 double amount=MathAbs(delta),balance=GetSessionStartBalance(tpdc_period),risk=TPDR_RiskCash();
 string cash=AccountInfoString(ACCOUNT_CURRENCY)+" "+DoubleToString(amount,2);
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
  if(tpdc_period!=GetDailySessionStart()||tpdc_signature!=TPDC_InputSignature()){TPDC_Close();Alert("Daily settings changed. Review them and press Update again.");UpdatePanel();return true;}
  if(tpdc_loss){
   if(!TPDL_SavePending(true)){TPDC_Close();UpdatePanel();return true;}
   TPDA_LimitSave(tpdc_period);TPDC_Close();UpdatePanel();return true;
  }
  double pending_target=TPDR_Parse(ObjectGetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TEXT));
  if(!MathIsValidNumber(pending_target)||pending_target<=0){TPDC_Close();return true;}
  if(!ReadDailyTarget())return true;
  GlobalVariableSet(SessionKey(tpdc_period,"APPLY_WINS"),tp_daily_wins?1:0);GlobalVariableSet(SessionKey(tpdc_period,"APPLY_LOSSES"),tp_daily_losses?1:0);
  TPDA_TargetSave(tpdc_period);
  TPDC_Close();UpdatePanel();return true;
 }
 if(name=="TradePilot_DAILY_UPDATE"){
  ObjectSetInteger(0,name,OBJPROP_STATE,false);
  if(tp_daily_choice_session!=GetDailySessionStart()){TP_DailyChoiceRender();Alert("The daily period has changed. Review the checkboxes and press Update again.");return true;}
  double value=TPDR_Parse(ObjectGetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TEXT));
  if(!MathIsValidNumber(value)||value<=0){Alert("Enter a positive daily target or valid risk-to-reward ratio before pressing Update.");return true;}
  double preview_wins=0,preview_losses=0;if(!TPDA_Closed(tp_daily_choice_session,preview_wins,preview_losses)){Alert("Wait for verified Current Basket results before applying wins or losses.");return true;}
  TPC_Close();tpdc_loss=false;tpdc_open=true;tpdc_period=tp_daily_choice_session;tpdc_signature=TPDC_InputSignature();TPDC_Render();ChartRedraw();return true;
 }
 if(StringFind(name,"TradePilot_DAILY_CHOICE_")!=0)return false;
 ObjectSetInteger(0,name,OBJPROP_STATE,false);
 if(name=="TradePilot_DAILY_CHOICE_WINS")tp_daily_wins=!tp_daily_wins;
 if(name=="TradePilot_DAILY_CHOICE_LOSSES")tp_daily_losses=!tp_daily_losses;
 TPDC_Close();UpdatePanel();return true;
}

void TP_DailyEquivalent()
{
 TP_SizerRiskEquivalents();
 datetime period=GetDailySessionStart();
 TPDR_TargetEquivalents(period,GetSessionTargetMoney(period),GetSessionTargetMode(period)==DAILY_PERCENTAGE,AccountInfoString(ACCOUNT_CURRENCY));
 double remaining=GetSessionRemainingTargetMoney(period),balance=GetSessionStartBalance(period);
 double day_closed=0,day_floating=0,day_adjusted=0;
 if(TPDL_Totals(day_closed,day_floating,day_adjusted)) remaining=MathMax(0,GetSessionTargetMoney(period)-day_adjusted);
 ObjectSetString(0,"TradePilot_REMAINING_VALUE",OBJPROP_TEXT,(GetSessionTargetMode(period)==DAILY_PERCENTAGE && balance>0 ? DoubleToString(remaining/balance*100,2)+"% " : "")+"("+AccountInfoString(ACCOUNT_CURRENCY)+" "+DoubleToString(remaining,2)+")");
 ObjectSetString(0,"TradePilot_REMAINING_UNIT",OBJPROP_TEXT,"");
 ObjectSetInteger(0,"TradePilot_REMAINING_UNIT",OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
 string primary="",second="",third="";
 TPDR_RemainingParts(period,remaining,balance,AccountInfoString(ACCOUNT_CURRENCY),GlobalVariableGet(GV_DAILY_MODE)>0.5,primary,second,third,true);
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
 ObjectSetInteger(0,"TradePilot_REMAINING_VALUE",OBJPROP_COLOR,!closed_ready?clrWhite:closed_net>0?C'90,220,140':closed_net<0?C'255,100,100':clrWhite);
 ObjectSetString(0,"TradePilot_MARGIN_UNIT",OBJPROP_TEXT,AccountInfoString(ACCOUNT_CURRENCY));
 string old_risk[]={"TradePilot_RISK_AMOUNT_LABEL","TradePilot_RISK_AMOUNT_VALUE","TradePilot_RISK_AMOUNT_UNIT"};
 for(int i=0;i<ArraySize(old_risk);i++)ObjectDelete(0,old_risk[i]);
 TP_BasketCostsRender(period);
 TP_BasketProgressRows(period);
 string carry_display=TP_CarryMoneyPercent(GetCarryOverFloatingProfit(GetDailySessionStart()));
 ObjectSetString(0,"TradePilot_CARRY_PROFIT_VALUE",OBJPROP_TEXT,carry_display);
 ObjectSetInteger(0,"TradePilot_CARRY_PROFIT_VALUE",OBJPROP_FONTSIZE,TP_HeaderFont(carry_display,FontSize(BASE_FONT_NORMAL),S(132),S(15)));
 ObjectSetString(0,"TradePilot_CARRY_PROFIT_VALUE",OBJPROP_TOOLTIP,"Older baskets' open net result in account currency. The percentage uses the sum of their distinct original-day starting balances, counted once per day; it is not a cash-flow-adjusted investment return.");
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
 int x=PanelX()+PanelWidth()+S(24),y=PanelY()+S(55);
 int chart_width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),chart_height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
 x=MathMax(S(8),MathMin(x,chart_width-S(294)));y=MathMax(S(8),MathMin(y,chart_height-S(82)));
 string text=tp_spread_pending_calculation?"Spread OFF. Continue calculating?":"Spread OFF. Continue with this trade?";
 CreateRectangle("TradePilot_SPREAD_CONFIRM_BG",x-S(4),y-S(5),S(286),S(70),C'25,28,35',C'110,125,145');
 CreateLabel("TradePilot_SPREAD_CONFIRM_TEXT",text,x,y,TP_HeaderFont(text,FontSize(BASE_FONT_NORMAL),S(278),S(16)),clrWhite);
 ObjectSetString(0,"TradePilot_SPREAD_CONFIRM_TEXT",OBJPROP_TOOLTIP,tp_spread_pending_calculation?"Calculate using your entered stop without extra spread allowance. Continue calculates only; it sends no order. Cancel leaves the calculation unchanged.":"Continue this one trade using the entered stop without extra spread allowance. Quote, stop, risk, margin and trading permissions are checked again. Cancel sends nothing.");
 CreateButton("TradePilot_SPREAD_CONFIRM_CONTINUE","Continue",x,y+S(25),S(130),S(24),C'55,60,70');
 CreateButton("TradePilot_SPREAD_CONFIRM_CANCEL","Cancel",x+S(148),y+S(25),S(130),S(24),C'140,45,45');
 ObjectSetString(0,"TradePilot_SPREAD_CONFIRM_CONTINUE",OBJPROP_TOOLTIP,tp_spread_pending_calculation?"Calculate with spread allowance OFF. This does not place a trade.":"Continue this one order with spread allowance OFF after normal broker checks.");
 ObjectSetString(0,"TradePilot_SPREAD_CONFIRM_CANCEL",OBJPROP_TOOLTIP,"Cancel this request without sending an order or changing the spread setting.");
 ObjectSetInteger(0,"TradePilot_SPREAD_CONFIRM_CONTINUE",OBJPROP_ZORDER,100);
 ObjectSetInteger(0,"TradePilot_SPREAD_CONFIRM_CANCEL",OBJPROP_ZORDER,100);
 ChartRedraw();
}

void TP_CalculateRequested(bool confirmed=false)
{
 if(!tp_spread_on && !confirmed){tp_spread_pending_calculation=true;tp_spread_confirm_open=true;TP_SpreadTradePrompt();return;}
 CalculatePositionSize();
}

#include "TradePilotPanelVisibility.mqh"

// Status text uses the full value column; lots is meaningful only for a number.
void TP_SizeRowLayout()
{
#ifdef __MQL5__
 string value="TradePilot_SIZE_VALUE",unit="TradePilot_SIZE_UNIT";
#else
 string value="TradePilot_CALCULATED_VALUE",unit="TradePilot_CALCULATED_UNIT";
#endif
 if(ObjectFind(0,value)<0)return;
 string text=ObjectGetString(0,value,OBJPROP_TEXT);
 bool numeric=StringToDouble(text)>0;
 ObjectSetString(0,unit,OBJPROP_TEXT,"lots");
 ObjectSetInteger(0,unit,OBJPROP_TIMEFRAMES,numeric && tp_main_open?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
 int width=numeric?UnitX()-ValueX()-S(8):PanelX()+PanelWidth()-S(12)-ValueX();
 ObjectSetInteger(0,value,OBJPROP_FONTSIZE,TP_HeaderFont(text,FontSize(BASE_FONT_NORMAL),width,S(16)));
 string margin=ObjectGetString(0,"TradePilot_MARGIN_VALUE",OBJPROP_TEXT);
 if(text=="Not calculated" && margin=="Not verified") {
  ObjectSetString(0,"TradePilot_MARGIN_VALUE",OBJPROP_TEXT,"Not calculated");
  margin="Not calculated";
 }
 if(margin=="Not calculated" || margin=="Not verified")ObjectSetInteger(0,"TradePilot_MARGIN_VALUE",OBJPROP_COLOR,C'255,100,100');
}

void TP_SizeFailure(string title,string reason)
{
 ObjectSetString(0,"TradePilot_SIZE_VALUE",OBJPROP_TEXT,title);
 ObjectSetString(0,"TradePilot_SIZE_VALUE",OBJPROP_TOOLTIP,reason);
 ObjectSetInteger(0,"TradePilot_SIZE_VALUE",OBJPROP_COLOR,C'255,100,100');
 ObjectSetString(0,"TradePilot_MARGIN_VALUE",OBJPROP_TEXT,"Not calculated");
 TP_SizeRowLayout();ChartRedraw();
}

// The entered risk is one planned risk unit; do not change sizing or order volume.
void TP_SizerRiskEquivalents()
{
 if(ObjectFind(0,"TradePilot_RISK_EDIT")<0 || ObjectFind(0,"TradePilot_RISK_UNIT")<0)return;
 double entered=StringToDouble(ObjectGetString(0,"TradePilot_RISK_EDIT",OBJPROP_TEXT));
#ifdef __MQL5__
 bool percent=risk_mode==RISK_PERCENTAGE;
 double balance=AccountInfoDouble(ACCOUNT_BALANCE);
 string currency=AccountInfoString(ACCOUNT_CURRENCY);
#else
 bool percent=risk_percentage_mode;
 double balance=AccountBalance();
 string currency=AccountCurrency();
#endif
 bool ready=TerminalInfoInteger(TERMINAL_CONNECTED) && MathIsValidNumber(balance) && balance>0 && MathIsValidNumber(entered) && entered>0 && currency!="";
 double cash=percent?balance*entered/100:entered;
 string suffix=(percent?"%":currency)+" (Pending; Pending)";
 if(ready)suffix=percent?"% ("+currency+" "+DoubleToString(cash,2)+"; 1R)":currency+" ("+DoubleToString(entered/balance*100,2)+"%; 1R)";
 string help="Risk is the planned loss at the selected stop before broker execution effects. Percentage uses your current broker account balance; Cash uses its account currency. 1R means one entered cash-risk amount, not a promised return. The brackets show the other two equivalents. "+(ready?suffix:"Wait for a connected account balance and enter positive risk to show equivalents.");
 ObjectSetString(0,"TradePilot_RISK_LABEL",OBJPROP_TEXT,"Risk");
 ObjectSetInteger(0,"TradePilot_RISK_LABEL",OBJPROP_XDISTANCE,LabelX());
 ObjectSetInteger(0,"TradePilot_RISK_LABEL",OBJPROP_FONTSIZE,FontSize(BASE_FONT_NORMAL));
 ObjectSetInteger(0,"TradePilot_RISK_EDIT",OBJPROP_XDISTANCE,LabelX()+S(46));
 ObjectSetInteger(0,"TradePilot_RISK_EDIT",OBJPROP_XSIZE,S(54));
 ObjectSetInteger(0,"TradePilot_RISK_UNIT",OBJPROP_XDISTANCE,LabelX()+S(106));
 ObjectSetString(0,"TradePilot_RISK_UNIT",OBJPROP_TEXT,suffix);
 ObjectSetInteger(0,"TradePilot_RISK_UNIT",OBJPROP_FONTSIZE,TP_HeaderFont(suffix,FontSize(BASE_FONT_NORMAL),PanelWidth()-S(132),S(8)));
 ObjectSetInteger(0,"TradePilot_RISK_UNIT",OBJPROP_COLOR,ready?clrWhite:C'220,90,90');
 ObjectSetInteger(0,"TradePilot_RISK_UNIT",OBJPROP_YDISTANCE,ObjectGetInteger(0,"TradePilot_RISK_LABEL",OBJPROP_YDISTANCE));
 ObjectSetString(0,"TradePilot_RISK_EDIT",OBJPROP_TOOLTIP,help);
 ObjectSetString(0,"TradePilot_RISK_UNIT",OBJPROP_TOOLTIP,help);
 ObjectSetString(0,"TradePilot_RISK_LABEL",OBJPROP_TOOLTIP,help);
}
