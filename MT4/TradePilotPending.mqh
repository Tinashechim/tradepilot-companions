// User-directed pending orders. No timer action without explicit Schedule.
bool tpp_on=false;
string tpp_place_text="Now",tpp_expiry_text="No expiry",tpp_picker="";
MqlDateTime tpp_date;
int tpp_type=0;
string tpp_types[4]={"Buy Limit","Sell Limit","Buy Stop","Sell Stop"};
string tpp_note="Ready - broker time";
ulong tpp_ticket=0;
datetime tpp_at=0,tpp_expiry=0;
double tpp_volume=0,tpp_entry=0,tpp_sl=0,tpp_tp=0;
int tpp_scheduled_type=0;

void TPP_Widget(string key,ENUM_OBJECT type,int x,int y,int w,int h,string text,string help)
{
   string name="TPP_"+key;
   // Own saved widgets are cleared once at startup; preserve creation order on refresh.

   bool fresh=ObjectFind(0,name)<0;
   if(fresh && !ObjectCreate(0,name,type,0,0,0)) return;
   ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,TPM_X()+TPM_S(x));
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,PanelY()+TPM_S((tpm_on ? 283 : 39)+y));
   ObjectSetInteger(0,name,OBJPROP_COLOR,key=="TITLE"?C'90,180,255':clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,type==OBJ_RECTANGLE_LABEL ? 0 : 20);
   if(type==OBJ_LABEL) ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   else {
      ObjectSetInteger(0,name,OBJPROP_XSIZE,TPM_S(w));
      ObjectSetInteger(0,name,OBJPROP_YSIZE,TPM_S(h));
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,C'37,44,57');
      ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'65,74,90');
   }
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,FontSize(key=="TITLE"?BASE_FONT_SECTION:BASE_FONT_NORMAL));
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   if(type!=OBJ_EDIT || fresh) ObjectSetString(0,name,OBJPROP_TEXT,text);
   if(type==OBJ_EDIT) ObjectSetInteger(0,name,OBJPROP_READONLY,tpp_at>0);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,help);
}
void TPP_Visibility(string prefix,bool visible)
{
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--) {
      string name=ObjectName(0,i,-1,-1);
      if(StringFind(name,prefix)!=0 || name=="TPP_BG" || name=="TPP_TITLE" || name=="TPP_TOGGLE") continue;
      ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   }
}
void TPP_Calendar()
{
   string months[12]={"January","February","March","April","May","June","July","August","September","October","November","December"};
   TPP_Widget("CAL_BG",OBJ_RECTANGLE_LABEL,8,32,288,252,"","Dates and times use the connected broker clock.");
   TPP_Widget("CAL_PREV",OBJ_BUTTON,12,35,30,24,"<","Previous month");
   TPP_Widget("CAL_MONTH",OBJ_LABEL,50,39,0,0,months[tpp_date.mon-1]+" "+IntegerToString(tpp_date.year),"Broker calendar month");
   TPP_Widget("CAL_NEXT",OBJ_BUTTON,263,35,29,24,">","Next month");
   string days[7]={"Mo","Tu","We","Th","Fr","Sa","Su"};
   for(int i=0;i<7;i++) TPP_Widget("CAL_HEAD"+IntegerToString(i),OBJ_LABEL,14+i*40,65,0,0,days[i],"Weekday");
   MqlDateTime first=tpp_date;first.day=1;first.hour=0;first.min=0;first.sec=0;
   TimeToStruct(StructToTime(first),first);
   int offset=(first.day_of_week+6)%7;
   for(int day=1;day<=31;day++) {
      MqlDateTime candidate=first;candidate.day=day;MqlDateTime check;
      TimeToStruct(StructToTime(candidate),check);
      string key="CAL_DAY"+IntegerToString(day);
      if(check.mon!=first.mon) { ObjectDelete(0,"TPP_"+key);continue; }
      int cell=offset+day-1;
      TPP_Widget(key,OBJ_BUTTON,12+(cell%7)*40,82+(cell/7)*23,38,22,IntegerToString(day),"Choose broker calendar date");
      if(day==tpp_date.day) ObjectSetInteger(0,"TPP_"+key,OBJPROP_BGCOLOR,C'27,110,94');
   }
   TPP_Widget("CAL_HMIN",OBJ_BUTTON,12,225,28,24,"-","Previous hour");
   TPP_Widget("CAL_HOUR",OBJ_LABEL,46,229,0,0,StringFormat("%02d",tpp_date.hour),"Broker hour, 00 to 23");
   TPP_Widget("CAL_HPLUS",OBJ_BUTTON,73,225,28,24,"+","Next hour");
   TPP_Widget("CAL_MMIN",OBJ_BUTTON,111,225,28,24,"-","Previous minute");
   TPP_Widget("CAL_MINUTE",OBJ_LABEL,145,229,0,0,StringFormat("%02d",tpp_date.min),"Broker minute, 00 to 59");
   TPP_Widget("CAL_MPLUS",OBJ_BUTTON,173,225,28,24,"+","Next minute");
   TPP_Widget("CAL_USE",OBJ_BUTTON,211,225,81,24,"Use time","Use this date and time for "+tpp_picker);
   TPP_Widget("CAL_CLEAR",OBJ_BUTTON,12,255,135,24,tpp_picker=="PLACE" ? "Place now" : "No expiry","Explicitly choose immediate placement or no expiry. Fields are never blank.");
   TPP_Widget("CAL_BACK",OBJ_BUTTON,157,255,135,24,"Back","Return without changing the chosen time");
}
void TPP_Render()
{
   TPP_Widget("BG",OBJ_RECTANGLE_LABEL,0,0,304,tpp_on ? 292 : 31,"","Pending orders, using broker prices and broker time.");
   TPP_Widget("TITLE",OBJ_LABEL,12,8,0,0,"PENDING ORDER", "User-directed pending orders: Buy Limit, Sell Limit, Buy Stop and Sell Stop.");
   TPP_Widget("TOGGLE",OBJ_BUTTON,244,6,50,24,tpp_on ? "ON" : "OFF","Show or hide Pending Order. OFF cancels local scheduled placement; broker orders remain unchanged.");
   ObjectSetInteger(0,"TPP_TOGGLE",OBJPROP_BGCOLOR,tpp_on ? C'35,115,80' : C'140,45,45');
   if(!tpp_on) TPP_Visibility("TPP_",false);
   ObjectSetInteger(0,"TPP_TITLE",OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   if(!tpp_on) return;
   static string prior_view="";string view=tpp_picker!=""?"calendar":"fields";
   if(view!=prior_view){TPP_Visibility("TPP_",false);prior_view=view;}
   if(tpp_picker!="") { TPP_Calendar();return; }
   TPP_Widget("TYPE_LABEL",OBJ_LABEL,12,37,0,0,"Order type","Choose the broker pending-order type.");
   TPP_Widget("TYPE",OBJ_BUTTON,160,33,132,25,tpp_types[tpp_type],"Click to choose Buy Limit, Sell Limit, Buy Stop or Sell Stop.");
   string keys[4]={"VOLUME","ENTRY","SL","TP"};
   string labels[4]={"Volume (lots)","At price","Stop Loss","Take Profit"};
   string values[4]={"0.01","","0","0"};
   values[0]=DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),8);
   for(int i=0;i<4;i++) {
      TPP_Widget(keys[i]+"_LABEL",OBJ_LABEL,12,66+i*29,0,0,labels[i],i==0 ? "Order volume in lots. It must follow the broker minimum, maximum and volume step; available margin is checked separately." : i==1 ? "Entry price that triggers the selected pending-order type after placement; use this chart symbol price." : i==2 ? "Stop-loss price for the pending trade. Enter 0 to omit; a missing stop can prevent risk-based copying." : "Take-profit price for the pending trade. Enter 0 to omit.");
      TPP_Widget(keys[i],OBJ_EDIT,160,62+i*29,132,25,values[i],i==0 ? "Broker lot size, for example 0.01. Must match the symbol volume step." : i==1 ? "The price that triggers this pending order. Use the chart symbol price." : "Optional broker price. Enter 0 to omit this protection.");
   }
   TPP_Widget("PLACE_LABEL",OBJ_LABEL,12,182,0,0,"Place at","Optional scheduled placement time in broker time.");
   TPP_Widget("PLACE",OBJ_BUTTON,160,178,132,25,tpp_place_text,"Click for the broker calendar and hour/minute selectors. Now means immediate placement. Terminal and trading permissions must stay on. More than 10 seconds late fails without submitting.");
   TPP_Widget("EXPIRY_LABEL",OBJ_LABEL,12,211,0,0,"Expiry","Optional expiry of the broker pending order.");
   TPP_Widget("EXPIRY",OBJ_BUTTON,160,207,132,25,tpp_expiry_text,"Click for the broker calendar and hour/minute selectors. No expiry is an explicit choice. Selected expiry must be after placement. Unsupported expiry is rejected, never silently removed.");
   TPP_Widget("PLACE_BUTTON",OBJ_BUTTON,12,240,132,26,tpp_at>0 ? "Scheduled" : "Place / Schedule","Submit now or schedule the entered pending order. A broker pending order executes only when its price condition is met.");
   TPP_Widget("CANCEL",OBJ_BUTTON,160,240,132,26,"Cancel plan","Cancel this local scheduled placement. Existing broker orders remain unchanged.");
   TPP_Widget("STATUS",OBJ_LABEL,12,273,0,0,StringSubstr(tpp_note=="Ready - broker time" ? "Broker "+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS) : tpp_note,0,38),tpp_note);
}
string TPP_Text(string key) { string s=ObjectGetString(0,"TPP_"+key,OBJPROP_TEXT); StringTrimLeft(s);StringTrimRight(s);return s; }
void TPP_Result(string text) { tpp_note=text; Print("TradePilot pending order: ",text); Alert(text); }
bool TPP_Number(string key,double &value)
{
   string s=TPP_Text(key);int dots=0;
   if(StringLen(s)==0) return false;
   for(int i=0;i<StringLen(s);i++) {
      ushort c=StringGetCharacter(s,i);
      if(c==46) { if(++dots>1) return false; }
      else if(c<48 || c>57) return false;
   }
   value=StringToDouble(s);return MathIsValidNumber(value);
}
bool TPP_Date(string key,datetime &value)
{
   string s=TPP_Text(key);value=0;if(s=="Now" || s=="No expiry") return true;
   value=StringToTime(s);
   return value>0 && TimeToString(value,TIME_DATE|TIME_MINUTES)==s;
}
bool TPP_Permissions()
{
   return TerminalInfoInteger(TERMINAL_CONNECTED) && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
}
bool TPP_Validate(double volume,double entry,double sl,double tp,int kind,datetime expiry)
{
   string daily_reason="";if(!TPDL_EntryAllowed(daily_reason)) {TPP_Result(daily_reason);return false;}
   if(!TPP_Permissions()) { TPP_Result("Pending order not sent: check connection and trading permissions on this lead account chart."); return false; }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || tick.ask<=0 || tick.time<=0 || TimeCurrent()-tick.time>30) { TPP_Result("Pending order not sent: no fresh broker price.");return false; }
   double minlot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),maxlot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double ticksize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(step<=0 || ticksize<=0 || volume<minlot || volume>maxlot || MathAbs(volume/step-MathRound(volume/step))>0.000001) { TPP_Result("Pending order not sent: volume does not match broker lot limits or step.");return false; }
   if(entry<=0 || sl<0 || tp<0 || MathAbs(entry/ticksize-MathRound(entry/ticksize))>0.000001 || (sl>0 && MathAbs(sl/ticksize-MathRound(sl/ticksize))>0.000001) || (tp>0 && MathAbs(tp/ticksize-MathRound(tp/ticksize))>0.000001)) { TPP_Result("Pending order not sent: prices do not match this symbol's broker price step.");return false; }
   bool buy=kind==0 || kind==2;
   double distance=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   bool valid=kind==0 ? tick.ask-entry>0 && tick.ask-entry>=distance : kind==1 ? entry-tick.bid>0 && entry-tick.bid>=distance : kind==2 ? entry-tick.ask>0 && entry-tick.ask>=distance : tick.bid-entry>0 && tick.bid-entry>=distance;
   if(!valid || (sl>0 && (buy ? entry-sl<=0 || entry-sl<distance : sl-entry<=0 || sl-entry<distance)) || (tp>0 && (buy ? tp-entry<=0 || tp-entry<distance : entry-tp<=0 || entry-tp<distance))) { TPP_Result("Pending order not sent: entry, Stop Loss or Take Profit is on the wrong side or too close to the broker price.");return false; }
   if(TPDL_Limit()>0) {
    if(sl<=0) {TPP_Result("A Stop Loss is required to verify this pending order against the daily loss budget.");return false;}
#ifdef __MQL5__
    double planned=volume*GetPlannedLossPerLot(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,entry,sl);
#else
    double planned=volume*GetPlannedLossPerLot(entry,sl);
#endif
    if(!TPDL_AcceptRisk(planned,daily_reason)) {TPP_Result(daily_reason);return false;}
   }
   if(expiry>0 && expiry<=TimeCurrent()) { TPP_Result("Pending order not sent: expiry has passed.");return false; }
   return true;
}
void TPP_Send(double volume,double entry,double sl,double tp,int kind,datetime expiry)
{
   if(!TPP_Validate(volume,entry,sl,tp,kind,expiry)) return;
#ifdef __MQL5__
   MqlTradeRequest request={};MqlTradeResult result={};MqlTradeCheckResult check={};
   ENUM_ORDER_TYPE types[4]={ORDER_TYPE_BUY_LIMIT,ORDER_TYPE_SELL_LIMIT,ORDER_TYPE_BUY_STOP,ORDER_TYPE_SELL_STOP};
   long modes=SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE);
   if((expiry>0 && (modes & SYMBOL_EXPIRATION_SPECIFIED)==0) || (expiry==0 && (modes & SYMBOL_EXPIRATION_GTC)==0)) { TPP_Result("Pending order not sent: this broker does not support the selected expiry option.");return; }
   request.action=TRADE_ACTION_PENDING;request.symbol=_Symbol;request.volume=volume;request.type=types[kind];request.price=entry;request.sl=sl;request.tp=tp;
   request.type_filling=ORDER_FILLING_RETURN;request.type_time=expiry>0 ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;request.expiration=expiry;request.comment="TradePilot pending";
   if(!OrderCheck(request,check)) { TPP_Result("Pending order rejected by broker check: "+check.comment+" ("+IntegerToString(check.retcode)+").");return; }
   string daily_reason="";if(!TPDL_EntryAllowed(daily_reason)) {TPP_Result(daily_reason);return;}
   bool sent=OrderSend(request,result);
   if(sent && result.order>0 && (result.retcode==TRADE_RETCODE_PLACED || result.retcode==TRADE_RETCODE_DONE)) {tpp_ticket=result.order;TPP_Result("Broker accepted pending order #"+IntegerToString((long)result.order)+". Waiting for entry price.");}
   else TPP_Result("Pending order not confirmed: "+result.comment+" ("+IntegerToString(result.retcode)+"). Check broker orders before retrying.");
#else
   int types[4]={OP_BUYLIMIT,OP_SELLLIMIT,OP_BUYSTOP,OP_SELLSTOP};
   string daily_reason="";if(!TPDL_EntryAllowed(daily_reason)) {TPP_Result(daily_reason);return;}
   ResetLastError();int ticket=OrderSend(_Symbol,types[kind],volume,entry,0,sl,tp,"TradePilot pending",0,expiry,clrNONE);
   if(ticket>0) {tpp_ticket=(ulong)ticket;TPP_Result("Broker accepted pending order #"+IntegerToString(ticket)+". Waiting for entry price.");}
   else TPP_Result("Pending order not confirmed. Broker error "+IntegerToString(GetLastError())+". Check broker orders before retrying; expiry is never silently removed.");
#endif
}
void TPP_Poll()
{
   TPP_ObserveExecution();
   if(!tpp_on || tpp_at==0) return;
   datetime due=tpp_at;
   if(!TPP_Permissions()) { tpp_at=0;TPP_Result("Scheduled placement cancelled: connection or trading permission was lost. Set a new schedule when ready.");return; }
   if(TimeCurrent()<due) return;
   tpp_at=0; // Consume before sending; never retry or duplicate on timer refresh.
   if(TimeCurrent()-due>10) { TPP_Result("Scheduled placement missed: more than 10 seconds late. No order sent.");return; }
   TPP_Send(tpp_volume,tpp_entry,tpp_sl,tpp_tp,tpp_scheduled_type,tpp_expiry);
}
bool TPP_Event(int id,string name)
{
   if(StringFind(name,"TPP_")!=0) return false;
   if(id==CHARTEVENT_OBJECT_CLICK && name=="TPP_TOGGLE") {
      tpp_on=!tpp_on;tpp_picker="";
      if(!tpp_on && tpp_at>0) { tpp_at=0;TPP_Result("Pending Order OFF: local scheduled placement cancelled. Existing broker orders unchanged."); }
      TPP_Render();ChartRedraw();return true;
   }
   if(!tpp_on) return true;
   if(id==CHARTEVENT_OBJECT_CLICK && StringFind(name,"TPP_CAL_")==0) {
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
      if(name=="TPP_CAL_PREV") { tpp_date.mon--;if(tpp_date.mon<1) {tpp_date.mon=12;tpp_date.year--;}tpp_date.day=1; }
      if(name=="TPP_CAL_NEXT") { tpp_date.mon++;if(tpp_date.mon>12) {tpp_date.mon=1;tpp_date.year++;}tpp_date.day=1; }
      if(StringFind(name,"TPP_CAL_DAY")==0) tpp_date.day=(int)StringToInteger(StringSubstr(name,11));
      if(name=="TPP_CAL_HMIN") tpp_date.hour=(tpp_date.hour+23)%24;
      if(name=="TPP_CAL_HPLUS") tpp_date.hour=(tpp_date.hour+1)%24;
      if(name=="TPP_CAL_MMIN") tpp_date.min=(tpp_date.min+59)%60;
      if(name=="TPP_CAL_MPLUS") tpp_date.min=(tpp_date.min+1)%60;
      if(name=="TPP_CAL_USE" || name=="TPP_CAL_CLEAR") {
         string selected=name=="TPP_CAL_CLEAR" ? (tpp_picker=="PLACE" ? "Now" : "No expiry") : TimeToString(StructToTime(tpp_date),TIME_DATE|TIME_MINUTES);
         if(tpp_picker=="PLACE") tpp_place_text=selected;else tpp_expiry_text=selected;
         tpp_picker="";
      }
      if(name=="TPP_CAL_BACK") tpp_picker="";
      TPP_Render();ChartRedraw();return true;
   }
   if(id==CHARTEVENT_OBJECT_CLICK && (name=="TPP_PLACE" || name=="TPP_EXPIRY") && tpp_at==0) {
      tpp_picker=name=="TPP_PLACE" ? "PLACE" : "EXPIRY";
      string selected=tpp_picker=="PLACE" ? tpp_place_text : tpp_expiry_text;
      datetime date=StringToTime(selected);
      if(date<=0) date=TimeCurrent()+60;
      TimeToStruct(date,tpp_date);tpp_date.sec=0;
      TPP_Render();ChartRedraw();return true;
   }
   if(tpp_picker!="") return true;
   if(id==CHARTEVENT_OBJECT_CLICK) {
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
      if(name=="TPP_TYPE" && tpp_at==0) tpp_type=(tpp_type+1)%4;
      if(name=="TPP_CANCEL") { tpp_at=0;TPP_Result("Local scheduled placement cancelled. Broker orders unchanged."); }
      if(name=="TPP_PLACE_BUTTON" && tpp_at==0) {
         double volume,entry,sl,tp;datetime at,expiry;
         if(!TPP_Number("VOLUME",volume) || !TPP_Number("ENTRY",entry) || !TPP_Number("SL",sl) || !TPP_Number("TP",tp) || !TPP_Date("PLACE",at) || !TPP_Date("EXPIRY",expiry)) TPP_Result("Check inputs: numeric lot size and prices; dates must be YYYY.MM.DD HH:MM in broker time.");
         else if(at>0 && at<=TimeCurrent()) TPP_Result("Scheduled placement must be in the future, using broker time.");
         else if(expiry>0 && expiry<=(at>0 ? at : TimeCurrent())) TPP_Result("Expiry must be later than placement.");
         else if(TPP_Validate(volume,entry,sl,tp,tpp_type,expiry)) {
            if(at==0) TPP_Send(volume,entry,sl,tp,tpp_type,expiry);
            else { tpp_volume=volume;tpp_entry=entry;tpp_sl=sl;tpp_tp=tp;tpp_expiry=expiry;tpp_scheduled_type=tpp_type;tpp_at=at;TPP_Result("Scheduled for "+TimeToString(at,TIME_DATE|TIME_MINUTES)+" broker time. Keep this chart and terminal running; closing cancels this plan."); }
         }
      }
   }
   TPP_Render();ChartRedraw();return true;
}
void TPP_Deinit()
{
   if(tpp_at>0) { tpp_at=0;Print("TradePilot pending order: scheduled placement cancelled because this chart closed or restarted. No order sent."); }
   ObjectsDeleteAll(0,"TPP_");
}

void TPP_ObserveExecution()
{
 if(tpp_ticket==0)return;
 string note="";
#ifdef __MQL5__
 if(OrderSelect(tpp_ticket)) {
  if((ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE)==ORDER_STATE_PARTIAL)note="Partially filled #"+(string)tpp_ticket+"; filled volume is in its daily basket.";
  else note="Pending #"+(string)tpp_ticket+"; waiting for broker entry price.";
 } else if(HistoryOrderSelect(tpp_ticket)) {
  ENUM_ORDER_STATE state=(ENUM_ORDER_STATE)HistoryOrderGetInteger(tpp_ticket,ORDER_STATE);
  if(state==ORDER_STATE_FILLED)note="Executed #"+(string)tpp_ticket+"; included in its entry-day basket and System execution history.";
  else if(state==ORDER_STATE_CANCELED)note="Broker cancelled pending #"+(string)tpp_ticket+"; check history for any partial fills.";
  else if(state==ORDER_STATE_EXPIRED)note="Broker expired pending #"+(string)tpp_ticket+"; check history for any partial fills.";
  else if(state==ORDER_STATE_REJECTED)note="Broker rejected pending #"+(string)tpp_ticket+".";
 }
#else
 if(OrderSelect((int)tpp_ticket,SELECT_BY_TICKET)) {
  if(OrderType()==OP_BUY||OrderType()==OP_SELL)note="Executed #"+(string)tpp_ticket+"; included in its entry-day basket and System execution history.";
  else if(OrderCloseTime()>0)note="Pending #"+(string)tpp_ticket+" ended without a market fill; see broker history.";
  else note="Pending #"+(string)tpp_ticket+"; waiting for broker entry price.";
 }
#endif
 if(note!="" && note!=tpp_note) {tpp_note=note;Print("TradePilot pending status: ",note);}
}
