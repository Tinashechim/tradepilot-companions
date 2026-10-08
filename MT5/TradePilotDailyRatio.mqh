#ifndef TRADEPILOT_DAILY_RATIO
#define TRADEPILOT_DAILY_RATIO
bool TPDR_Enabled() {return GlobalVariableCheck(GV_DAILY_MODE+"_RATIO") && GlobalVariableGet(GV_DAILY_MODE+"_RATIO")>0;}
double TPDR_RiskCash() {double risk=GetRiskAmount();return TerminalInfoInteger(TERMINAL_CONNECTED) && MathIsValidNumber(risk) && risk>0 ? risk : 0;}
double TPDR_Number(string text)
{
 StringTrimLeft(text);StringTrimRight(text);int dots=0,digits=0;
 for(int i=0;i<StringLen(text);i++) {ushort c=StringGetCharacter(text,i);if(c==46)dots++;else if(c>=48 && c<=57)digits++;else return -1;}
 double value=StringToDouble(text);return dots<=1 && digits>0 && MathIsValidNumber(value) && value>0 && value<=1e12 ? value : -1;
}
double TPDR_Parse(string text)
{
 if(!TPDR_Enabled()) return TPDR_Number(text);
 string parts[];int count=StringSplit(text,58,parts);double factor=-1;
 if(count==1)factor=TPDR_Number(parts[0]);
 if(count==2) {double risk=TPDR_Number(parts[0]),reward=TPDR_Number(parts[1]);if(risk>0 && reward>0)factor=reward/risk;}
 return MathIsValidNumber(factor) && factor>0 && factor<=1000000 ? factor : -1;
}
void TPDR_Save(datetime period)
{
 GlobalVariableSet(SessionKey(period,"RATIO"),TPDR_Enabled()?1:0);
 if(TPDR_Enabled()) GlobalVariableSet(SessionKey(period,"RATIO_RISK"),TPDR_RiskCash());
}
void TPDR_Init(datetime period)
{
 if(!GlobalVariableCheck(SessionKey(period,"RATIO"))) {
  if(period==GetSessionStartForTime(TPDL_Now())) TPDR_Save(period);
  else GlobalVariableSet(SessionKey(period,"RATIO"),0);
 }
}
bool TPDR_Target(datetime period,double factor,double &target)
{
 TPDR_Init(period);
 if(GlobalVariableGet(SessionKey(period,"RATIO"))<=0) return false;
 if(GlobalVariableGet(SessionKey(period,"RATIO_RISK"))<=0 && TPDR_RiskCash()>0) GlobalVariableSet(SessionKey(period,"RATIO_RISK"),TPDR_RiskCash());
 target=GlobalVariableGet(SessionKey(period,"RATIO_RISK"))*factor;
 if(!MathIsValidNumber(target) || target<=0) target=0;
 return true;
}
void TPDR_Render(datetime period)
{
 bool ratio=TPDR_Enabled();
 string mode=ratio?"Ratio":(GetDailyTargetMode()==DAILY_PERCENTAGE?"Percentage":"Cash");
 string unit=ratio?"R:R":(GetDailyTargetMode()==DAILY_PERCENTAGE?"%":AccountInfoString(ACCOUNT_CURRENCY));
 if(ObjectGetString(0,"TradePilot_DAILY_MODE_BUTTON",OBJPROP_TEXT)!=mode)ObjectSetString(0,"TradePilot_DAILY_MODE_BUTTON",OBJPROP_TEXT,mode);
 if(ObjectGetString(0,"TradePilot_DAILY_TARGET_UNIT",OBJPROP_TEXT)!=unit)ObjectSetString(0,"TradePilot_DAILY_TARGET_UNIT",OBJPROP_TEXT,unit);
 if(!ratio) {ObjectSetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TOOLTIP,"Enter a positive daily target in the selected Percentage or Cash mode. Press Update to save this period's target and review Apply wins / Apply losses.");return;}

 ObjectSetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TOOLTIP,"Daily risk-to-reward target. Enter 2 or 1:2 for a target twice the position-sizer risk. Update saves that cash risk for this broker period; later balance/risk changes do not silently change the saved target.");
 if(GlobalVariableGet(SessionKey(period,"RATIO_RISK"))<=0) {
  ObjectSetString(0,"TradePilot_DAILY_STATUS_VALUE",OBJPROP_TEXT,"TARGET RISK PENDING");
  ObjectSetString(0,"TradePilot_DAILY_STATUS_VALUE",OBJPROP_TOOLTIP,"The Ratio target needs a positive verified account balance and position-sizer risk. Wait for that balance or review the risk input, then Update.");
 }
 ObjectSetString(0,"TradePilot_DAILY_EQUIVALENT",OBJPROP_TOOLTIP,"Risk-to-reward target uses the cash risk saved when this period's target was updated. It is a planning target, not promised performance or an automatic order take-profit.");
}
bool TPDR_Event(string name)
{
 if(name!="TradePilot_DAILY_MODE_BUTTON") return false;
#ifdef __MQL5__
 int mode=TPDR_Enabled()?2:(int)GetDailyTargetMode();
#else
 int mode=TPDR_Enabled()?2:(daily_percentage_mode?1:0);
#endif
 int next=mode==1?0:mode==0?2:1;
 GlobalVariableSet(GV_DAILY_MODE+"_RATIO",next==2?1:0);
 GlobalVariableSet(GV_DAILY_MODE,next==1?1:0);
#ifdef __MQL5__
 if(next==2)GlobalVariableSet(GV_DAILY_TARGET,2);
 double value=GetDailyTargetValue();
#else
 daily_percentage_mode=next==1;
 if(next==2)GlobalVariableSet(GV_DAILY_VALUE,2);
 daily_target_value=GlobalVariableGet(GV_DAILY_VALUE);double value=daily_target_value;
#endif
 datetime period=GetSessionStartForTime(TPDL_Now());EnsureSessionState(period);
 GlobalVariableSet(SessionKey(period,"MODE"),next==1?1:0);GlobalVariableSet(SessionKey(period,"TARGET"),value);TPDR_Save(period);
 ObjectSetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TEXT,DoubleToString(value,2));
 ObjectSetInteger(0,name,OBJPROP_STATE,false);UpdatePanel();return true;
}

string TPDR_RemainingDisplay(datetime period,double remaining,double balance,string currency,bool percent)
{
 double risk=GlobalVariableGet(SessionKey(period,"RATIO"))>0?GlobalVariableGet(SessionKey(period,"RATIO_RISK")):TPDR_RiskCash();
 string cash=currency+" "+DoubleToString(remaining,2);
 string percentage=balance>0?DoubleToString(remaining/balance*100,2)+"%":"Percentage pending";
 string ratio=risk>0?"1:"+DoubleToString(remaining/risk,2):"Ratio pending";
 if(GlobalVariableGet(SessionKey(period,"RATIO"))>0)return ratio+" ("+percentage+" - "+cash+")";
 if(percent)return percentage+" ("+cash+" - "+ratio+")";
 return cash+" ("+percentage+" - "+ratio+")";
}


void TPDR_RemainingParts(datetime period,double remaining,double balance,string currency,bool percent,string &primary,string &second,string &third)
{
 double risk=GlobalVariableGet(SessionKey(period,"RATIO"))>0?GlobalVariableGet(SessionKey(period,"RATIO_RISK")):TPDR_RiskCash();
 string cash=currency+" "+DoubleToString(remaining,2);
 string percentage=balance>0?DoubleToString(remaining/balance*100,2)+"%":"Percentage pending";
 string ratio=MathIsValidNumber(risk)&&risk>0?"1:"+DoubleToString(remaining/risk,2):"Ratio pending";
 if(GlobalVariableGet(SessionKey(period,"RATIO"))>0){primary=ratio;second="Percentage: "+percentage;third="Cash: "+cash;}
 else if(percent){primary=percentage;second="Cash: "+cash;third="Ratio: "+ratio;}
 else {primary=cash;second="Percentage: "+percentage;third="Ratio: "+ratio;}
}

#endif
