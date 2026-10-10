#ifndef TRADEPILOT_DAILY_APPLY
#define TRADEPILOT_DAILY_APPLY
bool tp_limit_wins=false,tp_limit_losses=false;
datetime tp_apply_period=0;
bool TPDA_Closed(datetime period,double &wins,double &losses)
{int w=0,l=0;return TP_BasketOutcomes(period,w,l,wins,losses);}
bool TPDA_Flag(datetime period,string key)
{return GlobalVariableCheck(SessionKey(period,key)) && GlobalVariableGet(SessionKey(period,key))>0;}
double TPDA_Adjust(double base,double wins,double losses,bool use_wins,bool use_losses,bool target)
{return base+(target?-1:1)*((use_wins?wins:0)+(use_losses?losses:0));}
double TPDA_Target(datetime period,double base,bool draft=false)
{
 if(!draft && !TPDA_Flag(period,"APPLY_MODEL"))return base;
 double wins=0,losses=0;if(!TPDA_Closed(period,wins,losses))return base;
 return MathMax(0.00000001,TPDA_Adjust(base,wins,losses,draft?tp_daily_wins:TPDA_Flag(period,"APPLY_WINS"),draft?tp_daily_losses:TPDA_Flag(period,"APPLY_LOSSES"),true));
}
void TPDA_Load(datetime period)
{if(tp_apply_period==period)return;tp_apply_period=period;tp_limit_wins=TPDA_Flag(period,"LIMIT_WINS");tp_limit_losses=TPDA_Flag(period,"LIMIT_LOSSES");}
void TPDA_LimitSave(datetime period)
{GlobalVariableSet(SessionKey(period,"LIMIT_WINS"),tp_limit_wins?1:0);GlobalVariableSet(SessionKey(period,"LIMIT_LOSSES"),tp_limit_losses?1:0);GlobalVariableSet(SessionKey(period,"LIMIT_MODEL"),1);GlobalVariablesFlush();}
void TPDA_TargetSave(datetime period)
{GlobalVariableSet(SessionKey(period,"APPLY_MODEL"),1);GlobalVariablesFlush();}
void TPDA_LimitButtons()
{
 datetime period=GetSessionStartForTime(TPDL_Now());TPDA_Load(period);
 CreateButton("TradePilot_LIMIT_WINS","APPLY WINS",LabelX(),PanelY()+S(398),S(130),S(20),tp_limit_wins?C'35,115,80':C'140,45,45');
 CreateButton("TradePilot_LIMIT_LOSSES","APPLY LOSSES",ValueX(),PanelY()+S(398),S(130),S(20),tp_limit_losses?C'35,115,80':C'140,45,45');
 ObjectSetString(0,"TradePilot_LIMIT_WINS",OBJPROP_TOOLTIP,"Add this day's completed Current Basket wins to the loss allowance. Preview changes immediately; Update reviews and saves. Default OFF.");
 ObjectSetString(0,"TradePilot_LIMIT_LOSSES",OBJPROP_TOOLTIP,"Subtract this day's completed Current Basket losses from the loss allowance. Preview changes immediately; Update reviews and saves. Default OFF. Other open risk still counts.");
}
bool TPDA_LimitEvent(string name)
{if(name!="TradePilot_LIMIT_WINS" && name!="TradePilot_LIMIT_LOSSES")return false;ObjectSetInteger(0,name,OBJPROP_STATE,false);if(name=="TradePilot_LIMIT_WINS")tp_limit_wins=!tp_limit_wins;else tp_limit_losses=!tp_limit_losses;TPDC_Close();UpdatePanel();return true;}
void TPDA_PerformanceRows()
{
 datetime period=GetSessionStartForTime(TPDL_Now());
 string source[]={
#ifdef __MQL5__
 "TradePilot_DAILY_CLOSED_VALUE"
#else
 "TradePilot_CLOSED_PL_VALUE"
#endif
 };
 ObjectDelete(0,"TradePilot_PERF_BUDGET");ObjectDelete(0,"TradePilot_PERF_BUDGET_LABEL");
 string keys[]={"TradePilot_PERF_CLOSED"};string labels[]={"Closed P/L"};
 for(int i=0;i<1;i++){
 CreateLabel(keys[i]+"_LABEL",labels[i],LabelX(),PanelY()+S(140+i*22),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 CreateLabel(keys[i],ObjectGetString(0,source[i],OBJPROP_TEXT),ValueX(),PanelY()+S(140+i*22),FontSize(BASE_FONT_NORMAL),(color)ObjectGetInteger(0,source[i],OBJPROP_COLOR));
 ObjectSetString(0,keys[i],OBJPROP_TOOLTIP,ObjectGetString(0,source[i],OBJPROP_TOOLTIP));
 }
 double closed=0,floating=0,adjusted=0;bool ready=TPDL_Totals(closed,floating,adjusted);
 double base=GetSessionBaseTargetMoney(period),wins=0,losses=0;
 double entered=TPDR_Parse(ObjectGetString(0,"TradePilot_DAILY_TARGET_EDIT",OBJPROP_TEXT));
 if(MathIsValidNumber(entered) && entered>0)base=TPDR_Enabled()?entered*TPDR_RiskCash():(GetDailyTargetMode()==DAILY_PERCENTAGE?GetSessionStartBalance(period)*entered/100:entered);
 double preview=TPDA_Target(period,base,true);
 ready=ready && TPDA_Closed(period,wins,losses);
 // The completed outcomes are in the adjusted target; do not subtract them twice.
 double selected_saved=(TPDA_Flag(period,"APPLY_WINS")?wins:0)+(TPDA_Flag(period,"APPLY_LOSSES")?losses:0);
 if(!TPDA_Flag(period,"APPLY_MODEL"))adjusted-=selected_saved;
 double remaining=MathMax(0,preview-adjusted);
 string currency=AccountInfoString(ACCOUNT_CURRENCY);
 CreateLabel("TradePilot_PERF_REMAIN_LABEL","Remaining target",LabelX(),PanelY()+S(162),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 CreateLabel("TradePilot_PERF_REMAIN",ready?TP_BasketModeValue(period,remaining,currency):"Verification pending",ValueX(),PanelY()+S(162),FontSize(BASE_FONT_NORMAL),C'90,220,140');
 ObjectSetString(0,"TradePilot_PERF_REMAIN",OBJPROP_TOOLTIP,"Amount still needed for this day's target. Apply wins reduces the target; Apply losses increases it. Completed results are counted once. The displayed preview is saved only after Update and Yes.");
 TPDR_TargetEquivalents(period,preview,GetDailyTargetMode()==DAILY_PERCENTAGE,currency);
 ObjectSetString(0,"TradePilot_DAILY_EQUIVALENT_LABEL",OBJPROP_TEXT,"Target preview");
 ObjectSetString(0,"TradePilot_DAILY_EQUIVALENT",OBJPROP_TOOLTIP,"Preview of the base daily target adjusted by the selected completed Current Basket wins and losses. Update and Yes saves your selections. No changes are applied while this is only a preview.");
}
#endif
