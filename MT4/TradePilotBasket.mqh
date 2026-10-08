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
string TP_BasketModeValue(datetime period,double value,string currency)
{
 string primary="",second="",third="";
 TPDR_RemainingParts(period,value,GetSessionStartBalance(period),currency,GlobalVariableGet(GV_DAILY_MODE)>0.5,primary,second,third,true);
 return primary;
}
string TP_CarryMoneyPercent(double floating)
{
 #ifdef __MQL5__
 string currency=AccountInfoString(ACCOUNT_CURRENCY);
#else
 string currency=AccountCurrency();
#endif
 string cash=currency+" "+DoubleToString(floating,2);
 datetime today=GetSessionStartForTime(TPDL_Now()),days[];double baseline=0;
#ifdef __MQL5__
 int total=PositionsTotal();
#else
 int total=OrdersTotal();
#endif
 for(int i=0;i<total;i++) {
#ifdef __MQL5__
  if(PositionGetTicket(i)==0)continue;
  datetime day=GetSessionStartForTime((datetime)PositionGetInteger(POSITION_TIME));
#else
  if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)||(OrderType()!=OP_BUY&&OrderType()!=OP_SELL))continue;
  datetime day=GetSessionStartForTime(OrderOpenTime());
#endif
  if(day>=today)continue;bool seen=false;for(int j=0;j<ArraySize(days);j++)if(days[j]==day)seen=true;
  if(seen)continue;int n=ArraySize(days);if(ArrayResize(days,n+1)<0)return cash+" (Percentage pending)";days[n]=day;
  double balance=GetSessionStartBalance(day);if(!MathIsValidNumber(balance)||balance<=0)return cash+" (Percentage pending)";baseline+=balance;
 }
 return cash+" ("+(baseline>0?DoubleToString(floating/baseline*100,2)+"%":ArraySize(days)==0?"0.00%":"Percentage pending")+")";
}
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
 string cost_text=(verified?TP_BasketModeValue(period,commission,currency):"Verification pending");
 string swap_text=(verified?TP_BasketModeValue(period,swap,currency):"Verification pending");
 string spread_text=(!verified||!fresh?"Quote pending":TP_BasketModeValue(period,spread,currency));
 CreateLabel("TradePilot_BASKET_COSTS",cost_text,x,PanelY()+S(151),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 CreateLabel("TradePilot_BASKET_SWAP",swap_text,x,PanelY()+S(169),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 CreateLabel("TradePilot_BASKET_SPREAD",spread_text,x,PanelY()+S(187),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 string cost_keys[]={"BASKET_COSTS","BASKET_SWAP","BASKET_SPREAD"};
 string cost_labels[]={"Commission","Swap","Spread estimate"};
 int cost_rows[]={67,87,107};
 for(int i=0;i<3;i++)CreateLabel("TradePilot_"+cost_keys[i]+"_LABEL",cost_labels[i],x,PanelY()+S(cost_rows[i]),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 ObjectSetString(0,"TradePilot_BASKET_SWAP",OBJPROP_TOOLTIP,"Broker-reported swap, including current accrued swap. Credits appear as negative amounts. Already included in net results.");
 ObjectSetString(0,"TradePilot_BASKET_COSTS",OBJPROP_TOOLTIP,"Broker-reported commission. Credits appear as negative amounts. Separately reported fees: "+currency+" "+DoubleToString(fees,2)+". All charges are included once in net results.");
 ObjectSetString(0,"TradePilot_BASKET_SPREAD",OBJPROP_TOOLTIP,"Current fresh bid/ask cost estimate for this basket's remaining open volume, converted using this broker's contract. This is not the spread paid at entry. Closed-volume historic spread is not reconstructed from today's quotes. "+spread_text);
}


// Completed net outcomes for the original-day cohort; open/partial positions are not wins.
bool TP_BasketOutcomes(datetime period,int &wins,int &losses,double &win_result,double &loss_result)
{
 wins=0;losses=0;win_result=0;loss_result=0;
 if(!TerminalInfoInteger(TERMINAL_CONNECTED))return false;
#ifdef __MQL5__
 if(!HistorySelect(period,TPDL_Now()))return false;
 int expected=HistoryDealsTotal()+PositionsTotal();if(expected>1000000)return false;
 int capacity=16;while(capacity<expected*2+1)capacity*=2;
 ulong ids[];bool used[],open[],exited[];double net[];datetime born[];
 if(ArrayResize(ids,capacity)<0||ArrayResize(used,capacity)<0||ArrayResize(open,capacity)<0||ArrayResize(exited,capacity)<0||ArrayResize(net,capacity)<0||ArrayResize(born,capacity)<0)return false;
 ArrayInitialize(used,false);ArrayInitialize(open,false);ArrayInitialize(exited,false);ArrayInitialize(net,0);ArrayInitialize(born,0);
 for(int i=0;i<HistoryDealsTotal();i++) {
  ulong ticket=HistoryDealGetTicket(i);if(ticket==0)return false;
  long type=HistoryDealGetInteger(ticket,DEAL_TYPE);if(type!=DEAL_TYPE_BUY&&type!=DEAL_TYPE_SELL)continue;
  ulong id=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);if(id==0)continue;
  int slot=TP_BasketSlot(id,ids,used);if(slot<0)return false;
  double value=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_COMMISSION)+HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_FEE);
  if(!MathIsValidNumber(value))return false;net[slot]+=value;
  long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
  if(entry==DEAL_ENTRY_INOUT)return false; // Reversals need split-leg evidence, never invent a count.
  if(entry==DEAL_ENTRY_IN){datetime stamp=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);if(born[slot]==0||stamp<born[slot])born[slot]=stamp;}
  if(entry==DEAL_ENTRY_OUT||entry==DEAL_ENTRY_OUT_BY)exited[slot]=true;
 }
 for(int i=0;i<PositionsTotal();i++) {
  if(PositionGetTicket(i)==0)return false;
  int slot=TP_BasketSlot((ulong)PositionGetInteger(POSITION_IDENTIFIER),ids,used);if(slot<0)return false;open[slot]=true;
 }
 for(int i=0;i<capacity;i++)if(used[i]&&exited[i]&&!open[i]&&born[i]>0&&GetSessionStartForTime(born[i])==period){if(net[i]>0){wins++;win_result+=net[i];}else if(net[i]<0){losses++;loss_result+=net[i];}}
#else
 if(!TP_HistoryReady())return false;
 for(int i=0;i<OrdersHistoryTotal();i++) {
  if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))return false;
  if((OrderType()!=OP_BUY&&OrderType()!=OP_SELL)||OrderCloseTime()<=0||GetSessionStartForTime(OrderOpenTime())!=period)continue;
  double net=OrderProfit()+OrderCommission()+OrderSwap();if(!MathIsValidNumber(net))return false;
  if(net>0){wins++;win_result+=net;}else if(net<0){losses++;loss_result+=net;}
 }
#endif
 return true;
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
 string labels[]={"Floating trades","Total P/L"};
 string values[2];values[0]=TP_BasketModeValue(period,gross,currency);values[1]=verified?TP_BasketModeValue(period,actual,currency):"Verification pending";
 int ys[]={47,242};string keys[]={"TRADES","TOTAL"};
 for(int i=0;i<2;i++){string key="TradePilot_BASKET_"+keys[i];CreateLabel(key+"_LABEL",labels[i],x,PanelY()+S(ys[i]),FontSize(BASE_FONT_NORMAL),C'190,195,205');CreateLabel(key+"_VALUE",values[i],vx,PanelY()+S(ys[i]),MathMax(4,MathMin(FontSize(BASE_FONT_NORMAL),(int)(S(124)/MathMax(1,StringLen(values[i])*0.60)))),i==1?(actual<0?C'255,100,100':actual>0?C'90,220,140':clrWhite):clrWhite);}
 ObjectSetString(0,"TradePilot_BASKET_TRADES_VALUE",OBJPROP_TOOLTIP,"Current open trades' broker price profit/loss before separately reported commission and swap. Bid/ask spread already affects this price result.");
 ObjectSetString(0,"TradePilot_BASKET_TOTAL_VALUE",OBJPROP_TOOLTIP,"Original-day basket's closed and open broker net results, including retained commission, swap and fees once. Actual results are shown regardless of Apply wins/losses progress choices.");

#ifdef __MQL5__
 double floating=GetSessionFloatingProfit(period);bool percentage=GetSessionTargetMode(period)==DAILY_PERCENTAGE;
#else
 double floating=GetSessionFloatingPL(period);bool percentage=GetSessionPercentageMode(period);
#endif
 string primary="",second="",third="";TPDR_RemainingParts(period,floating,GetSessionStartBalance(period),currency,GlobalVariableGet(GV_DAILY_MODE)>0.5,primary,second,third,true);
 StringReplace(second,"Percentage: ","");StringReplace(second,"Cash: ","");StringReplace(second,"Ratio: ","");StringReplace(third,"Percentage: ","");StringReplace(third,"Cash: ","");StringReplace(third,"Ratio: ","");
 string equivalents="("+second+"; "+third+")";
 ObjectSetString(0,"TradePilot_PROFIT_VALUE",OBJPROP_TEXT,primary);
 ObjectSetInteger(0,"TradePilot_PROFIT_VALUE",OBJPROP_FONTSIZE,MathMax(4,MathMin(FontSize(BASE_FONT_NORMAL),(int)(S(124)/MathMax(1,StringLen(primary)*0.60)))));
 if(ObjectFind(0,"TradePilot_FLOATING_EQUIVALENTS")>=0)ObjectDelete(0,"TradePilot_FLOATING_EQUIVALENTS");
 string explanation="Floating P/L in the saved target mode, with the other two equivalents in brackets. Percentage uses original daily starting balance; Ratio uses planned cash risk. Broker floating results are distinct from total closed-plus-open net P/L. "+primary+" "+equivalents;
 ObjectSetString(0,"TradePilot_PROFIT_VALUE",OBJPROP_TOOLTIP,explanation);
 // Four outline edges keep the total readable without covering its labels.
 int total_x=PanelX()+PanelWidth()+S(20),total_y=PanelY()+S(235),total_w=S(288),total_h=S(29);
 CreateRectangle("TradePilot_TOTAL_TOP",total_x,total_y,total_w,1,C'110,125,145',C'110,125,145');
 CreateRectangle("TradePilot_TOTAL_BOTTOM",total_x,total_y+total_h,total_w,1,C'110,125,145',C'110,125,145');
 CreateRectangle("TradePilot_TOTAL_LEFT",total_x,total_y,1,total_h,C'110,125,145',C'110,125,145');
 CreateRectangle("TradePilot_TOTAL_RIGHT",total_x+total_w,total_y,1,total_h,C'110,125,145',C'110,125,145');
 ObjectSetInteger(0,"TradePilot_BASKET_TOTAL_LABEL",OBJPROP_YDISTANCE,PanelY()+S(242));ObjectSetInteger(0,"TradePilot_BASKET_TOTAL_VALUE",OBJPROP_YDISTANCE,PanelY()+S(242));
 string names[]={"PROFIT_LABEL","PROFIT_VALUE","TP_VALUE_LABEL","TARGET_VALUE","TARGET_OTHER1","TARGET_OTHER2","STATUS_LABEL","STATUS_VALUE","BASKET_COSTS","BASKET_SWAP","BASKET_SPREAD","BASKET_GROSS"};
 int positions[]={203,203,284,284,305,326,347,347,67,87,107,424};
 for(int i=0;i<ArraySize(names);i++)if(ObjectFind(0,"TradePilot_"+names[i])>=0)ObjectSetInteger(0,"TradePilot_"+names[i],OBJPROP_YDISTANCE,PanelY()+S(positions[i]));
 int wins=0,losses=0;double win_result=0,loss_result=0;
 bool outcomes=TP_BasketOutcomes(period,wins,losses,win_result,loss_result);
 string outcome_keys[]={"WINS","LOSSES"};string outcome_titles[]={"Wins","Losses"};
 for(int i=0;i<2;i++) {
  string key="TradePilot_BASKET_"+outcome_keys[i];int row=127+i*20;
  string main="Verification pending",other1="",other2="";
  if(outcomes)TPDR_RemainingParts(period,i==0?win_result:loss_result,GetSessionStartBalance(period),currency,GlobalVariableGet(GV_DAILY_MODE)>0.5,main,other1,other2,true);
  StringReplace(other1,"Percentage: ","");StringReplace(other1,"Cash: ","");StringReplace(other1,"Ratio: ","");
  StringReplace(other2,"Percentage: ","");StringReplace(other2,"Cash: ","");StringReplace(other2,"Ratio: ","");
  string outcome_equivalents=outcomes?"("+other1+"; "+other2+")":"";
  string display=outcomes?main+" "+outcome_equivalents:main;
  color shade=i==0?C'90,220,140':C'255,100,100';
  CreateLabel(key+"_LABEL",outcome_titles[i],x,PanelY()+S(row),FontSize(BASE_FONT_NORMAL),C'190,195,205');
  CreateLabel(key+"_VALUE",display,vx,PanelY()+S(row),TP_HeaderFont(display,FontSize(BASE_FONT_NORMAL),S(132),S(15)),shade);
  if(ObjectFind(0,key+"_OTHER")>=0)ObjectDelete(0,key+"_OTHER");
  string help=i==0?"Profit from completed winning trades in this day's basket. The main amount follows Cash, Percentage or Ratio; brackets show the other two ways to read it. The shared counter below shows wins/losses in W/L order. Reported trading charges are included. Open and break-even trades are not wins.":"Loss from completed losing trades in this day's basket, shown as a negative amount. The main amount follows Cash, Percentage or Ratio; brackets show the other two ways to read it. The shared counter below shows wins/losses in W/L order. Reported trading charges are included. Open and break-even trades are not losses.";
  help+=" Percentage uses the day's starting balance. Ratio uses planned cash risk. MT5 counts fully closed positions; MT4 counts closed broker tickets. Apply wins/losses changes target progress, not these actual results.";
  ObjectSetString(0,key+"_LABEL",OBJPROP_TOOLTIP,help);ObjectSetString(0,key+"_VALUE",OBJPROP_TOOLTIP,help);
 }
 ObjectDelete(0,"TradePilot_BASKET_WINS_COUNT");ObjectDelete(0,"TradePilot_BASKET_LOSSES_COUNT");
 CreateLabel("TradePilot_BASKET_TRADE_COUNT_LABEL","Trade count",x,PanelY()+S(167),FontSize(BASE_FONT_NORMAL),C'190,195,205');
 CreateLabel("TradePilot_BASKET_TRADE_COUNT_VALUE",outcomes?IntegerToString(wins)+"/"+IntegerToString(losses)+" (W/L)":"Count pending",vx,PanelY()+S(167),FontSize(BASE_FONT_NORMAL),clrWhite);
 string count_help="Completed wins / completed losses in this day's basket. 1/2 (W/L) means one win and two losses. Open and break-even trades are excluded. MT5 counts fully closed positions; MT4 counts closed broker tickets. Apply wins/losses does not change these actual counts.";
 ObjectSetString(0,"TradePilot_BASKET_TRADE_COUNT_LABEL",OBJPROP_TOOLTIP,count_help);ObjectSetString(0,"TradePilot_BASKET_TRADE_COUNT_VALUE",OBJPROP_TOOLTIP,count_help);
 // Floating P/L has a subtler outline; Total P/L remains the stronger total.
 int floating_y=PanelY()+S(196);
 CreateRectangle("TradePilot_FLOAT_TOP",total_x,floating_y,total_w,1,C'65,75,90',C'65,75,90');
 CreateRectangle("TradePilot_FLOAT_BOTTOM",total_x,floating_y+S(28),total_w,1,C'65,75,90',C'65,75,90');
 CreateRectangle("TradePilot_FLOAT_LEFT",total_x,floating_y,1,S(28),C'65,75,90',C'65,75,90');
 CreateRectangle("TradePilot_FLOAT_RIGHT",total_x+total_w,floating_y,1,S(28),C'65,75,90',C'65,75,90');
 string obsolete[]={"BASKET_ESTIMATE_LABEL","BASKET_ESTIMATE_VALUE","BASKET_GROSS","BASKET_GROSS_LABEL"};
 for(int i=0;i<ArraySize(obsolete);i++)if(ObjectFind(0,"TradePilot_"+obsolete[i])>=0)ObjectDelete(0,"TradePilot_"+obsolete[i]);
 ObjectSetInteger(0,"TradePilot_TOTAL_TOP",OBJPROP_YSIZE,2);ObjectSetInteger(0,"TradePilot_TOTAL_BOTTOM",OBJPROP_YSIZE,2);
 ObjectSetInteger(0,"TradePilot_TOTAL_LEFT",OBJPROP_XSIZE,2);ObjectSetInteger(0,"TradePilot_TOTAL_RIGHT",OBJPROP_XSIZE,2);
 // Keep every row on the same label edge, including the legacy Positions/Floating rows.
 string left_labels[]={"POSITIONS_LABEL","PROFIT_LABEL","TP_VALUE_LABEL","STATUS_LABEL","BASKET_TRADES_LABEL","BASKET_ESTIMATE_LABEL","BASKET_TOTAL_LABEL","BASKET_COSTS_LABEL","BASKET_SWAP_LABEL","BASKET_SPREAD_LABEL","BASKET_GROSS_LABEL","BASKET_WINS_LABEL","BASKET_LOSSES_LABEL","BASKET_TRADE_COUNT_LABEL"};
 for(int i=0;i<ArraySize(left_labels);i++) {
  string name="TradePilot_"+left_labels[i];if(ObjectFind(0,name)<0)continue;
  ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
  ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
 }
 ObjectSetInteger(0,"TradePilot_POSITIONS_LABEL",OBJPROP_YDISTANCE,PanelY()+S(27));
 ObjectSetInteger(0,"TradePilot_POSITIONS_VALUE",OBJPROP_YDISTANCE,PanelY()+S(27));
 // Values occupy the right column, with left-to-right text aligned at its left edge.
 int value_left=ValueX()+PanelWidth()+S(12);
 string right_values[]={"POSITIONS_VALUE","PROFIT_VALUE","TARGET_VALUE","STATUS_VALUE","BASKET_WINS_VALUE","BASKET_LOSSES_VALUE","BASKET_TRADE_COUNT_VALUE","BASKET_TRADES_VALUE","BASKET_ESTIMATE_VALUE","BASKET_TOTAL_VALUE","BASKET_COSTS","BASKET_SWAP","BASKET_SPREAD","BASKET_GROSS"};
 for(int i=0;i<ArraySize(right_values);i++) {
  string name="TradePilot_"+right_values[i];if(ObjectFind(0,name)<0)continue;
  ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
  ObjectSetInteger(0,name,OBJPROP_XDISTANCE,value_left);
  string value=ObjectGetString(0,name,OBJPROP_TEXT);
  ObjectSetInteger(0,name,OBJPROP_FONTSIZE,TP_HeaderFont(value,FontSize(BASE_FONT_NORMAL),S(132),S(15)));
 }
 string other_keys[]={"TARGET_OTHER1","TARGET_OTHER2"};
 for(int i=0;i<2;i++) {
  string name="TradePilot_"+other_keys[i],value=ObjectGetString(0,name,OBJPROP_TEXT);
  int split=StringFind(value,": ");string caption=split>=0?StringSubstr(value,0,split):"Equivalent";
  if(split>=0)value=StringSubstr(value,split+2);
  CreateLabel(name+"_LABEL",caption,x,PanelY()+S(305+i*21),FontSize(BASE_FONT_NORMAL),C'190,195,205');
  ObjectSetString(0,name,OBJPROP_TEXT,value);
  ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
  ObjectSetInteger(0,name,OBJPROP_XDISTANCE,value_left);
  ObjectSetInteger(0,name,OBJPROP_FONTSIZE,TP_HeaderFont(value,FontSize(BASE_FONT_NORMAL),S(132),S(15)));
 }
 if(ObjectFind(0,"TradePilot_BASKET_COLUMN_BG")>=0)ObjectSetInteger(0,"TradePilot_BASKET_COLUMN_BG",OBJPROP_YSIZE,S(478));
 if(ObjectFind(0,"TradePilot_CURRENT_BORDER")>=0)ObjectSetInteger(0,"TradePilot_CURRENT_BORDER",OBJPROP_YSIZE,S(366));
 // Carry-over owns a padded container; no divider may cross its text.
 // Resize the existing background only; creating it here would put it above the labels.
 ObjectSetInteger(0,"TradePilot_CARRY_BORDER",OBJPROP_XDISTANCE,PanelX()+PanelWidth()+S(18));
 ObjectSetInteger(0,"TradePilot_CARRY_BORDER",OBJPROP_XSIZE,S(292));
 if(ObjectFind(0,"TradePilot_CARRY_DIVIDER")>=0)ObjectDelete(0,"TradePilot_CARRY_DIVIDER");
 string carry_labels[]={"CARRY_TITLE","CARRY_BASKETS_LABEL","CARRY_POSITIONS_LABEL","CARRY_PROFIT_LABEL","CARRY_PL_LABEL"};
 for(int i=0;i<ArraySize(carry_labels);i++){string key="TradePilot_"+carry_labels[i];if(ObjectFind(0,key)<0)continue;ObjectSetInteger(0,key,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,key,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);}
 string carry_values[]={"CARRY_BASKETS_VALUE","CARRY_POSITIONS_VALUE","CARRY_PROFIT_VALUE","CARRY_PL_VALUE"};
 for(int i=0;i<ArraySize(carry_values);i++){string key="TradePilot_"+carry_values[i];if(ObjectFind(0,key)<0)continue;ObjectSetInteger(0,key,OBJPROP_XDISTANCE,value_left);ObjectSetInteger(0,key,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);string value=ObjectGetString(0,key,OBJPROP_TEXT);ObjectSetInteger(0,key,OBJPROP_FONTSIZE,TP_HeaderFont(value,FontSize(BASE_FONT_NORMAL),S(132),S(15)));}
 string carry[]={"CARRY_BORDER","CARRY_DIVIDER","CARRY_TITLE","CARRY_BASKETS_LABEL","CARRY_BASKETS_VALUE","CARRY_POSITIONS_LABEL","CARRY_POSITIONS_VALUE","CARRY_PROFIT_LABEL","CARRY_PROFIT_VALUE","CARRY_CURRENCY","CARRY_PL_LABEL","CARRY_PL_VALUE"};
 int carry_rows[]={370,370,380,403,403,423,423,443,443,444,443,443};
 for(int i=0;i<ArraySize(carry);i++){string name="TradePilot_"+carry[i];if(ObjectFind(0,name)<0)continue;ObjectSetInteger(0,name,OBJPROP_YDISTANCE,PanelY()+S(carry_rows[i]));if(carry[i]=="CARRY_BORDER")ObjectSetInteger(0,name,OBJPROP_YSIZE,S(108));}
}

#endif
