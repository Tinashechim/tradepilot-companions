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
 // Resolve original entry from complete history, including positions closed today.
 if(!HistorySelect(0,TPDL_Now()))return false;
 int expected=HistoryDealsTotal()+PositionsTotal();if(expected>1000000)return false;
 int capacity=16;while(capacity<expected*2+1)capacity*=2;
 ulong ids[];bool used[];datetime born[];double realised[],open_result[];
 if(ArrayResize(ids,capacity)<0||ArrayResize(used,capacity)<0||ArrayResize(born,capacity)<0||ArrayResize(realised,capacity)<0||ArrayResize(open_result,capacity)<0)return false;
 ArrayInitialize(used,false);ArrayInitialize(born,0);ArrayInitialize(realised,0);ArrayInitialize(open_result,0);
 for(int i=0;i<HistoryDealsTotal();i++){
  ulong ticket=HistoryDealGetTicket(i);if(ticket==0)return false;
  long type=HistoryDealGetInteger(ticket,DEAL_TYPE);if(type!=DEAL_TYPE_BUY&&type!=DEAL_TYPE_SELL)continue;
  ulong id=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);if(id==0)return false;
  int slot=TP_BasketSlot(id,ids,used);if(slot<0)return false;
  datetime stamp=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
  long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
  if((entry==DEAL_ENTRY_IN||entry==DEAL_ENTRY_INOUT)&&(born[slot]==0||stamp<born[slot]))born[slot]=stamp;
  double value=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_COMMISSION)+HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_FEE);
  if(!MathIsValidNumber(value))return false;
  if(stamp>=period)realised[slot]+=value;
 }
 for(int i=0;i<PositionsTotal();i++){
  if(PositionGetTicket(i)==0)return false;
  int slot=TP_BasketSlot((ulong)PositionGetInteger(POSITION_IDENTIFIER),ids,used);if(slot<0)return false;
  datetime stamp=(datetime)PositionGetInteger(POSITION_TIME);if(born[slot]==0||stamp<born[slot])born[slot]=stamp;
  double value=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);if(!MathIsValidNumber(value))return false;open_result[slot]+=value;
 }
 for(int i=0;i<capacity;i++)if(used[i]&&born[i]>0&&GetSessionStartForTime(born[i])==period){closed+=realised[i];floating+=open_result[i];}
#else
 if(!TP_HistoryReady()) return false;
 for(int i=0;i<OrdersHistoryTotal();i++) {
  if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) return false;
  if((OrderType()!=OP_BUY && OrderType()!=OP_SELL) || OrderCloseTime()<period || GetSessionStartForTime(OrderOpenTime())!=period) continue;
  double net=OrderProfit()+OrderCommission()+OrderSwap();if(!MathIsValidNumber(net)) return false;
  closed+=net;if(GetSessionStartForTime(OrderOpenTime())==period && TP_DailyInclude(period,net)) adjusted+=net;
 }
 for(int i=0;i<OrdersTotal();i++) {
  if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) return false;
  if((OrderType()!=OP_BUY && OrderType()!=OP_SELL) || GetSessionStartForTime(OrderOpenTime())!=period) continue;
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
 double cash=TPDL_Cash();
 if(TPDA_Flag(GetSessionStartForTime(TPDL_Now()),"LIMIT_MODEL")){
  double wins=0,losses=0;verified=verified && TPDA_Closed(GetSessionStartForTime(TPDL_Now()),wins,losses);
  net-=wins+losses;net+=(TPDA_Flag(GetSessionStartForTime(TPDL_Now()),"LIMIT_WINS")?wins:0)+(TPDA_Flag(GetSessionStartForTime(TPDL_Now()),"LIMIT_LOSSES")?losses:0);
 }
 remaining=cash>0 ? MathMax(0,cash+net) : -1;
 string key=TPDL_DayKey("COHORT_HIT");blocked=GlobalVariableCheck(key) && GlobalVariableGet(key)>0;
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
 bool active=TPDL_EntryAllowed(reason);
 ObjectSetInteger(0,"TradePilot_DAILY_STATUS_VALUE",OBJPROP_COLOR,active?C'90,220,140':C'255,100,100');
 if(!active) {
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
 if(blocked) {reason="Daily loss limit reached. Review Current Basket and your saved daily limit, or wait for renewal at 23:30 broker time. Existing positions remain open.";return false;}
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
 if(ObjectFind(0,"TradePilot_LIMIT_EDIT")<0) CreateEdit("TradePilot_LIMIT_EDIT",TPDL_Limit()>0?DoubleToString(TPDL_Limit(),2):"",ValueX(),y+S(284),S(72));
#else
 if(ObjectFind(0,"TradePilot_LIMIT_EDIT")<0) CreateEdit("TradePilot_LIMIT_EDIT",TPDL_Limit()>0?DoubleToString(TPDL_Limit(),2):"",ValueX(),y+S(284),S(72),S(19));
#endif
 ObjectSetInteger(0,"TradePilot_LIMIT_EDIT",OBJPROP_YDISTANCE,y+S(284));
 ObjectSetInteger(0,"TradePilot_LIMIT_EDIT",OBJPROP_XDISTANCE,ValueX());
 ObjectSetInteger(0,"TradePilot_LIMIT_EDIT",OBJPROP_XSIZE,S(130));
 ObjectSetInteger(0,"TradePilot_LIMIT_EDIT",OBJPROP_YSIZE,S(24));
 CreateLabel("TradePilot_LIMIT_TITLE","DAILY LOSS LIMIT",LabelX(),y+S(243),FontSize(BASE_FONT_SECTION),C'90,180,255');
 CreateLabel("TradePilot_LIMIT_MODE_LABEL","Limit mode",LabelX(),y+S(264),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 CreateButton("TradePilot_LIMIT_MODE",tpdl_edit_percent?"PERCENTAGE":"CASH",ValueX(),y+S(260),S(130),S(19),C'55,60,70');
 CreateLabel("TradePilot_LIMIT_LABEL","Loss limit",LabelX(),y+S(290),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 CreateButton("TradePilot_LIMIT_UPDATE","UPDATE",(LabelX()+ValueX()+S(130)-S(88))/2,y+S(425),S(88),S(19),C'55,60,70');
 ObjectSetString(0,"TradePilot_LIMIT_UPDATE",OBJPROP_TOOLTIP,"Review Apply wins and Apply losses, then save the daily loss limit and these choices. Your daily target is saved using Update under Daily Performance.");
 double net=0,remaining=0;bool blocked=false;bool verified=TPDL_State(net,remaining,blocked);
 CreateLabel("TradePilot_LIMIT_REMAIN_LABEL","Budget left",LabelX(),y+S(314),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 string currency=
#ifdef __MQL5__
 AccountInfoString(ACCOUNT_CURRENCY);
#else
 AccountCurrency();
#endif
 // Show the signed allowance while keeping the risk-cap calculation clamped at zero.
 double displayed_budget=TPDL_Cash()+net;
 double pwins=0,plosses=0;if(TPDA_Closed(period,pwins,plosses)){
  if(TPDA_Flag(period,"LIMIT_MODEL"))net-= (TPDA_Flag(period,"LIMIT_WINS")?pwins:0)+(TPDA_Flag(period,"LIMIT_LOSSES")?plosses:0);
  else net-=pwins+plosses;
  string draft_text=ObjectGetString(0,"TradePilot_LIMIT_EDIT",OBJPROP_TEXT);double draft_limit=StringToDouble(draft_text);if(MathIsValidNumber(draft_limit) && draft_limit>=0 && (!tpdl_edit_percent || draft_limit<=100))displayed_budget=(tpdl_edit_percent?GetSessionStartBalance(period)*draft_limit/100:draft_limit)+net+(tp_limit_wins?pwins:0)+(tp_limit_losses?plosses:0);
 }
 color budget_color=!verified?C'190,195,205':displayed_budget<0?clrRed:displayed_budget>0?C'90,220,140':clrWhite;
 CreateValue("TradePilot_LIMIT_REMAIN",TPDL_Limit()<=0?"No daily limit":!verified?"Not verified":(tpdl_edit_percent && GetSessionStartBalance(period)>0 ? DoubleToString(displayed_budget/GetSessionStartBalance(period)*100,2)+"%" : currency+" "+DoubleToString(displayed_budget,2)),y+S(314),budget_color);
 ObjectSetInteger(0,"TradePilot_LIMIT_REMAIN",OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
 ObjectSetInteger(0,"TradePilot_LIMIT_REMAIN",OBJPROP_XDISTANCE,ValueX());
 TPDR_BudgetEquivalents(GetSessionStartForTime(TPDL_Now()),displayed_budget,verified,TPDL_Limit()>0,currency,tpdl_edit_percent);
 ObjectSetString(0,"TradePilot_LIMIT_EDIT",OBJPROP_TOOLTIP,"Optional daily loss limit. Leave blank for no daily entry limit. Percentage uses the broker-period starting balance; cash uses account currency. Renews at 23:30 broker time. Counts only trades entered in the current broker period, including their floating results and net charges. Older baskets are excluded.");
 ObjectSetString(0,"TradePilot_LIMIT_MODE",OBJPROP_TOOLTIP,"Choose Percentage or Cash, then press Update under Daily Performance to save. Editing alone does not change the active limit.");
 string reason="";if(!TPDL_EntryAllowed(reason)) {
  ObjectSetString(0,"TradePilot_BUY_BUTTON",OBJPROP_TOOLTIP,reason);ObjectSetString(0,"TradePilot_SELL_BUTTON",OBJPROP_TOOLTIP,reason);
 }
}
void TPDL_ClosedSummary()
{
 double closed=0,floating=0,adjusted=0;bool ready=TPDL_Totals(closed,floating,adjusted);
 datetime period=GetSessionStartForTime(TPDL_Now());double balance=GetSessionStartBalance(period);
#ifdef __MQL5__
 string currency=AccountInfoString(ACCOUNT_CURRENCY),key="TradePilot_DAILY_CLOSED_VALUE";
 string old[]={"TradePilot_DAILY_PERCENT_LABEL","TradePilot_DAILY_PERCENT_VALUE","TradePilot_DAILY_PERCENT_UNIT"};
 string remaining_label="TradePilot_REMAINING_LABEL",remaining_value="TradePilot_REMAINING_VALUE";
#else
 string currency=AccountCurrency(),key="TradePilot_CLOSED_PL_VALUE";
 string old[]={"TradePilot_CLOSED_PERCENT_LABEL","TradePilot_CLOSED_PERCENT_VALUE"};
 string remaining_label="TradePilot_DAILY_REMAINING_LABEL",remaining_value="TradePilot_DAILY_REMAINING_VALUE";
#endif
 ObjectSetInteger(0,key,OBJPROP_YDISTANCE,PanelY()+S(333));
 ObjectSetInteger(0,"TradePilot_CLOSED_PL_LABEL",OBJPROP_YDISTANCE,PanelY()+S(333));
 string cash=currency+" "+DoubleToString(closed,2),percent=balance>0?DoubleToString(closed/balance*100,2)+"%":"Percentage pending";
 string value=!ready?"Verification pending":tpdl_edit_percent?percent+" ("+cash+")":cash+" ("+percent+")";
 ObjectSetString(0,key,OBJPROP_TEXT,value);ObjectSetInteger(0,key,OBJPROP_FONTSIZE,TP_HeaderFont(value,FontSize(BASE_FONT_NORMAL),S(132),S(15)));
 ObjectSetString(0,key,OBJPROP_TOOLTIP,"This broker day's realised net result in your chosen loss-limit mode, with the other equivalent in brackets. Floating results remain separate. Percentage uses the day's starting balance. "+value);
 for(int i=0;i<ArraySize(old);i++)ObjectDelete(0,old[i]);
 ObjectDelete(0,"TradePilot_DAILY_CURRENCY");
 ObjectDelete(0,"TradePilot_REMAINING_UNIT");
 // Display follows the saved loss-limit choice; target money stays independent.
 double target_left=MathMax(0,GetSessionTargetMoney(period)-adjusted);
 string remaining_cash=currency+" "+DoubleToString(target_left,2);
 string remaining_percent=balance>0?DoubleToString(target_left/balance*100,2)+"%":"Percentage pending";
 string remaining_text=!ready?"Verification pending":tpdl_edit_percent?remaining_percent+" ("+remaining_cash+")":remaining_cash+" ("+remaining_percent+")";
 ObjectSetString(0,remaining_value,OBJPROP_TEXT,remaining_text);
 ObjectSetInteger(0,remaining_value,OBJPROP_FONTSIZE,TP_HeaderFont(remaining_text,FontSize(BASE_FONT_NORMAL),S(132),S(15)));
 ObjectSetString(0,remaining_value,OBJPROP_TOOLTIP,"Amount still needed to reach the saved daily target, after the wins and losses you chose to apply. Shown in this section's Cash or Percentage mode; brackets show the other equivalent. Changing the loss-limit mode does not change the saved target.");
 ObjectSetInteger(0,remaining_label,OBJPROP_YDISTANCE,PanelY()+S(352));ObjectSetInteger(0,remaining_value,OBJPROP_YDISTANCE,PanelY()+S(352));
 ObjectSetInteger(0,"TradePilot_DAILY_STATUS_LABEL",OBJPROP_YDISTANCE,PanelY()+S(371));ObjectSetInteger(0,"TradePilot_DAILY_STATUS_VALUE",OBJPROP_YDISTANCE,PanelY()+S(371));
}
bool TPDL_ReadPending(double &value)
{
 string text=ObjectGetString(0,"TradePilot_LIMIT_EDIT",OBJPROP_TEXT);StringTrimLeft(text);StringTrimRight(text);
 value=0;
 if(text!="") {
  bool dot=false;for(int i=0;i<StringLen(text);i++) {ushort c=StringGetCharacter(text,i);if(c==46 && !dot) {dot=true;continue;}if(c<48||c>57) {Alert("Enter a positive daily limit number or leave the field blank for none.");return false;}}
  value=StringToDouble(text);if(!MathIsValidNumber(value)||value<=0||(tpdl_edit_percent&&value>100)) {Alert("Use a positive cash limit or percentage up to 100. Leave blank for no daily limit.");return false;}
 }
 return true;
}
bool TPDL_SavePending(bool removal_confirmed=false)
{
 double value=0;if(!TPDL_ReadPending(value))return false;
 double before=TPDL_Limit();bool before_percent=TPDL_Percent();
 if(!removal_confirmed && before>0 && value==0 && MessageBox("Removing the daily loss limit allows new entries without this overtrading guard. Continue?","Remove daily limit?",MB_YESNO|MB_ICONWARNING)!=IDYES) return false;
 if(before==value && before_percent==tpdl_edit_percent) return true;
 if(!TPDL_Audit(before,before_percent,value,tpdl_edit_percent)) {Alert("Daily limit unchanged: its audit record could not be saved. Check the terminal file error in Experts.");return false;}
 GlobalVariableSet(TPDL_Key("LIMIT"),value);GlobalVariableSet(TPDL_Key("PERCENT"),tpdl_edit_percent?1:0);GlobalVariableDel(TPDL_DayKey("COHORT_HIT"));GlobalVariablesFlush();
 TPDL_Render();return true;
}
bool TPDL_Event(string name)
{
 if(name=="TradePilot_LIMIT_UPDATE"){
  ObjectSetInteger(0,name,OBJPROP_STATE,false);
  double proposed_value=0;if(!TPDL_ReadPending(proposed_value))return true;
  datetime preview_period=GetSessionStartForTime(TPDL_Now());
  double balance=GetSessionStartBalance(preview_period),risk=TPDR_SavedRisk(preview_period);
  if(tpdl_edit_percent && proposed_value>0 && balance<=0){Alert("Wait for a verified starting balance before reviewing a percentage loss limit.");return true;}
  double proposed_cash=tpdl_edit_percent?balance*proposed_value/100:proposed_value;
  double wins=0,losses=0;if(!TPDA_Closed(preview_period,wins,losses)){Alert("Wait for verified Current Basket results before applying wins or losses.");return true;}
  proposed_cash=TPDA_Adjust(proposed_cash,wins,losses,tp_limit_wins,tp_limit_losses,false);
  double current_cash=TPDL_Cash();if(TPDA_Flag(preview_period,"LIMIT_MODEL"))current_cash=TPDA_Adjust(current_cash,wins,losses,TPDA_Flag(preview_period,"LIMIT_WINS"),TPDA_Flag(preview_period,"LIMIT_LOSSES"),false);
  double delta=proposed_cash-current_cash,amount=MathAbs(delta);
  string cash=AccountCurrency()+" "+DoubleToString(amount,2);
  string percentage=balance>0?DoubleToString(amount/balance*100,2)+"%":"Percentage pending";
  string ratio=risk>0?DoubleToString(amount/risk,2)+"R":"Ratio pending";
  string equivalents=tpdl_edit_percent?percentage+" ("+cash+"; "+ratio+")":cash+" ("+percentage+"; "+ratio+")";
  string change=MathAbs(delta)<0.00000001?"Daily loss limit unchanged":(delta>0?"Increase by ":"Decrease by ")+equivalents;
  TPC_Close();tpdc_loss=true;tpdc_loss_change=change;tpdc_loss_unlimited=proposed_value==0;
  tpdc_open=true;tpdc_period=preview_period;tpdc_signature=TPDC_InputSignature();
  TPDC_Render();ChartRedraw();return true;
 }
 if(name!="TradePilot_LIMIT_MODE")return false;
 double entered=0;if(!TPDL_ReadPending(entered)){ObjectSetInteger(0,name,OBJPROP_STATE,false);return true;}
 datetime period=GetSessionStartForTime(TPDL_Now());EnsureSessionState(period);
 double converted=entered==0?0:TPDM_Convert(entered,tpdl_edit_percent?1:0,tpdl_edit_percent?0:1,GetSessionStartBalance(period),0);
 if(converted<0 || (!tpdl_edit_percent && converted>100)) {
  ObjectSetInteger(0,name,OBJPROP_STATE,false);Alert("Mode unchanged. Wait for a verified daily starting balance; a percentage loss limit cannot exceed 100%.");return true;
 }
 TPDC_Close();tpdl_edit_percent=!tpdl_edit_percent;
 string converted_text=DoubleToString(converted,8);
 while(StringLen(converted_text)>0 && StringSubstr(converted_text,StringLen(converted_text)-1)=="0")converted_text=StringSubstr(converted_text,0,StringLen(converted_text)-1);
 if(StringSubstr(converted_text,StringLen(converted_text)-1)==".")converted_text+="00";
 ObjectSetString(0,"TradePilot_LIMIT_EDIT",OBJPROP_TEXT,entered==0?"":converted_text);
 ObjectSetInteger(0,name,OBJPROP_STATE,false);UpdatePanel();return true;
}

bool tpdl_notice_open=false;
string tpdl_notice_reason="";
void TPDL_NoticeRender()
{
 if(!tpdl_notice_open)return;
 int x=PanelX()+PanelWidth()+S(24),y=PanelY()+S(55),w=S(300);
 CreateRectangle("TradePilot_LIMIT_NOTICE_BG",x,y,w,S(168),C'25,30,40',C'85,95,110');
 CreateLabel("TradePilot_LIMIT_NOTICE_TITLE","Daily loss limit reached",x+S(12),y+S(12),FontSize(BASE_FONT_NORMAL),C'255,100,100');
 string lines[]={"This trade was not sent.","Review Daily Loss Limit and Current Basket.","Wait for renewal at 23:30 broker time.","Carried-over trades stay in older baskets."};
 for(int i=0;i<4;i++)CreateLabel("TradePilot_LIMIT_NOTICE_LINE"+IntegerToString(i),lines[i],x+S(12),y+S(38+i*20),TP_HeaderFont(lines[i],FontSize(BASE_FONT_NORMAL),S(276),S(16)),clrWhite);
 ObjectSetString(0,"TradePilot_LIMIT_NOTICE_TITLE",OBJPROP_TOOLTIP,tpdl_notice_reason);
 CreateButton("TradePilot_LIMIT_NOTICE_CLOSE","OK",x+S(12),y+S(132),S(90),S(22),C'55,60,70');
 ObjectSetInteger(0,"TradePilot_LIMIT_NOTICE_CLOSE",OBJPROP_ZORDER,100);
 ObjectSetString(0,"TradePilot_LIMIT_NOTICE_CLOSE",OBJPROP_TOOLTIP,"Dismiss this notice. No order is sent and no daily settings are changed.");
}
void TPDL_Notify(string reason)
{
 double net=0,remaining=0;bool blocked=false;
 if(!TPDL_State(net,remaining,blocked)||!blocked){Alert(reason);return;}
 TP_SpreadTradeClose();TPC_Close();TPDC_Close();
 tpdl_notice_reason=reason;tpdl_notice_open=true;TPDL_NoticeRender();ChartRedraw();
}
bool TPDL_NoticeEvent(string name)
{
 if(!tpdl_notice_open)return false;
 if(name=="TradePilot_LIMIT_NOTICE_CLOSE"){tpdl_notice_open=false;ObjectsDeleteAll(0,"TradePilot_LIMIT_NOTICE_");ChartRedraw();}
 return true;
}
#endif

// One verified budget snapshot per sizing request. Pending history is not a reached limit.
double TPDL_SizingRisk(double requested,string &reason)
{
 reason="";
 if(TPDL_Limit()<=0)return requested;
 if(!MathIsValidNumber(TPDL_Cash())||TPDL_Cash()<=0){reason="The daily starting balance is not available. Wait for a verified broker balance, then calculate again.";return 0;}
 double net=0,remaining=0;bool blocked=false;
 if(!TPDL_State(net,remaining,blocked)){reason="The daily budget needs verified broker history. Keep the terminal connected while history finishes loading, then calculate again.";return 0;}
 if(blocked||remaining<=0){reason="Daily loss limit reached. Review Current Basket and the saved limit, or wait for renewal at 23:30 broker time. Existing positions remain open.";return 0;}
 return MathMin(requested,remaining);
}
