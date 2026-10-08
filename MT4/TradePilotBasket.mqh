#ifndef TRADEPILOT_BASKET_RESULTS
#define TRADEPILOT_BASKET_RESULTS
// Original broker-day cohorts; net charges are counted once per retained record.
#ifdef __MQL5__
int TP_BasketSlot(ulong id,ulong &ids[],bool &used[])
{
 uint hash=(uint)(id^(id>>32));hash^=hash>>16;hash*=0x7feb352d;hash^=hash>>15;hash*=0x846ca68b;hash^=hash>>16;
 int size=ArraySize(ids),slot=(int)(hash%(uint)size);
 for(int i=0;i<size;i++) {if(!used[slot]) {used[slot]=true;ids[slot]=id;return slot;}if(ids[slot]==id)return slot;slot=(slot+1)%size;}
 return -1;
}
#endif
bool TP_BasketResults(datetime period,double &actual,double &adjusted,bool include_floating=true)
{
 actual=0;adjusted=0;
#ifdef __MQL5__
 if(!HistorySelect(period,TPDL_Now()))return false;
 int expected=HistoryDealsTotal()+PositionsTotal();if(expected>1000000)return false;
 int capacity=16;while(capacity<expected*2+1)capacity*=2;
 ulong ids[];bool used[];double net[];datetime started[];
 if(ArrayResize(ids,capacity)<0||ArrayResize(used,capacity)<0||ArrayResize(net,capacity)<0||ArrayResize(started,capacity)<0)return false;
 ArrayInitialize(used,false);ArrayInitialize(net,0);ArrayInitialize(started,0);
 for(int i=0;i<HistoryDealsTotal();i++) {
  ulong ticket=HistoryDealGetTicket(i);if(ticket==0)return false;
  long type=HistoryDealGetInteger(ticket,DEAL_TYPE);if(type!=DEAL_TYPE_BUY&&type!=DEAL_TYPE_SELL)continue;
  ulong id=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);if(id==0)continue;
  int slot=TP_BasketSlot(id,ids,used);if(slot<0)return false;
  double value=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_COMMISSION)+HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_FEE);
  if(!MathIsValidNumber(value))return false;net[slot]+=value;
  long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
  if(entry==DEAL_ENTRY_IN||entry==DEAL_ENTRY_INOUT) {datetime stamp=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);if(started[slot]==0||stamp<started[slot])started[slot]=stamp;}
 }
 for(int i=0;i<PositionsTotal();i++) {
  if(PositionGetTicket(i)==0)return false;
  int slot=TP_BasketSlot((ulong)PositionGetInteger(POSITION_IDENTIFIER),ids,used);if(slot<0)return false;
  double value=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);if(!MathIsValidNumber(value))return false;if(include_floating)net[slot]+=value;
  datetime stamp=(datetime)PositionGetInteger(POSITION_TIME);if(started[slot]==0||stamp<started[slot])started[slot]=stamp;
 }
 for(int i=0;i<capacity;i++) if(used[i]&&started[i]>0&&GetSessionStartForTime(started[i])==period) {actual+=net[i];if(TP_DailyInclude(period,net[i]))adjusted+=net[i];}
#else
 if(!TP_HistoryReady())return false;
 for(int pool=0;pool<(include_floating?2:1);pool++) {
  int total=pool==0?OrdersHistoryTotal():OrdersTotal();
  for(int i=0;i<total;i++) {
   if(!OrderSelect(i,SELECT_BY_POS,pool==0?MODE_HISTORY:MODE_TRADES))return false;
   if((OrderType()!=OP_BUY&&OrderType()!=OP_SELL)||GetSessionStartForTime(OrderOpenTime())!=period)continue;
   double value=OrderProfit()+OrderCommission()+OrderSwap();if(!MathIsValidNumber(value))return false;
   actual+=value;if(TP_DailyInclude(period,value))adjusted+=value;
  }
 }
#endif
 return MathIsValidNumber(actual)&&MathIsValidNumber(adjusted);
}

// Broker charges are reported separately from a current quote spread estimate.
// Neither is subtracted a second time from already net basket results.
bool TP_BasketChargeDetails(datetime period,double &costs,double &spread,bool &spread_verified,bool &prior_exits,double &commission,double &swaps,double &fees)
{
 costs=0;spread=0;commission=0;swaps=0;fees=0;prior_exits=false;spread_verified=true;
#ifdef __MQL5__
 if(!HistorySelect(period,TPDL_Now()))return false;
 int expected=HistoryDealsTotal()+PositionsTotal();if(expected>1000000)return false;
 int capacity=16;while(capacity<expected*2+1)capacity*=2;
 ulong ids[];bool used[],exits[];double charges[],commissions[],swap_values[],fee_values[];datetime born[];
 if(ArrayResize(ids,capacity)<0||ArrayResize(used,capacity)<0||ArrayResize(exits,capacity)<0||ArrayResize(charges,capacity)<0||ArrayResize(commissions,capacity)<0||ArrayResize(swap_values,capacity)<0||ArrayResize(fee_values,capacity)<0||ArrayResize(born,capacity)<0)return false;
 ArrayInitialize(used,false);ArrayInitialize(exits,false);ArrayInitialize(charges,0);ArrayInitialize(commissions,0);ArrayInitialize(swap_values,0);ArrayInitialize(fee_values,0);ArrayInitialize(born,0);
 for(int i=0;i<HistoryDealsTotal();i++) {
  ulong ticket=HistoryDealGetTicket(i);if(ticket==0)return false;
  long type=HistoryDealGetInteger(ticket,DEAL_TYPE);if(type!=DEAL_TYPE_BUY&&type!=DEAL_TYPE_SELL)continue;
  ulong id=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);if(id==0)continue;
  int slot=TP_BasketSlot(id,ids,used);if(slot<0)return false;
  double fee=HistoryDealGetDouble(ticket,DEAL_COMMISSION)+HistoryDealGetDouble(ticket,DEAL_FEE)+HistoryDealGetDouble(ticket,DEAL_SWAP);if(!MathIsValidNumber(fee))return false;charges[slot]-=fee;commissions[slot]-=HistoryDealGetDouble(ticket,DEAL_COMMISSION);swap_values[slot]-=HistoryDealGetDouble(ticket,DEAL_SWAP);fee_values[slot]-=HistoryDealGetDouble(ticket,DEAL_FEE);
  long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
  if(entry==DEAL_ENTRY_IN||entry==DEAL_ENTRY_INOUT) {datetime stamp=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);if(born[slot]==0||stamp<born[slot])born[slot]=stamp;}
  if(entry==DEAL_ENTRY_OUT||entry==DEAL_ENTRY_OUT_BY||entry==DEAL_ENTRY_INOUT)exits[slot]=true;
 }
 for(int i=0;i<PositionsTotal();i++) {
  if(PositionGetTicket(i)==0)return false;
  int slot=TP_BasketSlot((ulong)PositionGetInteger(POSITION_IDENTIFIER),ids,used);if(slot<0)return false;
  datetime stamp=(datetime)PositionGetInteger(POSITION_TIME);if(born[slot]==0||stamp<born[slot])born[slot]=stamp;
  if(GetSessionStartForTime(born[slot])!=period)continue;
  double swap=PositionGetDouble(POSITION_SWAP);if(!MathIsValidNumber(swap))return false;charges[slot]-=swap;swap_values[slot]-=swap;
  string symbol=PositionGetString(POSITION_SYMBOL);double volume=PositionGetDouble(POSITION_VOLUME);MqlTick quote;
  if(!TerminalInfoInteger(TERMINAL_CONNECTED)||!SymbolInfoTick(symbol,quote)||quote.bid<=0||quote.ask<quote.bid||MathAbs((double)(TPDL_Now()-quote.time))>15){spread_verified=false;continue;}
  double value=0;bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
  if(!OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,symbol,volume,buy?quote.ask:quote.bid,buy?quote.bid:quote.ask,value)||!MathIsValidNumber(value)){spread_verified=false;continue;}
  spread+=MathMax(0,-value);
 }
 for(int i=0;i<capacity;i++)if(used[i]&&born[i]>0&&GetSessionStartForTime(born[i])==period){costs+=charges[i];commission+=commissions[i];swaps+=swap_values[i];fees+=fee_values[i];if(exits[i])prior_exits=true;}
#else
 if(!TP_HistoryReady())return false;
 for(int pool=0;pool<2;pool++)for(int i=0;i<(pool==0?OrdersHistoryTotal():OrdersTotal());i++) {
  if(!OrderSelect(i,SELECT_BY_POS,pool==0?MODE_HISTORY:MODE_TRADES))return false;
  if((OrderType()!=OP_BUY&&OrderType()!=OP_SELL)||GetSessionStartForTime(OrderOpenTime())!=period)continue;
  double fee=OrderCommission()+OrderSwap();if(!MathIsValidNumber(fee))return false;costs-=fee;commission-=OrderCommission();swaps-=OrderSwap();
  if(pool==0){prior_exits=true;continue;}
  string symbol=OrderSymbol();MqlTick quote;double tick=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
  if(!TerminalInfoInteger(TERMINAL_CONNECTED)||!SymbolInfoTick(symbol,quote)||quote.bid<=0||quote.ask<quote.bid||MathAbs((double)(TPDL_Now()-quote.time))>15||!MathIsValidNumber(tick)||!MathIsValidNumber(value)||tick<=0||value<=0){spread_verified=false;continue;}
  spread+=(quote.ask-quote.bid)/tick*value*OrderLots();
 }
#endif
 return MathIsValidNumber(costs)&&MathIsValidNumber(spread);
}
bool TP_BasketCosts(datetime period,double &costs,double &spread,bool &fresh,bool &exits)
{double commission=0,swap=0,fees=0;return TP_BasketChargeDetails(period,costs,spread,fresh,exits,commission,swap,fees);}
void TP_BasketCostsRender(datetime period)
{
 double costs=0,spread=0,commission=0,swap=0,fees=0;bool fresh=false,exits=false;bool verified=TP_BasketChargeDetails(period,costs,spread,fresh,exits,commission,swap,fees);
 string currency=
#ifdef __MQL5__
 AccountInfoString(ACCOUNT_CURRENCY);
#else
 AccountCurrency();
#endif
 int x=PanelX()+PanelWidth()+S(24);
 string cost_text="Commission = "+(verified?currency+" "+DoubleToString(commission,2):"Verification pending");
 string swap_text="Swap = "+(verified?currency+" "+DoubleToString(swap,2):"Verification pending");
 string spread_text="Spread = "+(!verified||!fresh?"Quote pending":currency+" "+DoubleToString(spread,2)+" (current estimate)");
 string gross_reason=!verified ? "Checking trade details" : !fresh ? "Checking broker prices" : exits ? "Past spread not saved" : "";
 string gross_text="Gross estimate = "+(gross_reason!="" ? gross_reason : currency+" "+DoubleToString(GetSessionTargetMoney(period)+costs+spread,2));
 CreateLabel("TradePilot_BASKET_COSTS",cost_text,x,PanelY()+S(151),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 CreateLabel("TradePilot_BASKET_SWAP",swap_text,x,PanelY()+S(169),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 CreateLabel("TradePilot_BASKET_SPREAD",spread_text,x,PanelY()+S(187),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 CreateLabel("TradePilot_BASKET_GROSS",gross_text,x,PanelY()+S(205),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 ObjectSetString(0,"TradePilot_BASKET_SWAP",OBJPROP_TOOLTIP,"Broker-reported swap, including current accrued swap. Credits appear as negative amounts. Already included in net results.");
 ObjectSetString(0,"TradePilot_BASKET_COSTS",OBJPROP_TOOLTIP,"Broker-reported commission. Credits appear as negative amounts. Separately reported fees: "+currency+" "+DoubleToString(fees,2)+". All charges are included once in net results.");
 ObjectSetString(0,"TradePilot_BASKET_SPREAD",OBJPROP_TOOLTIP,"Current fresh bid/ask cost estimate for this basket's remaining open volume, converted using this broker's contract. This is not the spread paid at entry. Closed-volume historic spread is not reconstructed from today's quotes. "+spread_text);
 ObjectSetString(0,"TradePilot_BASKET_GROSS",OBJPROP_TOOLTIP,"Your target plus estimated commission, swap, fees and spread. Example: 500 target + 3 charges + 2 spread = 505. This is an estimate, not a bill. After trades close, their earlier spread may not be saved, so the estimate is not shown. Your basket still uses its net target without counting spread twice. "+gross_text);
}


void TP_BasketProgressRows(datetime period)
{
 double actual=0,adjusted=0,costs=0,spread=0,commission=0,swap=0,fees=0,gross=0;
 bool fresh=false,exits=false,verified=TP_BasketResults(period,actual,adjusted);
 bool charges=TP_BasketChargeDetails(period,costs,spread,fresh,exits,commission,swap,fees);
#ifdef __MQL5__
 string currency=AccountInfoString(ACCOUNT_CURRENCY);
 for(int i=0;i<PositionsTotal();i++)if(PositionGetTicket(i)>0&&GetSessionStartForTime((datetime)PositionGetInteger(POSITION_TIME))==period)gross+=PositionGetDouble(POSITION_PROFIT);
#else
 string currency=AccountCurrency();
 for(int i=0;i<OrdersTotal();i++)if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)&&(OrderType()==OP_BUY||OrderType()==OP_SELL)&&GetSessionStartForTime(OrderOpenTime())==period)gross+=OrderProfit();
#endif
 int x=PanelX()+PanelWidth()+S(24),vx=ValueX()+PanelWidth()+S(12);
 string labels[]={"Floating trades","Costs estimate","Total P/L"};
 string values[3];values[0]=currency+" "+DoubleToString(gross,2);values[1]=charges&&fresh?currency+" "+DoubleToString(costs+spread,2):"Quote pending";values[2]=verified?currency+" "+DoubleToString(actual,2):"Verification pending";
 int ys[]={46,65,160};string keys[]={"TRADES","ESTIMATE","TOTAL"};
 for(int i=0;i<3;i++){string key="TradePilot_BASKET_"+keys[i];CreateLabel(key+"_LABEL",labels[i],x,PanelY()+S(ys[i]),FontSize(BASE_FONT_NORMAL),C'190,195,205');CreateLabel(key+"_VALUE",values[i],vx,PanelY()+S(ys[i]),MathMax(4,MathMin(FontSize(BASE_FONT_NORMAL),(int)(S(124)/MathMax(1,StringLen(values[i])*0.60)))),i==2?(actual<0?C'255,100,100':actual>0?C'90,220,140':clrWhite):clrWhite);}
 ObjectSetString(0,"TradePilot_BASKET_TRADES_VALUE",OBJPROP_TOOLTIP,"Current open trades' broker price profit/loss before separately reported commission and swap. Bid/ask spread already affects this price result.");
 ObjectSetString(0,"TradePilot_BASKET_ESTIMATE_VALUE",OBJPROP_TOOLTIP,"This original-day basket's reported commission, swap and separate fees plus a current open-volume spread estimate. Not deducted again from Floating P/L or Total P/L. Historic entry spread and future fees are not invented.");
 ObjectSetString(0,"TradePilot_BASKET_TOTAL_VALUE",OBJPROP_TOOLTIP,"Original-day basket's closed and open broker net results, including retained commission, swap and fees once. Actual results are shown regardless of Apply wins/losses progress choices.");

#ifdef __MQL5__
 double floating=GetSessionFloatingProfit(period);bool percentage=GetSessionTargetMode(period)==DAILY_PERCENTAGE;
#else
 double floating=GetSessionFloatingPL(period);bool percentage=GetSessionPercentageMode(period);
#endif
 string primary="",second="",third="";TPDR_RemainingParts(period,floating,GetSessionStartBalance(period),currency,percentage,primary,second,third);
 StringReplace(second,"Percentage: ","");StringReplace(second,"Cash: ","");StringReplace(second,"Ratio: ","");StringReplace(third,"Percentage: ","");StringReplace(third,"Cash: ","");StringReplace(third,"Ratio: ","");
 string equivalents="("+second+"; "+third+")";
 ObjectSetString(0,"TradePilot_PROFIT_VALUE",OBJPROP_TEXT,primary);
 ObjectSetInteger(0,"TradePilot_PROFIT_VALUE",OBJPROP_FONTSIZE,MathMax(4,MathMin(FontSize(BASE_FONT_NORMAL),(int)(S(124)/MathMax(1,StringLen(primary)*0.60)))));
 if(ObjectFind(0,"TradePilot_FLOATING_EQUIVALENTS")>=0)ObjectDelete(0,"TradePilot_FLOATING_EQUIVALENTS");
 string explanation="Floating P/L in the saved target mode, with the other two equivalents in brackets. Percentage uses original daily starting balance; Ratio uses planned cash risk. Broker floating results are distinct from total closed-plus-open net P/L. "+primary+" "+equivalents;
 ObjectSetString(0,"TradePilot_PROFIT_VALUE",OBJPROP_TOOLTIP,explanation);
 ObjectSetInteger(0,"TradePilot_BASKET_TOTAL_LABEL",OBJPROP_YDISTANCE,PanelY()+S(184));ObjectSetInteger(0,"TradePilot_BASKET_TOTAL_VALUE",OBJPROP_YDISTANCE,PanelY()+S(184));
 string names[]={"PROFIT_LABEL","PROFIT_VALUE","TP_VALUE_LABEL","TARGET_VALUE","TARGET_OTHER1","TARGET_OTHER2","STATUS_LABEL","STATUS_VALUE","BASKET_COSTS","BASKET_SWAP","BASKET_SPREAD","BASKET_GROSS"};
 int positions[]={141,141,221,221,242,263,294,294,84,103,122,313};
 for(int i=0;i<ArraySize(names);i++)if(ObjectFind(0,"TradePilot_"+names[i])>=0)ObjectSetInteger(0,"TradePilot_"+names[i],OBJPROP_YDISTANCE,PanelY()+S(positions[i]));
 if(ObjectFind(0,"TradePilot_BASKET_COLUMN_BG")>=0)ObjectSetInteger(0,"TradePilot_BASKET_COLUMN_BG",OBJPROP_YSIZE,S(444));
 if(ObjectFind(0,"TradePilot_CURRENT_BORDER")>=0)ObjectSetInteger(0,"TradePilot_CURRENT_BORDER",OBJPROP_YSIZE,S(340));
 string carry[]={"CARRY_BORDER","CARRY_DIVIDER","CARRY_TITLE","CARRY_BASKETS_LABEL","CARRY_BASKETS_VALUE","CARRY_POSITIONS_LABEL","CARRY_POSITIONS_VALUE","CARRY_PROFIT_LABEL","CARRY_PROFIT_VALUE","CARRY_CURRENCY","CARRY_PL_LABEL","CARRY_PL_VALUE"};
 for(int i=0;i<ArraySize(carry);i++){string name="TradePilot_"+carry[i];if(ObjectFind(0,name)<0)continue;long y=ObjectGetInteger(0,name,OBJPROP_YDISTANCE);if(y<PanelY()+S(344))ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y+S(114));}
}

#endif
