#ifndef TRADEPILOT_DAILY_RISK
#define TRADEPILOT_DAILY_RISK
// Account-wide entry guard. Never closes positions or cancels broker orders.
datetime TPDL_Now() { return TP_LocalBridge && tp_prefix!="" && tp_clock_ready ? TP_ServerNow() : TimeCurrent(); }
#ifdef __MQL5__
bool TPDL_GroupAdd(ulong &ids[],double &amounts[],bool &used[],ulong id,double amount)
{
 int size=ArraySize(ids);uint hash=(uint)(id^(id>>32));hash^=hash>>16;hash*=0x7feb352d;hash^=hash>>15;hash*=0x846ca68b;hash^=hash>>16;
 int slot=(int)(hash%(uint)size);
 for(int checked=0;checked<size;checked++) {
  if(!used[slot]) {used[slot]=true;ids[slot]=id;amounts[slot]=amount;return true;}
  if(ids[slot]==id) {amounts[slot]+=amount;return true;}
  slot=(slot+1)%size;
 }
 return false;
}
#endif
string TPDL_Prefix() { return "TPDL_"+TP_Login()+"_"; }
string TPDL_Key(string name) { return TPDL_Prefix()+name; }
string TPDL_DayKey(string name) { return TPDL_Prefix()+IntegerToString((int)GetSessionStartForTime(TPDL_Now()))+"_"+name; }
double TPDL_Value(string name,double fallback=0) { string key=TPDL_Key(name);return GlobalVariableCheck(key) ? GlobalVariableGet(key) : fallback; }
double TPDL_Limit() { return TPDL_Value("LIMIT"); }
bool TPDL_Percent() { return TPDL_Value("PERCENT")>0; }
double TPDL_Cash() { double value=TPDL_Limit();return TPDL_Percent() ? GetSessionStartBalance(GetSessionStartForTime(TPDL_Now()))*value/100.0 : value; }
bool TPDL_Totals(double &closed,double &floating,double &adjusted)
{
 closed=0;floating=0;adjusted=0;
 datetime period=GetSessionStartForTime(TPDL_Now());
 #ifdef __MQL5__
 if(!HistorySelect(period,TPDL_Now())) return false;

 for(int i=0;i<HistoryDealsTotal();i++) {
  ulong ticket=HistoryDealGetTicket(i);if(ticket==0) return false;
  long type=HistoryDealGetInteger(ticket,DEAL_TYPE);
  if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL && type!=DEAL_TYPE_COMMISSION && type!=DEAL_TYPE_COMMISSION_DAILY && type!=DEAL_TYPE_COMMISSION_MONTHLY && type!=DEAL_TYPE_COMMISSION_AGENT_DAILY && type!=DEAL_TYPE_COMMISSION_AGENT_MONTHLY) continue;
  double net=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_COMMISSION)+HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_FEE);
  if(!MathIsValidNumber(net)) return false;
  closed+=net;
 }
 for(int i=0;i<PositionsTotal();i++) {
  if(PositionGetTicket(i)==0) return false;
  double net=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
  if(!MathIsValidNumber(net)) return false;
  floating+=net;
 }
#else
 if(!TP_HistoryReady()) return false;
 for(int i=0;i<OrdersHistoryTotal();i++) {
  if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) return false;
  if((OrderType()!=OP_BUY && OrderType()!=OP_SELL) || OrderCloseTime()<period) continue;
  double net=OrderProfit()+OrderCommission()+OrderSwap();if(!MathIsValidNumber(net)) return false;
  closed+=net;if(GetSessionStartForTime(OrderOpenTime())==period && TP_DailyInclude(period,net)) adjusted+=net;
 }
 for(int i=0;i<OrdersTotal();i++) {
  if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) return false;
  if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
  double net=OrderProfit()+OrderCommission()+OrderSwap();if(!MathIsValidNumber(net)) return false;
  floating+=net;if(GetSessionStartForTime(OrderOpenTime())==period && TP_DailyInclude(period,net)) adjusted+=net;
 }
#endif
 double basket_actual=0;
 if(!TP_BasketResults(period,basket_actual,adjusted))return false;
 return MathIsValidNumber(closed) && MathIsValidNumber(floating) && MathIsValidNumber(adjusted);
}
bool TPDL_State(double &net,double &remaining,bool &blocked)
{
 double closed=0,floating=0,adjusted=0;bool verified=TPDL_Totals(closed,floating,adjusted);net=closed+floating;
 double cash=TPDL_Cash();remaining=cash>0 ? MathMax(0,cash+net) : -1;
 string key=TPDL_DayKey("HIT");blocked=GlobalVariableCheck(key) && GlobalVariableGet(key)>0;
 if(cash>0 && verified && net<=-cash) {GlobalVariableSet(key,1);blocked=true;}
 if(cash<=0) blocked=false;
 return verified;
}
double TPDL_CapRisk(double requested)
{
 if(TPDL_Limit()<=0) return requested;
 double net=0,remaining=0;bool blocked=false;
 if(!TPDL_State(net,remaining,blocked) || blocked) return 0;
 return MathMin(requested,remaining);
}
bool TPDL_AcceptRisk(double planned,string &reason)
{
 if(TPDL_Limit()<=0) return true;
 if(!TPDL_EntryAllowed(reason)) return false;
 if(!MathIsValidNumber(planned) || planned<=0) {reason="The order's stop-loss risk is not verified for the active daily limit.";return false;}
 if(planned>TPDL_CapRisk(planned)+0.00000001) {reason="The order exceeds the remaining daily loss budget. Reduce its volume or review the daily limit.";return false;}
 return true;
}
void TPDL_FinalStatus()
{
 string reason="";
 if(!TPDL_EntryAllowed(reason)) {
  ObjectSetString(0,"TradePilot_DAILY_STATUS_VALUE",OBJPROP_TEXT,TPDL_Limit()>0 ? "DAILY LIMIT PAUSED" : "ENTRY CHECK PENDING");
  ObjectSetString(0,"TradePilot_DAILY_STATUS_VALUE",OBJPROP_TOOLTIP,reason);
  ObjectSetInteger(0,"TradePilot_DAILY_STATUS_VALUE",OBJPROP_COLOR,clrRed);
 }
 ObjectSetString(0,"TradePilot_BUY_BUTTON",OBJPROP_TOOLTIP,reason!="" ? reason : "Place a Buy using the verified stop-loss, lot size, available margin and daily budget. Broker permission remains required.");
 ObjectSetString(0,"TradePilot_SELL_BUTTON",OBJPROP_TOOLTIP,reason!="" ? reason : "Place a Sell using the verified stop-loss, lot size, available margin and daily budget. Broker permission remains required.");
}
bool TPDL_EntryAllowed(string &reason)
{
 if(TPDL_Limit()<=0) return true;
 if(!MathIsValidNumber(TPDL_Cash()) || TPDL_Cash()<=0) {reason="Daily loss limit starting balance is not available. Wait for a verified broker balance.";return false;}
 double net=0,remaining=0;bool blocked=false;
 if(!TPDL_State(net,remaining,blocked)) {reason="Daily loss budget not verified. Wait for complete broker history; existing positions remain open.";return false;}
 if(blocked) {reason="Daily loss limit reached. Change the daily limit or wait for the next broker period (23:30). Existing positions remain open.";return false;}
 return true;
}
void TPDL_Publish()
{
 // One authenticated owner publishes account-wide results; other chart inputs may be old.
 if(!TP_LocalBridge || !tp_owner || tp_prefix=="") return;
 double net=0,remaining=0,closed=0,floating=0,adjusted=0;bool blocked=false;
 bool verified=TPDL_State(net,remaining,blocked);if(verified) verified=TPDL_Totals(closed,floating,adjusted);
#ifdef __MQL5__
 string platform="MT5",currency=AccountInfoString(ACCOUNT_CURRENCY);
#else
 string platform="MT4",currency=AccountCurrency();
#endif
 datetime period=GetSessionStartForTime(TPDL_Now());double target=GetSessionTargetMoney(period);
 string text="DAILY\t"+TP_BridgeToken+"\t"+TP_AccountId+"\t"+TP_Login()+"\t"+TP_Server()+"\t"+platform+"\t"+TP_Int(TimeGMT())+"\t"+TimeToString(TPDL_Now(),TIME_DATE|TIME_SECONDS)+"\t"+TimeToString(period,TIME_DATE|TIME_SECONDS)+"\t"+currency+"\t"+(TPDL_Percent()?"Percentage":"Cash")+"\t"+TP_Num(TPDL_Limit())+"\t"+TP_Num(TPDL_Cash())+"\t"+TP_Num(net)+"\t"+TP_Num(remaining)+"\t"+(blocked?"1":"0")+"\t"+(verified?"1":"0")+"\t"+TP_Num(TPDL_Value("REV"))+"\t"+TP_Num(target)+"\t"+TP_Num(adjusted)+"\t"+(verified && adjusted>=target && target>0?"1":"0")+"\r\n";
 TP_Atomic(".daily.tsv",text);
}
bool TPDL_Audit(double old_value,bool old_percent,double value,bool percent)
{
 double revision=TPDL_Value("REV")+1;GlobalVariableSet(TPDL_Key("REV"),revision);
 string path=TP_Path(".daily-edits.tsv");
 int h=FileOpen(path,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
 if(h==INVALID_HANDLE) {Print("TradePilot daily limit audit file error ",GetLastError());return false;}
 FileSeek(h,0,SEEK_END);
 FileWriteString(h,"EDIT\t"+TP_BridgeToken+"\t"+TP_AccountId+"\t"+TP_Num(revision)+"\t"+TimeToString(TPDL_Now(),TIME_DATE|TIME_SECONDS)+"\t"+(old_percent?"Percentage":"Cash")+"\t"+TP_Num(old_value)+"\t"+(percent?"Percentage":"Cash")+"\t"+TP_Num(value)+"\r\n");FileClose(h);return true;
}
bool tpdl_edit_percent=false;
datetime tpdl_ui_period=0;
void TPDL_Render()
{
 datetime period=GetSessionStartForTime(TPDL_Now());
 if(tpdl_ui_period!=period) {tpdl_ui_period=period;tpdl_edit_percent=TPDL_Percent();}
 int y=PanelY();
#ifdef __MQL5__
 if(ObjectFind(0,"TradePilot_LIMIT_EDIT")<0) CreateEdit("TradePilot_LIMIT_EDIT",TPDL_Limit()>0?DoubleToString(TPDL_Limit(),2):"",ValueX(),y+S(235),S(72));
#else
 if(ObjectFind(0,"TradePilot_LIMIT_EDIT")<0) CreateEdit("TradePilot_LIMIT_EDIT",TPDL_Limit()>0?DoubleToString(TPDL_Limit(),2):"",ValueX(),y+S(235),S(72),S(19));
#endif
 CreateLabel("TradePilot_LIMIT_TITLE","LOSS PROTECTION",LabelX(),y+S(199),FontSize(BASE_FONT_SECTION),C'90,180,255');
 CreateLabel("TradePilot_LIMIT_MODE_LABEL","Limit mode",LabelX(),y+S(218),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 CreateButton("TradePilot_LIMIT_MODE",tpdl_edit_percent?"Percentage":"Cash",ValueX(),y+S(214),S(130),S(19),C'55,60,70');
 CreateLabel("TradePilot_LIMIT_LABEL","Loss limit",LabelX(),y+S(239),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 ObjectDelete(0,"TradePilot_LIMIT_UPDATE");
 double net=0,remaining=0;bool blocked=false;bool verified=TPDL_State(net,remaining,blocked);
 CreateLabel("TradePilot_LIMIT_REMAIN_LABEL","Budget left",LabelX(),y+S(260),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 string currency=
#ifdef __MQL5__
 AccountInfoString(ACCOUNT_CURRENCY);
#else
 AccountCurrency();
#endif
 CreateValue("TradePilot_LIMIT_REMAIN",TPDL_Limit()<=0?"No daily limit":!verified?"Not verified":blocked?"Limit reached":"("+currency+" "+DoubleToString(remaining,2)+")",y+S(260),blocked||!verified?clrRed:clrWhite);
 ObjectSetString(0,"TradePilot_LIMIT_EDIT",OBJPROP_TOOLTIP,"Optional daily loss limit. Leave blank for no daily entry limit. Percentage uses the broker-period starting balance; cash uses account currency. Includes all open floating results and net closed results since 23:30.");
 ObjectSetString(0,"TradePilot_LIMIT_MODE",OBJPROP_TOOLTIP,"Choose Percentage or Cash, then press the shared Update button to save. Editing alone does not change the active limit.");
 string reason="";if(!TPDL_EntryAllowed(reason)) {
  ObjectSetString(0,"TradePilot_BUY_BUTTON",OBJPROP_TOOLTIP,reason);ObjectSetString(0,"TradePilot_SELL_BUTTON",OBJPROP_TOOLTIP,reason);
 }
}
bool TPDL_SavePending(bool removal_confirmed=false)
{
 string text=ObjectGetString(0,"TradePilot_LIMIT_EDIT",OBJPROP_TEXT);StringTrimLeft(text);StringTrimRight(text);
 double value=0;
 if(text!="") {
  bool dot=false;for(int i=0;i<StringLen(text);i++) {ushort c=StringGetCharacter(text,i);if(c==46 && !dot) {dot=true;continue;}if(c<48||c>57) {Alert("Enter a positive daily limit number or leave the field blank for none.");return false;}}
  value=StringToDouble(text);if(!MathIsValidNumber(value)||value<=0||(tpdl_edit_percent&&value>100)) {Alert("Use a positive cash limit or percentage up to 100. Leave blank for no daily limit.");return false;}
 }
 double before=TPDL_Limit();bool before_percent=TPDL_Percent();
 if(!removal_confirmed && before>0 && value==0 && MessageBox("Removing the daily loss limit allows new entries without this overtrading guard. Continue?","Remove daily limit?",MB_YESNO|MB_ICONWARNING)!=IDYES) return false;
 if(before==value && before_percent==tpdl_edit_percent) return true;
 if(!TPDL_Audit(before,before_percent,value,tpdl_edit_percent)) {Alert("Daily limit unchanged: its audit record could not be saved. Check the terminal file error in Experts.");return false;}
 GlobalVariableSet(TPDL_Key("LIMIT"),value);GlobalVariableSet(TPDL_Key("PERCENT"),tpdl_edit_percent?1:0);GlobalVariableDel(TPDL_DayKey("HIT"));GlobalVariablesFlush();
 TPDL_Render();return true;
}
bool TPDL_Event(string name)
{
 if(name!="TradePilot_LIMIT_MODE")return false;
 tpdl_edit_percent=!tpdl_edit_percent;ObjectSetInteger(0,name,OBJPROP_STATE,false);TPDL_Render();return true;
}
#endif
